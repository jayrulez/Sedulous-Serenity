namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Manages the clustered lighting grid.
/// Subdivides the view frustum into 16x9x24 clusters for efficient light culling.
class ClusterGrid
{

	private IDevice mDevice;

	// Static GPU buffers (not updated per-frame)
	private IBuffer mClusterAABBBuffer ~ delete _;     // ClusterAABB[CLUSTER_COUNT]

	// Per-frame GPU buffers (to avoid GPU/CPU synchronization issues)
	private IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] mLightGridBuffers ~ { for (let b in _) delete b; };
	private IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] mLightIndexBuffers ~ { for (let b in _) delete b; };
	private IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] mLightBuffers ~ { for (let b in _) delete b; };
	private IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] mLightingUniformBuffers ~ { for (let b in _) delete b; };

	// CPU-side data for uploading
	private GPUClusteredLight[] mCpuLights ~ delete _;
	private LightGridEntry[] mCpuLightGrid ~ delete _;
	private uint32[] mCpuLightIndices ~ delete _;
	private ClusterAABB[] mCpuClusterAABBs ~ delete _;

	// Current light count
	private int32 mLightCount = 0;

	// Cached screen dimensions
	private uint32 mScreenWidth = 1920;
	private uint32 mScreenHeight = 1080;
	private float mNearPlane = 0.1f;
	private float mFarPlane = 1000.0f;

	public this(IDevice device)
	{
		mDevice = device;
		AllocateCpuData();
		CreateGpuBuffers();
	}

	private void AllocateCpuData()
	{
		mCpuLights = new GPUClusteredLight[ClusterConstants.MAX_LIGHTS];
		mCpuLightGrid = new LightGridEntry[ClusterConstants.CLUSTER_COUNT];
		mCpuLightIndices = new uint32[ClusterConstants.CLUSTER_COUNT * ClusterConstants.MAX_LIGHTS_PER_CLUSTER];
		mCpuClusterAABBs = new ClusterAABB[ClusterConstants.CLUSTER_COUNT];
	}

	private void CreateGpuBuffers()
	{
		// Cluster AABB buffer - static, only updated when camera parameters change significantly
		BufferDescriptor clusterAABBDesc = .((uint64)(sizeof(ClusterAABB) * ClusterConstants.CLUSTER_COUNT), .Storage, .Upload);
		if (mDevice.CreateBuffer(&clusterAABBDesc) case .Ok(let aabbBuf))
			mClusterAABBBuffer = aabbBuf;

		// Create per-frame buffers for data that changes every frame
		for (int i = 0; i < FrameConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			// Light grid buffer - stores offset/count per cluster
			BufferDescriptor lightGridDesc = .((uint64)(sizeof(LightGridEntry) * ClusterConstants.CLUSTER_COUNT), .Storage, .Upload);
			if (mDevice.CreateBuffer(&lightGridDesc) case .Ok(let gridBuf))
				mLightGridBuffers[i] = gridBuf;

			// Light index buffer - stores light indices per cluster
			BufferDescriptor lightIndexDesc = .((uint64)(sizeof(uint32) * ClusterConstants.CLUSTER_COUNT * ClusterConstants.MAX_LIGHTS_PER_CLUSTER), .Storage, .Upload);
			if (mDevice.CreateBuffer(&lightIndexDesc) case .Ok(let indexBuf))
				mLightIndexBuffers[i] = indexBuf;

			// Light buffer - stores all light data
			BufferDescriptor lightDesc = .((uint64)(sizeof(GPUClusteredLight) * ClusterConstants.MAX_LIGHTS), .Storage, .Upload);
			if (mDevice.CreateBuffer(&lightDesc) case .Ok(let lightBuf))
				mLightBuffers[i] = lightBuf;

			// Lighting uniforms buffer
			BufferDescriptor uniformDesc = .((uint64)sizeof(LightingUniforms), .Uniform, .Upload);
			if (mDevice.CreateBuffer(&uniformDesc) case .Ok(let uniformBuf))
				mLightingUniformBuffers[i] = uniformBuf;
		}
	}

	/// Updates the cluster grid for a new camera.
	public void UpdateClusters(CameraProxy* camera)
	{
		if (camera == null)
			return;

		mScreenWidth = camera.ViewportWidth;
		mScreenHeight = camera.ViewportHeight;
		mNearPlane = camera.NearPlane;
		mFarPlane = camera.FarPlane;

		// Build cluster AABBs on CPU (could be moved to compute shader)
		BuildClusterAABBs(camera.FieldOfView, camera.AspectRatio);

		// Upload to GPU
		UploadClusterAABBs();
	}

	/// Updates the cluster grid for a render view.
	public void UpdateClustersFromView(RenderView* view)
	{
		if (view == null)
			return;

		mScreenWidth = view.ViewportWidth;
		mScreenHeight = view.ViewportHeight;
		mNearPlane = view.NearPlane;
		mFarPlane = view.FarPlane;

		// Build cluster AABBs on CPU (could be moved to compute shader)
		BuildClusterAABBs(view.FieldOfView, view.AspectRatio);

		// Upload to GPU
		UploadClusterAABBs();
	}

	/// Assigns lights to clusters for the specified frame.
	public void CullLights(List<LightProxy*> lights, CameraProxy* camera, int32 frameIndex)
	{
		if (camera == null || frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return;

		CullLightsInternal(lights, camera.ViewMatrix, frameIndex);
	}

	/// Assigns lights to clusters for the specified frame using a render view.
	public void CullLightsFromView(List<LightProxy*> lights, RenderView* view, int32 frameIndex)
	{
		if (view == null || frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return;

		CullLightsInternal(lights, view.ViewMatrix, frameIndex);
	}

	/// Internal implementation for light culling.
	private void CullLightsInternal(List<LightProxy*> lights, Matrix viewMatrix, int32 frameIndex)
	{
		// Reset light grid
		for (int i = 0; i < ClusterConstants.CLUSTER_COUNT; i++)
		{
			mCpuLightGrid[i] = .() { Offset = 0, Count = 0, _pad0 = 0, _pad1 = 0 };
		}

		// Clear light indices
		for (int i = 0; i < mCpuLightIndices.Count; i++)
			mCpuLightIndices[i] = 0;

		// Copy lights to CPU buffer
		mLightCount = Math.Min((int32)lights.Count, ClusterConstants.MAX_LIGHTS);
		for (int i = 0; i < mLightCount; i++)
		{
			mCpuLights[i] = GPUClusteredLight.FromProxy(lights[i]);
		}

		// Assign lights to clusters (CPU implementation)
		AssignLightsToClustersInternal(lights, viewMatrix);

		// Upload to GPU
		UploadLightData(frameIndex);
	}

	/// Updates the lighting uniform buffer for the specified frame.
	public void UpdateUniforms(CameraProxy* camera, LightProxy* directionalLight, int32 frameIndex)
	{
		if (frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return;

		if (camera != null)
		{
			Matrix inverseProj = Matrix.Invert(camera.ProjectionMatrix);
			UpdateUniformsInternal(camera.ViewMatrix, inverseProj, directionalLight, frameIndex);
		}
		else
		{
			UpdateUniformsInternal(.Identity, .Identity, directionalLight, frameIndex);
		}
	}

	/// Updates the lighting uniform buffer for the specified frame using a render view.
	public void UpdateUniformsFromView(RenderView* view, LightProxy* directionalLight, int32 frameIndex)
	{
		if (frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return;

		if (view != null)
		{
			Matrix inverseProj = Matrix.Invert(view.ProjectionMatrix);
			UpdateUniformsInternal(view.ViewMatrix, inverseProj, directionalLight, frameIndex);
		}
		else
		{
			UpdateUniformsInternal(.Identity, .Identity, directionalLight, frameIndex);
		}
	}

	/// Internal implementation for updating uniforms.
	private void UpdateUniformsInternal(Matrix viewMatrix, Matrix inverseProjection, LightProxy* directionalLight, int32 frameIndex)
	{
		var uniforms = LightingUniforms.Default;

		uniforms.ViewMatrix = viewMatrix;
		uniforms.InverseProjection = inverseProjection;
		uniforms.ScreenParams = .((float)mScreenWidth, (float)mScreenHeight,
			(float)(mScreenWidth / ClusterConstants.CLUSTER_TILES_X),
			(float)(mScreenHeight / ClusterConstants.CLUSTER_TILES_Y));
		uniforms.ClusterParams = .(mNearPlane, mFarPlane,
			ComputeClusterDepthScale(), ComputeClusterDepthBias());

		if (directionalLight != null && directionalLight.Type == .Directional)
		{
			uniforms.DirectionalDir = .(
				directionalLight.Direction.X,
				directionalLight.Direction.Y,
				directionalLight.Direction.Z,
				directionalLight.Intensity
			);
			uniforms.DirectionalColor = .(
				directionalLight.Color.X,
				directionalLight.Color.Y,
				directionalLight.Color.Z,
				(float)directionalLight.ShadowMapIndex
			);
		}

		uniforms.LightCount = (uint32)mLightCount;

		// Upload to per-frame buffer
		if (mLightingUniformBuffers[frameIndex] != null)
		{
			Span<uint8> data = .((uint8*)&uniforms, sizeof(LightingUniforms));
			mDevice.Queue.WriteBuffer(mLightingUniformBuffers[frameIndex], 0, data);
		}
	}

	/// Gets the cluster AABB buffer for binding.
	public IBuffer ClusterAABBBuffer => mClusterAABBBuffer;

	/// Gets the light grid buffer for binding for the specified frame.
	public IBuffer GetLightGridBuffer(int32 frameIndex)
	{
		if (frameIndex >= 0 && frameIndex < FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return mLightGridBuffers[frameIndex];
		return null;
	}

	/// Gets the light index buffer for binding for the specified frame.
	public IBuffer GetLightIndexBuffer(int32 frameIndex)
	{
		if (frameIndex >= 0 && frameIndex < FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return mLightIndexBuffers[frameIndex];
		return null;
	}

	/// Gets the light buffer for binding for the specified frame.
	public IBuffer GetLightBuffer(int32 frameIndex)
	{
		if (frameIndex >= 0 && frameIndex < FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return mLightBuffers[frameIndex];
		return null;
	}

	/// Gets the lighting uniform buffer for binding for the specified frame.
	public IBuffer GetLightingUniformBuffer(int32 frameIndex)
	{
		if (frameIndex >= 0 && frameIndex < FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return mLightingUniformBuffers[frameIndex];
		return null;
	}

	/// Gets the current light count.
	public int32 LightCount => mLightCount;

	// ==================== Internal Implementation ====================

	/// Builds cluster AABBs in view space.
	private void BuildClusterAABBs(float fieldOfView, float aspectRatio)
	{
		float tileWidth = (float)mScreenWidth / ClusterConstants.CLUSTER_TILES_X;
		float tileHeight = (float)mScreenHeight / ClusterConstants.CLUSTER_TILES_Y;

		// Use logarithmic depth slicing for better near-plane precision
		float logRatio = Math.Log(mFarPlane / mNearPlane);

		for (int z = 0; z < ClusterConstants.CLUSTER_DEPTH_SLICES; z++)
		{
			// Logarithmic depth slice boundaries
			float nearSlice = mNearPlane * Math.Exp(logRatio * (float)z / ClusterConstants.CLUSTER_DEPTH_SLICES);
			float farSlice = mNearPlane * Math.Exp(logRatio * (float)(z + 1) / ClusterConstants.CLUSTER_DEPTH_SLICES);

			for (int y = 0; y < ClusterConstants.CLUSTER_TILES_Y; y++)
			{
				for (int x = 0; x < ClusterConstants.CLUSTER_TILES_X; x++)
				{
					int clusterIndex = x + y * ClusterConstants.CLUSTER_TILES_X +
						z * ClusterConstants.CLUSTER_TILES_X * ClusterConstants.CLUSTER_TILES_Y;

					// Screen-space tile bounds
					float minX = x * tileWidth;
					float maxX = (x + 1) * tileWidth;
					float minY = y * tileHeight;
					float maxY = (y + 1) * tileHeight;

					// Convert to NDC (-1 to 1)
					float ndcMinX = (minX / mScreenWidth) * 2.0f - 1.0f;
					float ndcMaxX = (maxX / mScreenWidth) * 2.0f - 1.0f;
					float ndcMinY = (minY / mScreenHeight) * 2.0f - 1.0f;
					float ndcMaxY = (maxY / mScreenHeight) * 2.0f - 1.0f;

					// Compute frustum corners in view space
					var aabb = ComputeClusterAABB(fieldOfView, aspectRatio, ndcMinX, ndcMaxX, ndcMinY, ndcMaxY, nearSlice, farSlice);
					mCpuClusterAABBs[clusterIndex] = aabb;
				}
			}
		}
	}

	/// Computes AABB for a single cluster in view space.
	private ClusterAABB ComputeClusterAABB(float fieldOfView, float aspectRatio, float ndcMinX, float ndcMaxX,
		float ndcMinY, float ndcMaxY, float nearZ, float farZ)
	{
		// Compute the 8 corners of the cluster frustum in view space
		Vector3[8] corners = .();

		// Near plane corners (in view space, Z is negative)
		corners[0] = ScreenToViewSpace(fieldOfView, aspectRatio, ndcMinX, ndcMinY, nearZ);
		corners[1] = ScreenToViewSpace(fieldOfView, aspectRatio, ndcMaxX, ndcMinY, nearZ);
		corners[2] = ScreenToViewSpace(fieldOfView, aspectRatio, ndcMinX, ndcMaxY, nearZ);
		corners[3] = ScreenToViewSpace(fieldOfView, aspectRatio, ndcMaxX, ndcMaxY, nearZ);

		// Far plane corners
		corners[4] = ScreenToViewSpace(fieldOfView, aspectRatio, ndcMinX, ndcMinY, farZ);
		corners[5] = ScreenToViewSpace(fieldOfView, aspectRatio, ndcMaxX, ndcMinY, farZ);
		corners[6] = ScreenToViewSpace(fieldOfView, aspectRatio, ndcMinX, ndcMaxY, farZ);
		corners[7] = ScreenToViewSpace(fieldOfView, aspectRatio, ndcMaxX, ndcMaxY, farZ);

		// Find AABB
		Vector3 minPoint = corners[0];
		Vector3 maxPoint = corners[0];

		for (int i = 1; i < 8; i++)
		{
			minPoint = Vector3.Min(minPoint, corners[i]);
			maxPoint = Vector3.Max(maxPoint, corners[i]);
		}

		return .()
		{
			MinPoint = .(minPoint.X, minPoint.Y, minPoint.Z, 1.0f),
			MaxPoint = .(maxPoint.X, maxPoint.Y, maxPoint.Z, 1.0f)
		};
	}

	/// Converts NDC coordinates to view space at a given depth.
	private Vector3 ScreenToViewSpace(float fieldOfView, float aspectRatio, float ndcX, float ndcY, float viewZ)
	{
		// Using perspective projection properties
		float tanHalfFov = Math.Tan(fieldOfView * 0.5f);

		// At depth viewZ in view space
		float x = ndcX * viewZ * tanHalfFov * aspectRatio;
		float y = ndcY * viewZ * tanHalfFov;

		return .(x, y, -viewZ); // View space Z is negative
	}

	/// Assigns lights to clusters using AABB intersection tests.
	private void AssignLightsToClustersInternal(List<LightProxy*> lights, Matrix viewMatrix)
	{
		// Use a simple approach: for each light, find all clusters it affects
		// This is O(lights * clusters) but works well for moderate counts

		// Track current offset into light index buffer
		uint32 currentOffset = 0;

		for (int clusterIdx = 0; clusterIdx < ClusterConstants.CLUSTER_COUNT; clusterIdx++)
		{
			let clusterAABB = mCpuClusterAABBs[clusterIdx];
			var clusterBounds = BoundingBox(
				.(clusterAABB.MinPoint.X, clusterAABB.MinPoint.Y, clusterAABB.MinPoint.Z),
				.(clusterAABB.MaxPoint.X, clusterAABB.MaxPoint.Y, clusterAABB.MaxPoint.Z)
			);

			mCpuLightGrid[clusterIdx].Offset = currentOffset;
			uint32 lightCount = 0;

			for (int lightIdx = 0; lightIdx < mLightCount && lightCount < ClusterConstants.MAX_LIGHTS_PER_CLUSTER; lightIdx++)
			{
				let light = lights[lightIdx];

				// Transform light to view space for intersection test
				Vector3 lightPosView = TransformToViewSpace(viewMatrix, light.Position);

				if (LightIntersectsCluster(light, lightPosView, clusterBounds))
				{
					mCpuLightIndices[currentOffset + lightCount] = (uint32)lightIdx;
					lightCount++;
				}
			}

			mCpuLightGrid[clusterIdx].Count = lightCount;
			currentOffset += lightCount;
		}
	}

	/// Transforms a world-space position to view space.
	private Vector3 TransformToViewSpace(Matrix viewMatrix, Vector3 worldPos)
	{
		Vector4 pos4 = .(worldPos.X, worldPos.Y, worldPos.Z, 1.0f);
		Vector4 viewPos = Vector4.Transform(pos4, viewMatrix);
		return .(viewPos.X, viewPos.Y, viewPos.Z);
	}

	/// Tests if a light intersects a cluster AABB (both in view space).
	private bool LightIntersectsCluster(LightProxy* light, Vector3 lightPosView, BoundingBox clusterBounds)
	{
		if (light.Type == .Directional)
			return true; // Directional lights affect all clusters

		// Sphere-AABB intersection for point/spot lights
		float range = light.Range;
		let center = (clusterBounds.Min + clusterBounds.Max) * 0.5f;
		let extents = (clusterBounds.Max - clusterBounds.Min) * 0.5f;

		// Find closest point on AABB to sphere center
		float dx = Math.Max(0.0f, Math.Abs(lightPosView.X - center.X) - extents.X);
		float dy = Math.Max(0.0f, Math.Abs(lightPosView.Y - center.Y) - extents.Y);
		float dz = Math.Max(0.0f, Math.Abs(lightPosView.Z - center.Z) - extents.Z);

		float distSq = dx * dx + dy * dy + dz * dz;
		return distSq <= range * range;
	}

	/// Computes the scale factor for logarithmic depth slicing.
	private float ComputeClusterDepthScale()
	{
		return (float)ClusterConstants.CLUSTER_DEPTH_SLICES / Math.Log(mFarPlane / mNearPlane);
	}

	/// Computes the bias factor for logarithmic depth slicing.
	private float ComputeClusterDepthBias()
	{
		return -((float)ClusterConstants.CLUSTER_DEPTH_SLICES * Math.Log(mNearPlane)) / Math.Log(mFarPlane / mNearPlane);
	}

	// ==================== GPU Upload ====================

	private void UploadClusterAABBs()
	{
		if (mClusterAABBBuffer != null)
		{
			Span<uint8> data = .((uint8*)mCpuClusterAABBs.Ptr, sizeof(ClusterAABB) * ClusterConstants.CLUSTER_COUNT);
			mDevice.Queue.WriteBuffer(mClusterAABBBuffer, 0, data);
		}
	}

	private void UploadLightData(int32 frameIndex)
	{
		if (frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return;

		// Upload lights
		if (mLightBuffers[frameIndex] != null && mLightCount > 0)
		{
			Span<uint8> data = .((uint8*)mCpuLights.Ptr, sizeof(GPUClusteredLight) * mLightCount);
			mDevice.Queue.WriteBuffer(mLightBuffers[frameIndex], 0, data);
		}

		// Upload light grid
		if (mLightGridBuffers[frameIndex] != null)
		{
			Span<uint8> data = .((uint8*)mCpuLightGrid.Ptr, sizeof(LightGridEntry) * ClusterConstants.CLUSTER_COUNT);
			mDevice.Queue.WriteBuffer(mLightGridBuffers[frameIndex], 0, data);
		}

		// Upload light indices (only used portion)
		uint32 totalIndices = 0;
		for (int i = 0; i < ClusterConstants.CLUSTER_COUNT; i++)
			totalIndices += mCpuLightGrid[i].Count;

		if (mLightIndexBuffers[frameIndex] != null && totalIndices > 0)
		{
			Span<uint8> data = .((uint8*)mCpuLightIndices.Ptr, (int)(sizeof(uint32) * totalIndices));
			mDevice.Queue.WriteBuffer(mLightIndexBuffers[frameIndex], 0, data);
		}
	}
}

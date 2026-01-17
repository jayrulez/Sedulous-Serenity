namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shaders;

/// Configuration for the cluster grid.
public struct ClusterGridConfig
{
	/// Number of clusters in X (screen width).
	public uint32 ClustersX;

	/// Number of clusters in Y (screen height).
	public uint32 ClustersY;

	/// Number of clusters in Z (depth slices).
	public uint32 ClustersZ;

	/// Maximum lights per cluster.
	public uint32 MaxLightsPerCluster;

	/// Creates default configuration (16x9x24 grid).
	public static Self Default => .()
	{
		ClustersX = 16,
		ClustersY = 9,
		ClustersZ = 24,
		MaxLightsPerCluster = 256
	};

	/// Total number of clusters.
	public uint32 TotalClusters => ClustersX * ClustersY * ClustersZ;
}

/// GPU data for a single cluster (light list info).
[CRepr]
public struct ClusterLightInfo
{
	/// Offset into the global light index list.
	public uint32 Offset;

	/// Number of lights affecting this cluster.
	public uint32 Count;
}

/// GPU uniform buffer for cluster grid parameters.
[CRepr]
public struct ClusterUniforms
{
	/// Cluster grid dimensions (x, y, z).
	public uint32 ClustersX;
	public uint32 ClustersY;
	public uint32 ClustersZ;
	public uint32 Padding0;

	/// Screen dimensions.
	public float ScreenWidth;
	public float ScreenHeight;

	/// Near and far planes.
	public float NearPlane;
	public float FarPlane;

	/// Logarithmic depth scale factor.
	public float LogDepthScale;

	/// Bias for logarithmic depth.
	public float LogDepthBias;

	/// Tile size in pixels.
	public float TileSizeX;
	public float TileSizeY;

	/// Size of this struct in bytes.
	public static int Size => 48;
}

/// Manages the cluster grid for clustered forward lighting.
/// Divides the view frustum into a 3D grid of clusters.
public class ClusterGrid : IDisposable
{
	// Configuration
	private ClusterGridConfig mConfig;
	private float mNearPlane;
	private float mFarPlane;
	private uint32 mScreenWidth;
	private uint32 mScreenHeight;

	// GPU resources
	private IDevice mDevice;
	private IBuffer mClusterAABBBuffer;      // AABB for each cluster (computed once per resize)
	private IBuffer mClusterLightInfoBuffer; // Per-cluster light offset/count
	private IBuffer mLightIndexBuffer;       // Global list of light indices
	private IBuffer mClusterUniformBuffer;   // Cluster parameters

	// Compute pipelines
	private IComputePipeline mBuildClustersPipeline ~ delete _;
	private IComputePipeline mCullLightsPipeline ~ delete _;

	// Bind group layouts
	private IBindGroupLayout mBuildClustersBindGroupLayout ~ delete _;
	private IBindGroupLayout mCullLightsBindGroupLayout ~ delete _;

	// Bind groups
	private IBindGroup mBuildClustersBindGroup ~ delete _;
	private IBindGroup mCullLightsBindGroup ~ delete _;

	// Pipeline layouts
	private IPipelineLayout mBuildClustersPipelineLayout ~ delete _;
	private IPipelineLayout mCullLightsPipelineLayout ~ delete _;

	// Counter buffer for atomic allocation
	private IBuffer mLightIndexCounterBuffer ~ delete _;

	// Whether GPU culling is available
	private bool mGPUCullingAvailable = false;

	// CPU-side cluster data (for debugging/fallback)
	private BoundingBox[] mClusterAABBs ~ delete _;

	// Statistics
	private ClusterStats mStats;

	/// Gets the cluster grid configuration.
	public ClusterGridConfig Config => mConfig;

	/// Gets cluster statistics.
	public ClusterStats Stats => mStats;

	/// Whether the cluster grid has been initialized.
	public bool IsInitialized => mDevice != null && mClusterAABBBuffer != null;

	/// Gets the cluster uniform buffer.
	public IBuffer UniformBuffer => mClusterUniformBuffer;

	/// Gets the cluster light info buffer (per-cluster offset/count).
	public IBuffer ClusterLightInfoBuffer => mClusterLightInfoBuffer;

	/// Gets the light index buffer (global light indices).
	public IBuffer LightIndexBuffer => mLightIndexBuffer;

	/// Whether GPU light culling is available.
	public bool GPUCullingAvailable => mGPUCullingAvailable;

	// Shader system reference (not owned)
	private NewShaderSystem mShaderSystem;

	/// Initializes the cluster grid.
	public Result<void> Initialize(IDevice device, ClusterGridConfig config = .Default, NewShaderSystem shaderSystem = null)
	{
		mDevice = device;
		mConfig = config;
		mShaderSystem = shaderSystem;

		// Create GPU buffers
		if (CreateBuffers() case .Err)
			return .Err;

		// Create compute pipelines (non-fatal if shaders unavailable)
		CreateComputePipelines();

		return .Ok;
	}

	/// Updates the cluster grid for new view parameters.
	public Result<void> Update(uint32 screenWidth, uint32 screenHeight, float nearPlane, float farPlane, Matrix inverseProjection)
	{
		bool needsRebuild = mScreenWidth != screenWidth ||
							mScreenHeight != screenHeight ||
							mNearPlane != nearPlane ||
							mFarPlane != farPlane;

		mScreenWidth = screenWidth;
		mScreenHeight = screenHeight;
		mNearPlane = nearPlane;
		mFarPlane = farPlane;

		if (needsRebuild)
		{
			// Rebuild cluster AABBs on CPU (could also be done on GPU)
			BuildClusterAABBs(inverseProjection);

			// Update uniform buffer
			UpdateUniforms();
		}

		return .Ok;
	}

	/// Performs light culling against the cluster grid using GPU compute.
	/// This assigns lights to clusters based on their bounding volumes.
	public void CullLights(IComputePassEncoder encoder, LightBuffer lightBuffer)
	{
		if (!IsInitialized || !mGPUCullingAvailable)
			return;

		if (mCullLightsPipeline == null || mCullLightsBindGroup == null)
			return;

		// Reset counter buffer
		uint32[1] zero = .(0);
		mDevice.Queue.WriteBuffer(mLightIndexCounterBuffer, 0, Span<uint8>((uint8*)&zero[0], 4));

		// Set pipeline and bind group
		encoder.SetPipeline(mCullLightsPipeline);
		encoder.SetBindGroup(0, mCullLightsBindGroup, default);

		// Dispatch one workgroup per cluster
		// Using 1x1x1 threads per group, dispatch ClustersX * ClustersY * ClustersZ groups
		encoder.Dispatch(mConfig.ClustersX, mConfig.ClustersY, mConfig.ClustersZ);

		// Update stats (would need readback for accurate counts)
		mStats.ClustersWithLights = (int32)mConfig.TotalClusters; // Estimate
		mStats.AverageLightsPerCluster = (float)lightBuffer.LightCount / (float)Math.Max(1, mStats.ClustersWithLights);
	}

	/// Builds cluster AABBs using GPU compute.
	public void BuildClustersGPU(IComputePassEncoder encoder)
	{
		if (!IsInitialized || !mGPUCullingAvailable)
			return;

		if (mBuildClustersPipeline == null || mBuildClustersBindGroup == null)
			return;

		// Set pipeline and bind group
		encoder.SetPipeline(mBuildClustersPipeline);
		encoder.SetBindGroup(0, mBuildClustersBindGroup, default);

		// Dispatch with 8x8x1 threads per workgroup
		let groupsX = (mConfig.ClustersX + 7) / 8;
		let groupsY = (mConfig.ClustersY + 7) / 8;
		let groupsZ = mConfig.ClustersZ;

		encoder.Dispatch(groupsX, groupsY, groupsZ);
	}

	/// CPU fallback for light culling (for debugging or when compute is unavailable).
	public void CullLightsCPU(RenderWorld world, VisibilityResolver visibility)
	{
		if (mClusterAABBs == null)
			return;

		mStats.ClustersWithLights = 0;
		int totalLights = 0;

		// For each cluster, test against visible lights
		for (int i = 0; i < mClusterAABBs.Count; i++)
		{
			let clusterAABB = mClusterAABBs[i];
			int lightsInCluster = 0;

			for (let visibleLight in visibility.VisibleLights)
			{
				if (let light = world.GetLight(visibleLight.Handle))
				{
					if (LightIntersectsCluster(light, clusterAABB))
						lightsInCluster++;
				}
			}

			if (lightsInCluster > 0)
			{
				mStats.ClustersWithLights++;
				totalLights += lightsInCluster;
			}
		}

		mStats.AverageLightsPerCluster = mStats.ClustersWithLights > 0
			? (float)totalLights / (float)mStats.ClustersWithLights
			: 0;
	}

	public void Dispose()
	{
		// Buffers
		if (mClusterAABBBuffer != null) { delete mClusterAABBBuffer; mClusterAABBBuffer = null; }
		if (mClusterLightInfoBuffer != null) { delete mClusterLightInfoBuffer; mClusterLightInfoBuffer = null; }
		if (mLightIndexBuffer != null) { delete mLightIndexBuffer; mLightIndexBuffer = null; }
		if (mClusterUniformBuffer != null) { delete mClusterUniformBuffer; mClusterUniformBuffer = null; }
		if (mLightIndexCounterBuffer != null) { delete mLightIndexCounterBuffer; mLightIndexCounterBuffer = null; }

		// Bind groups
		if (mBuildClustersBindGroup != null) { delete mBuildClustersBindGroup; mBuildClustersBindGroup = null; }
		if (mCullLightsBindGroup != null) { delete mCullLightsBindGroup; mCullLightsBindGroup = null; }

		// Pipelines
		if (mBuildClustersPipeline != null) { delete mBuildClustersPipeline; mBuildClustersPipeline = null; }
		if (mCullLightsPipeline != null) { delete mCullLightsPipeline; mCullLightsPipeline = null; }

		// Pipeline layouts
		if (mBuildClustersPipelineLayout != null) { delete mBuildClustersPipelineLayout; mBuildClustersPipelineLayout = null; }
		if (mCullLightsPipelineLayout != null) { delete mCullLightsPipelineLayout; mCullLightsPipelineLayout = null; }

		// Bind group layouts
		if (mBuildClustersBindGroupLayout != null) { delete mBuildClustersBindGroupLayout; mBuildClustersBindGroupLayout = null; }
		if (mCullLightsBindGroupLayout != null) { delete mCullLightsBindGroupLayout; mCullLightsBindGroupLayout = null; }

		mGPUCullingAvailable = false;
	}

	private Result<void> CreateBuffers()
	{
		let totalClusters = mConfig.TotalClusters;

		// Cluster AABB buffer: 6 floats per cluster (min xyz, max xyz)
		BufferDescriptor aabbDesc = .()
		{
			Label = "Cluster AABBs",
			Size = totalClusters * 24,
			Usage = .Storage | .CopyDst
		};

		switch (mDevice.CreateBuffer(&aabbDesc))
		{
		case .Ok(let buf): mClusterAABBBuffer = buf;
		case .Err: return .Err;
		}

		// Cluster light info buffer: 2 uint32s per cluster (offset, count)
		BufferDescriptor infoDesc = .()
		{
			Label = "Cluster Light Info",
			Size = totalClusters * 8,
			Usage = .Storage
		};

		switch (mDevice.CreateBuffer(&infoDesc))
		{
		case .Ok(let buf): mClusterLightInfoBuffer = buf;
		case .Err: return .Err;
		}

		// Light index buffer: maxLightsPerCluster * totalClusters indices
		// In practice, we use a more compact representation
		let maxIndices = mConfig.MaxLightsPerCluster * totalClusters;
		BufferDescriptor indexDesc = .()
		{
			Label = "Light Indices",
			Size = maxIndices * 4,
			Usage = .Storage
		};

		switch (mDevice.CreateBuffer(&indexDesc))
		{
		case .Ok(let buf): mLightIndexBuffer = buf;
		case .Err: return .Err;
		}

		// Cluster uniform buffer
		BufferDescriptor uniformDesc = .()
		{
			Label = "Cluster Uniforms",
			Size = (uint64)ClusterUniforms.Size,
			Usage = .Uniform | .CopyDst
		};

		switch (mDevice.CreateBuffer(&uniformDesc))
		{
		case .Ok(let buf): mClusterUniformBuffer = buf;
		case .Err: return .Err;
		}

		// Allocate CPU-side AABB storage
		mClusterAABBs = new BoundingBox[totalClusters];

		// Light index counter buffer (for atomic allocation)
		BufferDescriptor counterDesc = .()
		{
			Label = "Light Index Counter",
			Size = 4, // Single uint32
			Usage = .Storage | .CopyDst
		};

		switch (mDevice.CreateBuffer(&counterDesc))
		{
		case .Ok(let buf): mLightIndexCounterBuffer = buf;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private void CreateComputePipelines()
	{
		// Skip if shader system not available
		if (mShaderSystem == null)
			return;

		// Create bind group layout for cluster building
		BindGroupLayoutEntry[2] buildEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer }, // ClusterUniforms
			.() { Binding = 1, Visibility = .Compute, Type = .StorageBuffer }  // ClusterAABBs (output)
		);

		BindGroupLayoutDescriptor buildLayoutDesc = .()
		{
			Label = "Cluster Build BindGroup Layout",
			Entries = buildEntries
		};

		switch (mDevice.CreateBindGroupLayout(&buildLayoutDesc))
		{
		case .Ok(let layout): mBuildClustersBindGroupLayout = layout;
		case .Err: return;
		}

		// Create bind group layout for light culling
		BindGroupLayoutEntry[6] cullEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer },  // ClusterUniforms
			.() { Binding = 1, Visibility = .Compute, Type = .UniformBuffer },  // LightingUniforms
			.() { Binding = 2, Visibility = .Compute, Type = .StorageBuffer },  // ClusterAABBs (input)
			.() { Binding = 3, Visibility = .Compute, Type = .StorageBuffer },  // Lights (input)
			.() { Binding = 4, Visibility = .Compute, Type = .StorageBuffer },  // ClusterLightInfos (output)
			.() { Binding = 5, Visibility = .Compute, Type = .StorageBuffer }   // LightIndices (output)
		);

		BindGroupLayoutDescriptor cullLayoutDesc = .()
		{
			Label = "Cluster Cull BindGroup Layout",
			Entries = cullEntries
		};

		switch (mDevice.CreateBindGroupLayout(&cullLayoutDesc))
		{
		case .Ok(let layout): mCullLightsBindGroupLayout = layout;
		case .Err: return;
		}

		// Create pipeline layouts
		IBindGroupLayout[1] buildLayouts = .(mBuildClustersBindGroupLayout);
		PipelineLayoutDescriptor buildPlDesc = .(buildLayouts);
		switch (mDevice.CreatePipelineLayout(&buildPlDesc))
		{
		case .Ok(let layout): mBuildClustersPipelineLayout = layout;
		case .Err: return;
		}

		IBindGroupLayout[1] cullLayouts = .(mCullLightsBindGroupLayout);
		PipelineLayoutDescriptor cullPlDesc = .(cullLayouts);
		switch (mDevice.CreatePipelineLayout(&cullPlDesc))
		{
		case .Ok(let layout): mCullLightsPipelineLayout = layout;
		case .Err: return;
		}

		// Load cluster build shader
		if (mShaderSystem.GetShader("cluster_build", .Compute) case .Ok(let buildShader))
		{
			ComputePipelineDescriptor buildPipelineDesc = .(mBuildClustersPipelineLayout, buildShader.Module);
			buildPipelineDesc.Label = "Cluster Build Pipeline";

			switch (mDevice.CreateComputePipeline(&buildPipelineDesc))
			{
			case .Ok(let pipeline): mBuildClustersPipeline = pipeline;
			case .Err:
			}
		}

		// Load cluster cull shader
		if (mShaderSystem.GetShader("cluster_cull", .Compute) case .Ok(let cullShader))
		{
			ComputePipelineDescriptor cullPipelineDesc = .(mCullLightsPipelineLayout, cullShader.Module);
			cullPipelineDesc.Label = "Cluster Cull Pipeline";

			switch (mDevice.CreateComputePipeline(&cullPipelineDesc))
			{
			case .Ok(let pipeline): mCullLightsPipeline = pipeline;
			case .Err:
			}
		}

		mGPUCullingAvailable = mBuildClustersPipeline != null && mCullLightsPipeline != null;
	}

	/// Creates bind groups for GPU culling (call after light buffer is ready).
	public void CreateBindGroups(LightBuffer lightBuffer)
	{
		if (!mGPUCullingAvailable || lightBuffer == null)
			return;

		// Create build clusters bind group
		if (mBuildClustersBindGroupLayout != null && mBuildClustersBindGroup == null)
		{
			BindGroupEntry[2] buildEntries = .(
				BindGroupEntry.Buffer(0, mClusterUniformBuffer, 0, (uint64)ClusterUniforms.Size),
				BindGroupEntry.Buffer(1, mClusterAABBBuffer, 0, mConfig.TotalClusters * 24)
			);

			BindGroupDescriptor buildDesc = .(mBuildClustersBindGroupLayout, buildEntries);
			buildDesc.Label = "Cluster Build BindGroup";

			switch (mDevice.CreateBindGroup(&buildDesc))
			{
			case .Ok(let bg): mBuildClustersBindGroup = bg;
			case .Err:
			}
		}

		// Create cull lights bind group
		if (mCullLightsBindGroupLayout != null && mCullLightsBindGroup == null)
		{
			BindGroupEntry[6] cullEntries = .(
				BindGroupEntry.Buffer(0, mClusterUniformBuffer, 0, (uint64)ClusterUniforms.Size),
				BindGroupEntry.Buffer(1, lightBuffer.UniformBuffer, 0, (uint64)LightingUniforms.Size),
				BindGroupEntry.Buffer(2, mClusterAABBBuffer, 0, mConfig.TotalClusters * 24),
				BindGroupEntry.Buffer(3, lightBuffer.LightDataBuffer, 0, (uint64)(lightBuffer.MaxLights * GPULight.Size)),
				BindGroupEntry.Buffer(4, mClusterLightInfoBuffer, 0, mConfig.TotalClusters * 8),
				BindGroupEntry.Buffer(5, mLightIndexBuffer, 0, mConfig.MaxLightsPerCluster * mConfig.TotalClusters * 4)
			);

			BindGroupDescriptor cullDesc = .(mCullLightsBindGroupLayout, cullEntries);
			cullDesc.Label = "Cluster Cull BindGroup";

			switch (mDevice.CreateBindGroup(&cullDesc))
			{
			case .Ok(let bg): mCullLightsBindGroup = bg;
			case .Err:
			}
		}
	}

	private void BuildClusterAABBs(Matrix inverseProjection)
	{
		if (mClusterAABBs == null)
			return;

		let tileSizeX = (float)mScreenWidth / (float)mConfig.ClustersX;
		let tileSizeY = (float)mScreenHeight / (float)mConfig.ClustersY;

		// Logarithmic depth slicing parameters
		for (uint32 z = 0; z < mConfig.ClustersZ; z++)
		{
			// Calculate depth slice bounds using logarithmic distribution
			let zNear = mNearPlane * Math.Pow(mFarPlane / mNearPlane, (float)z / (float)mConfig.ClustersZ);
			let zFar = mNearPlane * Math.Pow(mFarPlane / mNearPlane, (float)(z + 1) / (float)mConfig.ClustersZ);

			for (uint32 y = 0; y < mConfig.ClustersY; y++)
			{
				for (uint32 x = 0; x < mConfig.ClustersX; x++)
				{
					// Calculate screen-space tile bounds
					let minX = (float)x * tileSizeX;
					let maxX = (float)(x + 1) * tileSizeX;
					let minY = (float)y * tileSizeY;
					let maxY = (float)(y + 1) * tileSizeY;

					// Convert to NDC (-1 to 1)
					let ndcMinX = (minX / (float)mScreenWidth) * 2.0f - 1.0f;
					let ndcMaxX = (maxX / (float)mScreenWidth) * 2.0f - 1.0f;
					let ndcMinY = (minY / (float)mScreenHeight) * 2.0f - 1.0f;
					let ndcMaxY = (maxY / (float)mScreenHeight) * 2.0f - 1.0f;

					// Build AABB from the 8 corners of the cluster frustum
					let aabb = ComputeClusterAABB(
						ndcMinX, ndcMaxX,
						ndcMinY, ndcMaxY,
						zNear, zFar,
						inverseProjection
					);

					let index = x + y * mConfig.ClustersX + z * mConfig.ClustersX * mConfig.ClustersY;
					mClusterAABBs[index] = aabb;
				}
			}
		}

		mStats.TotalClusters = (int32)mConfig.TotalClusters;
	}

	private BoundingBox ComputeClusterAABB(
		float ndcMinX, float ndcMaxX,
		float ndcMinY, float ndcMaxY,
		float zNear, float zFar,
		Matrix inverseProjection)
	{
		// Transform 8 corners of the cluster from NDC to view space
		Vector3 minBounds = .(float.MaxValue);
		Vector3 maxBounds = .(float.MinValue);

		float[2] xs = .(ndcMinX, ndcMaxX);
		float[2] ys = .(ndcMinY, ndcMaxY);
		float[2] zs = .(zNear, zFar);

		for (let ndcX in xs)
		{
			for (let ndcY in ys)
			{
				for (let viewZ in zs)
				{
					// Convert depth to NDC Z (assuming D3D convention: 0 at near, 1 at far)
					let ndcZ = (viewZ - mNearPlane) / (mFarPlane - mNearPlane);

					// Unproject to view space
					var clipPos = Vector4(ndcX, ndcY, ndcZ, 1.0f);
					var viewPos = Vector4.Transform(clipPos, inverseProjection);
					viewPos /= viewPos.W;

					let viewPos3 = Vector3(viewPos.X, viewPos.Y, viewPos.Z);
					minBounds = Vector3.Min(minBounds, viewPos3);
					maxBounds = Vector3.Max(maxBounds, viewPos3);
				}
			}
		}

		return BoundingBox(minBounds, maxBounds);
	}

	private void UpdateUniforms()
	{
		// Calculate logarithmic depth parameters
		let logDepthScale = (float)mConfig.ClustersZ / Math.Log(mFarPlane / mNearPlane);
		let logDepthBias = -(float)mConfig.ClustersZ * Math.Log(mNearPlane) / Math.Log(mFarPlane / mNearPlane);

		ClusterUniforms uniforms = .()
		{
			ClustersX = mConfig.ClustersX,
			ClustersY = mConfig.ClustersY,
			ClustersZ = mConfig.ClustersZ,
			ScreenWidth = (float)mScreenWidth,
			ScreenHeight = (float)mScreenHeight,
			NearPlane = mNearPlane,
			FarPlane = mFarPlane,
			LogDepthScale = logDepthScale,
			LogDepthBias = logDepthBias,
			TileSizeX = (float)mScreenWidth / (float)mConfig.ClustersX,
			TileSizeY = (float)mScreenHeight / (float)mConfig.ClustersY
		};

		// Upload to GPU
		mDevice.Queue.WriteBuffer(mClusterUniformBuffer, 0, Span<uint8>((uint8*)&uniforms, ClusterUniforms.Size));
	}

	private bool LightIntersectsCluster(LightProxy* light, BoundingBox clusterAABB)
	{
		if (light.Type == .Directional)
			return true; // Directional lights affect all clusters

		// Test sphere-AABB intersection
		let lightSphere = BoundingSphere(light.Position, light.Range);
		return SphereIntersectsAABB(lightSphere, clusterAABB);
	}

	private static bool SphereIntersectsAABB(BoundingSphere sphere, BoundingBox bounds)
	{
		// Find closest point on AABB to sphere center
		let closest = Vector3.Clamp(sphere.Center, bounds.Min, bounds.Max);

		// Check if that point is within the sphere
		let distSq = Vector3.DistanceSquared(sphere.Center, closest);
		return distSq <= sphere.Radius * sphere.Radius;
	}
}

/// Statistics from cluster grid operations.
public struct ClusterStats
{
	/// Total number of clusters in the grid.
	public int32 TotalClusters;

	/// Number of clusters that contain at least one light.
	public int32 ClustersWithLights;

	/// Average number of lights per non-empty cluster.
	public float AverageLightsPerCluster;

	/// Percentage of clusters that are empty.
	public float EmptyClusterPercentage => TotalClusters > 0
		? (float)(TotalClusters - ClustersWithLights) / (float)TotalClusters * 100.0f
		: 0.0f;
}

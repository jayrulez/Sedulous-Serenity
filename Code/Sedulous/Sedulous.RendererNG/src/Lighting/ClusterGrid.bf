namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Represents a 3D cluster in the view frustum.
[CRepr]
struct Cluster
{
	public Vector4 MinBounds; // xyz = min, w = unused
	public Vector4 MaxBounds; // xyz = max, w = unused

	public const uint32 Size = 32;
}

/// Per-cluster light list data for GPU.
[CRepr]
struct ClusterLightData
{
	public uint32 Offset;  // Offset into light index buffer
	public uint32 Count;   // Number of lights in this cluster

	public const uint32 Size = 8;
}

/// Manages a 3D cluster grid for clustered forward lighting.
/// Divides the view frustum into clusters for efficient light culling.
class ClusterGrid : IDisposable
{
	// Grid dimensions
	public readonly uint32 GridSizeX;
	public readonly uint32 GridSizeY;
	public readonly uint32 GridSizeZ;
	public readonly uint32 TotalClusters;

	// Cluster bounds (computed once per view)
	private Cluster[] mClusters ~ delete _;

	// Per-cluster light assignments (rebuilt each frame)
	private ClusterLightData[] mClusterLightData ~ delete _;
	private List<uint32> mLightIndices = new .() ~ delete _;

	// GPU buffers
	private IBuffer mClusterBoundsBuffer ~ delete _;
	private IBuffer mClusterLightDataBuffer ~ delete _;
	private IBuffer mLightIndexBuffer ~ delete _;

	// Configuration
	private float mNearPlane;
	private float mFarPlane;
	private float mLogFarOverNear;

	// Maximum lights per cluster
	public const uint32 MaxLightsPerCluster = 256;
	public const uint32 MaxTotalLightIndices = 65536;

	/// Creates a cluster grid with specified dimensions.
	public this(uint32 gridX = 16, uint32 gridY = 9, uint32 gridZ = 24)
	{
		GridSizeX = gridX;
		GridSizeY = gridY;
		GridSizeZ = gridZ;
		TotalClusters = gridX * gridY * gridZ;

		mClusters = new Cluster[TotalClusters];
		mClusterLightData = new ClusterLightData[TotalClusters];
	}

	/// Initializes GPU buffers.
	public Result<void> Initialize(IDevice device)
	{
		// Create cluster bounds buffer (static, updated when view changes)
		var boundsDesc = BufferDescriptor(TotalClusters * Cluster.Size, .Uniform, .Upload);
		boundsDesc.Label = "ClusterBoundsBuffer";

		switch (device.CreateBuffer(&boundsDesc))
		{
		case .Ok(let buffer):
			mClusterBoundsBuffer = buffer;
		case .Err:
			return .Err;
		}

		// Create cluster light data buffer (per-frame)
		var dataDesc = BufferDescriptor(TotalClusters * ClusterLightData.Size, .Uniform, .Upload);
		dataDesc.Label = "ClusterLightDataBuffer";

		switch (device.CreateBuffer(&dataDesc))
		{
		case .Ok(let buffer):
			mClusterLightDataBuffer = buffer;
		case .Err:
			return .Err;
		}

		// Create light index buffer (per-frame)
		var indexDesc = BufferDescriptor(MaxTotalLightIndices * sizeof(uint32), .Uniform, .Upload);
		indexDesc.Label = "LightIndexBuffer";

		switch (device.CreateBuffer(&indexDesc))
		{
		case .Ok(let buffer):
			mLightIndexBuffer = buffer;
		case .Err:
			return .Err;
		}

		return .Ok;
	}

	/// Computes cluster bounds for the given view parameters.
	/// Call when camera/projection changes.
	public void ComputeClusterBounds(Matrix projection, float nearPlane, float farPlane, uint32 screenWidth, uint32 screenHeight)
	{
		mNearPlane = nearPlane;
		mFarPlane = farPlane;
		mLogFarOverNear = Math.Log(farPlane / nearPlane);

		// Compute inverse projection for screen-to-view transformation
		Matrix.Invert(projection, var invProj);

		float tileSizeX = (float)screenWidth / GridSizeX;
		float tileSizeY = (float)screenHeight / GridSizeY;

		for (uint32 z = 0; z < GridSizeZ; z++)
		{
			// Compute depth slice bounds using logarithmic distribution
			float zNear = GetDepthSliceNear(z);
			float zFar = GetDepthSliceFar(z);

			for (uint32 y = 0; y < GridSizeY; y++)
			{
				for (uint32 x = 0; x < GridSizeX; x++)
				{
					// Screen space tile bounds
					float minX = x * tileSizeX;
					float maxX = (x + 1) * tileSizeX;
					float minY = y * tileSizeY;
					float maxY = (y + 1) * tileSizeY;

					// Convert to NDC [-1, 1]
					float ndcMinX = (minX / screenWidth) * 2.0f - 1.0f;
					float ndcMaxX = (maxX / screenWidth) * 2.0f - 1.0f;
					float ndcMinY = 1.0f - (maxY / screenHeight) * 2.0f; // Y flipped
					float ndcMaxY = 1.0f - (minY / screenHeight) * 2.0f;

					// Compute view space AABB for this cluster
					let clusterIdx = GetClusterIndex(x, y, z);
					ComputeClusterAABB(ref mClusters[clusterIdx],
						ndcMinX, ndcMaxX, ndcMinY, ndcMaxY,
						zNear, zFar, invProj);
				}
			}
		}

		// Upload to GPU
		UploadClusterBounds();
	}

	/// Gets the near depth of a depth slice (logarithmic distribution).
	private float GetDepthSliceNear(uint32 slice)
	{
		return mNearPlane * Math.Pow(mFarPlane / mNearPlane, (float)slice / GridSizeZ);
	}

	/// Gets the far depth of a depth slice.
	private float GetDepthSliceFar(uint32 slice)
	{
		return mNearPlane * Math.Pow(mFarPlane / mNearPlane, (float)(slice + 1) / GridSizeZ);
	}

	/// Computes the view-space AABB for a cluster.
	private void ComputeClusterAABB(ref Cluster cluster,
		float ndcMinX, float ndcMaxX, float ndcMinY, float ndcMaxY,
		float zNear, float zFar, Matrix invProj)
	{
		// Corner points at near plane
		Vector3[4] nearCorners;
		nearCorners[0] = ScreenToView(.(ndcMinX, ndcMinY, 0), zNear, invProj);
		nearCorners[1] = ScreenToView(.(ndcMaxX, ndcMinY, 0), zNear, invProj);
		nearCorners[2] = ScreenToView(.(ndcMinX, ndcMaxY, 0), zNear, invProj);
		nearCorners[3] = ScreenToView(.(ndcMaxX, ndcMaxY, 0), zNear, invProj);

		// Corner points at far plane
		Vector3[4] farCorners;
		farCorners[0] = ScreenToView(.(ndcMinX, ndcMinY, 1), zFar, invProj);
		farCorners[1] = ScreenToView(.(ndcMaxX, ndcMinY, 1), zFar, invProj);
		farCorners[2] = ScreenToView(.(ndcMinX, ndcMaxY, 1), zFar, invProj);
		farCorners[3] = ScreenToView(.(ndcMaxX, ndcMaxY, 1), zFar, invProj);

		// Compute AABB from all 8 corners
		Vector3 minBounds = .(float.MaxValue);
		Vector3 maxBounds = .(float.MinValue);

		for (int i = 0; i < 4; i++)
		{
			minBounds = Vector3.Min(minBounds, nearCorners[i]);
			maxBounds = Vector3.Max(maxBounds, nearCorners[i]);
			minBounds = Vector3.Min(minBounds, farCorners[i]);
			maxBounds = Vector3.Max(maxBounds, farCorners[i]);
		}

		cluster.MinBounds = .(minBounds.X, minBounds.Y, minBounds.Z, 0);
		cluster.MaxBounds = .(maxBounds.X, maxBounds.Y, maxBounds.Z, 0);
	}

	/// Converts NDC point to view space at given depth.
	private Vector3 ScreenToView(Vector3 ndc, float viewZ, Matrix invProj)
	{
		// For a standard perspective projection, we can compute view space directly
		Vector4 clipPos = .(ndc.X, ndc.Y, ndc.Z, 1.0f);
		Vector4 viewPos = Vector4.Transform(clipPos, invProj);
		viewPos /= viewPos.W;

		// Scale to desired depth
		float scale = viewZ / viewPos.Z;
		return .(viewPos.X * scale, viewPos.Y * scale, viewZ);
	}

	/// Uploads cluster bounds to GPU.
	private void UploadClusterBounds()
	{
		if (mClusterBoundsBuffer == null)
			return;

		let ptr = mClusterBoundsBuffer.Map();
		if (ptr != null)
		{
			Internal.MemCpy(ptr, mClusters.Ptr, TotalClusters * Cluster.Size);
			mClusterBoundsBuffer.Unmap();
		}
	}

	/// Assigns lights to clusters. Call each frame after light updates.
	public void AssignLights(Span<LightData> lights, Matrix viewMatrix)
	{
		// Clear previous assignments
		for (var data in ref mClusterLightData)
		{
			data.Offset = 0;
			data.Count = 0;
		}
		mLightIndices.Clear();

		// Temporary per-cluster light lists
		List<uint32>[] clusterLights = new List<uint32>[TotalClusters];
		defer
		{
			for (var list in clusterLights)
				delete list;
			delete clusterLights;
		}

		for (uint32 i = 0; i < TotalClusters; i++)
			clusterLights[i] = new .();

		// Test each light against each cluster
		for (uint32 lightIdx = 0; lightIdx < lights.Length; lightIdx++)
		{
			let light = ref lights[lightIdx];

			// Skip directional lights (they affect all clusters)
			if (light.Type == 0) // Directional
				continue;

			// Transform light position to view space
			Vector4 viewPos = Vector4.Transform(Vector4(light.Position, 1.0f), viewMatrix);
			Vector3 lightPosView = .(viewPos.X, viewPos.Y, viewPos.Z);

			// Get light bounds (sphere for point lights, cone for spot lights)
			float radius = light.Range;

			// Find affected clusters
			for (uint32 clusterIdx = 0; clusterIdx < TotalClusters; clusterIdx++)
			{
				if (LightIntersectsCluster(lightPosView, radius, ref mClusters[clusterIdx]))
				{
					if (clusterLights[clusterIdx].Count < MaxLightsPerCluster)
						clusterLights[clusterIdx].Add(lightIdx);
				}
			}
		}

		// Build compact light index buffer
		uint32 currentOffset = 0;
		for (uint32 i = 0; i < TotalClusters; i++)
		{
			mClusterLightData[i].Offset = currentOffset;
			mClusterLightData[i].Count = (uint32)clusterLights[i].Count;

			for (let lightIdx in clusterLights[i])
			{
				if (mLightIndices.Count < MaxTotalLightIndices)
					mLightIndices.Add(lightIdx);
			}

			currentOffset += (uint32)clusterLights[i].Count;
		}

		// Upload to GPU
		UploadLightAssignments();
	}

	/// Tests if a light sphere intersects a cluster AABB.
	private bool LightIntersectsCluster(Vector3 lightPos, float radius, ref Cluster cluster)
	{
		// Sphere-AABB intersection test
		Vector3 clusterMin = .(cluster.MinBounds.X, cluster.MinBounds.Y, cluster.MinBounds.Z);
		Vector3 clusterMax = .(cluster.MaxBounds.X, cluster.MaxBounds.Y, cluster.MaxBounds.Z);

		// Find closest point on AABB to sphere center
		Vector3 closest = Vector3.Clamp(lightPos, clusterMin, clusterMax);

		// Check if closest point is within sphere
		float distSq = Vector3.DistanceSquared(lightPos, closest);
		return distSq <= radius * radius;
	}

	/// Uploads light assignments to GPU.
	private void UploadLightAssignments()
	{
		// Upload cluster light data
		if (mClusterLightDataBuffer != null)
		{
			let ptr = mClusterLightDataBuffer.Map();
			if (ptr != null)
			{
				Internal.MemCpy(ptr, mClusterLightData.Ptr, TotalClusters * ClusterLightData.Size);
				mClusterLightDataBuffer.Unmap();
			}
		}

		// Upload light indices
		if (mLightIndexBuffer != null && mLightIndices.Count > 0)
		{
			let ptr = mLightIndexBuffer.Map();
			if (ptr != null)
			{
				Internal.MemCpy(ptr, mLightIndices.Ptr, mLightIndices.Count * sizeof(uint32));
				mLightIndexBuffer.Unmap();
			}
		}
	}

	/// Gets the cluster index for a given grid position.
	public uint32 GetClusterIndex(uint32 x, uint32 y, uint32 z)
	{
		return x + y * GridSizeX + z * GridSizeX * GridSizeY;
	}

	/// Gets the depth slice for a given view-space Z value.
	public uint32 GetDepthSlice(float viewZ)
	{
		if (viewZ <= mNearPlane) return 0;
		if (viewZ >= mFarPlane) return GridSizeZ - 1;

		// Logarithmic depth slice
		float logZ = Math.Log(viewZ / mNearPlane) / mLogFarOverNear;
		return (uint32)Math.Clamp(logZ * GridSizeZ, 0, GridSizeZ - 1);
	}

	/// Gets GPU buffers for shader binding.
	public IBuffer ClusterBoundsBuffer => mClusterBoundsBuffer;
	public IBuffer ClusterLightDataBuffer => mClusterLightDataBuffer;
	public IBuffer LightIndexBuffer => mLightIndexBuffer;

	/// Gets statistics.
	public void GetStats(String outStats)
	{
		outStats.AppendF("Cluster Grid: {}x{}x{} = {} clusters\n", GridSizeX, GridSizeY, GridSizeZ, TotalClusters);
		outStats.AppendF("  Light indices: {}\n", mLightIndices.Count);
	}

	public void Dispose()
	{
		// Buffers cleaned up by destructor
	}
}

namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Materials;

/// Sort mode for visible objects.
public enum SortMode : uint8
{
	/// No sorting.
	None,

	/// Sort front-to-back (nearest first) for early-Z optimization.
	FrontToBack,

	/// Sort back-to-front (farthest first) for transparency.
	BackToFront,

	/// Sort by material to minimize state changes.
	ByMaterial
}

/// Represents a visible mesh with computed data for rendering.
public struct VisibleMesh
{
	/// Handle to the mesh proxy.
	public MeshProxyHandle Handle;

	/// Squared distance from camera (for sorting/LOD).
	public float DistanceSq;

	/// Selected LOD level.
	public uint8 LODLevel;

	/// Sort key for batching (material hash, etc.).
	public uint32 SortKey;
}

/// Represents a visible skinned mesh with computed data.
public struct VisibleSkinnedMesh
{
	/// Handle to the skinned mesh proxy.
	public SkinnedMeshProxyHandle Handle;

	/// Squared distance from camera.
	public float DistanceSq;

	/// Selected LOD level.
	public uint8 LODLevel;

	/// Sort key for batching.
	public uint32 SortKey;
}

/// Represents a visible light affecting the view.
public struct VisibleLight
{
	/// Handle to the light proxy.
	public LightProxyHandle Handle;

	/// Squared distance from camera (for priority).
	public float DistanceSq;

	/// Whether this light casts shadows.
	public bool CastsShadows;
}

/// Collects and organizes visible objects for rendering.
/// Performs frustum culling, LOD selection, and sorting.
public class VisibilityResolver
{
	// Culling
	private FrustumCuller mCuller = new .() ~ delete _;

	// Visible object lists
	private List<VisibleMesh> mVisibleMeshes = new .() ~ delete _;
	private List<VisibleSkinnedMesh> mVisibleSkinnedMeshes = new .() ~ delete _;
	private List<VisibleLight> mVisibleLights = new .() ~ delete _;

	// Temporary lists for culling
	private List<MeshProxyHandle> mTempMeshHandles = new .() ~ delete _;
	private List<SkinnedMeshProxyHandle> mTempSkinnedHandles = new .() ~ delete _;
	private List<LightProxyHandle> mTempLightHandles = new .() ~ delete _;

	// LOD settings
	private float[4] mLODDistances = .(25.0f, 100.0f, 400.0f, 1600.0f);

	// Statistics
	private VisibilityStats mStats;

	/// Gets visible static meshes.
	public Span<VisibleMesh> VisibleMeshes => mVisibleMeshes;

	/// Gets visible skinned meshes.
	public Span<VisibleSkinnedMesh> VisibleSkinnedMeshes => mVisibleSkinnedMeshes;

	/// Gets visible lights.
	public Span<VisibleLight> VisibleLights => mVisibleLights;

	/// Gets visibility statistics.
	public VisibilityStats Stats => mStats;

	/// Gets the frustum culler for direct access.
	public FrustumCuller Culler => mCuller;

	/// Sets LOD distance thresholds (squared distances).
	public void SetLODDistances(float lod0, float lod1, float lod2, float lod3)
	{
		mLODDistances[0] = lod0 * lod0;
		mLODDistances[1] = lod1 * lod1;
		mLODDistances[2] = lod2 * lod2;
		mLODDistances[3] = lod3 * lod3;
	}

	/// Resolves visibility for a view against a render world.
	public void Resolve(RenderWorld world, CameraProxy* camera, SortMode sortMode = .FrontToBack)
	{
		mStats = .();

		if (camera == null)
			return;

		// Set up frustum from camera
		mCuller.ResetStats();
		mCuller.SetFrustum(camera);

		let cameraPos = camera.Position;

		// Cull and collect static meshes
		ResolveStaticMeshes(world, cameraPos, sortMode);

		// Cull and collect skinned meshes
		ResolveSkinnedMeshes(world, cameraPos, sortMode);

		// Cull and collect lights
		ResolveLights(world, cameraPos);

		// Update stats
		mStats.CullStats = mCuller.Stats;
	}

	/// Resolves visibility using a view-projection matrix directly.
	public void Resolve(RenderWorld world, Matrix viewProjection, Vector3 cameraPos, SortMode sortMode = .FrontToBack)
	{
		mStats = .();

		// Set up frustum from matrix
		mCuller.ResetStats();
		mCuller.SetFrustum(viewProjection);

		// Cull and collect static meshes
		ResolveStaticMeshes(world, cameraPos, sortMode);

		// Cull and collect skinned meshes
		ResolveSkinnedMeshes(world, cameraPos, sortMode);

		// Cull and collect lights
		ResolveLights(world, cameraPos);

		// Update stats
		mStats.CullStats = mCuller.Stats;
	}

	/// Clears all visibility data.
	public void Clear()
	{
		mVisibleMeshes.Clear();
		mVisibleSkinnedMeshes.Clear();
		mVisibleLights.Clear();
		mStats = .();
	}

	private void ResolveStaticMeshes(RenderWorld world, Vector3 cameraPos, SortMode sortMode)
	{
		mVisibleMeshes.Clear();
		mTempMeshHandles.Clear();

		// Frustum cull
		mCuller.CullMeshes(world, mTempMeshHandles);

		// Build visible mesh list with LOD and sort key
		for (let handle in mTempMeshHandles)
		{
			if (let proxy = world.GetMesh(handle))
			{
				// Calculate distance to bounds center
				let bounds = proxy.WorldBounds;
				let center = (bounds.Min + bounds.Max) * 0.5f;
				let distSq = Vector3.DistanceSquared(cameraPos, center);

				// Select LOD
				let lodLevel = SelectLOD(distSq);

				// Generate sort key (material-based for now)
				let sortKey = GenerateSortKey(proxy.Material, distSq);

				mVisibleMeshes.Add(.()
				{
					Handle = handle,
					DistanceSq = distSq,
					LODLevel = lodLevel,
					SortKey = sortKey
				});
			}
		}

		// Sort based on mode
		SortMeshes(sortMode);

		mStats.VisibleMeshCount = (int32)mVisibleMeshes.Count;
		mStats.TotalMeshCount = world.MeshCount;
	}

	private void ResolveSkinnedMeshes(RenderWorld world, Vector3 cameraPos, SortMode sortMode)
	{
		mVisibleSkinnedMeshes.Clear();
		mTempSkinnedHandles.Clear();

		// Frustum cull
		mCuller.CullSkinnedMeshes(world, mTempSkinnedHandles);

		// Build visible mesh list
		for (let handle in mTempSkinnedHandles)
		{
			if (let proxy = world.GetSkinnedMesh(handle))
			{
				let bounds = proxy.WorldBounds;
				let center = (bounds.Min + bounds.Max) * 0.5f;
				let distSq = Vector3.DistanceSquared(cameraPos, center);
				let lodLevel = SelectLOD(distSq);
				let sortKey = GenerateSortKey(proxy.Material, distSq);

				mVisibleSkinnedMeshes.Add(.()
				{
					Handle = handle,
					DistanceSq = distSq,
					LODLevel = lodLevel,
					SortKey = sortKey
				});
			}
		}

		// Sort based on mode
		SortSkinnedMeshes(sortMode);

		mStats.VisibleSkinnedMeshCount = (int32)mVisibleSkinnedMeshes.Count;
		mStats.TotalSkinnedMeshCount = world.SkinnedMeshCount;
	}

	private void ResolveLights(RenderWorld world, Vector3 cameraPos)
	{
		mVisibleLights.Clear();
		mTempLightHandles.Clear();

		// Frustum cull lights
		mCuller.CullLights(world, mTempLightHandles);

		// Build visible light list
		for (let handle in mTempLightHandles)
		{
			if (let proxy = world.GetLight(handle))
			{
				float distSq = 0;
				if (proxy.Type != .Directional)
					distSq = Vector3.DistanceSquared(cameraPos, proxy.Position);

				mVisibleLights.Add(.()
				{
					Handle = handle,
					DistanceSq = distSq,
					CastsShadows = proxy.CastsShadows
				});
			}
		}

		// Sort lights by distance (closest first for priority)
		mVisibleLights.Sort(scope (a, b) => a.DistanceSq <=> b.DistanceSq);

		mStats.VisibleLightCount = (int32)mVisibleLights.Count;
		mStats.TotalLightCount = world.LightCount;
	}

	private uint8 SelectLOD(float distanceSq)
	{
		if (distanceSq < mLODDistances[0])
			return 0;
		if (distanceSq < mLODDistances[1])
			return 1;
		if (distanceSq < mLODDistances[2])
			return 2;
		if (distanceSq < mLODDistances[3])
			return 3;
		return 3; // Max LOD
	}

	private uint32 GenerateSortKey(MaterialInstance material, float distanceSq)
	{
		// For now, use material pointer as hash for grouping
		// High bits: material hash, Low bits: distance quantized
		uint32 materialHash = (uint32)(int)Internal.UnsafeCastToPtr(material) & 0xFFFF0000;
		uint32 distKey = (uint32)(Math.Sqrt(distanceSq) * 10) & 0x0000FFFF;
		return materialHash | distKey;
	}

	private void SortMeshes(SortMode mode)
	{
		switch (mode)
		{
		case .None:
			break;

		case .FrontToBack:
			mVisibleMeshes.Sort(scope (a, b) => a.DistanceSq <=> b.DistanceSq);

		case .BackToFront:
			mVisibleMeshes.Sort(scope (a, b) => b.DistanceSq <=> a.DistanceSq);

		case .ByMaterial:
			mVisibleMeshes.Sort(scope (a, b) => a.SortKey <=> b.SortKey);
		}
	}

	private void SortSkinnedMeshes(SortMode mode)
	{
		switch (mode)
		{
		case .None:
			break;

		case .FrontToBack:
			mVisibleSkinnedMeshes.Sort(scope (a, b) => a.DistanceSq <=> b.DistanceSq);

		case .BackToFront:
			mVisibleSkinnedMeshes.Sort(scope (a, b) => b.DistanceSq <=> a.DistanceSq);

		case .ByMaterial:
			mVisibleSkinnedMeshes.Sort(scope (a, b) => a.SortKey <=> b.SortKey);
		}
	}
}

/// Statistics from visibility resolution.
public struct VisibilityStats
{
	/// Frustum culling statistics.
	public CullStats CullStats;

	/// Number of visible static meshes after culling.
	public int32 VisibleMeshCount;

	/// Total number of static meshes in the world.
	public int32 TotalMeshCount;

	/// Number of visible skinned meshes after culling.
	public int32 VisibleSkinnedMeshCount;

	/// Total number of skinned meshes in the world.
	public int32 TotalSkinnedMeshCount;

	/// Number of visible lights after culling.
	public int32 VisibleLightCount;

	/// Total number of lights in the world.
	public int32 TotalLightCount;

	/// Percentage of meshes culled.
	public float MeshCullPercentage => TotalMeshCount > 0
		? (float)(TotalMeshCount - VisibleMeshCount) / (float)TotalMeshCount * 100.0f
		: 0.0f;
}

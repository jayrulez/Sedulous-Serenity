namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
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

	// LOD settings
	private float[4] mLODDistances = .(25.0f, 100.0f, 400.0f, 1600.0f);
	private float mLODBias = 1.0f;

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

	/// Gets the total number of visible objects (meshes + skinned meshes).
	public int32 VisibleCount => (int32)(mVisibleMeshes.Count + mVisibleSkinnedMeshes.Count);

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

	/// Sets the LOD bias. Higher values push LOD transitions farther (higher quality at distance).
	public void SetLODBias(float bias)
	{
		mLODBias = Math.Max(0.01f, bias);
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

	/// Resolves visibility and accumulates results without clearing existing visible objects.
	/// Used for multi-view union visibility: call once per view to build the union.
	public void ResolveAccumulate(RenderWorld world, Matrix viewProjection, Vector3 cameraPos, SortMode sortMode = .FrontToBack)
	{
		// Set up frustum from matrix
		mCuller.ResetStats();
		mCuller.SetFrustum(viewProjection);

		// Accumulate static meshes
		AccumulateStaticMeshes(world, cameraPos);

		// Accumulate skinned meshes
		AccumulateSkinnedMeshes(world, cameraPos);

		// Accumulate lights
		AccumulateLights(world, cameraPos);

		// Sort after accumulation
		SortMeshes(sortMode);
		SortSkinnedMeshes(sortMode);
		mVisibleLights.Sort(scope (a, b) => a.DistanceSq <=> b.DistanceSq);

		mStats.VisibleMeshCount = (int32)mVisibleMeshes.Count;
		mStats.VisibleSkinnedMeshCount = (int32)mVisibleSkinnedMeshes.Count;
		mStats.VisibleLightCount = (int32)mVisibleLights.Count;
		mStats.TotalMeshCount = world.MeshCount;
		mStats.TotalSkinnedMeshCount = world.SkinnedMeshCount;
		mStats.TotalLightCount = world.LightCount;
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

		// Single-pass: frustum cull + build visible mesh list with LOD and sort key
		world.ForEachMesh(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive)
				return;

			if ((proxy.Flags & .Visible) == 0)
				return;

			if (!mCuller.IsVisible(proxy.WorldBounds))
				return;

			let bounds = proxy.WorldBounds;
			let center = (bounds.Min + bounds.Max) * 0.5f;
			let distSq = Vector3.DistanceSquared(cameraPos, center);
			let lodLevel = SelectLOD(distSq);
			let sortKey = GenerateSortKey(proxy.Materials[0], distSq);

			mVisibleMeshes.Add(.()
			{
				Handle = .() { Handle = handle },
				DistanceSq = distSq,
				LODLevel = lodLevel,
				SortKey = sortKey
			});
		});

		// Sort based on mode
		SortMeshes(sortMode);

		mStats.VisibleMeshCount = (int32)mVisibleMeshes.Count;
		mStats.TotalMeshCount = world.MeshCount;
	}

	private void ResolveSkinnedMeshes(RenderWorld world, Vector3 cameraPos, SortMode sortMode)
	{
		mVisibleSkinnedMeshes.Clear();

		// Single-pass: frustum cull + build visible mesh list
		world.ForEachSkinnedMesh(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive)
				return;

			if ((proxy.Flags & .Visible) == 0)
				return;

			if (!mCuller.IsVisible(proxy.WorldBounds))
				return;

			let bounds = proxy.WorldBounds;
			let center = (bounds.Min + bounds.Max) * 0.5f;
			let distSq = Vector3.DistanceSquared(cameraPos, center);
			let lodLevel = SelectLOD(distSq);
			let sortKey = GenerateSortKey(proxy.Materials[0], distSq);

			mVisibleSkinnedMeshes.Add(.()
			{
				Handle = .() { Handle = handle },
				DistanceSq = distSq,
				LODLevel = lodLevel,
				SortKey = sortKey
			});
		});

		// Sort based on mode
		SortSkinnedMeshes(sortMode);

		mStats.VisibleSkinnedMeshCount = (int32)mVisibleSkinnedMeshes.Count;
		mStats.TotalSkinnedMeshCount = world.SkinnedMeshCount;
	}

	private void ResolveLights(RenderWorld world, Vector3 cameraPos)
	{
		mVisibleLights.Clear();

		// Single-pass: frustum cull + build visible light list
		world.ForEachLight(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive || !proxy.IsEnabled)
				return;

			// Directional lights always affect the scene
			if (proxy.Type == .Directional)
			{
				mVisibleLights.Add(.()
				{
					Handle = .() { Handle = handle },
					DistanceSq = 0,
					CastsShadows = proxy.CastsShadows
				});
				return;
			}

			// For point/spot lights, test their bounding sphere
			let sphere = BoundingSphere(proxy.Position, proxy.Range);
			if (mCuller.IsVisible(sphere))
			{
				let distSq = Vector3.DistanceSquared(cameraPos, proxy.Position);
				mVisibleLights.Add(.()
				{
					Handle = .() { Handle = handle },
					DistanceSq = distSq,
					CastsShadows = proxy.CastsShadows
				});
			}
		});

		// Sort lights by distance (closest first for priority)
		mVisibleLights.Sort(scope (a, b) => a.DistanceSq <=> b.DistanceSq);

		mStats.VisibleLightCount = (int32)mVisibleLights.Count;
		mStats.TotalLightCount = world.LightCount;
	}

	private void AccumulateStaticMeshes(RenderWorld world, Vector3 cameraPos)
	{
		// Build HashSet of already-visible handle indices for O(1) dedup
		HashSet<uint32> existing = scope .((int32)mVisibleMeshes.Count);
		for (let vm in mVisibleMeshes)
			existing.Add(vm.Handle.Handle.Index);

		// Single-pass: frustum cull + build visible mesh list, skip duplicates
		world.ForEachMesh(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive)
				return;

			if ((proxy.Flags & .Visible) == 0)
				return;

			if (existing.Contains(handle.Index))
				return;

			if (!mCuller.IsVisible(proxy.WorldBounds))
				return;

			let bounds = proxy.WorldBounds;
			let center = (bounds.Min + bounds.Max) * 0.5f;
			let distSq = Vector3.DistanceSquared(cameraPos, center);
			let lodLevel = SelectLOD(distSq);
			let sortKey = GenerateSortKey(proxy.Materials[0], distSq);

			existing.Add(handle.Index);
			mVisibleMeshes.Add(.()
			{
				Handle = .() { Handle = handle },
				DistanceSq = distSq,
				LODLevel = lodLevel,
				SortKey = sortKey
			});
		});
	}

	private void AccumulateSkinnedMeshes(RenderWorld world, Vector3 cameraPos)
	{
		HashSet<uint32> existing = scope .((int32)mVisibleSkinnedMeshes.Count);
		for (let vm in mVisibleSkinnedMeshes)
			existing.Add(vm.Handle.Handle.Index);

		world.ForEachSkinnedMesh(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive)
				return;

			if ((proxy.Flags & .Visible) == 0)
				return;

			if (existing.Contains(handle.Index))
				return;

			if (!mCuller.IsVisible(proxy.WorldBounds))
				return;

			let bounds = proxy.WorldBounds;
			let center = (bounds.Min + bounds.Max) * 0.5f;
			let distSq = Vector3.DistanceSquared(cameraPos, center);
			let lodLevel = SelectLOD(distSq);
			let sortKey = GenerateSortKey(proxy.Materials[0], distSq);

			existing.Add(handle.Index);
			mVisibleSkinnedMeshes.Add(.()
			{
				Handle = .() { Handle = handle },
				DistanceSq = distSq,
				LODLevel = lodLevel,
				SortKey = sortKey
			});
		});
	}

	private void AccumulateLights(RenderWorld world, Vector3 cameraPos)
	{
		HashSet<uint32> existing = scope .((int32)mVisibleLights.Count);
		for (let vl in mVisibleLights)
			existing.Add(vl.Handle.Handle.Index);

		world.ForEachLight(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive || !proxy.IsEnabled)
				return;

			if (existing.Contains(handle.Index))
				return;

			if (proxy.Type == .Directional)
			{
				existing.Add(handle.Index);
				mVisibleLights.Add(.()
				{
					Handle = .() { Handle = handle },
					DistanceSq = 0,
					CastsShadows = proxy.CastsShadows
				});
				return;
			}

			let sphere = BoundingSphere(proxy.Position, proxy.Range);
			if (mCuller.IsVisible(sphere))
			{
				let distSq = Vector3.DistanceSquared(cameraPos, proxy.Position);
				existing.Add(handle.Index);
				mVisibleLights.Add(.()
				{
					Handle = .() { Handle = handle },
					DistanceSq = distSq,
					CastsShadows = proxy.CastsShadows
				});
			}
		});
	}

	private uint8 SelectLOD(float distanceSq)
	{
		// Scale distance by inverse LOD bias squared (higher bias = farther transitions = higher quality)
		let adjustedDist = distanceSq / (mLODBias * mLODBias);

		if (adjustedDist < mLODDistances[0])
			return 0;
		if (adjustedDist < mLODDistances[1])
			return 1;
		if (adjustedDist < mLODDistances[2])
			return 2;
		if (adjustedDist < mLODDistances[3])
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

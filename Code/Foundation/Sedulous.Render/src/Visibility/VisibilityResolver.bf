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
	/// Index into RenderableList.OpaqueMeshes (stable for the current frame).
	public int32 Index;

	/// Handle to the mesh proxy. Populated from the renderable's MeshRenderHandle
	/// so existing consumers that look up via RenderWorld.GetMesh keep working
	/// during the incremental Phase 5 migration. Will be removed once all
	/// consumers move to index-based RenderableList access.
	public MeshRenderHandle Handle;

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
	/// Index into RenderableList.SkinnedMeshes (stable for the current frame).
	public int32 Index;

	/// Handle to the skinned mesh proxy (holdover, see VisibleMesh.Handle).
	public SkinnedMeshRenderHandle Handle;

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
	/// Index into RenderableList.Lights (stable for the current frame).
	public int32 Index;

	/// Handle to the light proxy (holdover, see VisibleMesh.Handle).
	public LightRenderHandle Handle;

	/// Squared distance from camera (for priority).
	public float DistanceSq;

	/// Whether this light casts shadows.
	public bool CastsShadows;
}

/// Collects and organizes visible objects for rendering.
/// Performs frustum culling, LOD selection, and sorting against a RenderableList.
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

	/// Resolves visibility for a view against a RenderableList snapshot.
	public void Resolve(RenderableList renderables, Matrix viewProjection, Vector3 cameraPos, SortMode sortMode = .FrontToBack)
	{
		mStats = .();

		// Set up frustum from matrix
		mCuller.ResetStats();
		mCuller.SetFrustum(viewProjection);

		// Cull and collect static meshes
		ResolveStaticMeshes(renderables, cameraPos, sortMode);

		// Cull and collect skinned meshes
		ResolveSkinnedMeshes(renderables, cameraPos, sortMode);

		// Cull and collect lights
		ResolveLights(renderables, cameraPos);

		// Update stats
		mStats.CullStats = mCuller.Stats;
	}

	/// Resolves visibility and accumulates results without clearing existing visible objects.
	/// Used for multi-view union visibility: call once per view to build the union.
	public void ResolveAccumulate(RenderableList renderables, Matrix viewProjection, Vector3 cameraPos, SortMode sortMode = .FrontToBack)
	{
		// Set up frustum from matrix
		mCuller.ResetStats();
		mCuller.SetFrustum(viewProjection);

		// Accumulate static meshes
		AccumulateStaticMeshes(renderables, cameraPos);

		// Accumulate skinned meshes
		AccumulateSkinnedMeshes(renderables, cameraPos);

		// Accumulate lights
		AccumulateLights(renderables, cameraPos);

		// Sort after accumulation
		SortMeshes(sortMode);
		SortSkinnedMeshes(sortMode);
		mVisibleLights.Sort(scope (a, b) => a.DistanceSq <=> b.DistanceSq);

		mStats.VisibleMeshCount = (int32)mVisibleMeshes.Count;
		mStats.VisibleSkinnedMeshCount = (int32)mVisibleSkinnedMeshes.Count;
		mStats.VisibleLightCount = (int32)mVisibleLights.Count;
		mStats.TotalMeshCount = (int32)(renderables.OpaqueMeshes.Count + renderables.TransparentMeshes.Count);
		mStats.TotalSkinnedMeshCount = (int32)renderables.SkinnedMeshes.Count;
		mStats.TotalLightCount = (int32)renderables.Lights.Count;
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

	private void ResolveStaticMeshes(RenderableList renderables, Vector3 cameraPos, SortMode sortMode)
	{
		mVisibleMeshes.Clear();

		// Single-pass: frustum cull + build visible mesh list with LOD and sort key.
		// PopulateRenderables already filtered IsActive/Visible, so we skip that check.
		for (int32 i = 0; i < (int32)renderables.OpaqueMeshes.Count; i++)
		{
			let mesh = ref renderables.OpaqueMeshes[i];

			if (!mCuller.IsVisible(mesh.WorldBounds))
				continue;

			let bounds = mesh.WorldBounds;
			let center = (bounds.Min + bounds.Max) * 0.5f;
			let distSq = Vector3.DistanceSquared(cameraPos, center);
			let lodLevel = SelectLOD(distSq);
			let sortKey = GenerateSortKey(mesh.Materials[0], distSq);

			mVisibleMeshes.Add(.()
			{
				Index = i,
				Handle = mesh.MeshRenderHandle,
				DistanceSq = distSq,
				LODLevel = lodLevel,
				SortKey = sortKey
			});
		}

		// Sort based on mode
		SortMeshes(sortMode);

		mStats.VisibleMeshCount = (int32)mVisibleMeshes.Count;
		mStats.TotalMeshCount = (int32)(renderables.OpaqueMeshes.Count + renderables.TransparentMeshes.Count);
	}

	private void ResolveSkinnedMeshes(RenderableList renderables, Vector3 cameraPos, SortMode sortMode)
	{
		mVisibleSkinnedMeshes.Clear();

		for (int32 i = 0; i < (int32)renderables.SkinnedMeshes.Count; i++)
		{
			let mesh = ref renderables.SkinnedMeshes[i];

			if (!mCuller.IsVisible(mesh.WorldBounds))
				continue;

			let bounds = mesh.WorldBounds;
			let center = (bounds.Min + bounds.Max) * 0.5f;
			let distSq = Vector3.DistanceSquared(cameraPos, center);
			let lodLevel = SelectLOD(distSq);
			let sortKey = GenerateSortKey(mesh.Materials[0], distSq);

			mVisibleSkinnedMeshes.Add(.()
			{
				Index = i,
				Handle = mesh.SkinnedMeshHandle,
				DistanceSq = distSq,
				LODLevel = lodLevel,
				SortKey = sortKey
			});
		}

		// Sort based on mode
		SortSkinnedMeshes(sortMode);

		mStats.VisibleSkinnedMeshCount = (int32)mVisibleSkinnedMeshes.Count;
		mStats.TotalSkinnedMeshCount = (int32)renderables.SkinnedMeshes.Count;
	}

	private void ResolveLights(RenderableList renderables, Vector3 cameraPos)
	{
		mVisibleLights.Clear();

		for (int32 i = 0; i < (int32)renderables.Lights.Count; i++)
		{
			let light = ref renderables.Lights[i];

			// Directional lights always affect the scene
			if (light.Type == .Directional)
			{
				mVisibleLights.Add(.()
				{
					Index = i,
					Handle = light.LightHandle,
					DistanceSq = 0,
					CastsShadows = light.CastsShadows
				});
				continue;
			}

			// For point/spot lights, test their bounding sphere
			let sphere = BoundingSphere(light.Position, light.Range);
			if (mCuller.IsVisible(sphere))
			{
				let distSq = Vector3.DistanceSquared(cameraPos, light.Position);
				mVisibleLights.Add(.()
				{
					Index = i,
					Handle = light.LightHandle,
					DistanceSq = distSq,
					CastsShadows = light.CastsShadows
				});
			}
		}

		// Sort lights by distance (closest first for priority)
		mVisibleLights.Sort(scope (a, b) => a.DistanceSq <=> b.DistanceSq);

		mStats.VisibleLightCount = (int32)mVisibleLights.Count;
		mStats.TotalLightCount = (int32)renderables.Lights.Count;
	}

	private void AccumulateStaticMeshes(RenderableList renderables, Vector3 cameraPos)
	{
		// Dedup by list index — each entry in OpaqueMeshes represents a unique
		// per-slot draw, and the index is stable for the frame.
		HashSet<int32> existing = scope .((int32)mVisibleMeshes.Count);
		for (let vm in mVisibleMeshes)
			existing.Add(vm.Index);

		for (int32 i = 0; i < (int32)renderables.OpaqueMeshes.Count; i++)
		{
			if (existing.Contains(i))
				continue;

			let mesh = ref renderables.OpaqueMeshes[i];

			if (!mCuller.IsVisible(mesh.WorldBounds))
				continue;

			let bounds = mesh.WorldBounds;
			let center = (bounds.Min + bounds.Max) * 0.5f;
			let distSq = Vector3.DistanceSquared(cameraPos, center);
			let lodLevel = SelectLOD(distSq);
			let sortKey = GenerateSortKey(mesh.Materials[0], distSq);

			existing.Add(i);
			mVisibleMeshes.Add(.()
			{
				Index = i,
				Handle = mesh.MeshRenderHandle,
				DistanceSq = distSq,
				LODLevel = lodLevel,
				SortKey = sortKey
			});
		}
	}

	private void AccumulateSkinnedMeshes(RenderableList renderables, Vector3 cameraPos)
	{
		HashSet<int32> existing = scope .((int32)mVisibleSkinnedMeshes.Count);
		for (let vm in mVisibleSkinnedMeshes)
			existing.Add(vm.Index);

		for (int32 i = 0; i < (int32)renderables.SkinnedMeshes.Count; i++)
		{
			if (existing.Contains(i))
				continue;

			let mesh = ref renderables.SkinnedMeshes[i];

			if (!mCuller.IsVisible(mesh.WorldBounds))
				continue;

			let bounds = mesh.WorldBounds;
			let center = (bounds.Min + bounds.Max) * 0.5f;
			let distSq = Vector3.DistanceSquared(cameraPos, center);
			let lodLevel = SelectLOD(distSq);
			let sortKey = GenerateSortKey(mesh.Materials[0], distSq);

			existing.Add(i);
			mVisibleSkinnedMeshes.Add(.()
			{
				Index = i,
				Handle = mesh.SkinnedMeshHandle,
				DistanceSq = distSq,
				LODLevel = lodLevel,
				SortKey = sortKey
			});
		}
	}

	private void AccumulateLights(RenderableList renderables, Vector3 cameraPos)
	{
		HashSet<int32> existing = scope .((int32)mVisibleLights.Count);
		for (let vl in mVisibleLights)
			existing.Add(vl.Index);

		for (int32 i = 0; i < (int32)renderables.Lights.Count; i++)
		{
			if (existing.Contains(i))
				continue;

			let light = ref renderables.Lights[i];

			if (light.Type == .Directional)
			{
				existing.Add(i);
				mVisibleLights.Add(.()
				{
					Index = i,
					Handle = light.LightHandle,
					DistanceSq = 0,
					CastsShadows = light.CastsShadows
				});
				continue;
			}

			let sphere = BoundingSphere(light.Position, light.Range);
			if (mCuller.IsVisible(sphere))
			{
				let distSq = Vector3.DistanceSquared(cameraPos, light.Position);
				existing.Add(i);
				mVisibleLights.Add(.()
				{
					Index = i,
					Handle = light.LightHandle,
					DistanceSq = distSq,
					CastsShadows = light.CastsShadows
				});
			}
		}
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

namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// Resolves which objects are visible from a given view.
/// Performs frustum culling, LOD selection, and sort key generation.
class VisibilityResolver
{
	private List<VisibleMesh> mVisibleMeshes = new .() ~ delete _;
	private List<VisibleSkinnedMesh> mVisibleSkinnedMeshes = new .() ~ delete _;
	private List<VisibleLight> mVisibleLights = new .() ~ delete _;

	/// Squared LOD distance thresholds.
	private float[4] mLODDistancesSq = .(625, 10000, 160000, 2560000);
	private float mLODBias = 1.0f;

	public List<VisibleMesh> VisibleMeshes => mVisibleMeshes;
	public List<VisibleSkinnedMesh> VisibleSkinnedMeshes => mVisibleSkinnedMeshes;
	public List<VisibleLight> VisibleLights => mVisibleLights;

	/// Resolves visibility for the given world and view.
	public void Resolve(RenderWorld world, ViewContext viewCtx, SortMode sortMode = .FrontToBack)
	{
		Clear();
		CullMeshes(world, viewCtx);
		CullSkinnedMeshes(world, viewCtx);
		CullLights(world, viewCtx);
		Sort(sortMode);
	}

	/// Sets LOD transition distances (world-space, not squared).
	public void SetLODDistances(float lod0, float lod1, float lod2, float lod3)
	{
		mLODDistancesSq[0] = lod0 * lod0;
		mLODDistancesSq[1] = lod1 * lod1;
		mLODDistancesSq[2] = lod2 * lod2;
		mLODDistancesSq[3] = lod3 * lod3;
	}

	/// Sets a LOD bias multiplier. Values > 1 favor higher detail.
	public void SetLODBias(float bias)
	{
		mLODBias = Math.Max(bias, 0.01f);
	}

	/// Clears results without releasing memory.
	public void Clear()
	{
		mVisibleMeshes.Clear();
		mVisibleSkinnedMeshes.Clear();
		mVisibleLights.Clear();
	}

	// --- Internal ---

	private void CullMeshes(RenderWorld world, ViewContext viewCtx)
	{
		let frustum = viewCtx.Frustum;
		let cameraPos = viewCtx.CameraPosition;

		world.StaticMeshes.ForEach(scope (handle, proxy) =>
		{
			// Skip invisible or unassigned meshes
			if (!proxy.Flags.HasFlag(.Visible))
				return;
			if (!proxy.MeshHandle.IsValid)
				return;

			// Compute world-space AABB
			let worldBounds = FrustumCuller.TransformAABB(proxy.LocalBounds, proxy.Transform);

			// Frustum test
			if (!FrustumCuller.TestAABB(frustum, worldBounds))
				return;

			// Distance to AABB center
			let center = (worldBounds.Min + worldBounds.Max) * 0.5f;
			let diff = center - cameraPos;
			let distanceSq = diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z;

			// LOD selection
			let lod = SelectLOD(distanceSq, proxy.ForcedLOD);

			// Sort key
			let sortKey = SortKeyHelper.MakeOpaqueSortKey(
				proxy.Materials[0].Index,  // primary material for sorting
				proxy.MeshHandle.Index,
				lod,
				distanceSq
			);

			mVisibleMeshes.Add(.()
			{
				Handle = handle,
				MeshHandle = proxy.MeshHandle,
				DistanceSq = distanceSq,
				LODLevel = lod,
				SortKey = sortKey
			});
		});
	}

	private void CullSkinnedMeshes(RenderWorld world, ViewContext viewCtx)
	{
		let frustum = viewCtx.Frustum;
		let cameraPos = viewCtx.CameraPosition;

		world.SkinnedMeshes.ForEach(scope (handle, proxy) =>
		{
			if (!proxy.Flags.HasFlag(.Visible))
				return;
			if (!proxy.MeshHandle.IsValid)
				return;

			// Use animation bounds (expanded) for frustum culling
			let worldBounds = FrustumCuller.TransformAABB(proxy.AnimationBounds, proxy.Transform);

			if (!FrustumCuller.TestAABB(frustum, worldBounds))
				return;

			let center = (worldBounds.Min + worldBounds.Max) * 0.5f;
			let diff = center - cameraPos;
			let distanceSq = diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z;

			let lod = SelectLOD(distanceSq, proxy.ForcedLOD);

			let sortKey = SortKeyHelper.MakeOpaqueSortKey(
				proxy.Materials[0].Index,
				proxy.MeshHandle.Index,
				lod,
				distanceSq
			);

			mVisibleSkinnedMeshes.Add(.()
			{
				Handle = handle,
				MeshHandle = proxy.MeshHandle,
				DistanceSq = distanceSq,
				LODLevel = lod,
				SortKey = sortKey
			});
		});
	}

	private void CullLights(RenderWorld world, ViewContext viewCtx)
	{
		let frustum = viewCtx.Frustum;
		let cameraPos = viewCtx.CameraPosition;

		world.Lights.ForEach(scope (handle, proxy) =>
		{
			float distanceSq = 0;

			if (proxy.Type == .Directional)
			{
				// Directional lights are always visible
			}
			else
			{
				// Point/Spot/Area: sphere test
				let diff = proxy.Position - cameraPos;
				distanceSq = diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z;

				let sphere = BoundingSphere(proxy.Position, proxy.Range);
				if (!FrustumCuller.TestSphere(frustum, sphere))
					return;
			}

			mVisibleLights.Add(.()
			{
				Handle = handle,
				Type = proxy.Type,
				DistanceSq = distanceSq,
				CastsShadows = proxy.CastShadows
			});
		});
	}

	private uint8 SelectLOD(float distanceSq, int32 forcedLOD)
	{
		if (forcedLOD >= 0)
			return (uint8)Math.Min(forcedLOD, 3);

		// Apply bias (higher bias = prefer higher detail = larger effective distance thresholds)
		let biasedDistSq = distanceSq / (mLODBias * mLODBias);

		for (int i = 3; i >= 0; i--)
		{
			if (biasedDistSq >= mLODDistancesSq[i])
				return (uint8)Math.Min(i + 1, 3);
		}

		return 0; // highest detail
	}

	private void Sort(SortMode mode)
	{
		switch (mode)
		{
		case .FrontToBack, .ByMaterial:
			mVisibleMeshes.Sort(scope (a, b) => a.SortKey <=> b.SortKey);
			mVisibleSkinnedMeshes.Sort(scope (a, b) => a.SortKey <=> b.SortKey);
		case .BackToFront:
			mVisibleMeshes.Sort(scope (a, b) => b.DistanceSq <=> a.DistanceSq);
			mVisibleSkinnedMeshes.Sort(scope (a, b) => b.DistanceSq <=> a.DistanceSq);
		case .None:
			break;
		}
	}
}

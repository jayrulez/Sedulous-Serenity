namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Manages visibility determination and draw call sorting.
class VisibilityResolver
{
	private FrustumCuller mCuller = new .() ~ delete _;

	// Temporary lists for visibility processing
	private List<StaticMeshProxy*> mAllMeshes = new .() ~ delete _;
	private List<StaticMeshProxy*> mVisibleMeshes = new .() ~ delete _;
	private List<LightProxy*> mAllLights = new .() ~ delete _;
	private List<LightProxy*> mVisibleLights = new .() ~ delete _;
	private List<ParticleEmitterProxy*> mAllParticleEmitters = new .() ~ delete _;
	private List<ParticleEmitterProxy*> mVisibleParticleEmitters = new .() ~ delete _;

	// Output lists
	private List<StaticMeshProxy*> mOpaqueMeshes = new .() ~ delete _;
	private List<StaticMeshProxy*> mTransparentMeshes = new .() ~ delete _;
	private List<StaticMeshProxy*> mShadowCasters = new .() ~ delete _;

	/// Gets opaque meshes (front-to-back sorted).
	public List<StaticMeshProxy*> OpaqueMeshes => mOpaqueMeshes;

	/// Gets transparent meshes (back-to-front sorted).
	public List<StaticMeshProxy*> TransparentMeshes => mTransparentMeshes;

	/// Gets shadow-casting meshes.
	public List<StaticMeshProxy*> ShadowCasters => mShadowCasters;

	/// Gets visible lights.
	public List<LightProxy*> VisibleLights => mVisibleLights;

	/// Gets visible particle emitters (back-to-front sorted for alpha blending).
	public List<ParticleEmitterProxy*> VisibleParticleEmitters => mVisibleParticleEmitters;

	/// Resolves visibility for a render world and camera.
	public void Resolve(RenderWorld world, CameraProxy* camera)
	{
		if (camera == null)
		{
			ClearAll();
			return;
		}

		mCuller.SetCamera(camera);

		// Gather all proxies
		world.GetValidStaticMeshProxies(mAllMeshes);
		world.GetValidLightProxies(mAllLights);
		world.GetValidParticleEmitterProxies(mAllParticleEmitters);

		// Cull meshes
		mCuller.CullMeshes(mAllMeshes, mVisibleMeshes, camera.Position);

		// Cull lights
		mCuller.CullLights(mAllLights, mVisibleLights);

		// Cull particle emitters
		mCuller.CullParticleEmitters(mAllParticleEmitters, mVisibleParticleEmitters, camera.Position);

		// Sort particle emitters back-to-front for transparency
		SortParticleEmittersBackToFront();

		// Separate opaque and transparent
		mOpaqueMeshes.Clear();
		mTransparentMeshes.Clear();
		mShadowCasters.Clear();

		for (let mesh in mVisibleMeshes)
		{
			// Select LOD based on distance
			SelectLOD(mesh, camera.Position);

			// Generate sort key
			GenerateSortKey(mesh);

			if (mesh.IsTransparent)
				mTransparentMeshes.Add(mesh);
			else
				mOpaqueMeshes.Add(mesh);

			if (mesh.CastsShadows)
				mShadowCasters.Add(mesh);
		}

		// Sort opaque front-to-back (minimize overdraw)
		SortOpaqueFrontToBack();

		// Sort transparent back-to-front (correct blending)
		SortTransparentBackToFront();
	}

	/// Resolves visibility for a render world using a RenderView.
	/// This enables per-view layer mask filtering and custom frustum planes.
	public void ResolveForView(RenderWorld world, RenderView* view)
	{
		if (view == null)
		{
			ClearAll();
			return;
		}

		mCuller.SetView(view);

		// Gather all proxies
		world.GetValidStaticMeshProxies(mAllMeshes);
		world.GetValidLightProxies(mAllLights);
		world.GetValidParticleEmitterProxies(mAllParticleEmitters);

		// Cull meshes
		mCuller.CullMeshes(mAllMeshes, mVisibleMeshes, view.Position);

		// Cull lights
		mCuller.CullLights(mAllLights, mVisibleLights);

		// Cull particle emitters
		mCuller.CullParticleEmitters(mAllParticleEmitters, mVisibleParticleEmitters, view.Position);

		// Sort particle emitters back-to-front for transparency
		SortParticleEmittersBackToFront();

		// Separate opaque and transparent
		mOpaqueMeshes.Clear();
		mTransparentMeshes.Clear();
		mShadowCasters.Clear();

		for (let mesh in mVisibleMeshes)
		{
			// Select LOD based on distance
			SelectLOD(mesh, view.Position);

			// Generate sort key
			GenerateSortKey(mesh);

			if (mesh.IsTransparent)
				mTransparentMeshes.Add(mesh);
			else
				mOpaqueMeshes.Add(mesh);

			if (mesh.CastsShadows)
				mShadowCasters.Add(mesh);
		}

		// Sort opaque front-to-back (minimize overdraw)
		SortOpaqueFrontToBack();

		// Sort transparent back-to-front (correct blending)
		SortTransparentBackToFront();
	}

	/// Resolves visibility for shadow casters only (depth-only pass).
	/// Only populates ShadowCasters list, skips opaque/transparent sorting.
	public void ResolveForShadowView(RenderWorld world, RenderView* view)
	{
		if (view == null)
		{
			mShadowCasters.Clear();
			return;
		}

		mCuller.SetView(view);

		// Gather all mesh proxies
		world.GetValidStaticMeshProxies(mAllMeshes);

		// Cull meshes
		mCuller.CullMeshes(mAllMeshes, mVisibleMeshes, view.Position);

		// Only collect shadow casters
		mShadowCasters.Clear();

		for (let mesh in mVisibleMeshes)
		{
			if (mesh.CastsShadows)
				mShadowCasters.Add(mesh);
		}
	}

	/// Clears all visibility data.
	public void ClearAll()
	{
		mAllMeshes.Clear();
		mVisibleMeshes.Clear();
		mAllLights.Clear();
		mVisibleLights.Clear();
		mAllParticleEmitters.Clear();
		mVisibleParticleEmitters.Clear();
		mOpaqueMeshes.Clear();
		mTransparentMeshes.Clear();
		mShadowCasters.Clear();
	}

	/// Selects LOD level based on distance.
	private void SelectLOD(StaticMeshProxy* mesh, Vector3 cameraPos)
	{
		if (mesh.MaxLOD == 0)
		{
			mesh.LODLevel = 0;
			return;
		}

		// Simple distance-based LOD selection
		// LOD thresholds: 10, 30, 60, 100, ... units
		float distance = mesh.DistanceToCamera;

		if (distance < 10.0f)
			mesh.LODLevel = 0;
		else if (distance < 30.0f)
			mesh.LODLevel = Math.Min((uint8)1, mesh.MaxLOD);
		else if (distance < 60.0f)
			mesh.LODLevel = Math.Min((uint8)2, mesh.MaxLOD);
		else if (distance < 100.0f)
			mesh.LODLevel = Math.Min((uint8)3, mesh.MaxLOD);
		else
			mesh.LODLevel = mesh.MaxLOD;
	}

	/// Generates a sort key for efficient state-based sorting.
	/// Key format: [material(16)] [mesh(16)] [depth(32)]
	private void GenerateSortKey(StaticMeshProxy* mesh)
	{
		// For opaque: sort by material, then mesh (minimize state changes)
		// For transparent: sort by depth only (back to front)

		uint64 key = 0;

		if (!mesh.IsTransparent)
		{
			// Opaque: material ID (high bits) + mesh handle (low bits)
			uint64 materialKey = (mesh.MaterialCount > 0) ? (uint64)mesh.MaterialIds[0] : 0;
			uint64 meshKey = (uint64)mesh.MeshHandle.Index;
			key = (materialKey << 48) | (meshKey << 32);

			// Add depth as tie-breaker (front-to-back)
			uint32 depthBits = *(uint32*)&mesh.DistanceToCamera;
			key |= depthBits;
		}
		else
		{
			// Transparent: depth only (inverted for back-to-front)
			float invDist = 1000000.0f - mesh.DistanceToCamera;
			uint32 depthBits = *(uint32*)&invDist;
			key = depthBits;
		}

		mesh.SortKey = key;
	}

	/// Sorts opaque meshes front-to-back for minimal overdraw.
	private void SortOpaqueFrontToBack()
	{
		// Sort by sort key (ascending)
		mOpaqueMeshes.Sort(scope (a, b) =>
		{
			if (a.SortKey < b.SortKey) return -1;
			if (a.SortKey > b.SortKey) return 1;
			return 0;
		});
	}

	/// Sorts transparent meshes back-to-front for correct blending.
	private void SortTransparentBackToFront()
	{
		// Sort by distance (descending)
		mTransparentMeshes.Sort(scope (a, b) =>
		{
			if (a.DistanceToCamera > b.DistanceToCamera) return -1;
			if (a.DistanceToCamera < b.DistanceToCamera) return 1;
			return 0;
		});
	}

	/// Sorts particle emitters back-to-front for correct alpha blending.
	private void SortParticleEmittersBackToFront()
	{
		// Sort by distance (descending)
		mVisibleParticleEmitters.Sort(scope (a, b) =>
		{
			if (a.DistanceToCamera > b.DistanceToCamera) return -1;
			if (a.DistanceToCamera < b.DistanceToCamera) return 1;
			return 0;
		});
	}

	// ==================== Statistics ====================

	/// Number of meshes culled this frame.
	public int32 CulledMeshCount => (int32)(mAllMeshes.Count - mVisibleMeshes.Count);

	/// Number of visible meshes.
	public int32 VisibleMeshCount => (int32)mVisibleMeshes.Count;

	/// Number of opaque draw calls.
	public int32 OpaqueDrawCount => (int32)mOpaqueMeshes.Count;

	/// Number of transparent draw calls.
	public int32 TransparentDrawCount => (int32)mTransparentMeshes.Count;

	/// Number of visible lights.
	public int32 VisibleLightCount => (int32)mVisibleLights.Count;

	/// Number of particle emitters culled this frame.
	public int32 CulledParticleEmitterCount => (int32)(mAllParticleEmitters.Count - mVisibleParticleEmitters.Count);

	/// Number of visible particle emitters.
	public int32 VisibleParticleEmitterCount => (int32)mVisibleParticleEmitters.Count;

	/// Which plane caused culling (debug, 0=left,1=right,2=bottom,3=top,4=near,5=far,-1=none)
	public int32 CullingPlane => mCuller.LastCullingPlane;
}

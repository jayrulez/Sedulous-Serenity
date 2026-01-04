namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Manages visibility determination and draw call sorting.
class VisibilityResolver
{
	private FrustumCuller mCuller = new .() ~ delete _;

	// Temporary lists for visibility processing
	private List<MeshProxy*> mAllMeshes = new .() ~ delete _;
	private List<MeshProxy*> mVisibleMeshes = new .() ~ delete _;
	private List<LightProxy*> mAllLights = new .() ~ delete _;
	private List<LightProxy*> mVisibleLights = new .() ~ delete _;

	// Output lists
	private List<MeshProxy*> mOpaqueMeshes = new .() ~ delete _;
	private List<MeshProxy*> mTransparentMeshes = new .() ~ delete _;
	private List<MeshProxy*> mShadowCasters = new .() ~ delete _;

	/// Gets opaque meshes (front-to-back sorted).
	public List<MeshProxy*> OpaqueMeshes => mOpaqueMeshes;

	/// Gets transparent meshes (back-to-front sorted).
	public List<MeshProxy*> TransparentMeshes => mTransparentMeshes;

	/// Gets shadow-casting meshes.
	public List<MeshProxy*> ShadowCasters => mShadowCasters;

	/// Gets visible lights.
	public List<LightProxy*> VisibleLights => mVisibleLights;

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
		world.GetValidMeshProxies(mAllMeshes);
		world.GetValidLightProxies(mAllLights);

		// Cull meshes
		mCuller.CullMeshes(mAllMeshes, mVisibleMeshes, camera.Position);

		// Cull lights
		mCuller.CullLights(mAllLights, mVisibleLights);

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

	/// Clears all visibility data.
	public void ClearAll()
	{
		mAllMeshes.Clear();
		mVisibleMeshes.Clear();
		mAllLights.Clear();
		mVisibleLights.Clear();
		mOpaqueMeshes.Clear();
		mTransparentMeshes.Clear();
		mShadowCasters.Clear();
	}

	/// Selects LOD level based on distance.
	private void SelectLOD(MeshProxy* mesh, Vector3 cameraPos)
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
	private void GenerateSortKey(MeshProxy* mesh)
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

	/// Which plane caused culling (debug, 0=left,1=right,2=bottom,3=top,4=near,5=far,-1=none)
	public int32 CullingPlane => mCuller.LastCullingPlane;
}

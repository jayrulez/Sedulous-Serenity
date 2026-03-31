namespace Sedulous.Renderer;

using System;

/// Individual draw command before batching.
[CRepr]
struct DrawCommand
{
	/// GPU mesh to draw.
	public GPUMeshHandle MeshHandle;
	/// Material instance for this draw.
	public MaterialInstanceHandle MaterialHandle;
	/// Proxy handle for retrieving the transform.
	public ProxyHandle ProxyHandle;
	/// Which submesh within the mesh to draw.
	public uint32 SubMeshIndex;
	/// Selected LOD level.
	public uint8 LODLevel;
	/// Squared distance from camera.
	public float DistanceSq;
	/// Composite sort key.
	public uint64 SortKey;
}

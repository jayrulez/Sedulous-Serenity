namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

/// LOD level descriptor within a GPU mesh.
/// Each LOD selects a contiguous range of submeshes.
/// All LODs share the same vertex/index buffer.
public struct GPUMeshLOD
{
	/// First submesh index for this LOD.
	public uint32 SubMeshStart;
	/// Number of submeshes in this LOD.
	public uint32 SubMeshCount;
}

/// A submesh within a GPU mesh.
public struct GPUSubMesh
{
	/// Start index in the index buffer.
	public uint32 IndexStart;
	/// Number of indices (or vertices for non-indexed meshes).
	public uint32 IndexCount;
	/// Base vertex offset.
	public int32 BaseVertex;
	/// Material slot index.
	public uint32 MaterialSlot;
}

/// GPU-side mesh data.
public class GPUMesh
{
	/// Vertex buffer.
	public IBuffer VertexBuffer;
	/// Index buffer (null for non-indexed meshes).
	public IBuffer IndexBuffer;
	/// Vertex count.
	public uint32 VertexCount;
	/// Index count (0 for non-indexed meshes).
	public uint32 IndexCount;
	/// Vertex stride in bytes.
	public uint32 VertexStride;
	/// Index format.
	public IndexFormat IndexFormat;
	/// Submeshes.
	public GPUSubMesh[] SubMeshes ~ delete _;
	/// Local-space bounding box.
	public BoundingBox Bounds;
	/// Reference count.
	public int32 RefCount;
	/// Generation for handle validation.
	public uint32 Generation;
	/// Whether this slot is in use.
	public bool IsActive;
	/// Whether this mesh has skinning vertex data.
	public bool IsSkinned;
	/// LOD level descriptors. Null means single LOD using all submeshes.
	public GPUMeshLOD[] LODLevels ~ delete _;
	/// Number of LOD levels (0 = single LOD).
	public uint32 LODCount;

	/// Frees GPU resources. Device destroys are handled by the resource manager.
	public void Release(IDevice device)
	{
		if (VertexBuffer != null)
			device.DestroyBuffer(ref VertexBuffer);
		if (IndexBuffer != null)
			device.DestroyBuffer(ref IndexBuffer);
		DeleteAndNullify!(SubMeshes);
		DeleteAndNullify!(LODLevels);
		LODCount = 0;
		IsActive = false;
	}
}

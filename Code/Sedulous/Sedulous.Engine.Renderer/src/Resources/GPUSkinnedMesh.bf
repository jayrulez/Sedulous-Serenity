namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// GPU-side skinned mesh with vertex, index, and bone buffers.
class GPUSkinnedMesh
{
	/// Vertex buffer containing skinned vertex data.
	public IBuffer VertexBuffer;

	/// Index buffer (optional, null for non-indexed meshes).
	public IBuffer IndexBuffer;

	/// Number of indices in the index buffer.
	public uint32 IndexCount;

	/// Index format (UInt16 or UInt32).
	public IndexFormat IndexFormat = .UInt32;

	/// Number of vertices.
	public uint32 VertexCount;

	/// Stride of each vertex in bytes (72 for SkinnedVertex).
	public uint32 VertexStride = 72;

	/// Number of bones/joints in the skeleton.
	public uint32 BoneCount;

	/// Bounding box in local space.
	public BoundingBox Bounds;

	/// Reference count for resource management.
	private int32 mRefCount = 1;

	public this()
	{
	}

	public ~this()
	{
		if (VertexBuffer != null) delete VertexBuffer;
		if (IndexBuffer != null) delete IndexBuffer;
	}

	/// Adds a reference.
	public void AddRef()
	{
		mRefCount++;
	}

	/// Releases a reference. Returns true if the object should be deleted.
	public bool Release()
	{
		mRefCount--;
		return mRefCount <= 0;
	}
}

/// Handle to a GPU skinned mesh resource.
struct GPUSkinnedMeshHandle
{
	public uint32 Index;
	public uint32 Generation;

	public this(uint32 index, uint32 generation)
	{
		Index = index;
		Generation = generation;
	}

	public bool IsValid => Index != uint32.MaxValue;

	public static GPUSkinnedMeshHandle Invalid => .(uint32.MaxValue, 0);
}

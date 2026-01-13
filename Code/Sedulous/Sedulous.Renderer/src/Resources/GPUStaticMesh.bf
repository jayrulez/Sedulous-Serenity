namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Mathematics;

/// GPU-side mesh data with vertex and index buffers.
class GPUStaticMesh
{
	/// Vertex buffer containing all vertex data.
	public IBuffer VertexBuffer ~ delete _;

	/// Index buffer (null for non-indexed draws).
	public IBuffer IndexBuffer ~ delete _;

	/// Size of a single vertex in bytes.
	public uint32 VertexStride;

	/// Number of vertices.
	public uint32 VertexCount;

	/// Number of indices (0 for non-indexed).
	public uint32 IndexCount;

	/// Index format (UInt16 or UInt32).
	public IndexFormat IndexFormat;

	/// Sub-meshes for multi-material rendering.
	public SubMesh[] SubMeshes ~ delete _;

	/// Bounding box of the mesh.
	public BoundingBox Bounds;

	/// Reference count for resource management.
	public int32 RefCount = 1;

	public this()
	{
	}

	/// Increments reference count.
	public void AddRef()
	{
		RefCount++;
	}

	/// Decrements reference count. Returns true if resource should be freed.
	public bool Release()
	{
		RefCount--;
		return RefCount <= 0;
	}
}

/// Handle to a GPU mesh resource.
struct GPUStaticMeshHandle : IEquatable<GPUStaticMeshHandle>, IHashable
{
	private uint32 mIndex;
	private uint32 mGeneration;

	public static readonly Self Invalid = .((uint32)-1, 0);

	public uint32 Index => mIndex;
	public uint32 Generation => mGeneration;
	public bool IsValid => mIndex != (uint32)-1;

	public this(uint32 index, uint32 generation)
	{
		mIndex = index;
		mGeneration = generation;
	}

	public bool Equals(GPUStaticMeshHandle other)
	{
		return mIndex == other.mIndex && mGeneration == other.mGeneration;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ (mGeneration << 16));
	}
}

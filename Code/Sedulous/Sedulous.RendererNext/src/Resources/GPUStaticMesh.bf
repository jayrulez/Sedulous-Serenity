namespace Sedulous.RendererNext;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Geometry;

/// GPU-side static mesh with vertex and index buffers.
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
	public IndexFormat IndexFormat = .UInt32;

	/// Sub-meshes for multi-material rendering.
	public SubMesh[] SubMeshes ~ delete _;

	/// Bounding box of the mesh.
	public BoundingBox Bounds;

	/// Reference count for resource management.
	private int32 mRefCount = 1;

	public this()
	{
	}

	/// Increments reference count.
	public void AddRef()
	{
		mRefCount++;
	}

	/// Decrements reference count. Returns true if resource should be freed.
	public bool Release()
	{
		mRefCount--;
		return mRefCount <= 0;
	}

	/// Current reference count.
	public int32 RefCount => mRefCount;

	/// Whether this mesh uses indexed rendering.
	public bool IsIndexed => IndexBuffer != null && IndexCount > 0;

	/// Number of sub-meshes.
	public int32 SubMeshCount => SubMeshes != null ? (int32)SubMeshes.Count : 0;
}

/// Handle to a GPU static mesh resource.
struct GPUStaticMeshHandle : IEquatable<GPUStaticMeshHandle>, IHashable
{
	private uint32 mIndex;
	private uint32 mGeneration;

	public static readonly Self Invalid = .(uint32.MaxValue, 0);

	public uint32 Index => mIndex;
	public uint32 Generation => mGeneration;
	public bool IsValid => mIndex != uint32.MaxValue;

	public this(uint32 index, uint32 generation)
	{
		mIndex = index;
		mGeneration = generation;
	}

	public bool Equals(Self other)
	{
		return mIndex == other.mIndex && mGeneration == other.mGeneration;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ (mGeneration << 16));
	}

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}

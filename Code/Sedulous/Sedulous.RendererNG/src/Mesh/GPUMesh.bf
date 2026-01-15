namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Handle to a GPU mesh in the mesh pool.
struct MeshHandle : IHashable, IEquatable<MeshHandle>
{
	public uint32 Index;
	public uint32 Generation;

	public static readonly Self Invalid = .(uint32.MaxValue, 0);

	public this(uint32 index, uint32 generation)
	{
		Index = index;
		Generation = generation;
	}

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode() => (int)Index ^ ((int)Generation << 16);

	public bool Equals(Self other) => Index == other.Index && Generation == other.Generation;

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}

/// GPU-resident mesh data.
class GPUMesh
{
	/// Vertex buffer.
	public IBuffer VertexBuffer ~ delete _;

	/// Index buffer.
	public IBuffer IndexBuffer ~ delete _;

	/// Vertex layout type.
	public VertexLayoutType VertexLayout;

	/// Vertex count.
	public uint32 VertexCount;

	/// Index count.
	public uint32 IndexCount;

	/// Whether indices are 32-bit.
	public bool Use32BitIndices;

	/// Submeshes.
	public List<Submesh> Submeshes = new .() ~ delete _;

	/// Overall bounding box.
	public BoundingBox Bounds;

	/// Whether this is a skinned mesh.
	public bool IsSkinned;

	/// Bone count (for skinned meshes).
	public int BoneCount;

	/// Gets vertex stride.
	public uint32 VertexStride => VertexLayouts.GetStride(VertexLayout);

	/// Gets the index format for RHI.
	public IndexFormat IndexFormat => Use32BitIndices ? .UInt32 : .UInt16;

	/// Whether the mesh is valid for rendering.
	public bool IsValid => VertexBuffer != null && IndexBuffer != null && IndexCount > 0;
}

/// Slot in the mesh pool.
class MeshSlot
{
	public GPUMesh Mesh ~ delete _;
	public uint32 Generation;
	public bool InUse;
}

/// Pool for managing GPU meshes.
class MeshPool : IDisposable
{
	private IDevice mDevice;
	private List<MeshSlot> mSlots = new .() ~ {
		for (let slot in _)
			delete slot;
		delete _;
	};
	private List<uint32> mFreeList = new .() ~ delete _;

	/// Total meshes in pool.
	public int TotalCount => mSlots.Count;

	/// Active meshes.
	public int ActiveCount
	{
		get
		{
			int count = 0;
			for (let slot in mSlots)
				if (slot.InUse)
					count++;
			return count;
		}
	}

	/// Initializes the mesh pool.
	public void Initialize(IDevice device)
	{
		mDevice = device;
	}

	/// Allocates a new mesh slot.
	public Result<MeshHandle> Allocate()
	{
		uint32 index;
		uint32 generation;

		if (mFreeList.Count > 0)
		{
			index = mFreeList.PopBack();
			generation = mSlots[index].Generation + 1;
		}
		else
		{
			index = (uint32)mSlots.Count;
			generation = 1;
			mSlots.Add(new MeshSlot());
		}

		let slot = mSlots[index];
		if (slot.Mesh != null)
			delete slot.Mesh;
		slot.Mesh = new GPUMesh();
		slot.Generation = generation;
		slot.InUse = true;

		return MeshHandle(index, generation);
	}

	/// Gets the GPU mesh for a handle.
	public GPUMesh Get(MeshHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mSlots.Count)
			return null;

		let slot = mSlots[handle.Index];
		if (slot.Generation != handle.Generation || !slot.InUse)
			return null;

		return slot.Mesh;
	}

	/// Releases a mesh back to the pool.
	public void Release(MeshHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mSlots.Count)
			return;

		let slot = mSlots[handle.Index];
		if (slot.Generation != handle.Generation || !slot.InUse)
			return;

		slot.InUse = false;
		mFreeList.Add(handle.Index);
	}

	/// Clears all meshes.
	public void Clear()
	{
		for (let slot in mSlots)
		{
			if (slot.Mesh != null)
			{
				delete slot.Mesh;
				slot.Mesh = null;
			}
			slot.InUse = false;
		}
		mFreeList.Clear();
		for (uint32 i = 0; i < mSlots.Count; i++)
			mFreeList.Add(i);
	}

	/// Gets pool statistics.
	public void GetStats(String outStats)
	{
		outStats.AppendF("Mesh Pool:\n");
		outStats.AppendF("  Total slots: {}\n", mSlots.Count);
		outStats.AppendF("  Active: {}\n", ActiveCount);
		outStats.AppendF("  Free: {}\n", mFreeList.Count);
	}

	public void Dispose()
	{
		Clear();
	}
}

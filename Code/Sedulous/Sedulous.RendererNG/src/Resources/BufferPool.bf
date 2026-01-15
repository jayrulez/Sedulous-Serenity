namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;

/// Entry in the buffer pool.
struct BufferPoolEntry
{
	/// The GPU buffer (null if slot is free).
	public IBuffer Buffer;

	/// Current generation counter for this slot.
	public uint32 Generation;

	/// Size of the buffer in bytes.
	public uint32 Size;

	/// Buffer usage flags.
	public BufferUsage Usage;

	/// Debug name for the buffer.
	public String Name;
}

/// Pool for managing GPU buffer resources.
/// Uses generation-based handles for safe access.
class BufferPool
{
	private IDevice mDevice;
	private DeferredDeletionQueue mDeletionQueue;
	private List<BufferPoolEntry> mEntries = new .() ~ delete _;
	private List<uint32> mFreeList = new .() ~ delete _;

	/// Gets the number of allocated buffers.
	public int AllocatedCount
	{
		get
		{
			int count = 0;
			for (let entry in mEntries)
			{
				if (entry.Buffer != null)
					count++;
			}
			return count;
		}
	}

	/// Gets the total number of slots (allocated + free).
	public int TotalSlots => mEntries.Count;

	/// Gets the number of free slots.
	public int FreeSlots => mFreeList.Count;

	public this(IDevice device, DeferredDeletionQueue deletionQueue, int32 initialCapacity = 0)
	{
		mDevice = device;
		mDeletionQueue = deletionQueue;

		if (initialCapacity > 0)
		{
			mEntries.Reserve(initialCapacity);
			mFreeList.Reserve(initialCapacity);
		}
	}

	public ~this()
	{
		// Delete all buffer names
		for (var entry in ref mEntries)
		{
			if (entry.Name != null)
				delete entry.Name;
		}
	}

	/// Creates a new GPU buffer and returns a handle to it.
	/// @param size Size in bytes.
	/// @param usage Buffer usage flags.
	/// @param name Optional debug name.
	/// @returns Handle to the created buffer, or Invalid on failure.
	public BufferHandle Create(uint32 size, BufferUsage usage, StringView name = "")
	{
		// Create the GPU buffer
		BufferDescriptor desc = .(size, usage);
		let result = mDevice.CreateBuffer(&desc);
		if (result case .Err)
			return .Invalid;

		let buffer = result.Value;

		// Find or create a slot
		uint32 index;
		uint32 generation;

		if (mFreeList.Count > 0)
		{
			// Reuse a free slot
			index = mFreeList.PopBack();
			generation = mEntries[index].Generation; // Keep existing generation (already incremented when freed)

			var entry = ref mEntries[index];
			entry.Buffer = buffer;
			entry.Size = size;
			entry.Usage = usage;
			if (!name.IsEmpty)
			{
				if (entry.Name == null)
					entry.Name = new String(name);
				else
					entry.Name.Set(name);
			}
		}
		else
		{
			// Allocate a new slot
			index = (uint32)mEntries.Count;
			generation = 1; // Start at generation 1

			BufferPoolEntry entry = .();
			entry.Buffer = buffer;
			entry.Generation = generation;
			entry.Size = size;
			entry.Usage = usage;
			if (!name.IsEmpty)
				entry.Name = new String(name);

			mEntries.Add(entry);
		}

		return .(index, generation);
	}

	/// Creates a buffer with initial data.
	/// @param data Initial data to upload.
	/// @param usage Buffer usage flags.
	/// @param name Optional debug name.
	/// @returns Handle to the created buffer, or Invalid on failure.
	public BufferHandle CreateWithData<T>(Span<T> data, BufferUsage usage, StringView name = "") where T : struct
	{
		uint32 size = (uint32)(data.Length * sizeof(T));

		// Create buffer descriptor with initial data
		BufferDescriptor desc = .(size, usage | .CopyDst);
		let result = mDevice.CreateBuffer(&desc);
		if (result case .Err)
			return .Invalid;

		let buffer = result.Value;

		// Upload initial data via mapped memory
		if (let ptr = buffer.Map())
		{
			Internal.MemCpy(ptr, data.Ptr, size);
			buffer.Unmap();
		}

		// Find or create a slot
		uint32 index;
		uint32 generation;

		if (mFreeList.Count > 0)
		{
			index = mFreeList.PopBack();
			generation = mEntries[index].Generation;

			var entry = ref mEntries[index];
			entry.Buffer = buffer;
			entry.Size = size;
			entry.Usage = usage;
			if (!name.IsEmpty)
			{
				if (entry.Name == null)
					entry.Name = new String(name);
				else
					entry.Name.Set(name);
			}
		}
		else
		{
			index = (uint32)mEntries.Count;
			generation = 1;

			BufferPoolEntry entry = .();
			entry.Buffer = buffer;
			entry.Generation = generation;
			entry.Size = size;
			entry.Usage = usage;
			if (!name.IsEmpty)
				entry.Name = new String(name);

			mEntries.Add(entry);
		}

		return .(index, generation);
	}

	/// Gets the buffer for a handle.
	/// Returns null if the handle is invalid or the generation doesn't match.
	public IBuffer Get(BufferHandle handle)
	{
		if (!handle.HasValidIndex)
			return null;

		if (handle.Index >= (uint32)mEntries.Count)
			return null;

		let entry = mEntries[handle.Index];
		if (entry.Generation != handle.Generation)
			return null; // Stale handle

		return entry.Buffer;
	}

	/// Checks if a handle is valid (points to an existing buffer).
	public bool IsValid(BufferHandle handle)
	{
		return Get(handle) != null;
	}

	/// Gets the size of a buffer.
	/// Returns 0 if the handle is invalid.
	public uint32 GetSize(BufferHandle handle)
	{
		if (!handle.HasValidIndex || handle.Index >= (uint32)mEntries.Count)
			return 0;

		let entry = mEntries[handle.Index];
		if (entry.Generation != handle.Generation)
			return 0;

		return entry.Size;
	}

	/// Gets the usage flags of a buffer.
	public BufferUsage GetUsage(BufferHandle handle)
	{
		if (!handle.HasValidIndex || handle.Index >= (uint32)mEntries.Count)
			return .None;

		let entry = mEntries[handle.Index];
		if (entry.Generation != handle.Generation)
			return .None;

		return entry.Usage;
	}

	/// Releases a buffer. The buffer will be queued for deferred deletion.
	/// The handle becomes invalid after this call.
	public void Release(BufferHandle handle)
	{
		if (!handle.HasValidIndex)
			return;

		if (handle.Index >= (uint32)mEntries.Count)
			return;

		var entry = ref mEntries[handle.Index];
		if (entry.Generation != handle.Generation)
			return; // Already released or stale

		// Queue the buffer for deferred deletion
		if (entry.Buffer != null)
		{
			mDeletionQueue.QueueBuffer(entry.Buffer);
			entry.Buffer = null;
		}

		// Increment generation so existing handles become invalid
		entry.Generation++;

		// Add to free list for reuse
		mFreeList.Add(handle.Index);
	}

	/// Immediately destroys all buffers without deferring deletion.
	/// Use only during shutdown when the GPU is guaranteed to be idle.
	public void DestroyAll()
	{
		for (var entry in ref mEntries)
		{
			if (entry.Buffer != null)
			{
				delete entry.Buffer;
				entry.Buffer = null;
			}
			entry.Generation++;
		}
		mFreeList.Clear();

		// Rebuild free list with all slots
		for (uint32 i = 0; i < (uint32)mEntries.Count; i++)
		{
			mFreeList.Add(i);
		}
	}
}

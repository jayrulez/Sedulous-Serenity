namespace Sedulous.RendererNG;

using System;
using System.Collections;

/// Entry in a proxy pool.
struct ProxyPoolEntry<T> where T : struct
{
	/// The proxy data (default if slot is free).
	public T Proxy;

	/// Current generation counter for this slot.
	public uint32 Generation;

	/// Whether this slot is currently in use.
	public bool InUse;
}

/// Generic pool for managing render proxies.
/// Uses generation-based handles for safe access.
class ProxyPool<T> where T : struct
{
	private List<ProxyPoolEntry<T>> mEntries = new .() ~ delete _;
	private List<uint32> mFreeList = new .() ~ delete _;

	/// Gets the number of active proxies.
	public int AllocatedCount
	{
		get
		{
			int count = 0;
			for (let entry in mEntries)
			{
				if (entry.InUse)
					count++;
			}
			return count;
		}
	}

	/// Gets the total number of slots.
	public int TotalSlots => mEntries.Count;

	/// Gets the number of free slots.
	public int FreeSlots => mFreeList.Count;

	public this(int32 initialCapacity = 0)
	{
		if (initialCapacity > 0)
		{
			mEntries.Reserve(initialCapacity);
			mFreeList.Reserve(initialCapacity);
		}
	}

	/// Creates a new proxy and returns a handle to it.
	/// The proxy is default-initialized.
	public ProxyHandle<T> Create()
	{
		uint32 index;
		uint32 generation;

		if (mFreeList.Count > 0)
		{
			// Reuse a free slot
			index = mFreeList.PopBack();
			generation = mEntries[index].Generation;

			var entry = ref mEntries[index];
			entry.Proxy = default;
			entry.InUse = true;
		}
		else
		{
			// Allocate a new slot
			index = (uint32)mEntries.Count;
			generation = 1;

			ProxyPoolEntry<T> entry = .();
			entry.Generation = generation;
			entry.InUse = true;
			mEntries.Add(entry);
		}

		return .(index, generation);
	}

	/// Creates a new proxy with initial data and returns a handle to it.
	public ProxyHandle<T> Create(T initialData)
	{
		let handle = Create();
		if (handle.HasValidIndex)
		{
			var ptr = GetPtr(handle);
			if (ptr != null)
				*ptr = initialData;
		}
		return handle;
	}

	/// Gets a pointer to the proxy for a handle.
	/// Returns null if the handle is invalid or stale.
	public T* GetPtr(ProxyHandle<T> handle)
	{
		if (!handle.HasValidIndex)
			return null;

		if (handle.Index >= (uint32)mEntries.Count)
			return null;

		var entry = ref mEntries[handle.Index];
		if (entry.Generation != handle.Generation || !entry.InUse)
			return null;

		return &entry.Proxy;
	}

	/// Gets a copy of the proxy for a handle.
	/// Returns default if the handle is invalid.
	public T Get(ProxyHandle<T> handle)
	{
		let ptr = GetPtr(handle);
		return ptr != null ? *ptr : default;
	}

	/// Checks if a handle is valid (points to an existing proxy).
	public bool IsValid(ProxyHandle<T> handle)
	{
		return GetPtr(handle) != null;
	}

	/// Destroys a proxy. The handle becomes invalid after this call.
	public void Destroy(ProxyHandle<T> handle)
	{
		if (!handle.HasValidIndex)
			return;

		if (handle.Index >= (uint32)mEntries.Count)
			return;

		var entry = ref mEntries[handle.Index];
		if (entry.Generation != handle.Generation || !entry.InUse)
			return;

		// Clear the proxy data
		entry.Proxy = default;
		entry.InUse = false;

		// Increment generation so existing handles become invalid
		entry.Generation++;

		// Add to free list for reuse
		mFreeList.Add(handle.Index);
	}

	/// Clears all proxies from the pool.
	public void Clear()
	{
		for (var entry in ref mEntries)
		{
			if (entry.InUse)
			{
				entry.Proxy = default;
				entry.InUse = false;
				entry.Generation++;
			}
		}

		mFreeList.Clear();

		// Rebuild free list with all slots
		for (uint32 i = 0; i < (uint32)mEntries.Count; i++)
		{
			mFreeList.Add(i);
		}
	}

	/// Iterates over all active proxies.
	/// Callback receives the handle and a pointer to the proxy.
	public void ForEach(delegate void(ProxyHandle<T> handle, T* proxy) callback)
	{
		for (uint32 i = 0; i < (uint32)mEntries.Count; i++)
		{
			var entry = ref mEntries[i];
			if (entry.InUse)
			{
				let handle = ProxyHandle<T>(i, entry.Generation);
				callback(handle, &entry.Proxy);
			}
		}
	}

	/// Iterates over all active proxies (read-only).
	/// Callback receives the handle and a copy of the proxy.
	public void ForEachReadOnly(delegate void(ProxyHandle<T> handle, T proxy) callback)
	{
		for (uint32 i = 0; i < (uint32)mEntries.Count; i++)
		{
			let entry = mEntries[i];
			if (entry.InUse)
			{
				let handle = ProxyHandle<T>(i, entry.Generation);
				callback(handle, entry.Proxy);
			}
		}
	}
}

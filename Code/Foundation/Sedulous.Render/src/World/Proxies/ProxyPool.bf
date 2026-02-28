namespace Sedulous.Render;

using System;
using System.Collections;

/// Callback for iterating over active proxies.
public delegate void ProxyCallback<T>(ProxyHandle handle, ref T proxy) where T : struct;

/// Pool of proxy objects with handle-based access.
/// Supports efficient iteration and slot recycling.
public class ProxyPool<T> where T : struct
{
	private List<T> mProxies = new .() ~ delete _;
	private List<uint32> mGenerations = new .() ~ delete _;
	private List<int32> mFreeList = new .() ~ delete _;
	private int32 mActiveCount = 0;

	/// Gets the number of active proxies.
	public int32 ActiveCount => mActiveCount;

	/// Gets the total capacity.
	public int32 Capacity => (int32)mProxies.Count;

	/// Allocates a new proxy and returns its handle.
	public ProxyHandle Allocate()
	{
		uint32 index;
		uint32 generation;

		if (mFreeList.Count > 0)
		{
			// Reuse a freed slot
			index = (uint32)mFreeList.PopBack();
			generation = mGenerations[(int)index];
		}
		else
		{
			// Allocate new slot
			index = (uint32)mProxies.Count;
			mProxies.Add(default);
			mGenerations.Add(1);
			generation = 1;
		}

		mActiveCount++;

		return .()
		{
			Index = index,
			Generation = generation
		};
	}

	/// Frees a proxy by handle.
	public void Free(ProxyHandle handle)
	{
		if (!IsValid(handle))
			return;

		// Increment generation to invalidate existing handles
		mGenerations[(int)handle.Index]++;
		mFreeList.Add((int32)handle.Index);
		mActiveCount--;
	}

	/// Checks if a handle is valid.
	public bool IsValid(ProxyHandle handle)
	{
		if (handle.Index >= mProxies.Count)
			return false;
		return mGenerations[(int)handle.Index] == handle.Generation;
	}

	/// Gets a reference to a proxy by handle.
	public T* Get(ProxyHandle handle)
	{
		if (!IsValid(handle))
			return null;
		return &mProxies[(int)handle.Index];
	}

	/// Gets a mutable reference to a proxy by handle.
	public ref T GetRef(ProxyHandle handle)
	{
		Runtime.Assert(IsValid(handle), "Invalid proxy handle");
		return ref mProxies[(int)handle.Index];
	}

	/// Tries to get a proxy by handle.
	public bool TryGet(ProxyHandle handle, out T* proxy)
	{
		if (!IsValid(handle))
		{
			proxy = null;
			return false;
		}
		proxy = &mProxies[(int)handle.Index];
		return true;
	}

	/// Iterates over all active proxies.
	/// Note: This iterates over all slots, checking validity.
	public void ForEach(ProxyCallback<T> callback)
	{
		for (int32 i = 0; i < mProxies.Count; i++)
		{
			let generation = mGenerations[i];
			// Check if slot is active (not in free list)
			bool isFree = false;
			for (let freeIdx in mFreeList)
			{
				if (freeIdx == i)
				{
					isFree = true;
					break;
				}
			}

			if (!isFree)
			{
				let handle = ProxyHandle() { Index = (uint32)i, Generation = generation };
				callback(handle, ref mProxies[i]);
			}
		}
	}

	/// Clears all proxies.
	public void Clear()
	{
		mProxies.Clear();
		mGenerations.Clear();
		mFreeList.Clear();
		mActiveCount = 0;
	}

	/// Reserves capacity for proxies.
	public void Reserve(int32 capacity)
	{
		mProxies.Reserve(capacity);
		mGenerations.Reserve(capacity);
	}
}

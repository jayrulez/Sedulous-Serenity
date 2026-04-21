namespace Sedulous.Render;

using System;
using System.Collections;

/// Callback for iterating over active proxies.
public delegate void RenderPoolCallback<T>(RenderHandle handle, ref T proxy) where T : struct;

/// Pool of proxy objects with handle-based access.
/// Supports efficient iteration and slot recycling.
public class RenderPool<T> where T : struct
{
	private List<T> mProxies = new .() ~ delete _;
	private List<uint32> mGenerations = new .() ~ delete _;
	private List<bool> mActive = new .() ~ delete _;
	private List<int32> mFreeList = new .() ~ delete _;
	private int32 mActiveCount = 0;

	/// Gets the number of active proxies.
	public int32 ActiveCount => mActiveCount;

	/// Gets the total capacity.
	public int32 Capacity => (int32)mProxies.Count;

	/// Allocates a new proxy and returns its handle.
	public RenderHandle Allocate()
	{
		uint32 index;
		uint32 generation;

		if (mFreeList.Count > 0)
		{
			// Reuse a freed slot
			index = (uint32)mFreeList.PopBack();
			generation = mGenerations[(int)index];
			mActive[(int)index] = true;
		}
		else
		{
			// Allocate new slot
			index = (uint32)mProxies.Count;
			mProxies.Add(default);
			mGenerations.Add(1);
			mActive.Add(true);
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
	public void Free(RenderHandle handle)
	{
		if (!IsValid(handle))
			return;

		// Increment generation to invalidate existing handles
		mGenerations[(int)handle.Index]++;
		mActive[(int)handle.Index] = false;
		mFreeList.Add((int32)handle.Index);
		mActiveCount--;
	}

	/// Checks if a handle is valid.
	public bool IsValid(RenderHandle handle)
	{
		if (handle.Index >= mProxies.Count)
			return false;
		return mGenerations[(int)handle.Index] == handle.Generation;
	}

	/// Gets a reference to a proxy by handle.
	public T* Get(RenderHandle handle)
	{
		if (!IsValid(handle))
			return null;
		return &mProxies[(int)handle.Index];
	}

	/// Gets a mutable reference to a proxy by handle.
	public ref T GetRef(RenderHandle handle)
	{
		Runtime.Assert(IsValid(handle), "Invalid proxy handle");
		return ref mProxies[(int)handle.Index];
	}

	/// Tries to get a proxy by handle.
	public bool TryGet(RenderHandle handle, out T* proxy)
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
	public void ForEach(RenderPoolCallback<T> callback)
	{
		for (int32 i = 0; i < mProxies.Count; i++)
		{
			if (!mActive[i])
				continue;

			let handle = RenderHandle() { Index = (uint32)i, Generation = mGenerations[i] };
			callback(handle, ref mProxies[i]);
		}
	}

	/// Clears all proxies.
	public void Clear()
	{
		mProxies.Clear();
		mGenerations.Clear();
		mActive.Clear();
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

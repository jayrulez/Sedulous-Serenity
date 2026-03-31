namespace Sedulous.Renderer;

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
	private List<bool> mActive = new .() ~ delete _;
	private List<int32> mFreeList = new .() ~ delete _;
	private int32 mActiveCount = 0;

	public int32 ActiveCount => mActiveCount;
	public int32 Capacity => (int32)mProxies.Count;

	public ProxyHandle Allocate()
	{
		uint32 index;
		uint32 generation;

		if (mFreeList.Count > 0)
		{
			index = (uint32)mFreeList.PopBack();
			generation = mGenerations[(int)index];
			mActive[(int)index] = true;
		}
		else
		{
			index = (uint32)mProxies.Count;
			mProxies.Add(default);
			mGenerations.Add(1);
			mActive.Add(true);
			generation = 1;
		}

		mActiveCount++;
		return .() { Index = index, Generation = generation };
	}

	public void Free(ProxyHandle handle)
	{
		if (!IsValid(handle))
			return;

		mGenerations[(int)handle.Index]++;
		mActive[(int)handle.Index] = false;
		mFreeList.Add((int32)handle.Index);
		mActiveCount--;
	}

	public bool IsValid(ProxyHandle handle)
	{
		if (handle.Index >= mProxies.Count)
			return false;
		return mGenerations[(int)handle.Index] == handle.Generation;
	}

	public T* Get(ProxyHandle handle)
	{
		if (!IsValid(handle))
			return null;
		return &mProxies[(int)handle.Index];
	}

	public ref T GetRef(ProxyHandle handle)
	{
		Runtime.Assert(IsValid(handle), "Invalid proxy handle");
		return ref mProxies[(int)handle.Index];
	}

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

	public void ForEach(ProxyCallback<T> callback)
	{
		for (int32 i = 0; i < mProxies.Count; i++)
		{
			if (!mActive[i])
				continue;

			let handle = ProxyHandle() { Index = (uint32)i, Generation = mGenerations[i] };
			callback(handle, ref mProxies[i]);
		}
	}

	public void Clear()
	{
		mProxies.Clear();
		mGenerations.Clear();
		mActive.Clear();
		mFreeList.Clear();
		mActiveCount = 0;
	}

	public void Reserve(int32 capacity)
	{
		mProxies.Reserve(capacity);
		mGenerations.Reserve(capacity);
	}
}

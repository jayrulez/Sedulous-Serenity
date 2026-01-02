using System;
using System.Threading;
using System.Collections;

namespace Sedulous.Resources;

/// Cache for loaded resources.
class ResourceCache
{
	private Monitor mMonitor = new .() ~ delete _;
	private Dictionary<ResourceCacheKey, ResourceHandle<IResource>> mResources = new .() ~ {
		for (var kv in _)
		{
			kv.key.Dispose();
		}
		delete _;
	};

	/// Caches a resource.
	public void Set(ResourceCacheKey key, ResourceHandle<IResource> handle)
	{
		using (mMonitor.Enter())
		{
			if (mResources.TryGetRefAlt(key, var keyPtr, var handlePtr))
			{
				// Replace existing - release old handle, reuse key
				var oldHandle = *handlePtr;
				oldHandle.Release();
				var h = handle;
				h.AddRef();
				*handlePtr = h;
			}
			else
			{
				// Clone the key so the cache owns its own copy
				var h = handle;
				h.AddRef();
				mResources[key.Clone()] = h;
			}
		}
	}

	/// Gets a cached resource by key.
	public ResourceHandle<IResource> Get(ResourceCacheKey key)
	{
		using (mMonitor.Enter())
		{
			if (mResources.TryGetValue(key, let handle))
				return handle;
			return default;
		}
	}

	/// Removes a resource from the cache.
	public void Remove(ResourceHandle<IResource> handle)
	{
		using (mMonitor.Enter())
		{
			for (var kv in mResources)
			{
				if (kv.value.Resource?.Id == handle.Resource?.Id)
				{
					var key = kv.key;
					mResources.Remove(key);
					key.Dispose();
					break;
				}
			}
		}
	}

	/// Removes a resource by key.
	public void Remove(ResourceCacheKey key)
	{
		using (mMonitor.Enter())
		{
			if (mResources.TryGetRefAlt(key, var keyPtr, var handlePtr))
			{
				var storedKey = *keyPtr;
				var handle = *handlePtr;
				mResources.Remove(key);
				storedKey.Dispose();
				handle.Release();
			}
		}
	}

	/// Clears all cached resources.
	public void Clear()
	{
		using (mMonitor.Enter())
		{
			for (var kv in mResources)
			{
				var handle = kv.value;
				handle.Release();
				kv.key.Dispose();
			}
			mResources.Clear();
		}
	}

	/// Gets the number of cached resources.
	public int Count
	{
		get
		{
			using (mMonitor.Enter())
				return mResources.Count;
		}
	}

	public void GetResources(List<ResourceHandle<IResource>> resources)
	{
		using (mMonitor.Enter())
			resources.AddRange(mResources.Values);
	}
}

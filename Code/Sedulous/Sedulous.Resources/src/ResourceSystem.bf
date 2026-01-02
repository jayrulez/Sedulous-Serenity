using System;
using System.Threading;
using System.Collections;
using Sedulous.Jobs;
using Sedulous.Logging.Abstractions;

namespace Sedulous.Resources;

/// Manages resource loading, caching, and lifecycle.
class ResourceSystem
{
	private readonly ILogger mLogger;
	private readonly JobSystem mJobSystem;

	private readonly Monitor mManagersMonitor = new .() ~ delete _;
	private readonly Dictionary<Type, IResourceManager> mManagers = new .() ~ delete _;
	private readonly ResourceCache mCache = new .() ~ delete _;

	/// Gets the resource cache.
	public ResourceCache Cache => mCache;

	public this(ILogger logger, JobSystem jobSystem)
	{
		mLogger = logger;
		mJobSystem = jobSystem;
	}

	public ~this()
	{
		Shutdown();
	}

	/// Initializes the resource system.
	public void Startup() { }

	/// Shuts down the resource system.
	public void Shutdown()
	{
		for (var resource in mCache.GetResources(.. scope .()))
		{
			if (let manager = GetManager(resource.Resource.GetType()))
			{
				manager.Unload(ref resource);
			}
		}
		mCache.Clear();
	}

	/// Updates the resource system.
	public void Update()
	{
	}

	/// Registers a resource manager.
	public void AddResourceManager(IResourceManager manager)
	{
		using (mManagersMonitor.Enter())
		{
			if (mManagers.ContainsKey(manager.ResourceType))
			{
				mLogger?.LogWarning("A resource manager has already been registered for type '{0}'.", manager.ResourceType.GetName(.. scope .()));
				return;
			}
			mManagers.Add(manager.ResourceType, manager);
		}
	}

	/// Unregisters a resource manager.
	public void RemoveResourceManager(IResourceManager manager)
	{
		using (mManagersMonitor.Enter())
		{
			if (mManagers.TryGet(manager.ResourceType, var type, ?))
				mManagers.Remove(type);
		}
	}

	/// Gets the manager for a resource type.
	private IResourceManager GetManager<T>() where T : IResource
	{
		using (mManagersMonitor.Enter())
		{
			if (mManagers.TryGetValue(typeof(T), let manager))
				return manager;
			return null;
		}
	}

	private IResourceManager GetManager(Type type)
	{
		using (mManagersMonitor.Enter())
		{
			if (mManagers.ContainsKey(type))
			{
				return mManagers[type];
			}

			return null;
		}
	}

	/// Adds an already-loaded resource to the system.
	public Result<ResourceHandle<T>, ResourceLoadError> AddResource<T>(T resource, bool cache = true) where T : IResource
	{
		let manager = GetManager<T>();
		if (manager == null)
			return .Err(.ManagerNotFound);

		var handle = ResourceHandle<IResource>(resource);

		if (cache)
		{
			String id = scope $"{resource.Id.ToString(.. scope .()):X}";
			var key = ResourceCacheKey(id, typeof(T));
			mCache.Set(key, handle);
		}

		return ResourceHandle<T>((T)handle.Resource);
	}

	/// Loads a resource synchronously.
	public Result<ResourceHandle<T>, ResourceLoadError> LoadResource<T>(
		StringView path,
		bool fromCache = true,
		bool cacheIfLoaded = true) where T : IResource
	{
		// Check cache first
		if (fromCache)
		{
			var key = ResourceCacheKey(path, typeof(T));
			defer key.Dispose();
			let handle = mCache.Get(key);
			if (handle.IsValid)
				return ResourceHandle<T>((T)handle.Resource);
		}

		// Get manager
		let manager = GetManager<T>();
		if (manager == null)
			return .Err(.ManagerNotFound);

		// Load resource
		let loadResult = manager.Load(path);
		if (loadResult case .Err(let error))
			return .Err(error);

		let handle = loadResult.Value;

		// Cache if requested
		if (cacheIfLoaded)
		{
			var key = ResourceCacheKey(path, typeof(T));
			mCache.Set(key, handle);
		}

		return ResourceHandle<T>((T)handle.Resource);
	}

	/// Loads a resource asynchronously.
	public Job<Result<ResourceHandle<T>, ResourceLoadError>> LoadResourceAsync<T>(
		StringView path,
		bool fromCache = true,
		bool cacheIfLoaded = true,
		delegate void(Result<ResourceHandle<T>, ResourceLoadError>) onCompleted = null,
		bool ownsDelegate = true) where T : IResource
	{
		let job = new LoadResourceJob<T>(this, path, fromCache, cacheIfLoaded, .AutoRelease, onCompleted, ownsDelegate);
		mJobSystem.AddJob(job);
		return job;
	}

	/// Unloads a resource.
	public void UnloadResource<T>(ref ResourceHandle<IResource> resource) where T : IResource
	{
		mCache.Remove(resource);

		if (resource.Resource?.RefCount > 1)
		{
			mLogger.LogWarning(scope $"Unloading resource '{resource.Resource.Id}' with RefCount {resource.Resource.RefCount}. Resource must be manually freed.");
		}

		let manager = GetManager<T>();
		if (manager != null)
			manager.Unload(ref resource);
		else
		{
			mLogger.LogWarning(scope $"ResourceManager for resource type '{resource.GetType().GetName(.. scope .())}' not found.");
		}

		resource.Release();
	}
}

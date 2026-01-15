using System;
using System.Collections;
using Sedulous.Jobs;
using Sedulous.Resources;
using Sedulous.Logging.Abstractions;

namespace Sedulous.Engine.Core;

/// Central access point for all subsystems.
/// Owns the core systems (JobSystem, ResourceSystem, SceneManager) and
/// provides type-keyed service registration.
class Context
{
	private ILogger mLogger;
	private JobSystem mJobSystem ~ delete _;
	private ResourceSystem mResourceSystem ~ delete _;
	private SceneManager mSceneManager ~ delete _;
	private ComponentRegistry mComponentRegistry ~ delete _;
	private Dictionary<Type, ContextService> mServices = new .() ~ delete _;
	private List<ContextService> mSortedServices = new .() ~ delete _;  // Sorted by UpdateOrder
	private bool mIsRunning = false;

	/// Gets the logger.
	public ILogger Logger => mLogger;

	/// Gets the job system.
	public JobSystem JobSystem => mJobSystem;

	/// Gets the resource system.
	public ResourceSystem ResourceSystem => mResourceSystem;

	/// Gets the scene manager.
	public SceneManager SceneManager => mSceneManager;

	/// Gets the component registry for entity components.
	public ComponentRegistry ComponentRegistry => mComponentRegistry;

	/// Returns true if the context is running.
	public bool IsRunning => mIsRunning;

	/// Creates a new context with the specified configuration.
	public this(ILogger logger, int32 workerThreads = 4)
	{
		mLogger = logger;

		// Use provided worker count (default to 4 threads)
		int32 workers = workerThreads;
		if (workers <= 0)
			workers = 4;

		mJobSystem = new .(logger, workers);
		mResourceSystem = new .(logger, mJobSystem);
		mComponentRegistry = new .();
		mSceneManager = new .(mComponentRegistry, this);
	}

	/// Registers a service with the context.
	/// Services are type-keyed and must extend ContextService.
	/// Services are updated in order based on their UpdateOrder property.
	public void RegisterService<T>(T service) where T : ContextService
	{
		let type = typeof(T);
		if (mServices.ContainsKey(type))
		{
			mLogger?.LogWarning("Service of type '{}' is already registered.", type.GetName(.. scope .()));
			return;
		}

		mServices[type] = service;
		RebuildSortedServiceList();
		service.OnRegister(this);

		if (mIsRunning)
			service.Startup();
	}

	/// Unregisters a service from the context.
	public void UnregisterService<T>() where T : ContextService
	{
		let type = typeof(T);
		if (mServices.TryGetValue(type, let service))
		{
			if (mIsRunning)
				service.Shutdown();
			service.OnUnregister();
			mServices.Remove(type);
			RebuildSortedServiceList();
		}
	}

	/// Gets a registered service by type.
	/// Returns null if the service is not registered.
	public T GetService<T>() where T : ContextService
	{
		if (mServices.TryGetValue(typeof(T), let service))
			return (T)service;
		return null;
	}

	/// Checks if a service is registered.
	public bool HasService<T>() where T : ContextService
	{
		return mServices.ContainsKey(typeof(T));
	}

	/// Starts up all subsystems.
	public void Startup()
	{
		if (mIsRunning)
			return;

		mLogger?.LogInformation("Context starting up...");

		mJobSystem.Startup();
		mResourceSystem.Startup();

		// Start all registered services (in UpdateOrder)
		for (let service in mSortedServices)
			service.Startup();

		mIsRunning = true;
		mLogger?.LogInformation("Context started.");
	}

	/// Updates all subsystems.
	public void Update(float deltaTime)
	{
		if (!mIsRunning)
			return;

		// Update job system (process completed jobs)
		mJobSystem.Update();

		// Update resource system
		mResourceSystem.Update();

		// Update services (in UpdateOrder - lower values first)
		for (let service in mSortedServices)
			service.Update(deltaTime);

		// Update scene manager (and active scene)
		mSceneManager.Update(deltaTime);
	}

	/// Shuts down all subsystems.
	public void Shutdown()
	{
		if (!mIsRunning)
			return;

		mLogger?.LogInformation("Context shutting down...");

		// Unload all scenes
		mSceneManager.UnloadAllScenes();

		// Shutdown services in reverse UpdateOrder (higher values first)
		for (int i = mSortedServices.Count - 1; i >= 0; i--)
			mSortedServices[i].Shutdown();

		// Shutdown core systems
		mResourceSystem.Shutdown();
		mJobSystem.Shutdown();

		mIsRunning = false;
		mLogger?.LogInformation("Context shutdown complete.");
	}

	// ==================== Internal Scene Notifications ====================

	/// Called by SceneManager when a scene is created.
	private void NotifyServicesSceneCreated(Scene scene)
	{
		for (let service in mSortedServices)
			service.OnSceneCreated(scene);
	}

	/// Called by SceneManager when a scene is being destroyed.
	private void NotifyServicesSceneDestroyed(Scene scene)
	{
		for (let service in mSortedServices)
			service.OnSceneDestroyed(scene);
	}

	// ==================== Internal Helpers ====================

	/// Rebuilds the sorted service list after registration changes.
	private void RebuildSortedServiceList()
	{
		mSortedServices.Clear();
		for (let service in mServices.Values)
			mSortedServices.Add(service);

		// Sort by UpdateOrder (lower values first)
		mSortedServices.Sort(scope (a, b) => a.UpdateOrder <=> b.UpdateOrder);
	}
}

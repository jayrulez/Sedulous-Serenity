namespace Sedulous.Engine.Physics;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.Physics;
using Sedulous.Physics.Jolt;

/// Context service that manages physics across all scenes.
/// Register this service with the Context to enable entity-based physics.
/// Automatically creates PhysicsSceneComponent for each scene.
class PhysicsService : ContextService, IDisposable
{
	private Context mContext;
	private bool mInitialized = false;

	// Configuration
	private PhysicsWorldDescriptor mWorldDescriptor = .Default;

	// Track created scene components and their physics worlds
	private List<PhysicsSceneComponent> mSceneComponents = new .() ~ delete _;
	private List<IPhysicsWorld> mPhysicsWorlds = new .() ~ delete _;

	// ==================== Properties ====================

	/// Gets whether the service has been initialized.
	public bool IsInitialized => mInitialized;

	/// Gets the world descriptor used for creating new physics worlds.
	public ref PhysicsWorldDescriptor WorldDescriptor => ref mWorldDescriptor;

	/// Gets all physics scene components created by this service.
	public Span<PhysicsSceneComponent> SceneComponents => mSceneComponents;

	// ==================== Configuration ====================

	/// Initializes the physics service.
	public Result<void> Initialize()
	{
		mInitialized = true;
		return .Ok;
	}

	/// Sets the gravity vector for new physics worlds.
	public void SetGravity(Vector3 gravity)
	{
		mWorldDescriptor.Gravity = gravity;
	}

	/// Sets the maximum number of bodies for new physics worlds.
	public void SetMaxBodies(uint32 maxBodies)
	{
		mWorldDescriptor.MaxBodies = maxBodies;
	}

	/// Configures the physics world descriptor.
	/// Must be called before scenes are created.
	public void Configure(PhysicsWorldDescriptor descriptor)
	{
		mWorldDescriptor = descriptor;
	}

	// ==================== Scene Access ====================

	/// Gets the physics world for a specific scene.
	public IPhysicsWorld GetPhysicsWorld(Scene scene)
	{
		for (let component in mSceneComponents)
		{
			if (component.Scene == scene)
				return component.PhysicsWorld;
		}
		return null;
	}

	/// Gets the PhysicsSceneComponent for a specific scene.
	public PhysicsSceneComponent GetSceneComponent(Scene scene)
	{
		for (let component in mSceneComponents)
		{
			if (component.Scene == scene)
				return component;
		}
		return null;
	}

	// ==================== Factory Methods ====================

	/// Creates a physics world with the current descriptor settings.
	/// Useful for creating worlds outside of scenes.
	public Result<IPhysicsWorld> CreatePhysicsWorld()
	{
		return CreatePhysicsWorld(mWorldDescriptor);
	}

	/// Creates a physics world with custom settings.
	public Result<IPhysicsWorld> CreatePhysicsWorld(PhysicsWorldDescriptor descriptor)
	{
		let result = JoltPhysicsWorld.Create(descriptor);
		if (result case .Err)
			return .Err;

		return .Ok(result.Get());
	}

	// ==================== ContextService Implementation ====================

	/// Called when the service is registered with the context.
	public override void OnRegister(Context context)
	{
		mContext = context;
	}

	/// Called when the service is unregistered from the context.
	public override void OnUnregister()
	{
		mContext = null;
	}

	/// Called during context startup.
	public override void Startup()
	{
		mInitialized = true;
	}

	/// Called during context shutdown.
	public override void Shutdown()
	{
		// Physics worlds and components are cleaned up via OnSceneDestroyed
		// and scene destruction
	}

	/// Called each frame during context update.
	/// Physics simulation is handled by PhysicsSceneComponent.OnUpdate.
	public override void Update(float deltaTime)
	{
		// Global physics service updates (if any) go here
		// Per-scene simulation is handled by PhysicsSceneComponent
	}

	/// Called when a scene is created.
	/// Automatically adds PhysicsSceneComponent to the scene.
	public override void OnSceneCreated(Scene scene)
	{
		// Create physics world for this scene
		let worldResult = JoltPhysicsWorld.Create(mWorldDescriptor);
		if (worldResult case .Err)
		{
			mContext?.Logger?.LogError("PhysicsService: Failed to create physics world for scene '{}'", scene.Name);
			return;
		}

		let physicsWorld = worldResult.Get();
		mPhysicsWorlds.Add(physicsWorld);

		// Create and add scene component
		let component = new PhysicsSceneComponent(physicsWorld);
		scene.AddSceneComponent(component);
		mSceneComponents.Add(component);

		mContext?.Logger?.LogDebug("PhysicsService: Added PhysicsSceneComponent to scene '{}'", scene.Name);
	}

	/// Called when a scene is being destroyed.
	/// Cleans up the physics world for this scene.
	///
	/// NOTE: This is called BEFORE the scene is deleted (and before entities are cleaned up).
	/// Entity components like RigidBodyComponent may still try to access the physics world
	/// during their OnDetach(). We must invalidate the world reference before deleting to
	/// prevent access to deleted memory.
	///
	/// TODO: The scene system needs a proper lifecycle with clear phases:
	///   1. OnSceneWillUnload - Services prepare for shutdown
	///   2. Scene cleans up entities (OnDetach called on entity components)
	///   3. Scene cleans up scene components
	///   4. OnSceneDidUnload - Services can safely delete resources
	/// Currently we work around this by invalidating references before deletion.
	public override void OnSceneDestroyed(Scene scene)
	{
		// Find and remove component belonging to this scene
		for (int i = mSceneComponents.Count - 1; i >= 0; i--)
		{
			let component = mSceneComponents[i];
			if (component.Scene == scene)
			{
				// Get the physics world before invalidating
				let world = component.PhysicsWorld;

				// Invalidate the component's reference BEFORE deleting the world
				// This prevents RigidBodyComponent.ClearShape() from accessing deleted memory
				component.InvalidatePhysicsWorld();

				mSceneComponents.RemoveAt(i);

				// Remove and delete the physics world
				for (int j = mPhysicsWorlds.Count - 1; j >= 0; j--)
				{
					if (mPhysicsWorlds[j] == world)
					{
						mPhysicsWorlds.RemoveAt(j);
						delete world;
						break;
					}
				}
				break;
			}
		}
	}

	// ==================== IDisposable Implementation ====================

	public void Dispose()
	{
		// Invalidate all component references before deleting worlds
		for (let component in mSceneComponents)
			component.InvalidatePhysicsWorld();

		// Clean up any remaining physics worlds
		for (let world in mPhysicsWorlds)
			delete world;
		mPhysicsWorlds.Clear();
		mSceneComponents.Clear();
	}
}

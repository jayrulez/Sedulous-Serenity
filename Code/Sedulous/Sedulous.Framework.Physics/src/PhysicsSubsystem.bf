namespace Sedulous.Framework.Physics;

using System;
using System.Collections;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;
using Sedulous.Physics;

/// Delegate for creating physics worlds. Allows backend injection.
/// Example: JoltPhysicsWorld.Create
delegate Result<IPhysicsWorld> PhysicsWorldFactory(PhysicsWorldDescriptor descriptor);

/// Physics subsystem that manages physics simulation and integrates with Sedulous.Physics.
/// Backend factory (e.g., JoltPhysicsWorld.Create) is injected via constructor.
/// Implements ISceneAware to automatically create PhysicsSceneModule for each scene.
public class PhysicsSubsystem : Subsystem, ISceneAware
{
	/// Physics runs early, before game logic processes physics results.
	public override int32 UpdateOrder => 0;

	private PhysicsWorldFactory mWorldFactory ~ delete _;
	private PhysicsWorldDescriptor mDefaultDescriptor = .Default;

	// Track physics worlds per scene
	private Dictionary<Scene, IPhysicsWorld> mSceneWorlds = new .() ~ delete _;

	// ==================== Construction ====================

	/// Creates a PhysicsSubsystem with the given world factory.
	/// @param worldFactory Factory function for creating physics worlds (e.g., JoltPhysicsWorld.Create).
	public this(PhysicsWorldFactory worldFactory)
	{
		mWorldFactory = worldFactory;
	}

	// ==================== Configuration ====================

	/// Gets the default world descriptor used for new physics worlds.
	public ref PhysicsWorldDescriptor DefaultDescriptor => ref mDefaultDescriptor;

	/// Sets the gravity for new physics worlds.
	public void SetGravity(Vector3 gravity)
	{
		mDefaultDescriptor.Gravity = gravity;
	}

	/// Sets the maximum number of bodies for new physics worlds.
	public void SetMaxBodies(uint32 maxBodies)
	{
		mDefaultDescriptor.MaxBodies = maxBodies;
	}

	// ==================== World Access ====================

	/// Gets the physics world for a specific scene.
	public IPhysicsWorld GetWorld(Scene scene)
	{
		if (mSceneWorlds.TryGetValue(scene, let world))
			return world;
		return null;
	}

	/// Creates a physics world with the default descriptor.
	public Result<IPhysicsWorld> CreateWorld()
	{
		return CreateWorld(mDefaultDescriptor);
	}

	/// Creates a physics world with custom settings.
	public Result<IPhysicsWorld> CreateWorld(PhysicsWorldDescriptor descriptor)
	{
		if (mWorldFactory == null)
			return .Err;
		return mWorldFactory(descriptor);
	}

	// ==================== Subsystem Lifecycle ====================

	protected override void OnInit()
	{
	}

	protected override void OnShutdown()
	{
		// Clean up all physics worlds
		for (let (scene, world) in mSceneWorlds)
		{
			world.Dispose();
			delete world;
		}
		mSceneWorlds.Clear();
	}

	public override void Update(float deltaTime)
	{
		// Per-scene simulation is handled by PhysicsSceneModule
	}

	// ==================== ISceneAware ====================

	public void OnSceneCreated(Scene scene)
	{
		if (mWorldFactory == null)
			return;

		// Create physics world for this scene
		switch (mWorldFactory(mDefaultDescriptor))
		{
		case .Ok(let world):
			mSceneWorlds[scene] = world;

			// Create and add scene module
			let module = new PhysicsSceneModule(this, world);
			scene.AddModule(module);

		case .Err:
			// Failed to create physics world
		}
	}

	public void OnSceneDestroyed(Scene scene)
	{
		// Clean up physics world for this scene
		if (mSceneWorlds.TryGetValue(scene, let world))
		{
			mSceneWorlds.Remove(scene);
			world.Dispose();
			delete world;
		}
	}
}

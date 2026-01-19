namespace Sedulous.Framework.Physics;

using System;
using System.Collections;
using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;
using Sedulous.Physics;

/// Component for entities with physics bodies.
struct RigidBodyComponent
{
	/// Handle to the physics body in the world.
	public BodyHandle BodyHandle;
	/// Whether to sync entity transform FROM physics (for dynamic bodies).
	public bool SyncFromPhysics;
	/// Whether to sync entity transform TO physics (for kinematic bodies).
	public bool SyncToPhysics;

	public static RigidBodyComponent Default => .() {
		BodyHandle = .Invalid,
		SyncFromPhysics = true,
		SyncToPhysics = false
	};
}

/// Scene module that manages physics bodies for entities.
/// Created automatically by PhysicsSubsystem for each scene.
class PhysicsSceneModule : SceneModule
{
	private PhysicsSubsystem mSubsystem;
	private IPhysicsWorld mPhysicsWorld;
	private Scene mScene;

	// Simulation settings
	private int32 mCollisionSteps = 1;
	private float mFixedTimeStep = 1.0f / 60.0f;
	private float mAccumulatedTime = 0.0f;

	/// Creates a PhysicsSceneModule with the given world.
	public this(PhysicsSubsystem subsystem, IPhysicsWorld physicsWorld)
	{
		mSubsystem = subsystem;
		mPhysicsWorld = physicsWorld;
	}

	/// Gets the physics subsystem.
	public PhysicsSubsystem Subsystem => mSubsystem;

	/// Gets the physics world for this scene.
	public IPhysicsWorld PhysicsWorld => mPhysicsWorld;

	/// Gets or sets the number of collision sub-steps per physics step.
	public int32 CollisionSteps
	{
		get => mCollisionSteps;
		set => mCollisionSteps = Math.Max(1, value);
	}

	/// Gets or sets the fixed time step for physics simulation.
	public float FixedTimeStep
	{
		get => mFixedTimeStep;
		set => mFixedTimeStep = Math.Max(0.001f, value);
	}

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;
	}

	public override void OnSceneDestroy(Scene scene)
	{
		// Clean up all physics bodies
		if (mPhysicsWorld != null)
		{
			for (let (entity, body) in scene.Query<RigidBodyComponent>())
			{
				if (body.BodyHandle.IsValid)
					mPhysicsWorld.DestroyBody(body.BodyHandle);
			}
		}
		mScene = null;
	}

	public override void Update(Scene scene, float deltaTime)
	{
		if (mPhysicsWorld == null)
			return;

		// Sync kinematic bodies TO physics
		SyncKinematicBodies(scene);

		// Fixed timestep physics simulation
		mAccumulatedTime += deltaTime;
		while (mAccumulatedTime >= mFixedTimeStep)
		{
			mPhysicsWorld.Step(mFixedTimeStep, mCollisionSteps);
			mAccumulatedTime -= mFixedTimeStep;
		}

		// Sync dynamic bodies FROM physics
		SyncDynamicBodies(scene);
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		if (mPhysicsWorld == null)
			return;

		if (let body = scene.GetComponent<RigidBodyComponent>(entity))
		{
			if (body.BodyHandle.IsValid)
			{
				mPhysicsWorld.DestroyBody(body.BodyHandle);
				body.BodyHandle = .Invalid;
			}
		}
	}

	// ==================== Body Creation ====================

	/// Creates a physics body for an entity.
	public Result<BodyHandle> CreateBody(EntityId entity, PhysicsBodyDescriptor descriptor)
	{
		var descriptor;
		if (mScene == null || mPhysicsWorld == null)
			return .Err;

		// Use entity transform if not specified
		if (descriptor.Position == .Zero && descriptor.Rotation == .Identity)
		{
			let transform = mScene.GetTransform(entity);
			descriptor.Position = transform.Position;
			descriptor.Rotation = transform.Rotation;
		}

		// Store entity ID as user data for callbacks (pack index + generation into uint64)
		descriptor.UserData = ((uint64)entity.Index) | (((uint64)entity.Generation) << 32);

		switch (mPhysicsWorld.CreateBody(descriptor))
		{
		case .Ok(let handle):
			var bodyComp = mScene.GetComponent<RigidBodyComponent>(entity);
			if (bodyComp == null)
			{
				mScene.SetComponent<RigidBodyComponent>(entity, .Default);
				bodyComp = mScene.GetComponent<RigidBodyComponent>(entity);
			}

			bodyComp.BodyHandle = handle;
			bodyComp.SyncFromPhysics = (descriptor.BodyType == .Dynamic);
			bodyComp.SyncToPhysics = (descriptor.BodyType == .Kinematic);

			return .Ok(handle);

		case .Err:
			return .Err;
		}
	}

	/// Creates a box collider body for an entity.
	public Result<BodyHandle> CreateBoxBody(EntityId entity, Vector3 halfExtents, BodyType type = .Dynamic)
	{
		if (mPhysicsWorld == null)
			return .Err;

		switch (mPhysicsWorld.CreateBoxShape(halfExtents))
		{
		case .Ok(let shape):
			var descriptor = PhysicsBodyDescriptor();
			descriptor.Shape = shape;
			descriptor.BodyType = type;
			return CreateBody(entity, descriptor);

		case .Err:
			return .Err;
		}
	}

	/// Creates a sphere collider body for an entity.
	public Result<BodyHandle> CreateSphereBody(EntityId entity, float radius, BodyType type = .Dynamic)
	{
		if (mPhysicsWorld == null)
			return .Err;

		switch (mPhysicsWorld.CreateSphereShape(radius))
		{
		case .Ok(let shape):
			var descriptor = PhysicsBodyDescriptor();
			descriptor.Shape = shape;
			descriptor.BodyType = type;
			return CreateBody(entity, descriptor);

		case .Err:
			return .Err;
		}
	}

	/// Creates a capsule collider body for an entity.
	public Result<BodyHandle> CreateCapsuleBody(EntityId entity, float halfHeight, float radius, BodyType type = .Dynamic)
	{
		if (mPhysicsWorld == null)
			return .Err;

		switch (mPhysicsWorld.CreateCapsuleShape(halfHeight, radius))
		{
		case .Ok(let shape):
			var descriptor = PhysicsBodyDescriptor();
			descriptor.Shape = shape;
			descriptor.BodyType = type;
			return CreateBody(entity, descriptor);

		case .Err:
			return .Err;
		}
	}

	/// Destroys the physics body for an entity.
	public void DestroyBody(EntityId entity)
	{
		if (mScene == null || mPhysicsWorld == null)
			return;

		if (let body = mScene.GetComponent<RigidBodyComponent>(entity))
		{
			if (body.BodyHandle.IsValid)
			{
				mPhysicsWorld.DestroyBody(body.BodyHandle);
				body.BodyHandle = .Invalid;
			}
		}
	}

	// ==================== Forces ====================

	/// Applies a force to an entity's physics body.
	public void AddForce(EntityId entity, Vector3 force)
	{
		if (mScene == null || mPhysicsWorld == null)
			return;

		if (let body = mScene.GetComponent<RigidBodyComponent>(entity))
		{
			if (body.BodyHandle.IsValid)
				mPhysicsWorld.AddForce(body.BodyHandle, force);
		}
	}

	/// Applies an impulse to an entity's physics body.
	public void AddImpulse(EntityId entity, Vector3 impulse)
	{
		if (mScene == null || mPhysicsWorld == null)
			return;

		if (let body = mScene.GetComponent<RigidBodyComponent>(entity))
		{
			if (body.BodyHandle.IsValid)
				mPhysicsWorld.AddImpulse(body.BodyHandle, impulse);
		}
	}

	/// Sets the linear velocity of an entity's physics body.
	public void SetLinearVelocity(EntityId entity, Vector3 velocity)
	{
		if (mScene == null || mPhysicsWorld == null)
			return;

		if (let body = mScene.GetComponent<RigidBodyComponent>(entity))
		{
			if (body.BodyHandle.IsValid)
				mPhysicsWorld.SetLinearVelocity(body.BodyHandle, velocity);
		}
	}

	/// Gets the linear velocity of an entity's physics body.
	public Vector3 GetLinearVelocity(EntityId entity)
	{
		if (mScene == null || mPhysicsWorld == null)
			return .Zero;

		if (let body = mScene.GetComponent<RigidBodyComponent>(entity))
		{
			if (body.BodyHandle.IsValid)
				return mPhysicsWorld.GetLinearVelocity(body.BodyHandle);
		}
		return .Zero;
	}

	// ==================== Queries ====================

	/// Casts a ray and returns the first hit entity.
	public bool RayCast(Vector3 origin, Vector3 direction, float maxDistance, out EntityId hitEntity, out Vector3 hitPoint, out Vector3 hitNormal)
	{
		hitEntity = .Invalid;
		hitPoint = .Zero;
		hitNormal = .Zero;

		if (mPhysicsWorld == null)
			return false;

		let query = RayCastQuery(origin, direction, maxDistance);
		RayCastResult result = .();

		if (mPhysicsWorld.RayCast(query, out result))
		{
			// Unpack entity ID from user data
			let userData = result.UserData;
			hitEntity = EntityId((uint32)(userData & 0xFFFFFFFF), (uint32)(userData >> 32));
			hitPoint = result.Position;
			hitNormal = result.Normal;
			return true;
		}
		return false;
	}

	// ==================== Private ====================

	private void SyncKinematicBodies(Scene scene)
	{
		for (let (entity, body) in scene.Query<RigidBodyComponent>())
		{
			if (!body.SyncToPhysics || !body.BodyHandle.IsValid)
				continue;

			let transform = scene.GetTransform(entity);
			mPhysicsWorld.SetBodyTransform(body.BodyHandle, transform.Position, transform.Rotation);
		}
	}

	private void SyncDynamicBodies(Scene scene)
	{
		for (let (entity, body) in scene.Query<RigidBodyComponent>())
		{
			if (!body.SyncFromPhysics || !body.BodyHandle.IsValid)
				continue;

			let position = mPhysicsWorld.GetBodyPosition(body.BodyHandle);
			let rotation = mPhysicsWorld.GetBodyRotation(body.BodyHandle);

			var transform = scene.GetTransform(entity);
			transform.Position = position;
			transform.Rotation = rotation;
			scene.SetTransform(entity, transform);
		}
	}
}

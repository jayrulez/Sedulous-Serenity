namespace Sedulous.Engine.Physics;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Engine.Render;
using Sedulous.Core.Mathematics;
using Sedulous.Physics;
using Sedulous.Render;
using Sedulous.Profiler;
using Sedulous.Serialization;

/// Internal data for a physics body. All body state is owned here.
struct PhysicsBodyData
{
	public BodyHandle Handle = .Invalid;
	public bool SyncFromPhysics;  // Dynamic bodies: sync entity transform from physics
	public bool SyncToPhysics;    // Kinematic bodies: sync entity transform to physics

	// Body properties (source of truth)
	public BodyType BodyType;
	public float Mass;
	public float LinearDamping;
	public float AngularDamping;
	public float Friction;
	public float Restitution;
	public float GravityFactor;
	public bool Enabled;

	// Debug shape info (replaces PhysicsDebugShapeComponent)
	public DebugShapeType ShapeType;
	public Vector3 HalfExtents;
}

/// Scene module that manages physics bodies for entities.
/// Created automatically by PhysicsSubsystem for each scene.
///
/// All physics body data is owned by this module in internal storage.
/// Components are thin handles into this storage.
class PhysicsSceneModule : SceneModule
{
	private PhysicsSubsystem mSubsystem;
	private IPhysicsWorld mPhysicsWorld;
	private Scene mScene;

	// Track body data per entity
	private Dictionary<EntityId, PhysicsBodyData> mBodies = new .() ~ delete _;

	// Simulation settings
	private int32 mCollisionSteps = 1;

	// Debug drawing
	private bool mDebugDrawEnabled = false;
	private Color mDebugColorStatic = .(128, 128, 128, 200);
	private Color mDebugColorDynamic = .(100, 200, 100, 200);
	private Color mDebugColorKinematic = .(100, 100, 200, 200);

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

	/// Provides read access to bodies for serialization.
	public Dictionary<EntityId, PhysicsBodyData> Bodies => mBodies;

	/// Gets or sets the number of collision sub-steps per physics step.
	public int32 CollisionSteps
	{
		get => mCollisionSteps;
		set => mCollisionSteps = Math.Max(1, value);
	}

	/// Gets or sets whether physics debug drawing is enabled.
	public bool DebugDrawEnabled
	{
		get => mDebugDrawEnabled;
		set => mDebugDrawEnabled = value;
	}

	/// Gets or sets the color for static bodies in debug draw.
	public Color DebugColorStatic
	{
		get => mDebugColorStatic;
		set => mDebugColorStatic = value;
	}

	/// Gets or sets the color for dynamic bodies in debug draw.
	public Color DebugColorDynamic
	{
		get => mDebugColorDynamic;
		set => mDebugColorDynamic = value;
	}

	/// Gets or sets the color for kinematic bodies in debug draw.
	public Color DebugColorKinematic
	{
		get => mDebugColorKinematic;
		set => mDebugColorKinematic = value;
	}

	// ==================== Scene Lifecycle ====================

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;

		// Register custom serializer
		scene.RegisterComponentSerializer(new RigidBodyComponentSerializer());

		// Apply physics settings from scene
		if (let settings = scene.GetModuleSettings<PhysicsModuleSettings>())
			mCollisionSteps = settings.CollisionSteps;
	}

	public override void OnSceneDestroy(Scene scene)
	{
		mBodies.Clear();
		mScene = null;
	}

	public override void FixedUpdate(Scene scene, float fixedDeltaTime)
	{
		if (mPhysicsWorld == null)
			return;

		// Sync kinematic bodies TO physics before stepping
		{
			using (SProfiler.Begin("Physics.SyncKinematic"))
				SyncKinematicBodies(scene);
		}

		// Step physics simulation at fixed timestep
		{
			using (SProfiler.Begin("Physics.Step"))
				mPhysicsWorld.Step(fixedDeltaTime, mCollisionSteps);
		}

		// Sync dynamic bodies FROM physics after stepping
		{
			using (SProfiler.Begin("Physics.SyncDynamic"))
				SyncDynamicBodies(scene);
		}
	}

	public override void Update(Scene scene, float deltaTime)
	{
	}

	public override void PostUpdate(Scene scene, float deltaTime)
	{
		if (!mDebugDrawEnabled || mPhysicsWorld == null || mScene == null)
			return;

		let renderModule = scene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return;

		let renderSystem = renderModule.Subsystem?.RenderSystem;
		if (renderSystem == null)
			return;

		let overlayFeature = renderSystem.GetFeature<OverlayRenderFeature>();
		if (overlayFeature == null)
			return;

		// Draw debug shapes for all physics bodies from internal storage
		for (let (entity, bodyData) in mBodies)
		{
			if (!bodyData.Handle.IsValid || bodyData.ShapeType == .None)
				continue;

			let position = mPhysicsWorld.GetBodyPosition(bodyData.Handle);
			let rotation = mPhysicsWorld.GetBodyRotation(bodyData.Handle);

			Color color;
			switch (bodyData.BodyType)
			{
			case .Static: color = mDebugColorStatic;
			case .Dynamic: color = mDebugColorDynamic;
			case .Kinematic: color = mDebugColorKinematic;
			}

			switch (bodyData.ShapeType)
			{
			case .Box:
				DrawOrientedBox(overlayFeature, position, rotation, bodyData.HalfExtents, color);

			case .Sphere:
				let radius = bodyData.HalfExtents.X;
				overlayFeature.AddSphere(position, radius, color);

			case .Capsule:
				let radius = bodyData.HalfExtents.X;
				let halfHeight = bodyData.HalfExtents.Y;
				let height = (halfHeight + radius) * 2.0f;
				overlayFeature.AddCapsule(position, radius, height, color);

			case .Cylinder:
				let radius = bodyData.HalfExtents.X;
				let halfHeight = bodyData.HalfExtents.Y;
				overlayFeature.AddCylinder(position, radius, halfHeight * 2.0f, color);

			case .None:
			}
		}
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		if (mPhysicsWorld == null)
			return;

		if (mBodies.TryGetValue(entity, let bodyData))
		{
			if (bodyData.Handle.IsValid)
				mPhysicsWorld.DestroyBody(bodyData.Handle);
			mBodies.Remove(entity);
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

		// Store entity ID as user data for callbacks
		descriptor.UserData = ((uint64)entity.Index) | (((uint64)entity.Generation) << 32);

		switch (mPhysicsWorld.CreateBody(descriptor))
		{
		case .Ok(let handle):
			var bodyData = PhysicsBodyData();
			bodyData.Handle = handle;
			bodyData.SyncFromPhysics = (descriptor.BodyType == .Dynamic);
			bodyData.SyncToPhysics = (descriptor.BodyType == .Kinematic);
			bodyData.BodyType = descriptor.BodyType;
			bodyData.Mass = descriptor.Mass;
			bodyData.LinearDamping = descriptor.LinearDamping;
			bodyData.AngularDamping = descriptor.AngularDamping;
			bodyData.Friction = descriptor.Friction;
			bodyData.Restitution = descriptor.Restitution;
			bodyData.GravityFactor = descriptor.GravityFactor;
			bodyData.Enabled = true;
			mBodies[entity] = bodyData;

			// Ensure thin handle component exists
			var comp = mScene.GetComponent<RigidBodyComponent>(entity);
			if (comp == null)
			{
				mScene.SetComponent<RigidBodyComponent>(entity, .());
				comp = mScene.GetComponent<RigidBodyComponent>(entity);
			}

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
			let result = CreateBody(entity, descriptor);

			if (result case .Ok)
				SetDebugShape(entity, .Box, halfExtents);

			return result;

		case .Err:
			return .Err;
		}
	}

	/// Creates a sphere collider body for an entity.
	public Result<BodyHandle> CreateSphereBody(EntityId entity, float radius, BodyType type = .Dynamic, float restitution = 0.0f)
	{
		if (mPhysicsWorld == null)
			return .Err;

		switch (mPhysicsWorld.CreateSphereShape(radius))
		{
		case .Ok(let shape):
			var descriptor = PhysicsBodyDescriptor();
			descriptor.Shape = shape;
			descriptor.BodyType = type;
			descriptor.Restitution = restitution;
			let result = CreateBody(entity, descriptor);

			if (result case .Ok)
				SetDebugShape(entity, .Sphere, .(radius, 0, 0));

			return result;

		case .Err:
			return .Err;
		}
	}

	/// Creates a sphere collider body with full descriptor control.
	public Result<BodyHandle> CreateSphereBody(EntityId entity, float radius, in PhysicsBodyDescriptor baseDescriptor)
	{
		if (mPhysicsWorld == null)
			return .Err;

		switch (mPhysicsWorld.CreateSphereShape(radius))
		{
		case .Ok(let shape):
			var descriptor = baseDescriptor;
			descriptor.Shape = shape;
			let result = CreateBody(entity, descriptor);

			if (result case .Ok)
				SetDebugShape(entity, .Sphere, .(radius, 0, 0));

			return result;

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
			let result = CreateBody(entity, descriptor);

			if (result case .Ok)
				SetDebugShape(entity, .Capsule, .(radius, halfHeight, 0));

			return result;

		case .Err:
			return .Err;
		}
	}

	/// Creates an infinite plane collider body for an entity (static only).
	public Result<BodyHandle> CreatePlaneBody(EntityId entity, Vector3 normal, float distance = 0.0f)
	{
		if (mPhysicsWorld == null)
			return .Err;

		switch (mPhysicsWorld.CreatePlaneShape(normal, distance))
		{
		case .Ok(let shape):
			var descriptor = PhysicsBodyDescriptor();
			descriptor.Shape = shape;
			descriptor.BodyType = .Static;
			return CreateBody(entity, descriptor);

		case .Err:
			return .Err;
		}
	}

	/// Creates a mesh collider body for an entity (static only).
	public Result<BodyHandle> CreateMeshBody(EntityId entity, Span<Vector3> vertices, Span<uint32> indices)
	{
		if (mPhysicsWorld == null)
			return .Err;

		switch (mPhysicsWorld.CreateMeshShape(vertices, indices))
		{
		case .Ok(let shape):
			var descriptor = PhysicsBodyDescriptor();
			descriptor.Shape = shape;
			descriptor.BodyType = .Static;
			return CreateBody(entity, descriptor);

		case .Err:
			return .Err;
		}
	}

	/// Creates a body from serialization data (deferred — no physics shape yet).
	/// Stores body properties for future reconstruction when physics world is available.
	public void CreateBodyFromData(EntityId entity, RigidBodyComponentData data)
	{
		if (mScene == null)
			return;

		var bodyData = PhysicsBodyData();
		bodyData.Handle = .Invalid;
		bodyData.SyncFromPhysics = (data.BodyType == .Dynamic);
		bodyData.SyncToPhysics = (data.BodyType == .Kinematic);
		bodyData.BodyType = data.BodyType;
		bodyData.Mass = data.Mass;
		bodyData.LinearDamping = data.LinearDamping;
		bodyData.AngularDamping = data.AngularDamping;
		bodyData.Friction = data.Friction;
		bodyData.Restitution = data.Restitution;
		bodyData.GravityFactor = data.GravityFactor;
		bodyData.Enabled = data.Enabled;
		bodyData.ShapeType = data.ShapeType;
		bodyData.HalfExtents = data.HalfExtents;
		mBodies[entity] = bodyData;

		// Set thin handle on entity
		var comp = mScene.GetComponent<RigidBodyComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<RigidBodyComponent>(entity, .());
			comp = mScene.GetComponent<RigidBodyComponent>(entity);
		}
	}

	/// Destroys the physics body for an entity.
	public void DestroyBody(EntityId entity)
	{
		if (mPhysicsWorld == null)
			return;

		if (mBodies.TryGetValue(entity, let bodyData))
		{
			if (bodyData.Handle.IsValid)
				mPhysicsWorld.DestroyBody(bodyData.Handle);
			mBodies.Remove(entity);
		}

		if (mScene != null)
		{
			if (let comp = mScene.GetComponent<RigidBodyComponent>(entity))
				comp.InternalHandle = -1;
		}
	}

	// ==================== Property Setters ====================

	/// Sets the mass of an entity's physics body.
	public void SetMass(EntityId entity, float mass)
	{
		if (mPhysicsWorld == null)
			return;
		if (!mBodies.TryGetValue(entity, var bodyData))
			return;
		bodyData.Mass = mass;
		if (bodyData.Handle.IsValid)
			mPhysicsWorld.SetBodyMass(bodyData.Handle, mass);
		mBodies[entity] = bodyData;
	}

	/// Sets the linear damping of an entity's physics body.
	public void SetLinearDamping(EntityId entity, float damping)
	{
		if (mPhysicsWorld == null)
			return;
		if (!mBodies.TryGetValue(entity, var bodyData))
			return;
		bodyData.LinearDamping = damping;
		if (bodyData.Handle.IsValid)
			mPhysicsWorld.SetBodyLinearDamping(bodyData.Handle, damping);
		mBodies[entity] = bodyData;
	}

	/// Sets the angular damping of an entity's physics body.
	public void SetAngularDamping(EntityId entity, float damping)
	{
		if (mPhysicsWorld == null)
			return;
		if (!mBodies.TryGetValue(entity, var bodyData))
			return;
		bodyData.AngularDamping = damping;
		if (bodyData.Handle.IsValid)
			mPhysicsWorld.SetBodyAngularDamping(bodyData.Handle, damping);
		mBodies[entity] = bodyData;
	}

	/// Sets the friction of an entity's physics body.
	public void SetFriction(EntityId entity, float friction)
	{
		if (mPhysicsWorld == null)
			return;
		if (!mBodies.TryGetValue(entity, var bodyData))
			return;
		bodyData.Friction = friction;
		if (bodyData.Handle.IsValid)
			mPhysicsWorld.SetBodyFriction(bodyData.Handle, friction);
		mBodies[entity] = bodyData;
	}

	/// Sets the restitution of an entity's physics body.
	public void SetRestitution(EntityId entity, float restitution)
	{
		if (mPhysicsWorld == null)
			return;
		if (!mBodies.TryGetValue(entity, var bodyData))
			return;
		bodyData.Restitution = restitution;
		if (bodyData.Handle.IsValid)
			mPhysicsWorld.SetBodyRestitution(bodyData.Handle, restitution);
		mBodies[entity] = bodyData;
	}

	/// Sets the gravity factor of an entity's physics body.
	public void SetGravityFactor(EntityId entity, float factor)
	{
		if (mPhysicsWorld == null)
			return;
		if (!mBodies.TryGetValue(entity, var bodyData))
			return;
		bodyData.GravityFactor = factor;
		if (bodyData.Handle.IsValid)
			mPhysicsWorld.SetBodyGravityFactor(bodyData.Handle, factor);
		mBodies[entity] = bodyData;
	}

	/// Enables or disables an entity's physics body.
	public void SetEnabled(EntityId entity, bool enabled)
	{
		if (mPhysicsWorld == null)
			return;
		if (!mBodies.TryGetValue(entity, var bodyData))
			return;
		bodyData.Enabled = enabled;
		if (bodyData.Handle.IsValid)
		{
			if (enabled)
				mPhysicsWorld.ActivateBody(bodyData.Handle);
			else
				mPhysicsWorld.DeactivateBody(bodyData.Handle);
		}
		mBodies[entity] = bodyData;
	}

	/// Gets the body type for an entity.
	public BodyType GetBodyType(EntityId entity)
	{
		if (mBodies.TryGetValue(entity, let bodyData))
			return bodyData.BodyType;
		return .Dynamic;
	}

	/// Gets the mass of an entity's body.
	public float GetMass(EntityId entity)
	{
		if (mBodies.TryGetValue(entity, let bodyData))
			return bodyData.Mass;
		return 0;
	}

	/// Gets whether a body exists and has a valid handle for an entity.
	public bool HasBody(EntityId entity)
	{
		return mBodies.ContainsKey(entity);
	}

	// ==================== Forces ====================

	/// Applies a force to an entity's physics body.
	public void AddForce(EntityId entity, Vector3 force)
	{
		if (mPhysicsWorld == null)
			return;

		if (mBodies.TryGetValue(entity, let bodyData))
		{
			if (bodyData.Handle.IsValid)
				mPhysicsWorld.AddForce(bodyData.Handle, force);
		}
	}

	/// Applies an impulse to an entity's physics body.
	public void AddImpulse(EntityId entity, Vector3 impulse)
	{
		if (mPhysicsWorld == null)
			return;

		if (mBodies.TryGetValue(entity, let bodyData))
		{
			if (bodyData.Handle.IsValid)
				mPhysicsWorld.AddImpulse(bodyData.Handle, impulse);
		}
	}

	/// Sets the linear velocity of an entity's physics body.
	public void SetLinearVelocity(EntityId entity, Vector3 velocity)
	{
		if (mPhysicsWorld == null)
			return;

		if (mBodies.TryGetValue(entity, let bodyData))
		{
			if (bodyData.Handle.IsValid)
				mPhysicsWorld.SetLinearVelocity(bodyData.Handle, velocity);
		}
	}

	/// Gets the linear velocity of an entity's physics body.
	public Vector3 GetLinearVelocity(EntityId entity)
	{
		if (mPhysicsWorld == null)
			return .Zero;

		if (mBodies.TryGetValue(entity, let bodyData))
		{
			if (bodyData.Handle.IsValid)
				return mPhysicsWorld.GetLinearVelocity(bodyData.Handle);
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
			let userData = result.UserData;
			hitEntity = EntityId((uint32)(userData & 0xFFFFFFFF), (uint32)(userData >> 32));
			hitPoint = result.Position;
			hitNormal = result.Normal;
			return true;
		}
		return false;
	}

	// ==================== Private ====================

	/// Sets debug shape info on an entity's body data.
	private void SetDebugShape(EntityId entity, DebugShapeType shapeType, Vector3 halfExtents)
	{
		if (mBodies.TryGetValue(entity, var bodyData))
		{
			bodyData.ShapeType = shapeType;
			bodyData.HalfExtents = halfExtents;
			mBodies[entity] = bodyData;
		}
	}

	private void SyncKinematicBodies(Scene scene)
	{
		for (let (entity, bodyData) in mBodies)
		{
			if (!bodyData.SyncToPhysics || !bodyData.Handle.IsValid)
				continue;

			let transform = scene.GetTransform(entity);
			mPhysicsWorld.SetBodyTransform(bodyData.Handle, transform.Position, transform.Rotation);
		}
	}

	private void SyncDynamicBodies(Scene scene)
	{
		for (let (entity, bodyData) in mBodies)
		{
			if (!bodyData.SyncFromPhysics || !bodyData.Handle.IsValid)
				continue;

			let position = mPhysicsWorld.GetBodyPosition(bodyData.Handle);
			let rotation = mPhysicsWorld.GetBodyRotation(bodyData.Handle);

			var transform = scene.GetTransform(entity);
			transform.Position = position;
			transform.Rotation = rotation;
			scene.SetTransform(entity, transform);
		}
	}

	private void DrawOrientedBox(OverlayRenderFeature overlayFeature, Vector3 position, Quaternion rotation, Vector3 halfExtents, Color color)
	{
		Vector3[8] localCorners = .(
			.(-halfExtents.X, -halfExtents.Y, -halfExtents.Z),
			.( halfExtents.X, -halfExtents.Y, -halfExtents.Z),
			.( halfExtents.X, -halfExtents.Y,  halfExtents.Z),
			.(-halfExtents.X, -halfExtents.Y,  halfExtents.Z),
			.(-halfExtents.X,  halfExtents.Y, -halfExtents.Z),
			.( halfExtents.X,  halfExtents.Y, -halfExtents.Z),
			.( halfExtents.X,  halfExtents.Y,  halfExtents.Z),
			.(-halfExtents.X,  halfExtents.Y,  halfExtents.Z)
		);

		Vector3[8] worldCorners = ?;
		for (int i = 0; i < 8; i++)
		{
			worldCorners[i] = position + Vector3.Transform(localCorners[i], rotation);
		}

		overlayFeature.AddLine(worldCorners[0], worldCorners[1], color);
		overlayFeature.AddLine(worldCorners[1], worldCorners[2], color);
		overlayFeature.AddLine(worldCorners[2], worldCorners[3], color);
		overlayFeature.AddLine(worldCorners[3], worldCorners[0], color);

		overlayFeature.AddLine(worldCorners[4], worldCorners[5], color);
		overlayFeature.AddLine(worldCorners[5], worldCorners[6], color);
		overlayFeature.AddLine(worldCorners[6], worldCorners[7], color);
		overlayFeature.AddLine(worldCorners[7], worldCorners[4], color);

		overlayFeature.AddLine(worldCorners[0], worldCorners[4], color);
		overlayFeature.AddLine(worldCorners[1], worldCorners[5], color);
		overlayFeature.AddLine(worldCorners[2], worldCorners[6], color);
		overlayFeature.AddLine(worldCorners[3], worldCorners[7], color);
	}
}

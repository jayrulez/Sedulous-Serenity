namespace Sedulous.Framework.Physics;

using System;
using System.Collections;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Mathematics;
using Sedulous.Physics;
using Sedulous.Render;
using Sedulous.Profiler;

/// Component for entities with physics bodies.
/// Exposes serializable physics properties that sync with the physics world.
/// The actual body handle is managed internally by PhysicsSceneModule.
struct RigidBodyComponent
{
	/// Body type (Dynamic, Kinematic, Static).
	public BodyType BodyType;
	/// Mass of the body (only applies to dynamic bodies).
	public float Mass;
	/// Linear damping coefficient.
	public float LinearDamping;
	/// Angular damping coefficient.
	public float AngularDamping;
	/// Friction coefficient.
	public float Friction;
	/// Restitution (bounciness) coefficient.
	public float Restitution;
	/// Gravity multiplier (0 = no gravity, 1 = normal gravity).
	public float GravityFactor;
	/// Whether the body is enabled in the simulation.
	public bool Enabled;

	public static RigidBodyComponent Default => .() {
		BodyType = .Dynamic,
		Mass = 1.0f,
		LinearDamping = 0.0f,
		AngularDamping = 0.05f,
		Friction = 0.2f,
		Restitution = 0.0f,
		GravityFactor = 1.0f,
		Enabled = true
	};
}

/// Shape type for debug drawing.
enum DebugShapeType
{
	None,
	Box,
	Sphere,
	Capsule,
	Cylinder
}

/// Component storing shape info for debug drawing.
struct PhysicsDebugShapeComponent
{
	public DebugShapeType ShapeType;
	public Vector3 HalfExtents;  // Box: half extents, Sphere: (radius, 0, 0), Capsule/Cylinder: (radius, halfHeight, 0)

	public static PhysicsDebugShapeComponent Default => .() {
		ShapeType = .None,
		HalfExtents = .Zero
	};
}

/// Scene module that manages physics bodies for entities.
/// Created automatically by PhysicsSubsystem for each scene.
/// Internal data for a physics body.
struct PhysicsBodyData
{
	public BodyHandle Handle;
	public bool SyncFromPhysics;  // Dynamic bodies: sync entity transform from physics
	public bool SyncToPhysics;    // Kinematic bodies: sync entity transform to physics

	// Cached component values for change detection
	public float Mass;
	public float LinearDamping;
	public float AngularDamping;
	public float Friction;
	public float Restitution;
	public float GravityFactor;
	public bool Enabled;
}

class PhysicsSceneModule : SceneModule
{
	private PhysicsSubsystem mSubsystem;
	private IPhysicsWorld mPhysicsWorld;
	private Scene mScene;

	// Track body data per entity (internal, not exposed on components)
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

	/// Gets or sets the number of collision sub-steps per physics step.
	public int32 CollisionSteps
	{
		get => mCollisionSteps;
		set => mCollisionSteps = Math.Max(1, value);
	}

	/// Gets or sets whether physics debug drawing is enabled.
	/// When enabled, draws wireframe shapes for all physics bodies.
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

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;
	}

	public override void OnSceneDestroy(Scene scene)
	{
		// Note: Physics bodies are cleaned up by the physics world when it's destroyed.
		// The PhysicsSubsystem destroys the world before scene modules are notified,
		// so we don't attempt to destroy bodies here.
		mBodies.Clear();
		mScene = null;
	}

	public override void FixedUpdate(Scene scene, float fixedDeltaTime)
	{
		if (mPhysicsWorld == null)
			return;

		// Sync component property changes TO physics bodies
		{
			using (SProfiler.Begin("Physics.SyncProperties"))
				SyncComponentProperties(scene);
		}

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
		// Physics simulation now happens in FixedUpdate.
		// This method is kept for potential future per-frame work (e.g., interpolation).
	}

	public override void PostUpdate(Scene scene, float deltaTime)
	{
		if (!mDebugDrawEnabled || mPhysicsWorld == null || mScene == null)
			return;

		// Get RenderSceneModule to access DebugRenderFeature
		let renderModule = scene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return;

		let renderSystem = renderModule.Subsystem?.RenderSystem;
		if (renderSystem == null)
			return;

		let debugFeature = renderSystem.GetFeature<DebugRenderFeature>();
		if (debugFeature == null)
			return;

		// Draw debug shapes for all physics bodies
		for (let (entity, _) in scene.Query<RigidBodyComponent>())
		{
			PhysicsBodyData bodyData = .();
			if (mBodies.TryGetValue(entity, var data))
				bodyData = data;

			if (!bodyData.Handle.IsValid)
				continue;

			// Get debug shape info
			let debugShape = scene.GetComponent<PhysicsDebugShapeComponent>(entity);
			if (debugShape == null || debugShape.ShapeType == .None)
				continue;

			// Get body transform from physics world
			let position = mPhysicsWorld.GetBodyPosition(bodyData.Handle);
			let rotation = mPhysicsWorld.GetBodyRotation(bodyData.Handle);

			// Determine color based on body type
			let bodyType = mPhysicsWorld.GetBodyType(bodyData.Handle);
			Color color;
			switch (bodyType)
			{
			case .Static: color = mDebugColorStatic;
			case .Dynamic: color = mDebugColorDynamic;
			case .Kinematic: color = mDebugColorKinematic;
			}

			// Draw the shape
			switch (debugShape.ShapeType)
			{
			case .Box:
				DrawOrientedBox(debugFeature, position, rotation, debugShape.HalfExtents, color);

			case .Sphere:
				let radius = debugShape.HalfExtents.X;
				debugFeature.AddSphere(position, radius, color);

			case .Capsule:
				let radius = debugShape.HalfExtents.X;
				let halfHeight = debugShape.HalfExtents.Y;
				let height = (halfHeight + radius) * 2.0f;
				debugFeature.AddCapsule(position, radius, height, color);

			case .Cylinder:
				let radius = debugShape.HalfExtents.X;
				let halfHeight = debugShape.HalfExtents.Y;
				debugFeature.AddCylinder(position, radius, halfHeight * 2.0f, color);

			case .None:
				// Skip
			}
		}
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		if (mPhysicsWorld == null)
			return;

		// Clean up body from internal tracking
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

		// Store entity ID as user data for callbacks (pack index + generation into uint64)
		descriptor.UserData = ((uint64)entity.Index) | (((uint64)entity.Generation) << 32);

		switch (mPhysicsWorld.CreateBody(descriptor))
		{
		case .Ok(let handle):
			// Store in internal tracking with sync settings and cached values
			var bodyData = PhysicsBodyData();
			bodyData.Handle = handle;
			bodyData.SyncFromPhysics = (descriptor.BodyType == .Dynamic);
			bodyData.SyncToPhysics = (descriptor.BodyType == .Kinematic);
			bodyData.Mass = descriptor.Mass;
			bodyData.LinearDamping = descriptor.LinearDamping;
			bodyData.AngularDamping = descriptor.AngularDamping;
			bodyData.Friction = descriptor.Friction;
			bodyData.Restitution = descriptor.Restitution;
			bodyData.GravityFactor = descriptor.GravityFactor;
			bodyData.Enabled = true;
			mBodies[entity] = bodyData;

			// Ensure component exists and sync properties from descriptor
			var comp = mScene.GetComponent<RigidBodyComponent>(entity);
			if (comp == null)
			{
				mScene.SetComponent<RigidBodyComponent>(entity, .Default);
				comp = mScene.GetComponent<RigidBodyComponent>(entity);
			}

			comp.BodyType = descriptor.BodyType;
			comp.Mass = descriptor.Mass;
			comp.LinearDamping = descriptor.LinearDamping;
			comp.AngularDamping = descriptor.AngularDamping;
			comp.Friction = descriptor.Friction;
			comp.Restitution = descriptor.Restitution;
			comp.GravityFactor = descriptor.GravityFactor;
			comp.Enabled = true;

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

			// Store shape info for debug drawing
			if (result case .Ok)
			{
				mScene?.SetComponent<PhysicsDebugShapeComponent>(entity, .() {
					ShapeType = .Box,
					HalfExtents = halfExtents
				});
			}

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

			// Store shape info for debug drawing
			if (result case .Ok)
			{
				mScene?.SetComponent<PhysicsDebugShapeComponent>(entity, .() {
					ShapeType = .Sphere,
					HalfExtents = .(radius, 0, 0)
				});
			}

			return result;

		case .Err:
			return .Err;
		}
	}

	/// Creates a sphere collider body with full descriptor control.
	/// The shape is created internally; all other descriptor fields are used as-is.
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
			{
				mScene?.SetComponent<PhysicsDebugShapeComponent>(entity, .() {
					ShapeType = .Sphere,
					HalfExtents = .(radius, 0, 0)
				});
			}

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

			// Store shape info for debug drawing
			if (result case .Ok)
			{
				mScene?.SetComponent<PhysicsDebugShapeComponent>(entity, .() {
					ShapeType = .Capsule,
					HalfExtents = .(radius, halfHeight, 0)
				});
			}

			return result;

		case .Err:
			return .Err;
		}
	}

	/// Creates an infinite plane collider body for an entity (static only).
	/// @param normal The plane normal direction (will be normalized).
	/// @param distance Distance from origin along the normal.
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
	/// Mesh shapes are typically used for static level geometry.
	public Result<BodyHandle> CreateMeshBody(EntityId entity, Span<Vector3> vertices, Span<uint32> indices)
	{
		if (mPhysicsWorld == null)
			return .Err;

		switch (mPhysicsWorld.CreateMeshShape(vertices, indices))
		{
		case .Ok(let shape):
			var descriptor = PhysicsBodyDescriptor();
			descriptor.Shape = shape;
			descriptor.BodyType = .Static;  // Mesh shapes must be static
			let result = CreateBody(entity, descriptor);

			// No debug shape for mesh (too complex to visualize)

			return result;

		case .Err:
			return .Err;
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

	/// Syncs component property changes to the physics bodies.
	private void SyncComponentProperties(Scene scene)
	{
		for (let (entity, comp) in scene.Query<RigidBodyComponent>())
		{
			if (!mBodies.TryGetValue(entity, var bodyData))
				continue;

			if (!bodyData.Handle.IsValid)
				continue;

			bool changed = false;

			// Check each property for changes
			if (comp.Mass != bodyData.Mass)
			{
				mPhysicsWorld.SetBodyMass(bodyData.Handle, comp.Mass);
				bodyData.Mass = comp.Mass;
				changed = true;
			}

			if (comp.LinearDamping != bodyData.LinearDamping)
			{
				mPhysicsWorld.SetBodyLinearDamping(bodyData.Handle, comp.LinearDamping);
				bodyData.LinearDamping = comp.LinearDamping;
				changed = true;
			}

			if (comp.AngularDamping != bodyData.AngularDamping)
			{
				mPhysicsWorld.SetBodyAngularDamping(bodyData.Handle, comp.AngularDamping);
				bodyData.AngularDamping = comp.AngularDamping;
				changed = true;
			}

			if (comp.Friction != bodyData.Friction)
			{
				mPhysicsWorld.SetBodyFriction(bodyData.Handle, comp.Friction);
				bodyData.Friction = comp.Friction;
				changed = true;
			}

			if (comp.Restitution != bodyData.Restitution)
			{
				mPhysicsWorld.SetBodyRestitution(bodyData.Handle, comp.Restitution);
				bodyData.Restitution = comp.Restitution;
				changed = true;
			}

			if (comp.GravityFactor != bodyData.GravityFactor)
			{
				mPhysicsWorld.SetBodyGravityFactor(bodyData.Handle, comp.GravityFactor);
				bodyData.GravityFactor = comp.GravityFactor;
				changed = true;
			}

			if (comp.Enabled != bodyData.Enabled)
			{
				if (comp.Enabled)
					mPhysicsWorld.ActivateBody(bodyData.Handle);
				else
					mPhysicsWorld.DeactivateBody(bodyData.Handle);
				bodyData.Enabled = comp.Enabled;
				changed = true;
			}

			// Update cached data if any property changed
			if (changed)
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

	private void DrawOrientedBox(DebugRenderFeature debugFeature, Vector3 position, Quaternion rotation, Vector3 halfExtents, Color color)
	{
		// 8 corners in local space
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

		// Transform corners to world space
		Vector3[8] worldCorners = ?;
		for (int i = 0; i < 8; i++)
		{
			worldCorners[i] = position + Vector3.Transform(localCorners[i], rotation);
		}

		// Bottom face (Y = min)
		debugFeature.AddLine(worldCorners[0], worldCorners[1], color);
		debugFeature.AddLine(worldCorners[1], worldCorners[2], color);
		debugFeature.AddLine(worldCorners[2], worldCorners[3], color);
		debugFeature.AddLine(worldCorners[3], worldCorners[0], color);

		// Top face (Y = max)
		debugFeature.AddLine(worldCorners[4], worldCorners[5], color);
		debugFeature.AddLine(worldCorners[5], worldCorners[6], color);
		debugFeature.AddLine(worldCorners[6], worldCorners[7], color);
		debugFeature.AddLine(worldCorners[7], worldCorners[4], color);

		// Vertical edges
		debugFeature.AddLine(worldCorners[0], worldCorners[4], color);
		debugFeature.AddLine(worldCorners[1], worldCorners[5], color);
		debugFeature.AddLine(worldCorners[2], worldCorners[6], color);
		debugFeature.AddLine(worldCorners[3], worldCorners[7], color);
	}
}

namespace Sedulous.Framework.Physics;

using System;
using System.Collections;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Mathematics;
using Sedulous.Physics;
using Sedulous.Render;

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
class PhysicsSceneModule : SceneModule
{
	private PhysicsSubsystem mSubsystem;
	private IPhysicsWorld mPhysicsWorld;
	private Scene mScene;

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
		mScene = null;
	}

	public override void FixedUpdate(Scene scene, float fixedDeltaTime)
	{
		if (mPhysicsWorld == null)
			return;

		// Sync kinematic bodies TO physics before stepping
		SyncKinematicBodies(scene);

		// Step physics simulation at fixed timestep
		mPhysicsWorld.Step(fixedDeltaTime, mCollisionSteps);

		// Sync dynamic bodies FROM physics after stepping
		SyncDynamicBodies(scene);
	}

	public override void Update(Scene scene, float deltaTime)
	{
		// Physics simulation now happens in FixedUpdate.
		// This method is kept for potential future per-frame work (e.g., interpolation).
	}

	public override void OnEndFrame(Scene scene)
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
		for (let (entity, body) in scene.Query<RigidBodyComponent>())
		{
			if (!body.BodyHandle.IsValid)
				continue;

			// Get debug shape info
			let debugShape = scene.GetComponent<PhysicsDebugShapeComponent>(entity);
			if (debugShape == null || debugShape.ShapeType == .None)
				continue;

			// Get body transform from physics world
			let position = mPhysicsWorld.GetBodyPosition(body.BodyHandle);
			let rotation = mPhysicsWorld.GetBodyRotation(body.BodyHandle);

			// Determine color based on body type
			let bodyType = mPhysicsWorld.GetBodyType(body.BodyHandle);
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

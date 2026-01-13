# Engine Physics Integration

Entity-based physics integration for the Sedulous engine, providing automatic synchronization between game entities and the physics simulation.

## Overview

The engine physics integration consists of:

- **PhysicsService** - Context service that manages physics worlds per scene
- **PhysicsSceneComponent** - Scene component that owns the physics world and handles entity synchronization
- **RigidBodyComponent** - Entity component for adding physics to entities

## Quick Start

```beef
using Sedulous.Engine.Core;
using Sedulous.Engine.Physics;
using Sedulous.Physics;

// Create context
let context = new Context(null, 1);

// Create and register PhysicsService
let physicsService = new PhysicsService();
physicsService.SetGravity(.(0, -9.81f, 0));
context.RegisterService<PhysicsService>(physicsService);

// Start context
context.Startup();

// Create scene (PhysicsService automatically adds PhysicsSceneComponent)
let scene = context.SceneManager.CreateScene("MyScene");

// Create entity with physics
let entity = scene.CreateEntity("Box");
entity.Transform.SetPosition(.(0, 10, 0));

let rigidBody = new RigidBodyComponent();
rigidBody.BodyType = .Dynamic;
rigidBody.SetBoxShape(.(0.5f, 0.5f, 0.5f));
entity.AddComponent(rigidBody);

// Game loop
while (running)
{
    context.Update(deltaTime);  // Physics steps automatically
    // Entity transforms are automatically synced
}

// Cleanup
context.Shutdown();
delete physicsService;
```

## PhysicsService

The `PhysicsService` is a context-level service that:

1. Creates physics worlds for each scene
2. Manages `PhysicsSceneComponent` lifecycle
3. Provides global physics configuration

### Registration

```beef
let physicsService = new PhysicsService();
context.RegisterService<PhysicsService>(physicsService);
```

### Configuration

Configure before creating scenes:

```beef
// Set gravity
physicsService.SetGravity(.(0, -9.81f, 0));

// Set max bodies for large worlds
physicsService.SetMaxBodies(100000);

// Full configuration
PhysicsWorldDescriptor desc = .Large;
desc.Gravity = .(0, -20, 0);
physicsService.Configure(desc);
```

### Accessing Physics

```beef
// Get physics world for a scene
IPhysicsWorld world = physicsService.GetPhysicsWorld(scene);

// Get scene component
PhysicsSceneComponent component = physicsService.GetSceneComponent(scene);

// Create standalone physics world
let world = physicsService.CreatePhysicsWorld().Get();
```

## PhysicsSceneComponent

The `PhysicsSceneComponent` is automatically created by `PhysicsService` when a scene is created. It:

1. Owns the `IPhysicsWorld` for the scene
2. Manages entity-to-proxy mapping
3. Handles transform synchronization
4. Runs fixed timestep simulation

### Properties

```beef
let component = scene.GetSceneComponent<PhysicsSceneComponent>();

// Access physics world
IPhysicsWorld world = component.PhysicsWorld;

// Configure timestep
component.FixedTimeStep = 1.0f / 60.0f;  // 60 Hz (default)
component.MaxSubSteps = 8;                // Prevent spiral of death

// Statistics
int32 proxyCount = component.ProxyCount;
```

### Transform Synchronization

The component automatically synchronizes transforms:

| Body Type | Direction | When |
|-----------|-----------|------|
| Kinematic | Gameplay -> Physics | Before Step() |
| Dynamic | Physics -> Gameplay | After Step() |
| Static | None | Never |

Kinematic bodies follow entity transforms. Dynamic bodies update entity transforms from physics.

### Contact Listeners

```beef
class MyContactListener : IContactListener
{
    public bool OnContactAdded(BodyHandle body1, BodyHandle body2, ContactEvent event)
    {
        // Return false to disable contact (trigger behavior)
        return true;
    }

    public void OnContactPersisted(BodyHandle body1, BodyHandle body2, ContactEvent event) { }
    public void OnContactRemoved(BodyHandle body1, BodyHandle body2) { }
}

let listener = new MyContactListener();
component.SetContactListener(listener);
```

## RigidBodyComponent

The `RigidBodyComponent` adds physics to an entity. It automatically creates a physics body when attached to an entity with a `PhysicsSceneComponent`.

### Basic Usage

```beef
let entity = scene.CreateEntity("MyEntity");

let rigidBody = new RigidBodyComponent();
rigidBody.BodyType = .Dynamic;
entity.AddComponent(rigidBody);

// Set shape after attachment
rigidBody.SetBoxShape(.(1, 1, 1));
```

### Configuration

```beef
let rigidBody = new RigidBodyComponent();

// Body type
rigidBody.BodyType = .Dynamic;  // .Static, .Kinematic, .Dynamic

// Physics properties
rigidBody.Mass = 1.0f;
rigidBody.Friction = 0.5f;
rigidBody.Restitution = 0.3f;    // Bounciness
rigidBody.LinearDamping = 0.05f;
rigidBody.AngularDamping = 0.05f;
rigidBody.GravityFactor = 1.0f;  // 0 = no gravity

// Collision
rigidBody.Layer = 1;             // Collision layer
rigidBody.IsSensor = false;      // true for trigger volumes
rigidBody.AllowSleep = true;     // Allow sleep for optimization
```

### Setting Shapes

```beef
// Primitives
rigidBody.SetBoxShape(.(halfX, halfY, halfZ));
rigidBody.SetSphereShape(radius);
rigidBody.SetCapsuleShape(halfHeight, radius);

// Pre-created shape (doesn't transfer ownership)
let shape = physicsWorld.CreateBoxShape(halfExtents).Get();
rigidBody.SetShape(shape);
```

### Physics Actions

```beef
// Velocity
Vector3 vel = rigidBody.GetLinearVelocity();
rigidBody.SetLinearVelocity(.(10, 0, 0));

Vector3 angVel = rigidBody.GetAngularVelocity();
rigidBody.SetAngularVelocity(.(0, 1, 0));

// Forces (gradual)
rigidBody.AddForce(.(100, 0, 0));
rigidBody.AddTorque(.(0, 10, 0));

// Impulses (instant)
rigidBody.AddImpulse(.(0, 5, 0));

// Sleep control
rigidBody.Activate();    // Wake up
rigidBody.Deactivate();  // Force sleep
bool active = rigidBody.IsActive();
```

### Dynamic Body Type Changes

```beef
// Change body type at runtime
rigidBody.BodyType = .Kinematic;  // Now follows entity transform
// ... move entity ...
rigidBody.BodyType = .Dynamic;    // Now simulated
```

## Workflow Patterns

### Kinematic Platforms

```beef
// Create kinematic platform
let platform = scene.CreateEntity("Platform");
let rb = new RigidBodyComponent();
rb.BodyType = .Kinematic;
platform.AttachComponent(rb);
rb.SetBoxShape(.(2, 0.1f, 2));

// In update loop - move entity, physics follows
platform.Transform.SetPosition(newPosition);
```

### Picking Up Objects

```beef
// Make object kinematic to follow hand
void PickUp(Entity entity)
{
    let rb = entity.GetComponent<RigidBodyComponent>();
    rb.BodyType = .Kinematic;
}

// Drop object, make dynamic again
void Drop(Entity entity)
{
    let rb = entity.GetComponent<RigidBodyComponent>();
    rb.BodyType = .Dynamic;
    rb.SetLinearVelocity(throwVelocity);
}
```

### Triggers/Sensors

```beef
let trigger = scene.CreateEntity("TriggerZone");
let rb = new RigidBodyComponent();
rb.BodyType = .Static;
rb.IsSensor = true;  // Detects but doesn't collide
trigger.AttachComponent(rb);
rb.SetBoxShape(.(2, 2, 2));

// Use contact listener to detect overlaps
```

### Applying Forces

```beef
// Movement force (continuous)
void Update(float dt)
{
    if (moveInput != .Zero)
    {
        let force = moveInput * moveSpeed;
        rigidBody.AddForce(force);
    }
}

// Jump impulse (instant)
void Jump()
{
    if (isGrounded)
        rigidBody.AddImpulse(.(0, jumpForce, 0));
}
```

### Querying Physics

Access the physics world for queries:

```beef
let physicsWorld = physicsService.GetPhysicsWorld(scene);

// Ray cast
RayCastQuery query = .()
{
    Origin = camera.Position,
    Direction = camera.Forward,
    MaxDistance = 100
};

RayCastResult result;
if (physicsWorld.RayCast(query, out result))
{
    // result.Body, result.Position, etc.
}
```

## Architecture

```
Context
├── PhysicsService (registered)
│   └── OnSceneCreated() → creates PhysicsSceneComponent
│
└── Scene
    └── PhysicsSceneComponent
        ├── IPhysicsWorld (owns)
        ├── Entity → Proxy mapping
        └── Transform sync (kinematic ← entity, dynamic → entity)

Entity
└── RigidBodyComponent
    ├── BodyType, Mass, Friction, etc.
    ├── ShapeHandle
    └── ProxyHandle → PhysicsBodyProxy
```

## Fixed Timestep

The `PhysicsSceneComponent` uses fixed timestep with accumulator:

```
OnUpdate(deltaTime):
    accumulator += deltaTime

    while accumulator >= fixedTimeStep && steps < maxSubSteps:
        SyncGameplayToPhysics()  // Kinematic bodies
        PhysicsWorld.Step(fixedTimeStep)
        SyncPhysicsToGameplay()  // Dynamic bodies
        accumulator -= fixedTimeStep
        steps++

    // Clamp to prevent spiral of death
    if accumulator > fixedTimeStep * 2:
        accumulator = fixedTimeStep * 2
```

Default: 60 Hz with max 8 sub-steps per frame.

## Serialization

Both `PhysicsSceneComponent` and `RigidBodyComponent` support serialization:

- **PhysicsSceneComponent**: Serializes `fixedTimeStep`, `maxSubSteps`
- **RigidBodyComponent**: Serializes body type, mass, friction, restitution, damping, flags, layer

Note: Shapes are NOT serialized. They must be set up by application code after deserialization.

## Samples

- **EnginePhysics**: Demonstrates `PhysicsService`, entity creation, and transform synchronization

## See Also

- [Low-Level Physics API](../Physics.md)
- [Sedulous.Physics.Jolt implementation](../../Code/Sedulous/Sedulous.Physics.Jolt/)

# Sedulous Physics

Low-level physics simulation library providing an abstract interface for rigid body dynamics, collision detection, constraints, and character controllers.

## Overview

The physics system is organized into three main libraries:

- **Sedulous.Physics** - Abstract interfaces and types
- **Sedulous.Physics.Jolt** - Jolt Physics backend implementation
- **Sedulous.Engine.Physics** - Engine integration (see [Engine Physics](Engine/Physics.md))

## Quick Start

```beef
using Sedulous.Physics;
using Sedulous.Physics.Jolt;
using Sedulous.Mathematics;

// Create physics world
PhysicsWorldDescriptor worldDesc = .Default;
worldDesc.Gravity = .(0, -9.81f, 0);

let world = JoltPhysicsWorld.Create(worldDesc).Get();
defer delete world;

// Create shapes
let groundShape = world.CreateBoxShape(.(50, 0.5f, 50)).Get();
let sphereShape = world.CreateSphereShape(0.5f).Get();

// Create static ground
let ground = world.CreateBody(.Static(groundShape, .(0, -0.5f, 0))).Get();

// Create dynamic sphere
let sphere = world.CreateBody(.Dynamic(sphereShape, .(0, 10, 0))).Get();

// Simulation loop
while (running)
{
    world.Step(1.0f / 60.0f);
    let pos = world.GetBodyPosition(sphere);
    // Use position...
}

// Cleanup
world.DestroyBody(ground);
world.DestroyBody(sphere);
world.ReleaseShape(groundShape);
world.ReleaseShape(sphereShape);
```

## Core Concepts

### Handles

All physics objects are referenced through handles that combine an index with a generation counter. This prevents stale reference bugs when objects are destroyed and slots are reused.

```beef
struct BodyHandle     // Reference to a physics body
struct ShapeHandle    // Reference to a collision shape
struct ConstraintHandle  // Reference to a constraint/joint
struct CharacterHandle   // Reference to a character controller
```

Handles have an `IsValid` property and can be compared with `.Invalid`.

### Body Types

Bodies have three motion types:

| Type | Description |
|------|-------------|
| `Static` | Never moves, infinite mass. Used for ground, walls, static geometry. |
| `Kinematic` | Moved by code, affects dynamic bodies but isn't affected by them. Used for moving platforms, elevators. |
| `Dynamic` | Fully simulated with forces, gravity, and collisions. Used for physics objects. |

### Collision Layers

Bodies are assigned to layers (0-65535) for collision filtering:

- Layer 0: Typically static bodies
- Layer 1: Typically dynamic/kinematic bodies

Configure layer collision rules through the physics backend.

## World Configuration

```beef
struct PhysicsWorldDescriptor
{
    // Capacity
    uint32 MaxBodies = 65536;
    uint32 MaxBodyPairs = 65536;
    uint32 MaxContactConstraints = 10240;

    // Simulation
    Vector3 Gravity = .(0, -9.81f, 0);
    int32 VelocitySteps = 10;
    int32 PositionSteps = 2;

    // Presets
    static Self Small;    // MaxBodies = 1024
    static Self Default;  // MaxBodies = 65536
    static Self Large;    // MaxBodies = 262144
}
```

## Shapes

Shapes define collision geometry. Shapes can be shared between multiple bodies.

### Primitive Shapes

```beef
// Sphere
let sphere = world.CreateSphereShape(radius: 0.5f).Get();

// Box (half-extents)
let box = world.CreateBoxShape(.(1.0f, 0.5f, 1.0f)).Get();

// Capsule (Y-axis aligned)
let capsule = world.CreateCapsuleShape(halfHeight: 1.0f, radius: 0.3f).Get();

// Cylinder (Y-axis aligned)
let cylinder = world.CreateCylinderShape(halfHeight: 0.5f, radius: 0.4f).Get();
```

### Complex Shapes

```beef
// Convex hull from points
Vector3[8] points = ...;
let hull = world.CreateConvexHullShape(points).Get();

// Triangle mesh (static geometry only)
let mesh = world.CreateMeshShape(vertices, indices).Get();
```

### Shape Lifecycle

```beef
// Create shape
let shape = world.CreateBoxShape(.(1, 1, 1)).Get();

// Use in multiple bodies
let body1 = world.CreateBody(.Dynamic(shape, pos1)).Get();
let body2 = world.CreateBody(.Dynamic(shape, pos2)).Get();

// Release when done (only deletes if not referenced)
world.ReleaseShape(shape);
```

## Bodies

### Creating Bodies

```beef
// Using static helpers
let staticBody = world.CreateBody(.Static(shape, position)).Get();
let dynamicBody = world.CreateBody(.Dynamic(shape, position)).Get();
let kinematicBody = world.CreateBody(.Kinematic(shape, position)).Get();

// Full configuration
PhysicsBodyDescriptor desc = .();
desc.Shape = shape;
desc.Position = .(0, 5, 0);
desc.Rotation = .Identity;
desc.BodyType = .Dynamic;
desc.Layer = 1;
desc.Friction = 0.5f;
desc.Restitution = 0.3f;
desc.LinearDamping = 0.05f;
desc.AngularDamping = 0.05f;
desc.GravityFactor = 1.0f;
desc.MotionQuality = .Discrete;  // or .LinearCast for fast objects
desc.AllowedDOFs = .All;         // Restrict to .Plane2D for 2D games
desc.IsSensor = false;           // true for trigger volumes
desc.AllowSleep = true;

let body = world.CreateBody(desc).Get();
```

### Body Properties

```beef
// Transform
Vector3 pos = world.GetBodyPosition(body);
Quaternion rot = world.GetBodyRotation(body);
world.SetBodyTransform(body, newPos, newRot, activate: true);

// Velocity
Vector3 linearVel = world.GetLinearVelocity(body);
Vector3 angularVel = world.GetAngularVelocity(body);
world.SetLinearVelocity(body, .(1, 0, 0));
world.SetAngularVelocity(body, .(0, 1, 0));

// Body type
BodyType type = world.GetBodyType(body);
world.SetBodyType(body, .Kinematic);

// User data
world.SetBodyUserData(body, myEntityId);
uint64 data = world.GetBodyUserData(body);
```

### Forces and Impulses

```beef
// Force (gradual acceleration, applied over time)
world.AddForce(body, .(100, 0, 0));           // At center of mass
world.AddForceAtPosition(body, force, worldPos);
world.AddTorque(body, .(0, 10, 0));

// Impulse (instant velocity change)
world.AddImpulse(body, .(0, 5, 0));           // At center of mass
world.AddImpulseAtPosition(body, impulse, worldPos);
```

### Sleep/Activation

```beef
bool active = world.IsBodyActive(body);
world.ActivateBody(body);    // Wake up
world.DeactivateBody(body);  // Force sleep
```

## Queries

### Ray Casting

```beef
RayCastQuery query = .()
{
    Origin = .(0, 10, 0),
    Direction = .(0, -1, 0),
    MaxDistance = 100,
    LayerMask = 0xFFFF  // All layers
};

// Single closest hit
RayCastResult result;
if (world.RayCast(query, out result))
{
    Vector3 hitPos = result.Position;
    Vector3 hitNormal = result.Normal;
    float distance = result.Distance;
    BodyHandle hitBody = result.Body;
    uint64 userData = result.UserData;
}

// All hits
List<RayCastResult> results = scope .();
world.RayCastAll(query, results);
```

### Shape Casting

```beef
ShapeCastQuery query = .()
{
    Shape = sphereShape,
    Position = startPos,
    Rotation = .Identity,
    Direction = .(1, 0, 0),
    MaxDistance = 10
};

ShapeCastResult result;
if (world.ShapeCast(query, out result))
{
    // Handle hit
}
```

### Query Filters

```beef
class MyFilter : IQueryFilter
{
    public bool ShouldCollide(BodyHandle body)
    {
        // Return false to skip this body
        return body != mIgnoreBody;
    }
}

let filter = scope MyFilter();
world.RayCast(query, out result, filter);
```

## Constraints

Constraints connect two bodies and restrict their relative motion.

### Fixed Constraint

Locks two bodies together with no relative motion.

```beef
FixedConstraintDescriptor desc = .()
{
    Body1 = bodyA,
    Body2 = bodyB,
    Point1 = worldAnchor,
    Point2 = worldAnchor
};
let constraint = world.CreateFixedConstraint(desc).Get();
```

### Point Constraint (Ball-and-Socket)

Allows rotation around a point.

```beef
PointConstraintDescriptor desc = .()
{
    Body1 = bodyA,
    Body2 = bodyB,
    Point1 = anchorOnA,
    Point2 = anchorOnB
};
let constraint = world.CreatePointConstraint(desc).Get();
```

### Hinge Constraint

Rotation around a single axis, like a door hinge.

```beef
HingeConstraintDescriptor desc = .()
{
    Body1 = frame,
    Body2 = door,
    Point1 = hingePos,
    Point2 = hingePos,
    HingeAxis1 = .(0, 1, 0),  // Y-axis
    HingeAxis2 = .(0, 1, 0),
    NormalAxis1 = .(1, 0, 0),
    NormalAxis2 = .(1, 0, 0),
    HasLimits = true,
    LimitMin = -Math.PI_f / 2,  // -90 degrees
    LimitMax = Math.PI_f / 2    // +90 degrees
};
let hinge = world.CreateHingeConstraint(desc).Get();
```

### Slider Constraint

Linear motion along an axis.

```beef
SliderConstraintDescriptor desc = .()
{
    Body1 = rail,
    Body2 = slider,
    Point1 = startPos,
    Point2 = startPos,
    SliderAxis1 = .(1, 0, 0),
    SliderAxis2 = .(1, 0, 0),
    HasLimits = true,
    LimitMin = 0,
    LimitMax = 5.0f
};
let slider = world.CreateSliderConstraint(desc).Get();
```

### Distance Constraint

Maintains distance between two points (like a rope).

```beef
DistanceConstraintDescriptor desc = .()
{
    Body1 = anchor,
    Body2 = pendulum,
    Point1 = anchorPos,
    Point2 = pendulumPos,
    MinDistance = 1.0f,
    MaxDistance = 3.0f
};
let rope = world.CreateDistanceConstraint(desc).Get();
```

## Character Controllers

For player movement with ground detection and slope handling.

```beef
// Create capsule shape for character
let capsuleShape = world.CreateCapsuleShape(0.8f, 0.3f).Get();

CharacterDescriptor desc = .()
{
    Shape = capsuleShape,
    Position = .(0, 2, 0),
    Up = .(0, 1, 0),
    MaxSlopeAngle = Math.PI_f / 4,  // 45 degrees
    Mass = 80.0f,
    MaxStrength = 100.0f,
    CharacterPadding = 0.02f,
    PredictiveContactDistance = 0.1f,
    Friction = 0.5f,
    MaxStepHeight = 0.5f
};

let character = world.CreateCharacter(desc).Get();

// In update loop
world.Step(deltaTime);
world.UpdateCharacter(character, 0.1f);

// Query state
GroundState groundState = world.GetCharacterGroundState(character);
bool onGround = world.IsCharacterSupported(character);
Vector3 groundNormal = world.GetCharacterGroundNormal(character);
Vector3 groundVelocity = world.GetCharacterGroundVelocity(character);

// Move character
world.SetCharacterLinearVelocity(character, moveVelocity);
```

## Event Listeners

### Contact Listener

```beef
class MyContactListener : IContactListener
{
    public bool OnContactAdded(BodyHandle body1, BodyHandle body2, ContactEvent event)
    {
        // Called when bodies first touch
        Vector3 point = event.ContactPoint;
        Vector3 normal = event.Normal;
        float depth = event.PenetrationDepth;

        // Return false to disable this contact (sensor behavior)
        return true;
    }

    public void OnContactPersisted(BodyHandle body1, BodyHandle body2, ContactEvent event)
    {
        // Called each frame while contact continues
    }

    public void OnContactRemoved(BodyHandle body1, BodyHandle body2)
    {
        // Called when bodies separate
    }
}

world.SetContactListener(new MyContactListener());
```

### Body Activation Listener

```beef
class MyActivationListener : IBodyActivationListener
{
    public void OnBodyActivated(BodyHandle body)
    {
        // Body woke up
    }

    public void OnBodyDeactivated(BodyHandle body)
    {
        // Body went to sleep
    }
}

world.SetBodyActivationListener(new MyActivationListener());
```

## Simulation

### Stepping

```beef
float fixedTimeStep = 1.0f / 60.0f;
float accumulator = 0;

// In game loop
accumulator += deltaTime;
while (accumulator >= fixedTimeStep)
{
    world.Step(fixedTimeStep, collisionSteps: 1);
    accumulator -= fixedTimeStep;
}
```

### Optimization

After adding many bodies at once:

```beef
world.OptimizeBroadPhase();
```

### Statistics

```beef
uint32 totalBodies = world.BodyCount;
uint32 activeBodies = world.ActiveBodyCount;
```

## Best Practices

1. **Shape Reuse**: Create shapes once and share between bodies with identical geometry.

2. **Fixed Timestep**: Use a fixed timestep (e.g., 1/60s) for deterministic simulation.

3. **Layer Organization**: Use layer 0 for static, layer 1+ for dynamic to optimize broad phase.

4. **Motion Quality**: Use `LinearCast` for fast-moving objects to prevent tunneling.

5. **Sleep**: Enable sleep (`AllowSleep = true`) for bodies that can rest.

6. **Constraints vs Direct Positioning**: Use constraints for physical connections; use `SetBodyTransform` for teleportation.

7. **User Data**: Store entity IDs in body user data for easy lookup in callbacks.

## Samples

- **PhysicsSandbox**: Low-level API demonstration with shapes, bodies, forces, raycasting, and constraints.

## See Also

- [Engine Physics Integration](Engine/Physics.md)
- [Sedulous.Physics.Jolt implementation](../Code/Sedulous/Sedulous.Physics.Jolt/)

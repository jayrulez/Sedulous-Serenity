namespace PhysicsSandbox;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Physics;
using Sedulous.Physics.Jolt;

/// Low-level physics API demonstration.
/// Shows direct use of IPhysicsWorld for simulation, shapes, bodies, queries, and constraints.
class Program
{
	public static int Main(String[] args)
	{
		Console.WriteLine("=== Sedulous Physics Sandbox ===\n");

		// Create physics world
		PhysicsWorldDescriptor worldDesc = .Default;
		worldDesc.Gravity = .(0, -9.81f, 0);

		let worldResult = JoltPhysicsWorld.Create(worldDesc);
		if (worldResult case .Err)
		{
			Console.WriteLine("ERROR: Failed to create physics world!");
			return 1;
		}

		IPhysicsWorld world = worldResult.Get();
		defer delete world;

		Console.WriteLine("Physics world created successfully.");
		Console.WriteLine($"  Gravity: {world.Gravity}");
		Console.WriteLine();

		// Run demos
		BasicShapesDemo(world);
		ForcesAndImpulsesDemo(world);
		RayCastDemo(world);
		ConstraintsDemo(world);
		SimulationDemo(world);

		Console.WriteLine("\n=== Physics Sandbox Complete ===");
		return 0;
	}

	/// Demonstrates creating different shapes and bodies.
	static void BasicShapesDemo(IPhysicsWorld world)
	{
		Console.WriteLine("--- Basic Shapes Demo ---\n");

		// Create shapes
		let sphereShape = world.CreateSphereShape(0.5f).Get();
		let boxShape = world.CreateBoxShape(.(1.0f, 0.5f, 1.0f)).Get();
		let capsuleShape = world.CreateCapsuleShape(1.0f, 0.3f).Get();
		let cylinderShape = world.CreateCylinderShape(0.5f, 0.4f).Get();

		Console.WriteLine("Created shapes: Sphere, Box, Capsule, Cylinder");

		// Create static ground plane (large box)
		let groundShape = world.CreateBoxShape(.(50.0f, 0.5f, 50.0f)).Get();
		let groundDesc = PhysicsBodyDescriptor.Static(groundShape, .(0, -0.5f, 0));
		let groundBody = world.CreateBody(groundDesc).Get();

		Console.WriteLine("Created static ground body");

		// Create dynamic bodies
		let sphereBody = world.CreateBody(.Dynamic(sphereShape, .(0, 5, 0))).Get();
		let boxBody = world.CreateBody(.Dynamic(boxShape, .(2, 5, 0))).Get();
		let capsuleBody = world.CreateBody(.Dynamic(capsuleShape, .(-2, 5, 0))).Get();

		Console.WriteLine($"Created 3 dynamic bodies at Y=5");
		Console.WriteLine($"  Total bodies: {world.BodyCount}");
		Console.WriteLine($"  Active bodies: {world.ActiveBodyCount}");

		// Create kinematic body
		PhysicsBodyDescriptor kinematicDesc = .Kinematic(cylinderShape, .(0, 2, 3));
		let kinematicBody = world.CreateBody(kinematicDesc).Get();

		Console.WriteLine($"  Body types: {world.GetBodyType(groundBody)}, {world.GetBodyType(sphereBody)}, {world.GetBodyType(kinematicBody)}");

		// Demonstrate body properties
		Console.WriteLine($"\nSphere position: {world.GetBodyPosition(sphereBody)}");
		Console.WriteLine($"Sphere rotation: {world.GetBodyRotation(sphereBody)}");
		Console.WriteLine($"Sphere active: {world.IsBodyActive(sphereBody)}");

		// Set user data
		world.SetBodyUserData(sphereBody, 12345);
		Console.WriteLine($"Sphere user data: {world.GetBodyUserData(sphereBody)}");

		// Cleanup bodies for next demo
		world.DestroyBody(groundBody);
		world.DestroyBody(sphereBody);
		world.DestroyBody(boxBody);
		world.DestroyBody(capsuleBody);
		world.DestroyBody(kinematicBody);

		// Release shapes
		world.ReleaseShape(sphereShape);
		world.ReleaseShape(boxShape);
		world.ReleaseShape(capsuleShape);
		world.ReleaseShape(cylinderShape);
		world.ReleaseShape(groundShape);

		Console.WriteLine("\nCleaned up all bodies and shapes.\n");
	}

	/// Demonstrates applying forces and impulses.
	static void ForcesAndImpulsesDemo(IPhysicsWorld world)
	{
		Console.WriteLine("--- Forces and Impulses Demo ---\n");

		// Create a dynamic sphere
		let shape = world.CreateSphereShape(0.5f).Get();
		defer world.ReleaseShape(shape);

		let body = world.CreateBody(.Dynamic(shape, .(0, 2, 0))).Get();
		defer world.DestroyBody(body);

		Console.WriteLine($"Initial velocity: {world.GetLinearVelocity(body)}");

		// Apply force (gradual acceleration)
		world.AddForce(body, .(100, 0, 0));
		Console.WriteLine("Applied force: (100, 0, 0)");

		// Step to see effect
		world.Step(1.0f / 60.0f);
		Console.WriteLine($"Velocity after force: {world.GetLinearVelocity(body)}");

		// Apply impulse (instant velocity change)
		world.AddImpulse(body, .(0, 5, 0));
		Console.WriteLine("Applied impulse: (0, 5, 0)");
		Console.WriteLine($"Velocity after impulse: {world.GetLinearVelocity(body)}");

		// Apply torque
		world.AddTorque(body, .(0, 10, 0));
		world.Step(1.0f / 60.0f);
		Console.WriteLine($"Angular velocity after torque: {world.GetAngularVelocity(body)}");

		// Set velocity directly
		world.SetLinearVelocity(body, .(1, 2, 3));
		world.SetAngularVelocity(body, .(0, 1, 0));
		Console.WriteLine($"Set linear velocity: {world.GetLinearVelocity(body)}");
		Console.WriteLine($"Set angular velocity: {world.GetAngularVelocity(body)}");

		Console.WriteLine();
	}

	/// Demonstrates ray casting for collision queries.
	static void RayCastDemo(IPhysicsWorld world)
	{
		Console.WriteLine("--- Ray Cast Demo ---\n");

		// Create ground and some objects
		let groundShape = world.CreateBoxShape(.(50, 0.5f, 50)).Get();
		let sphereShape = world.CreateSphereShape(1.0f).Get();
		let boxShape = world.CreateBoxShape(.(1, 1, 1)).Get();
		defer world.ReleaseShape(groundShape);
		defer world.ReleaseShape(sphereShape);
		defer world.ReleaseShape(boxShape);

		let ground = world.CreateBody(.Static(groundShape, .(0, -0.5f, 0))).Get();
		let sphere = world.CreateBody(.Dynamic(sphereShape, .(0, 3, 0))).Get();
		let @box = world.CreateBody(.Static(boxShape, .(5, 1, 0))).Get();
		defer world.DestroyBody(ground);
		defer world.DestroyBody(sphere);
		defer world.DestroyBody(@box);

		// Set user data to identify bodies
		world.SetBodyUserData(ground, 1);
		world.SetBodyUserData(sphere, 2);
		world.SetBodyUserData(@box, 3);

		world.OptimizeBroadPhase();

		// Ray cast downward from above
		RayCastQuery downRay = .(.(0, 10, 0), .(0, -1, 0), 100);

		RayCastResult result = ?;
		if (world.RayCast(downRay, out result))
		{
			Console.WriteLine("Downward ray hit:");
			Console.WriteLine($"  Position: {result.Position}");
			Console.WriteLine($"  Normal: {result.Normal}");
			Console.WriteLine($"  Distance: {result.Distance}");
			Console.WriteLine($"  UserData: {result.UserData}");
		}

		// Ray cast horizontally
		RayCastQuery horizontalRay = .(.(- 10, 1, 0), .(1, 0, 0), 50);

		if (world.RayCast(horizontalRay, out result))
		{
			Console.WriteLine("\nHorizontal ray hit:");
			Console.WriteLine($"  Position: {result.Position}");
			Console.WriteLine($"  UserData: {result.UserData}");
		}

		// Ray cast all hits
		List<RayCastResult> allHits = scope .();
		world.RayCastAll(downRay, allHits);
		Console.WriteLine($"\nRay cast all: found {allHits.Count} hits");

		// Ray that misses
		RayCastQuery missRay = .(.(0, 10, 100), .(0, -1, 0), 5);

		if (!world.RayCast(missRay, out result))
			Console.WriteLine("Miss ray: no hit (as expected)");

		Console.WriteLine();
	}

	/// Demonstrates constraints between bodies.
	static void ConstraintsDemo(IPhysicsWorld world)
	{
		Console.WriteLine("--- Constraints Demo ---\n");

		// Create bodies for constraints
		let shape = world.CreateSphereShape(0.5f).Get();
		defer world.ReleaseShape(shape);

		// Create anchor (static) and pendulum (dynamic)
		let anchor = world.CreateBody(.Static(shape, .(0, 5, 0))).Get();
		let pendulum = world.CreateBody(.Dynamic(shape, .(2, 5, 0))).Get();
		defer world.DestroyBody(anchor);
		defer world.DestroyBody(pendulum);

		// Create distance constraint (like a rope)
		DistanceConstraintDescriptor distDesc = .()
		{
			Body1 = anchor,
			Body2 = pendulum,
			Point1 = .(0, 5, 0),
			Point2 = .(2, 5, 0),
			MinDistance = 1.5f,
			MaxDistance = 2.5f
		};

		if (world.CreateDistanceConstraint(distDesc) case .Ok(let constraint))
		{
			Console.WriteLine("Created distance constraint (rope)");
			Console.WriteLine($"  Constraint count: {world.ConstraintCount}");

			// Simulate a few steps
			for (int i < 30)
				world.Step(1.0f / 60.0f);

			Console.WriteLine($"  After simulation - Pendulum position: {world.GetBodyPosition(pendulum)}");

			world.DestroyConstraint(constraint);
			Console.WriteLine("  Constraint destroyed");
		}

		// Create hinge constraint demo
		let boxShape = world.CreateBoxShape(.(0.5f, 0.1f, 1.0f)).Get();
		defer world.ReleaseShape(boxShape);

		let door = world.CreateBody(.Dynamic(boxShape, .(0, 3, 0))).Get();
		let doorFrame = world.CreateBody(.Static(shape, .(0, 3, -1))).Get();
		defer world.DestroyBody(door);
		defer world.DestroyBody(doorFrame);

		HingeConstraintDescriptor hingeDesc = .()
		{
			Body1 = doorFrame,
			Body2 = door,
			Point1 = .(0, 3, -1),
			Point2 = .(0, 3, -1),
			HingeAxis1 = .(0, 1, 0),
			HingeAxis2 = .(0, 1, 0),
			NormalAxis1 = .(1, 0, 0),
			NormalAxis2 = .(1, 0, 0),
			HasLimits = true,
			LimitsMin = -Math.PI_f / 2,
			LimitsMax = Math.PI_f / 2
		};

		if (world.CreateHingeConstraint(hingeDesc) case .Ok(let hinge))
		{
			Console.WriteLine("Created hinge constraint (door)");
			Console.WriteLine($"  Constraint count: {world.ConstraintCount}");
			world.DestroyConstraint(hinge);
		}

		Console.WriteLine();
	}

	/// Demonstrates physics simulation over time.
	static void SimulationDemo(IPhysicsWorld world)
	{
		Console.WriteLine("--- Simulation Demo ---\n");

		// Create ground
		let groundShape = world.CreateBoxShape(.(50, 0.5f, 50)).Get();
		let ground = world.CreateBody(.Static(groundShape, .(0, -0.5f, 0))).Get();
		defer world.ReleaseShape(groundShape);
		defer world.DestroyBody(ground);

		// Create falling sphere
		let sphereShape = world.CreateSphereShape(0.5f).Get();
		let sphere = world.CreateBody(.Dynamic(sphereShape, .(0, 10, 0))).Get();
		defer world.ReleaseShape(sphereShape);
		defer world.DestroyBody(sphere);

		Console.WriteLine("Simulating sphere falling from Y=10...\n");
		Console.WriteLine(" Time    Y-Position    Y-Velocity    Active");
		Console.WriteLine("------  ------------  ------------  --------");

		float time = 0;
		float dt = 1.0f / 60.0f;

		// Simulate 3 seconds
		while (time < 3.0f)
		{
			world.Step(dt);
			time += dt;

			// Print every 0.5 seconds
			if (Math.Abs(Math.Round(time * 2) / 2 - time) < dt / 2)
			{
				let pos = world.GetBodyPosition(sphere);
				let vel = world.GetLinearVelocity(sphere);
				let active = world.IsBodyActive(sphere);
				Console.WriteLine($" {time:F2}s       {pos.Y:F4}       {vel.Y:F4}      {active}");
			}
		}

		Console.WriteLine($"\nFinal position: {world.GetBodyPosition(sphere)}");
		Console.WriteLine($"Body count: {world.BodyCount}, Active: {world.ActiveBodyCount}");

		Console.Read();
	}
}

namespace EnginePhysics;

using System;
using System.Collections;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Engine.Core;
using Sedulous.Engine.Physics;
using Sedulous.Mathematics;
using Sedulous.Physics;

/// Engine physics integration demonstration.
/// Shows how to use PhysicsService and RigidBodyComponent with entities.
class Program
{
	private static IShell mShell;
	private static Context mContext;
	private static PhysicsService mPhysicsService;
	private static Scene mScene;

	// Entity references for demonstration
	private static Entity mGroundEntity;
	private static Entity mFallingBox;
	private static Entity mKinematicPlatform;
	private static List<Entity> mStackedBoxes = new .() ~ delete _;

	// Simulation state
	private static float mTime = 0;
	private static float mPlatformAngle = 0;

	public static int Main(String[] args)
	{
		Console.WriteLine("=== Sedulous Engine Physics Sample ===");
		Console.WriteLine("Demonstrates entity-based physics integration.\n");

		// Initialize shell
		mShell = new SDL3Shell();
		defer delete mShell;

		if (mShell.Initialize() case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize shell");
			return 1;
		}

		// Create window
		let windowSettings = WindowSettings()
		{
			Title = "Engine Physics Sample",
			Width = 1280,
			Height = 720,
			Resizable = true,
			Bordered = true
		};

		if (mShell.WindowManager.CreateWindow(windowSettings) case .Err)
		{
			Console.WriteLine("ERROR: Failed to create window");
			return 1;
		}

		// Create engine context
		mContext = new Context(null, 1);
		defer delete mContext;

		// Create and register PhysicsService
		mPhysicsService = new PhysicsService();
		mPhysicsService.SetGravity(.(0, -9.81f, 0));
		mContext.RegisterService<PhysicsService>(mPhysicsService);

		// Start context (must happen before creating scenes)
		mContext.Startup();

		// Create scene (PhysicsService will automatically add PhysicsSceneComponent)
		mScene = mContext.SceneManager.CreateScene("PhysicsDemo");
		if (mScene == null)
		{
			Console.WriteLine("ERROR: Failed to create scene");
			return 1;
		}

		// Create entities with physics
		CreatePhysicsEntities();

		// Get the physics world for optimization
		let physicsWorld = mPhysicsService.GetPhysicsWorld(mScene);
		if (physicsWorld != null)
			physicsWorld.OptimizeBroadPhase();

		Console.WriteLine("Scene created with physics:");
		Console.WriteLine($"  - Ground (static)");
		Console.WriteLine($"  - Falling box (dynamic)");
		Console.WriteLine($"  - Platform (kinematic)");
		Console.WriteLine($"  - Stacked boxes (dynamic)\n");
		Console.WriteLine("Press ESC to exit.\n");

		// Main loop
		float lastPrintTime = 0;

		while (mShell.IsRunning)
		{
			mShell.ProcessEvents();

			if (mShell.InputManager.Keyboard.IsKeyPressed(.Escape))
			{
				mShell.RequestExit();
				continue;
			}

			float deltaTime = 1.0f / 60.0f;
			mTime += deltaTime;

			// Update kinematic platform
			UpdateKinematicPlatform(deltaTime);

			// Update engine (processes physics via PhysicsService and syncs transforms)
			mContext.Update(deltaTime);

			// Print status every second
			if (mTime - lastPrintTime >= 1.0f)
			{
				PrintStatus();
				lastPrintTime = mTime;
			}
		}

		// Cleanup
		mStackedBoxes.Clear();
		mContext.Shutdown();
		delete mPhysicsService;
		mShell.Shutdown();

		Console.WriteLine("\nEngine physics sample completed.");
		return 0;
	}

	/// Creates the physics entities.
	private static void CreatePhysicsEntities()
	{
		CreateGroundEntity();
		CreateFallingBox();
		CreateKinematicPlatform();
		CreateStackedBoxes();
	}

	/// Creates the static ground entity.
	private static void CreateGroundEntity()
	{
		mGroundEntity = mScene.CreateEntity("Ground");
		mGroundEntity.Transform.SetPosition(.(0, -0.5f, 0));

		let rigidBody = new RigidBodyComponent();
		rigidBody.BodyType = .Static;
		rigidBody.Friction = 0.6f;
		rigidBody.Layer = 0; // Static layer
		mGroundEntity.AddComponent(rigidBody);

		// Set box shape after attachment (when physics scene is available)
		rigidBody.SetBoxShape(.(50, 0.5f, 50));
	}

	/// Creates a falling dynamic box.
	private static void CreateFallingBox()
	{
		mFallingBox = mScene.CreateEntity("FallingBox");
		mFallingBox.Transform.SetPosition(.(0, 10, 0));

		let rigidBody = new RigidBodyComponent();
		rigidBody.BodyType = .Dynamic;
		rigidBody.Mass = 1.0f;
		rigidBody.Friction = 0.5f;
		rigidBody.Restitution = 0.3f;
		mFallingBox.AddComponent(rigidBody);

		rigidBody.SetBoxShape(.(0.5f, 0.5f, 0.5f));
	}

	/// Creates a kinematic platform that moves.
	private static void CreateKinematicPlatform()
	{
		mKinematicPlatform = mScene.CreateEntity("Platform");
		mKinematicPlatform.Transform.SetPosition(.(5, 2, 0));

		let rigidBody = new RigidBodyComponent();
		rigidBody.BodyType = .Kinematic;
		rigidBody.Layer = 1;
		mKinematicPlatform.AddComponent(rigidBody);

		rigidBody.SetBoxShape(.(2, 0.1f, 2));
	}

	/// Creates a stack of dynamic boxes.
	private static void CreateStackedBoxes()
	{
		float boxSize = 0.4f;
		int stackHeight = 5;

		for (int i < stackHeight)
		{
			let @box = mScene.CreateEntity(scope $"StackBox_{i}");
			@box.Transform.SetPosition(.(-3, boxSize + i * boxSize * 2.1f, 0));

			let rigidBody = new RigidBodyComponent();
			rigidBody.BodyType = .Dynamic;
			rigidBody.Mass = 0.5f;
			rigidBody.Friction = 0.7f;
			rigidBody.Restitution = 0.1f;
			@box.AddComponent(rigidBody);

			rigidBody.SetBoxShape(.(boxSize, boxSize, boxSize));
			mStackedBoxes.Add(@box);
		}
	}

	/// Updates the kinematic platform position.
	private static void UpdateKinematicPlatform(float deltaTime)
	{
		mPlatformAngle += deltaTime * 0.5f;

		// Move the platform in a circle
		float radius = 2.0f;
		float x = 5 + Math.Cos(mPlatformAngle) * radius;
		float z = Math.Sin(mPlatformAngle) * radius;

		// Set entity transform (PhysicsSceneComponent will sync to physics)
		mKinematicPlatform.Transform.SetPosition(.(x, 2, z));
	}

	/// Prints the current physics status.
	private static void PrintStatus()
	{
		let physicsWorld = mPhysicsService.GetPhysicsWorld(mScene);
		if (physicsWorld == null)
			return;

		Console.WriteLine($"[{mTime:F1}s] Bodies: {physicsWorld.BodyCount}, Active: {physicsWorld.ActiveBodyCount}");

		// Print falling box info
		let fallingPos = mFallingBox.Transform.Position;
		let fallingRb = mFallingBox.GetComponent<RigidBodyComponent>();
		if (fallingRb != null)
		{
			let vel = fallingRb.GetLinearVelocity();
			Console.WriteLine($"  FallingBox: pos=({fallingPos.X:F2}, {fallingPos.Y:F2}, {fallingPos.Z:F2}), vel.y={vel.Y:F2}, active={fallingRb.IsActive()}");
		}

		// Print platform info
		let platPos = mKinematicPlatform.Transform.Position;
		Console.WriteLine($"  Platform: pos=({platPos.X:F2}, {platPos.Y:F2}, {platPos.Z:F2})");

		// Print stack info
		int activeCount = 0;
		for (let @box in mStackedBoxes)
		{
			let rb = @box.GetComponent<RigidBodyComponent>();
			if (rb != null && rb.IsActive())
				activeCount++;
		}
		Console.WriteLine($"  Stack: {activeCount}/{mStackedBoxes.Count} active\n");
	}
}

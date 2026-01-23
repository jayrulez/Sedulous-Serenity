using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Animation;
using Sedulous.Framework.Physics;
using Sedulous.Framework.Audio;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;
using Sedulous.Physics;
using Sedulous.Physics.Jolt;
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Framework.Physics;
using Sedulous.Profiler;

namespace FrameworkSandbox;

/// Demonstrates the Sedulous Framework with Context, Subsystems, Scenes, and Entities.
class FrameworkSandboxApp : Application
{
	// Framework core (mContext is now owned by base Application)
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private Scene mMainScene;

	// Render system (needed by RenderSubsystem)
	private RenderSystem mRenderSystem ~ delete _;
	private RenderView mRenderView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private ForwardTransparentFeature mTransparentFeature;
	private ParticleFeature mParticleFeature;
	private SpriteFeature mSpriteFeature;
	private SkyFeature mSkyFeature;
	private DebugRenderFeature mDebugFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Test objects
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;
	private GPUMeshHandle mSphereMeshHandle;
	private MaterialInstance mCubeMaterial ~ delete _;
	private MaterialInstance mFloorMaterial ~ delete _;
	private MaterialInstance mSphereMaterial ~ delete _;

	// Entities
	private EntityId mFloorEntity;
	private EntityId mCubeEntity;
	private EntityId mCameraEntity;
	private EntityId mSunEntity;
	private List<EntityId> mDynamicEntities = new .() ~ delete _;
	private EntityId[4] mWallEntities;
	private EntityId mFireEntity;
	private EntityId mSmokeEntity;
	private EntityId mSparksEntity;
	private EntityId mMagicEntity;
	private EntityId mSpriteEntity;

	// Camera control
	private float mCameraYaw = 0.5f;
	private float mCameraPitch = 0.4f;
	private float mCameraDistance = 15.0f;
	private Vector3 mCameraTarget = .(0, 1.0f, 0);

	// Timing and FPS
	private float mDeltaTime = 0.016f;
	private float mSmoothedFps = 60.0f;

	// Spawning
	private bool mSpawningEnabled = false;
	private int32 mSpawnCount = 0;
	private float mSpawnTimer = 0.0f;
	private const float SpawnInterval = 0.075f;  // Time between spawns
	private const float ObjectRestitution = 0.3f;  // Bounciness

	// Debug draw toggle
	private bool mPhysicsDebugDraw = true;

	// Arena size
	private const float ArenaHalfSize = 10.0f;
	private const float WallHeight = 2.0f;
	private const float WallThickness = 0.5f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Context context)
	{
		Console.WriteLine("=== Framework Sandbox ===");
		Console.WriteLine("Demonstrating Sedulous Framework\n");

		// Physics tuning for high body counts
		FixedTimeStep = 1.0f / 30.0f;    // 30Hz physics (33ms budget per step)
		MaxFixedStepsPerFrame = 3;        // Cap catch-up to prevent spiral of death

		// Initialize render system first (before subsystems that depend on it)
		InitializeRenderSystem();

		// Register subsystems with the context (context is owned by base Application)
		RegisterSubsystems(context);
	}

	protected override void OnContextStarted()
	{
		// Initialize profiler
		SProfiler.Initialize();

		// Create the main scene (subsystems are now initialized)
		CreateMainScene();

		// Create scene objects
		CreateSceneObjects();

		Console.WriteLine("\n=== Initialization Complete ===");
		Console.WriteLine("Controls:");
		Console.WriteLine("  WASD: Rotate camera");
		Console.WriteLine("  Q/E: Zoom in/out");
		Console.WriteLine("  Space: Toggle spawn");
		Console.WriteLine("  F: Toggle physics debug draw");
		Console.WriteLine("  P: Print profiler stats");
		Console.WriteLine("\nParticle emitters:");
		Console.WriteLine("  Fire (right):  Color/size curves + turbulence");
		Console.WriteLine("  Smoke (above): Alpha curve + wind + turbulence");
		Console.WriteLine("  Sparks (left): Burst emission + stretched billboard + speed curve");
		Console.WriteLine("  Magic (back):  Vortex + attractor + size curve");
		Console.WriteLine("  ESC: Exit\n");
	}

	private void InitializeRenderSystem()
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope $"{AssetDirectory}/Render/Shaders", .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}
		Console.WriteLine("RenderSystem initialized");

		// Create render view
		mRenderView = new RenderView();
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.FieldOfView = Math.PI_f / 4.0f;
		mRenderView.NearPlane = 0.1f;
		mRenderView.FarPlane = 100.0f;

		// Register render features
		RegisterRenderFeatures();
	}

	private void RegisterRenderFeatures()
	{
		// Depth prepass
		mDepthFeature = new DepthPrepassFeature();
		if (mRenderSystem.RegisterFeature(mDepthFeature) case .Ok)
			Console.WriteLine("Registered: DepthPrepassFeature");

		// Forward opaque
		mForwardFeature = new ForwardOpaqueFeature();
		if (mRenderSystem.RegisterFeature(mForwardFeature) case .Ok)
			Console.WriteLine("Registered: ForwardOpaqueFeature");

		// Forward transparent
		mTransparentFeature = new ForwardTransparentFeature();
		if (mRenderSystem.RegisterFeature(mTransparentFeature) case .Ok)
			Console.WriteLine("Registered: ForwardTransparentFeature");

		// Particles
		mParticleFeature = new ParticleFeature();
		if (mRenderSystem.RegisterFeature(mParticleFeature) case .Ok)
			Console.WriteLine("Registered: ParticleFeature");

		// Sprites
		mSpriteFeature = new SpriteFeature();
		if (mRenderSystem.RegisterFeature(mSpriteFeature) case .Ok)
			Console.WriteLine("Registered: SpriteFeature");

		// Sky
		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Ok)
			Console.WriteLine("Registered: SkyFeature");

		// Debug render (for physics debug draw)
		mDebugFeature = new DebugRenderFeature();
		if (mRenderSystem.RegisterFeature(mDebugFeature) case .Ok)
			Console.WriteLine("Registered: DebugRenderFeature");

		// Final output
		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Ok)
			Console.WriteLine("Registered: FinalOutputFeature");
	}

	private void RegisterSubsystems(Context context)
	{
		Console.WriteLine("\nRegistering subsystems...");

		// Scene subsystem (manages scenes)
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);
		Console.WriteLine("  - SceneSubsystem (manages scene lifecycle)");

		// Animation subsystem
		let animSubsystem = new AnimationSubsystem();
		context.RegisterSubsystem(animSubsystem);
		Console.WriteLine("  - AnimationSubsystem (skeletal animation)");

		// Audio subsystem
		let audioSystem = new SDL3AudioSystem();
		if (audioSystem.IsInitialized)
		{
			let audioSubsystem = new AudioSubsystem(audioSystem, takeOwnership: true);
			context.RegisterSubsystem(audioSubsystem);
			Console.WriteLine("  - AudioSubsystem (SDL3 backend)");
		}
		else
		{
			delete audioSystem;
			Console.WriteLine("  - AudioSubsystem SKIPPED (failed to initialize)");
		}

		// Physics subsystem
		let physicsSubsystem = new PhysicsSubsystem(
			new (desc) => {
				switch (JoltPhysicsWorld.Create(desc))
				{
				case .Ok(let world): return .Ok(world);
				case .Err: return .Err;
				}
			}
		);
		context.RegisterSubsystem(physicsSubsystem);
		Console.WriteLine("  - PhysicsSubsystem (Jolt backend)");

		// Render subsystem
		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);
		Console.WriteLine("  - RenderSubsystem");
	}

	private void CreateMainScene()
	{
		Console.WriteLine("\nCreating main scene...");

		// Create scene through SceneSubsystem (notifies ISceneAware subsystems)
		mMainScene = mSceneSubsystem.CreateScene("MainScene");
		mSceneSubsystem.SetActiveScene(mMainScene);

		// Add our custom gameplay module
		let gameplayModule = new GameplaySceneModule();
		mMainScene.AddModule(gameplayModule);

		Console.WriteLine("Scene created with modules:");
		// List modules that were auto-added by ISceneAware subsystems
		Console.WriteLine("  - GameplaySceneModule (custom)");
		Console.WriteLine("  - AnimationSceneModule (from AnimationSubsystem)");
		Console.WriteLine("  - AudioSceneModule (from AudioSubsystem)");
		Console.WriteLine("  - PhysicsSceneModule (from PhysicsSubsystem)");
		Console.WriteLine("  - RenderSceneModule (from RenderSubsystem)");
	}

	private void CreateSceneObjects()
	{
		Console.WriteLine("\nCreating scene objects...");

		// Get render module for creating render components
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		if (renderModule == null)
		{
			Console.WriteLine("ERROR: RenderSceneModule not found!");
			return;
		}

		// Get physics module for creating physics bodies
		let physicsModule = mMainScene.GetModule<PhysicsSceneModule>();
		if (physicsModule != null)
		{
			// Enable physics debug draw
			physicsModule.DebugDrawEnabled = true;
			Console.WriteLine("Physics debug draw enabled");
		}

		// Create meshes
		CreateMeshes();

		// Get default material
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Create materials
		if (let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			mCubeMaterial = new MaterialInstance(baseMaterial);
			mCubeMaterial.SetColor("BaseColor", .(0.2f, 0.6f, 0.9f, 1.0f));

			mFloorMaterial = new MaterialInstance(baseMaterial);
			mFloorMaterial.SetColor("BaseColor", .(0.8f, 0.8f, 0.8f, 1.0f));

			mSphereMaterial = new MaterialInstance(baseMaterial);
			mSphereMaterial.SetColor("BaseColor", .(0.9f, 0.3f, 0.2f, 1.0f));  // Red sphere
		}

		// Create floor entity
		mFloorEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFloorEntity);
			transform.Position = .(0, -0.5f, 0);  // Position below origin so top surface is at y=0
			mMainScene.SetTransform(mFloorEntity, transform);

			let handle = renderModule.CreateMeshRenderer(mFloorEntity);
			if (handle.IsValid)
			{
				renderModule.SetMeshData(mFloorEntity, mPlaneMeshHandle, BoundingBox(Vector3(-ArenaHalfSize, 0, -ArenaHalfSize), Vector3(ArenaHalfSize, 0.01f, ArenaHalfSize)));
				renderModule.SetMeshMaterial(mFloorEntity, mFloorMaterial ?? defaultMaterial);
			}

			// Add static physics body (thin box for floor)
			if (physicsModule != null)
				physicsModule.CreateBoxBody(mFloorEntity, .(ArenaHalfSize, 0.5f, ArenaHalfSize), .Static);
		}
		Console.WriteLine("  Created floor entity with static physics body");

		// Create wall entities (banks at edges - physics only, rendered by debug draw)
		if (physicsModule != null)
		{
			// Wall positions: +X, -X, +Z, -Z
			Vector3[4] wallPositions = .(
				.(ArenaHalfSize + WallThickness * 0.5f, WallHeight * 0.5f, 0),  // +X wall
				.(-ArenaHalfSize - WallThickness * 0.5f, WallHeight * 0.5f, 0), // -X wall
				.(0, WallHeight * 0.5f, ArenaHalfSize + WallThickness * 0.5f),  // +Z wall
				.(0, WallHeight * 0.5f, -ArenaHalfSize - WallThickness * 0.5f)  // -Z wall
			);
			Vector3[4] wallHalfExtents = .(
				.(WallThickness * 0.5f, WallHeight * 0.5f, ArenaHalfSize),  // +X wall (thin in X)
				.(WallThickness * 0.5f, WallHeight * 0.5f, ArenaHalfSize),  // -X wall
				.(ArenaHalfSize, WallHeight * 0.5f, WallThickness * 0.5f),  // +Z wall (thin in Z)
				.(ArenaHalfSize, WallHeight * 0.5f, WallThickness * 0.5f)   // -Z wall
			);

			for (int i = 0; i < 4; i++)
			{
				mWallEntities[i] = mMainScene.CreateEntity();
				var transform = mMainScene.GetTransform(mWallEntities[i]);
				transform.Position = wallPositions[i];
				mMainScene.SetTransform(mWallEntities[i], transform);
				physicsModule.CreateBoxBody(mWallEntities[i], wallHalfExtents[i], .Static);
			}
			Console.WriteLine("  Created 4 wall entities (banks at edges)");
		}

		// Create spinning cube entity
		mCubeEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mCubeEntity);
			transform.Position = .(0, 0.5f, 0);
			mMainScene.SetTransform(mCubeEntity, transform);

			// Add custom components
			mMainScene.SetComponent<SpinComponent>(mCubeEntity, SpinComponent() { Speed = 1.0f, CurrentAngle = 0 });
			mMainScene.SetComponent<BobComponent>(mCubeEntity, BobComponent() { Speed = 2.0f, Amplitude = 0.2f, BaseY = 0.5f, Phase = 0 });

			let handle = renderModule.CreateMeshRenderer(mCubeEntity);
			if (handle.IsValid)
			{
				renderModule.SetMeshData(mCubeEntity, mCubeMeshHandle, BoundingBox(Vector3(-0.5f), Vector3(0.5f)));
				renderModule.SetMeshMaterial(mCubeEntity, mCubeMaterial ?? defaultMaterial);
			}

			// Add kinematic physics body (controlled by gameplay, not physics simulation)
			if (physicsModule != null)
				physicsModule.CreateBoxBody(mCubeEntity, .(0.5f, 0.5f, 0.5f), .Kinematic);
		}
		Console.WriteLine("  Created spinning cube entity with kinematic physics body");

		// Create multiple dynamic objects (simulated by physics)
		if (physicsModule != null)
		{
			// Spawn positions for falling objects (spread around the arena)
			Vector3[?] spawnPositions = .(
				.(2.0f, 5.0f, 2.0f),
				.(-3.0f, 6.0f, 1.0f),
				.(4.0f, 7.0f, -2.0f),
				.(-2.0f, 4.0f, -3.0f),
				.(0.0f, 8.0f, 4.0f),
				.(5.0f, 5.0f, 0.0f),
				.(-4.0f, 6.0f, -4.0f),
				.(3.0f, 9.0f, 3.0f),
				.(-1.0f, 7.0f, -1.0f),
				.(1.0f, 10.0f, -4.0f)
			);

			for (int i = 0; i < spawnPositions.Count; i++)
			{
				let entity = mMainScene.CreateEntity();
				mDynamicEntities.Add(entity);

				var transform = mMainScene.GetTransform(entity);
				transform.Position = spawnPositions[i];
				mMainScene.SetTransform(entity, transform);

				let handle = renderModule.CreateMeshRenderer(entity);
				if (handle.IsValid)
				{
					renderModule.SetMeshData(entity, mSphereMeshHandle, BoundingBox(Vector3(-0.3f), Vector3(0.3f)));
					renderModule.SetMeshMaterial(entity, mSphereMaterial ?? defaultMaterial);
				}

				// Add dynamic physics body - will fall and bounce
				physicsModule.CreateSphereBody(entity, 0.3f, .Dynamic, ObjectRestitution);
				mSpawnCount++;
			}
			Console.WriteLine("  Created {} dynamic sphere entities (physics-simulated)", spawnPositions.Count);
		}

		// Create camera entity
		mCameraEntity = mMainScene.CreateEntity();
		{
			renderModule.CreatePerspectiveCamera(mCameraEntity, Math.PI_f / 4.0f, (float)mSwapChain.Width / mSwapChain.Height, 0.1f, 100.0f);
			renderModule.SetMainCamera(mCameraEntity);
		}
		Console.WriteLine("  Created camera entity");

		// Create sun light entity
		mSunEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSunEntity);
			// Point light direction via transform forward
			transform.Rotation = Quaternion.CreateFromAxisAngle(.(1, 0, 0), -0.8f) * Quaternion.CreateFromAxisAngle(.(0, 1, 0), 0.5f);
			mMainScene.SetTransform(mSunEntity, transform);

			renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.98f, 0.95f), 2.0f);
		}
		Console.WriteLine("  Created sun light entity");

		// Create fire particle emitter (with color/size curves)
		mFireEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFireEntity);
			transform.Position = .(3.0f, 0.0f, -2.0f);
			mMainScene.SetTransform(mFireEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mFireEntity, 2000);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mFireEntity))
				{
					proxy.SpawnRate = 200.0f;
					proxy.ParticleLifetime = 1.2f;
					proxy.BlendMode = .Additive;
					proxy.InitialVelocity = .(0.0f, 2.0f, 0.0f);
					proxy.VelocityRandomness = .(0.5f, 0.3f, 0.5f);
					proxy.GravityMultiplier = -0.3f;
					proxy.Drag = 1.0f;
					proxy.SortParticles = false;
					proxy.LifetimeVarianceMin = 0.7f;
					proxy.LifetimeVarianceMax = 1.3f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					// Color curve: bright yellow -> orange -> dark red -> transparent
					proxy.ColorOverLifetime = .();
					proxy.ColorOverLifetime.AddKey(0.0f, .(1.0f, 0.9f, 0.3f, 1.0f));
					proxy.ColorOverLifetime.AddKey(0.2f, .(1.0f, 0.6f, 0.1f, 0.9f));
					proxy.ColorOverLifetime.AddKey(0.6f, .(0.8f, 0.2f, 0.0f, 0.5f));
					proxy.ColorOverLifetime.AddKey(1.0f, .(0.3f, 0.0f, 0.0f, 0.0f));

					// Size curve: grows then shrinks
					proxy.SizeOverLifetime = .();
					proxy.SizeOverLifetime.AddKey(0.0f, .(0.05f, 0.05f));
					proxy.SizeOverLifetime.AddKey(0.15f, .(0.18f, 0.18f));
					proxy.SizeOverLifetime.AddKey(1.0f, .(0.02f, 0.02f));

					// Slight turbulence for flickering
					proxy.ForceModules.TurbulenceStrength = 1.5f;
					proxy.ForceModules.TurbulenceFrequency = 3.0f;
					proxy.ForceModules.TurbulenceSpeed = 2.0f;

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Cone(0.3f, 0.1f);
				}
			}
		}
		Console.WriteLine("  Created fire particle emitter (curves + turbulence)");

		// Create smoke particle emitter (turbulence + alpha fade curve)
		mSmokeEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSmokeEntity);
			transform.Position = .(3.0f, 0.8f, -2.0f);
			mMainScene.SetTransform(mSmokeEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mSmokeEntity, 1000);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mSmokeEntity))
				{
					proxy.SpawnRate = 30.0f;
					proxy.ParticleLifetime = 4.0f;
					proxy.BlendMode = .Alpha;
					proxy.StartColor = .(0.4f, 0.4f, 0.4f, 0.5f);
					proxy.EndColor = .(0.3f, 0.3f, 0.3f, 0.0f);
					proxy.InitialVelocity = .(0.0f, 0.8f, 0.0f);
					proxy.VelocityRandomness = .(0.3f, 0.1f, 0.3f);
					proxy.GravityMultiplier = -0.1f;
					proxy.Drag = 0.6f;
					proxy.SortParticles = true;
					proxy.SoftParticleDistance = 0.5f;
					proxy.LifetimeVarianceMin = 0.8f;
					proxy.LifetimeVarianceMax = 1.5f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					// Size grows over lifetime
					proxy.SizeOverLifetime = .Linear(.(0.08f, 0.08f), .(0.5f, 0.5f));

					// Alpha fades after half lifetime
					proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.4f);

					// Turbulence for organic drift
					proxy.ForceModules.TurbulenceStrength = 0.6f;
					proxy.ForceModules.TurbulenceFrequency = 1.0f;
					proxy.ForceModules.TurbulenceSpeed = 0.4f;

					// Gentle wind
					proxy.ForceModules.WindForce = .(0.3f, 0, 0.1f);
					proxy.ForceModules.WindTurbulence = 0.15f;

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Cone(0.4f, 0.1f);
				}
			}
		}
		Console.WriteLine("  Created smoke particle emitter (turbulence + wind + alpha curve)");

		// Create sparks emitter (burst emission + stretched billboards + gravity)
		mSparksEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSparksEntity);
			transform.Position = .(-3.0f, 0.5f, -2.0f);
			mMainScene.SetTransform(mSparksEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mSparksEntity, 500);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mSparksEntity))
				{
					proxy.SpawnRate = 0; // No continuous spawn
					proxy.BurstCount = 30;
					proxy.BurstInterval = 2.0f; // Burst every 2 seconds
					proxy.BurstCycles = 0; // Infinite bursts
					proxy.ParticleLifetime = 1.5f;
					proxy.BlendMode = .Additive;
					proxy.RenderMode = .StretchedBillboard;
					proxy.StretchFactor = 2.5f;
					proxy.StartColor = .(1.0f, 0.8f, 0.3f, 1.0f);
					proxy.EndColor = .(1.0f, 0.2f, 0.0f, 0.0f);
					proxy.StartSize = .(0.02f, 0.02f);
					proxy.EndSize = .(0.005f, 0.005f);
					proxy.InitialVelocity = .(0.0f, 4.0f, 0.0f);
					proxy.VelocityRandomness = .(2.5f, 2.0f, 2.5f);
					proxy.GravityMultiplier = 2.0f;
					proxy.Drag = 0.3f;
					proxy.LifetimeVarianceMin = 0.4f;
					proxy.LifetimeVarianceMax = 1.0f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					// Speed decays over lifetime
					proxy.SpeedOverLifetime = .Linear(1.0f, 0.2f);

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Sphere(0.05f, true);
				}
			}
		}
		Console.WriteLine("  Created sparks emitter (burst + stretched billboard + speed curve)");

		// Create magic orb emitter (vortex + attractor + additive)
		mMagicEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mMagicEntity);
			transform.Position = .(-3.0f, 1.5f, 2.0f);
			mMainScene.SetTransform(mMagicEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mMagicEntity, 1000);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mMagicEntity))
				{
					proxy.SpawnRate = 40.0f;
					proxy.ParticleLifetime = 3.0f;
					proxy.BlendMode = .Additive;
					proxy.StartColor = .(0.3f, 0.5f, 1.0f, 0.8f);
					proxy.EndColor = .(0.6f, 0.2f, 1.0f, 0.0f);
					proxy.InitialVelocity = .Zero;
					proxy.VelocityRandomness = .(0.3f, 0.3f, 0.3f);
					proxy.GravityMultiplier = -0.15f;
					proxy.Drag = 0.5f;
					proxy.LifetimeVarianceMin = 0.8f;
					proxy.LifetimeVarianceMax = 1.2f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					// Size pulses: small -> big -> small -> gone
					proxy.SizeOverLifetime = .();
					proxy.SizeOverLifetime.AddKey(0.0f, .(0.01f, 0.01f));
					proxy.SizeOverLifetime.AddKey(0.25f, .(0.07f, 0.07f));
					proxy.SizeOverLifetime.AddKey(0.5f, .(0.03f, 0.03f));
					proxy.SizeOverLifetime.AddKey(0.75f, .(0.05f, 0.05f));
					proxy.SizeOverLifetime.AddKey(1.0f, .(0.0f, 0.0f));

					// Alpha fades out
					proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.7f);

					// Vortex makes particles swirl
					proxy.ForceModules.VortexStrength = 3.0f;
					proxy.ForceModules.VortexAxis = .(0, 1, 0);
					proxy.ForceModules.VortexCenter = .(-3.0f, 1.5f, 2.0f);

					// Attractor keeps them orbiting
					proxy.ForceModules.AttractorStrength = 2.0f;
					proxy.ForceModules.AttractorPosition = .(-3.0f, 1.5f, 2.0f);
					proxy.ForceModules.AttractorRadius = 2.0f;

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Sphere(0.8f);
				}
			}
		}
		Console.WriteLine("  Created magic orb emitter (vortex + attractor + size curve)");

		// Create test sprite (floating marker near the fire)
		mSpriteEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSpriteEntity);
			transform.Position = .(-3.0f, 1.5f, -1.0f);
			mMainScene.SetTransform(mSpriteEntity, transform);

			let handle = renderModule.CreateSprite(mSpriteEntity);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetSpriteProxy(mSpriteEntity))
				{
					proxy.Size = .(0.5f, 0.5f);
					proxy.Color = .(0.2f, 0.8f, 1.0f, 1.0f);  // Cyan tint
					proxy.UVRect = .(0, 0, 1, 1);
				}
			}
		}
		Console.WriteLine("  Created test sprite");

		// Set world ambient
		if (let world = renderModule.World)
		{
			world.AmbientColor = .(0.05f, 0.05f, 0.08f);
			world.AmbientIntensity = 1.0f;
		}

		Console.WriteLine("\nEntity count: {}", mMainScene.EntityCount);
	}

	private void CreateMeshes()
	{
		// Create cube mesh
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let cubeHandle))
			mCubeMeshHandle = cubeHandle;
		delete cubeMesh;

		// Create floor plane mesh (sized to arena)
		let planeMesh = StaticMesh.CreatePlane(ArenaHalfSize * 2, ArenaHalfSize * 2, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let planeHandle))
			mPlaneMeshHandle = planeHandle;
		delete planeMesh;

		// Create sphere mesh
		let sphereMesh = StaticMesh.CreateSphere(0.3f, 16, 12);
		if (mRenderSystem.ResourceManager.UploadMesh(sphereMesh) case .Ok(let sphereHandle))
			mSphereMeshHandle = sphereHandle;
		delete sphereMesh;
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		// Toggle spawning
		if (keyboard.IsKeyPressed(.Space))
			mSpawningEnabled = !mSpawningEnabled;

		// Toggle physics debug draw
		if (keyboard.IsKeyPressed(.F))
		{
			mPhysicsDebugDraw = !mPhysicsDebugDraw;
			if (let physicsModule = mMainScene?.GetModule<PhysicsSceneModule>())
				physicsModule.DebugDrawEnabled = mPhysicsDebugDraw;
		}

		// Print profiler stats
		if (keyboard.IsKeyPressed(.P))
			PrintProfilerStats();

		// Camera rotation
		float rotSpeed = 0.02f;
		if (keyboard.IsKeyDown(.A))
			mCameraYaw -= rotSpeed;
		if (keyboard.IsKeyDown(.D))
			mCameraYaw += rotSpeed;
		if (keyboard.IsKeyDown(.W))
			mCameraPitch = Math.Clamp(mCameraPitch + rotSpeed, -1.4f, 1.4f);
		if (keyboard.IsKeyDown(.S))
			mCameraPitch = Math.Clamp(mCameraPitch - rotSpeed, -1.4f, 1.4f);

		// Camera zoom
		if (keyboard.IsKeyDown(.Q))
			mCameraDistance = Math.Clamp(mCameraDistance - 0.1f, 2.0f, 20.0f);
		if (keyboard.IsKeyDown(.E))
			mCameraDistance = Math.Clamp(mCameraDistance + 0.1f, 2.0f, 20.0f);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = (float)frame.DeltaTime;

		// Update smoothed FPS (exponential moving average)
		if (mDeltaTime > 0)
		{
			let instantFps = 1.0f / mDeltaTime;
			mSmoothedFps = mSmoothedFps * 0.95f + instantFps * 0.05f;
		}

		// Spawn objects when enabled
		if (mSpawningEnabled && mSpawnCount < 1200)
		{
			mSpawnTimer += mDeltaTime;
			while (mSpawnTimer >= SpawnInterval)
			{
				mSpawnTimer -= SpawnInterval;
				SpawnObject();
			}
		}

		// Framework context update is now handled by base Application:
		// - BeginFrame before OnUpdate
		// - Update/PostUpdate after OnUpdate
		// - EndFrame after Frame

		// Update camera transform
		UpdateCamera();
	}

	private void SpawnObject()
	{
		if (mMainScene == null)
			return;

		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		let physicsModule = mMainScene.GetModule<PhysicsSceneModule>();
		if (renderModule == null || physicsModule == null)
			return;

		// Random position above the arena
		let rand = scope System.Random();
		let x = (rand.NextDouble() * 2.0 - 1.0) * (ArenaHalfSize - 1.0);
		let z = (rand.NextDouble() * 2.0 - 1.0) * (ArenaHalfSize - 1.0);
		let y = 8.0 + rand.NextDouble() * 5.0;

		let entity = mMainScene.CreateEntity();
		mDynamicEntities.Add(entity);

		var transform = mMainScene.GetTransform(entity);
		transform.Position = .((float)x, (float)y, (float)z);
		mMainScene.SetTransform(entity, transform);

		let handle = renderModule.CreateMeshRenderer(entity);
		if (handle.IsValid)
		{
			renderModule.SetMeshData(entity, mSphereMeshHandle, BoundingBox(Vector3(-0.3f), Vector3(0.3f)));
			let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
			renderModule.SetMeshMaterial(entity, mSphereMaterial ?? defaultMaterial);
		}

		physicsModule.CreateSphereBody(entity, 0.3f, .Dynamic, ObjectRestitution);
		mSpawnCount++;
	}

	private void UpdateCamera()
	{
		// Calculate orbital camera position
		float x = mCameraDistance * Math.Cos(mCameraPitch) * Math.Sin(mCameraYaw);
		float y = mCameraDistance * Math.Sin(mCameraPitch);
		float z = mCameraDistance * Math.Cos(mCameraPitch) * Math.Cos(mCameraYaw);

		let cameraPos = mCameraTarget + Vector3(x, y, z);
		let cameraForward = Vector3.Normalize(mCameraTarget - cameraPos);

		// Update camera entity transform
		var transform = mMainScene.GetTransform(mCameraEntity);
		transform.Position = cameraPos;
		// Calculate rotation from forward vector
		let yaw = Math.Atan2(cameraForward.X, cameraForward.Z);
		let pitch = Math.Asin(-cameraForward.Y);
		transform.Rotation = Quaternion.CreateFromYawPitchRoll(yaw, pitch, 0);
		mMainScene.SetTransform(mCameraEntity, transform);

		// Also update render view for rendering
		mRenderView.CameraPosition = cameraPos;
		mRenderView.CameraForward = cameraForward;
		mRenderView.CameraUp = .(0, 1, 0);
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		// Begin frame
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		// Set swapchain for final output
		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		// Set the active world from the scene's render module
		if (let renderModule = mMainScene?.GetModule<RenderSceneModule>())
		{
			if (let world = renderModule.World)
				mRenderSystem.SetActiveWorld(world);
		}

		// Draw debug HUD
		if (mDebugFeature != null)
		{
			let bgColor = Color(0, 0, 0, 180);
			let brightBlue = Color(100, 180, 255, 255);
			let brightCyan = Color(100, 255, 255, 255);
			let brightGreen = Color(100, 255, 100, 255);

			// Background for top-left instructions
			mDebugFeature.AddRect2D(5, 5, 420, 20, bgColor);
			mDebugFeature.AddText2D("WASD: Camera  Q/E: Zoom  Space: Spawn  F: Debug  ESC: Exit", 10, 8, brightBlue, 1.0f);

			// Background for top-right stats panel
			mDebugFeature.AddRect2D((float)mRenderView.Width - 155, 5, 150, 95, bgColor);

			// FPS display (top right)
			let fpsInt = (int32)Math.Round(mSmoothedFps);
			let fpsText = scope String();
			fpsInt.ToString(fpsText);
			mDebugFeature.AddText2D("FPS:", (float)mRenderView.Width - 100, 10, brightBlue, 1.5f);
			mDebugFeature.AddText2DRight(fpsText, 10, 10, brightCyan, 1.5f);

			// Spawn count display
			let countText = scope String();
			mSpawnCount.ToString(countText);
			mDebugFeature.AddText2D("Objects:", (float)mRenderView.Width - 140, 32, brightBlue, 1.5f);
			mDebugFeature.AddText2DRight(countText, 10, 32, brightCyan, 1.5f);

			// Spawn status
			let spawnStatus = mSpawningEnabled ? "ON" : "OFF";
			let spawnColor = mSpawningEnabled ? brightGreen : brightBlue;
			mDebugFeature.AddText2D("Spawn:", (float)mRenderView.Width - 115, 54, brightBlue, 1.5f);
			mDebugFeature.AddText2DRight(spawnStatus, 10, 54, spawnColor, 1.5f);

			// Debug draw status
			let debugStatus = mPhysicsDebugDraw ? "ON" : "OFF";
			let debugColor = mPhysicsDebugDraw ? brightGreen : brightBlue;
			mDebugFeature.AddText2D("Debug:", (float)mRenderView.Width - 115, 76, brightBlue, 1.5f);
			mDebugFeature.AddText2DRight(debugStatus, 10, 76, debugColor, 1.5f);
		}

		// Set camera
		mRenderSystem.SetCamera(
			mRenderView.CameraPosition,
			mRenderView.CameraForward,
			.(0, 1, 0),
			mRenderView.FieldOfView,
			mRenderView.AspectRatio,
			mRenderView.NearPlane,
			mRenderView.FarPlane,
			mRenderView.Width,
			mRenderView.Height
		);

		// Build and execute render graph
		if (mRenderSystem.BuildRenderGraph(mRenderView) case .Ok)
		{
			mRenderSystem.Execute(render.Encoder);
		}

		// End frame
		mRenderSystem.EndFrame();

		return true;
	}

	private void PrintProfilerStats()
	{
		let frame = SProfiler.GetCompletedFrame();
		Console.WriteLine("\n=== Profiler Frame {} ===", frame.FrameNumber);
		Console.WriteLine("Total Frame Time: {0:F2}ms", frame.FrameDurationMs);
		Console.WriteLine("Samples: {}", frame.SampleCount);

		if (frame.SampleCount > 0)
		{
			Console.WriteLine("\nBreakdown:");
			for (let sample in frame.Samples)
			{
				let indent = scope String();
				for (int i = 0; i < sample.Depth; i++)
					indent.Append("  ");
				Console.WriteLine("  {0}{1}: {2:F3}ms", indent, sample.Name, sample.DurationMs);
			}
		}
		Console.WriteLine("");
	}

	protected override void OnShutdown()
	{
		// Shutdown profiler
		Profiler.Shutdown();

		Console.WriteLine("\n=== Shutting Down ===");

		// Release mesh handles before render system shutdown
		if (mCubeMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
		if (mPlaneMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);
		if (mSphereMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mSphereMeshHandle, mRenderSystem.FrameNumber);

		// Context shutdown is handled by base Application after OnShutdown

		// Shutdown render system (not owned by context)
		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Shutdown complete");
	}
}

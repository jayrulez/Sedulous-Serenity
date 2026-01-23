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
	private EntityId mMagicCoreEntity;
	private EntityId mMagicWispsEntity;
	private EntityId mTrailEntity;
	private EntityId mFireworkLauncherEntity;
	private EntityId mFireworkBurstEntity;
	private EntityId mSteamEntity;
	private EntityId mFountainEntity;
	private EntityId mSnowEntity;
	private EntityId mFairyDustEntity;
	private EntityId mTrailedSparksEntity;
	private EntityId mHealingEntity;
	private EntityId mSpriteEntity;

	// Trail emitters
	private EntityId mTrailEmitterEntity;
	private EntityId mSwordTrailEntity;
	private float mTrailTime = 0.0f;

	// Camera control
	private OrbitFlyCamera mCamera ~ delete _;

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
	private const float ArenaHalfSize = 25.0f;
	private const float WallHeight = 2.0f;
	private const float WallThickness = 0.5f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
		mCamera = new .();
		mCamera.OrbitalYaw = 0.5f;
		mCamera.OrbitalPitch = 0.4f;
		mCamera.OrbitalDistance = 25.0f;
		mCamera.OrbitalTarget = .(0, 1.0f, 0);
		mCamera.FlyPosition = .(0, 5.0f, 25.0f);
		mCamera.FlyPitch = -0.2f;
		mCamera.Update();
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
		Console.WriteLine("  Smoke (above): Lit + alpha curve + wind + turbulence");
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

		// Sky (solid deep blue)
		mSkyFeature = new SkyFeature();
		mSkyFeature.Mode = .SolidColor;
		mSkyFeature.SolidColor = .(0.1f, 0.1f, 0.15f);
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Ok)
			Console.WriteLine("Registered: SkyFeature (solid deep blue)");

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
			mFloorMaterial.SetColor("BaseColor", .(0.4f, 0.4f, 0.4f, 1.0f));

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
			renderModule.CreatePerspectiveCamera(mCameraEntity, Math.PI_f / 4.0f, (float)mSwapChain.Width / mSwapChain.Height, 0.1f, 200.0f);
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
			transform.Position = .(0.0f, 0.0f, -8.0f);
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
			transform.Position = .(0.0f, 0.8f, -8.0f);
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
					proxy.Lit = true;
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
		Console.WriteLine("  Created smoke particle emitter (lit + turbulence + wind + alpha curve)");

		// Create sparks emitter (burst emission + stretched billboards + gravity)
		mSparksEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSparksEntity);
			transform.Position = .(-8.0f, 0.5f, -4.0f);
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
			transform.Position = .(8.0f, 1.5f, 0.0f);
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
					proxy.ForceModules.VortexCenter = .(8.0f, 1.5f, 0.0f);

					// Attractor keeps them orbiting
					proxy.ForceModules.AttractorStrength = 2.0f;
					proxy.ForceModules.AttractorPosition = .(8.0f, 1.5f, 0.0f);
					proxy.ForceModules.AttractorRadius = 2.0f;

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Sphere(0.8f);
				}
			}
		}
		Console.WriteLine("  Created magic orb emitter (vortex + attractor + size curve)");

		// Magic orb core glow (pulsating center)
		mMagicCoreEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mMagicCoreEntity);
			transform.Position = .(8.0f, 1.5f, 0.0f);
			mMainScene.SetTransform(mMagicCoreEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mMagicCoreEntity, 100);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mMagicCoreEntity))
				{
					proxy.SpawnRate = 15.0f;
					proxy.ParticleLifetime = 1.0f;
					proxy.BlendMode = .Additive;
					proxy.StartColor = .(0.6f, 0.8f, 1.0f, 1.0f);
					proxy.EndColor = .(0.4f, 0.5f, 1.0f, 0.0f);
					proxy.InitialVelocity = .Zero;
					proxy.VelocityRandomness = .(0.05f, 0.05f, 0.05f);
					proxy.GravityMultiplier = 0;
					proxy.Drag = 2.0f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					// Pulse size
					proxy.SizeOverLifetime = .();
					proxy.SizeOverLifetime.AddKey(0.0f, .(0.2f, 0.2f));
					proxy.SizeOverLifetime.AddKey(0.5f, .(0.35f, 0.35f));
					proxy.SizeOverLifetime.AddKey(1.0f, .(0.15f, 0.15f));

					proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.5f);

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Sphere(0.1f);
				}
			}
		}

		// Magic orb energy wisps (per-particle trails orbiting)
		mMagicWispsEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mMagicWispsEntity);
			transform.Position = .(8.0f, 1.5f, 0.0f);
			mMainScene.SetTransform(mMagicWispsEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mMagicWispsEntity, 50);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mMagicWispsEntity))
				{
					proxy.SpawnRate = 5.0f;
					proxy.ParticleLifetime = 4.0f;
					proxy.BlendMode = .Additive;
					proxy.StartColor = .(0.5f, 0.3f, 1.0f, 0.9f);
					proxy.EndColor = .(0.8f, 0.4f, 1.0f, 0.0f);
					proxy.StartSize = .(0.04f, 0.04f);
					proxy.EndSize = .(0.01f, 0.01f);
					proxy.InitialVelocity = .Zero;
					proxy.VelocityRandomness = .(0.2f, 0.2f, 0.2f);
					proxy.GravityMultiplier = 0;
					proxy.Drag = 0.3f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.7f);

					// Vortex + attractor keeps wisps orbiting
					proxy.ForceModules.VortexStrength = 4.0f;
					proxy.ForceModules.VortexAxis = .(0, 1, 0);
					proxy.ForceModules.VortexCenter = .(8.0f, 1.5f, 0.0f);
					proxy.ForceModules.AttractorStrength = 3.0f;
					proxy.ForceModules.AttractorPosition = .(8.0f, 1.5f, 0.0f);
					proxy.ForceModules.AttractorRadius = 1.5f;

					// Per-particle trails
					proxy.Trail.Enabled = true;
					proxy.Trail.MaxPoints = 30;
					proxy.Trail.RecordInterval = 0.03f;
					proxy.Trail.Lifetime = 0.8f;
					proxy.Trail.WidthStart = 0.03f;
					proxy.Trail.WidthEnd = 0.0f;
					proxy.Trail.MinVertexDistance = 0.02f;
					proxy.Trail.UseParticleColor = true;

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Sphere(1.0f);
				}
			}
		}
		Console.WriteLine("  Created magic orb layers (core glow + wisps with trails)");

		// Create trail comet emitter (stretched billboard + ribbon trail)
		mTrailEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mTrailEntity);
			transform.Position = .(-8.0f, 2.0f, 8.0f);
			mMainScene.SetTransform(mTrailEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mTrailEntity, 200);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mTrailEntity))
				{
					proxy.SpawnRate = 8.0f;
					proxy.ParticleLifetime = 3.0f;
					proxy.BlendMode = .Additive;
					proxy.RenderMode = .StretchedBillboard;
					proxy.StretchFactor = 1.5f;
					proxy.StartColor = .(1.0f, 0.6f, 0.2f, 1.0f);
					proxy.EndColor = .(1.0f, 0.2f, 0.0f, 0.0f);
					proxy.StartSize = .(0.06f, 0.06f);
					proxy.EndSize = .(0.02f, 0.02f);
					proxy.InitialVelocity = .(1.5f, 0.5f, 0.0f);
					proxy.VelocityRandomness = .(0.3f, 0.3f, 0.3f);
					proxy.GravityMultiplier = 0.3f;
					proxy.Drag = 0.5f;
					proxy.LifetimeVarianceMin = 0.8f;
					proxy.LifetimeVarianceMax = 1.2f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					// Color fades to transparent
					proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.5f);

					// Enable trails
					proxy.Trail.Enabled = true;
					proxy.Trail.MaxPoints = 20;
					proxy.Trail.RecordInterval = 0.02f;
					proxy.Trail.Lifetime = 1.5f;
					proxy.Trail.WidthStart = 0.04f;
					proxy.Trail.WidthEnd = 0.0f;
					proxy.Trail.MinVertexDistance = 0.01f;
					proxy.Trail.UseParticleColor = true;

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Sphere(0.2f);
				}
			}
		}
		Console.WriteLine("  Created trail comet emitter (stretched billboard + ribbon trails)");

		// Create firework sub-emitter demo (launcher + explosion burst on death)
		mFireworkLauncherEntity = mMainScene.CreateEntity();
		mFireworkBurstEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFireworkLauncherEntity);
			transform.Position = .(12.0f, 0.0f, -10.0f);
			mMainScene.SetTransform(mFireworkLauncherEntity, transform);

			// First create the child "burst" emitter (SubEmitterOnly - only receives from parent)
			let burstHandle = renderModule.CreateCPUParticleEmitter(mFireworkBurstEntity, 1000);
			if (burstHandle.IsValid)
			{
				if (let burstProxy = renderModule.GetParticleEmitterProxy(mFireworkBurstEntity))
				{
					burstProxy.SubEmitterOnly = true;
					burstProxy.SpawnRate = 0;
					burstProxy.ParticleLifetime = 1.5f;
					burstProxy.BlendMode = .Additive;
					burstProxy.RenderMode = .StretchedBillboard;
					burstProxy.StretchFactor = 2.0f;
					burstProxy.StartColor = .(1.0f, 0.8f, 0.3f, 1.0f);
					burstProxy.EndColor = .(1.0f, 0.2f, 0.0f, 0.0f);
					burstProxy.StartSize = .(0.03f, 0.03f);
					burstProxy.EndSize = .(0.005f, 0.005f);
					burstProxy.InitialVelocity = .(0, 0, 0);
					burstProxy.VelocityRandomness = .(3.0f, 3.0f, 3.0f);
					burstProxy.GravityMultiplier = 1.5f;
					burstProxy.Drag = 0.5f;
					burstProxy.LifetimeVarianceMin = 0.5f;
					burstProxy.LifetimeVarianceMax = 1.0f;
					burstProxy.IsEnabled = true;
					burstProxy.IsEmitting = true;

					burstProxy.AlphaOverLifetime = .FadeOut(1.0f, 0.6f);
					burstProxy.SpeedOverLifetime = .Linear(1.0f, 0.1f);

					if (burstProxy.CPUEmitter != null)
						burstProxy.CPUEmitter.Shape = EmissionShape.Sphere(0.05f, true);
				}
			}

			// Now create the parent "launcher" emitter
			let launcherHandle = renderModule.CreateCPUParticleEmitter(mFireworkLauncherEntity, 50);
			if (launcherHandle.IsValid)
			{
				if (let launcherProxy = renderModule.GetParticleEmitterProxy(mFireworkLauncherEntity))
				{
					launcherProxy.SpawnRate = 0;
					launcherProxy.BurstCount = 1;
					launcherProxy.BurstInterval = 2.5f;
					launcherProxy.BurstCycles = 0;
					launcherProxy.ParticleLifetime = 1.0f;
					launcherProxy.BlendMode = .Additive;
					launcherProxy.StartColor = .(1.0f, 1.0f, 0.8f, 1.0f);
					launcherProxy.EndColor = .(1.0f, 0.8f, 0.4f, 0.5f);
					launcherProxy.StartSize = .(0.08f, 0.08f);
					launcherProxy.EndSize = .(0.04f, 0.04f);
					launcherProxy.InitialVelocity = .(0, 6.0f, 0);
					launcherProxy.VelocityRandomness = .(0.5f, 1.0f, 0.5f);
					launcherProxy.GravityMultiplier = 0.5f;
					launcherProxy.IsEnabled = true;
					launcherProxy.IsEmitting = true;

					// Sub-emitter: spawn 20 burst particles when launcher particle dies
					launcherProxy.SubEmitterCount = 1;
					launcherProxy.SubEmitters[0] = .()
					{
						Trigger = .OnDeath,
						ChildEmitter = burstHandle,
						SpawnCount = 20,
						Probability = 1.0f,
						InheritPosition = true,
						InheritVelocity = true,
						InheritColor = false,
						VelocityInheritFactor = 0.3f
					};

					if (launcherProxy.CPUEmitter != null)
						launcherProxy.CPUEmitter.Shape = EmissionShape.Point();
				}
			}
		}
		Console.WriteLine("  Created firework sub-emitter (launcher + burst on death)");

		// Create steam vent (soft particles + turbulence + upward buoyancy)
		mSteamEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSteamEntity);
			transform.Position = .(8.0f, 0.1f, -8.0f);
			mMainScene.SetTransform(mSteamEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mSteamEntity, 500);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mSteamEntity))
				{
					proxy.SpawnRate = 30.0f;
					proxy.ParticleLifetime = 3.0f;
					proxy.BlendMode = .Alpha;
					proxy.StartColor = .(1.0f, 1.0f, 1.0f, 0.4f);
					proxy.EndColor = .(0.9f, 0.9f, 0.95f, 0.0f);
					proxy.StartSize = .(0.2f, 0.2f);
					proxy.EndSize = .(0.8f, 0.8f);
					proxy.InitialVelocity = .(0, 2.5f, 0);
					proxy.VelocityRandomness = .(0.3f, 0.5f, 0.3f);
					proxy.GravityMultiplier = -0.2f;
					proxy.Drag = 0.4f;
					proxy.SoftParticleDistance = 1.0f;
					proxy.SortParticles = true;
					proxy.LifetimeVarianceMin = 0.7f;
					proxy.LifetimeVarianceMax = 1.3f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					proxy.AlphaOverLifetime = .FadeOut(0.8f, 0.5f);

					// Size grows over lifetime
					proxy.SizeOverLifetime = .();
					proxy.SizeOverLifetime.AddKey(0.0f, .(0.2f, 0.2f));
					proxy.SizeOverLifetime.AddKey(0.5f, .(0.5f, 0.5f));
					proxy.SizeOverLifetime.AddKey(1.0f, .(0.9f, 0.9f));

					proxy.ForceModules.TurbulenceStrength = 1.2f;
					proxy.ForceModules.TurbulenceFrequency = 0.8f;
					proxy.ForceModules.TurbulenceSpeed = 0.8f;

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Cone(0.35f, 0.1f);
				}
			}
		}
		Console.WriteLine("  Created steam vent (soft particles + turbulence)");

		// Create water fountain (ballistic arc + high speed)
		mFountainEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFountainEntity);
			transform.Position = .(-12.0f, 0.5f, 0.0f);
			mMainScene.SetTransform(mFountainEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mFountainEntity, 800);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mFountainEntity))
				{
					proxy.SpawnRate = 120.0f;
					proxy.ParticleLifetime = 2.0f;
					proxy.BlendMode = .Alpha;
					proxy.StartColor = .(0.5f, 0.7f, 1.0f, 0.8f);
					proxy.EndColor = .(0.3f, 0.5f, 0.9f, 0.0f);
					proxy.StartSize = .(0.06f, 0.06f);
					proxy.EndSize = .(0.03f, 0.03f);
					proxy.InitialVelocity = .(0, 10.0f, 0);
					proxy.VelocityRandomness = .(1.0f, 1.5f, 1.0f);
					proxy.GravityMultiplier = 2.5f;
					proxy.Drag = 0.1f;
					proxy.SortParticles = false;
					proxy.LifetimeVarianceMin = 0.6f;
					proxy.LifetimeVarianceMax = 1.0f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.6f);

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Cone(0.15f, 0.05f);
				}
			}
		}
		Console.WriteLine("  Created water fountain (ballistic arc + gravity)");

		// Create snow (box emission + wind + gentle fall)
		mSnowEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSnowEntity);
			transform.Position = .(0.0f, 12.0f, 0.0f);
			mMainScene.SetTransform(mSnowEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mSnowEntity, 500);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mSnowEntity))
				{
					proxy.SpawnRate = 40.0f;
					proxy.ParticleLifetime = 8.0f;
					proxy.BlendMode = .Alpha;
					proxy.StartColor = .(1.0f, 1.0f, 1.0f, 0.8f);
					proxy.EndColor = .(0.9f, 0.95f, 1.0f, 0.0f);
					proxy.StartSize = .(0.04f, 0.04f);
					proxy.EndSize = .(0.06f, 0.06f);
					proxy.InitialVelocity = .(0, -0.5f, 0);
					proxy.VelocityRandomness = .(0.2f, 0.1f, 0.2f);
					proxy.GravityMultiplier = 0.15f;
					proxy.Drag = 2.0f;
					proxy.SortParticles = false;
					proxy.LifetimeVarianceMin = 0.7f;
					proxy.LifetimeVarianceMax = 1.3f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					proxy.AlphaOverLifetime = .FadeOut(0.7f, 0.8f);

					// Wind drift
					proxy.ForceModules.WindForce = .(1.2f, 0.0f, 0.4f);
					proxy.ForceModules.WindTurbulence = 0.6f;

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Box(.(10.0f, 0.5f, 10.0f));
				}
			}
		}
		Console.WriteLine("  Created snow (box emission + wind drift)");

		// Create fairy dust / fireflies (turbulence + gentle float + glow)
		mFairyDustEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFairyDustEntity);
			transform.Position = .(12.0f, 1.5f, 5.0f);
			mMainScene.SetTransform(mFairyDustEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mFairyDustEntity, 200);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mFairyDustEntity))
				{
					proxy.SpawnRate = 20.0f;
					proxy.ParticleLifetime = 4.0f;
					proxy.BlendMode = .Additive;
					proxy.StartColor = .(1.0f, 0.85f, 0.4f, 0.9f);
					proxy.EndColor = .(1.0f, 0.6f, 0.2f, 0.0f);
					proxy.InitialVelocity = .(0, 0.2f, 0);
					proxy.VelocityRandomness = .(0.4f, 0.3f, 0.4f);
					proxy.GravityMultiplier = -0.05f;
					proxy.Drag = 0.5f;
					proxy.SortParticles = false;
					proxy.LifetimeVarianceMin = 0.6f;
					proxy.LifetimeVarianceMax = 1.4f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					// Size pulses
					proxy.SizeOverLifetime = .();
					proxy.SizeOverLifetime.AddKey(0.0f, .(0.04f, 0.04f));
					proxy.SizeOverLifetime.AddKey(0.3f, .(0.1f, 0.1f));
					proxy.SizeOverLifetime.AddKey(0.7f, .(0.06f, 0.06f));
					proxy.SizeOverLifetime.AddKey(1.0f, .(0.0f, 0.0f));

					proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.6f);

					// Gentle turbulence for organic motion
					proxy.ForceModules.TurbulenceStrength = 0.4f;
					proxy.ForceModules.TurbulenceFrequency = 0.6f;
					proxy.ForceModules.TurbulenceSpeed = 0.5f;

					// Gentle vortex for swirling
					proxy.ForceModules.VortexStrength = 0.8f;
					proxy.ForceModules.VortexAxis = .(0, 1, 0);
					proxy.ForceModules.VortexCenter = .(12.0f, 1.5f, 5.0f);

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Sphere(2.5f);
				}
			}
		}
		Console.WriteLine("  Created fairy dust (turbulence + vortex + glow)");

		// Create trailed sparks (gravity + per-particle trails)
		mTrailedSparksEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mTrailedSparksEntity);
			transform.Position = .(-5.0f, 3.0f, 10.0f);
			mMainScene.SetTransform(mTrailedSparksEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mTrailedSparksEntity, 100);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mTrailedSparksEntity))
				{
					proxy.SpawnRate = 8.0f;
					proxy.ParticleLifetime = 2.5f;
					proxy.BlendMode = .Additive;
					proxy.StartColor = .(1.0f, 0.8f, 0.2f, 1.0f);
					proxy.EndColor = .(1.0f, 0.3f, 0.0f, 0.0f);
					proxy.StartSize = .(0.06f, 0.06f);
					proxy.EndSize = .(0.02f, 0.02f);
					proxy.InitialVelocity = .(0, 5.0f, 0);
					proxy.VelocityRandomness = .(3.0f, 2.0f, 3.0f);
					proxy.GravityMultiplier = 1.5f;
					proxy.Drag = 0.2f;
					proxy.LifetimeVarianceMin = 0.6f;
					proxy.LifetimeVarianceMax = 1.0f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.5f);

					// Per-particle trails
					proxy.Trail.Enabled = true;
					proxy.Trail.MaxPoints = 15;
					proxy.Trail.RecordInterval = 0.015f;
					proxy.Trail.Lifetime = 0.6f;
					proxy.Trail.WidthStart = 0.04f;
					proxy.Trail.WidthEnd = 0.0f;
					proxy.Trail.MinVertexDistance = 0.05f;
					proxy.Trail.UseParticleColor = true;

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Sphere(0.3f, true);
				}
			}
		}
		Console.WriteLine("  Created trailed sparks (gravity + per-particle trails)");

		// Create healing magic (green sparkles + attractor spiral)
		mHealingEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mHealingEntity);
			transform.Position = .(5.0f, 0.5f, 8.0f);
			mMainScene.SetTransform(mHealingEntity, transform);

			let handle = renderModule.CreateCPUParticleEmitter(mHealingEntity, 300);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mHealingEntity))
				{
					proxy.SpawnRate = 35.0f;
					proxy.ParticleLifetime = 2.5f;
					proxy.BlendMode = .Additive;
					proxy.StartColor = .(0.2f, 1.0f, 0.4f, 0.9f);
					proxy.EndColor = .(0.1f, 0.8f, 0.3f, 0.0f);
					proxy.InitialVelocity = .(0, 0.5f, 0);
					proxy.VelocityRandomness = .(0.5f, 0.3f, 0.5f);
					proxy.GravityMultiplier = -0.1f;
					proxy.Drag = 0.3f;
					proxy.SortParticles = false;
					proxy.LifetimeVarianceMin = 0.7f;
					proxy.LifetimeVarianceMax = 1.2f;
					proxy.IsEnabled = true;
					proxy.IsEmitting = true;

					// Size shrinks to nothing
					proxy.SizeOverLifetime = .();
					proxy.SizeOverLifetime.AddKey(0.0f, .(0.02f, 0.02f));
					proxy.SizeOverLifetime.AddKey(0.2f, .(0.08f, 0.08f));
					proxy.SizeOverLifetime.AddKey(1.0f, .(0.0f, 0.0f));

					proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.6f);

					// Attractor pulls particles inward (spiral upward)
					proxy.ForceModules.AttractorStrength = 2.5f;
					proxy.ForceModules.AttractorPosition = .(5.0f, 1.5f, 8.0f);
					proxy.ForceModules.AttractorRadius = 3.0f;

					// Vortex for spiral motion
					proxy.ForceModules.VortexStrength = 2.0f;
					proxy.ForceModules.VortexAxis = .(0, 1, 0);
					proxy.ForceModules.VortexCenter = .(5.0f, 0.5f, 8.0f);

					if (proxy.CPUEmitter != null)
						proxy.CPUEmitter.Shape = EmissionShape.Sphere(2.0f);
				}
			}
		}
		Console.WriteLine("  Created healing magic (green sparkles + attractor spiral)");

		// Create test sprite (floating marker)
		mSpriteEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSpriteEntity);
			transform.Position = .(0.0f, 2.0f, -5.0f);
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

		// Create trail emitter (orbiting ring)
		mTrailEmitterEntity = mMainScene.CreateEntity();
		{
			let handle = renderModule.CreateTrailEmitter(mTrailEmitterEntity, 64);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetTrailEmitterProxy(mTrailEmitterEntity))
				{
					proxy.BlendMode = .Additive;
					proxy.Lifetime = 2.0f;
					proxy.WidthStart = 0.08f;
					proxy.WidthEnd = 0.0f;
					proxy.MinVertexDistance = 0.02f;
					proxy.Color = .(0.3f, 0.8f, 1.0f, 1.0f);
					proxy.SoftParticleDistance = 0.5f;
					proxy.IsEnabled = true;
				}
			}
		}
		Console.WriteLine("  Created trail emitter (orbiting ring)");

		// Create sword swing trail (pendulum motion)
		mSwordTrailEntity = mMainScene.CreateEntity();
		{
			let handle = renderModule.CreateTrailEmitter(mSwordTrailEntity, 40);
			if (handle.IsValid)
			{
				if (let proxy = renderModule.GetTrailEmitterProxy(mSwordTrailEntity))
				{
					proxy.BlendMode = .Alpha;
					proxy.Lifetime = 0.4f;
					proxy.WidthStart = 1.2f;
					proxy.WidthEnd = 0.3f;
					proxy.MinVertexDistance = 0.02f;
					proxy.Color = .(0.7f, 0.4f, 1.0f, 0.85f);
					proxy.SoftParticleDistance = 0.5f;
					proxy.IsEnabled = true;
				}
			}
		}
		Console.WriteLine("  Created sword swing trail");

		// Set world ambient
		if (let world = renderModule.World)
		{
			world.AmbientColor = .(0.05f, 0.05f, 0.08f);
			world.AmbientIntensity = 1.0f;
		}

		Console.WriteLine("\nEntity count: {}", mMainScene.EntityCount);

		Console.WriteLine("\nControls:");
		Console.WriteLine("  Tab    - Toggle orbit/fly camera");
		Console.WriteLine("  Orbit: W/S pitch, A/D yaw, Q/E zoom");
		Console.WriteLine("  Fly:   W/S forward/back, A/D strafe, Q/E up/down");
		Console.WriteLine("         Arrow keys: look, Shift: fast");
		Console.WriteLine("  Space  - Toggle physics spawning");
		Console.WriteLine("  F      - Toggle physics debug draw");
		Console.WriteLine("  P      - Print profiler stats");
		Console.WriteLine("  Escape - Quit");
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
		let mouse = mShell.InputManager.Mouse;

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

		// Camera input
		mCamera.HandleInput(keyboard, mouse, mDeltaTime);
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

		// Update trail emitters
		{
			mTrailTime += mDeltaTime;
			let renderModule = mMainScene?.GetModule<RenderSceneModule>();
			if (renderModule != null)
			{
				// Orbiting ring trail
				if (let proxy = renderModule.GetTrailEmitterProxy(mTrailEmitterEntity))
				{
					if (proxy.Emitter != null)
					{
						let radius = 2.0f;
						let speed = 1.5f;
						let x = Math.Cos(mTrailTime * speed) * radius;
						let z = Math.Sin(mTrailTime * speed) * radius;
						let y = 2.5f + Math.Sin(mTrailTime * speed * 2.0f) * 0.5f;

						let pos = Vector3((float)x, (float)y, (float)z);
						proxy.Emitter.AddPointFiltered(pos, proxy.WidthStart, Color(255, 255, 255, 255), proxy.MinVertexDistance);
					}
				}

				// Sword swing trail (pendulum motion - wide arc)
				if (let proxy = renderModule.GetTrailEmitterProxy(mSwordTrailEntity))
				{
					if (proxy.Emitter != null)
					{
						let swingSpeed = 4.0f;
						let swingAngle = Math.Sin(mTrailTime * swingSpeed) * 2.0f;
						let swingX = Math.Sin(swingAngle) * 3.5f;
						let swingY = 2.5f + Math.Cos(swingAngle) * 2.0f;
						let baseX = -12.0f;
						let baseZ = 8.0f;

						let pos = Vector3(baseX + (float)swingX, (float)swingY, baseZ);
						proxy.Emitter.AddPointFiltered(pos, proxy.WidthStart, Color(180, 100, 255, 220), proxy.MinVertexDistance);
					}
				}
			}
		}

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
		// Update camera entity transform
		var transform = mMainScene.GetTransform(mCameraEntity);
		transform.Position = mCamera.Position;
		let yaw = Math.Atan2(mCamera.Forward.X, mCamera.Forward.Z);
		let pitch = Math.Asin(-mCamera.Forward.Y);
		transform.Rotation = Quaternion.CreateFromYawPitchRoll(yaw, pitch, 0);
		mMainScene.SetTransform(mCameraEntity, transform);

		// Also update render view for rendering
		mRenderView.CameraPosition = mCamera.Position;
		mRenderView.CameraForward = mCamera.Forward;
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
			let labelColor = Color(255, 255, 200, 255);

			// Compute camera-facing billboard vectors for world-space labels
			let camFwd = mCamera.Forward;
			var camRight = Vector3.Cross(camFwd, .(0, 1, 0));
			let rightLen = camRight.Length();
			if (rightLen < 0.001f)
				camRight = .(1, 0, 0);
			else
				camRight = camRight / rightLen;
			let camUp = Vector3.Normalize(Vector3.Cross(camRight, camFwd));

			// Label particle emitters (scale 1.5 for readability)
			mDebugFeature.AddText("Fire + Smoke", .(0.0f, 3.5f, -8.0f), labelColor, 1.5f, camRight, camUp, .Overlay);
			mDebugFeature.AddText("Sparks", .(-8.0f, 3.0f, -4.0f), labelColor, 1.5f, camRight, camUp, .Overlay);
			mDebugFeature.AddText("Magic Orb", .(8.0f, 4.0f, 0.0f), labelColor, 1.5f, camRight, camUp, .Overlay);
			mDebugFeature.AddText("Trail Comet", .(-8.0f, 4.5f, 8.0f), labelColor, 1.5f, camRight, camUp, .Overlay);
			mDebugFeature.AddText("Firework", .(12.0f, 4.0f, -10.0f), labelColor, 1.5f, camRight, camUp, .Overlay);
			mDebugFeature.AddText("Steam", .(8.0f, 3.5f, -8.0f), labelColor, 1.5f, camRight, camUp, .Overlay);
			mDebugFeature.AddText("Fountain", .(-12.0f, 4.0f, 0.0f), labelColor, 1.5f, camRight, camUp, .Overlay);
			mDebugFeature.AddText("Fairy Dust", .(12.0f, 4.0f, 5.0f), labelColor, 1.5f, camRight, camUp, .Overlay);
			mDebugFeature.AddText("Trailed Sparks", .(-5.0f, 5.5f, 10.0f), labelColor, 1.5f, camRight, camUp, .Overlay);
			mDebugFeature.AddText("Healing", .(5.0f, 3.5f, 8.0f), labelColor, 1.5f, camRight, camUp, .Overlay);
			mDebugFeature.AddText("Sword Trail", .(-12.0f, 4.5f, 8.0f), labelColor, 1.5f, camRight, camUp, .Overlay);

			let white = Color(255, 255, 255, 255);
			let brightYellow = Color(255, 255, 100, 255);
			let brightOrange = Color(255, 180, 100, 255);

			// ===== TOP LEFT: Instructions =====
			mDebugFeature.AddRect2D(5, 5, 400, 120, bgColor);
			mDebugFeature.AddText2D("FRAMEWORK SANDBOX", 15, 12, brightYellow, 1.5f);

			if (mCamera.CurrentMode == .Orbital)
				mDebugFeature.AddText2D("ORBITAL: WASD rotate, Q/E zoom, RMB drag", 15, 35, white, 1.0f);
			else
				mDebugFeature.AddText2D("FLY: WASD move, Q/E up/down, RMB look", 15, 35, white, 1.0f);

			mDebugFeature.AddText2D("Tab: Toggle camera    `: Back to orbital", 15, 52, white, 1.0f);
			mDebugFeature.AddText2D("Space: Spawn objects  F: Debug draw", 15, 69, white, 1.0f);
			mDebugFeature.AddText2D("P: Profiler           ESC: Exit", 15, 86, white, 1.0f);

			// ===== TOP RIGHT: Stats =====
			float panelX = (float)mRenderView.Width - 220;
			mDebugFeature.AddRect2D(panelX, 5, 215, 135, bgColor);

			// FPS
			let fpsText = scope String();
			((int32)Math.Round(mSmoothedFps)).ToString(fpsText);
			mDebugFeature.AddText2D("FPS:", panelX + 10, 12, brightBlue, 1.5f);
			mDebugFeature.AddText2DRight(fpsText, 10, 12, brightCyan, 1.5f);

			// Object count
			let countText = scope String();
			mSpawnCount.ToString(countText);
			mDebugFeature.AddText2D("Objects:", panelX + 10, 35, brightBlue, 1.5f);
			mDebugFeature.AddText2DRight(countText, 10, 35, brightCyan, 1.5f);

			// Spawn status
			let spawnStatus = mSpawningEnabled ? "ON" : "OFF";
			let spawnColor = mSpawningEnabled ? brightGreen : brightBlue;
			mDebugFeature.AddText2D("Spawn:", panelX + 10, 58, brightBlue, 1.5f);
			mDebugFeature.AddText2DRight(spawnStatus, 10, 58, spawnColor, 1.5f);

			// Debug draw status
			let debugStatus = mPhysicsDebugDraw ? "ON" : "OFF";
			let debugColor = mPhysicsDebugDraw ? brightGreen : brightBlue;
			mDebugFeature.AddText2D("Debug:", panelX + 10, 81, brightBlue, 1.5f);
			mDebugFeature.AddText2DRight(debugStatus, 10, 81, debugColor, 1.5f);

			// Camera mode
			let camMode = (mCamera.CurrentMode == .Orbital) ? "ORBITAL" : "FLYTHROUGH";
			let camColor = (mCamera.CurrentMode == .Orbital) ? brightGreen : brightOrange;
			mDebugFeature.AddText2D("Camera:", panelX + 10, 104, brightBlue, 1.2f);
			mDebugFeature.AddText2DRight(camMode, 10, 104, camColor, 1.2f);
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

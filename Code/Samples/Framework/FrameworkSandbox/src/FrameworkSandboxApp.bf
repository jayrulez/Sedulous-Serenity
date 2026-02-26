using System;
using System.Collections;
using Sedulous.Foundation.Mathematics;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Animation;
using Sedulous.Framework.Physics;
using Sedulous.Framework.Audio;
using Sedulous.Framework.Input;
using Sedulous.Framework.UI;
using Sedulous.Fonts;
using Sedulous.GUI;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Resources;
using Sedulous.Materials;
using Sedulous.Physics;
using Sedulous.Physics.Jolt;
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Framework.Physics;
using Sedulous.Profiler;
using Sedulous.Drawing.Fonts;
using Sedulous.Imaging;
using Sedulous.Textures.Resources;

namespace FrameworkSandbox;

/// Demonstrates the Sedulous Framework with Context, Subsystems, Scenes, and Entities.
class FrameworkSandboxApp : Application
{
	// Framework core (mContext is now owned by base Application)
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private UISubsystem mUISubsystem;
	private Scene mMainScene;

	private FontService mFontService;

	// Render system (needed by RenderSubsystem)
	private RenderSystem mRenderSystem ~ delete _;
	private RenderView mRenderView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private ForwardTransparentFeature mTransparentFeature;
	private ParticleFeature mParticleFeature;
	private SpriteFeature mSpriteFeature;
	private DecalFeature mDecalFeature;
	private SkyFeature mSkyFeature;
	private OverlayRenderFeature mOverlayFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Mesh resources
	private StaticMeshResource mCubeResource /*~ delete _*/;
	private StaticMeshResource mPlaneResource /*~ delete _*/;
	private StaticMeshResource mSphereResource /*~ delete _*/;
	private MaterialInstance mCubeMaterial ~ _?.ReleaseRef();
	private MaterialInstance mFloorMaterial ~ _?.ReleaseRef();
	private MaterialInstance mSphereMaterial ~ _?.ReleaseRef();

	// Decal resources
	private TextureResource mDecalTextureResource ~ _.ReleaseRef();

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
	private EntityId mDecalEntity1;
	private EntityId mDecalEntity2;
	private EntityId mWorldUIPanelEntity;

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

	// Sun light control (spherical coordinates, matching RendererIntegrated)
	private float mSunYaw = 0.5f;
	private float mSunPitch = -1.0f;

	// Render scene module reference (for UI callbacks)
	private RenderSceneModule mRenderModule;

	// Floor color tracking (for per-channel slider updates)
	private float mFloorR = 0.4f;
	private float mFloorG = 0.4f;
	private float mFloorB = 0.4f;

	// Deferred proxy-only setup (sub-emitter linkage requires proxy handles)
	private bool mNeedsSubEmitterSetup = true;

	// Arena size
	private const float ArenaHalfSize = 25.0f;
	private const float WallHeight = 2.0f;
	private const float WallThickness = 0.5f;

	private Canvas mUIRoot;
	private StackPanel mWorldSpaceUIRoot;

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

		InitializeFont();

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

		// Create UI overlay
		CreateUI();

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
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), null, .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
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

	private bool InitializeFont()
	{
		Console.WriteLine("Initializing fonts...");

		mFontService = new FontService();

		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = 16;

		if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
		{
			Console.WriteLine($"Failed to load font: {fontPath}");
			return false;
		}

		Console.WriteLine("Font loaded successfully");
		return true;
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

		// Decals
		mDecalFeature = new DecalFeature();
		if (mRenderSystem.RegisterFeature(mDecalFeature) case .Ok)
			Console.WriteLine("Registered: DecalFeature");

		// Sky (gradient environment map)
		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Ok)
		{
			// Create gradient sky matching RendererIntegrated
			let topColor = Color(70, 130, 200, 255);
			let horizonColor = Color(180, 210, 240, 255);
			if (mSkyFeature.CreateGradientSky(topColor, horizonColor, 32) case .Ok)
				Console.WriteLine("Registered: SkyFeature (gradient environment map)");
			else
				Console.WriteLine("Registered: SkyFeature (fallback)");
		}

		// Debug render (for physics debug draw)
		mOverlayFeature = new OverlayRenderFeature();
		if (mRenderSystem.RegisterFeature(mOverlayFeature) case .Ok)
			Console.WriteLine("Registered: OverlayRenderFeature");

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

		// Input subsystem (needed for UI input routing)
		let inputSubsystem = new InputSubsystem();
		inputSubsystem.SetInputManager(mShell.InputManager);
		context.RegisterSubsystem(inputSubsystem);
		Console.WriteLine("  - InputSubsystem");

		// UI subsystem
		mUISubsystem = new UISubsystem(mFontService);
		context.RegisterSubsystem(mUISubsystem);
		if (mUISubsystem.InitializeRendering(mDevice, .BGRA8UnormSrgb, 2, mShell, mWindow, mRenderSystem) not case .Ok)
		{
			Console.WriteLine("  - UISubsystem (render init failed)");
		}
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
		Console.WriteLine("  - UISceneModule (from UISubsystem)");
	}

	private void CreateSceneObjects()
	{
		Console.WriteLine("\nCreating scene objects...");

		// Get render module for creating render components
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		mRenderModule = renderModule;
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
			mFloorMaterial.SetFloat("Metallic", 0.0f);
			mFloorMaterial.SetFloat("Roughness", 0.95f);
			mFloorMaterial.SetFloat("AO", 1.0f);

			mSphereMaterial = new MaterialInstance(baseMaterial);
			mSphereMaterial.SetColor("BaseColor", .(0.9f, 0.3f, 0.2f, 1.0f));  // Red sphere
		}

		// Create floor entity
		mFloorEntity = mMainScene.CreateEntity();
		{
			// Set mesh component - framework handles proxy creation and GPU upload
			mMainScene.SetComponent<MeshRendererComponent>(mFloorEntity, .Default);
			var comp = mMainScene.GetComponent<MeshRendererComponent>(mFloorEntity);
			comp.Mesh = ResourceHandle<StaticMeshResource>(mPlaneResource);
			comp.MaterialInstances[0] = mFloorMaterial ?? defaultMaterial;
			comp.MaterialInstances[0]?.AddRef();
			comp.MaterialRefs.Count = 1;

			// Infinite plane at Y=0 facing up
			if (physicsModule != null)
				physicsModule.CreatePlaneBody(mFloorEntity, .(0, 1, 0), 0.0f);
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

			// Set mesh component - framework handles proxy creation and GPU upload
			mMainScene.SetComponent<MeshRendererComponent>(mCubeEntity, .Default);
			var comp = mMainScene.GetComponent<MeshRendererComponent>(mCubeEntity);
			comp.Mesh = ResourceHandle<StaticMeshResource>(mCubeResource);
			comp.MaterialInstances[0] = mCubeMaterial ?? defaultMaterial;
			comp.MaterialInstances[0]?.AddRef();
			comp.MaterialRefs.Count = 1;

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

				// Set mesh component - framework handles proxy creation and GPU upload
				mMainScene.SetComponent<MeshRendererComponent>(entity, .Default);
				var comp = mMainScene.GetComponent<MeshRendererComponent>(entity);
				comp.Mesh = ResourceHandle<StaticMeshResource>(mSphereResource);
				comp.MaterialInstances[0] = mSphereMaterial ?? defaultMaterial;
				comp.MaterialInstances[0]?.AddRef();
				comp.MaterialRefs.Count = 1;

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
			// Direction computed from mSunYaw/mSunPitch (same as RendererIntegrated)
			let handle = renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.98f, 0.95f), 2.0f);
			if (handle.IsValid)
				UpdateSunLight();

			// Enable shadow casting on the sun (must set on component, not just proxy,
			// because PostUpdate syncs component → proxy every frame)
			if (let comp = mMainScene.GetComponent<LightComponent>(mSunEntity))
				comp.CastsShadows = true;
		}
		Console.WriteLine("  Created sun light entity");

		// Enable shadow rendering
		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;

		// Create point lights (fixed seed for consistent placement, matching RendererIntegrated)
		{
			Random rng = scope .(12345);
			for (int i = 0; i < 8; i++)
			{
				float px = ((float)rng.NextDouble() - 0.5f) * 24.0f;
				float py = (float)rng.NextDouble() * 2.0f + 3.0f;
				float pz = ((float)rng.NextDouble() - 0.5f) * 24.0f;

				let lightEntity = mMainScene.CreateEntity();
				var transform = mMainScene.GetTransform(lightEntity);
				transform.Position = .(px, py, pz);
				mMainScene.SetTransform(lightEntity, transform);

				Vector3 color = .(
					(float)rng.NextDouble() * 0.5f + 0.5f,
					(float)rng.NextDouble() * 0.5f + 0.5f,
					(float)rng.NextDouble() * 0.5f + 0.5f
				);

				renderModule.CreatePointLight(lightEntity, color, 5.0f, 8.0f);
			}
		}
		Console.WriteLine("  Created 8 point lights");

		// Create fire particle emitter (with color/size curves)
		mFireEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFireEntity);
			transform.Position = .(0.0f, 0.0f, -8.0f);
			mMainScene.SetTransform(mFireEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 2000;
			comp.SpawnRate = 200.0f;
			comp.ParticleLifetime = 1.2f;
			comp.BlendMode = .Additive;
			comp.InitialVelocity = .(0.0f, 2.0f, 0.0f);
			comp.VelocityRandomness = .(0.5f, 0.3f, 0.5f);
			comp.GravityMultiplier = -0.3f;
			comp.Drag = 1.0f;
			comp.SortParticles = false;
			comp.LifetimeVarianceMin = 0.7f;
			comp.LifetimeVarianceMax = 1.3f;
			comp.Shape = EmissionShape.Cone(0.3f, 0.1f);
			// Color curve: bright yellow -> orange -> dark red -> transparent
			comp.ColorOverLifetime = .();
			comp.ColorOverLifetime.AddKey(0.0f, .(1.0f, 0.9f, 0.3f, 1.0f));
			comp.ColorOverLifetime.AddKey(0.2f, .(1.0f, 0.6f, 0.1f, 0.9f));
			comp.ColorOverLifetime.AddKey(0.6f, .(0.8f, 0.2f, 0.0f, 0.5f));
			comp.ColorOverLifetime.AddKey(1.0f, .(0.3f, 0.0f, 0.0f, 0.0f));
			// Size curve: grows then shrinks
			comp.SizeOverLifetime = .();
			comp.SizeOverLifetime.AddKey(0.0f, .(0.05f, 0.05f));
			comp.SizeOverLifetime.AddKey(0.15f, .(0.18f, 0.18f));
			comp.SizeOverLifetime.AddKey(1.0f, .(0.02f, 0.02f));
			// Slight turbulence for flickering
			comp.ForceModules.TurbulenceStrength = 1.5f;
			comp.ForceModules.TurbulenceFrequency = 3.0f;
			comp.ForceModules.TurbulenceSpeed = 2.0f;
			mMainScene.SetComponent<ParticleEmitterComponent>(mFireEntity, comp);
		}
		Console.WriteLine("  Created fire particle emitter (curves + turbulence)");

		// Create smoke particle emitter (turbulence + alpha fade curve)
		mSmokeEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSmokeEntity);
			transform.Position = .(0.0f, 0.8f, -8.0f);
			mMainScene.SetTransform(mSmokeEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.SpawnRate = 30.0f;
			comp.ParticleLifetime = 4.0f;
			comp.BlendMode = .Alpha;
			comp.StartColor = .(0.4f, 0.4f, 0.4f, 0.5f);
			comp.EndColor = .(0.3f, 0.3f, 0.3f, 0.0f);
			comp.InitialVelocity = .(0.0f, 0.8f, 0.0f);
			comp.VelocityRandomness = .(0.3f, 0.1f, 0.3f);
			comp.GravityMultiplier = -0.1f;
			comp.Drag = 0.6f;
			comp.SortParticles = true;
			comp.Lit = true;
			comp.SoftParticleDistance = 0.5f;
			comp.LifetimeVarianceMin = 0.8f;
			comp.LifetimeVarianceMax = 1.5f;
			comp.Shape = EmissionShape.Cone(0.4f, 0.1f);
			comp.SizeOverLifetime = .Linear(.(0.08f, 0.08f), .(0.5f, 0.5f));
			comp.AlphaOverLifetime = .FadeOut(1.0f, 0.4f);
			comp.ForceModules.TurbulenceStrength = 0.6f;
			comp.ForceModules.TurbulenceFrequency = 1.0f;
			comp.ForceModules.TurbulenceSpeed = 0.4f;
			comp.ForceModules.WindForce = .(0.3f, 0, 0.1f);
			comp.ForceModules.WindTurbulence = 0.15f;
			mMainScene.SetComponent<ParticleEmitterComponent>(mSmokeEntity, comp);
		}
		Console.WriteLine("  Created smoke particle emitter (lit + turbulence + wind + alpha curve)");

		// Create sparks emitter (burst emission + stretched billboards + gravity)
		mSparksEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSparksEntity);
			transform.Position = .(-8.0f, 0.5f, -4.0f);
			mMainScene.SetTransform(mSparksEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 500;
			comp.SpawnRate = 0;
			comp.BurstCount = 30;
			comp.BurstInterval = 2.0f;
			comp.BurstCycles = 0;
			comp.ParticleLifetime = 1.5f;
			comp.BlendMode = .Additive;
			comp.RenderMode = .StretchedBillboard;
			comp.StretchFactor = 2.5f;
			comp.StartColor = .(1.0f, 0.8f, 0.3f, 1.0f);
			comp.EndColor = .(1.0f, 0.2f, 0.0f, 0.0f);
			comp.StartSize = .(0.02f, 0.02f);
			comp.EndSize = .(0.005f, 0.005f);
			comp.InitialVelocity = .(0.0f, 4.0f, 0.0f);
			comp.VelocityRandomness = .(2.5f, 2.0f, 2.5f);
			comp.GravityMultiplier = 2.0f;
			comp.Drag = 0.3f;
			comp.LifetimeVarianceMin = 0.4f;
			comp.LifetimeVarianceMax = 1.0f;
			comp.Shape = EmissionShape.Sphere(0.05f, true);
			comp.SpeedOverLifetime = .Linear(1.0f, 0.2f);
			mMainScene.SetComponent<ParticleEmitterComponent>(mSparksEntity, comp);
		}
		Console.WriteLine("  Created sparks emitter (burst + stretched billboard + speed curve)");

		// Create magic orb emitter (vortex + attractor + additive)
		mMagicEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mMagicEntity);
			transform.Position = .(8.0f, 1.5f, 0.0f);
			mMainScene.SetTransform(mMagicEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.SpawnRate = 40.0f;
			comp.ParticleLifetime = 3.0f;
			comp.BlendMode = .Additive;
			comp.StartColor = .(0.3f, 0.5f, 1.0f, 0.8f);
			comp.EndColor = .(0.6f, 0.2f, 1.0f, 0.0f);
			comp.InitialVelocity = .Zero;
			comp.VelocityRandomness = .(0.3f, 0.3f, 0.3f);
			comp.GravityMultiplier = -0.15f;
			comp.Drag = 0.5f;
			comp.LifetimeVarianceMin = 0.8f;
			comp.LifetimeVarianceMax = 1.2f;
			comp.Shape = EmissionShape.Sphere(0.8f);
			comp.SizeOverLifetime = .();
			comp.SizeOverLifetime.AddKey(0.0f, .(0.01f, 0.01f));
			comp.SizeOverLifetime.AddKey(0.25f, .(0.07f, 0.07f));
			comp.SizeOverLifetime.AddKey(0.5f, .(0.03f, 0.03f));
			comp.SizeOverLifetime.AddKey(0.75f, .(0.05f, 0.05f));
			comp.SizeOverLifetime.AddKey(1.0f, .(0.0f, 0.0f));
			comp.AlphaOverLifetime = .FadeOut(1.0f, 0.7f);
			comp.ForceModules.VortexStrength = 3.0f;
			comp.ForceModules.VortexAxis = .(0, 1, 0);
			comp.ForceModules.VortexCenter = .(8.0f, 1.5f, 0.0f);
			comp.ForceModules.AttractorStrength = 2.0f;
			comp.ForceModules.AttractorPosition = .(8.0f, 1.5f, 0.0f);
			comp.ForceModules.AttractorRadius = 2.0f;
			mMainScene.SetComponent<ParticleEmitterComponent>(mMagicEntity, comp);
		}
		Console.WriteLine("  Created magic orb emitter (vortex + attractor + size curve)");

		// Magic orb core glow (pulsating center)
		mMagicCoreEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mMagicCoreEntity);
			transform.Position = .(8.0f, 1.5f, 0.0f);
			mMainScene.SetTransform(mMagicCoreEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 100;
			comp.SpawnRate = 15.0f;
			comp.ParticleLifetime = 1.0f;
			comp.BlendMode = .Additive;
			comp.StartColor = .(0.6f, 0.8f, 1.0f, 1.0f);
			comp.EndColor = .(0.4f, 0.5f, 1.0f, 0.0f);
			comp.InitialVelocity = .Zero;
			comp.VelocityRandomness = .(0.05f, 0.05f, 0.05f);
			comp.GravityMultiplier = 0;
			comp.Drag = 2.0f;
			comp.Shape = EmissionShape.Sphere(0.1f);
			comp.SizeOverLifetime = .();
			comp.SizeOverLifetime.AddKey(0.0f, .(0.2f, 0.2f));
			comp.SizeOverLifetime.AddKey(0.5f, .(0.35f, 0.35f));
			comp.SizeOverLifetime.AddKey(1.0f, .(0.15f, 0.15f));
			comp.AlphaOverLifetime = .FadeOut(1.0f, 0.5f);
			mMainScene.SetComponent<ParticleEmitterComponent>(mMagicCoreEntity, comp);
		}

		// Magic orb energy wisps (per-particle trails orbiting)
		mMagicWispsEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mMagicWispsEntity);
			transform.Position = .(8.0f, 1.5f, 0.0f);
			mMainScene.SetTransform(mMagicWispsEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 50;
			comp.SpawnRate = 5.0f;
			comp.ParticleLifetime = 4.0f;
			comp.BlendMode = .Additive;
			comp.StartColor = .(0.5f, 0.3f, 1.0f, 0.9f);
			comp.EndColor = .(0.8f, 0.4f, 1.0f, 0.0f);
			comp.StartSize = .(0.04f, 0.04f);
			comp.EndSize = .(0.01f, 0.01f);
			comp.InitialVelocity = .Zero;
			comp.VelocityRandomness = .(0.2f, 0.2f, 0.2f);
			comp.GravityMultiplier = 0;
			comp.Drag = 0.3f;
			comp.Shape = EmissionShape.Sphere(1.0f);
			comp.AlphaOverLifetime = .FadeOut(1.0f, 0.7f);
			comp.ForceModules.VortexStrength = 4.0f;
			comp.ForceModules.VortexAxis = .(0, 1, 0);
			comp.ForceModules.VortexCenter = .(8.0f, 1.5f, 0.0f);
			comp.ForceModules.AttractorStrength = 3.0f;
			comp.ForceModules.AttractorPosition = .(8.0f, 1.5f, 0.0f);
			comp.ForceModules.AttractorRadius = 1.5f;
			comp.Trail.Enabled = true;
			comp.Trail.MaxPoints = 30;
			comp.Trail.RecordInterval = 0.03f;
			comp.Trail.Lifetime = 0.8f;
			comp.Trail.WidthStart = 0.03f;
			comp.Trail.WidthEnd = 0.0f;
			comp.Trail.MinVertexDistance = 0.02f;
			comp.Trail.UseParticleColor = true;
			mMainScene.SetComponent<ParticleEmitterComponent>(mMagicWispsEntity, comp);
		}
		Console.WriteLine("  Created magic orb layers (core glow + wisps with trails)");

		// Create trail comet emitter (stretched billboard + ribbon trail)
		mTrailEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mTrailEntity);
			transform.Position = .(-8.0f, 2.0f, 8.0f);
			mMainScene.SetTransform(mTrailEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 200;
			comp.SpawnRate = 8.0f;
			comp.ParticleLifetime = 3.0f;
			comp.BlendMode = .Additive;
			comp.RenderMode = .StretchedBillboard;
			comp.StretchFactor = 1.5f;
			comp.StartColor = .(1.0f, 0.6f, 0.2f, 1.0f);
			comp.EndColor = .(1.0f, 0.2f, 0.0f, 0.0f);
			comp.StartSize = .(0.06f, 0.06f);
			comp.EndSize = .(0.02f, 0.02f);
			comp.InitialVelocity = .(1.5f, 0.5f, 0.0f);
			comp.VelocityRandomness = .(0.3f, 0.3f, 0.3f);
			comp.GravityMultiplier = 0.3f;
			comp.Drag = 0.5f;
			comp.LifetimeVarianceMin = 0.8f;
			comp.LifetimeVarianceMax = 1.2f;
			comp.Shape = EmissionShape.Sphere(0.2f);
			comp.AlphaOverLifetime = .FadeOut(1.0f, 0.5f);
			comp.Trail.Enabled = true;
			comp.Trail.MaxPoints = 20;
			comp.Trail.RecordInterval = 0.02f;
			comp.Trail.Lifetime = 1.5f;
			comp.Trail.WidthStart = 0.04f;
			comp.Trail.WidthEnd = 0.0f;
			comp.Trail.MinVertexDistance = 0.01f;
			comp.Trail.UseParticleColor = true;
			mMainScene.SetComponent<ParticleEmitterComponent>(mTrailEntity, comp);
		}
		Console.WriteLine("  Created trail comet emitter (stretched billboard + ribbon trails)");

		// Create firework sub-emitter demo (launcher + explosion burst on death)
		mFireworkLauncherEntity = mMainScene.CreateEntity();
		mFireworkBurstEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFireworkLauncherEntity);
			transform.Position = .(12.0f, 0.0f, -10.0f);
			mMainScene.SetTransform(mFireworkLauncherEntity, transform);

			// Child "burst" emitter (SubEmitterOnly - only receives from parent)
			var burstComp = ParticleEmitterComponent.Default;
			burstComp.SubEmitterOnly = true;
			burstComp.SpawnRate = 0;
			burstComp.ParticleLifetime = 1.5f;
			burstComp.BlendMode = .Additive;
			burstComp.RenderMode = .StretchedBillboard;
			burstComp.StretchFactor = 2.0f;
			burstComp.StartColor = .(1.0f, 0.8f, 0.3f, 1.0f);
			burstComp.EndColor = .(1.0f, 0.2f, 0.0f, 0.0f);
			burstComp.StartSize = .(0.03f, 0.03f);
			burstComp.EndSize = .(0.005f, 0.005f);
			burstComp.InitialVelocity = .(0, 0, 0);
			burstComp.VelocityRandomness = .(3.0f, 3.0f, 3.0f);
			burstComp.GravityMultiplier = 1.5f;
			burstComp.Drag = 0.5f;
			burstComp.LifetimeVarianceMin = 0.5f;
			burstComp.LifetimeVarianceMax = 1.0f;
			burstComp.Shape = EmissionShape.Sphere(0.05f, true);
			burstComp.AlphaOverLifetime = .FadeOut(1.0f, 0.6f);
			burstComp.SpeedOverLifetime = .Linear(1.0f, 0.1f);
			mMainScene.SetComponent<ParticleEmitterComponent>(mFireworkBurstEntity, burstComp);

			// Parent "launcher" emitter (sub-emitter linkage deferred to first update)
			var launcherComp = ParticleEmitterComponent.Default;
			launcherComp.MaxParticles = 50;
			launcherComp.SpawnRate = 0;
			launcherComp.BurstCount = 1;
			launcherComp.BurstInterval = 2.5f;
			launcherComp.BurstCycles = 0;
			launcherComp.ParticleLifetime = 1.0f;
			launcherComp.BlendMode = .Additive;
			launcherComp.StartColor = .(1.0f, 1.0f, 0.8f, 1.0f);
			launcherComp.EndColor = .(1.0f, 0.8f, 0.4f, 0.5f);
			launcherComp.StartSize = .(0.08f, 0.08f);
			launcherComp.EndSize = .(0.04f, 0.04f);
			launcherComp.InitialVelocity = .(0, 6.0f, 0);
			launcherComp.VelocityRandomness = .(0.5f, 1.0f, 0.5f);
			launcherComp.GravityMultiplier = 0.5f;
			launcherComp.Shape = EmissionShape.Point();
			mMainScene.SetComponent<ParticleEmitterComponent>(mFireworkLauncherEntity, launcherComp);
		}
		Console.WriteLine("  Created firework sub-emitter (launcher + burst on death)");

		// Create steam vent (soft particles + turbulence + upward buoyancy)
		mSteamEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSteamEntity);
			transform.Position = .(8.0f, 0.1f, -8.0f);
			mMainScene.SetTransform(mSteamEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 500;
			comp.SpawnRate = 30.0f;
			comp.ParticleLifetime = 3.0f;
			comp.BlendMode = .Alpha;
			comp.StartColor = .(1.0f, 1.0f, 1.0f, 0.4f);
			comp.EndColor = .(0.9f, 0.9f, 0.95f, 0.0f);
			comp.StartSize = .(0.2f, 0.2f);
			comp.EndSize = .(0.8f, 0.8f);
			comp.InitialVelocity = .(0, 2.5f, 0);
			comp.VelocityRandomness = .(0.3f, 0.5f, 0.3f);
			comp.GravityMultiplier = -0.2f;
			comp.Drag = 0.4f;
			comp.SoftParticleDistance = 1.0f;
			comp.SortParticles = true;
			comp.LifetimeVarianceMin = 0.7f;
			comp.LifetimeVarianceMax = 1.3f;
			comp.Shape = EmissionShape.Cone(0.35f, 0.1f);
			comp.AlphaOverLifetime = .FadeOut(0.8f, 0.5f);
			comp.SizeOverLifetime = .();
			comp.SizeOverLifetime.AddKey(0.0f, .(0.2f, 0.2f));
			comp.SizeOverLifetime.AddKey(0.5f, .(0.5f, 0.5f));
			comp.SizeOverLifetime.AddKey(1.0f, .(0.9f, 0.9f));
			comp.ForceModules.TurbulenceStrength = 1.2f;
			comp.ForceModules.TurbulenceFrequency = 0.8f;
			comp.ForceModules.TurbulenceSpeed = 0.8f;
			mMainScene.SetComponent<ParticleEmitterComponent>(mSteamEntity, comp);
		}
		Console.WriteLine("  Created steam vent (soft particles + turbulence)");

		// Create water fountain (ballistic arc + high speed)
		mFountainEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFountainEntity);
			transform.Position = .(-12.0f, 0.5f, 0.0f);
			mMainScene.SetTransform(mFountainEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 800;
			comp.SpawnRate = 120.0f;
			comp.ParticleLifetime = 2.0f;
			comp.BlendMode = .Alpha;
			comp.StartColor = .(0.5f, 0.7f, 1.0f, 0.8f);
			comp.EndColor = .(0.3f, 0.5f, 0.9f, 0.0f);
			comp.StartSize = .(0.06f, 0.06f);
			comp.EndSize = .(0.03f, 0.03f);
			comp.InitialVelocity = .(0, 10.0f, 0);
			comp.VelocityRandomness = .(1.0f, 1.5f, 1.0f);
			comp.GravityMultiplier = 2.5f;
			comp.Drag = 0.1f;
			comp.SortParticles = false;
			comp.LifetimeVarianceMin = 0.6f;
			comp.LifetimeVarianceMax = 1.0f;
			comp.Shape = EmissionShape.Cone(0.15f, 0.05f);
			comp.AlphaOverLifetime = .FadeOut(1.0f, 0.6f);
			mMainScene.SetComponent<ParticleEmitterComponent>(mFountainEntity, comp);
		}
		Console.WriteLine("  Created water fountain (ballistic arc + gravity)");

		// Create cherry blossoms (box emission + wind + gentle fall)
		mSnowEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSnowEntity);
			transform.Position = .(0.0f, 12.0f, 0.0f);
			mMainScene.SetTransform(mSnowEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 500;
			comp.SpawnRate = 40.0f;
			comp.ParticleLifetime = 8.0f;
			comp.BlendMode = .Alpha;
			comp.StartColor = .(1.0f, 0.4f, 0.5f, 0.9f);
			comp.EndColor = .(0.9f, 0.3f, 0.4f, 0.0f);
			comp.StartSize = .(0.08f, 0.08f);
			comp.EndSize = .(0.12f, 0.12f);
			comp.InitialVelocity = .(0, -0.5f, 0);
			comp.VelocityRandomness = .(0.2f, 0.1f, 0.2f);
			comp.GravityMultiplier = 0.15f;
			comp.Drag = 2.0f;
			comp.SortParticles = false;
			comp.LifetimeVarianceMin = 0.7f;
			comp.LifetimeVarianceMax = 1.3f;
			comp.Shape = EmissionShape.Box(.(10.0f, 0.5f, 10.0f));
			comp.AlphaOverLifetime = .FadeOut(0.7f, 0.8f);
			comp.ForceModules.WindForce = .(1.2f, 0.0f, 0.4f);
			comp.ForceModules.WindTurbulence = 0.6f;
			mMainScene.SetComponent<ParticleEmitterComponent>(mSnowEntity, comp);
		}
		Console.WriteLine("  Created cherry blossoms (box emission + wind drift)");

		// Create fairy dust / fireflies (turbulence + gentle float + glow)
		mFairyDustEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFairyDustEntity);
			transform.Position = .(12.0f, 1.5f, 5.0f);
			mMainScene.SetTransform(mFairyDustEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 200;
			comp.SpawnRate = 20.0f;
			comp.ParticleLifetime = 4.0f;
			comp.BlendMode = .Additive;
			comp.StartColor = .(1.0f, 0.85f, 0.4f, 0.9f);
			comp.EndColor = .(1.0f, 0.6f, 0.2f, 0.0f);
			comp.InitialVelocity = .(0, 0.2f, 0);
			comp.VelocityRandomness = .(0.4f, 0.3f, 0.4f);
			comp.GravityMultiplier = -0.05f;
			comp.Drag = 0.5f;
			comp.SortParticles = false;
			comp.LifetimeVarianceMin = 0.6f;
			comp.LifetimeVarianceMax = 1.4f;
			comp.Shape = EmissionShape.Sphere(2.5f);
			comp.SizeOverLifetime = .();
			comp.SizeOverLifetime.AddKey(0.0f, .(0.04f, 0.04f));
			comp.SizeOverLifetime.AddKey(0.3f, .(0.1f, 0.1f));
			comp.SizeOverLifetime.AddKey(0.7f, .(0.06f, 0.06f));
			comp.SizeOverLifetime.AddKey(1.0f, .(0.0f, 0.0f));
			comp.AlphaOverLifetime = .FadeOut(1.0f, 0.6f);
			comp.ForceModules.TurbulenceStrength = 0.4f;
			comp.ForceModules.TurbulenceFrequency = 0.6f;
			comp.ForceModules.TurbulenceSpeed = 0.5f;
			comp.ForceModules.VortexStrength = 0.8f;
			comp.ForceModules.VortexAxis = .(0, 1, 0);
			comp.ForceModules.VortexCenter = .(12.0f, 1.5f, 5.0f);
			mMainScene.SetComponent<ParticleEmitterComponent>(mFairyDustEntity, comp);
		}
		Console.WriteLine("  Created fairy dust (turbulence + vortex + glow)");

		// Create trailed sparks (gravity + per-particle trails)
		mTrailedSparksEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mTrailedSparksEntity);
			transform.Position = .(-5.0f, 3.0f, 10.0f);
			mMainScene.SetTransform(mTrailedSparksEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 100;
			comp.SpawnRate = 8.0f;
			comp.ParticleLifetime = 2.5f;
			comp.BlendMode = .Additive;
			comp.StartColor = .(1.0f, 0.8f, 0.2f, 1.0f);
			comp.EndColor = .(1.0f, 0.3f, 0.0f, 0.0f);
			comp.StartSize = .(0.06f, 0.06f);
			comp.EndSize = .(0.02f, 0.02f);
			comp.InitialVelocity = .(0, 5.0f, 0);
			comp.VelocityRandomness = .(3.0f, 2.0f, 3.0f);
			comp.GravityMultiplier = 1.5f;
			comp.Drag = 0.2f;
			comp.LifetimeVarianceMin = 0.6f;
			comp.LifetimeVarianceMax = 1.0f;
			comp.Shape = EmissionShape.Sphere(0.3f, true);
			comp.AlphaOverLifetime = .FadeOut(1.0f, 0.5f);
			comp.Trail.Enabled = true;
			comp.Trail.MaxPoints = 15;
			comp.Trail.RecordInterval = 0.015f;
			comp.Trail.Lifetime = 0.6f;
			comp.Trail.WidthStart = 0.04f;
			comp.Trail.WidthEnd = 0.0f;
			comp.Trail.MinVertexDistance = 0.05f;
			comp.Trail.UseParticleColor = true;
			mMainScene.SetComponent<ParticleEmitterComponent>(mTrailedSparksEntity, comp);
		}
		Console.WriteLine("  Created trailed sparks (gravity + per-particle trails)");

		// Create healing magic (green sparkles + attractor spiral)
		mHealingEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mHealingEntity);
			transform.Position = .(5.0f, 0.5f, 8.0f);
			mMainScene.SetTransform(mHealingEntity, transform);

			var comp = ParticleEmitterComponent.Default;
			comp.MaxParticles = 300;
			comp.SpawnRate = 35.0f;
			comp.ParticleLifetime = 2.5f;
			comp.BlendMode = .Additive;
			comp.StartColor = .(0.2f, 1.0f, 0.4f, 0.9f);
			comp.EndColor = .(0.1f, 0.8f, 0.3f, 0.0f);
			comp.InitialVelocity = .(0, 0.5f, 0);
			comp.VelocityRandomness = .(0.5f, 0.3f, 0.5f);
			comp.GravityMultiplier = -0.1f;
			comp.Drag = 0.3f;
			comp.SortParticles = false;
			comp.LifetimeVarianceMin = 0.7f;
			comp.LifetimeVarianceMax = 1.2f;
			comp.Shape = EmissionShape.Sphere(2.0f);
			comp.SizeOverLifetime = .();
			comp.SizeOverLifetime.AddKey(0.0f, .(0.02f, 0.02f));
			comp.SizeOverLifetime.AddKey(0.2f, .(0.08f, 0.08f));
			comp.SizeOverLifetime.AddKey(1.0f, .(0.0f, 0.0f));
			comp.AlphaOverLifetime = .FadeOut(1.0f, 0.6f);
			comp.ForceModules.AttractorStrength = 2.5f;
			comp.ForceModules.AttractorPosition = .(5.0f, 1.5f, 8.0f);
			comp.ForceModules.AttractorRadius = 3.0f;
			comp.ForceModules.VortexStrength = 2.0f;
			comp.ForceModules.VortexAxis = .(0, 1, 0);
			comp.ForceModules.VortexCenter = .(5.0f, 0.5f, 8.0f);
			mMainScene.SetComponent<ParticleEmitterComponent>(mHealingEntity, comp);
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

		// Create procedural decal texture (64x64 soft circle)
		{
			const int32 TexSize = 64;
			let pixels = new uint8[TexSize * TexSize * 4];
			let center = (float)TexSize / 2.0f;
			let radius = center - 2.0f;
			for (int32 y = 0; y < TexSize; y++)
			{
				for (int32 x = 0; x < TexSize; x++)
				{
					let dx = (float)x + 0.5f - center;
					let dy = (float)y + 0.5f - center;
					let dist = Math.Sqrt(dx * dx + dy * dy);
					let alpha = Math.Clamp(1.0f - (dist / radius), 0.0f, 1.0f);
					let idx = (y * TexSize + x) * 4;
					pixels[idx + 0] = 255;  // R
					pixels[idx + 1] = 255;  // G
					pixels[idx + 2] = 255;  // B
					pixels[idx + 3] = (uint8)(alpha * alpha * 255.0f);  // A (quadratic falloff)
				}
			}
			let image = new Sedulous.Imaging.Image((uint32)TexSize, (uint32)TexSize, .RGBA8, pixels);
			delete pixels;
			mDecalTextureResource = new TextureResource(image, true);
			mDecalTextureResource.AddRef();
			mDecalTextureResource.WrapU = .ClampToEdge;
			mDecalTextureResource.WrapV = .ClampToEdge;
			mDecalTextureResource.GenerateMipmaps = false;
		}

		// Create decal entities
		mDecalEntity1 = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mDecalEntity1);
			transform.Position = .(0.0f, 0.01f, 0.0f);
			mMainScene.SetTransform(mDecalEntity1, transform);

			let handle = renderModule.CreateDecal(mDecalEntity1);
			if (handle.IsValid)
			{
				if (let comp = mMainScene.GetComponent<DecalComponent>(mDecalEntity1))
				{
					comp.Scale = .(3.0f, 2.0f, 3.0f);
					comp.Color = .(1.0f, 0.3f, 0.2f, 0.8f);  // Red-ish tint
					comp.BlendMode = .Alpha;
					comp.SortOrder = 0;
					comp.Texture = ResourceHandle<TextureResource>(mDecalTextureResource);
				}
			}
		}
		Console.WriteLine("  Created floor decal (alpha, red)");

		mDecalEntity2 = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mDecalEntity2);
			transform.Position = .(2.0f, 0.01f, -2.0f);
			mMainScene.SetTransform(mDecalEntity2, transform);

			let handle = renderModule.CreateDecal(mDecalEntity2);
			if (handle.IsValid)
			{
				if (let comp = mMainScene.GetComponent<DecalComponent>(mDecalEntity2))
				{
					comp.Scale = .(2.0f, 1.0f, 2.0f);
					comp.Color = .(1.0f, 0.9f, 0.2f, 1.0f);  // Yellow tint
					comp.BlendMode = .Additive;
					comp.SortOrder = 1;
					comp.Texture = ResourceHandle<TextureResource>(mDecalTextureResource);
				}
			}
		}
		Console.WriteLine("  Created glow decal (additive, yellow)");

		// Create world-space UI panel (floating in 3D)
		{
			let uiModule = mMainScene.GetModule<UISceneModule>();
			if (uiModule != null)
			{
				mWorldUIPanelEntity = mMainScene.CreateEntity();
				var uiTransform = mMainScene.GetTransform(mWorldUIPanelEntity);
				uiTransform.Position = .(0.0f, 3.0f, -3.0f);
				mMainScene.SetTransform(mWorldUIPanelEntity, uiTransform);

				let panel = uiModule.CreateWorldUI(mWorldUIPanelEntity, 256, 192, 2.0f, 1.5f);
				if (panel != null)
				{
					// Build UI content on the panel
					mWorldSpaceUIRoot = new StackPanel();
					mWorldSpaceUIRoot.Background = Color(20, 20, 40, 220);
					mWorldSpaceUIRoot.Padding = Thickness(12);
					mWorldSpaceUIRoot.Spacing = 8;

					let panelTitle = new TextBlock();
					panelTitle.Text = "World Panel";
					panelTitle.Foreground = Color(180, 220, 255);
					panelTitle.FontSize = 16;
					mWorldSpaceUIRoot.AddChild(panelTitle);

					let panelInfo = new TextBlock();
					panelInfo.Text = "3D UI Surface";
					panelInfo.Foreground = Color(160, 160, 180);
					panelInfo.FontSize = 12;
					mWorldSpaceUIRoot.AddChild(panelInfo);

					let panelBtn = new Button("Click Me");
					panelBtn.Width = .Fixed(100);
					panelBtn.Click.Subscribe(new (btn) => {
						panel.MarkDirty();
					});
					mWorldSpaceUIRoot.AddChild(panelBtn);

					panel.GUIContext.RootElement = mWorldSpaceUIRoot;
					panel.MarkDirty();
					Console.WriteLine("  Created world-space UI panel");
				}
			}
		}

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
					proxy.Lifetime = 0.6f;
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

		// Set world ambient (matching RendererIntegrated)
		if (let world = renderModule.World)
		{
			world.AmbientColor = .(0.02f, 0.02f, 0.03f);
			world.AmbientIntensity = 0.5f;
		}

		Console.WriteLine("\nEntity count: {}", mMainScene.EntityCount);

		Console.WriteLine("\nControls:");
		Console.WriteLine("  Tab    - Toggle orbit/fly camera");
		Console.WriteLine("  Orbit: W/S pitch, A/D yaw, Q/E zoom");
		Console.WriteLine("  Fly:   W/S forward/back, A/D strafe, Q/E up/down");
		Console.WriteLine("         Shift: fast");
		Console.WriteLine("  Arrow keys - Rotate sun light");
		Console.WriteLine("  Space  - Toggle physics spawning");
		Console.WriteLine("  F      - Toggle physics debug draw");
		Console.WriteLine("  P      - Print profiler stats");
		Console.WriteLine("  Escape - Quit");
	}

	private void CreateUI()
	{
		if (mUISubsystem == null || !mUISubsystem.IsInitialized)
			return;

		// Create root canvas for absolute positioning
		mUIRoot = new Canvas();

		// Create a panel in the top-left corner
		let panel = new StackPanel();
		panel.Background = Color(20, 20, 30, 200);
		panel.Padding = Thickness(10);
		panel.Spacing = 6;

		// Title
		let title = new TextBlock();
		title.Text = "UI Controls";
		title.Foreground = Color(200, 220, 255);
		title.FontSize = 14;
		panel.AddChild(title);

		// Spawn toggle button
		let spawnBtn = new Button("Toggle Spawn");
		spawnBtn.Width = .Fixed(150);
		spawnBtn.Click.Subscribe(new (btn) => {
			mSpawningEnabled = !mSpawningEnabled;
		});
		panel.AddChild(spawnBtn);

		// Physics debug toggle
		let debugBtn = new Button("Toggle Debug Draw");
		debugBtn.Width = .Fixed(150);
		debugBtn.Click.Subscribe(new (btn) => {
			if (let physicsModule = mMainScene?.GetModule<PhysicsSceneModule>())
				physicsModule.DebugDrawEnabled = !physicsModule.DebugDrawEnabled;
		});
		panel.AddChild(debugBtn);

		// Roughness slider label
		let roughLabel = new TextBlock();
		roughLabel.Text = "Roughness";
		roughLabel.Foreground = Color(180, 180, 200);
		panel.AddChild(roughLabel);

		// Roughness slider
		let roughSlider = new Slider();
		roughSlider.Minimum = 0;
		roughSlider.Maximum = 100;
		roughSlider.Value = 95;
		roughSlider.Width = .Fixed(150);
		roughSlider.ValueChanged.Subscribe(new (slider, value) => {
			if (mSphereMaterial != null)
				mSphereMaterial.SetFloat("Roughness", (float)value / 100.0f);
		});
		panel.AddChild(roughSlider);

		// Metallic slider label
		let metalLabel = new TextBlock();
		metalLabel.Text = "Metallic";
		metalLabel.Foreground = Color(180, 180, 200);
		panel.AddChild(metalLabel);

		// Metallic slider
		let metalSlider = new Slider();
		metalSlider.Minimum = 0;
		metalSlider.Maximum = 100;
		metalSlider.Value = 0;
		metalSlider.Width = .Fixed(150);
		metalSlider.ValueChanged.Subscribe(new (slider, value) => {
			if (mSphereMaterial != null)
				mSphereMaterial.SetFloat("Metallic", (float)value / 100.0f);
		});
		panel.AddChild(metalSlider);

		// ==================== Scene Visuals ====================
		let visualsHeader = new TextBlock();
		visualsHeader.Text = "— Scene Visuals —";
		visualsHeader.Foreground = Color(220, 200, 100);
		panel.AddChild(visualsHeader);

		// Exposure (0–200 → 0.0–2.0)
		let expLabel = new TextBlock();
		expLabel.Text = "Exposure";
		expLabel.Foreground = Color(180, 180, 200);
		panel.AddChild(expLabel);

		let expSlider = new Slider();
		expSlider.Minimum = 0;
		expSlider.Maximum = 200;
		expSlider.Value = 100;
		expSlider.Width = .Fixed(150);
		expSlider.ValueChanged.Subscribe(new (slider, value) => {
			if (let world = mRenderModule?.World)
				world.Exposure = (float)value / 100.0f;
		});
		panel.AddChild(expSlider);

		// Ambient Intensity (0–100 → 0.0–1.0)
		let ambLabel = new TextBlock();
		ambLabel.Text = "Ambient Intensity";
		ambLabel.Foreground = Color(180, 180, 200);
		panel.AddChild(ambLabel);

		let ambSlider = new Slider();
		ambSlider.Minimum = 0;
		ambSlider.Maximum = 100;
		ambSlider.Value = 50;
		ambSlider.Width = .Fixed(150);
		ambSlider.ValueChanged.Subscribe(new (slider, value) => {
			if (let world = mRenderModule?.World)
				world.AmbientIntensity = (float)value / 100.0f;
		});
		panel.AddChild(ambSlider);

		// Sun Intensity (0–500 → 0.0–5.0)
		let sunLabel = new TextBlock();
		sunLabel.Text = "Sun Intensity";
		sunLabel.Foreground = Color(180, 180, 200);
		panel.AddChild(sunLabel);

		let sunSlider = new Slider();
		sunSlider.Minimum = 0;
		sunSlider.Maximum = 500;
		sunSlider.Value = 200;
		sunSlider.Width = .Fixed(150);
		sunSlider.ValueChanged.Subscribe(new (slider, value) => {
			if (let comp = mMainScene?.GetComponent<LightComponent>(mSunEntity))
				comp.Intensity = (float)value / 100.0f;
		});
		panel.AddChild(sunSlider);

		// Shadow Normal Bias (0–100 → 0.0–10.0)
		let biasLabel = new TextBlock();
		biasLabel.Text = "Shadow Normal Bias";
		biasLabel.Foreground = Color(180, 180, 200);
		panel.AddChild(biasLabel);

		let biasSlider = new Slider();
		biasSlider.Minimum = 0;
		biasSlider.Maximum = 100;
		biasSlider.Value = 30;
		biasSlider.Width = .Fixed(150);
		biasSlider.ValueChanged.Subscribe(new (slider, value) => {
			if (let comp = mMainScene?.GetComponent<LightComponent>(mSunEntity))
				comp.ShadowNormalBias = (float)value / 10.0f;
		});
		panel.AddChild(biasSlider);

		// ==================== Floor Color ====================
		let floorHeader = new TextBlock();
		floorHeader.Text = "— Floor Color —";
		floorHeader.Foreground = Color(220, 200, 100);
		panel.AddChild(floorHeader);

		// Floor R (0–100 → 0.0–1.0)
		let floorRLabel = new TextBlock();
		floorRLabel.Text = "R";
		floorRLabel.Foreground = Color(220, 140, 140);
		panel.AddChild(floorRLabel);

		let floorRSlider = new Slider();
		floorRSlider.Minimum = 0;
		floorRSlider.Maximum = 100;
		floorRSlider.Value = 40;
		floorRSlider.Width = .Fixed(150);
		floorRSlider.ValueChanged.Subscribe(new (slider, value) => {
			mFloorR = (float)value / 100.0f;
			if (mFloorMaterial != null)
				mFloorMaterial.SetColor("BaseColor", .(mFloorR, mFloorG, mFloorB, 1.0f));
		});
		panel.AddChild(floorRSlider);

		// Floor G (0–100 → 0.0–1.0)
		let floorGLabel = new TextBlock();
		floorGLabel.Text = "G";
		floorGLabel.Foreground = Color(140, 220, 140);
		panel.AddChild(floorGLabel);

		let floorGSlider = new Slider();
		floorGSlider.Minimum = 0;
		floorGSlider.Maximum = 100;
		floorGSlider.Value = 40;
		floorGSlider.Width = .Fixed(150);
		floorGSlider.ValueChanged.Subscribe(new (slider, value) => {
			mFloorG = (float)value / 100.0f;
			if (mFloorMaterial != null)
				mFloorMaterial.SetColor("BaseColor", .(mFloorR, mFloorG, mFloorB, 1.0f));
		});
		panel.AddChild(floorGSlider);

		// Floor B (0–100 → 0.0–1.0)
		let floorBLabel = new TextBlock();
		floorBLabel.Text = "B";
		floorBLabel.Foreground = Color(140, 140, 220);
		panel.AddChild(floorBLabel);

		let floorBSlider = new Slider();
		floorBSlider.Minimum = 0;
		floorBSlider.Maximum = 100;
		floorBSlider.Value = 40;
		floorBSlider.Width = .Fixed(150);
		floorBSlider.ValueChanged.Subscribe(new (slider, value) => {
			mFloorB = (float)value / 100.0f;
			if (mFloorMaterial != null)
				mFloorMaterial.SetColor("BaseColor", .(mFloorR, mFloorG, mFloorB, 1.0f));
		});
		panel.AddChild(floorBSlider);

		mUIRoot.AddChild(panel);
		CanvasProperties.SetLeft(panel, 10);
		CanvasProperties.SetTop(panel, 150);
		mUISubsystem.GUIContext.RootElement = mUIRoot;

		Console.WriteLine("UI overlay created");
	}

	private void CreateMeshes()
	{
		// Create mesh resources (framework handles GPU upload automatically)
		mCubeResource = StaticMeshResource.CreateCube(1.0f);
		mPlaneResource = StaticMeshResource.CreatePlane(ArenaHalfSize * 2, ArenaHalfSize * 2, 1, 1);
		mSphereResource = StaticMeshResource.CreateSphere(0.3f, 16, 12);
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

		// Cycle lighting debug mode (L key): 0=normal, 1=clusters, 2=light count, 3=diffuse only
		if (keyboard.IsKeyPressed(.L))
		{
			let lightBuffer = mForwardFeature?.Lighting?.LightBuffer;
			if (lightBuffer != null)
			{
				let mode = (lightBuffer.DebugMode + 1) % 4;
				lightBuffer.DebugMode = mode;
				String[4] names = .("Normal", "Cluster Index", "Light Count", "Diffuse Only");
				Console.WriteLine("Lighting debug: {}", names[mode]);
			}
		}

		// Toggle shadows (O key)
		if (keyboard.IsKeyPressed(.O))
		{
			let shadowRenderer = mForwardFeature?.ShadowRenderer;
			if (shadowRenderer != null)
			{
				shadowRenderer.EnableShadows = !shadowRenderer.EnableShadows;
				Console.WriteLine("Shadows: {}", shadowRenderer.EnableShadows ? "ON" : "OFF");
			}
		}

		// Sun light rotation (Arrow keys)
		{
			float lightRotSpeed = 0.03f;
			if (keyboard.IsKeyDown(.Left))
				mSunYaw -= lightRotSpeed;
			if (keyboard.IsKeyDown(.Right))
				mSunYaw += lightRotSpeed;
			if (keyboard.IsKeyDown(.Up))
				mSunPitch = Math.Clamp(mSunPitch + lightRotSpeed, -1.5f, -0.1f);
			if (keyboard.IsKeyDown(.Down))
				mSunPitch = Math.Clamp(mSunPitch - lightRotSpeed, -1.5f, -0.1f);
		}

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

		// Deferred sub-emitter linkage (proxy must exist first, created by PostUpdate)
		if (mNeedsSubEmitterSetup)
		{
			let renderModule = mMainScene?.GetModule<RenderSceneModule>();
			if (renderModule != null)
			{
				let burstHandle = renderModule.GetParticleEmitterProxyHandle(mFireworkBurstEntity);
				let launcherProxy = renderModule.GetParticleEmitterProxy(mFireworkLauncherEntity);
				if (burstHandle.IsValid && launcherProxy != null)
				{
					launcherProxy.SubEmitterCount = 1;
					launcherProxy.SubEmitters[0] = .()
					{
						Trigger = .OnDeath,
						ChildEmitter = burstHandle,
						SpawnCount = 30,
						Probability = 1.0f,
						InheritPosition = true
					};
					mNeedsSubEmitterSetup = false;
				}
			}
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
						let swingSpeed = 2.0f;
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

		// Update sun light direction from arrow keys
		UpdateSunLight();
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

		// Set mesh component - framework handles proxy creation and GPU upload
		mMainScene.SetComponent<MeshRendererComponent>(entity, .Default);
		var comp = mMainScene.GetComponent<MeshRendererComponent>(entity);
		comp.Mesh = ResourceHandle<StaticMeshResource>(mSphereResource);
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		comp.MaterialInstances[0] = mSphereMaterial ?? defaultMaterial;
		comp.MaterialInstances[0]?.AddRef();
		comp.MaterialRefs.Count = 1;

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

	private void UpdateSunLight()
	{
		// Update entity transform rotation so RenderSceneModule syncs the direction
		var transform = mMainScene.GetTransform(mSunEntity);
		transform.Rotation = Quaternion.CreateFromYawPitchRoll(mSunYaw, -mSunPitch, 0);
		mMainScene.SetTransform(mSunEntity, transform);

		// Update procedural sky sun direction (opposite of light travel direction)
		if (mSkyFeature != null)
		{
			float x = Math.Cos(mSunPitch) * Math.Sin(mSunYaw);
			float y = Math.Sin(mSunPitch);
			float z = Math.Cos(mSunPitch) * Math.Cos(mSunYaw);
			mSkyFeature.SkyParams.SunDirection = Vector3.Normalize(.(-x, -y, -z));
		}
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
		if (mOverlayFeature != null)
		{
			let bgColor = Color(0, 0, 0, 180);
			let brightBlue = Color(100, 180, 255, 255);
			let brightCyan = Color(100, 255, 255, 255);
			let brightGreen = Color(100, 255, 100, 255);
			// Compute camera-facing billboard vectors for world-space labels
			let camFwd = mCamera.Forward;
			var camRight = Vector3.Cross(camFwd, .(0, 1, 0));
			let rightLen = camRight.Length();
			if (rightLen < 0.001f)
				camRight = .(1, 0, 0);
			else
				camRight = camRight / rightLen;
			let camUp = Vector3.Normalize(Vector3.Cross(camRight, camFwd));

			// Label particle emitters with per-effect colors (matching RendererIntegrated style)
			mOverlayFeature.AddText("FIRE + SMOKE", .(0.0f, 3.5f, -8.0f), Color(255, 150, 50, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("SPARKS", .(-8.0f, 3.0f, -4.0f), Color(255, 255, 100, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("MAGIC ORB", .(8.0f, 4.0f, 0.0f), Color(150, 100, 255, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("TRAIL COMET", .(-8.0f, 4.5f, 8.0f), Color(255, 200, 50, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("FIREWORK", .(12.0f, 4.0f, -10.0f), Color(255, 255, 100, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("STEAM", .(8.0f, 3.5f, -8.0f), Color(200, 200, 255, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("FOUNTAIN", .(-12.0f, 4.0f, 0.0f), Color(100, 180, 255, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("FAIRY DUST", .(12.0f, 4.0f, 5.0f), Color(255, 220, 100, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("TRAILED SPARKS", .(-5.0f, 5.5f, 10.0f), Color(255, 180, 50, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("HEALING", .(5.0f, 3.5f, 8.0f), Color(50, 255, 100, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("SWORD TRAIL", .(-12.0f, 4.5f, 8.0f), Color(180, 150, 255, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("CHERRY BLOSSOMS", .(0.0f, 13.0f, 0.0f), Color(255, 130, 150, 255), 1.5f, camRight, camUp, .Overlay);
			mOverlayFeature.AddText("WORLD UI", .(0.0f, 4.8f, -3.0f), Color(180, 220, 255, 255), 1.5f, camRight, camUp, .Overlay);

			// Draw directional light direction (matching RendererIntegrated)
			{
				let renderModule = mMainScene?.GetModule<RenderSceneModule>();
				if (renderModule != null)
				{
					if (let light = renderModule.GetLightProxy(mSunEntity))
					{
						Vector3 sunOrigin = .(0, 8, 0);
						Vector3 sunEnd = sunOrigin + light.Direction * 5.0f;
						mOverlayFeature.AddArrow(sunOrigin, sunEnd, Color.Yellow, 0.3f, .Overlay);
						mOverlayFeature.AddSphere(sunOrigin, 0.3f, Color.Yellow, 8, .Overlay);
					}
				}
			}

			let white = Color(255, 255, 255, 255);
			let brightYellow = Color(255, 255, 100, 255);
			let brightOrange = Color(255, 180, 100, 255);

			// ===== TOP LEFT: Instructions =====
			mOverlayFeature.AddRect2D(5, 5, 400, 137, bgColor);
			mOverlayFeature.AddText2D("FRAMEWORK SANDBOX", 15, 12, brightYellow, 1.5f);

			if (mCamera.CurrentMode == .Orbital)
				mOverlayFeature.AddText2D("ORBITAL: WASD rotate, Q/E zoom, RMB drag", 15, 35, white, 1.0f);
			else
				mOverlayFeature.AddText2D("FLY: WASD move, Q/E up/down, RMB look", 15, 35, white, 1.0f);

			mOverlayFeature.AddText2D("Tab: Toggle camera    `: Back to orbital", 15, 52, white, 1.0f);
			mOverlayFeature.AddText2D("Arrow keys: Rotate sun light", 15, 69, white, 1.0f);
			mOverlayFeature.AddText2D("Space: Spawn objects  F: Debug draw", 15, 86, white, 1.0f);
			mOverlayFeature.AddText2D("P: Profiler           ESC: Exit", 15, 103, white, 1.0f);

			// ===== TOP RIGHT: Stats =====
			float panelX = (float)mRenderView.Width - 220;
			mOverlayFeature.AddRect2D(panelX, 5, 215, 135, bgColor);

			// FPS
			let fpsText = scope String();
			((int32)Math.Round(mSmoothedFps)).ToString(fpsText);
			mOverlayFeature.AddText2D("FPS:", panelX + 10, 12, brightBlue, 1.5f);
			mOverlayFeature.AddText2DRight(fpsText, 10, 12, brightCyan, 1.5f);

			// Object count
			let countText = scope String();
			mSpawnCount.ToString(countText);
			mOverlayFeature.AddText2D("Objects:", panelX + 10, 35, brightBlue, 1.5f);
			mOverlayFeature.AddText2DRight(countText, 10, 35, brightCyan, 1.5f);

			// Spawn status
			let spawnStatus = mSpawningEnabled ? "ON" : "OFF";
			let spawnColor = mSpawningEnabled ? brightGreen : brightBlue;
			mOverlayFeature.AddText2D("Spawn:", panelX + 10, 58, brightBlue, 1.5f);
			mOverlayFeature.AddText2DRight(spawnStatus, 10, 58, spawnColor, 1.5f);

			// Debug draw status
			let debugStatus = mPhysicsDebugDraw ? "ON" : "OFF";
			let debugColor = mPhysicsDebugDraw ? brightGreen : brightBlue;
			mOverlayFeature.AddText2D("Debug:", panelX + 10, 81, brightBlue, 1.5f);
			mOverlayFeature.AddText2DRight(debugStatus, 10, 81, debugColor, 1.5f);

			// Camera mode
			let camMode = (mCamera.CurrentMode == .Orbital) ? "ORBITAL" : "FLYTHROUGH";
			let camColor = (mCamera.CurrentMode == .Orbital) ? brightGreen : brightOrange;
			mOverlayFeature.AddText2D("Camera:", panelX + 10, 104, brightBlue, 1.2f);
			mOverlayFeature.AddText2DRight(camMode, 10, 104, camColor, 1.2f);
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

		// Render UI overlay (after 3D scene, before present)
		if (mUISubsystem != null && mUISubsystem.IsInitialized)
		{
			mUISubsystem.RenderUI(render.Encoder, render.CurrentTextureView,
				mSwapChain.Width, mSwapChain.Height, render.Frame.FrameIndex);
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

		// Mesh resources are cleaned up automatically via ~ delete _ on fields
		// GPU mesh cache is cleaned up when RenderSceneModule is destroyed

		// Context shutdown is handled by base Application after OnShutdown

		if(mFontService != null)
		{
			delete mFontService;
		}

		
		delete mUIRoot;
		delete mWorldSpaceUIRoot;

		// Shutdown render system (not owned by context)
		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Shutdown complete");
	}
}

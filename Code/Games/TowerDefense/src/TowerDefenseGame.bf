namespace TowerDefense;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Engine.Audio;
using Sedulous.Renderer;
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Audio.Decoders;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Debug;
using SampleFramework;
using TowerDefense.Data;
using TowerDefense.Maps;
using TowerDefense.Enemies;
using TowerDefense.Components;

/// Tower Defense game main class.
/// Phase 3: Enemy System - Enemies that follow the path.
class TowerDefenseGame : RHISampleApp
{
	// Engine Core
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;  // Owned by SceneManager

	// Services
	private RendererService mRendererService;
	private AudioService mAudioService;
	private RenderSceneComponent mRenderSceneComponent;

	// Audio backend
	private SDL3AudioSystem mAudioSystem;
	private AudioDecoderFactory mDecoderFactory ~ delete _;

	// Map system
	private MapBuilder mMapBuilder ~ delete _;
	private MapDefinition mCurrentMap ~ delete _;

	// Enemy system
	private EnemyFactory mEnemyFactory ~ delete _;

	// Game state
	private int32 mMoney = 200;
	private int32 mLives = 20;
	private int32 mEnemiesKilled = 0;

	// Entities
	private Entity mCameraEntity;

	// Camera control (top-down)
	private float mCameraHeight = 25.0f;
	private float mCameraTargetX = 0.0f;
	private float mCameraTargetZ = 0.0f;
	private float mCameraMoveSpeed = 20.0f;

	// Current frame
	private int32 mCurrentFrameIndex = 0;

	// Spawn timer for testing
	private float mSpawnTimer = 0.0f;
	private float mSpawnInterval = 2.0f;
	private bool mAutoSpawn = false;

	public this() : base(.()
		{
			Title = "Tower Defense",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.15f, 0.2f, 0.15f, 1.0f),  // Dark green background
			EnableDepth = true
		})
	{
	}

	protected override bool OnInitialize()
	{
		Console.WriteLine("=== Tower Defense - Phase 3: Enemy System ===");

		// Create logger
		mLogger = new DebugLogger(.Information);

		// Create engine context
		mContext = new Context(mLogger, 4);

		// Initialize renderer service
		if (!InitializeRenderer())
			return false;

		// Initialize audio service
		if (!InitializeAudio())
			return false;

		// Start context (enables automatic component creation)
		mContext.Startup();

		// Create game scene
		mScene = mContext.SceneManager.CreateScene("GameScene");
		mRenderSceneComponent = mScene.GetSceneComponent<RenderSceneComponent>();
		mContext.SceneManager.SetActiveScene(mScene);

		// Initialize map builder
		mMapBuilder = new MapBuilder(mScene, mRendererService);
		mMapBuilder.InitializeMaterials();

		// Initialize enemy factory
		mEnemyFactory = new EnemyFactory(mScene, mRendererService);
		mEnemyFactory.InitializeMaterials();

		// Subscribe to enemy events
		mEnemyFactory.OnEnemyReachedExit.Subscribe(new => OnEnemyReachedExit);
		mEnemyFactory.OnEnemyKilled.Subscribe(new => OnEnemyKilled);

		// Create scene entities (light, camera)
		CreateSceneEntities();

		// Load and build the first map
		LoadMap();

		Console.WriteLine("Initialization complete!");
		Console.WriteLine("Controls: WASD=Pan camera, QE=Zoom, Space=Spawn enemy, T=Toggle auto-spawn, Escape=Exit");
		Console.WriteLine($"Starting: Money={mMoney}, Lives={mLives}");

		return true;
	}

	private bool InitializeRenderer()
	{
		Console.WriteLine("Initializing renderer service...");

		mRendererService = new RendererService();
		mRendererService.SetFormats(SwapChain.Format, .Depth24PlusStencil8);

		let shaderPath = GetAssetPath("framework/shaders", .. scope .());
		if (mRendererService.Initialize(Device, shaderPath) case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}

		mContext.RegisterService<RendererService>(mRendererService);
		Console.WriteLine("Renderer service initialized");
		return true;
	}

	private bool InitializeAudio()
	{
		Console.WriteLine("Initializing audio service...");

		// Create SDL3 audio backend
		mAudioSystem = new SDL3AudioSystem();
		if (!mAudioSystem.IsInitialized)
		{
			Console.WriteLine("WARNING: Audio system failed to initialize");
			delete mAudioSystem;
			mAudioSystem = null;
			return true;  // Continue without audio
		}

		// Create decoder factory
		mDecoderFactory = new AudioDecoderFactory();
		mDecoderFactory.RegisterDefaultDecoders();

		// Create and register audio service
		mAudioService = new AudioService();
		if (mAudioService.Initialize(mAudioSystem) case .Err)
		{
			Console.WriteLine("WARNING: AudioService failed to initialize");
			delete mAudioService;
			mAudioService = null;
			return true;
		}

		mContext.RegisterService<AudioService>(mAudioService);
		Console.WriteLine($"Audio service initialized. Decoders: {mDecoderFactory.DecoderCount}");
		return true;
	}

	private void CreateSceneEntities()
	{
		// Create directional light (sun)
		{
			let sunLight = mScene.CreateEntity("SunLight");
			sunLight.Transform.LookAt(.(-0.4f, -1.0f, -0.3f));

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.95f, 0.85f), 1.2f, true);
			sunLight.AddComponent(lightComp);
		}

		// Create top-down camera
		{
			mCameraEntity = mScene.CreateEntity("MainCamera");
			UpdateCameraTransform();

			let cameraComp = new CameraComponent(Math.PI_f / 4.0f, 0.1f, 500.0f, true);
			cameraComp.UseReverseZ = false;
			cameraComp.SetViewport(SwapChain.Width, SwapChain.Height);
			mCameraEntity.AddComponent(cameraComp);
		}

		Console.WriteLine("Scene entities created");
	}

	private void LoadMap()
	{
		// Create Map01 - Grasslands
		mCurrentMap = Map01_Grasslands.Create();

		// Build the map (creates tile entities)
		mMapBuilder.BuildMap(mCurrentMap);

		// Set up enemy factory with waypoints
		mEnemyFactory.SetWaypoints(mCurrentMap.Waypoints);

		// Initialize game state from map
		mMoney = mCurrentMap.StartingMoney;
		mLives = mCurrentMap.StartingLives;

		Console.WriteLine($"Map loaded: {mCurrentMap.Name}");
		Console.WriteLine($"  Size: {mCurrentMap.Width}x{mCurrentMap.Height}");
		Console.WriteLine($"  Waypoints: {mCurrentMap.Waypoints.Count}");
		Console.WriteLine($"  Starting money: {mCurrentMap.StartingMoney}");
		Console.WriteLine($"  Starting lives: {mCurrentMap.StartingLives}");
	}

	private void UpdateCameraTransform()
	{
		if (mCameraEntity == null)
			return;

		// Position camera above target, looking down
		mCameraEntity.Transform.SetPosition(.(mCameraTargetX, mCameraHeight, mCameraTargetZ + 0.1f));

		// Look at target point
		let target = Vector3(mCameraTargetX, 0, mCameraTargetZ);
		mCameraEntity.Transform.LookAt(target);
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		if (let cameraComp = mCameraEntity?.GetComponent<CameraComponent>())
		{
			cameraComp.SetViewport(width, height);
		}
	}

	protected override void OnInput()
	{
		let keyboard = Shell.InputManager.Keyboard;

		// Camera panning with WASD
		float panSpeed = mCameraMoveSpeed * DeltaTime;

		if (keyboard.IsKeyDown(.W))
			mCameraTargetZ -= panSpeed;
		if (keyboard.IsKeyDown(.S))
			mCameraTargetZ += panSpeed;
		if (keyboard.IsKeyDown(.A))
			mCameraTargetX -= panSpeed;
		if (keyboard.IsKeyDown(.D))
			mCameraTargetX += panSpeed;

		// Zoom with Q/E
		float zoomSpeed = 20.0f * DeltaTime;
		if (keyboard.IsKeyDown(.Q))
			mCameraHeight = Math.Max(10.0f, mCameraHeight - zoomSpeed);
		if (keyboard.IsKeyDown(.E))
			mCameraHeight = Math.Min(100.0f, mCameraHeight + zoomSpeed);

		// Spawn enemy with Space
		if (keyboard.IsKeyPressed(.Space))
		{
			SpawnTestEnemy();
		}

		// Toggle auto-spawn with T
		if (keyboard.IsKeyPressed(.T))
		{
			mAutoSpawn = !mAutoSpawn;
			Console.WriteLine($"Auto-spawn: {mAutoSpawn}");
		}

		// Spawn different enemy types with 1-4
		if (keyboard.IsKeyPressed(.Num1))
			mEnemyFactory.SpawnEnemy(.BasicTank);
		if (keyboard.IsKeyPressed(.Num2))
			mEnemyFactory.SpawnEnemy(.FastTank);
		if (keyboard.IsKeyPressed(.Num3))
			mEnemyFactory.SpawnEnemy(.ArmoredTank);
		if (keyboard.IsKeyPressed(.Num4))
			mEnemyFactory.SpawnEnemy(.Helicopter);

		UpdateCameraTransform();
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Auto-spawn enemies
		if (mAutoSpawn && mLives > 0)
		{
			mSpawnTimer += deltaTime;
			if (mSpawnTimer >= mSpawnInterval)
			{
				mSpawnTimer = 0.0f;
				SpawnTestEnemy();
			}
		}

		// Update engine context (handles entity sync, visibility culling, etc.)
		mContext.Update(deltaTime);
	}

	private void SpawnTestEnemy()
	{
		// Randomly select an enemy type
		int32 roll = (int32)(TotalTime * 1000) % 4;
		EnemyDefinition def;
		switch (roll)
		{
		case 0: def = .BasicTank;
		case 1: def = .FastTank;
		case 2: def = .ArmoredTank;
		default: def = .BasicTank;
		}

		mEnemyFactory.SpawnEnemy(def);
		Console.WriteLine($"Spawned {def.Name}. Active enemies: {mEnemyFactory.ActiveEnemyCount}");
	}

	private void OnEnemyReachedExit(EnemyComponent enemy)
	{
		mLives -= enemy.Definition.Damage;
		Console.WriteLine($"Enemy reached exit! Lives: {mLives}");

		if (mLives <= 0)
		{
			Console.WriteLine("=== GAME OVER ===");
			mAutoSpawn = false;
		}
	}

	private void OnEnemyKilled(Entity enemy, int32 reward)
	{
		mMoney += reward;
		mEnemiesKilled++;
		Console.WriteLine($"Enemy killed! +${reward} (Total: ${mMoney}, Kills: {mEnemiesKilled})");
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		mCurrentFrameIndex = frameIndex;

		// Begin render graph frame
		mRendererService.BeginFrame(
			(uint32)frameIndex, DeltaTime, TotalTime,
			SwapChain.CurrentTexture, SwapChain.CurrentTextureView,
			mDepthTexture, DepthTextureView);
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Execute all render passes
		mRendererService.ExecuteFrame(encoder);
		return true;
	}

	protected override void OnCleanup()
	{
		Console.WriteLine("Cleaning up...");

		// Shutdown context
		mContext?.Shutdown();

		// Wait for GPU
		Device.WaitIdle();

		// Clean up enemy factory (releases materials)
		mEnemyFactory?.Cleanup();

		// Clean up map builder (releases materials)
		mMapBuilder?.Cleanup();

		// Delete services (in reverse order)
		delete mAudioService;
		delete mRendererService;

		// Audio system is owned by AudioService if takeOwnership=true (default)
		// But we created it ourselves, so if AudioService didn't take it, clean up
		if (mAudioSystem != null && mAudioService == null)
			delete mAudioSystem;

		Console.WriteLine("Cleanup complete");
	}
}

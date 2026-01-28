namespace TowerDefense;

using System;
using System.Collections;
using System.IO;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Resources;
using Sedulous.Materials;
using Sedulous.Render;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Input;
using Sedulous.Framework.Audio;
using Sedulous.Framework.UI;
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Audio.Decoders;
using Sedulous.Drawing.Fonts;
using Sedulous.Fonts;
using Sedulous.Fonts.TTF;
using Sedulous.UI;
using TowerDefense.Data;
using TowerDefense.Maps;
using TowerDefense.Enemies;
using TowerDefense.Towers;
using TowerDefense.Components;
using TowerDefense.Systems;
using TowerDefense.UI;
using TowerDefense.Audio;
using TowerDefense.Effects;

/// Tower Defense game main class.
/// Ported to Sedulous.Framework.* architecture.
class TowerDefenseGame : Application
{
	// Render system
	private RenderSystem mRenderSystem;
	private RenderView mRenderView;
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private ForwardTransparentFeature mTransparentFeature;
	private ParticleFeature mParticleFeature;
	private DebugRenderFeature mDebugFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Subsystems
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private InputSubsystem mInputSubsystem;
	private AudioSubsystem mAudioSubsystem;
	private UISubsystem mUISubsystem;

	// Scene
	private Scene mScene;
	private EntityId mCameraEntity;
	private EntityId mSunEntity;

	// Meshes
	private StaticMeshResource mCubeResource;

	// Materials
	private MaterialInstance mPreviewValidMat;
	private MaterialInstance mPreviewInvalidMat;

	// UI
	private FontService mFontService;
	private GameTheme mGameTheme ~ delete _;
	private MainMenu mMainMenu ~ delete _;
	private LevelSelect mLevelSelect ~ delete _;
	private GameHUD mGameHUD ~ delete _;

	// Audio backend
	private AudioDecoderFactory mDecoderFactory ~ delete _;

	// Game audio helper
	private GameAudio mGameAudio ~ delete _;

	// Map system
	private MapBuilder mMapBuilder ~ delete _;
	private MapDefinition mCurrentMap ~ delete _;

	// Enemy system
	private EnemyFactory mEnemyFactory ~ delete _;

	// Tower system
	private TowerFactory mTowerFactory ~ delete _;
	private int32 mSelectedTowerType = 0;  // 0=None, 1=Cannon, 2=Archer, 3=Frost, 4=Mortar, 5=SAM
	private EntityId mSelectedPlacedTower = .Invalid;  // Currently selected placed tower

	// Tower placement preview
	private EntityId mTowerPreview = .Invalid;
	private bool mPreviewValid = false;

	// Wave system
	private WaveSpawner mWaveSpawner ~ delete _;

	// Particle effects
	private ParticleEffects mParticleEffects ~ delete _;

	// Game state
	private GameState mGameState = .MainMenu;
	private GameState mPrePauseState = .MainMenu;
	private int32 mMoney = 200;
	private int32 mLives = 20;
	private int32 mEnemiesKilled = 0;
	private float mGameSpeed = 1.0f;

	// Camera control (top-down)
	private float mCameraHeight = 25.0f;
	private float mCameraTargetX = 0.0f;
	private float mCameraTargetZ = 0.0f;
	private float mCameraMoveSpeed = 20.0f;

	// Input actions
	private InputAction mMoveAction;
	private InputAction mZoomInAction;
	private InputAction mZoomOutAction;
	private InputAction mPauseAction;
	private InputAction mStartWaveAction;
	private InputAction mRestartAction;
	private InputAction mTower1Action;
	private InputAction mTower2Action;
	private InputAction mTower3Action;
	private InputAction mTower4Action;
	private InputAction mTower5Action;
	private InputAction mCancelAction;

	// Stored input state
	private Vector2 mMoveInput;
	private float mDeltaTime;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Context context)
	{
		Console.WriteLine("=== Tower Defense - Framework Port ===");

		FixedTimeStep = 1.0f / 60.0f;
		MaxFixedStepsPerFrame = 3;

		InitializeRenderSystem();
		RegisterSubsystems(context);
	}

	private void InitializeRenderSystem()
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope $"{AssetDirectory}/Render/Shaders",
			.BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("Failed to initialize RenderSystem");
			return;
		}

		mRenderView = new RenderView();
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.FieldOfView = Math.PI_f / 4.0f;
		mRenderView.NearPlane = 0.1f;
		mRenderView.FarPlane = 500.0f;

		// Register render features
		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mTransparentFeature = new ForwardTransparentFeature();
		mRenderSystem.RegisterFeature(mTransparentFeature);

		mParticleFeature = new ParticleFeature();
		mRenderSystem.RegisterFeature(mParticleFeature);

		mDebugFeature = new DebugRenderFeature();
		mRenderSystem.RegisterFeature(mDebugFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);

		Console.WriteLine("Render system initialized");
	}

	private void RegisterSubsystems(Context context)
	{
		// Scene subsystem
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);

		// Render subsystem
		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);

		// Input subsystem
		mInputSubsystem = new InputSubsystem();
		mInputSubsystem.SetInputManager(mShell.InputManager);
		context.RegisterSubsystem(mInputSubsystem);
		SetupInputActions();

		// Audio subsystem
		let audioSystem = new SDL3AudioSystem();
		mAudioSubsystem = new AudioSubsystem(audioSystem, takeOwnership: true);
		context.RegisterSubsystem(mAudioSubsystem);

		// UI subsystem - create after font service is initialized in OnContextStarted
		// mUISubsystem will be created later with font service

		Console.WriteLine("Subsystems registered");
	}

	private void SetupInputActions()
	{
		let gameContext = mInputSubsystem.CreateContext("Game", 0);

		// Camera movement: WASD
		mMoveAction = gameContext.RegisterAction("Move");
		mMoveAction.AddBinding(new CompositeBinding(.W, .S, .A, .D));

		// Camera zoom: Q/E
		mZoomInAction = gameContext.RegisterAction("ZoomIn");
		mZoomInAction.AddBinding(new KeyBinding(.Q));

		mZoomOutAction = gameContext.RegisterAction("ZoomOut");
		mZoomOutAction.AddBinding(new KeyBinding(.E));

		// Game controls
		mPauseAction = gameContext.RegisterAction("Pause");
		mPauseAction.AddBinding(new KeyBinding(.P));
		mPauseAction.AddBinding(new KeyBinding(.Escape));

		mStartWaveAction = gameContext.RegisterAction("StartWave");
		mStartWaveAction.AddBinding(new KeyBinding(.Space));

		mRestartAction = gameContext.RegisterAction("Restart");
		mRestartAction.AddBinding(new KeyBinding(.R));

		// Tower selection: F1-F5
		mTower1Action = gameContext.RegisterAction("Tower1");
		mTower1Action.AddBinding(new KeyBinding(.F1));

		mTower2Action = gameContext.RegisterAction("Tower2");
		mTower2Action.AddBinding(new KeyBinding(.F2));

		mTower3Action = gameContext.RegisterAction("Tower3");
		mTower3Action.AddBinding(new KeyBinding(.F3));

		mTower4Action = gameContext.RegisterAction("Tower4");
		mTower4Action.AddBinding(new KeyBinding(.F4));

		mTower5Action = gameContext.RegisterAction("Tower5");
		mTower5Action.AddBinding(new KeyBinding(.F5));

		mCancelAction = gameContext.RegisterAction("Cancel");
		mCancelAction.AddBinding(new KeyBinding(.Escape));
	}

	protected override void OnContextStarted()
	{
		InitializeUI();
		CreateMeshes();
		CreateMaterials();
		CreateScene();
		InitializeGameSystems();
		InitializeAudio();

		// Show main menu
		mGameState = .MainMenu;

		Console.WriteLine("Initialization complete!");
		Console.WriteLine("Press SPACE to start the game!");
	}

	private void InitializeUI()
	{
		// Initialize font service
		mFontService = new FontService();
		let fontPath = scope String();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		// Load font at different sizes
		int32[6] fontSizes = .(14, 16, 18, 20, 24, 32);
		for (let size in fontSizes)
		{
			FontLoadOptions options = .ExtendedLatin;
			options.PixelHeight = size;
			if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
			{
				Console.WriteLine($"Failed to load font at size {size}");
			}
		}

		// Create and initialize UI subsystem
		mUISubsystem = new UISubsystem(mFontService);
		mContext.RegisterSubsystem(mUISubsystem);

		if (mUISubsystem.InitializeRendering(mDevice, .BGRA8UnormSrgb, FrameConfig.MAX_FRAMES_IN_FLIGHT, mShell, mRenderSystem) case .Err)
		{
			Console.WriteLine("Failed to initialize UI rendering");
			return;
		}

		// Use GameTheme for dark UI with light text
		mGameTheme = new GameTheme();
		mUISubsystem.UIContext.RegisterService<ITheme>(mGameTheme);

		// Create main menu, level select, and game HUD
		mMainMenu = new MainMenu();
		mLevelSelect = new LevelSelect();
		mGameHUD = new GameHUD();

		// Start with main menu as root
		mUISubsystem.UIContext.RootElement = mMainMenu.RootElement;

		// Wire up main menu events
		mMainMenu.OnPlay.Subscribe(new () => {
			// Show level selection
			mUISubsystem.UIContext.RootElement = mLevelSelect.RootElement;
		});
		mMainMenu.OnQuit.Subscribe(new () => {
			Exit();
		});

		// Wire up level select events
		mLevelSelect.OnLevelSelected.Subscribe(new (levelIndex) => {
			StartGame(levelIndex);
		});
		mLevelSelect.OnBack.Subscribe(new () => {
			mUISubsystem.UIContext.RootElement = mMainMenu.RootElement;
		});

		// Wire up HUD events
		mGameHUD.OnTowerSelected.Subscribe(new (index) => {
			let def = GetTowerDefinitionByIndex(index + 1);  // HUD uses 0-4, we use 1-5
			SelectTower(index + 1, def);
		});
		mGameHUD.OnStartWave.Subscribe(new () => {
			TryStartNextWave();
		});
		mGameHUD.OnRestart.Subscribe(new () => {
			RestartGame();
		});
		mGameHUD.OnResume.Subscribe(new () => {
			ResumeGame();
		});
		mGameHUD.OnMainMenu.Subscribe(new () => {
			// Return to main menu
			mEnemyFactory?.ClearAllEnemies();
			mTowerFactory?.ClearAll();
			mParticleEffects?.Clear();
			mGameState = .MainMenu;
			mUISubsystem.UIContext.RootElement = mMainMenu.RootElement;
		});
		mGameHUD.OnSellTower.Subscribe(new () => {
			if (mSelectedPlacedTower.IsValid)
			{
				let refund = mTowerFactory.SellTower(mSelectedPlacedTower);
				mMoney += refund;
				DeselectPlacedTower();
				mGameHUD.HideTowerInfo();
			}
		});
		mGameHUD.OnUpgradeTower.Subscribe(new () => {
			if (mSelectedPlacedTower.IsValid)
			{
				let data = mTowerFactory.GetTowerData(mSelectedPlacedTower);
				if (data != null && data.CanUpgrade)
				{
					let cost = data.GetUpgradeCost();
					if (mMoney >= cost)
					{
						mMoney -= cost;
						mTowerFactory.UpgradeTower(mSelectedPlacedTower);
						mGameHUD.ShowTowerInfo(data);  // Refresh display
					}
				}
			}
		});
		mGameHUD.OnSpeedChanged.Subscribe(new (speed) => {
			mGameSpeed = speed;
		});
		mGameHUD.OnMusicVolumeChanged.Subscribe(new (vol) => {
			if (mGameAudio != null)
				mGameAudio.MusicVolume = vol;
		});
		mGameHUD.OnSFXVolumeChanged.Subscribe(new (vol) => {
			if (mGameAudio != null)
				mGameAudio.SFXVolume = vol;
		});

		Console.WriteLine("UI system initialized");
	}

	private void CreateMeshes()
	{
		mCubeResource = StaticMeshResource.CreateCube(1.0f);
		Console.WriteLine("Meshes created");
	}

	private void CreateMaterials()
	{
		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
		if (baseMat == null) return;

		// Tower preview materials
		mPreviewValidMat = new MaterialInstance(baseMat);
		mPreviewValidMat.SetColor("BaseColor", .(0.2f, 0.8f, 0.2f, 0.6f));
		mPreviewValidMat.SetFloat("Roughness", 0.8f);

		mPreviewInvalidMat = new MaterialInstance(baseMat);
		mPreviewInvalidMat.SetColor("BaseColor", .(0.8f, 0.2f, 0.2f, 0.6f));
		mPreviewInvalidMat.SetFloat("Roughness", 0.8f);

		Console.WriteLine("Materials created");
	}

	private void CreateScene()
	{
		mScene = mSceneSubsystem.CreateScene("GameScene");
		mSceneSubsystem.SetActiveScene(mScene);

		let renderModule = mScene.GetModule<RenderSceneModule>();
		if (renderModule == null)
		{
			Console.WriteLine("ERROR: No RenderSceneModule found!");
			return;
		}

		// Set ambient lighting (moderate ambient with strong directional for contrast)
		if (let world = renderModule.World)
		{
			world.AmbientColor = .(0.12f, 0.13f, 0.11f);
			world.AmbientIntensity = 0.6f;
			world.Exposure = 1.0f;
		}

		// Create camera (top-down)
		mCameraEntity = mScene.CreateEntity();
		renderModule.CreatePerspectiveCamera(mCameraEntity,
			Math.PI_f / 4.0f,
			(float)mSwapChain.Width / mSwapChain.Height,
			0.1f, 500.0f);
		renderModule.SetMainCamera(mCameraEntity);
		UpdateCameraTransform();

		// Create sun light (strong intensity for visible lit/shadow sides)
		mSunEntity = mScene.CreateEntity();
		renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.95f, 0.85f), 2.5f);
		var sunTransform = mScene.GetTransform(mSunEntity);
		// LookAt direction matching old Engine setup: .(-0.4f, -1.0f, -0.3f)
		let lightDir = Vector3.Normalize(.(-0.4f, -1.0f, -0.3f));
		sunTransform.Rotation = Quaternion.CreateFromRotationMatrix(Matrix.CreateLookAt(sunTransform.Position, lightDir, .(0, 1, 0)));
		mScene.SetTransform(mSunEntity, sunTransform);

		// Create tower preview entity
		CreateTowerPreview();

		Console.WriteLine("Scene created");
	}

	private void CreateTowerPreview()
	{
		let renderModule = mScene.GetModule<RenderSceneModule>();
		if (renderModule == null) return;

		mTowerPreview = mScene.CreateEntity();

		// Set initial position hidden
		var transform = mScene.GetTransform(mTowerPreview);
		transform.Position = .(0, -100, 0);
		mScene.SetTransform(mTowerPreview, transform);

		// Add mesh renderer component
		mScene.SetComponent<MeshRendererComponent>(mTowerPreview, .Default);
		var meshComp = mScene.GetComponent<MeshRendererComponent>(mTowerPreview);
		meshComp.Mesh = ResourceHandle<StaticMeshResource>(mCubeResource);
		meshComp.Material = mPreviewValidMat;

		Console.WriteLine("Tower preview created");
	}

	private void InitializeGameSystems()
	{
		let renderModule = mScene.GetModule<RenderSceneModule>();
		if (renderModule == null) return;

		// Initialize map builder (uses cube mesh for tiles)
		mMapBuilder = new MapBuilder(mScene, renderModule, mRenderSystem, mCubeResource);
		mMapBuilder.InitializeMaterials();

		// Initialize enemy factory
		mEnemyFactory = new EnemyFactory(mScene, renderModule, mRenderSystem, mCubeResource);
		mEnemyFactory.InitializeMaterials();

		// Subscribe to enemy events
		mEnemyFactory.OnEnemyReachedExit.Subscribe(new => OnEnemyReachedExit);
		mEnemyFactory.OnEnemyKilled.Subscribe(new => OnEnemyKilled);
		mEnemyFactory.OnEnemyDeathAudio.Subscribe(new (position) => {
			mGameAudio?.PlayEnemyDeath(position);
			mParticleEffects?.SpawnEnemyDeath(position, .(1.0f, 0.5f, 0.2f, 1.0f));
		});

		// Initialize tower factory (uses cube mesh for towers and projectiles)
		mTowerFactory = new TowerFactory(mScene, renderModule, mRenderSystem, mCubeResource, mCubeResource, mEnemyFactory, mGameAudio);
		mTowerFactory.InitializeMaterials();

		// Initialize particle effects (uses RenderWorld from RenderSceneModule)
		mParticleEffects = new ParticleEffects(renderModule.World, mRenderSystem.Device);

		// Subscribe to tower events
		mTowerFactory.OnTowerFired.Subscribe(new (def, position) => {
			mParticleEffects?.SpawnTowerFire(def.Name, position, .(0, 1, 0));
		});
		mTowerFactory.OnProjectileImpact.Subscribe(new (position, color) => {
			mParticleEffects?.SpawnProjectileHit(position, color);
		});

		// Initialize wave spawner
		mWaveSpawner = new WaveSpawner();
		mWaveSpawner.OnWaveStarted.Subscribe(new => OnWaveStarted);
		mWaveSpawner.OnWaveCompleted.Subscribe(new => OnWaveCompleted);
		mWaveSpawner.OnAllWavesCompleted.Subscribe(new => OnAllWavesCompleted);
		mWaveSpawner.OnSpawnEnemy.Subscribe(new => OnSpawnEnemyRequest);

		Console.WriteLine("Game systems initialized");
	}

	private void InitializeAudio()
	{
		mDecoderFactory = new AudioDecoderFactory();
		mDecoderFactory.RegisterDefaultDecoders();

		mGameAudio = new GameAudio(mAudioSubsystem, mDecoderFactory);

		Console.WriteLine("Audio initialized");
	}

	private void UpdateCameraTransform()
	{
		if (!mCameraEntity.IsValid)
			return;

		var transform = mScene.GetTransform(mCameraEntity);
		transform.Position = .(mCameraTargetX, mCameraHeight, mCameraTargetZ + 0.1f);

		// Look at target point
		let target = Vector3(mCameraTargetX, 0, mCameraTargetZ);
		let forward = Vector3.Normalize(target - transform.Position);
		let right = Vector3.Normalize(Vector3.Cross(.(0, 1, 0), forward));
		let up = Vector3.Cross(forward, right);
		transform.Rotation = Quaternion.CreateFromRotationMatrix(Matrix(
			right.X, right.Y, right.Z, 0,
			up.X, up.Y, up.Z, 0,
			-forward.X, -forward.Y, -forward.Z, 0,
			0, 0, 0, 1
		));

		mScene.SetTransform(mCameraEntity, transform);
	}

	protected override void OnInput()
	{
		let mouse = mShell.InputManager?.Mouse;

		// In main menu
		if (mGameState == .MainMenu)
		{
			if (mStartWaveAction.WasPressed)
				StartGame(0);  // Start level 1
			if (mCancelAction.WasPressed)
				Exit();
			return;
		}

		// Pause toggle
		if (mPauseAction.WasPressed)
		{
			if (mGameState == .Paused)
				ResumeGame();
			else if (mGameState != .MainMenu && mGameState != .Victory && mGameState != .GameOver)
				PauseGame();
			return;
		}

		// When paused
		if (mGameState == .Paused)
			return;

		// Store movement input
		mMoveInput = mMoveAction.Vector2Value;

		// Zoom
		if (mZoomInAction.IsActive)
			mCameraHeight = Math.Max(10.0f, mCameraHeight - 20.0f * mDeltaTime);
		if (mZoomOutAction.IsActive)
			mCameraHeight = Math.Min(100.0f, mCameraHeight + 20.0f * mDeltaTime);

		// Tower selection
		if (mTower1Action.WasPressed)
			SelectTower(1, .Cannon);
		if (mTower2Action.WasPressed)
			SelectTower(2, .Archer);
		if (mTower3Action.WasPressed)
			SelectTower(3, .SlowTower);
		if (mTower4Action.WasPressed)
			SelectTower(4, .Splash);
		if (mTower5Action.WasPressed)
			SelectTower(5, .AntiAir);

		// Cancel tower selection
		if (mCancelAction.WasPressed && mSelectedTowerType != 0)
		{
			mSelectedTowerType = 0;
			HideTowerPreview();
		}

		// Start wave
		if (mStartWaveAction.WasPressed)
			TryStartNextWave();

		// Restart
		if (mRestartAction.WasPressed)
			RestartGame();

		// Mouse input for tower placement
		if (mouse != null)
		{
			// Right click cancels selection
			if (mouse.IsButtonPressed(.Right))
			{
				if (mSelectedTowerType != 0)
				{
					mSelectedTowerType = 0;
					HideTowerPreview();
				}
				else if (mSelectedPlacedTower.IsValid)
				{
					DeselectPlacedTower();
				}
			}

			// Left click places tower or selects tower
			if (mouse.IsButtonPressed(.Left))
			{
				bool inHUDArea = mouse.Y < 50 || mouse.Y > (mSwapChain.Height - 80);
				if (!inHUDArea)
				{
					if (mSelectedTowerType != 0)
						TryPlaceTower(mouse.X, mouse.Y);
					else
						TrySelectPlacedTower(mouse.X, mouse.Y);
				}
			}

			// Update tower preview
			UpdateTowerPreview(mouse.X, mouse.Y);
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = frame.DeltaTime;

		// Skip updates when paused or in menu
		if (mGameState == .Paused || mGameState == .MainMenu)
			return;

		let scaledDelta = mDeltaTime * mGameSpeed;

		// Camera movement
		mCameraTargetX += mMoveInput.X * mCameraMoveSpeed * mDeltaTime;
		mCameraTargetZ -= mMoveInput.Y * mCameraMoveSpeed * mDeltaTime;
		UpdateCameraTransform();

		// Update game systems
		if (mGameState == .WaveInProgress)
			mWaveSpawner?.Update(scaledDelta);

		mTowerFactory?.Update(scaledDelta);
		mEnemyFactory?.Update(scaledDelta);
		mParticleEffects?.Update(scaledDelta);
	}

	protected override void OnFixedUpdate(float fixedDt)
	{
		// Physics updates go here if needed
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame(render.Frame.TotalTime, render.Frame.DeltaTime);

		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		// Set active render world
		if (let renderModule = mScene?.GetModule<RenderSceneModule>())
		{
			if (let world = renderModule.World)
				mRenderSystem.SetActiveWorld(world);
		}

		// Update HUD state
		UpdateHUD();

		// Draw debug visuals
		DrawDebugVisuals();

		// Update camera in render view
		var camTransform = mScene.GetTransform(mCameraEntity);
		var camPos = camTransform.Position;
		let camForward = Vector3.Normalize(Vector3(mCameraTargetX, 0, mCameraTargetZ) - camPos);
		mRenderView.CameraPosition = camPos;
		mRenderView.CameraForward = camForward;
		mRenderView.CameraUp = .(0, 1, 0);
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.UpdateMatrices(mDevice.FlipProjectionRequired);

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

		if (mRenderSystem.BuildRenderGraph(mRenderView) case .Ok)
			mRenderSystem.Execute(render.Encoder);

		mRenderSystem.EndFrame();

		// Render UI overlay
		if (mUISubsystem != null)
		{
			mUISubsystem.RenderUI(render.Encoder, render.SwapChain.CurrentTextureView,
				mSwapChain.Width, mSwapChain.Height, render.Frame.FrameIndex);
		}

		return true;
	}

	private void UpdateHUD()
	{
		// Skip HUD updates when in main menu (MainMenu class handles that)
		if (mGameState == .MainMenu || mGameHUD == null)
			return;

		// Update stats display
		mGameHUD.SetMoney(mMoney);
		mGameHUD.SetLives(mLives);
		mGameHUD.SetWave(mWaveSpawner?.CurrentWaveNumber ?? 0, mWaveSpawner?.TotalWaves ?? 0);

		// Update start wave button state
		bool canStartWave = (mGameState == .WaitingToStart || mGameState == .WavePaused);
		mGameHUD.SetStartWaveEnabled(canStartWave);
		if (canStartWave)
			mGameHUD.SetStartWaveText("Start Wave");
		else if (mGameState == .WaveInProgress)
			mGameHUD.SetStartWaveText("Wave Active...");
		else
			mGameHUD.SetStartWaveText("---");

		// Update overlays based on game state
		switch (mGameState)
		{
		case .MainMenu:
			// Handled by MainMenu class
		case .WaitingToStart, .WaveInProgress, .WavePaused:
			mGameHUD.HideOverlays();
		case .Paused:
			mGameHUD.HideOverlays();
			mGameHUD.ShowPause();
		case .Victory:
			mGameHUD.HideOverlays();
			mGameHUD.ShowVictory(mMoney, mEnemiesKilled);
		case .GameOver:
			mGameHUD.HideOverlays();
			mGameHUD.ShowGameOver(mWaveSpawner?.CurrentWaveNumber ?? 0, mEnemiesKilled);
		}

		// Update tower info panel
		if (mSelectedPlacedTower.IsValid)
		{
			let data = mTowerFactory?.GetTowerData(mSelectedPlacedTower);
			if (data != null)
				mGameHUD.ShowTowerInfo(data);
		}
	}

	private void DrawDebugVisuals()
	{
		if (mDebugFeature == null || mGameState == .MainMenu)
			return;

		// Draw enemy health bars
		DrawEnemyHealthBars();

		// Draw tower range indicator
		DrawTowerRangeIndicator();
	}

	private void DrawEnemyHealthBars()
	{
		if (mEnemyFactory == null) return;

		let enemies = scope List<EntityId>();
		mEnemyFactory.GetActiveEnemies(enemies);

		for (let enemy in enemies)
		{
			let healthPct = mEnemyFactory.GetEnemyHealthPercent(enemy);
			if (healthPct <= 0 || healthPct > 1)
				continue;

			var enemyTransform = mScene.GetTransform(enemy);
			let pos = enemyTransform.Position;

			let barWidth = 1.2f;
			let barHeight = 0.15f;
			let barY = pos.Y + 1.5f;

			let halfWidth = barWidth * 0.5f;
			let halfHeight = barHeight * 0.5f;

			// Background
			mDebugFeature.AddQuad(
				.(pos.X - halfWidth, barY, pos.Z - halfHeight),
				.(pos.X + halfWidth, barY, pos.Z - halfHeight),
				.(pos.X + halfWidth, barY, pos.Z + halfHeight),
				.(pos.X - halfWidth, barY, pos.Z + halfHeight),
				.(60, 20, 20, 200), .Overlay);

			// Foreground
			let fgWidth = barWidth * healthPct;
			let fgStartX = pos.X - halfWidth;
			uint8 r = (uint8)(255 * (1.0f - healthPct));
			uint8 g = (uint8)(255 * healthPct);

			mDebugFeature.AddQuad(
				.(fgStartX, barY + 0.01f, pos.Z - halfHeight * 0.8f),
				.(fgStartX + fgWidth, barY + 0.01f, pos.Z - halfHeight * 0.8f),
				.(fgStartX + fgWidth, barY + 0.01f, pos.Z + halfHeight * 0.8f),
				.(fgStartX, barY + 0.01f, pos.Z + halfHeight * 0.8f),
				.(r, g, 0, 255), .Overlay);
		}
	}

	private void DrawTowerRangeIndicator()
	{
		Vector3 center = .Zero;
		float range = 0;
		Color color = .(100, 200, 255, 180);

		// Preview tower
		if (mSelectedTowerType > 0 && mTowerPreview.IsValid)
		{
			var previewTransform = mScene.GetTransform(mTowerPreview);
			let previewPos = previewTransform.Position;
			if (previewPos.Y > -50)  // Not hidden
			{
				center = previewPos;
				let def = GetTowerDefinitionByIndex(mSelectedTowerType);
				range = def.Range;
				color = mPreviewValid ? Color(100, 255, 100, 150) : Color(255, 100, 100, 150);
			}
		}
		// Selected placed tower
		else if (mSelectedPlacedTower.IsValid)
		{
			var selectedTransform = mScene.GetTransform(mSelectedPlacedTower);
			center = selectedTransform.Position;
			range = mTowerFactory?.GetTowerRange(mSelectedPlacedTower) ?? 0;
		}

		if (range > 0)
			DrawCircleXZ(center, range, color, 32);
	}

	private void DrawCircleXZ(Vector3 center, float radius, Color color, int segments)
	{
		float angleStep = Math.PI_f * 2.0f / segments;
		float y = center.Y + 0.05f;

		for (int i = 0; i < segments; i++)
		{
			float a0 = i * angleStep;
			float a1 = (i + 1) * angleStep;
			Vector3 p0 = .(center.X + Math.Cos(a0) * radius, y, center.Z + Math.Sin(a0) * radius);
			Vector3 p1 = .(center.X + Math.Cos(a1) * radius, y, center.Z + Math.Sin(a1) * radius);
			mDebugFeature.AddLine(p0, p1, color, .Overlay);
		}
	}

	// ==================== Game Logic ====================

	private void StartGame(int32 levelIndex)
	{
		Console.WriteLine($"\n=== STARTING GAME (Level {levelIndex + 1}) ===\n");

		// Switch UI to game HUD
		mUISubsystem.UIContext.RootElement = mGameHUD.RootElement;
		mGameHUD.HideOverlays();

		LoadMap(levelIndex);
		mGameState = .WaitingToStart;
		mGameAudio?.StartMusic();

		Console.WriteLine($"Game started! Money=${mMoney}, Lives={mLives}");
	}

	private void LoadMap(int32 levelIndex)
	{
		// Clean up existing map
		if (mCurrentMap != null)
		{
			mMapBuilder?.ClearMap();
			mTowerFactory?.ClearAll();
			mEnemyFactory?.ClearAllEnemies();
			delete mCurrentMap;
			mCurrentMap = null;
		}

		// Create map
		switch (levelIndex)
		{
		case 0: mCurrentMap = Map01_Grasslands.Create();
		case 1: mCurrentMap = Map02_Desert.Create();
		case 2: mCurrentMap = Map03_Fortress.Create();
		default: mCurrentMap = Map01_Grasslands.Create();
		}

		// Build map
		mMapBuilder?.BuildMap(mCurrentMap);

		// Set up systems
		mEnemyFactory?.SetWaypoints(mCurrentMap.Waypoints);

		mWaveSpawner?.ClearWaves();
		for (let wave in mCurrentMap.Waves)
			mWaveSpawner?.AddWave(wave);

		// Reset state
		mMoney = mCurrentMap.StartingMoney;
		mLives = mCurrentMap.StartingLives;
		mEnemiesKilled = 0;
		mSelectedTowerType = 0;
		mSelectedPlacedTower = .Invalid;
		mGameSpeed = 1.0f;

		HideTowerPreview();

		Console.WriteLine($"Map loaded: {mCurrentMap.Name}");
	}

	private void SelectTower(int32 type, TowerDefinition def)
	{
		if (mGameState == .Victory || mGameState == .GameOver)
			return;

		mSelectedTowerType = type;
		Console.WriteLine($"Selected: {def.Name} (${def.Cost})");
	}

	private TowerDefinition GetTowerDefinitionByIndex(int32 index)
	{
		switch (index)
		{
		case 1: return .Cannon;
		case 2: return .Archer;
		case 3: return .SlowTower;
		case 4: return .Splash;
		case 5: return .AntiAir;
		default: return .Cannon;
		}
	}

	private void TryPlaceTower(float screenX, float screenY)
	{
		let worldPos = ScreenToWorld(screenX, screenY);
		let (gridX, gridY) = mCurrentMap.WorldToGrid(worldPos);

		if (gridX < 0 || gridY < 0)
			return;

		let tileType = mCurrentMap.GetTile(gridX, gridY);
		if (!mTowerFactory.CanPlaceTower(gridX, gridY, tileType))
			return;

		let def = GetTowerDefinitionByIndex(mSelectedTowerType);
		if (mMoney < def.Cost)
		{
			mGameAudio?.PlayNoMoney();
			return;
		}

		let tileWorldPos = mCurrentMap.GridToWorld(gridX, gridY);
		mTowerFactory.PlaceTower(def, tileWorldPos, gridX, gridY);
		mMoney -= def.Cost;
		mGameAudio?.PlayTowerPlace();

		mSelectedTowerType = 0;
		HideTowerPreview();
	}

	private void TrySelectPlacedTower(float screenX, float screenY)
	{
		let worldPos = ScreenToWorld(screenX, screenY);
		let (gridX, gridY) = mCurrentMap.WorldToGrid(worldPos);

		if (gridX < 0 || gridY < 0)
			return;

		let tower = mTowerFactory.GetTowerAt(gridX, gridY);
		if (tower.IsValid)
			mSelectedPlacedTower = tower;
		else
			DeselectPlacedTower();
	}

	private void DeselectPlacedTower()
	{
		mSelectedPlacedTower = .Invalid;
	}

	private void UpdateTowerPreview(float mouseX, float mouseY)
	{
		if (!mTowerPreview.IsValid)
			return;

		if (mSelectedTowerType == 0 || mGameState == .MainMenu || mGameState == .Victory || mGameState == .GameOver)
		{
			HideTowerPreview();
			return;
		}

		bool inHUDArea = mouseY < 50 || mouseY > (mSwapChain.Height - 80);
		if (inHUDArea)
		{
			HideTowerPreview();
			return;
		}

		let worldPos = ScreenToWorld(mouseX, mouseY);
		let (gridX, gridY) = mCurrentMap.WorldToGrid(worldPos);

		bool canPlace = false;
		Vector3 snappedPos = worldPos;

		if (gridX >= 0 && gridY >= 0)
		{
			let tileType = mCurrentMap.GetTile(gridX, gridY);
			canPlace = mTowerFactory.CanPlaceTower(gridX, gridY, tileType);
			snappedPos = mCurrentMap.GridToWorld(gridX, gridY);
		}

		let def = GetTowerDefinitionByIndex(mSelectedTowerType);
		float yPos = def.Scale * 0.5f;

		var transform = mScene.GetTransform(mTowerPreview);
		transform.Position = .(snappedPos.X, yPos, snappedPos.Z);
		transform.Scale = .(def.Scale * 0.8f, def.Scale, def.Scale * 0.8f);
		mScene.SetTransform(mTowerPreview, transform);

		if (canPlace != mPreviewValid)
		{
			mPreviewValid = canPlace;
			var meshComp = mScene.GetComponent<MeshRendererComponent>(mTowerPreview);
			meshComp.Material = canPlace ? mPreviewValidMat : mPreviewInvalidMat;
		}
	}

	private void HideTowerPreview()
	{
		if (!mTowerPreview.IsValid)
			return;

		var transform = mScene.GetTransform(mTowerPreview);
		transform.Position = .(0, -100, 0);
		mScene.SetTransform(mTowerPreview, transform);
	}

	private Vector3 ScreenToWorld(float screenX, float screenY)
	{
		float ndcX = (2.0f * screenX / mSwapChain.Width) - 1.0f;
		float ndcY = 1.0f - (2.0f * screenY / mSwapChain.Height);

		float fovY = Math.PI_f / 4.0f;
		float aspect = (float)mSwapChain.Width / (float)mSwapChain.Height;
		float halfHeight = mCameraHeight * Math.Tan(fovY / 2.0f);
		float halfWidth = halfHeight * aspect;

		float worldX = mCameraTargetX + ndcX * halfWidth;
		float worldZ = mCameraTargetZ - ndcY * halfHeight;

		return .(worldX, 0, worldZ);
	}

	private void TryStartNextWave()
	{
		if (mGameState != .WaitingToStart && mGameState != .WavePaused)
			return;

		if (mWaveSpawner.StartNextWave())
			mGameState = .WaveInProgress;
	}

	private void PauseGame()
	{
		mPrePauseState = mGameState;
		mGameState = .Paused;
		mGameAudio?.PauseMusic();
	}

	private void ResumeGame()
	{
		mGameState = mPrePauseState;
		mGameAudio?.ResumeMusic();
	}

	private void RestartGame()
	{
		Console.WriteLine("\n=== RESTARTING GAME ===\n");

		mEnemyFactory?.ClearAllEnemies();
		mTowerFactory?.ClearAll();
		mParticleEffects?.Clear();
		mWaveSpawner?.Reset();

		mWaveSpawner?.ClearWaves();
		for (let wave in mCurrentMap.Waves)
			mWaveSpawner?.AddWave(wave);

		mMoney = mCurrentMap.StartingMoney;
		mLives = mCurrentMap.StartingLives;
		mEnemiesKilled = 0;
		mSelectedTowerType = 0;
		mSelectedPlacedTower = .Invalid;
		mGameSpeed = 1.0f;

		HideTowerPreview();

		// Reset HUD state
		mGameHUD?.ClearSelection();
		mGameHUD?.HideTowerInfo();
		mGameHUD?.HideOverlays();
		mGameHUD?.ResetSpeed();

		mGameState = .WaitingToStart;
	}

	// ==================== Event Handlers ====================

	private void OnWaveStarted(int32 waveNumber)
	{
		Console.WriteLine($"\n=== WAVE {waveNumber}/{mWaveSpawner.TotalWaves} ===");
		mGameAudio?.PlayWaveStart();
	}

	private void OnWaveCompleted(int32 waveNumber, int32 bonusReward)
	{
		mMoney += bonusReward;
		Console.WriteLine($"Wave {waveNumber} complete! Bonus: +${bonusReward}");
		mGameAudio?.PlayWaveComplete();

		if (waveNumber < mWaveSpawner.TotalWaves)
			mGameState = .WavePaused;
	}

	private void OnAllWavesCompleted()
	{
		mGameState = .Victory;
		Console.WriteLine("\n=== VICTORY! ===");
		mGameAudio?.StopMusic();
		mGameAudio?.PlayVictory();
	}

	private void OnSpawnEnemyRequest(EnemyPreset preset)
	{
		EnemyDefinition def;
		switch (preset)
		{
		case .BasicTank: def = .BasicTank;
		case .FastTank: def = .FastTank;
		case .ArmoredTank: def = .ArmoredTank;
		case .Helicopter: def = .Helicopter;
		case .BossTank: def = .BossTank;
		}
		mEnemyFactory?.SpawnEnemy(def);
	}

	private void OnEnemyReachedExit(EnemyComponent enemy)
	{
		mWaveSpawner?.OnEnemyRemoved();
		mLives -= enemy.Definition.Damage;
		mGameAudio?.PlayEnemyExit();

		if (mLives <= 0)
		{
			mGameState = .GameOver;
			Console.WriteLine("\n=== GAME OVER ===");
			mGameAudio?.StopMusic();
			mGameAudio?.PlayGameOver();
		}
	}

	private void OnEnemyKilled(EntityId enemy, int32 reward)
	{
		mWaveSpawner?.OnEnemyRemoved();
		mMoney += reward;
		mEnemiesKilled++;
	}

	protected override void OnShutdown()
	{
		Console.WriteLine("Shutting down...");

		// Clean up UI (FontService is owned by UISubsystem)
		delete mFontService;

		// Clean up materials
		delete mPreviewValidMat;
		delete mPreviewInvalidMat;

		// Clean up render system
		if (mRenderSystem != null)
			mRenderSystem.Shutdown();
		delete mRenderView;
		delete mRenderSystem;

		Console.WriteLine("Shutdown complete");
	}
}

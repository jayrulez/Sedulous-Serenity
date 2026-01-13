namespace TowerDefense;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Engine.Audio;
using Sedulous.Engine.Input;
using Sedulous.Engine.UI;
using Sedulous.Renderer;
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Audio.Decoders;
using Sedulous.Drawing;
using Sedulous.Fonts;
using Sedulous.Fonts.TTF;
using Sedulous.UI;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Debug;
using SampleFramework;
using TowerDefense.Data;
using TowerDefense.Maps;
using TowerDefense.Enemies;
using TowerDefense.Towers;
using TowerDefense.Components;
using TowerDefense.Systems;
using TowerDefense.UI;
using TowerDefense.Audio;

/// Tower Defense game main class.
/// Phase 7: Audio - Sound effects and music.
class TowerDefenseGame : RHISampleApp
{
	// Engine Core
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;  // Owned by SceneManager

	// Services
	private RendererService mRendererService;
	private DebugDrawService mDebugDrawService;
	private AudioService mAudioService;
	private InputService mInputService;
	private UIService mUIService;
	private RenderSceneComponent mRenderSceneComponent;
	private UISceneComponent mUISceneComponent;

	// UI
	private MainMenu mMainMenu ~ delete _;
	private LevelSelect mLevelSelect ~ delete _;
	private GameHUD mGameHUD ~ delete _;
	private ITheme mUITheme ~ delete _;
	private GameFontService mFontService ~ delete _;
	private IFont mFont ~ delete _;
	private IFontAtlas mFontAtlas ~ delete _;
	private CachedFont mCachedFont ~ delete _;
	private Sedulous.RHI.ITexture mAtlasTexture;  // Deleted in OnCleanup (GPU resource)
	private ITextureView mAtlasTextureView;       // Deleted in OnCleanup (GPU resource)
	private TextureRef mFontTextureRef ~ delete _;

	// Audio backend
	private SDL3AudioSystem mAudioSystem;
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
	private Entity mSelectedPlacedTower = null;  // Currently selected placed tower (for info panel)

	// Tower placement preview
	private Entity mTowerPreview;
	private StaticMeshComponent mPreviewMeshComp;
	private StaticMesh mPreviewMesh ~ delete _;
	private MaterialHandle mPreviewBaseMaterial = .Invalid;
	private MaterialInstanceHandle mPreviewValidMaterial = .Invalid;
	private MaterialInstanceHandle mPreviewInvalidMaterial = .Invalid;
	private bool mPreviewValid = false;

	// Wave system
	private WaveSpawner mWaveSpawner ~ delete _;

	// Game state
	private GameState mGameState = .MainMenu;
	private GameState mPrePauseState = .MainMenu;  // State before pausing (to restore on resume)
	private int32 mMoney = 200;
	private int32 mLives = 20;
	private int32 mEnemiesKilled = 0;
	private float mGameSpeed = 1.0f;  // Game speed multiplier (1x, 2x, 3x)

	// Entities
	private Entity mCameraEntity;

	// Camera control (top-down)
	private float mCameraHeight = 25.0f;
	private float mCameraTargetX = 0.0f;
	private float mCameraTargetZ = 0.0f;
	private float mCameraMoveSpeed = 20.0f;

	// Current frame
	private int32 mCurrentFrameIndex = 0;

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
		Console.WriteLine("=== Tower Defense - Phase 7: Audio ===");

		// Initialize font first (needed for UI)
		if (!InitializeFont())
			return false;

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

		// Create game audio helper (after audio service)
		mGameAudio = new GameAudio(mAudioService, mDecoderFactory);

		// Initialize input service
		mInputService = new InputService(Shell.InputManager);
		mContext.RegisterService<InputService>(mInputService);

		// Initialize UI service
		if (!InitializeUI())
			return false;

		// Start context (enables automatic component creation)
		mContext.Startup();

		// Create game scene
		mScene = mContext.SceneManager.CreateScene("GameScene");
		mRenderSceneComponent = mScene.GetSceneComponent<RenderSceneComponent>();
		mUISceneComponent = mScene.GetSceneComponent<UISceneComponent>();
		mUISceneComponent?.SetViewportSize(SwapChain.Width, SwapChain.Height);
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

		// Subscribe to enemy death audio event
		mEnemyFactory.OnEnemyDeathAudio.Subscribe(new (position) => {
			mGameAudio?.PlayEnemyDeath(position);
		});

		// Initialize tower factory (pass GameAudio for AudioSourceComponent)
		mTowerFactory = new TowerFactory(mScene, mRendererService, mEnemyFactory, mGameAudio);
		mTowerFactory.InitializeMaterials();

		// Note: Tower fire audio is now played via AudioSourceComponent on each tower entity
		// The OnTowerFired event is still available for visual effects if needed

		// Create tower placement preview
		CreateTowerPreview();

		// Initialize wave spawner
		mWaveSpawner = new WaveSpawner();
		mWaveSpawner.OnWaveStarted.Subscribe(new => OnWaveStarted);
		mWaveSpawner.OnWaveCompleted.Subscribe(new => OnWaveCompleted);
		mWaveSpawner.OnAllWavesCompleted.Subscribe(new => OnAllWavesCompleted);
		mWaveSpawner.OnSpawnEnemy.Subscribe(new => OnSpawnEnemyRequest);

		// Create scene entities (light, camera)
		CreateSceneEntities();

		// Build game UI (map is loaded when level is selected)
		BuildUI();

		Console.WriteLine("Initialization complete!");
		Console.WriteLine("Tower Defense running. Click PLAY to start!");

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

		// Create and register debug draw service (for health bars, range indicators)
		mDebugDrawService = new DebugDrawService();
		mContext.RegisterService<DebugDrawService>(mDebugDrawService);

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

	private bool InitializeFont()
	{
		Console.WriteLine("Initializing fonts...");

		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		if (!File.Exists(fontPath))
		{
			Console.WriteLine($"Font not found: {fontPath}");
			return false;
		}

		TrueTypeFonts.Initialize();

		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = 16;

		if (FontLoaderFactory.LoadFont(fontPath, options) case .Ok(let font))
			mFont = font;
		else
		{
			Console.WriteLine("Failed to load font");
			return false;
		}

		if (FontLoaderFactory.CreateAtlas(mFont, options) case .Ok(let atlas))
		{
			mFontAtlas = atlas;
			Console.WriteLine($"Font atlas created: {mFontAtlas.Width}x{mFontAtlas.Height}");
		}
		else
		{
			Console.WriteLine("Failed to create font atlas");
			return false;
		}

		return true;
	}

	private bool CreateAtlasTexture()
	{
		let atlasWidth = mFontAtlas.Width;
		let atlasHeight = mFontAtlas.Height;
		let r8Data = mFontAtlas.PixelData;

		// Convert R8 to RGBA8
		uint8[] rgba8Data = new uint8[atlasWidth * atlasHeight * 4];
		defer delete rgba8Data;

		for (uint32 i = 0; i < atlasWidth * atlasHeight; i++)
		{
			let alpha = r8Data[i];
			rgba8Data[i * 4 + 0] = 255;
			rgba8Data[i * 4 + 1] = 255;
			rgba8Data[i * 4 + 2] = 255;
			rgba8Data[i * 4 + 3] = alpha;
		}

		TextureDescriptor textureDesc = TextureDescriptor.Texture2D(
			atlasWidth, atlasHeight, .RGBA8Unorm, .Sampled | .CopyDst
		);

		if (Device.CreateTexture(&textureDesc) not case .Ok(let texture))
		{
			Console.WriteLine("Failed to create atlas texture");
			return false;
		}
		mAtlasTexture = texture;

		TextureDataLayout dataLayout = .()
		{
			Offset = 0,
			BytesPerRow = atlasWidth * 4,
			RowsPerImage = atlasHeight
		};
		Extent3D writeSize = .(atlasWidth, atlasHeight, 1);
		Device.Queue.WriteTexture(mAtlasTexture, Span<uint8>(rgba8Data.Ptr, rgba8Data.Count), &dataLayout, &writeSize);

		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
		if (Device.CreateTextureView(mAtlasTexture, &viewDesc) not case .Ok(let view))
		{
			Console.WriteLine("Failed to create atlas texture view");
			return false;
		}
		mAtlasTextureView = view;

		mFontTextureRef = new TextureRef(mAtlasTexture, atlasWidth, atlasHeight);
		mCachedFont = new CachedFont(mFont, mFontAtlas);
		mFont = null;  // CachedFont now owns the font
		mFontAtlas = null;  // CachedFont now owns the atlas

		return true;
	}

	private bool InitializeUI()
	{
		Console.WriteLine("Initializing UI service...");

		// Create atlas texture for UI rendering
		if (!CreateAtlasTexture())
			return false;

		// Create and configure UIService
		mUIService = new UIService();

		// Register font service
		mFontService = new GameFontService(mCachedFont, mFontTextureRef);
		mUIService.SetFontService(mFontService);

		// Register theme
		mUITheme = new GameTheme();
		mUIService.SetTheme(mUITheme);

		// Set atlas texture
		let (wu, wv) = mCachedFont.Atlas.WhitePixelUV;
		mUIService.SetAtlasTexture(mAtlasTextureView, .(wu, wv));

		mContext.RegisterService<UIService>(mUIService);
		Console.WriteLine("UI service initialized");
		return true;
	}

	private void BuildUI()
	{
		if (mUISceneComponent == null)
		{
			Console.WriteLine("WARNING: No UISceneComponent available");
			return;
		}

		// Create main menu
		mMainMenu = new MainMenu();

		// Subscribe to menu events
		mMainMenu.OnPlay.Subscribe(new () => {
			mGameAudio?.PlayUIClick();
			ShowLevelSelect();
		});

		mMainMenu.OnQuit.Subscribe(new () => {
			mGameAudio?.PlayUIClick();
			Shell.RequestExit();
		});

		// Create level select screen
		mLevelSelect = new LevelSelect();

		mLevelSelect.OnLevelSelected.Subscribe(new (levelIndex) => {
			mGameAudio?.PlayUIClick();
			StartGame(levelIndex);
		});

		mLevelSelect.OnBack.Subscribe(new () => {
			mGameAudio?.PlayUIClick();
			ShowMainMenu();
		});

		// Create game HUD
		mGameHUD = new GameHUD();

		// Subscribe to HUD events
		mGameHUD.OnTowerSelected.Subscribe(new (index) => {
			mGameAudio?.PlayUIClick();
			SelectTowerByIndex(index);
		});

		mGameHUD.OnStartWave.Subscribe(new () => {
			mGameAudio?.PlayUIClick();
			TryStartNextWave();
		});

		mGameHUD.OnRestart.Subscribe(new () => {
			mGameAudio?.PlayUIClick();
			RestartGame();
		});

		mGameHUD.OnResume.Subscribe(new () => {
			mGameAudio?.PlayUIClick();
			ResumeGame();
		});
		mGameHUD.OnMainMenu.Subscribe(new () => {
			mGameAudio?.PlayUIClick();
			ReturnToMainMenu();
		});
		mGameHUD.OnSellTower.Subscribe(new () => {
			mGameAudio?.PlayUIClick();
			SellSelectedTower();
		});
		mGameHUD.OnUpgradeTower.Subscribe(new () => {
			mGameAudio?.PlayUIClick();
			UpgradeSelectedTower();
		});
		mGameHUD.OnMusicVolumeChanged.Subscribe(new (volume) => {
			mGameAudio?.SetMusicVolume(volume);
		});
		mGameHUD.OnSFXVolumeChanged.Subscribe(new (volume) => {
			mGameAudio?.SetSFXVolume(volume);
		});
		mGameHUD.OnSpeedChanged.Subscribe(new (speed) => {
			mGameSpeed = speed;
			Console.WriteLine($"Game speed: {speed}x");
		});

		// Sync initial volume values to HUD
		if (mGameAudio != null)
			mGameHUD.SetVolumes(mGameAudio.MusicVolume, mGameAudio.SFXVolume);

		// Start with main menu visible
		ShowMainMenu();

		Console.WriteLine("Game UI built");
	}

	private void ShowMainMenu()
	{
		// Simply swap root element - no need for visibility toggling
		mUISceneComponent.RootElement = mMainMenu.RootElement;
		mGameState = .MainMenu;
	}

	private void ShowLevelSelect()
	{
		mUISceneComponent.RootElement = mLevelSelect.RootElement;
		mGameState = .MainMenu;  // Still in menu state
	}

	private void ShowGameUI()
	{
		// Simply swap root element - no need for visibility toggling
		mUISceneComponent.RootElement = mGameHUD.RootElement;
		mGameHUD.HideOverlays();  // Ensure overlays are hidden
		UpdateHUD();
	}

	private void StartGame(int32 levelIndex)
	{
		Console.WriteLine($"\n=== STARTING GAME (Level {levelIndex + 1}) ===\n");

		// Load the selected map
		LoadMap(levelIndex);

		// Switch to game UI
		ShowGameUI();

		// Start background music
		mGameAudio?.StartMusic();

		// Set game state
		mGameState = .WaitingToStart;

		// Update HUD
		UpdateHUD();

		Console.WriteLine($"Game started! Money=${mMoney}, Lives={mLives}");
		Console.WriteLine("Press SPACE or click 'Start Wave' to begin Wave 1!");
	}

	private void SelectTowerByIndex(int32 index)
	{
		// Map index to tower type (1-based in the game logic)
		mSelectedTowerType = index + 1;

		TowerDefinition def;
		switch (index)
		{
		case 0: def = .Cannon;
		case 1: def = .Archer;
		case 2: def = .SlowTower;  // Frost Tower
		case 3: def = .Splash;     // Mortar Tower
		case 4: def = .AntiAir;    // SAM Tower
		default: return;
		}

		Console.WriteLine($"Selected: {def.Name} (${def.Cost})");
	}

	private void UpdateHUD()
	{
		if (mGameHUD == null)
			return;

		mGameHUD.SetMoney(mMoney);
		mGameHUD.SetLives(mLives);
		mGameHUD.SetWave(mWaveSpawner.CurrentWaveNumber, mWaveSpawner.TotalWaves);

		// Update start wave button
		bool canStartWave = (mGameState == .WaitingToStart || mGameState == .WavePaused);
		mGameHUD.SetStartWaveEnabled(canStartWave);

		if (mGameState == .WaveInProgress)
			mGameHUD.SetStartWaveText("Wave In Progress");
		else if (mGameState == .WaitingToStart)
			mGameHUD.SetStartWaveText("Start Wave 1");
		else if (mGameState == .WavePaused)
			mGameHUD.SetStartWaveText(scope $"Start Wave {mWaveSpawner.CurrentWaveNumber + 1}");
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

	private void LoadMap(int32 levelIndex)
	{
		// Clean up existing map if any
		if (mCurrentMap != null)
		{
			mMapBuilder.ClearMap();
			mTowerFactory.ClearAll();
			mEnemyFactory.ClearAllEnemies();
			delete mCurrentMap;
			mCurrentMap = null;
		}

		// Create the selected map
		switch (levelIndex)
		{
		case 0:
			mCurrentMap = Map01_Grasslands.Create();
		case 1:
			mCurrentMap = Map02_Desert.Create();
		case 2:
			mCurrentMap = Map03_Fortress.Create();
		default:
			mCurrentMap = Map01_Grasslands.Create();  // Fallback
		}

		// Build the map (creates tile entities)
		mMapBuilder.BuildMap(mCurrentMap);

		// Set up enemy factory with waypoints
		mEnemyFactory.SetWaypoints(mCurrentMap.Waypoints);

		// Set up wave spawner with map waves
		mWaveSpawner.ClearWaves();
		for (let wave in mCurrentMap.Waves)
			mWaveSpawner.AddWave(wave);

		// Initialize game values from map (state is set by menu/StartGame)
		mMoney = mCurrentMap.StartingMoney;
		mLives = mCurrentMap.StartingLives;
		mEnemiesKilled = 0;
		mSelectedTowerType = 0;
		mSelectedPlacedTower = null;
		mGameSpeed = 1.0f;

		Console.WriteLine($"Map loaded: {mCurrentMap.Name}");
		Console.WriteLine($"  Size: {mCurrentMap.Width}x{mCurrentMap.Height}");
		Console.WriteLine($"  Waypoints: {mCurrentMap.Waypoints.Count}");
		Console.WriteLine($"  Waves: {mCurrentMap.Waves.Count}");
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

	private void CreateTowerPreview()
	{
		// Create preview entity (initially hidden far below ground)
		mTowerPreview = mScene.CreateEntity("TowerPreview");
		mTowerPreview.Transform.SetPosition(.(0, -100, 0));  // Hidden below ground

		// Add mesh component using tower mesh
		mPreviewMesh = StaticMesh.CreateCube(1.0f);
		mPreviewMeshComp = new StaticMeshComponent();
		mTowerPreview.AddComponent(mPreviewMeshComp);
		mPreviewMeshComp.SetMesh(mPreviewMesh);

		// Create semi-transparent materials for valid/invalid placement
		let materialSystem = mRendererService.MaterialSystem;
		if (materialSystem == null)
			return;

		// Create base PBR material for preview
		let basePbrMaterial = Material.CreatePBR("PreviewMaterial");
		mPreviewBaseMaterial = materialSystem.RegisterMaterial(basePbrMaterial);
		if (!mPreviewBaseMaterial.IsValid)
			return;

		// Valid placement material (green, semi-transparent)
		mPreviewValidMaterial = materialSystem.CreateInstance(mPreviewBaseMaterial);
		if (mPreviewValidMaterial.IsValid)
		{
			let instance = materialSystem.GetInstance(mPreviewValidMaterial);
			if (instance != null)
			{
				instance.SetFloat4("baseColor", .(0.2f, 0.8f, 0.2f, 0.6f));
				instance.SetFloat("metallic", 0.0f);
				instance.SetFloat("roughness", 0.8f);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0.1f, 0.3f, 0.1f, 1.0f));
				materialSystem.UploadInstance(mPreviewValidMaterial);
			}
		}

		// Invalid placement material (red, semi-transparent)
		mPreviewInvalidMaterial = materialSystem.CreateInstance(mPreviewBaseMaterial);
		if (mPreviewInvalidMaterial.IsValid)
		{
			let instance = materialSystem.GetInstance(mPreviewInvalidMaterial);
			if (instance != null)
			{
				instance.SetFloat4("baseColor", .(0.8f, 0.2f, 0.2f, 0.6f));
				instance.SetFloat("metallic", 0.0f);
				instance.SetFloat("roughness", 0.8f);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0.3f, 0.1f, 0.1f, 1.0f));
				materialSystem.UploadInstance(mPreviewInvalidMaterial);
			}
		}

		// Start with valid material
		mPreviewMeshComp.SetMaterialInstance(0, mPreviewValidMaterial);
		Console.WriteLine("Tower preview created");
	}

	private void UpdateTowerPreview(float mouseX, float mouseY)
	{
		if (mTowerPreview == null)
			return;

		// Hide preview if no tower selected or in wrong game state
		if (mSelectedTowerType == 0 || mGameState == .MainMenu || mGameState == .Victory || mGameState == .GameOver)
		{
			mTowerPreview.Transform.SetPosition(.(0, -100, 0));  // Hidden below ground
			return;
		}

		// Check if mouse is over HUD area
		bool inHUDArea = mouseY < 50 || mouseY > (SwapChain.Height - 80);
		if (inHUDArea)
		{
			mTowerPreview.Transform.SetPosition(.(0, -100, 0));  // Hidden below ground
			return;
		}

		// Convert screen position to world position
		let worldPos = ScreenToWorld(mouseX, mouseY);

		// Convert to grid coordinates
		let (gridX, gridY) = mCurrentMap.WorldToGrid(worldPos);

		// Get tile type and check validity
		bool canPlace = false;
		Vector3 snappedPos = worldPos;

		if (gridX >= 0 && gridY >= 0)
		{
			let tileType = mCurrentMap.GetTile(gridX, gridY);
			canPlace = mTowerFactory.CanPlaceTower(gridX, gridY, tileType);

			// Snap preview to grid center
			snappedPos = mCurrentMap.GridToWorld(gridX, gridY);
		}

		// Get current tower definition for scale
		TowerDefinition def;
		switch (mSelectedTowerType)
		{
		case 1: def = .Cannon;
		case 2: def = .Archer;
		case 3: def = .SlowTower;
		case 4: def = .Splash;
		case 5: def = .AntiAir;
		default: def = .Cannon;
		}

		// Position preview at grid-snapped location
		float yPos = def.Scale * 0.5f;
		mTowerPreview.Transform.SetPosition(.(snappedPos.X, yPos, snappedPos.Z));
		mTowerPreview.Transform.SetScale(.(def.Scale * 0.8f, def.Scale, def.Scale * 0.8f));

		// Update material based on validity
		if (canPlace != mPreviewValid)
		{
			mPreviewValid = canPlace;
			mPreviewMeshComp.SetMaterialInstance(0, canPlace ? mPreviewValidMaterial : mPreviewInvalidMaterial);
		}
	}

	private void HideTowerPreview()
	{
		if (mTowerPreview != null)
			mTowerPreview.Transform.SetPosition(.(0, -100, 0));
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		if (let cameraComp = mCameraEntity?.GetComponent<CameraComponent>())
		{
			cameraComp.SetViewport(width, height);
		}

		// Update UI viewport
		mUISceneComponent?.SetViewportSize(width, height);
	}

	protected override bool OnEscapePressed()
	{
		// Application handles Escape key - don't let base class exit
		return true;
	}

	protected override void OnInput()
	{
		let keyboard = Shell.InputManager.Keyboard;
		let mouse = Shell.InputManager.Mouse;

		// In main menu - only handle Escape to quit
		if (mGameState == .MainMenu)
		{
			if (keyboard.IsKeyPressed(.Escape))
				Shell.RequestExit();
			return;
		}

		// Pause toggle with P key (works in any gameplay state)
		if (keyboard.IsKeyPressed(.P))
		{
			TogglePause();
			return;
		}

		// When paused - only allow Escape to unpause
		if (mGameState == .Paused)
		{
			if (keyboard.IsKeyPressed(.Escape))
				ResumeGame();
			return;
		}

		// Escape: cancel tower selection, or pause game
		if (keyboard.IsKeyPressed(.Escape))
		{
			if (mSelectedTowerType != 0)
			{
				mSelectedTowerType = 0;
				mGameHUD?.ClearSelection();
				HideTowerPreview();
				Console.WriteLine("Tower selection cancelled");
			}
			else if (mSelectedPlacedTower != null)
			{
				DeselectPlacedTower();
			}
			else
			{
				// Pause the game instead of returning to main menu
				PauseGame();
				return;
			}
		}

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

		// Tower selection with F1-F5
		if (keyboard.IsKeyPressed(.F1))
			SelectTower(1, .Cannon);
		if (keyboard.IsKeyPressed(.F2))
			SelectTower(2, .Archer);
		if (keyboard.IsKeyPressed(.F3))
			SelectTower(3, .SlowTower);
		if (keyboard.IsKeyPressed(.F4))
			SelectTower(4, .Splash);
		if (keyboard.IsKeyPressed(.F5))
			SelectTower(5, .AntiAir);

		// Cancel tower selection or deselect placed tower with Right Click
		if (mouse.IsButtonPressed(.Right))
		{
			if (mSelectedTowerType != 0)
			{
				mSelectedTowerType = 0;
				mGameHUD?.ClearSelection();
				HideTowerPreview();
				Console.WriteLine("Tower selection cancelled");
			}
			else if (mSelectedPlacedTower != null)
			{
				DeselectPlacedTower();
			}
		}

		// Place tower with Left Click (only if not clicking on UI HUD areas)
		if (mouse.IsButtonPressed(.Left) && mSelectedTowerType != 0)
		{
			// Check if click is in HUD areas (top bar: 50px, bottom panel: 80px)
			bool inHUDArea = mouse.Y < 50 || mouse.Y > (SwapChain.Height - 80);
			if (!inHUDArea)
			{
				// Click is not on HUD - try to place tower
				TryPlaceTower(mouse.X, mouse.Y);
			}
		}
		// Select placed tower with Left Click (when not in placement mode)
		else if (mouse.IsButtonPressed(.Left) && mSelectedTowerType == 0)
		{
			bool inHUDArea = mouse.Y < 50 || mouse.Y > (SwapChain.Height - 80);
			if (!inHUDArea)
			{
				TrySelectPlacedTower(mouse.X, mouse.Y);
			}
		}

		// Start wave with Space
		if (keyboard.IsKeyPressed(.Space))
		{
			TryStartNextWave();
		}

		// Restart game with R
		if (keyboard.IsKeyPressed(.R))
		{
			RestartGame();
		}

		UpdateCameraTransform();

		// Update tower placement preview
		UpdateTowerPreview(mouse.X, mouse.Y);
	}

	private void ReturnToMainMenu()
	{
		Console.WriteLine("\n=== RETURNING TO MAIN MENU ===\n");

		// Hide tower preview
		HideTowerPreview();

		// Reset game state
		ResetGameState();

		// Show main menu
		ShowMainMenu();
	}

	private void TryStartNextWave()
	{
		// Can only start waves in WaitingToStart or WavePaused states
		if (mGameState != .WaitingToStart && mGameState != .WavePaused)
		{
			if (mGameState == .WaveInProgress)
				Console.WriteLine("Wave already in progress!");
			else if (mGameState == .Victory)
				Console.WriteLine("You already won! Press R to restart.");
			else if (mGameState == .GameOver)
				Console.WriteLine("Game over! Press R to restart.");
			return;
		}

		if (mWaveSpawner.StartNextWave())
		{
			mGameState = .WaveInProgress;
		}
	}

	private void ResetGameState()
	{
		// Clear all enemies
		mEnemyFactory.ClearAllEnemies();

		// Clear all towers
		mTowerFactory.ClearAll();

		// Reset wave spawner
		mWaveSpawner.Reset();

		// Reload wave definitions
		mWaveSpawner.ClearWaves();
		for (let wave in mCurrentMap.Waves)
			mWaveSpawner.AddWave(wave);

		// Reset game variables
		mMoney = mCurrentMap.StartingMoney;
		mLives = mCurrentMap.StartingLives;
		mEnemiesKilled = 0;
		mSelectedTowerType = 0;
		mSelectedPlacedTower = null;  // Clear stale reference before towers are deleted
		mGameSpeed = 1.0f;  // Reset speed to 1x

		// Hide tower preview
		HideTowerPreview();

		// Reset UI
		mGameHUD?.HideOverlays();
		mGameHUD?.ClearSelection();
		mGameHUD?.ResetSpeed();
	}

	private void RestartGame()
	{
		Console.WriteLine("\n=== RESTARTING GAME ===\n");

		// Reset game state
		ResetGameState();

		// Set state to waiting
		mGameState = .WaitingToStart;

		// Update UI
		UpdateHUD();

		Console.WriteLine($"Game restarted! Money=${mMoney}, Lives={mLives}");
		Console.WriteLine("Press SPACE to start Wave 1!");
	}

	private void PauseGame()
	{
		// Can only pause during active gameplay
		if (mGameState == .MainMenu || mGameState == .Victory || mGameState == .GameOver || mGameState == .Paused)
			return;

		Console.WriteLine("Game paused");
		mPrePauseState = mGameState;
		mGameState = .Paused;
		mGameAudio?.PauseMusic();
		mGameHUD?.ShowPause();
	}

	private void ResumeGame()
	{
		if (mGameState != .Paused)
			return;

		Console.WriteLine("Game resumed");
		mGameState = mPrePauseState;
		mGameAudio?.ResumeMusic();
		mGameHUD?.HidePause();
	}

	private void TogglePause()
	{
		if (mGameState == .Paused)
			ResumeGame();
		else
			PauseGame();
	}

	private void SelectTower(int32 type, TowerDefinition def)
	{
		// Can't place towers during victory/game over
		if (mGameState == .Victory || mGameState == .GameOver)
		{
			Console.WriteLine("Press R to restart the game first!");
			return;
		}

		mSelectedTowerType = type;
		Console.WriteLine($"Selected: {def.Name} (${def.Cost})");
	}

	/// Gets tower definition by selection index (1-5).
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
		// Convert screen position to world position (simple top-down projection)
		let worldPos = ScreenToWorld(screenX, screenY);

		// Convert to grid coordinates
		let (gridX, gridY) = mCurrentMap.WorldToGrid(worldPos);
		if (gridX < 0 || gridY < 0)
		{
			Console.WriteLine("Cannot place tower outside map!");
			return;
		}

		// Get tile type
		let tileType = mCurrentMap.GetTile(gridX, gridY);

		// Check if placement is valid
		if (!mTowerFactory.CanPlaceTower(gridX, gridY, tileType))
		{
			Console.WriteLine("Cannot place tower here!");
			return;
		}

		// Get tower definition
		TowerDefinition def;
		switch (mSelectedTowerType)
		{
		case 1: def = .Cannon;
		case 2: def = .Archer;
		case 3: def = .SlowTower;
		case 4: def = .Splash;
		case 5: def = .AntiAir;
		default: return;
		}

		// Check if we have enough money
		if (mMoney < def.Cost)
		{
			mGameAudio?.PlayNoMoney();
			Console.WriteLine($"Not enough money! Need ${def.Cost}, have ${mMoney}");
			return;
		}

		// Place the tower
		let tileWorldPos = mCurrentMap.GridToWorld(gridX, gridY);
		mTowerFactory.PlaceTower(def, tileWorldPos, gridX, gridY);
		mMoney -= def.Cost;
		mGameAudio?.PlayTowerPlace();
		Console.WriteLine($"Placed {def.Name}! Money: ${mMoney}");

		// Clear selection after placing
		mSelectedTowerType = 0;
		mGameHUD?.ClearSelection();
		HideTowerPreview();

		UpdateHUD();
	}

	/// Tries to select a placed tower at the screen position.
	private void TrySelectPlacedTower(float screenX, float screenY)
	{
		let worldPos = ScreenToWorld(screenX, screenY);

		// Convert to grid coordinates
		let (gridX, gridY) = mCurrentMap.WorldToGrid(worldPos);
		if (gridX < 0 || gridY < 0)
			return;

		// Check if there is a tower at this position
		let tower = mTowerFactory.GetTowerAt(gridX, gridY);
		if (tower != null)
		{
			mSelectedPlacedTower = tower;
			let towerComp = tower.GetComponent<TowerComponent>();
			if (towerComp != null)
			{
				Console.WriteLine($"Selected {towerComp.Definition.Name} tower at ({gridX}, {gridY})");
				mGameHUD?.ShowTowerInfo(towerComp);
			}
		}
		else
		{
			// Clicked on empty space - deselect
			DeselectPlacedTower();
		}
	}

	/// Deselects the currently selected placed tower.
	private void DeselectPlacedTower()
	{
		if (mSelectedPlacedTower != null)
		{
			Console.WriteLine("Deselected tower");
			mSelectedPlacedTower = null;
			mGameHUD?.HideTowerInfo();
		}
	}

	/// Sells the currently selected placed tower.
	private void SellSelectedTower()
	{
		if (mSelectedPlacedTower == null)
			return;

		let refund = mTowerFactory.SellTower(mSelectedPlacedTower);
		mMoney += refund;
		Console.WriteLine($"Sold tower for ${refund}. Money: ${mMoney}");
		mSelectedPlacedTower = null;
		mGameHUD?.HideTowerInfo();
		UpdateHUD();
	}

	/// Upgrades the currently selected placed tower.
	private void UpgradeSelectedTower()
	{
		if (mSelectedPlacedTower == null)
			return;

		let towerComp = mSelectedPlacedTower.GetComponent<TowerComponent>();
		if (towerComp == null)
			return;

		// Check if can upgrade
		if (!towerComp.CanUpgrade)
		{
			Console.WriteLine("Tower is already at max level!");
			return;
		}

		// Check if we have enough money
		let cost = towerComp.GetUpgradeCost();
		if (mMoney < cost)
		{
			mGameAudio?.PlayNoMoney();
			Console.WriteLine($"Not enough money! Need ${cost}, have ${mMoney}");
			return;
		}

		// Perform upgrade
		mMoney -= cost;
		towerComp.Upgrade();
		Console.WriteLine($"Upgraded {towerComp.Definition.Name} to level {towerComp.Level}! Money: ${mMoney}");

		// Refresh tower info panel to show new stats
		mGameHUD?.ShowTowerInfo(towerComp);
		UpdateHUD();
	}

	private Vector3 ScreenToWorld(float screenX, float screenY)
	{
		// Simple conversion for top-down camera
		// Assumes camera is looking straight down at ground plane (Y=0)
		let cameraComp = mCameraEntity.GetComponent<CameraComponent>();
		if (cameraComp == null)
			return .Zero;

		// Normalize screen coordinates to -1..1
		float ndcX = (2.0f * screenX / SwapChain.Width) - 1.0f;
		float ndcY = 1.0f - (2.0f * screenY / SwapChain.Height);

		// Calculate world position based on camera height and FOV
		float fovY = Math.PI_f / 4.0f;
		float aspect = (float)SwapChain.Width / (float)SwapChain.Height;
		float halfHeight = mCameraHeight * Math.Tan(fovY / 2.0f);
		float halfWidth = halfHeight * aspect;

		float worldX = mCameraTargetX + ndcX * halfWidth;
		float worldZ = mCameraTargetZ - ndcY * halfHeight;  // Negative because camera looks down

		return .(worldX, 0, worldZ);
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Apply game speed multiplier
		let scaledDelta = deltaTime * mGameSpeed;

		// When paused, use zero delta time so components don't update movement/cooldowns
		let effectiveDelta = (mGameState == .Paused) ? 0.0f : scaledDelta;

		// Skip game logic updates when in main menu or paused
		if (mGameState != .MainMenu && mGameState != .Paused)
		{
			// Update wave spawner during active wave
			if (mGameState == .WaveInProgress)
			{
				mWaveSpawner.Update(scaledDelta);
			}

			// Update tower system (targeting, firing, projectiles)
			mTowerFactory.Update(scaledDelta);

			// Update enemy system (death animations cleanup)
			mEnemyFactory.Update(scaledDelta);
		}

		// Update engine context (handles entity sync, visibility culling, etc.)
		// Pass zero delta when paused to freeze component updates
		mContext.Update(effectiveDelta);

		// Draw debug visuals (health bars, range indicators)
		DrawDebugVisuals();
	}

	/// Draws health bars above enemies and range indicators for towers.
	private void DrawDebugVisuals()
	{
		let debugDraw = mRendererService?.DebugDrawService;
		if (debugDraw == null)
			return;

		// Don't draw during main menu
		if (mGameState == .MainMenu)
			return;

		// Draw enemy health bars
		DrawEnemyHealthBars(debugDraw);

		// Draw tower range indicator
		DrawTowerRangeIndicator(debugDraw);
	}

	/// Draws health bars above all active enemies.
	private void DrawEnemyHealthBars(DebugDrawService debugDraw)
	{
		if (mEnemyFactory == null)
			return;

		let enemies = scope List<Entity>();
		mEnemyFactory.GetActiveEnemies(enemies);

		for (let enemy in enemies)
		{
			let healthComp = enemy.GetComponent<HealthComponent>();
			if (healthComp == null || healthComp.IsDead)
				continue;

			let pos = enemy.Transform.WorldPosition;
			let healthPct = healthComp.HealthPercent;

			// Health bar dimensions
			let barWidth = 1.2f;
			let barHeight = 0.15f;
			let barY = pos.Y + 1.5f;  // Height above enemy

			// For top-down view, draw horizontal bar on XZ plane
			let halfWidth = barWidth * 0.5f;
			let halfHeight = barHeight * 0.5f;

			// Background (dark red) - full width
			let bgColor = Color(60, 20, 20, 200);
			debugDraw.DrawQuad(
				.(pos.X - halfWidth, barY, pos.Z - halfHeight),
				.(pos.X + halfWidth, barY, pos.Z - halfHeight),
				.(pos.X + halfWidth, barY, pos.Z + halfHeight),
				.(pos.X - halfWidth, barY, pos.Z + halfHeight),
				bgColor, .Overlay);

			// Foreground (green to red based on health) - scaled by health
			let fgWidth = barWidth * healthPct;
			let fgStartX = pos.X - halfWidth;  // Start from left edge

			// Color: green when healthy, yellow at 50%, red when low
			uint8 r = (uint8)(255 * (1.0f - healthPct));
			uint8 g = (uint8)(255 * healthPct);
			let fgColor = Color(r, g, 0, 255);

			if (healthPct > 0.01f)
			{
				debugDraw.DrawQuad(
					.(fgStartX, barY + 0.01f, pos.Z - halfHeight * 0.8f),
					.(fgStartX + fgWidth, barY + 0.01f, pos.Z - halfHeight * 0.8f),
					.(fgStartX + fgWidth, barY + 0.01f, pos.Z + halfHeight * 0.8f),
					.(fgStartX, barY + 0.01f, pos.Z + halfHeight * 0.8f),
					fgColor, .Overlay);
			}
		}
	}

	/// Draws range indicator circle for selected tower or tower being placed.
	private void DrawTowerRangeIndicator(DebugDrawService debugDraw)
	{
		Vector3 center = .Zero;
		float range = 0;
		Color color = .(100, 200, 255, 180);  // Light blue

		// Check if placing a tower
		if (mSelectedTowerType > 0 && mTowerPreview != null && mPreviewMeshComp?.Visible == true)
		{
			center = mTowerPreview.Transform.WorldPosition;
			let def = GetTowerDefinitionByIndex(mSelectedTowerType);
			range = def.Range;
			color = mPreviewValid ? Color(100, 255, 100, 150) : Color(255, 100, 100, 150);
		}
		// Check if a placed tower is selected
		else if (mSelectedPlacedTower != null)
		{
			let towerComp = mSelectedPlacedTower.GetComponent<TowerComponent>();
			if (towerComp != null)
			{
				center = mSelectedPlacedTower.Transform.WorldPosition;
				range = towerComp.GetRange();
			}
		}

		// Draw range circle if we have a valid range
		if (range > 0)
		{
			DrawCircleXZ(debugDraw, center, range, color, 32);
		}
	}

	/// Draws a circle on the XZ plane (ground).
	private void DrawCircleXZ(DebugDrawService debugDraw, Vector3 center, float radius, Color color, int segments)
	{
		float angleStep = Math.PI_f * 2.0f / segments;
		float y = center.Y + 0.05f;  // Slightly above ground to avoid z-fighting

		for (int i = 0; i < segments; i++)
		{
			float a0 = i * angleStep;
			float a1 = (i + 1) * angleStep;
			Vector3 p0 = .(center.X + Math.Cos(a0) * radius, y, center.Z + Math.Sin(a0) * radius);
			Vector3 p1 = .(center.X + Math.Cos(a1) * radius, y, center.Z + Math.Sin(a1) * radius);
			debugDraw.DrawLine(p0, p1, color, .Overlay);
		}
	}

	// Wave event handlers
	private void OnWaveStarted(int32 waveNumber)
	{
		Console.WriteLine($"\n=== WAVE {waveNumber}/{mWaveSpawner.TotalWaves} ===");
		mGameAudio?.PlayWaveStart();
		UpdateHUD();
	}

	private void OnWaveCompleted(int32 waveNumber, int32 bonusReward)
	{
		mMoney += bonusReward;
		Console.WriteLine($"Wave {waveNumber} complete! Bonus: +${bonusReward} (Total: ${mMoney})");
		mGameAudio?.PlayWaveComplete();

		// Check if more waves remain
		if (waveNumber < mWaveSpawner.TotalWaves)
		{
			mGameState = .WavePaused;
			Console.WriteLine($"Press SPACE for Wave {waveNumber + 1}!");
		}
		UpdateHUD();
	}

	private void OnAllWavesCompleted()
	{
		mGameState = .Victory;
		Console.WriteLine("\n=== VICTORY! ===");
		Console.WriteLine($"Final Score: Kills={mEnemiesKilled}, Money=${mMoney}");
		Console.WriteLine("Press R to play again!");

		mGameAudio?.StopMusic();
		mGameAudio?.PlayVictory();
		mGameHUD?.ShowVictory(mMoney, mEnemiesKilled);
		UpdateHUD();
	}

	private void OnSpawnEnemyRequest(EnemyPreset preset)
	{
		// Convert preset to definition and spawn
		EnemyDefinition def;
		switch (preset)
		{
		case .BasicTank: def = .BasicTank;
		case .FastTank: def = .FastTank;
		case .ArmoredTank: def = .ArmoredTank;
		case .Helicopter: def = .Helicopter;
		case .BossTank: def = .BossTank;
		}
		mEnemyFactory.SpawnEnemy(def);
	}

	private void OnEnemyReachedExit(EnemyComponent enemy)
	{
		// Notify wave spawner
		mWaveSpawner.OnEnemyRemoved();

		mLives -= enemy.Definition.Damage;
		Console.WriteLine($"Enemy reached exit! Lives: {mLives}");
		mGameAudio?.PlayEnemyExit();

		if (mLives <= 0)
		{
			mGameState = .GameOver;
			Console.WriteLine("\n=== GAME OVER ===");
			Console.WriteLine($"You survived {mWaveSpawner.CurrentWaveNumber - 1} waves. Kills: {mEnemiesKilled}");
			Console.WriteLine("Press R to try again!");

			mGameAudio?.StopMusic();
			mGameAudio?.PlayGameOver();
			mGameHUD?.ShowGameOver(mWaveSpawner.CurrentWaveNumber - 1, mEnemiesKilled);
		}
		UpdateHUD();
	}

	private void OnEnemyKilled(Entity enemy, int32 reward)
	{
		// Notify wave spawner
		mWaveSpawner.OnEnemyRemoved();

		mMoney += reward;
		mEnemiesKilled++;
		Console.WriteLine($"Enemy killed! +${reward} (Total: ${mMoney}, Kills: {mEnemiesKilled})");
		UpdateHUD();
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		mCurrentFrameIndex = frameIndex;

		// Begin render graph frame
		mRendererService.BeginFrame(
			(uint32)frameIndex, DeltaTime, TotalTime,
			SwapChain.CurrentTexture, SwapChain.CurrentTextureView,
			mDepthTexture, DepthTextureView);

		// Add UI pass
		mUISceneComponent?.AddUIPass(mRendererService.RenderGraph, mRendererService.SwapChainHandle, frameIndex);
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

		// Clean up preview materials
		let materialSystem = mRendererService?.MaterialSystem;
		if (materialSystem != null)
		{
			if (mPreviewValidMaterial.IsValid)
				materialSystem.ReleaseInstance(mPreviewValidMaterial);
			if (mPreviewInvalidMaterial.IsValid)
				materialSystem.ReleaseInstance(mPreviewInvalidMaterial);
			if (mPreviewBaseMaterial.IsValid)
				materialSystem.ReleaseMaterial(mPreviewBaseMaterial);
		}
		mPreviewBaseMaterial = .Invalid;
		mPreviewValidMaterial = .Invalid;
		mPreviewInvalidMaterial = .Invalid;

		// Clean up game objects BEFORE context shutdown (while scene is still valid)
		// This allows entity components to properly clean up render proxies etc.
		mTowerFactory?.Cleanup();
		mEnemyFactory?.Cleanup();
		mMapBuilder?.Cleanup();

		// Clear UI root element before deleting UI objects
		if (mUISceneComponent != null)
			mUISceneComponent.RootElement = null;

		// Delete UI objects before context shutdown
		DeleteAndNullify!(mMainMenu);
		DeleteAndNullify!(mLevelSelect);
		DeleteAndNullify!(mGameHUD);

		// Wait for GPU before destroying renderer resources
		Device.WaitIdle();

		// Delete GPU resources (must be done while device is still valid)
		delete mAtlasTextureView;
		delete mAtlasTexture;

		// Shutdown context (destroys scenes)
		mContext?.Shutdown();

		// Delete services (in reverse order of creation)
		delete mInputService;
		delete mUIService;
		delete mAudioService;
		delete mDebugDrawService;
		delete mRendererService;

		// Audio system is owned by AudioService if takeOwnership=true (default)
		// But we created it ourselves, so if AudioService didn't take it, clean up
		if (mAudioSystem != null && mAudioService == null)
			delete mAudioSystem;

		Console.WriteLine("Cleanup complete");
	}
}

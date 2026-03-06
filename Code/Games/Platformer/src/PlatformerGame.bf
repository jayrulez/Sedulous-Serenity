namespace Platformer;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using Sedulous.Fonts;
using Sedulous.Drawing.Fonts;
using Sedulous.GUI;
using Sedulous.Physics.Jolt;
using Sedulous.Core.Logging.Abstractions;
using Sedulous.Core.Logging.Console;
using Sedulous.Runtime.Client;
using Sedulous.Runtime;
using Sedulous.Engine.Scenes;
using Sedulous.Engine.Render;
using Sedulous.Engine.Animation;
using Sedulous.Engine.Physics;
using Sedulous.Engine.Input;
using Sedulous.Engine.UI;

using Platformer.Data;
using Platformer.Assets;
using Platformer.Levels;
using Platformer.Components;
using Platformer.Player;
using Platformer.Enemies;
using Platformer.Effects;
using Platformer.UI;

using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Resources;

class PlatformerGame : Application
{
	// Logging
	private ILogger mLogger ~ delete _;

	// Render system
	private RenderSystem mRenderSystem;
	private RenderView mRenderView;
	private GPUSkinningFeature mSkinningFeature;
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private ForwardTransparentFeature mTransparentFeature;
	private ParticleFeature mParticleFeature;
	private OverlayRenderFeature mOverlayFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Subsystems
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private InputSubsystem mInputSubsystem;
	private UISubsystem mUISubsystem;

	// Scene
	private Scene mScene;
	private EntityId mCameraEntity = .Invalid;
	private EntityId mSunEntity = .Invalid;

	// Game systems
	private AssetLoader mAssetLoader ~ delete _;
	private LevelBuilder mLevelBuilder ~ delete _;
	private PlayerController mPlayerController ~ delete _;
	private EnemyBehavior mEnemyBehavior ~ delete _;
	private EnemyFactory mEnemyFactory ~ delete _;
	private ParticleEffects mParticleEffects ~ delete _;

	// Level data
	private LevelDefinition mCurrentLevel ~ delete _;
	private int32 mCurrentLevelIndex = 0;
	private int32 mUnlockedLevels = 1;

	// UI
	private FontService mFontService;
	private Platformer.UI.GameTheme mGameTheme;
	private MainMenu mMainMenu;
	private CharacterSelect mCharacterSelect ~ delete _;
	private LevelSelect mLevelSelect ~ delete _;
	private GameHUD mGameHUD;

	// Selected character
	private CharacterType mSelectedCharacter = .Oopi;

	// Input actions
	private InputAction mMoveAction;
	private InputAction mJumpAction;
	private InputAction mPauseAction;

	// Game state
	private GameState mGameState = .MainMenu;
	private float mDeltaTime;

	// Jump input buffering
	private bool mJumpBuffered = false;

	// Animation state
	private AnimationSceneModule mAnimModule;
	private AnimationClip mAnimClipIdle;
	private AnimationClip mAnimClipRun;
	private AnimationClip mAnimClipJump;
	private AnimationClip mAnimClipDeath;
	private ResourceHandle<AnimationClipResource>[4] mAnimClipHandles; // Keep refs alive
	private int32 mPlayerAnimState = -1; // 0=Idle, 1=Run, 2=Jump, 3=Death

	// Placeholder model toggle: true = use colored cubes, false = use real GLTF models
	private const bool USE_PLACEHOLDER_MODELS = false;

	// Camera
	private float mCameraX;
	private float mCameraY;
	private const float CAMERA_DISTANCE = 18.0f;
	private const float CAMERA_SMOOTH = 5.0f;
	private const float CAMERA_Y_OFFSET = 3.0f;

	// Fly-through debug camera (toggle with F)
	private OrbitFlyCamera mFlyCamera ~ delete _;
	private bool mFlyCameraActive = false;

	public this(IShell shell, IDevice device, IBackend backend) : base(shell, device, backend)
	{
		mLogger = new ConsoleLogger(.Debug, "Platformer");
	}

	// =================================================================
	// Initialization
	// =================================================================

	protected override void OnInitialize(Context context)
	{
		mLogger.LogInformation("=== Initializing ===");
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();
		mLogger.LogInformation("SDLImageLoader initialized");

		FixedTimeStep = 1.0f / 60.0f;
		MaxFixedStepsPerFrame = 3;
		mLogger.LogInformation("FixedTimeStep={}, MaxFixedStepsPerFrame={}", FixedTimeStep, MaxFixedStepsPerFrame);

		InitializeRenderSystem();
		RegisterSubsystems(context);
		mLogger.LogInformation("=== Initialization complete ===");
	}

	private void InitializeRenderSystem()
	{
		mLogger.LogInformation("Initializing RenderSystem...");
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), null,
			.BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			mLogger.LogError("Failed to initialize RenderSystem! Rendering will not work.");
			return;
		}
		mLogger.LogInformation("RenderSystem initialized successfully");

		mRenderView = new RenderView();
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.FieldOfView = Math.PI_f / 4.0f;
		mRenderView.NearPlane = 0.1f;
		mRenderView.FarPlane = 200.0f;
		mLogger.LogInformation("RenderView: {}x{}, Near={}, Far={}", mRenderView.Width, mRenderView.Height, mRenderView.NearPlane, mRenderView.FarPlane);

		// Register render features (order matters)
		mSkinningFeature = new GPUSkinningFeature();
		mRenderSystem.RegisterFeature(mSkinningFeature);

		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mTransparentFeature = new ForwardTransparentFeature();
		mRenderSystem.RegisterFeature(mTransparentFeature);

		mParticleFeature = new ParticleFeature();
		mRenderSystem.RegisterFeature(mParticleFeature);

		mOverlayFeature = new OverlayRenderFeature();
		mRenderSystem.RegisterFeature(mOverlayFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);

		mLogger.LogInformation("Registered 7 render features (GPUSkinning, DepthPrepass, ForwardOpaque, ForwardTransparent, Particle, DebugRender, FinalOutput)");
	}

	private void RegisterSubsystems(Context context)
	{
		mLogger.LogInformation("Registering subsystems...");

		// Scene
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);
		mLogger.LogDebug("SceneSubsystem registered");

		// Animation (for skinned character and enemies)
		let animSubsystem = new AnimationSubsystem();
		context.RegisterSubsystem(animSubsystem);
		mLogger.LogDebug("AnimationSubsystem registered");

		// Physics
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
		mLogger.LogDebug("PhysicsSubsystem registered (Jolt)");

		// Render
		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);
		mLogger.LogDebug("RenderSubsystem registered");

		// Input
		mInputSubsystem = new InputSubsystem();
		mInputSubsystem.SetInputManager(mShell.InputManager);
		context.RegisterSubsystem(mInputSubsystem);
		mLogger.LogDebug("InputSubsystem registered");

		mLogger.LogInformation("All subsystems registered");
	}

	protected override void OnContextStarted()
	{
		mLogger.LogInformation("=== Context started, setting up game ===");
		InitializeUI();
		ImportAssets();
		CreateScene();
		SetupInputActions();
		mGameState = .MainMenu;
		mLogger.LogInformation("=== Game setup complete, showing main menu ===");
	}

	// =================================================================
	// UI Setup
	// =================================================================

	private void InitializeUI()
	{
		mLogger.LogInformation("Initializing UI...");
		mFontService = new FontService();
		let fontPath = scope String();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);
		mLogger.LogDebug("Font path: {}", fontPath);

		int32[6] fontSizes = .(14, 16, 18, 20, 24, 32);
		int32 fontsLoaded = 0;
		for (let size in fontSizes)
		{
			FontLoadOptions options = .ExtendedLatin;
			options.PixelHeight = size;
			if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
				mLogger.LogWarning("Failed to load font 'Roboto' at size {}", size);
			else
				fontsLoaded++;
		}
		mLogger.LogInformation("Loaded {}/{} font sizes", fontsLoaded, fontSizes.Count);

		mUISubsystem = new UISubsystem(mFontService);
		mContext.RegisterSubsystem(mUISubsystem);

		if (mUISubsystem.InitializeRendering(mDevice, .BGRA8UnormSrgb, FrameConfig.MAX_FRAMES_IN_FLIGHT, mShell, mWindow, mRenderSystem) case .Err)
		{
			mLogger.LogError("Failed to initialize UI rendering! UI will not display.");
			return;
		}

		// Theme
		mGameTheme = new Platformer.UI.GameTheme();
		mUISubsystem.GUIContext.Theme = mGameTheme;
		mLogger.LogDebug("GameTheme applied");

		// Create UI screens
		mMainMenu = new MainMenu();
		mCharacterSelect = new CharacterSelect();
		mLevelSelect = new LevelSelect();
		mGameHUD = new GameHUD();

		// Wire up events
		mMainMenu.OnPlay.Subscribe(new => OnPlayClicked);
		mMainMenu.OnQuit.Subscribe(new => OnQuitClicked);
		mCharacterSelect.OnCharacterSelected.Subscribe(new => OnCharacterSelected);
		mCharacterSelect.OnBack.Subscribe(new => OnBackToMenu);
		mLevelSelect.OnLevelSelected.Subscribe(new => OnLevelSelected);
		mLevelSelect.OnBack.Subscribe(new => OnBackToCharacterSelect);
		mGameHUD.OnResume.Subscribe(new => OnResumeClicked);
		mGameHUD.OnRestart.Subscribe(new => OnRestartClicked);
		mGameHUD.OnMainMenu.Subscribe(new => OnBackToMenu);
		mGameHUD.OnNextLevel.Subscribe(new => OnNextLevelClicked);

		// Show main menu
		ShowScreen(mMainMenu.RootElement);
		mLogger.LogInformation("UI initialization complete");
	}

	private void ShowScreen(UIElement root)
	{
		if (mUISubsystem == null)
		{
			mLogger.LogWarning("ShowScreen called but UISubsystem is null");
			return;
		}
		mUISubsystem.GUIContext.RootElement = root;
	}

	// =================================================================
	// Assets
	// =================================================================

	private void ImportAssets()
	{
		mLogger.LogInformation("Importing assets...");
		mLogger.LogDebug("AssetDirectory: {}", AssetDirectory);
		mLogger.LogDebug("AssetCacheDirectory: {}", AssetCacheDirectory);
		mAssetLoader = new AssetLoader(mLogger);
		mAssetLoader.Initialize(AssetDirectory, AssetCacheDirectory);
		if (USE_PLACEHOLDER_MODELS)
		{
			mLogger.LogInformation("Using PLACEHOLDER models (colored cubes)");
			mAssetLoader.ImportPlaceholderModels(mContext);
		}
		else
		{
			mAssetLoader.ImportAssets(mContext);
		}
		mLogger.LogInformation("Asset import complete");
	}

	// =================================================================
	// Scene Setup
	// =================================================================

	private void CreateScene()
	{
		mLogger.LogInformation("Creating scene...");
		mScene = mSceneSubsystem.CreateScene("PlatformerScene");
		mSceneSubsystem.SetActiveScene(mScene);

		let renderModule = mScene.GetModule<RenderSceneModule>();
		if (renderModule == null)
		{
			mLogger.LogError("No RenderSceneModule found in scene! 3D rendering will not work.");
			return;
		}

		// Ambient lighting (set on the RenderWorld)
		if (renderModule.World != null)
		{
			renderModule.World.AmbientColor = .(0.04f, 0.05f, 0.08f);
			renderModule.World.AmbientIntensity = 0.5f;
			renderModule.World.Exposure = 1.0f;
			mLogger.LogDebug("Ambient lighting configured (intensity=0.5, exposure=1.0)");
		}
		else
		{
			mLogger.LogWarning("RenderWorld is null, cannot set ambient lighting");
		}

		// Camera - side-scrolling perspective
		mCameraEntity = mScene.CreateEntity();
		mScene.SetName(mCameraEntity, "Camera");
		renderModule.CreatePerspectiveCamera(mCameraEntity,
			Math.PI_f / 4.0f,
			(float)mSwapChain.Width / (float)mSwapChain.Height,
			0.1f,
			200.0f);
		renderModule.SetMainCamera(mCameraEntity);

		// Position camera initially
		mCameraX = 5.0f;
		mCameraY = 6.0f;
		UpdateCameraTransform();

		// Directional light (sun)
		mSunEntity = mScene.CreateEntity();
		mScene.SetName(mSunEntity, "Sun");
		renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.95f, 0.85f), 1.5f);
		var sunTransform = mScene.GetTransform(mSunEntity);
		let lightDir = Vector3.Normalize(.(-0.3f, -1.0f, -0.5f));
		sunTransform.Rotation = Quaternion.CreateFromAxisAngle(
			Vector3.Cross(.(0, -1, 0), lightDir),
			Math.Acos(Math.Clamp(Vector3.Dot(.(0, -1, 0), lightDir), -1.0f, 1.0f)));
		mScene.SetTransform(mSunEntity, sunTransform);

		// Create game systems that need the scene
		let physicsModule = mScene.GetModule<PhysicsSceneModule>();
		if (physicsModule == null)
			mLogger.LogWarning("No PhysicsSceneModule found, physics will be disabled");
		else
			physicsModule.DebugDrawEnabled = true;

		mLevelBuilder = new LevelBuilder(mScene, renderModule, physicsModule, mAssetLoader, mLogger);
		mPlayerController = new PlayerController(mScene, physicsModule, mLogger);
		mEnemyBehavior = new EnemyBehavior(mScene);
		mEnemyFactory = new EnemyFactory(mScene, mLogger);

		if (renderModule.World != null)
		{
			mParticleEffects = new ParticleEffects(renderModule.World, mLogger);
		}
		else
		{
			mLogger.LogWarning("RenderWorld is null, particle effects disabled");
		}

		mLogger.LogInformation("Scene creation complete");
	}

	// =================================================================
	// Input
	// =================================================================

	private void SetupInputActions()
	{
		mLogger.LogInformation("Setting up input actions...");
		let gameCtx = mInputSubsystem.CreateContext("Game", 0);

		// Movement (WASD/Arrows + Left stick)
		mMoveAction = gameCtx.RegisterAction("Move");
		mMoveAction.AddBinding(new CompositeBinding(.W, .S, .A, .D));
		mMoveAction.AddBinding(new CompositeBinding(.Up, .Down, .Left, .Right));
		mMoveAction.AddBinding(new GamepadStickBinding(.Left, 0, 0.15f));

		// Jump (Space + Gamepad South)
		mJumpAction = gameCtx.RegisterAction("Jump");
		mJumpAction.AddBinding(new KeyBinding(.Space));
		mJumpAction.AddBinding(new GamepadButtonBinding(.South, 0));

		// Pause (Escape + Gamepad Start)
		mPauseAction = gameCtx.RegisterAction("Pause");
		mPauseAction.AddBinding(new KeyBinding(.Escape));
		mPauseAction.AddBinding(new GamepadButtonBinding(.Start, 0));

		mLogger.LogInformation("Registered 3 input actions (Move, Jump, Pause) with keyboard/gamepad bindings");
	}

	// =================================================================
	// Game Loop
	// =================================================================

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;

		// Toggle fly-through debug camera with F
		if (keyboard.IsKeyPressed(.F))
		{
			mFlyCameraActive = !mFlyCameraActive;
			if (mFlyCameraActive)
			{
				if (mFlyCamera == null)
				{
					mFlyCamera = new OrbitFlyCamera();
					mFlyCamera.MoveSpeed = 10.0f;
					mFlyCamera.CurrentMode = .Flythrough;
				}
				// Initialize from current game camera
				mFlyCamera.FlyPosition = .(mCameraX, mCameraY, CAMERA_DISTANCE);
				mFlyCamera.FlyYaw = Math.PI_f; // Looking along -Z
				mFlyCamera.FlyPitch = 0;
				mFlyCamera.Update();
				mLogger.LogInformation("Fly camera enabled (WASD move, right-click look, Shift sprint, Q/E up/down)");
			}
			else
			{
				// Release mouse capture if active
				if (mFlyCamera.MouseCaptured)
				{
					let mouse = mShell.InputManager.Mouse;
					mFlyCamera.MouseCaptured = false;
					mouse.RelativeMode = false;
					mouse.Visible = true;
				}
				mLogger.LogInformation("Fly camera disabled");
			}
		}

		// Feed input to fly camera when active
		if (mFlyCameraActive && mFlyCamera != null)
		{
			mFlyCamera.HandleInput(keyboard, mShell.InputManager.Mouse, mDeltaTime);
			return; // Don't process game input while flying
		}

		// Character select navigation (arrow keys + enter)
		if (mGameState == .CharacterSelect)
		{
			mCharacterSelect.HandleInput(
				keyboard.IsKeyPressed(.Left) || keyboard.IsKeyPressed(.A),
				keyboard.IsKeyPressed(.Right) || keyboard.IsKeyPressed(.D),
				keyboard.IsKeyPressed(.Return) || keyboard.IsKeyPressed(.Space));
		}

		// Buffer jump input so it's not lost between frames that skip FixedUpdate
		if (mJumpAction.WasPressed)
			mJumpBuffered = true;

		// Pause toggle
		if (mPauseAction.WasPressed)
		{
			if (mGameState == .Playing)
			{
				mLogger.LogInformation("Game paused");
				mGameState = .Paused;
				mGameHUD.ShowPause();
			}
			else if (mGameState == .Paused)
			{
				OnResumeClicked();
			}
		}
	}

	protected override void OnFixedUpdate(float fixedDt)
	{
		if (mGameState != .Playing)
			return;

		let playerEntity = mLevelBuilder.PlayerEntity;
		if (playerEntity == .Invalid || mCurrentLevel == null)
			return;

		// Update moving platforms first (so collision check uses current positions)
		UpdateMovingPlatforms(fixedDt);

		// Update moving hazards
		UpdateMovingHazards(fixedDt);

		// Feed input to player controller (suppress when fly camera active)
		if (mFlyCameraActive)
		{
			mPlayerController.MoveInput = 0;
			mPlayerController.JumpPressed = false;
			mPlayerController.JumpHeld = false;
		}
		else
		{
			mPlayerController.MoveInput = mMoveAction.Vector2Value.X;
			mPlayerController.JumpPressed = mJumpBuffered;
			mPlayerController.JumpHeld = mJumpAction.IsActive;
		}
		mJumpBuffered = false; // Consumed by this fixed update

		// Update player physics (tile-based collision)
		mPlayerController.FixedUpdate(playerEntity, fixedDt, mCurrentLevel);

		// Check if player is standing on a moving platform
		CheckMovingPlatformCollisions(playerEntity);

		// Update enemies
		let playerTransform = mScene.GetTransform(playerEntity);
		let playerPos = playerTransform.Position;
		mEnemyBehavior.Update(mLevelBuilder.EnemyEntities, fixedDt, playerPos);

		// Update pickup bobbing
		UpdatePickups(fixedDt);

		// Check player-enemy collisions
		CheckEnemyCollisions(playerEntity, playerPos);

		// Check player-pickup collisions
		CheckPickupCollisions(playerEntity, playerPos);

		// Check player-hazard collisions
		CheckHazardCollisions(playerEntity, playerPos);

		// Check goal reached
		CheckGoalReached(playerEntity, playerPos);

		// Check player death
		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player != null && !player.Alive)
		{
			mLogger.LogInformation("Player died (health={})", player.Health);
			mGameState = .GameOver;
			mGameHUD.ShowGameOver();
		}

		// Update player animation based on state
		if (player != null)
			UpdatePlayerAnimation(playerEntity, player);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = frame.DeltaTime;

		if (mGameState == .Playing)
		{
			// Smooth camera follow
			let playerEntity = mLevelBuilder.PlayerEntity;
			if (playerEntity != .Invalid)
			{
				let playerPos = mScene.GetTransform(playerEntity).Position;
				mCameraX += (playerPos.X - mCameraX) * CAMERA_SMOOTH * mDeltaTime;
				mCameraY += (playerPos.Y + CAMERA_Y_OFFSET - mCameraY) * CAMERA_SMOOTH * mDeltaTime;

				// Clamp camera to level bounds
				if (mCurrentLevel != null)
				{
					float levelWidth = mCurrentLevel.Width * mCurrentLevel.TileSize;
					float levelHeight = mCurrentLevel.Height * mCurrentLevel.TileSize;
					mCameraX = Math.Clamp(mCameraX, 8.0f, Math.Max(8.0f, levelWidth - 8.0f));
					mCameraY = Math.Clamp(mCameraY, 4.0f, Math.Max(4.0f, levelHeight));
				}
			}

			UpdateCameraTransform();

			// Update HUD
			if (playerEntity != .Invalid)
			{
				var player = mScene.GetComponent<PlayerComponent>(playerEntity);
				if (player != null)
				{
					mGameHUD.SetHealth(player.Health);
					mGameHUD.SetCoins(player.Coins);
					mGameHUD.SetKeys(player.Keys);
				}
			}

			mGameHUD.UpdateLevelNameFade(mDeltaTime);
			mParticleEffects?.Update(mDeltaTime);
		}
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame(render.Frame.TotalTime, render.Frame.DeltaTime);

		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		// Set active render world from scene
		if (let renderModule = mScene?.GetModule<RenderSceneModule>())
			if (let world = renderModule.World)
				mRenderSystem.SetActiveWorld(world);

		// Update camera in render view
		Vector3 camPos;
		Vector3 camForward;
		if (mFlyCameraActive && mFlyCamera != null)
		{
			camPos = mFlyCamera.Position;
			camForward = mFlyCamera.Forward;
		}
		else
		{
			camPos = mScene.GetTransform(mCameraEntity).Position;
			camForward = .(0, 0, -1);
		}
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
		else
			mLogger.LogWarning("BuildRenderGraph failed this frame");

		mRenderSystem.EndFrame();

		// Render UI overlay
		if (mUISubsystem != null)
		{
			mUISubsystem.RenderUI(render.Encoder, render.SwapChain.CurrentTextureView,
				mSwapChain.Width, mSwapChain.Height, render.Frame.FrameIndex);
		}

		return true;
	}

	// =================================================================
	// Camera
	// =================================================================

	private void UpdateCameraTransform()
	{
		if (mCameraEntity == .Invalid || mScene == null)
			return;

		var transform = mScene.GetTransform(mCameraEntity);
		transform.Position = .(mCameraX, mCameraY, CAMERA_DISTANCE);
		// Camera looks along -Z (toward the play area at Z=0)
		transform.Rotation = Quaternion.Identity;
		mScene.SetTransform(mCameraEntity, transform);
	}

	// =================================================================
	// Game Logic Helpers
	// =================================================================

	private void UpdateMovingPlatforms(float dt)
	{
		for (let entity in mLevelBuilder.MovingPlatformEntities)
		{
			var platform = mScene.GetComponent<MovingPlatformComponent>(entity);
			if (platform == null) continue;

			// Store position before moving
			platform.PreviousPosition = platform.CurrentPosition;

			platform.T += platform.Direction * platform.Speed * dt / Vector3.Distance(platform.PointA, platform.PointB);
			if (platform.T >= 1.0f)
			{
				platform.T = 1.0f;
				platform.Direction = -1.0f;
			}
			else if (platform.T <= 0.0f)
			{
				platform.T = 0.0f;
				platform.Direction = 1.0f;
			}

			var transform = mScene.GetTransform(entity);
			transform.Position = platform.CurrentPosition;
			mScene.SetTransform(entity, transform);
			mScene.SetComponent<MovingPlatformComponent>(entity, *platform);
		}
	}

	private void CheckMovingPlatformCollisions(EntityId playerEntity)
	{
		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player == null || !player.Alive)
			return;

		var playerTransform = mScene.GetTransform(playerEntity);
		var playerPos = playerTransform.Position;
		// Center-origin: entity position = character center
		float playerHalfW = PlayerController.CHARACTER_HALF_WIDTH;
		float playerHalfH = PlayerController.CHARACTER_HALF_HEIGHT;
		float playerFootY = playerPos.Y - playerHalfH;

		for (let entity in mLevelBuilder.MovingPlatformEntities)
		{
			var platform = mScene.GetComponent<MovingPlatformComponent>(entity);
			if (platform == null) continue;

			let platPos = platform.CurrentPosition;
			float platHalfW = platform.HalfExtents.X;
			float platHalfH = platform.HalfExtents.Y;
			float platTop = platPos.Y + platHalfH;
			float platBottom = platPos.Y - platHalfH;

			// Check horizontal overlap
			float dx = Math.Abs(playerPos.X - platPos.X);
			if (dx >= platHalfW + playerHalfW - 0.05f)
				continue;

			// Check if player feet are near platform top (landing on it)
			if (playerFootY >= platBottom && playerFootY <= platTop + 0.15f && player.Velocity.Y <= 0.1f)
			{
				// Snap player center so feet are at platform top
				playerPos.Y = platTop + playerHalfH;
				player.Velocity.Y = 0;
				player.Grounded = true;

				// Carry player with platform movement
				let platDelta = platform.CurrentPosition - platform.PreviousPosition;
				playerPos.X += platDelta.X;
				playerPos.Y += platDelta.Y;

				playerTransform.Position = playerPos;
				mScene.SetTransform(playerEntity, playerTransform);
				mScene.SetComponent<PlayerComponent>(playerEntity, *player);
				return; // Only stand on one platform
			}
		}
	}

	private void UpdateMovingHazards(float dt)
	{
		for (let entity in mLevelBuilder.HazardEntities)
		{
			var hazard = mScene.GetComponent<HazardComponent>(entity);
			if (hazard == null || !hazard.Active || hazard.Speed <= 0)
				continue;

			// Only move hazards that have different start/end positions
			if (Vector3.Distance(hazard.StartPos, hazard.EndPos) < 0.1f)
				continue;

			hazard.Timer += hazard.Direction * hazard.Speed * dt / Vector3.Distance(hazard.StartPos, hazard.EndPos);
			if (hazard.Timer >= 1.0f) { hazard.Timer = 1.0f; hazard.Direction = -1.0f; }
			else if (hazard.Timer <= 0.0f) { hazard.Timer = 0.0f; hazard.Direction = 1.0f; }

			var transform = mScene.GetTransform(entity);
			transform.Position = Vector3.Lerp(hazard.StartPos, hazard.EndPos, hazard.Timer);
			// Rotate saws
			if (hazard.Type == .Saw)
				transform.Rotation = Quaternion.CreateFromAxisAngle(.(0, 0, 1), hazard.Timer * Math.PI_f * 8.0f);
			mScene.SetTransform(entity, transform);
			mScene.SetComponent<HazardComponent>(entity, *hazard);
		}
	}

	private void UpdatePickups(float dt)
	{
		for (let entity in mLevelBuilder.PickupEntities)
		{
			var pickup = mScene.GetComponent<PickupComponent>(entity);
			if (pickup == null || pickup.Collected)
				continue;

			pickup.BobPhase += dt * 3.0f;
			var transform = mScene.GetTransform(entity);
			transform.Position.Y += Math.Sin(pickup.BobPhase) * 0.003f; // Gentle bobbing
			// Slow rotation
			transform.Rotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), pickup.BobPhase * 0.5f);
			mScene.SetTransform(entity, transform);
			mScene.SetComponent<PickupComponent>(entity, *pickup);
		}
	}

	private void CheckEnemyCollisions(EntityId playerEntity, Vector3 playerPos)
	{
		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player == null || !player.Alive)
			return;

		for (let entity in mLevelBuilder.EnemyEntities)
		{
			var enemy = mScene.GetComponent<EnemyComponent>(entity);
			if (enemy == null || !enemy.Alive)
				continue;

			let enemyPos = mScene.GetTransform(entity).Position;

			if (EnemyBehavior.IsStompingEnemy(playerPos, player.Velocity, enemyPos, enemy.Type))
			{
				// Stomp the enemy
				mLogger.LogInformation("Enemy stomped (type={})", enemy.Type);
				mEnemyFactory.KillEnemy(entity);
				mPlayerController.ApplyBounce(playerEntity, PlayerController.STOMP_BOUNCE);
				mParticleEffects?.SpawnEnemyDeath(enemyPos);
			}
			else if (EnemyBehavior.IsTouchingEnemy(playerPos, enemyPos))
			{
				// Player takes damage
				mLogger.LogInformation("Player hit by enemy (type={})", enemy.Type);
				mPlayerController.TakeDamage(playerEntity, 1);
			}
		}
	}

	private void CheckPickupCollisions(EntityId playerEntity, Vector3 playerPos)
	{
		for (let entity in mLevelBuilder.PickupEntities)
		{
			var pickup = mScene.GetComponent<PickupComponent>(entity);
			if (pickup == null || pickup.Collected)
				continue;

			let pickupPos = mScene.GetTransform(entity).Position;
			float dx = Math.Abs(playerPos.X - pickupPos.X);
			float dy = Math.Abs(playerPos.Y - pickupPos.Y);

			if (dx < 0.6f && dy < 0.6f)
			{
				pickup.Collected = true;
				mScene.SetComponent<PickupComponent>(entity, *pickup);

				// Hide pickup
				var transform = mScene.GetTransform(entity);
				transform.Position.Y = -100;
				mScene.SetTransform(entity, transform);

				mLogger.LogDebug("Pickup collected (type={}, value={})", pickup.Type, pickup.Value);
				mPlayerController.CollectPickup(playerEntity, pickup.Type, pickup.Value);
				mParticleEffects?.SpawnCoinCollect(pickupPos);
			}
		}
	}

	private void CheckHazardCollisions(EntityId playerEntity, Vector3 playerPos)
	{
		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player == null || !player.Alive || player.InvincibleTimer > 0)
			return;

		for (let entity in mLevelBuilder.HazardEntities)
		{
			var hazard = mScene.GetComponent<HazardComponent>(entity);
			if (hazard == null || !hazard.Active)
				continue;

			let hazardPos = mScene.GetTransform(entity).Position;
			float dx = Math.Abs(playerPos.X - hazardPos.X);
			float dy = Math.Abs(playerPos.Y - hazardPos.Y);

			if (dx < 0.5f && dy < 0.5f)
			{
				if (hazard.Damage > 0)
				{
					mLogger.LogInformation("Player hit by hazard (type={}, damage={})", hazard.Type, hazard.Damage);
					mPlayerController.TakeDamage(playerEntity, hazard.Damage);
				}
				else
				{
					// Bouncer (damage == 0)
					mLogger.LogDebug("Player hit bouncer");
					mPlayerController.ApplyBounce(playerEntity, PlayerController.BOUNCE_VELOCITY);
					mParticleEffects?.SpawnDust(playerPos);
				}
			}
		}

		// Check door collisions (spend key to open)
		for (let entity in mLevelBuilder.DoorEntities)
		{
			let doorPos = mScene.GetTransform(entity).Position;
			float dx = Math.Abs(playerPos.X - doorPos.X);
			float dy = Math.Abs(playerPos.Y - doorPos.Y);

			if (dx < 0.6f && dy < 0.9f)
			{
				if (mPlayerController.TryOpenDoor(playerEntity))
				{
					mLogger.LogInformation("Door opened with key");
					// Remove the door
					var transform = mScene.GetTransform(entity);
					transform.Position.Y = -100;
					mScene.SetTransform(entity, transform);
				}
			}
		}
	}

	private void CheckGoalReached(EntityId playerEntity, Vector3 playerPos)
	{
		let goalEntity = mLevelBuilder.GoalEntity;
		if (goalEntity == .Invalid)
			return;

		var goalTransform = mScene.GetTransform(goalEntity);
		float gx = goalTransform.Position.X;
		float gy = goalTransform.Position.Y;
		float dx = Math.Abs(playerPos.X - gx);
		float dy = Math.Abs(playerPos.Y - gy);

		if (dx >= 0.8f || dy >= 1.2f)
			return;

		int32 coins = 0;
		var player = mScene.GetComponent<PlayerComponent>(playerEntity);
		if (player != null)
			coins = player.Coins;

		mLogger.LogInformation("Level {} complete! Coins collected: {}", mCurrentLevelIndex + 1, coins);
		mGameState = .LevelComplete;
		mGameHUD.ShowLevelComplete(coins);

		// Unlock next level
		int32 nextLevel = mCurrentLevelIndex + 1;
		if (nextLevel >= mUnlockedLevels && nextLevel < 5)
		{
			mUnlockedLevels = nextLevel + 1;
			mLevelSelect.SetUnlockedLevels(mUnlockedLevels);
			mLogger.LogInformation("Unlocked level {}", mUnlockedLevels);
		}
	}

	// =================================================================
	// Level Management
	// =================================================================

	private void StartLevel(int32 levelIndex)
	{
		mLogger.LogInformation("Starting level {}...", levelIndex + 1);
		mCurrentLevelIndex = levelIndex;

		// Clean up old level
		if (mCurrentLevel != null)
		{
			mLogger.LogDebug("Cleaning up previous level");
			delete mCurrentLevel;
		}

		mCurrentLevel = CreateLevel(levelIndex);
		if (mCurrentLevel == null)
		{
			mLogger.LogError("Failed to create level {}! No level definition returned.", levelIndex + 1);
			return;
		}

		mLogger.LogInformation("Level '{}' ({}x{}), spawn=({},{}), goal=({},{})",
			mCurrentLevel.Name, mCurrentLevel.Width, mCurrentLevel.Height,
			mCurrentLevel.SpawnX, mCurrentLevel.SpawnY, mCurrentLevel.GoalX, mCurrentLevel.GoalY);
		mLogger.LogDebug("Enemies: {}, MovingPlatforms: {}, MovingHazards: {}",
			mCurrentLevel.Enemies.Count, mCurrentLevel.MovingPlatforms.Count, mCurrentLevel.MovingHazards.Count);

		let charDef = CharacterDefinition.Get(mSelectedCharacter);
		mLevelBuilder.BuildLevel(mCurrentLevel, charDef.ModelKey);

		// Apply character skill modifiers
		mPlayerController.ApplyCharacterSkills(mLevelBuilder.PlayerEntity, charDef);

		// Preload player animation clips
		PreloadPlayerAnimations(charDef.ModelKey);

		// Populate pickups, decorations, etc.
		PopulateLevelEntities(levelIndex);

		// Set up camera at spawn
		let spawnPos = mCurrentLevel.GridToWorld(mCurrentLevel.SpawnX, mCurrentLevel.SpawnY);
		mCameraX = spawnPos.X;
		mCameraY = spawnPos.Y + CAMERA_Y_OFFSET;
		UpdateCameraTransform();

		// Reset animation state
		mPlayerAnimState = -1;

		// Show HUD
		mGameState = .Playing;
		ShowScreen(mGameHUD.RootElement);
		mGameHUD.HideOverlays();
		mGameHUD.ShowLevelName(mCurrentLevel.Name);
		mLogger.LogInformation("Level {} '{}' started", levelIndex + 1, mCurrentLevel.Name);
	}

	private LevelDefinition CreateLevel(int32 index)
	{
		switch (index)
		{
		case 0: return Level01_GreenMeadows.Create();
		case 1: return Level02_UndergroundCaves.Create();
		case 2: return Level03_SkyFortress.Create();
		case 3: return Level04_MechanicalFactory.Create();
		case 4: return Level05_FinalChallenge.Create();
		default:
			mLogger.LogError("Invalid level index {} (valid range: 0-4)", index);
			return null;
		}
	}

	private void PopulateLevelEntities(int32 levelIndex)
	{
		if (mCurrentLevel == null) return;

		switch (levelIndex)
		{
		case 0: Level01_GreenMeadows.PopulateEntities(mCurrentLevel, mLevelBuilder);
		case 1: Level02_UndergroundCaves.PopulateEntities(mCurrentLevel, mLevelBuilder);
		case 2: Level03_SkyFortress.PopulateEntities(mCurrentLevel, mLevelBuilder);
		case 3: Level04_MechanicalFactory.PopulateEntities(mCurrentLevel, mLevelBuilder);
		case 4: Level05_FinalChallenge.PopulateEntities(mCurrentLevel, mLevelBuilder);
		}

		mLogger.LogDebug("Populated entities: {} pickups, {} doors, {} hazards, {} moving platforms",
			mLevelBuilder.PickupEntities.Count, mLevelBuilder.DoorEntities.Count,
			mLevelBuilder.HazardEntities.Count, mLevelBuilder.MovingPlatformEntities.Count);
	}

	// =================================================================
	// Animation Management
	// =================================================================

	private void PreloadPlayerAnimations(StringView characterKey = "character_oopi")
	{
		// Release previous handles
		ReleaseAnimClipHandles();

		mAnimModule = mScene.GetModule<AnimationSceneModule>();
		mPlayerAnimState = -1;

		mAnimClipIdle = LoadAnimClip(characterKey, "Idle", 0);
		mAnimClipRun = LoadAnimClip(characterKey, "Run", 1);
		mAnimClipJump = LoadAnimClip(characterKey, "Jump_Idle", 2);
		mAnimClipDeath = LoadAnimClip(characterKey, "Death", 3);

		int32 loaded = (mAnimClipIdle != null ? 1 : 0) + (mAnimClipRun != null ? 1 : 0) +
			(mAnimClipJump != null ? 1 : 0) + (mAnimClipDeath != null ? 1 : 0);
		mLogger.LogInformation("Preloaded {}/4 player animation clips", loaded);
	}

	private AnimationClip LoadAnimClip(StringView meshKey, StringView animName, int32 handleIndex)
	{
		var animRef = ResourceRef();
		if (!mAssetLoader.GetAnimationRefByName(meshKey, animName, out animRef))
		{
			mLogger.LogWarning("Animation ref not found: {}/{}", meshKey, animName);
			return null;
		}

		AnimationClip result = null;
		if (mContext.Resources.LoadByRef<AnimationClipResource>(animRef) case .Ok(let handle))
		{
			mAnimClipHandles[handleIndex] = handle;
			result = handle.Resource?.Clip;
			if (result == null)
				mLogger.LogWarning("Animation clip resource has null clip: {}/{}", meshKey, animName);
		}
		else
		{
			mLogger.LogWarning("Failed to load animation resource: {}/{}", meshKey, animName);
		}

		animRef.Dispose();
		return result;
	}

	private void ReleaseAnimClipHandles()
	{
		for (int32 i = 0; i < 4; i++)
			mAnimClipHandles[i].Release();
		mAnimClipIdle = null;
		mAnimClipRun = null;
		mAnimClipJump = null;
		mAnimClipDeath = null;
	}

	private void UpdatePlayerAnimation(EntityId entity, PlayerComponent* player)
	{
		if (mAnimModule == null) return;

		// Determine desired animation state
		int32 desired;
		if (!player.Alive)
			desired = 3; // Death
		else if (!player.Grounded)
			desired = 2; // Jump
		else if (Math.Abs(player.Velocity.X) > 0.5f)
			desired = 1; // Run
		else
			desired = 0; // Idle

		if (desired == mPlayerAnimState)
			return;

		mPlayerAnimState = desired;
		AnimationClip clip;
		bool loop;
		switch (desired)
		{
		case 1: clip = mAnimClipRun; loop = true;
		case 2: clip = mAnimClipJump; loop = true;
		case 3: clip = mAnimClipDeath; loop = false;
		default: clip = mAnimClipIdle; loop = true;
		}

		if (clip != null)
			mAnimModule.Play(entity, clip, loop);
	}

	// =================================================================
	// UI Event Handlers
	// =================================================================

	private void OnPlayClicked()
	{
		mLogger.LogInformation("Play clicked -> CharacterSelect");
		mGameState = .CharacterSelect;
		ShowScreen(mCharacterSelect.RootElement);
	}

	private void OnCharacterSelected(CharacterType character)
	{
		mSelectedCharacter = character;
		let def = CharacterDefinition.Get(character);
		mLogger.LogInformation("Character selected: {} ({})", def.Name, def.SkillName);
		mGameState = .LevelSelect;
		mLevelSelect.SetUnlockedLevels(mUnlockedLevels);
		ShowScreen(mLevelSelect.RootElement);
	}

	private void OnBackToCharacterSelect()
	{
		mLogger.LogInformation("Back to character select");
		mGameState = .CharacterSelect;
		ShowScreen(mCharacterSelect.RootElement);
	}

	private void OnQuitClicked()
	{
		mLogger.LogInformation("Quit clicked -> Exiting");
		mIsRunning = false;
	}

	private void OnLevelSelected(int32 levelIndex)
	{
		mLogger.LogInformation("Level {} selected", levelIndex + 1);
		StartLevel(levelIndex);
	}

	private void OnBackToMenu()
	{
		mLogger.LogInformation("Back to main menu");
		mGameState = .MainMenu;
		ReleaseAnimClipHandles();
		mLevelBuilder?.ClearLevel();
		ShowScreen(mMainMenu.RootElement);
	}

	private void OnResumeClicked()
	{
		mLogger.LogInformation("Resume -> Playing");
		mGameState = .Playing;
		mGameHUD.HideOverlays();
	}

	private void OnRestartClicked()
	{
		mLogger.LogInformation("Restart level {}", mCurrentLevelIndex + 1);
		StartLevel(mCurrentLevelIndex);
	}

	private void OnNextLevelClicked()
	{
		if (mCurrentLevelIndex < 4)
		{
			mLogger.LogInformation("Next level -> {}", mCurrentLevelIndex + 2);
			StartLevel(mCurrentLevelIndex + 1);
		}
		else
		{
			mLogger.LogInformation("All levels complete, returning to menu");
			OnBackToMenu(); // Last level completed, go to menu
		}
	}

	// =================================================================
	// Shutdown
	// =================================================================

	protected override void OnShutdown()
	{
		mLogger.LogInformation("=== Shutting down ===");

		ReleaseAnimClipHandles();

		mLogger.LogDebug("Deleting FontService...");
		delete mFontService;
		mLogger.LogDebug("Deleting UI screens...");
		delete mGameHUD;
		delete mMainMenu;

		if (mRenderSystem != null)
		{
			mLogger.LogDebug("Shutting down RenderSystem...");
			mRenderSystem.Shutdown();
		}
		delete mRenderView;
		delete mRenderSystem;
		mLogger.LogInformation("=== Shutdown complete ===");
	}
}

namespace ImpactArena;

using System;
using System.Collections;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Materials;
using Sedulous.Render;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Physics;
using Sedulous.Framework.Input;
using Sedulous.Framework.Audio;
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Audio.Decoders;
using Sedulous.Physics;
using Sedulous.Physics.Jolt;
using Sedulous.Drawing;
using Sedulous.Drawing.Fonts;
using Sedulous.Drawing.Renderer;
using Sedulous.Fonts;

class ImpactArenaGame : Application
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

	// Scene
	private Scene mMainScene;
	private EntityId mCameraEntity;
	private EntityId mSunEntity;

	// Meshes
	private GPUMeshHandle mPlaneMeshHandle;
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mSphereMeshHandle;

	// Materials
	private MaterialInstance mFloorMat;
	private MaterialInstance mWallMat;
	private MaterialInstance mPlayerMat;
	private MaterialInstance mGruntMat;
	private MaterialInstance mBruteMat;
	private MaterialInstance mDasherMat;
	private MaterialInstance mHealthPickupMat;
	private MaterialInstance mSpeedPickupMat;
	private MaterialInstance mShockPickupMat;
	private MaterialInstance mEmpPickupMat;

	// Audio
	private AudioSubsystem mAudioSubsystem;
	private GameAudio mGameAudio = new .() ~ delete _;
	private IAudioSource mBgMusicSource;
	private AudioClip mBgMusicClip ~ delete _;

	// 2D Drawing (UI)
	private FontService mFontService;
	private DrawContext mDrawContext;
	private DrawingRenderer mDrawingRenderer;

	// Game objects
	private Arena mArena = new .() ~ delete _;
	private Player mPlayer = new .() ~ delete _;
	private EnemyManager mEnemyManager = new .() ~ delete _;
	private EffectsManager mEffectsManager = new .() ~ delete _;
	private PowerUpManager mPowerUpManager = new .() ~ delete _;
	private HUD mHud = new .() ~ delete _;

	// Game state
	private GameState mState = .Title;
	private int32 mWave = 0;
	private int32 mScore = 0;
	private int32 mHighScore = 0;
	private float mWaveIntroTimer = 0;
	private float mDeltaTime = 0;
	private float mSmoothedFps = 60.0f;

	// Screen shake
	private float mShakeIntensity = 0;
	private Random mShakeRandom = new .() ~ delete _;

	// Combo tracking
	private int32 mComboCount = 0;
	private bool mWasDashing = false;
	private float mComboDisplayTimer = 0;
	private int32 mLastComboBonus = 0;

	// Input actions
	private InputSubsystem mInputSubsystem;
	private InputAction mMoveAction;
	private InputAction mDashAction;
	private InputAction mConfirmAction;
	private InputAction mPauseAction;
	private InputAction mCycleLeftAction;
	private InputAction mCycleRightAction;
	private InputAction mUsePickupAction;

	// Stored input state for fixed update
	private Vector2 mMoveInput;
	private bool mDashPressed;

	// Inventory (storable pickups)
	private const int32 MaxInventory = 3;
	private PowerUpType[MaxInventory] mInventory;
	private int32 mInventoryCount = 0;
	private int32 mActiveSlot = 0;

	// Dash trail (emitter on player entity)
	private bool mTrailInitialized = false;

	// Debug gizmo visibility
	private bool mShowGizmo = false;

	// Temp lists for collision results
	private List<Vector3> mDeathPositions = new .() ~ delete _;
	private List<EnemyType> mDeathTypes = new .() ~ delete _;

	// Material mode toggle (true = unlit, false = PBR)
	private const bool UseUnlitMaterials = false;
	private Material mUnlitBaseMaterial ~ delete _;

	// Sun light control (spherical coordinates)
	private float mSunYaw = 0.0f;
	private float mSunPitch = 1.3f;
	private float mSunIntensity = 4.0f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Context context)
	{
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
			return;

		mRenderView = new RenderView();
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.FieldOfView = Math.PI_f / 4.0f;
		mRenderView.NearPlane = 0.1f;
		mRenderView.FarPlane = 100.0f;

		// Register features
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
	}

	private void RegisterSubsystems(Context context)
	{
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);

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

		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);

		mInputSubsystem = new InputSubsystem();
		mInputSubsystem.SetInputManager(mShell.InputManager);
		context.RegisterSubsystem(mInputSubsystem);
		SetupInputActions();

		let audioSystem = new SDL3AudioSystem();
		mAudioSubsystem = new AudioSubsystem(audioSystem, takeOwnership: true);
		mAudioSubsystem.SFXVolume = 0.5f;
		context.RegisterSubsystem(mAudioSubsystem);
	}

	private void SetupInputActions()
	{
		let gameplayContext = mInputSubsystem.CreateContext("Gameplay", 0);

		// Move: WASD + left stick
		mMoveAction = gameplayContext.RegisterAction("Move");
		mMoveAction.AddBinding(new CompositeBinding(.W, .S, .A, .D));
		let stickBinding = new GamepadStickBinding(.Left, 0, 0.15f);
		stickBinding.InvertY = true; // SDL Y axis is inverted (up = negative)
		mMoveAction.AddBinding(stickBinding);

		// Dash: Space + A button (South) + right trigger
		mDashAction = gameplayContext.RegisterAction("Dash");
		mDashAction.AddBinding(new KeyBinding(.Space));
		mDashAction.AddBinding(new GamepadButtonBinding(.South));

		// Confirm: Space + A button
		mConfirmAction = gameplayContext.RegisterAction("Confirm");
		mConfirmAction.AddBinding(new KeyBinding(.Space));
		mConfirmAction.AddBinding(new GamepadButtonBinding(.South));

		// Pause: Escape + Start
		mPauseAction = gameplayContext.RegisterAction("Pause");
		mPauseAction.AddBinding(new KeyBinding(.Escape));
		mPauseAction.AddBinding(new GamepadButtonBinding(.Start));

		// Cycle inventory: Left/Right arrows + L1/R1
		mCycleLeftAction = gameplayContext.RegisterAction("CycleLeft");
		mCycleLeftAction.AddBinding(new KeyBinding(.Left));
		mCycleLeftAction.AddBinding(new GamepadButtonBinding(.LeftShoulder));

		mCycleRightAction = gameplayContext.RegisterAction("CycleRight");
		mCycleRightAction.AddBinding(new KeyBinding(.Right));
		mCycleRightAction.AddBinding(new GamepadButtonBinding(.RightShoulder));

		// Use pickup: E + West (X) button
		mUsePickupAction = gameplayContext.RegisterAction("UsePickup");
		mUsePickupAction.AddBinding(new KeyBinding(.E));
		mUsePickupAction.AddBinding(new GamepadButtonBinding(.West));
	}

	protected override void OnContextStarted()
	{
		CreateMeshes();
		CreateMaterials();
		CreateScene();
		InitializeDrawing();
		InitializeGameObjects();
		InitializeAudio();
	}

	private void InitializeDrawing()
	{
		// Initialize font service with multiple sizes for UI hierarchy
		mFontService = new FontService(mDevice);
		let fontPath = scope String();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		// Load font at different sizes for UI hierarchy
		int32[5] fontSizes = .(14, 18, 24, 32, 48);
		for (let size in fontSizes)
		{
			FontLoadOptions options = .ExtendedLatin;
			options.PixelHeight = size;
			if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
			{
				Console.WriteLine($"Failed to load UI font at size {size}");
			}
		}

		// Create draw context with font service
		mDrawContext = new DrawContext(mFontService);

		// Create and initialize the drawing renderer
		mDrawingRenderer = new DrawingRenderer();
		if (mDrawingRenderer.Initialize(mDevice, mSwapChain.Format, FrameConfig.MAX_FRAMES_IN_FLIGHT, mRenderSystem.ShaderSystem) case .Err)
		{
			Console.WriteLine("Failed to initialize DrawingRenderer");
		}
		else
		{
			// Set up multi-texture support for different font sizes
			mDrawingRenderer.SetTextureLookup(new (texture) => mFontService.GetTextureView(texture));
		}
	}

	private void InitializeAudio()
	{
		mGameAudio.Initialize(mAudioSubsystem, scope => GetAssetPath);

		// Background music - decode via AudioDecoderFactory (handles 24-bit WAV -> 16-bit PCM)
		let musicPath = scope String();
		GetAssetPath("samples/audio/ImpactArena/eyeless.wav", musicPath);
		let decoder = scope AudioDecoderFactory();
		decoder.RegisterDefaultDecoders();
		if (decoder.DecodeFile(musicPath) case .Ok(let clip))
		{
			mBgMusicClip = clip;
			mBgMusicSource = mAudioSubsystem.AudioSystem.CreateSource();
			mBgMusicSource.Loop = true;
			mBgMusicSource.Volume = 0.15f;
			mBgMusicSource.Play(clip);
		}
	}

	private void CreateMeshes()
	{
		let planeMesh = StaticMesh.CreatePlane(Arena.HalfSize * 2, Arena.HalfSize * 2, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let planeHandle))
			mPlaneMeshHandle = planeHandle;
		delete planeMesh;

		let cubeMesh = StaticMesh.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let cubeHandle))
			mCubeMeshHandle = cubeHandle;
		delete cubeMesh;

		let sphereMesh = StaticMesh.CreateSphere(0.5f, 16, 12);
		if (mRenderSystem.ResourceManager.UploadMesh(sphereMesh) case .Ok(let sphereHandle))
			mSphereMeshHandle = sphereHandle;
		delete sphereMesh;
	}

	private void CreateMaterials()
	{
		if (UseUnlitMaterials)
			CreateUnlitMaterials();
		else
			CreatePBRMaterials();
	}

	private void CreateUnlitMaterials()
	{
		// Create unlit base material
		mUnlitBaseMaterial = Materials.CreateUnlit("GameUnlit");

		mFloorMat = new MaterialInstance(mUnlitBaseMaterial);
		mFloorMat.SetColor("BaseColor", .(0.15f, 0.15f, 0.2f, 1.0f));

		mWallMat = new MaterialInstance(mUnlitBaseMaterial);
		mWallMat.SetColor("BaseColor", .(0.3f, 0.3f, 0.35f, 1.0f));

		mPlayerMat = new MaterialInstance(mUnlitBaseMaterial);
		mPlayerMat.SetColor("BaseColor", .(0.2f, 0.5f, 1.0f, 1.0f));

		mGruntMat = new MaterialInstance(mUnlitBaseMaterial);
		mGruntMat.SetColor("BaseColor", .(0.9f, 0.2f, 0.15f, 1.0f));

		mBruteMat = new MaterialInstance(mUnlitBaseMaterial);
		mBruteMat.SetColor("BaseColor", .(0.2f, 0.8f, 0.2f, 1.0f));

		mDasherMat = new MaterialInstance(mUnlitBaseMaterial);
		mDasherMat.SetColor("BaseColor", .(0.9f, 0.8f, 0.1f, 1.0f));

		// Pickups use emissive for glow effect
		mHealthPickupMat = new MaterialInstance(mUnlitBaseMaterial);
		mHealthPickupMat.SetColor("BaseColor", .(0.1f, 0.9f, 0.3f, 1.0f));
		mHealthPickupMat.SetColor("EmissiveColor", .(0.1f, 0.8f, 0.3f, 1.0f));

		mSpeedPickupMat = new MaterialInstance(mUnlitBaseMaterial);
		mSpeedPickupMat.SetColor("BaseColor", .(0.1f, 0.8f, 1.0f, 1.0f));
		mSpeedPickupMat.SetColor("EmissiveColor", .(0.1f, 0.6f, 1.0f, 1.0f));

		mShockPickupMat = new MaterialInstance(mUnlitBaseMaterial);
		mShockPickupMat.SetColor("BaseColor", .(0.7f, 0.2f, 1.0f, 1.0f));
		mShockPickupMat.SetColor("EmissiveColor", .(0.6f, 0.15f, 0.9f, 1.0f));

		mEmpPickupMat = new MaterialInstance(mUnlitBaseMaterial);
		mEmpPickupMat.SetColor("BaseColor", .(1.0f, 0.9f, 0.2f, 1.0f));
		mEmpPickupMat.SetColor("EmissiveColor", .(1.0f, 0.8f, 0.2f, 1.0f));
	}

	private void CreatePBRMaterials()
	{
		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
		if (baseMat == null) return;

		mFloorMat = new MaterialInstance(baseMat);
		mFloorMat.SetColor("BaseColor", .(0.35f, 0.35f, 0.45f, 1.0f));
		mFloorMat.SetFloat("Metallic", 0.0f);
		mFloorMat.SetFloat("Roughness", 0.9f);

		mWallMat = new MaterialInstance(baseMat);
		mWallMat.SetColor("BaseColor", .(0.55f, 0.55f, 0.6f, 1.0f));
		mWallMat.SetFloat("Roughness", 0.7f);

		mPlayerMat = new MaterialInstance(baseMat);
		mPlayerMat.SetColor("BaseColor", .(0.4f, 0.7f, 1.0f, 1.0f));
		mPlayerMat.SetFloat("Metallic", 0.8f);
		mPlayerMat.SetFloat("Roughness", 0.2f);
		mPlayerMat.SetTexture("EmissiveMap", mRenderSystem.MaterialSystem.WhiteTexture);

		mGruntMat = new MaterialInstance(baseMat);
		mGruntMat.SetColor("BaseColor", .(1.0f, 0.4f, 0.35f, 1.0f));
		mGruntMat.SetFloat("Roughness", 0.5f);

		mBruteMat = new MaterialInstance(baseMat);
		mBruteMat.SetColor("BaseColor", .(0.4f, 0.95f, 0.4f, 1.0f));
		mBruteMat.SetFloat("Roughness", 0.6f);

		mDasherMat = new MaterialInstance(baseMat);
		mDasherMat.SetColor("BaseColor", .(1.0f, 0.9f, 0.3f, 1.0f));
		mDasherMat.SetFloat("Metallic", 0.5f);
		mDasherMat.SetFloat("Roughness", 0.3f);

		let emissiveTex = mRenderSystem.MaterialSystem.WhiteTexture;

		mHealthPickupMat = new MaterialInstance(baseMat);
		mHealthPickupMat.SetColor("BaseColor", .(0.3f, 1.0f, 0.5f, 1.0f));
		mHealthPickupMat.SetFloat("Metallic", 0.6f);
		mHealthPickupMat.SetFloat("Roughness", 0.3f);
		mHealthPickupMat.SetTexture("EmissiveMap", emissiveTex);
		mHealthPickupMat.SetColor("EmissiveColor", .(0.2f, 0.9f, 0.4f, 1.0f));

		mSpeedPickupMat = new MaterialInstance(baseMat);
		mSpeedPickupMat.SetColor("BaseColor", .(0.3f, 0.9f, 1.0f, 1.0f));
		mSpeedPickupMat.SetFloat("Metallic", 0.7f);
		mSpeedPickupMat.SetFloat("Roughness", 0.2f);
		mSpeedPickupMat.SetTexture("EmissiveMap", emissiveTex);
		mSpeedPickupMat.SetColor("EmissiveColor", .(0.2f, 0.7f, 1.0f, 1.0f));

		mShockPickupMat = new MaterialInstance(baseMat);
		mShockPickupMat.SetColor("BaseColor", .(0.8f, 0.4f, 1.0f, 1.0f));
		mShockPickupMat.SetFloat("Metallic", 0.6f);
		mShockPickupMat.SetFloat("Roughness", 0.3f);
		mShockPickupMat.SetTexture("EmissiveMap", emissiveTex);
		mShockPickupMat.SetColor("EmissiveColor", .(0.7f, 0.3f, 1.0f, 1.0f));

		mEmpPickupMat = new MaterialInstance(baseMat);
		mEmpPickupMat.SetColor("BaseColor", .(1.0f, 0.95f, 0.4f, 1.0f));
		mEmpPickupMat.SetFloat("Metallic", 0.9f);
		mEmpPickupMat.SetFloat("Roughness", 0.1f);
		mEmpPickupMat.SetTexture("EmissiveMap", emissiveTex);
		mEmpPickupMat.SetColor("EmissiveColor", .(1.0f, 0.9f, 0.3f, 1.0f));
	}

	private void CreateScene()
	{
		mMainScene = mSceneSubsystem.CreateScene("ArenaScene");
		mSceneSubsystem.SetActiveScene(mMainScene);

		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		if (renderModule == null) return;

		// Brighten the scene with ambient lighting and exposure
		if (let world = renderModule.World)
		{
			world.AmbientColor = .(0.15f, 0.15f, 0.18f); // Brighter ambient with slight blue tint
			world.AmbientIntensity = 1.2f;
			world.Exposure = 1.0f;
		}

		// Camera - fixed top-down
		mCameraEntity = mMainScene.CreateEntity();
		renderModule.CreatePerspectiveCamera(mCameraEntity,
			Math.PI_f / 4.0f,
			(float)mSwapChain.Width / mSwapChain.Height,
			0.1f, 100.0f);
		renderModule.SetMainCamera(mCameraEntity);

		var camTransform = mMainScene.GetTransform(mCameraEntity);
		camTransform.Position = .(0, 35, 4);
		mMainScene.SetTransform(mCameraEntity, camTransform);

		// Sun light - nearly overhead for even arena illumination
		mSunEntity = mMainScene.CreateEntity();
		renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.98f, 0.95f), mSunIntensity);
		UpdateSunLight();
	}

	private void UpdateSunLight()
	{
		if (mMainScene == null) return;

		var transform = mMainScene.GetTransform(mSunEntity);
		transform.Rotation = Quaternion.CreateFromYawPitchRoll(mSunYaw, -mSunPitch, 0);
		mMainScene.SetTransform(mSunEntity, transform);

		// Update intensity on the light proxy (use pointer directly to modify in place)
		if (let renderModule = mMainScene.GetModule<RenderSceneModule>())
		{
			let proxyPtr = renderModule.GetLightProxy(mSunEntity);
			if (proxyPtr != null)
				proxyPtr.Intensity = mSunIntensity;
		}
	}

	private void InitializeGameObjects()
	{
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		let physicsModule = mMainScene.GetModule<PhysicsSceneModule>();
		if (renderModule == null || physicsModule == null) return;

		mArena.Initialize(mMainScene, renderModule, physicsModule,
			mPlaneMeshHandle, mCubeMeshHandle, mFloorMat, mWallMat);

		mPlayer.Initialize(mMainScene, renderModule, physicsModule,
			mSphereMeshHandle, mPlayerMat);

		// Player dash trail emitter - speed/afterburner effect
		let trailHandle = renderModule.CreateCPUParticleEmitter(mPlayer.Entity, 150);
		if (trailHandle.IsValid)
		{
			if (let proxy = renderModule.GetParticleEmitterProxy(mPlayer.Entity))
			{
				proxy.BlendMode = .Additive;
				proxy.SpawnRate = 120; // High rate for solid trail
				proxy.ParticleLifetime = 0.35f;
				proxy.StartSize = .(0.8f, 0.8f);
				proxy.EndSize = .(0.02f, 0.02f);
				// Speed colors: bright cyan core fading to blue
				proxy.StartColor = .(0.5f, 0.9f, 1.0f, 1.0f);
				proxy.EndColor = .(0.1f, 0.4f, 1.0f, 0.0f);
				// Top-down game: velocities in XZ plane only
				proxy.InitialVelocity = .(0, 0.2f, 0);
				proxy.VelocityRandomness = .(0.5f, 0.3f, 0.5f); // XZ spread only
				//proxy.VelocityInheritance = 0.5f; // Inherit player velocity for trail direction
				proxy.GravityMultiplier = 0;
				proxy.Drag = 2.0f; // Quick slowdown for tight trail
				proxy.LifetimeVarianceMin = 0.8f;
				proxy.LifetimeVarianceMax = 1.0f;
				//// Horizontal billboard for top-down view (flat on ground)
				//proxy.RenderMode = .HorizontalBillboard;
				proxy.IsEnabled = true;
				proxy.IsEmitting = false; // Only emit when dashing
				proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.2f);
				mTrailInitialized = true;
			}
		}

		mEnemyManager.Initialize(mMainScene, renderModule, physicsModule,
			mSphereMeshHandle, mGruntMat, mBruteMat, mDasherMat);

		mEffectsManager.Initialize(mMainScene, renderModule);
		mPowerUpManager.Initialize(mMainScene, renderModule, mSphereMeshHandle,
			mHealthPickupMat, mSpeedPickupMat, mShockPickupMat, mEmpPickupMat);
		mHud.Initialize(mDrawContext);
	}

	protected override void OnInput()
	{
		switch (mState)
		{
		case .Title:
			if (mConfirmAction.WasPressed)
				StartGame();
			if (mPauseAction.WasPressed)
				Exit();
		case .Playing, .WaveIntro:
			// Store input state for fixed update
			mMoveInput = mMoveAction.Vector2Value;
			if (mDashAction.WasPressed)
				mDashPressed = true; // Latch until consumed by fixed update
			if (mPauseAction.WasPressed)
			{
				mState = .Paused;
				mAudioSubsystem.AudioSystem.PauseAll();
			}
			// Inventory cycling
			if (mCycleRightAction.WasPressed && mInventoryCount > 0)
				mActiveSlot = (mActiveSlot + 1) % mInventoryCount;
			if (mCycleLeftAction.WasPressed && mInventoryCount > 0)
				mActiveSlot = (mActiveSlot - 1 + mInventoryCount) % mInventoryCount;
			// Use active pickup
			if (mUsePickupAction.WasPressed && mInventoryCount > 0)
				UseActivePickup();
		case .GameOver:
			if (mConfirmAction.WasPressed)
				StartGame();
			if (mPauseAction.WasPressed)
				mState = .Title;
		case .Paused:
			if (mPauseAction.WasPressed)
			{
				mState = .Playing;
				mAudioSubsystem.AudioSystem.ResumeAll();
			}
		}

		// Sun light controls (always active for tuning)
		HandleLightControls();
	}

	private void HandleLightControls()
	{
		let keyboard = mShell.InputManager?.Keyboard;
		if (keyboard == null) return;

		// G - toggle debug gizmo (always available)
		if (keyboard.IsKeyPressed(.G))
			mShowGizmo = !mShowGizmo;

		// Light controls only when gizmo is visible
		if (!mShowGizmo)
			return;

		bool lightChanged = false;
		float rotSpeed = 0.03f;
		float intensityStep = 0.25f;

		// Arrow keys - rotate sun
		if (keyboard.IsKeyDown(.Left))
		{
			mSunYaw -= rotSpeed;
			lightChanged = true;
		}
		if (keyboard.IsKeyDown(.Right))
		{
			mSunYaw += rotSpeed;
			lightChanged = true;
		}
		if (keyboard.IsKeyDown(.Up))
		{
			mSunPitch = Math.Clamp(mSunPitch + rotSpeed, 0.1f, 1.5f);
			lightChanged = true;
		}
		if (keyboard.IsKeyDown(.Down))
		{
			mSunPitch = Math.Clamp(mSunPitch - rotSpeed, 0.1f, 1.5f);
			lightChanged = true;
		}

		// U/I - decrease/increase intensity
		if (keyboard.IsKeyPressed(.U))
		{
			mSunIntensity = Math.Max(0.5f, mSunIntensity - intensityStep);
			lightChanged = true;
		}
		if (keyboard.IsKeyPressed(.I))
		{
			mSunIntensity = Math.Min(10.0f, mSunIntensity + intensityStep);
			lightChanged = true;
		}

		if (lightChanged)
			UpdateSunLight();

		// L - print light properties
		if (keyboard.IsKeyPressed(.L))
		{
			Console.WriteLine("=== Sun Light Properties ===");
			Console.WriteLine("  Yaw:       {:.3f} rad ({:.1f} deg)", mSunYaw, mSunYaw * 180.0f / Math.PI_f);
			Console.WriteLine("  Pitch:     {:.3f} rad ({:.1f} deg)", mSunPitch, mSunPitch * 180.0f / Math.PI_f);
			Console.WriteLine("  Intensity: {:.2f} (local)", mSunIntensity);

			if (let renderModule = mMainScene?.GetModule<RenderSceneModule>())
			{
				let proxyPtr = renderModule.GetLightProxy(mSunEntity);
				if (proxyPtr != null)
				{
					Console.WriteLine("  Intensity: {:.2f} (proxy)", proxyPtr.Intensity);
					Console.WriteLine("  Direction: ({:.3f}, {:.3f}, {:.3f})", proxyPtr.Direction.X, proxyPtr.Direction.Y, proxyPtr.Direction.Z);
				}
			}
			Console.WriteLine("============================");
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = frame.DeltaTime;
		if (mDeltaTime > 0)
		{
			let instantFps = 1.0f / mDeltaTime;
			mSmoothedFps = mSmoothedFps * 0.95f + instantFps * 0.05f;
		}

		mEffectsManager.Update(mDeltaTime);

		// Screen shake decay (runs in all states)
		if (mShakeIntensity > 0.01f)
			mShakeIntensity *= Math.Pow(0.05f, mDeltaTime);
		else
			mShakeIntensity = 0;

		switch (mState)
		{
		case .Playing:
			UpdatePlaying();
		case .WaveIntro:
			UpdateWaveIntro();
		default:
		}
	}

	protected override void OnFixedUpdate(float fixedDt)
	{
		switch (mState)
		{
		case .Playing, .WaveIntro:
			FixedUpdatePlaying(fixedDt);
		default:
		}
	}

	private void FixedUpdatePlaying(float dt)
	{
		// Player physics update with stored input
		mPlayer.Update(mMoveInput, mDashPressed, dt);
		mDashPressed = false; // Consume the latched dash input

		// Enemy AI and physics
		let playerPos = mPlayer.Position;
		mEnemyManager.Update(playerPos, dt);
		mPowerUpManager.Update(dt);

		// Check power-up pickup
		if (let pickupType = mPowerUpManager.CheckPickup(playerPos, mInventoryCount < MaxInventory))
		{
			mEffectsManager.SpawnPickupEffect(playerPos, pickupType);
			mGameAudio.PlayPickup();

			if (pickupType == .HealthPack)
			{
				mPlayer.Heal(25.0f);
			}
			else if (mInventoryCount < MaxInventory)
			{
				mInventory[mInventoryCount] = pickupType;
				mInventoryCount++;
			}
		}

		// Check collisions
		mDeathPositions.Clear();
		mDeathTypes.Clear();
		let damage = mEnemyManager.CheckPlayerCollisions(
			playerPos, mPlayer.Speed, mPlayer.IsInvulnerable,
			mDeathPositions, mDeathTypes);

		if (damage > 0)
		{
			mPlayer.TakeDamage(damage);
			mEffectsManager.SpawnHitEffect(playerPos);
			mGameAudio.PlayHit();
			mShakeIntensity = 0.5f;
		}

		// Spawn death effects, add score, track combo
		for (int32 i = 0; i < (int32)mDeathPositions.Count; i++)
		{
			mEffectsManager.SpawnDeathEffect(mDeathPositions[i], mDeathTypes[i]);
			mGameAudio.PlayEnemyDeath();
			let enemyScore = GetScoreForEnemy(mDeathTypes[i]);
			mScore += enemyScore;

			if (mPlayer.IsDashing)
				mComboCount++;
		}

		// Process combo at end of dash
		if (!mPlayer.IsDashing && mComboCount > 1)
		{
			let bonus = mComboCount * 10;
			mScore += bonus;
			mLastComboBonus = bonus;
			mComboDisplayTimer = 2.0f;
		}
		if (!mPlayer.IsDashing)
			mComboCount = 0;

		// Check player death
		if (!mPlayer.IsAlive)
		{
			mEffectsManager.SpawnPlayerDeathEffect(playerPos);
			mGameAudio.PlayPlayerDeath();
			mShakeIntensity = 1.0f;
			if (mScore > mHighScore)
				mHighScore = mScore;
			mState = .GameOver;
		}

		// Wave complete check
		if (mState == .Playing && mEnemyManager.AliveCount == 0)
		{
			mWave++;
			mScore += mWave * 100;
			mState = .WaveIntro;
			mWaveIntroTimer = 3.0f;
		}
	}

	private void UpdatePlaying()
	{
		// Visual-only updates (physics handled in FixedUpdate)

		// Dash trail - only emit when dashing
		if (mTrailInitialized)
		{
			if (let renderModule = mMainScene.GetModule<RenderSceneModule>())
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mPlayer.Entity))
				{
					proxy.IsEmitting = mPlayer.IsDashing;
				}
			}
		}

		// Player visual effects based on state
		if (mPlayer.IsInvulnerable)
		{
			// Invulnerability flash (red pulse)
			let pulse = (Math.Sin(mPlayer.InvulnTimer * 20.0f) + 1.0f) * 0.5f;
			mPlayerMat.SetColor("EmissiveColor", .(1.0f * pulse, 0.3f * pulse, 0.3f * pulse, 1.0f));
		}
		else
		{
			// Speed-based glow: faster = brighter cyan/blue glow
			let speed = mPlayer.Speed;
			let maxSpeed = mPlayer.IsDashing ? 25.0f : 12.0f;
			let speedFactor = Math.Clamp(speed / maxSpeed, 0.0f, 1.0f);

			if (speedFactor > 0.1f)
			{
				let intensity = speedFactor * speedFactor;
				let r = 0.2f * intensity;
				let g = 0.7f * intensity;
				let b = 1.0f * intensity;
				mPlayerMat.SetColor("EmissiveColor", .(r, g, b, 1.0f));
			}
			else
			{
				mPlayerMat.SetColor("EmissiveColor", .(0, 0, 0, 1.0f));
			}
		}

		// Combo display timer (visual only)
		if (mComboDisplayTimer > 0)
			mComboDisplayTimer -= mDeltaTime;

		// Dash sound trigger
		if (mPlayer.IsDashing && !mWasDashing)
			mGameAudio.PlayDash();
		mWasDashing = mPlayer.IsDashing;
	}

	private void UseActivePickup()
	{
		if (mInventoryCount <= 0) return;

		let type = mInventory[mActiveSlot];
		let playerPos = mPlayer.Position;

		switch (type)
		{
		case .SpeedBoost:
			mPlayer.ApplySpeedBoost(5.0f);
		case .Shockwave:
			mEffectsManager.SpawnShockwaveEffect(playerPos);
			mGameAudio.PlayShockwave();
			mShakeIntensity = 0.8f;
			mDeathPositions.Clear();
			mDeathTypes.Clear();
			mEnemyManager.KillInRadius(playerPos, 5.0f, mDeathPositions, mDeathTypes);
			for (int32 i = 0; i < (int32)mDeathPositions.Count; i++)
			{
				mEffectsManager.SpawnDeathEffect(mDeathPositions[i], mDeathTypes[i]);
				mScore += GetScoreForEnemy(mDeathTypes[i]);
			}
		case .EMP:
			mEffectsManager.SpawnEMPEffect(playerPos);
			mGameAudio.PlayShockwave();
			mShakeIntensity = 1.2f;
			mDeathPositions.Clear();
			mDeathTypes.Clear();
			mEnemyManager.KillInRadius(playerPos, 20.0f, mDeathPositions, mDeathTypes);
			for (int32 i = 0; i < (int32)mDeathPositions.Count; i++)
			{
				mEffectsManager.SpawnDeathEffect(mDeathPositions[i], mDeathTypes[i]);
				mScore += GetScoreForEnemy(mDeathTypes[i]);
			}
		default:
		}

		// Remove used item from inventory, shift remaining
		for (int32 i = mActiveSlot; i < mInventoryCount - 1; i++)
			mInventory[i] = mInventory[i + 1];
		mInventoryCount--;
		if (mActiveSlot >= mInventoryCount && mInventoryCount > 0)
			mActiveSlot = mInventoryCount - 1;
		if (mInventoryCount == 0)
			mActiveSlot = 0;
	}

	private void UpdateWaveIntro()
	{
		mWaveIntroTimer -= mDeltaTime;
		if (mWaveIntroTimer <= 0)
		{
			mEnemyManager.SpawnWave(mWave);
			mGameAudio.PlayWaveStart();
			mState = .Playing;
		}
	}

	private void StartGame()
	{
		mState = .WaveIntro;
		mWave = 1;
		mScore = 0;
		mWaveIntroTimer = 3.0f;
		// Start with one of each usable powerup
		mInventory[0] = .SpeedBoost;
		mInventory[1] = .Shockwave;
		mInventory[2] = .EMP;
		mInventoryCount = 3;
		mActiveSlot = 0;
		mPlayer.Reset();
		mEnemyManager.ClearAll();
		mEffectsManager.ClearAll();
		mPowerUpManager.ClearAll();
	}

	private int32 GetScoreForEnemy(EnemyType type)
	{
		switch (type)
		{
		case .Grunt: return 10;
		case .Brute: return 30;
		case .Dasher: return 20;
		}
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame(render.Frame.TotalTime, render.Frame.DeltaTime);

		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		if (let renderModule = mMainScene?.GetModule<RenderSceneModule>())
		{
			if (let world = renderModule.World)
				mRenderSystem.SetActiveWorld(world);
		}

		// Draw 2D UI to DrawContext
		if (mDrawContext != null)
		{
			mDrawContext.Clear();
			mHud.Draw(mState, mPlayer, mWave, mEnemyManager.AliveCount, mScore,
				mHighScore, mWaveIntroTimer, mSwapChain.Width, mSwapChain.Height,
				&mInventory[0], mInventoryCount, mActiveSlot, render.Frame.TotalTime);
			mHud.DrawExtras(mComboDisplayTimer, mLastComboBonus, mPlayer.HasSpeedBoost,
				mSmoothedFps, mSwapChain.Width, mSwapChain.Height, mShowGizmo);
		}

		// 3D Debug overlays (sun gizmo, arena boundary lines)
		if (mDebugFeature != null)
		{
			// Sun light direction gizmo (G to toggle)
			if (mShowGizmo)
			{
				if (let renderModule = mMainScene?.GetModule<RenderSceneModule>())
				{
					let lightProxy = renderModule.GetLightProxy(mSunEntity);
					if (lightProxy != null)
					{
						Vector3 sunOrigin = .(0, 8, 0); // Elevated above arena center
						Vector3 sunEnd = sunOrigin + lightProxy.Direction * 5.0f;
						mDebugFeature.AddArrow(sunOrigin, sunEnd, Color.Yellow, 0.3f, .Overlay);
						mDebugFeature.AddSphere(sunOrigin, 0.3f, Color.Yellow, 8, .Overlay);
					}
				}
			}

			// Arena boundary lines - change color based on player proximity to edge
			if (mState == .Playing || mState == .WaveIntro)
			{
				let hs = Arena.HalfSize;
				let playerPos = mPlayer.Position;
				let edgeDistX = hs - Math.Abs(playerPos.X);
				let edgeDistZ = hs - Math.Abs(playerPos.Z);
				let minEdgeDist = Math.Min(edgeDistX, edgeDistZ);
				let dangerZone = 3.0f; // Start warning within 3 units of edge
				let danger = Math.Max(0.0f, 1.0f - minEdgeDist / dangerZone);
				// Lerp from blue/cyan to red/orange
				let r = (uint8)Math.Min(255, (int32)(50 + danger * 205));
				let g = (uint8)Math.Min(255, (int32)(150 - danger * 120));
				let b = (uint8)Math.Min(255, (int32)(255 - danger * 200));
				let lineColor = Color(r, g, b, (uint8)(150 + danger * 105));
				let y = 0.05f;

				// Draw boundary lines (4 edges, segmented for better visibility)
				int32 segments = 8;
				let segLen = hs * 2.0f / (float)segments;
				for (int32 s = 0; s < segments; s++)
				{
					let t0 = -hs + (float)s * segLen;
					let t1 = t0 + segLen;
					// North edge (Z = -hs)
					mDebugFeature.AddLine(.(t0, y, -hs), .(t1, y, -hs), lineColor, .Overlay);
					// South edge (Z = +hs)
					mDebugFeature.AddLine(.(t0, y, hs), .(t1, y, hs), lineColor, .Overlay);
					// West edge (X = -hs)
					mDebugFeature.AddLine(.(-hs, y, t0), .(-hs, y, t1), lineColor, .Overlay);
					// East edge (X = +hs)
					mDebugFeature.AddLine(.(hs, y, t0), .(hs, y, t1), lineColor, .Overlay);
				}
			}
		}

		// Update camera in render view (with screen shake)
		var camPos = mMainScene.GetTransform(mCameraEntity).Position;
		if (mShakeIntensity > 0.01f)
		{
			camPos.X += ((float)mShakeRandom.NextDouble() - 0.5f) * 2.0f * mShakeIntensity;
			camPos.Z += ((float)mShakeRandom.NextDouble() - 0.5f) * 2.0f * mShakeIntensity;
		}
		let camForward = Vector3(0, -0.99f, -0.14f); // Nearly straight down with slight tilt
		mRenderView.CameraPosition = camPos;
		mRenderView.CameraForward = Vector3.Normalize(camForward);
		mRenderView.CameraUp = .(0, 0, -1); // Use -Z as up for top-down view
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.UpdateMatrices(mDevice.FlipProjectionRequired);

		mRenderSystem.SetCamera(
			mRenderView.CameraPosition,
			mRenderView.CameraForward,
			.(0, 0, -1),
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

		// Render 2D UI overlay on top of 3D scene
		if (mDrawingRenderer != null && mDrawContext != null)
		{
			let frameIndex = render.Frame.FrameIndex;

			// Prepare batch data for GPU
			let batch = mDrawContext.GetBatch();
			mDrawingRenderer.Prepare(batch, frameIndex);
			mDrawingRenderer.UpdateProjection(mSwapChain.Width, mSwapChain.Height, frameIndex);

			// Create render pass with Load to preserve 3D scene
			RenderPassColorAttachment[1] colorAttachments = .(.()
			{
				View = render.SwapChain.CurrentTextureView,
				LoadOp = .Load,
				StoreOp = .Store
			});

			RenderPassDescriptor passDesc = .(colorAttachments);
			let renderPass = render.Encoder.BeginRenderPass(&passDesc);
			if (renderPass != null)
			{
				mDrawingRenderer.Render(renderPass, mSwapChain.Width, mSwapChain.Height, frameIndex);
				renderPass.End();
				delete renderPass;
			}
		}

		return true;
	}

	protected override void OnShutdown()
	{
		// Clean up drawing system
		if (mDrawingRenderer != null)
		{
			mDrawingRenderer.Dispose();
			delete mDrawingRenderer;
		}
		delete mDrawContext;
		delete mFontService;

		if (mPlaneMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);
		if (mCubeMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
		if (mSphereMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mSphereMeshHandle, mRenderSystem.FrameNumber);

		delete mFloorMat;
		delete mWallMat;
		delete mPlayerMat;
		delete mGruntMat;
		delete mBruteMat;
		delete mDasherMat;
		delete mHealthPickupMat;
		delete mSpeedPickupMat;
		delete mShockPickupMat;
		delete mEmpPickupMat;

		if (mBgMusicSource != null)
			mAudioSubsystem.AudioSystem.DestroySource(mBgMusicSource);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		delete mRenderView;
		delete mRenderSystem;
	}
}

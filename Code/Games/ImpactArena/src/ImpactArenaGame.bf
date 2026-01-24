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
using Sedulous.Physics;
using Sedulous.Physics.Jolt;

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

	// Inventory (storable pickups)
	private const int32 MaxInventory = 3;
	private PowerUpType[MaxInventory] mInventory;
	private int32 mInventoryCount = 0;
	private int32 mActiveSlot = 0;

	// Dash trail (emitter on player entity)
	private bool mTrailInitialized = false;

	// Temp lists for collision results
	private List<Vector3> mDeathPositions = new .() ~ delete _;
	private List<EnemyType> mDeathTypes = new .() ~ delete _;

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
		InitializeGameObjects();
		InitializeAudio();
	}

	private void InitializeAudio()
	{
		mGameAudio.Initialize(mAudioSubsystem, scope => GetAssetPath);
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
		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
		if (baseMat == null) return;

		mFloorMat = new MaterialInstance(baseMat);
		mFloorMat.SetColor("BaseColor", .(0.15f, 0.15f, 0.2f, 1.0f));
		mFloorMat.SetFloat("Metallic", 0.0f);
		mFloorMat.SetFloat("Roughness", 0.9f);

		mWallMat = new MaterialInstance(baseMat);
		mWallMat.SetColor("BaseColor", .(0.3f, 0.3f, 0.35f, 1.0f));
		mWallMat.SetFloat("Roughness", 0.7f);

		mPlayerMat = new MaterialInstance(baseMat);
		mPlayerMat.SetColor("BaseColor", .(0.2f, 0.5f, 1.0f, 1.0f));
		mPlayerMat.SetFloat("Metallic", 0.8f);
		mPlayerMat.SetFloat("Roughness", 0.2f);

		mGruntMat = new MaterialInstance(baseMat);
		mGruntMat.SetColor("BaseColor", .(0.9f, 0.2f, 0.15f, 1.0f));
		mGruntMat.SetFloat("Roughness", 0.5f);

		mBruteMat = new MaterialInstance(baseMat);
		mBruteMat.SetColor("BaseColor", .(0.2f, 0.8f, 0.2f, 1.0f));
		mBruteMat.SetFloat("Roughness", 0.6f);

		mDasherMat = new MaterialInstance(baseMat);
		mDasherMat.SetColor("BaseColor", .(0.9f, 0.8f, 0.1f, 1.0f));
		mDasherMat.SetFloat("Metallic", 0.5f);
		mDasherMat.SetFloat("Roughness", 0.3f);

		let emissiveTex = mRenderSystem.MaterialSystem.WhiteTexture;

		mHealthPickupMat = new MaterialInstance(baseMat);
		mHealthPickupMat.SetColor("BaseColor", .(0.1f, 0.9f, 0.3f, 1.0f));
		mHealthPickupMat.SetFloat("Metallic", 0.6f);
		mHealthPickupMat.SetFloat("Roughness", 0.3f);
		mHealthPickupMat.SetTexture("EmissiveMap", emissiveTex);

		mSpeedPickupMat = new MaterialInstance(baseMat);
		mSpeedPickupMat.SetColor("BaseColor", .(0.1f, 0.8f, 1.0f, 1.0f));
		mSpeedPickupMat.SetFloat("Metallic", 0.7f);
		mSpeedPickupMat.SetFloat("Roughness", 0.2f);
		mSpeedPickupMat.SetTexture("EmissiveMap", emissiveTex);

		mShockPickupMat = new MaterialInstance(baseMat);
		mShockPickupMat.SetColor("BaseColor", .(0.7f, 0.2f, 1.0f, 1.0f));
		mShockPickupMat.SetFloat("Metallic", 0.6f);
		mShockPickupMat.SetFloat("Roughness", 0.3f);
		mShockPickupMat.SetTexture("EmissiveMap", emissiveTex);

		mEmpPickupMat = new MaterialInstance(baseMat);
		mEmpPickupMat.SetColor("BaseColor", .(1.0f, 0.9f, 0.2f, 1.0f));
		mEmpPickupMat.SetFloat("Metallic", 0.9f);
		mEmpPickupMat.SetFloat("Roughness", 0.1f);
		mEmpPickupMat.SetTexture("EmissiveMap", emissiveTex);
	}

	private void CreateScene()
	{
		mMainScene = mSceneSubsystem.CreateScene("ArenaScene");
		mSceneSubsystem.SetActiveScene(mMainScene);

		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		if (renderModule == null) return;

		// Camera - fixed top-down
		mCameraEntity = mMainScene.CreateEntity();
		renderModule.CreatePerspectiveCamera(mCameraEntity,
			Math.PI_f / 4.0f,
			(float)mSwapChain.Width / mSwapChain.Height,
			0.1f, 100.0f);
		renderModule.SetMainCamera(mCameraEntity);

		var camTransform = mMainScene.GetTransform(mCameraEntity);
		camTransform.Position = .(0, 32, 4);
		mMainScene.SetTransform(mCameraEntity, camTransform);

		// Sun light - set transform first so direction is derived from it
		mSunEntity = mMainScene.CreateEntity();
		var sunTransform = mMainScene.GetTransform(mSunEntity);
		sunTransform.Rotation = Quaternion.CreateFromYawPitchRoll(0.3f, -0.8f, 0);
		mMainScene.SetTransform(mSunEntity, sunTransform);
		renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.95f, 0.9f), 2.0f);
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

		// Player dash trail emitter
		let trailHandle = renderModule.CreateCPUParticleEmitter(mPlayer.Entity, 64);
		if (trailHandle.IsValid)
		{
			if (let proxy = renderModule.GetParticleEmitterProxy(mPlayer.Entity))
			{
				proxy.BlendMode = .Additive;
				proxy.SpawnRate = 15;
				proxy.ParticleLifetime = 0.5f;
				proxy.StartSize = .(0.15f, 0.15f);
				proxy.EndSize = .(0.01f, 0.01f);
				proxy.StartColor = .(0.3f, 0.7f, 1.0f, 0.8f);
				proxy.EndColor = .(0.1f, 0.3f, 1.0f, 0.0f);
				proxy.InitialVelocity = .(0, 0.2f, 0);
				proxy.VelocityRandomness = .(0.5f, 0.3f, 0.5f);
				proxy.GravityMultiplier = 0;
				proxy.Drag = 2.0f;
				proxy.LifetimeVarianceMin = 0.7f;
				proxy.LifetimeVarianceMax = 1.0f;
				proxy.IsEnabled = true;
				proxy.IsEmitting = false; // Only emit when dashing
				proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.3f);
				mTrailInitialized = true;
			}
		}

		mEnemyManager.Initialize(mMainScene, renderModule, physicsModule,
			mSphereMeshHandle, mGruntMat, mBruteMat, mDasherMat);

		mEffectsManager.Initialize(mMainScene, renderModule);
		mPowerUpManager.Initialize(mMainScene, renderModule, mSphereMeshHandle,
			mHealthPickupMat, mSpeedPickupMat, mShockPickupMat, mEmpPickupMat);
		mHud.Initialize(mDebugFeature);
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
			mPlayer.Update(mMoveAction.Vector2Value, mDashAction.WasPressed, mDeltaTime);
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

	private void UpdatePlaying()
	{
		let playerPos = mPlayer.Position;
		mEnemyManager.Update(playerPos, mDeltaTime);
		mPowerUpManager.Update(mDeltaTime);

		// Dash trail - always on, changes color/intensity when dashing
		if (mTrailInitialized)
		{
			if (let renderModule = mMainScene.GetModule<RenderSceneModule>())
			{
				if (let proxy = renderModule.GetParticleEmitterProxy(mPlayer.Entity))
				{
					if (mPlayer.IsDashing)
					{
						proxy.SpawnRate = 50;
						proxy.StartColor = .(1.0f, 0.6f, 0.1f, 1.0f);
						proxy.EndColor = .(1.0f, 0.2f, 0.0f, 0.0f);
						proxy.StartSize = .(0.3f, 0.3f);
						proxy.EndSize = .(0.02f, 0.02f);
					}
					else
					{
						proxy.SpawnRate = 15;
						proxy.StartColor = .(0.3f, 0.6f, 1.0f, 0.5f);
						proxy.EndColor = .(0.1f, 0.3f, 0.8f, 0.0f);
						proxy.StartSize = .(0.15f, 0.15f);
						proxy.EndSize = .(0.01f, 0.01f);
					}
					proxy.IsEmitting = mPlayer.Speed > 1.0f;
				}
			}
		}

		// Invulnerability flash (pulse player base color)
		if (mPlayer.IsInvulnerable)
		{
			let pulse = (Math.Sin(mPlayer.InvulnTimer * 20.0f) + 1.0f) * 0.5f;
			let r = 0.2f + 0.8f * pulse;
			let g = 0.5f * (1.0f - pulse);
			let b = 1.0f * (1.0f - pulse);
			mPlayerMat.SetColor("BaseColor", .(r, g, b, 1.0f));
		}
		else
		{
			mPlayerMat.SetColor("BaseColor", .(0.2f, 0.5f, 1.0f, 1.0f));
		}

		// Combo display timer
		if (mComboDisplayTimer > 0)
			mComboDisplayTimer -= mDeltaTime;

		// Dash sound
		if (mPlayer.IsDashing && !mWasDashing)
			mGameAudio.PlayDash();

		// Check power-up pickup
		if (let pickupType = mPowerUpManager.CheckPickup(playerPos, mInventoryCount < MaxInventory))
		{
			mEffectsManager.SpawnPickupEffect(playerPos, pickupType);
			mGameAudio.PlayPickup();

			if (pickupType == .HealthPack)
			{
				// Health is always instant
				mPlayer.Heal(25.0f);
			}
			else if (mInventoryCount < MaxInventory)
			{
				// Store in inventory
				mInventory[mInventoryCount] = pickupType;
				mInventoryCount++;
			}
			// If inventory full, pickup is wasted (can't pick up more)
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

		// Combo bonus when dash ends
		if (mWasDashing && !mPlayer.IsDashing && mComboCount > 1)
		{
			mLastComboBonus = mComboCount * mComboCount * 10; // Quadratic bonus
			mScore += mLastComboBonus;
			mComboDisplayTimer = 2.0f;
			mGameAudio.PlayCombo();
		}
		if (!mPlayer.IsDashing)
			mComboCount = 0;
		mWasDashing = mPlayer.IsDashing;

		// Check player death
		if (!mPlayer.IsAlive)
		{
			mEffectsManager.SpawnPlayerDeathEffect(playerPos);
			mGameAudio.PlayPlayerDeath();
			mShakeIntensity = 1.5f;
			mEnemyManager.ClearAll();
			mState = .GameOver;
			if (mScore > mHighScore)
				mHighScore = mScore;
			return;
		}

		// Check wave complete
		if (mEnemyManager.AliveCount == 0)
		{
			mWave++;
			mScore += mWave * 100; // Wave completion bonus
			mWaveIntroTimer = 3.0f;
			mState = .WaveIntro;
		}
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
		mInventoryCount = 0;
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

		// Draw HUD
		if (mDebugFeature != null)
		{
			mHud.Draw(mState, mPlayer, mWave, mEnemyManager.AliveCount, mScore,
				mHighScore, mWaveIntroTimer, mSwapChain.Width, mSwapChain.Height,
				&mInventory[0], mInventoryCount, mActiveSlot);

			// Combo display (center screen, fades out)
			if (mComboDisplayTimer > 0 && mLastComboBonus > 0)
			{
				let alpha = (uint8)Math.Min(255, (int32)(mComboDisplayTimer * 200));
				let comboText = scope String();
				comboText.AppendF("COMBO +{}", mLastComboBonus);
				let cx = (float)mSwapChain.Width * 0.5f - 50;
				mDebugFeature.AddText2D(comboText, cx, (float)mSwapChain.Height * 0.35f,
					Color(255, 200, 50, alpha), 2.0f);
			}

			// Speed boost indicator
			if (mPlayer.HasSpeedBoost)
			{
				let boostX = (float)mSwapChain.Width * 0.5f - 40;
				mDebugFeature.AddText2D("SPEED BOOST", boostX, (float)mSwapChain.Height - 65,
					Color(50, 220, 255), 1.0f);
			}

			// FPS counter bottom-left
			let fpsText = scope String();
			fpsText.AppendF("FPS: {:.0}", mSmoothedFps);
			mDebugFeature.AddText2D(fpsText, 10, (float)mSwapChain.Height - 20,
				Color(150, 150, 150), 0.8f);

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
		return true;
	}

	protected override void OnShutdown()
	{
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

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		delete mRenderView;
		delete mRenderSystem;
	}
}

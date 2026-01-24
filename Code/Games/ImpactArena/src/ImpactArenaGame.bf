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
using Sedulous.Physics;
using Sedulous.Physics.Jolt;

class ImpactArenaGame : Application
{
	// Render system
	private RenderSystem mRenderSystem;
	private RenderView mRenderView;
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
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

	// Game objects
	private Arena mArena = new .() ~ delete _;
	private Player mPlayer = new .() ~ delete _;
	private EnemyManager mEnemyManager = new .() ~ delete _;
	private EffectsManager mEffectsManager = new .() ~ delete _;
	private HUD mHud = new .() ~ delete _;

	// Game state
	private GameState mState = .Title;
	private int32 mWave = 0;
	private int32 mScore = 0;
	private int32 mHighScore = 0;
	private float mWaveIntroTimer = 0;
	private float mDeltaTime = 0;
	private float mSmoothedFps = 60.0f;

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

		let inputSubsystem = new InputSubsystem();
		inputSubsystem.SetInputManager(mShell.InputManager);
		context.RegisterSubsystem(inputSubsystem);
	}

	protected override void OnContextStarted()
	{
		CreateMeshes();
		CreateMaterials();
		CreateScene();
		InitializeGameObjects();
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
		camTransform.Position = .(0, 32, 2);
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

		mEnemyManager.Initialize(mMainScene, renderModule, physicsModule,
			mSphereMeshHandle, mGruntMat, mBruteMat, mDasherMat);

		mEffectsManager.Initialize(mMainScene, renderModule);
		mHud.Initialize(mDebugFeature);
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;

		switch (mState)
		{
		case .Title:
			if (keyboard.IsKeyPressed(.Space))
				StartGame();
			if (keyboard.IsKeyPressed(.Escape))
				Exit();
		case .Playing, .WaveIntro:
			mPlayer.Update(keyboard, mDeltaTime);
			if (keyboard.IsKeyPressed(.Escape))
				mState = .Paused;
		case .GameOver:
			if (keyboard.IsKeyPressed(.Space))
				StartGame();
			if (keyboard.IsKeyPressed(.Escape))
				mState = .Title;
		case .Paused:
			if (keyboard.IsKeyPressed(.Escape))
				mState = .Playing;
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
		}

		// Spawn death effects and add score
		for (int32 i = 0; i < (int32)mDeathPositions.Count; i++)
		{
			mEffectsManager.SpawnDeathEffect(mDeathPositions[i], mDeathTypes[i]);
			mScore += GetScoreForEnemy(mDeathTypes[i]);
		}

		// Check player death
		if (!mPlayer.IsAlive)
		{
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
			mWaveIntroTimer = 2.0f;
			mState = .WaveIntro;
		}
	}

	private void UpdateWaveIntro()
	{
		mWaveIntroTimer -= mDeltaTime;
		if (mWaveIntroTimer <= 0)
		{
			mEnemyManager.SpawnWave(mWave);
			mState = .Playing;
		}
	}

	private void StartGame()
	{
		mState = .WaveIntro;
		mWave = 1;
		mScore = 0;
		mWaveIntroTimer = 2.0f;
		mPlayer.Reset();
		mEnemyManager.ClearAll();
		mEffectsManager.ClearAll();
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
				mHighScore, mWaveIntroTimer, mSwapChain.Width, mSwapChain.Height);

			// FPS counter bottom-left
			let fpsText = scope String();
			fpsText.AppendF("FPS: {:.0}", mSmoothedFps);
			mDebugFeature.AddText2D(fpsText, 10, (float)mSwapChain.Height - 20,
				Color(150, 150, 150), 0.8f);
		}

		// Update camera in render view
		let camPos = mMainScene.GetTransform(mCameraEntity).Position;
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

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		delete mRenderView;
		delete mRenderSystem;
	}
}

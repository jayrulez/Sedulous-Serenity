namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Render;
using Sedulous.Materials;
using Sedulous.Profiler;
using StormTactics.Battle;
using StormTactics.Core;

class StormTacticsGame : Application
{
	// Framework subsystems
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private Scene mMainScene;

	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderView mRenderView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private DebugRenderFeature mDebugFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Game state
	private GameState mGameState = .Loading;
	private BattleScene mBattleScene ~ delete _;

	// Test battle data (for demo — will be replaced by proper game flow)
	private ConfigDatabase mTestConfigs ~ delete _;
	private BattleSimulation mTestSim ~ delete _;

	// Timing
	private float mDeltaTime;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		Console.WriteLine("=== Storm Tactics ===");

		FixedTimeStep = 1.0f / 60.0f;
		MaxFixedStepsPerFrame = 3;

		// Initialize render system
		InitializeRenderSystem();

		// Register subsystems
		RegisterSubsystems(context);
	}

	private void InitializeRenderSystem()
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"),
			.BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
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
		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Ok)
		{
			let zenith = Color(60, 100, 160, 255);
			let horizon = Color(140, 170, 200, 255);
			mSkyFeature.CreateGradientSky(zenith, horizon, 32);
		}

		mDebugFeature = new DebugRenderFeature();
		mRenderSystem.RegisterFeature(mDebugFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void RegisterSubsystems(Context context)
	{
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);

		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);

		Console.WriteLine("Subsystems registered");
	}

	protected override void OnContextStarted()
	{
		SProfiler.Initialize();

		// Create main scene
		mMainScene = mSceneSubsystem.CreateScene("BattleScene");
		mSceneSubsystem.SetActiveScene(mMainScene);

		// Create a test battle for demo
		CreateTestBattle();

		mGameState = .Battle;
		Console.WriteLine("Storm Tactics initialized — entering battle demo");
	}

	/// Create a test battle with sample units for the demo.
	private void CreateTestBattle()
	{
		mTestConfigs = new ConfigDatabase();

		// --- Register test units ---
		let warrior = new UnitConfig();
		warrior.mId = 1;
		warrior.mName.Set("Warrior");
		warrior.mUnitClass = .Infantry;
		warrior.mSoldierHP = 120;
		warrior.mSoldierCount = 4;
		warrior.mSoldierDamage = 25;
		warrior.mDefense = 12;
		warrior.mAttackRange = 1;
		warrior.mMoveRange = 2;
		warrior.mActionSpeed = 80;
		warrior.mDamageType = .Physical;
		warrior.mModelName.Set("warrior");
		mTestConfigs.RegisterUnit(warrior);

		let archer = new UnitConfig();
		archer.mId = 2;
		archer.mName.Set("Archer");
		archer.mUnitClass = .Ranged;
		archer.mSoldierHP = 80;
		archer.mSoldierCount = 4;
		archer.mSoldierDamage = 30;
		archer.mDefense = 5;
		archer.mAttackRange = 3;
		archer.mMoveRange = 2;
		archer.mActionSpeed = 90;
		archer.mDamageType = .Physical;
		archer.mIsRanged = true;
		archer.mModelName.Set("archer");
		mTestConfigs.RegisterUnit(archer);

		let mage = new UnitConfig();
		mage.mId = 3;
		mage.mName.Set("Mage");
		mage.mUnitClass = .Mage;
		mage.mSoldierHP = 60;
		mage.mSoldierCount = 3;
		mage.mSoldierDamage = 40;
		mage.mDefense = 3;
		mage.mAttackRange = 2;
		mage.mMoveRange = 1;
		mage.mActionSpeed = 70;
		mage.mDamageType = .Magic;
		mage.mIsRanged = true;
		mage.mModelName.Set("mage");
		mTestConfigs.RegisterUnit(mage);

		let tank = new UnitConfig();
		tank.mId = 4;
		tank.mName.Set("Guardian");
		tank.mUnitClass = .Infantry;
		tank.mSoldierHP = 200;
		tank.mSoldierCount = 3;
		tank.mSoldierDamage = 15;
		tank.mDefense = 20;
		tank.mAttackRange = 1;
		tank.mMoveRange = 1;
		tank.mActionSpeed = 60;
		tank.mDamageType = .Physical;
		tank.mModelName.Set("guardian");
		mTestConfigs.RegisterUnit(tank);

		// --- Create formations ---
		// Attackers on left side (columns 0-1)
		let attackers = scope List<FormationSlot>();
		let a1 = scope FormationSlot(); a1.mUnitId = 1; a1.mGridX = 0; a1.mGridY = 1;
		let a2 = scope FormationSlot(); a2.mUnitId = 2; a2.mGridX = 1; a2.mGridY = 0;
		let a3 = scope FormationSlot(); a3.mUnitId = 3; a3.mGridX = 1; a3.mGridY = 2;
		let a4 = scope FormationSlot(); a4.mUnitId = 4; a4.mGridX = 0; a4.mGridY = 3;
		attackers.Add(a1); attackers.Add(a2); attackers.Add(a3); attackers.Add(a4);

		// Defenders on right side (columns 6-7)
		let defenders = scope List<FormationSlot>();
		let d1 = scope FormationSlot(); d1.mUnitId = 4; d1.mGridX = 7; d1.mGridY = 1;
		let d2 = scope FormationSlot(); d2.mUnitId = 1; d2.mGridX = 6; d2.mGridY = 0;
		let d3 = scope FormationSlot(); d3.mUnitId = 2; d3.mGridX = 6; d3.mGridY = 2;
		let d4 = scope FormationSlot(); d4.mUnitId = 3; d4.mGridX = 7; d4.mGridY = 3;
		defenders.Add(d1); defenders.Add(d2); defenders.Add(d3); defenders.Add(d4);

		// Create simulation
		mTestSim = new BattleSimulation(mTestConfigs);
		mTestSim.Initialize(attackers, defenders, 8, 5, 42);
		mTestSim.Difficulty = .Normal;

		Console.WriteLine("Test battle created: 4v4 on 8x5 grid");

		// Create the battle scene
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		mBattleScene = new BattleScene();
		mBattleScene.Initialize(mMainScene, renderModule, mRenderSystem, mDebugFeature, mTestSim, 1.0f);
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		if (mBattleScene != null)
			mBattleScene.HandleInput(keyboard, mouse, mDeltaTime);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = (float)frame.DeltaTime;

		if (mBattleScene != null)
			mBattleScene.Update(mDeltaTime);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		// Set active world from scene
		if (let renderModule = mMainScene?.GetModule<RenderSceneModule>())
		{
			if (let world = renderModule.World)
				mRenderSystem.SetActiveWorld(world);
		}

		// Draw battle overlays
		if (mBattleScene != null)
			mBattleScene.DrawOverlay(mSwapChain.Width, mSwapChain.Height);

		// Update camera from battle camera
		if (mBattleScene != null)
		{
			let cam = mBattleScene.Camera;
			mRenderView.CameraPosition = cam.Position;
			mRenderView.CameraForward = cam.Forward;
			mRenderView.CameraUp = .(0, 1, 0);
			mRenderView.Width = mSwapChain.Width;
			mRenderView.Height = mSwapChain.Height;
			mRenderView.UpdateMatrices(mDevice.FlipProjectionRequired);

			// Also update camera entity transform
			if (mMainScene != null)
			{
				// Update camera entity for the scene's RenderSceneModule
				// The RenderSceneModule reads the camera entity's transform
			}

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
		}

		// Build and execute render graph
		if (mRenderSystem.BuildRenderGraph(mRenderView) case .Ok)
			mRenderSystem.Execute(render.Encoder);

		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnShutdown()
	{
		Profiler.Shutdown();

		mBattleScene?.Shutdown();

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Storm Tactics shutting down");
	}
}

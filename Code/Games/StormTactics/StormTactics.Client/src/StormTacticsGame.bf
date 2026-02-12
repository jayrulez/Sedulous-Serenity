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
using Sedulous.Framework.Input;
using Sedulous.Framework.UI;
using Sedulous.Render;
using Sedulous.Materials;
using Sedulous.Profiler;
using Sedulous.Drawing.Fonts;
using Sedulous.Fonts;
using Sedulous.Fonts.TTF;
using Sedulous.GUI;
using StormTactics.Battle;
using StormTactics.Core;

class StormTacticsGame : Application
{
	// Framework subsystems
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private InputSubsystem mInputSubsystem;
	private UISubsystem mUISubsystem;
	private Scene mMainScene;

	// Render system
	private RenderSystem mRenderSystem;
	private RenderView mRenderView;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private DebugRenderFeature mDebugFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// UI
	private FontService mFontService;
	private GameTheme mGameTheme;
	private BattleHUD mBattleHUD;

	// Game state
	private GameState mGameState = .Loading;
	private BattleScene mBattleScene;

	// Test battle data (for demo — will be replaced by proper game flow)
	private ConfigDatabase mTestConfigs;
	private BattleSimulation mTestSim;

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

		// Input subsystem
		mInputSubsystem = new InputSubsystem();
		mInputSubsystem.SetInputManager(mShell.InputManager);
		context.RegisterSubsystem(mInputSubsystem);

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

		// Initialize UI (after battle scene so we can wire events)
		InitializeUI();

		mGameState = .Battle;
		Console.WriteLine("Storm Tactics initialized — entering battle demo");
	}

	private void InitializeUI()
	{
		// Initialize font service
		mFontService = new FontService();
		let fontPath = scope String();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		int32[6] fontSizes = .(14, 16, 18, 20, 24, 32);
		for (let size in fontSizes)
		{
			FontLoadOptions options = .ExtendedLatin;
			options.PixelHeight = size;
			if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
				Console.WriteLine("Failed to load font at size {}", size);
		}

		// Create and initialize UI subsystem
		mUISubsystem = new UISubsystem(mFontService);
		mContext.RegisterSubsystem(mUISubsystem);

		if (mUISubsystem.InitializeRendering(mDevice, .BGRA8UnormSrgb, FrameConfig.MAX_FRAMES_IN_FLIGHT, mShell, mWindow, mRenderSystem) case .Err)
		{
			Console.WriteLine("Failed to initialize UI rendering");
			return;
		}

		// Use GameTheme for dark UI with gold accents
		mGameTheme = new GameTheme();
		mUISubsystem.GUIContext.RegisterService<ITheme>(mGameTheme);

		// Create battle HUD
		mBattleHUD = new BattleHUD();
		mUISubsystem.GUIContext.RootElement = mBattleHUD.RootElement;

		// Wire HUD events
		mBattleHUD.OnAutoToggle.Subscribe(new () => {
			mBattleScene?.ToggleAutoPlay();
		});
		mBattleHUD.OnSkip.Subscribe(new () => {
			mBattleScene?.SkipAnimations();
		});
		mBattleHUD.OnStep.Subscribe(new () => {
			mBattleScene?.StepBattle();
		});
		mBattleHUD.OnSpeedChanged.Subscribe(new (speed) => {
			mBattleScene?.SetSpeed(speed);
		});

		Console.WriteLine("UI system initialized");
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

		// Only forward input to battle scene if UI didn't consume it
		if (mBattleScene != null && !(mInputSubsystem?.UIConsumedInput ?? false))
			mBattleScene.HandleInput(keyboard, mouse, mDeltaTime);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = (float)frame.DeltaTime;

		if (mBattleScene != null)
		{
			mBattleScene.Update(mDeltaTime);

			// Update hover detection (use view-projection from last frame)
			if (!(mInputSubsystem?.UIConsumedInput ?? false))
			{
				let mouse = mShell.InputManager.Mouse;
				mBattleScene.UpdateHover(mouse.X, mouse.Y, mSwapChain.Width, mSwapChain.Height,
					mRenderView.ViewProjectionMatrix);
			}
		}

		// Push battle state to HUD
		UpdateHUD();
	}

	private void UpdateHUD()
	{
		if (mBattleHUD == null || mBattleScene == null) return;

		let sim = mBattleScene.Simulation;
		if (sim == null) return;

		// Count alive units per side
		int32 attackersAlive = 0, defendersAlive = 0;
		for (int32 i = 0; i < sim.UnitCount; i++)
		{
			let unit = sim.GetUnit(i);
			if (unit != null && unit.mAlive)
			{
				if (unit.mForce == .Attacker) attackersAlive++;
				else defendersAlive++;
			}
		}

		mBattleHUD.UpdateTurnInfo(sim.TurnCount, attackersAlive, defendersAlive);

		// Update current unit info
		let curIdx = sim.CurrentUnitIndex;
		if (curIdx >= 0)
		{
			let unit = sim.GetUnit(curIdx);
			if (unit != null && unit.mAlive)
			{
				let className = scope String();
				unit.mConfig.mUnitClass.ToString(className);

				mBattleHUD.UpdateCurrentUnit(
					unit.mConfig.mName,
					unit.mCurrentHP,
					unit.mMaxHP,
					className,
					unit.mModifiedDamage,
					unit.mModifiedDefense,
					unit.mModifiedActionSpeed
				);
			}
			else
			{
				mBattleHUD.ClearCurrentUnit();
			}
		}
		else
		{
			mBattleHUD.ClearCurrentUnit();
		}

		// Update target info from hover
		if (mBattleScene.HoveredUnitIndex >= 0)
		{
			let targetUnit = sim.GetUnit(mBattleScene.HoveredUnitIndex);
			if (targetUnit != null && targetUnit.mAlive)
			{
				let targetClass = scope String();
				targetUnit.mConfig.mUnitClass.ToString(targetClass);
				mBattleHUD.UpdateTargetInfo(targetUnit.mConfig.mName, targetUnit.mCurrentHP, targetUnit.mMaxHP, targetClass);
			}
			else
			{
				mBattleHUD.ClearTargetInfo();
			}
		}
		else
		{
			mBattleHUD.ClearTargetInfo();
		}

		// Update auto-play state
		mBattleHUD.SetAutoPlaying(mBattleScene.IsAutoPlaying);

		// Show battle result
		if (sim.IsFinished)
		{
			let resultStr = scope String();
			switch (sim.State)
			{
			case .AttackerWins: resultStr.Set("ATTACKERS WIN!");
			case .DefenderWins: resultStr.Set("DEFENDERS WIN!");
			case .Draw: resultStr.Set("DRAW!");
			default: resultStr.Set("Battle Over");
			}
			mBattleHUD.ShowBattleResult(resultStr);
		}
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

		// Draw battle overlays (world-space: health bars, floating numbers, VFX)
		if (mBattleScene != null)
			mBattleScene.DrawOverlay();

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

		// Render UI overlay on top of 3D scene
		if (mUISubsystem != null)
		{
			mUISubsystem.RenderUI(render.Encoder, render.SwapChain.CurrentTextureView,
				mSwapChain.Width, mSwapChain.Height, render.Frame.FrameIndex);
		}

		return true;
	}

	protected override void OnShutdown()
	{
		Profiler.Shutdown();

		// Cleanup in dependency order:
		// 1. HUD — before UISubsystem is torn down by context
		delete mBattleHUD;
		mBattleHUD = null;

		// 2. Theme + font service — GUIContext doesn't take ownership
		delete mGameTheme;
		mGameTheme = null;
		delete mFontService;
		mFontService = null;

		// 3. BattleScene — references render system, debug feature, simulation
		mBattleScene?.Shutdown();
		delete mBattleScene;
		mBattleScene = null;

		// 4. Simulation — references config database
		delete mTestSim;
		mTestSim = null;

		// 5. Config data — standalone
		delete mTestConfigs;
		mTestConfigs = null;

		// 6. Render view — standalone
		delete mRenderView;
		mRenderView = null;

		// 7. Render system — owns features, must be last
		if (mRenderSystem != null)
			mRenderSystem.Shutdown();
		delete mRenderSystem;
		mRenderSystem = null;

		Console.WriteLine("Storm Tactics shutting down");
	}
}

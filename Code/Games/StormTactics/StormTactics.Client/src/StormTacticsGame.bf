namespace StormTactics.Client;

using System;
using System.Collections;
using System.IO;
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

	// Config database (loaded from XML, persists across battles)
	private ConfigDatabase mConfigs;

	// Current battle (created/destroyed per stage)
	private BattleSimulation mCurrentSim;
	private int32 mCurrentStageId;

	// HUD state tracking
	private PlayerTurnPhase mLastPlayerPhase = .Idle;
	private List<int32> mTurnOrderBuffer = new .() ~ delete _;

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

		// Load all configs from XML
		LoadConfigs();

		// Initialize UI
		InitializeUI();

		// Start at stage selection
		ShowStageSelect();
		Console.WriteLine("Storm Tactics initialized — showing stage select");
	}

	/// Load all game configs from XML data files.
	private void LoadConfigs()
	{
		mConfigs = new ConfigDatabase();
		let configPath = scope String();
		GetAssetPath("StormTactics/configs", configPath);

		if (mConfigs.LoadAll(configPath) case .Err)
		{
			Console.WriteLine("ERROR: Failed to load configs from {}", configPath);
			return;
		}

		mConfigs.Validate();
		Console.WriteLine("Configs loaded from XML");
	}

	/// Show the stage selection screen.
	private void ShowStageSelect()
	{
		// Destroy any existing battle
		DestroyBattle();

		mGameState = .Campaign;
		mLastPlayerPhase = .Idle;

		// Build stage info list from loaded configs
		let stageList = scope List<StageDisplayInfo>();
		for (let stage in mConfigs.Stages)
		{
			var info = StageDisplayInfo();
			info.mId = stage.mId;
			info.mName = stage.mName;
			info.mDifficulty = stage.mDifficulty;
			info.mEnemyCount = (int32)stage.mEnemyFormation.Count;
			stageList.Add(info);
		}

		// Sort by ID for consistent display order
		stageList.Sort(scope (a, b) => a.mId <=> b.mId);

		mBattleHUD.ShowStageSelect(stageList);
	}

	/// Create a battle for the given stage.
	private void CreateBattle(int32 stageId)
	{
		let stageConfig = mConfigs.GetStage(stageId);
		if (stageConfig == null)
		{
			Console.WriteLine("ERROR: Stage {} not found", stageId);
			return;
		}

		mCurrentStageId = stageId;

		// Create a default player formation (first 5 units: Footman, Knight, Archer, Wizard, Priest)
		let attackers = scope List<FormationSlot>();
		int32[5] playerUnits = .(1, 2, 3, 4, 5);
		int32 slotIdx = 0;
		for (let unitId in playerUnits)
		{
			if (mConfigs.GetUnit(unitId) == null) continue;
			let slot = scope :: FormationSlot();
			slot.mUnitId = unitId;
			// Arrange in a 2-column formation on the left
			slot.mGridX = (int32)(slotIdx / 3); // Column 0-1
			slot.mGridY = (int32)(slotIdx % 3); // Row 0-2
			attackers.Add(slot);
			slotIdx++;
		}

		// Determine grid size from stage enemy positions
		int32 maxCol = 7, maxRow = 3;
		for (let slot in stageConfig.mEnemyFormation)
		{
			if (slot.mGridX > maxCol) maxCol = slot.mGridX;
			if (slot.mGridY > maxRow) maxRow = slot.mGridY;
		}
		let columns = Math.Max(maxCol + 1, 8);
		let rows = Math.Max(maxRow + 1, 4);

		// Create simulation
		mCurrentSim = new BattleSimulation(mConfigs);
		mCurrentSim.Initialize(attackers, stageConfig.mEnemyFormation, columns, rows, DateTime.Now.Ticks);
		mCurrentSim.Difficulty = .Normal;

		Console.WriteLine("Battle created: Stage '{}' — {}v{} on {}x{} grid",
			stageConfig.mName, attackers.Count, stageConfig.mEnemyFormation.Count, columns, rows);

		// Create the battle scene
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		mBattleScene = new BattleScene();
		mBattleScene.Initialize(mMainScene, renderModule, mRenderSystem, mDebugFeature, mCurrentSim, 1.0f);

		// Enter deployment mode
		mBattleScene.EnterDeploymentMode();
		mBattleHUD.HideStageSelect();
		mBattleHUD.ShowDeploymentPanel();
		mBattleHUD.ResetResultState();
		mGameState = .BattlePrepare;
	}

	/// Destroy the current battle (clean up between stages).
	private void DestroyBattle()
	{
		if (mBattleScene != null)
		{
			mBattleScene.Shutdown();
			delete mBattleScene;
			mBattleScene = null;
		}

		if (mCurrentSim != null)
		{
			delete mCurrentSim;
			mCurrentSim = null;
		}
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
		mBattleHUD.OnAutoStepToggle.Subscribe(new () => {
			mBattleScene?.ToggleAutoStep();
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

		// Player action events
		mBattleHUD.OnMoveSelected.Subscribe(new () => {
			mBattleScene?.PlayerSelectMove();
		});
		mBattleHUD.OnAttackSelected.Subscribe(new () => {
			mBattleScene?.PlayerSelectAttack();
		});
		mBattleHUD.OnSkillSelected.Subscribe(new () => {
			mBattleScene?.PlayerSelectSkill();
		});
		mBattleHUD.OnWaitSelected.Subscribe(new () => {
			mBattleScene?.PlayerWait();
		});
		mBattleHUD.OnCancelAction.Subscribe(new () => {
			mBattleScene?.PlayerCancelAction();
		});
		mBattleHUD.OnUndoMove.Subscribe(new () => {
			mBattleScene?.PlayerUndoMove();
		});
		mBattleHUD.OnSkillChosen.Subscribe(new (skillId) => {
			mBattleScene?.PlayerChooseSkill(skillId);
		});
		mBattleHUD.OnStartBattle.Subscribe(new () => {
			if (mBattleScene != null && mBattleScene.IsDeploymentMode)
			{
				mBattleScene.StartBattle();
				mBattleHUD.HideDeploymentPanel();
				mGameState = .Battle;
				Console.WriteLine("Deployment complete — battle started!");
			}
		});
		mBattleHUD.OnStageSelected.Subscribe(new (stageId) => {
			CreateBattle(stageId);
		});
		mBattleHUD.OnContinue.Subscribe(new () => {
			ShowStageSelect();
		});

		Console.WriteLine("UI system initialized");
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
		{
			// Escape during battle returns to stage select; from stage select, exits
			if (mGameState == .Campaign)
				Exit();
			else
				ShowStageSelect();
			return;
		}

		// Check if mouse is over an interactive UI element
		let hitElement = mUISubsystem?.GUIContext?.HitTest(mouse.X, mouse.Y);
		bool uiHovered = hitElement != null;

		if (mBattleScene != null && !uiHovered)
		{
			mBattleScene.HandleInput(keyboard, mouse, mDeltaTime);

			if (mouse.IsButtonPressed(.Left) && mBattleScene.HasHoveredHex)
			{
				if (mBattleScene.IsDeploymentMode)
				{
					// Deployment: click to select/swap/move units
					mBattleScene.DeploymentClickHex(mBattleScene.HoveredHex);
				}
				else if (mBattleScene.IsPlayerTurn)
				{
					// Battle: forward hex click for player action
					mBattleScene.PlayerClickHex(mBattleScene.HoveredHex);
				}
			}
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = (float)frame.DeltaTime;

		if (mBattleScene != null)
		{
			mBattleScene.Update(mDeltaTime);

			// Update hover detection — only when mouse is not over a UI element
			let mouse = mShell.InputManager.Mouse;
			let hitElement = mUISubsystem?.GUIContext?.HitTest(mouse.X, mouse.Y);
			bool uiHovered = hitElement != null;
			if (!uiHovered)
			{
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

		// During deployment, update hint and unit hover — skip rest of battle HUD
		if (mBattleScene.IsDeploymentMode)
		{
			if (mBattleScene.DeploySelectedUnit >= 0)
			{
				let selUnit = sim.GetUnit(mBattleScene.DeploySelectedUnit);
				if (selUnit != null)
				{
					let hint = scope String();
					hint.AppendF("{} selected — click a hex to place or another unit to swap.", selUnit.mConfig.mName);
					mBattleHUD.UpdateDeploymentHint(hint);
				}
			}
			else
			{
				mBattleHUD.UpdateDeploymentHint("Click a unit to select, then click a hex to move or another unit to swap.");
			}

			// Show unit info on hover during deployment
			if (mBattleScene.HoveredUnitIndex >= 0)
			{
				let hoveredUnit = sim.GetUnit(mBattleScene.HoveredUnitIndex);
				if (hoveredUnit != null && hoveredUnit.mAlive)
				{
					let className = scope String();
					hoveredUnit.mConfig.mUnitClass.ToString(className);

					let forceTag = hoveredUnit.mForce == .Attacker ? " [ATK]" : " [DEF]";
					let nameStr = scope String();
					nameStr.AppendF("{}{}", hoveredUnit.mConfig.mName, forceTag);

					mBattleHUD.UpdateCurrentUnit(
						nameStr,
						hoveredUnit.mCurrentHP,
						hoveredUnit.mMaxHP,
						className,
						hoveredUnit.mModifiedDamage,
						hoveredUnit.mModifiedDefense,
						hoveredUnit.mModifiedActionSpeed
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

			// Show unit counts in top bar during deployment
			int32 atkCount = 0, defCount = 0;
			for (int32 i = 0; i < sim.UnitCount; i++)
			{
				let unit = sim.GetUnit(i);
				if (unit != null && unit.mAlive)
				{
					if (unit.mForce == .Attacker) atkCount++;
					else defCount++;
				}
			}
			mBattleHUD.UpdateTurnInfo(0, atkCount, defCount);
			return;
		}

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

		// Update turn order bar
		if (!sim.IsFinished)
		{
			sim.PredictTurnOrder(12, mTurnOrderBuffer);
			var entries = scope TurnOrderEntry[mTurnOrderBuffer.Count];
			for (int32 i = 0; i < (int32)mTurnOrderBuffer.Count; i++)
			{
				let unitIdx = mTurnOrderBuffer[i];
				let unit = sim.GetUnit(unitIdx);
				entries[i].mName = unit.mConfig.mName;
				entries[i].mIsAttacker = unit.mForce == .Attacker;
				entries[i].mIsCurrent = (i == 0);
			}
			mBattleHUD.UpdateTurnOrder(entries);
		}

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
		mBattleHUD.SetAutoStepping(mBattleScene.IsAutoStepping);

		// Update player turn phase UI — only on phase transitions to avoid
		// rebuilding dynamic UI (skill buttons) every frame
		let currentPhase = mBattleScene.PlayerPhase;
		if (currentPhase != mLastPlayerPhase)
		{
			mLastPlayerPhase = currentPhase;
			switch (currentPhase)
			{
			case .ChoosingAction:
				let canMove = mBattleScene.ReachableCells.Count > 0;
				let canAttack = mBattleScene.AttackableUnits.Count > 0;
				let hasSkills = mBattleScene.UsableSkills.Count > 0;
				mBattleHUD.ShowActionPanel(canMove, canAttack, hasSkills);
			case .PostMove:
				let postCanAttack = mBattleScene.AttackableUnits.Count > 0;
				let postHasSkills = mBattleScene.UsableSkills.Count > 0;
				mBattleHUD.ShowActionPanel(false, postCanAttack, postHasSkills, isPostMove: true);
			case .SelectingMoveTarget:
				mBattleHUD.ShowSelectingMode("Click a green tile to move");
			case .SelectingAttackTarget:
				mBattleHUD.ShowSelectingMode("Click an enemy to attack");
			case .SelectingSkill:
				// Build skill display list
				{
					let playerIdx = mBattleScene.PlayerUnitIndex;
					let playerUnit = sim.GetUnit(playerIdx);
					var skills = scope SkillDisplayInfo[playerUnit.mConfig.mSkillIds.Count];
					int32 skillCount = 0;

					for (let skillId in playerUnit.mConfig.mSkillIds)
					{
						let skillCfg = sim.Configs.GetSkill(skillId);
						if (skillCfg == null) continue;
						if (skillCfg.mMoment != .OnActionBegin) continue;

						var info = SkillDisplayInfo();
						info.mId = skillId;
						info.mName = skillCfg.mName;
						info.mCooldownLeft = playerUnit.mSkillCooldowns.ContainsKey(skillId) ? playerUnit.mSkillCooldowns[skillId] : 0;
						info.mUsable = mBattleScene.UsableSkills.Contains(skillId);
						if (skillCount < skills.Count)
							skills[skillCount++] = info;
					}
					mBattleHUD.ShowSkillPanel(skills[0..<skillCount]);
				}
			case .SelectingSkillTarget:
				mBattleHUD.ShowSelectingMode("Click a target for skill");
			default:
				mBattleHUD.HideActionPanel();
			}
		}

		// Show battle result
		if (sim.IsFinished)
		{
			let result = sim.GetResult();
			defer delete result;

			let resultStr = scope String();
			switch (sim.State)
			{
			case .AttackerWins: resultStr.Set("VICTORY!");
			case .DefenderWins: resultStr.Set("DEFEAT");
			case .Draw: resultStr.Set("DRAW");
			default: resultStr.Set("Battle Over");
			}
			mBattleHUD.ShowBattleResult(resultStr, result.mStarRating, result.mTotalTurns,
				(int32)result.mSurvivingAttackers.Count, result.mTotalAttackers,
				result.mTotalDamageDealt, result.mTotalHealingDone, result.mUnitsKilled);
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

		// 3. Battle scene + simulation
		DestroyBattle();

		// 4. Config data — standalone
		delete mConfigs;
		mConfigs = null;

		// 5. Render view — standalone
		delete mRenderView;
		mRenderView = null;

		// 6. Render system — owns features, must be last
		if (mRenderSystem != null)
			mRenderSystem.Shutdown();
		delete mRenderSystem;
		mRenderSystem = null;

		Console.WriteLine("Storm Tactics shutting down");
	}
}

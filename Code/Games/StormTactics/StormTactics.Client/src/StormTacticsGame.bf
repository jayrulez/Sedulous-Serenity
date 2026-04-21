namespace StormTactics.Client;

using System;
using System.Collections;
using System.IO;
using Sedulous.Shell.Input;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Runtime.Client;
using Sedulous.Runtime;
using Sedulous.Engine.Scenes;
using Sedulous.Engine.Render;
using Sedulous.Engine.Input;
using Sedulous.GUI.Runtime;
using Sedulous.Render;
using Sedulous.Materials;
using Sedulous.Profiler;
using Sedulous.Fonts;
using Sedulous.GUI;
using StormTactics.Battle;
using StormTactics.Core;
using StormTactics.Game;

class StormTacticsGame : Application
{
	// Framework subsystems
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private InputSubsystem mInputSubsystem;
	private Sedulous.GUI.Runtime.GUISubsystem mUISubsystem;
	private Scene mMainScene;

	// Render system
	private RenderSystem mRenderSystem;
	private RenderView mRenderView;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private OverlayRenderFeature mOverlayFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// UI
	private BattleHUD mBattleHUD;
	private CityHubScreen mCityHubScreen;
	private RosterScreen mRosterScreen;
	private InventoryScreen mInventoryScreen;
	private EquipSelectPopup mEquipSelectPopup;
	private ShopScreen mShopScreen;
	private GachaScreen mGachaScreen;
	private FormationScreen mFormationScreen;
	private SettingsScreen mSettingsScreen;
	private CampaignScreen mCampaignScreen;
	private DailyChallengeScreen mDailyChallengeScreen;
	private BossRushScreen mBossRushScreen;
	private TowerScreen mTowerScreen;
	private CrusadeScreen mCrusadeScreen;
	private ToastNotification mToast;
	private UnitSelectPopup mUnitSelectPopup;

	// Deferred sky setup (must happen after first BeginFrame flushes the init transfer batch)
	private bool mNeedsSkySetup = true;

	// Game state
	private GameState mGameState = .Loading;
	private BattleScene mBattleScene;

	// Config database (loaded from XML, persists across battles)
	private ConfigDatabase mConfigs;

	// Server mode (default: on)
	private bool mServerMode = true;
	private String mServerHost = new .("127.0.0.1") ~ delete _;
	private uint16 mServerPort = 8080;
	private ServerSaveManager mServerSaveManager;
	private LoginScreen mLoginScreen;

	/// Enable server mode with the specified host and port.
	public void SetServerMode(StringView host, uint16 port)
	{
		mServerMode = true;
		mServerHost.Set(host);
		mServerPort = port;
	}

	/// Disable server mode (use local saves).
	public void SetLocalMode()
	{
		mServerMode = false;
	}

	// Metagame systems
	private SaveManager mSaveManager;
	private PlayerManager mPlayerManager;
	private InventoryManager mInventoryManager;
	private RewardProcessor mRewardProcessor;
	private RosterManager mRosterManager;
	private EquipmentManager mEquipmentManager;
	private ShopManager mShopManager;
	private GachaManager mGachaManager;
	private FormationManager mFormationManager;
	private DailyChallengeManager mDailyChallengeManager;
	private BossRushManager mBossRushManager;
	private TowerManager mTowerManager;
	private CrusadeManager mCrusadeManager;

	// Current battle (created/destroyed per stage)
	private BattleSimulation mCurrentSim;
	private int32 mCurrentStageId;
	private bool mRewardsProcessed;
	private bool mCurrentBattleHardMode;
	private int32 mCurrentChallengeIndex = -1; // -1 = not a challenge battle
	private int32 mCurrentBossIndex = -1;      // -1 = not a boss battle
	private int32 mCurrentTowerFloor = -1;     // -1 = not a tower battle
	private int32 mCurrentCrusadeWave = -1;    // -1 = not a crusade battle

	// HUD state tracking
	private PlayerTurnPhase mLastPlayerPhase = .Idle;
	private List<int32> mTurnOrderBuffer = new .() ~ delete _;

	// Deployment roster state
	private int32 mDeployRosterSelectedUnitId = -1;
	private bool mDeployRosterDirty;

	// Timing
	private float mDeltaTime;

	public this() : base()
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
		if (mRenderSystem.Initialize(mDevice, mSwapChain.Width, mSwapChain.Height, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), null,
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
		mRenderSystem.RegisterFeature(mSkyFeature);

		mOverlayFeature = new OverlayRenderFeature();
		mRenderSystem.RegisterFeature(mOverlayFeature);

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

		// Initialize UI first (needed for login screen in server mode)
		InitializeUI();

		if (mServerMode)
		{
			// Server mode: show login screen, defer metagame init until auth
			mServerSaveManager = new ServerSaveManager();
			mServerSaveManager.Initialize(mServerHost, mServerPort);

			mLoginScreen = new LoginScreen();
			mLoginScreen.SetCallbacks(mServerSaveManager);
			mLoginScreen.OnLoginSuccess.Subscribe(new () =>
			{
				// Auth succeeded — now initialize metagame with server data
				InitializeMetagame();
				ShowCityHub();
				Console.WriteLine("Storm Tactics initialized — logged in to server");
			});

			mUISubsystem.GUIContext.RootElement = mLoginScreen.RootElement;
			Console.WriteLine("Storm Tactics initialized — showing login screen");
		}
		else
		{
			// Local mode: initialize metagame and go straight to city hub
			InitializeMetagame();
			ShowCityHub();
			Console.WriteLine("Storm Tactics initialized — showing city hub");
		}
	}

	/// Get the active PlayerSaveData from whichever save system is in use.
	private PlayerSaveData GetSaveData()
	{
		if (mServerMode)
			return mServerSaveManager.SaveData;
		return mSaveManager.SaveData;
	}

	/// Save via whichever save system is active.
	private void DoSave()
	{
		if (mServerMode)
			mServerSaveManager.Save();
		else
			mSaveManager?.Save();
	}

	/// Initialize save/progression/inventory/reward systems.
	private void InitializeMetagame()
	{
		if (!mServerMode)
		{
			// Local save manager — handles load/save to XML file
			mSaveManager = new SaveManager();
			let savePath = scope String();
			GetAssetPath("", savePath);
			mSaveManager.Initialize(savePath);
		}

		let saveData = GetSaveData();

		// Player manager — EXP, stamina, currencies, stage tracking
		mPlayerManager = new PlayerManager();
		mPlayerManager.Initialize(saveData, mConfigs);

		// Inventory manager — item add/remove with stacking
		mInventoryManager = new InventoryManager();
		mInventoryManager.Initialize(saveData, mConfigs);

		// Equipment manager — equip/unequip, stat bonuses, enhancement
		mEquipmentManager = new EquipmentManager();
		mEquipmentManager.Initialize(saveData, mConfigs);

		// Roster manager — unit ownership, star upgrades, effective stats
		mRosterManager = new RosterManager();
		mRosterManager.Initialize(saveData, mConfigs);
		mRosterManager.SetEquipmentManager(mEquipmentManager);

		// Wire cross-manager dependencies
		mInventoryManager.SetManagers(mPlayerManager, mRosterManager);
		mEquipmentManager.SetManagers(mPlayerManager, mInventoryManager);

		// Shop manager — purchase logic, limits, daily refresh
		mShopManager = new ShopManager();
		mShopManager.Initialize(saveData, mConfigs, mPlayerManager, mInventoryManager);

		// Formation manager — preset management
		mFormationManager = new FormationManager();
		mFormationManager.Initialize(saveData, mConfigs);

		// Gacha manager — summoning, pity system
		mGachaManager = new GachaManager();
		mGachaManager.Initialize(saveData, mConfigs, mPlayerManager, mRosterManager);

		// Reward processor — post-battle reward calculation
		mRewardProcessor = new RewardProcessor();
		mRewardProcessor.Initialize(mPlayerManager, mInventoryManager, mConfigs);

		// Daily challenge manager — rotating restricted battles
		mDailyChallengeManager = new DailyChallengeManager();
		mDailyChallengeManager.Initialize(saveData, mConfigs);

		// Boss rush manager — powerful bosses with phase transitions
		mBossRushManager = new BossRushManager();
		mBossRushManager.Initialize(saveData, mConfigs);

		// Tower manager — sequential floors with persistent HP, daily reset
		mTowerManager = new TowerManager();
		mTowerManager.Initialize(saveData, mConfigs);

		// Crusade manager — sequential waves with persistent HP, weekly reset
		mCrusadeManager = new CrusadeManager();
		mCrusadeManager.Initialize(saveData, mConfigs);

		// Process stamina regen from offline time and check shop refresh
		mPlayerManager.UpdateStaminaRegen();
		mShopManager.CheckRefresh();

		Console.WriteLine("Metagame systems initialized");
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

	/// Show the city hub screen.
	private void ShowCityHub()
	{
		DestroyBattle();
		mGameState = .City;
		mLastPlayerPhase = .Idle;

		// Process stamina regen from elapsed time
		mPlayerManager.UpdateStaminaRegen();

		// Switch UI root to city hub
		if (mCityHubScreen != null)
		{
			mUISubsystem.GUIContext.RootElement = mCityHubScreen.RootElement;
			UpdateCityHubInfo();
		}

		// Auto-save when returning to city
		DoSave();
	}

	/// Update city hub player info display.
	private void UpdateCityHubInfo()
	{
		if (mCityHubScreen == null) return;
		let save = GetSaveData();
		mCityHubScreen.UpdatePlayerInfo(
			save.mHeroLevel,
			save.mHeroExp,
			mPlayerManager.ExpToNextLevel,
			save.mGold,
			save.mGems,
			save.mStamina,
			mPlayerManager.MaxStamina
		);
	}

	/// Show the unit roster screen.
	private void ShowRoster()
	{
		mGameState = .UnitManagement;
		mUISubsystem.GUIContext.RootElement = mRosterScreen.RootElement;
		mRosterScreen.Refresh(GetSaveData(), mConfigs, mRosterManager, mEquipmentManager);
	}

	/// Show the inventory screen.
	private void ShowInventory()
	{
		mGameState = .Inventory;
		mUISubsystem.GUIContext.RootElement = mInventoryScreen.RootElement;
		mInventoryScreen.Refresh(GetSaveData(), mConfigs, mInventoryManager);
	}

	/// Show the shop screen.
	private void ShowShop()
	{
		mGameState = .City; // Reuse City state for shop
		mShopManager.CheckRefresh();
		mUISubsystem.GUIContext.RootElement = mShopScreen.RootElement;
		mShopScreen.Refresh(GetSaveData(), mConfigs, mShopManager);
	}

	/// Show the formation screen.
	private void ShowFormation()
	{
		mGameState = .Formation;
		mUISubsystem.GUIContext.RootElement = mFormationScreen.RootElement;
		mFormationScreen.Show(GetSaveData(), mConfigs, mFormationManager, mPlayerManager.MaxFormationSlots, mRosterManager);
	}

	/// Show the gacha screen.
	private void ShowGacha()
	{
		mGameState = .Gacha;
		mUISubsystem.GUIContext.RootElement = mGachaScreen.RootElement;
		mGachaScreen.Refresh(GetSaveData());
	}

	/// Show the settings screen.
	private void ShowSettings()
	{
		mGameState = .Settings;
		mUISubsystem.GUIContext.RootElement = mSettingsScreen.RootElement;
		mSettingsScreen.Refresh(GetSaveData().mGameSettings);
	}

	/// Show the campaign screen with chapter tabs and stage selection.
	private void ShowStageSelect()
	{
		// Destroy any existing battle
		DestroyBattle();

		mGameState = .Campaign;
		mLastPlayerPhase = .Idle;

		// Switch UI root to campaign screen
		mUISubsystem.GUIContext.RootElement = mCampaignScreen.RootElement;
		mCampaignScreen.Show(mConfigs, mPlayerManager, GetSaveData());
	}

	/// Show the daily challenge screen.
	private void ShowDailyChallenges()
	{
		DestroyBattle();
		mDailyChallengeManager.CheckDailyReset();
		mGameState = .DailyChallenge;
		mUISubsystem.GUIContext.RootElement = mDailyChallengeScreen.RootElement;
		mDailyChallengeScreen.Show(mDailyChallengeManager);
	}

	/// Show the boss rush selection screen.
	private void ShowBossRush()
	{
		DestroyBattle();
		mGameState = .BossRush;
		mUISubsystem.GUIContext.RootElement = mBossRushScreen.RootElement;
		mBossRushScreen.Show(mBossRushManager);
	}

	/// Show the tower floor selection screen.
	private void ShowTower()
	{
		DestroyBattle();
		mTowerManager.CheckDailyReset();
		mGameState = .Tower;
		mUISubsystem.GUIContext.RootElement = mTowerScreen.RootElement;
		mTowerScreen.Show(mTowerManager);
	}

	/// Show the crusade wave selection screen.
	private void ShowCrusade()
	{
		DestroyBattle();
		mCrusadeManager.CheckWeeklyReset();
		mGameState = .Crusade;
		mUISubsystem.GUIContext.RootElement = mCrusadeScreen.RootElement;
		mCrusadeScreen.Show(mCrusadeManager);
	}

	/// Create a battle for the given stage.
	private void CreateBattle(int32 stageId, bool isHardMode = false)
	{
		let stageConfig = mConfigs.GetStage(stageId);
		if (stageConfig == null)
		{
			Console.WriteLine("ERROR: Stage {} not found", stageId);
			return;
		}

		// Check stage unlock
		if (!mPlayerManager.IsStageUnlocked(stageId))
		{
			Console.WriteLine("Stage {} is locked", stageId);
			return;
		}

		// Check stamina availability (but don't spend yet — spend when battle starts)
		if (GetSaveData().mStamina < stageConfig.mStaminaCost)
		{
			Console.WriteLine("Not enough stamina for stage {} (need {}, have {})",
				stageId, stageConfig.mStaminaCost, GetSaveData().mStamina);
			return;
		}

		mCurrentStageId = stageId;
		mCurrentBattleHardMode = isHardMode;
		mCurrentChallengeIndex = -1;
		mCurrentBossIndex = -1;
		mCurrentTowerFloor = -1;
		mCurrentCrusadeWave = -1;
		mRewardsProcessed = false;

		// Build player formation from active formation preset (or fallback to owned units)
		let attackers = scope List<FormationSlot>();
		let save = GetSaveData();

		if (save.mFormationPresets.Count > 0 && save.mActiveFormationIndex < (int32)save.mFormationPresets.Count)
		{
			let preset = save.mFormationPresets[save.mActiveFormationIndex];
			for (let fSlot in preset.mSlots)
			{
				if (mConfigs.GetUnit(fSlot.mUnitId) == null) continue;
				if (save.GetOwnedUnit(fSlot.mUnitId) == null) continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = fSlot.mUnitId;
				slot.mGridX = fSlot.mGridX;
				slot.mGridY = fSlot.mGridY;
				attackers.Add(slot);
			}
		}

		// Fallback: if no valid formation, use all owned units
		if (attackers.Count == 0)
		{
			int32 slotIdx = 0;
			for (let owned in save.mOwnedUnits)
			{
				if (mConfigs.GetUnit(owned.mUnitId) == null) continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = owned.mUnitId;
				slot.mGridX = (int32)(slotIdx / 3);
				slot.mGridY = (int32)(slotIdx % 3);
				attackers.Add(slot);
				slotIdx++;
				if (slotIdx >= mPlayerManager.MaxFormationSlots) break;
			}
		}

		// Determine grid size from stage enemy positions
		int32 maxCol = 7, maxRow = 3;
		for (let slot in stageConfig.mEnemyFormation)
		{
			if (slot.mGridX > maxCol) maxCol = slot.mGridX;
			if (slot.mGridY > maxRow) maxRow = slot.mGridY;
		}
		let columns = Math.Max(maxCol + 1, BattleConstants.MIN_COLUMNS);
		let rows = Math.Max(maxRow + 1, BattleConstants.MIN_ROWS);

		// Create simulation
		mCurrentSim = new BattleSimulation(mConfigs);
		mCurrentSim.Initialize(attackers, stageConfig.mEnemyFormation, columns, rows, DateTime.Now.Ticks);
		if (isHardMode)
		{
			mCurrentSim.ApplyDefenderScaling(1.5f, 1.5f, 1.5f);
			mCurrentSim.Difficulty = .Hard;
		}
		else
		{
			mCurrentSim.Difficulty = .Normal;
		}
		StampUnitLevels();

		Console.WriteLine("Battle created: Stage '{}'{} — {}v{} on {}x{} grid",
			stageConfig.mName, isHardMode ? " [HARD]" : "", attackers.Count, stageConfig.mEnemyFormation.Count, columns, rows);

		// Create the battle scene
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		mBattleScene = new BattleScene();
		mBattleScene.Initialize(mMainScene, renderModule, mRenderSystem, mOverlayFeature, mCurrentSim, 1.0f);

		// Apply user settings to battle scene
		let settings = GetSaveData().mGameSettings;
		mBattleScene.ApplySettings(settings.mAutoStepDefault, settings.mAutoBattleDefault, (float)settings.mDefaultBattleSpeed, settings.mInvertCameraPan);

		// Enter deployment mode
		mBattleScene.EnterDeploymentMode();
		mBattleHUD.ShowDeploymentPanel();
		mBattleHUD.ResetResultState();
		mDeployRosterSelectedUnitId = -1;
		mDeployRosterDirty = true;
		mGameState = .BattlePrepare;
	}

	/// Create a battle for a daily challenge.
	private void CreateChallengeBattle(int32 challengeIndex)
	{
		if (mDailyChallengeManager.IsChallengeCompleted(challengeIndex))
		{
			ShowToast("Already completed today!");
			return;
		}

		let tmpl = mDailyChallengeManager.GetChallenge(challengeIndex);
		if (tmpl == null) return;

		let stageConfig = mConfigs.GetStage(tmpl.mStageId);
		if (stageConfig == null)
		{
			Console.WriteLine("ERROR: Challenge stage {} not found", tmpl.mStageId);
			return;
		}

		mCurrentChallengeIndex = challengeIndex;
		mCurrentStageId = tmpl.mStageId;
		mCurrentBattleHardMode = false;
		mRewardsProcessed = false;

		// Build player formation from active preset, filtered by challenge restriction
		let attackers = scope List<FormationSlot>();
		let save = GetSaveData();

		if (save.mFormationPresets.Count > 0 && save.mActiveFormationIndex < (int32)save.mFormationPresets.Count)
		{
			let preset = save.mFormationPresets[save.mActiveFormationIndex];
			for (let fSlot in preset.mSlots)
			{
				let unitConfig = mConfigs.GetUnit(fSlot.mUnitId);
				if (unitConfig == null) continue;
				if (save.GetOwnedUnit(fSlot.mUnitId) == null) continue;
				if (!mDailyChallengeManager.IsUnitAllowed(challengeIndex, unitConfig)) continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = fSlot.mUnitId;
				slot.mGridX = fSlot.mGridX;
				slot.mGridY = fSlot.mGridY;
				attackers.Add(slot);
			}
		}

		// Fallback: use all owned units that pass the restriction
		if (attackers.Count == 0)
		{
			int32 slotIdx = 0;
			for (let owned in save.mOwnedUnits)
			{
				let unitConfig = mConfigs.GetUnit(owned.mUnitId);
				if (unitConfig == null) continue;
				if (!mDailyChallengeManager.IsUnitAllowed(challengeIndex, unitConfig)) continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = owned.mUnitId;
				slot.mGridX = (int32)(slotIdx / 3);
				slot.mGridY = (int32)(slotIdx % 3);
				attackers.Add(slot);
				slotIdx++;
				if (slotIdx >= mPlayerManager.MaxFormationSlots) break;
			}
		}

		// Grid sizing from stage enemy positions
		int32 maxCol = 7, maxRow = 3;
		for (let slot in stageConfig.mEnemyFormation)
		{
			if (slot.mGridX > maxCol) maxCol = slot.mGridX;
			if (slot.mGridY > maxRow) maxRow = slot.mGridY;
		}
		let columns = Math.Max(maxCol + 1, BattleConstants.MIN_COLUMNS);
		let rows = Math.Max(maxRow + 1, BattleConstants.MIN_ROWS);

		// Create simulation
		mCurrentSim = new BattleSimulation(mConfigs);
		mCurrentSim.Initialize(attackers, stageConfig.mEnemyFormation, columns, rows, DateTime.Now.Ticks);

		// Apply difficulty scaling
		if (tmpl.mDifficultyScale > 1.0f)
			mCurrentSim.ApplyDefenderScaling(tmpl.mDifficultyScale, tmpl.mDifficultyScale, tmpl.mDifficultyScale);

		mCurrentSim.Difficulty = .Normal;
		StampUnitLevels();

		Console.WriteLine("Challenge battle created: '{}' — {}v{} on {}x{} grid (x{} difficulty)",
			tmpl.mName, attackers.Count, stageConfig.mEnemyFormation.Count, columns, rows, tmpl.mDifficultyScale);

		// Create battle scene
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		mBattleScene = new BattleScene();
		mBattleScene.Initialize(mMainScene, renderModule, mRenderSystem, mOverlayFeature, mCurrentSim, 1.0f);

		let settings = GetSaveData().mGameSettings;
		mBattleScene.ApplySettings(settings.mAutoStepDefault, settings.mAutoBattleDefault, (float)settings.mDefaultBattleSpeed, settings.mInvertCameraPan);

		// Switch to battle HUD and enter deployment
		mUISubsystem.GUIContext.RootElement = mBattleHUD.RootElement;
		mBattleScene.EnterDeploymentMode();
		mBattleHUD.ShowDeploymentPanel();
		mBattleHUD.ResetResultState();
		mDeployRosterSelectedUnitId = -1;
		mDeployRosterDirty = true;
		mGameState = .BattlePrepare;
	}

	/// Create a battle for a boss rush encounter.
	private void CreateBossBattle(int32 bossIndex)
	{
		let tmpl = mBossRushManager.GetBoss(bossIndex);
		if (tmpl == null) return;

		mCurrentBossIndex = bossIndex;
		mCurrentChallengeIndex = -1;
		mCurrentStageId = 0;
		mCurrentBattleHardMode = false;
		mRewardsProcessed = false;

		// Build player formation from active preset (no restrictions for bosses)
		let attackers = scope List<FormationSlot>();
		let save = GetSaveData();

		if (save.mFormationPresets.Count > 0 && save.mActiveFormationIndex < (int32)save.mFormationPresets.Count)
		{
			let preset = save.mFormationPresets[save.mActiveFormationIndex];
			for (let fSlot in preset.mSlots)
			{
				if (mConfigs.GetUnit(fSlot.mUnitId) == null) continue;
				if (save.GetOwnedUnit(fSlot.mUnitId) == null) continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = fSlot.mUnitId;
				slot.mGridX = fSlot.mGridX;
				slot.mGridY = fSlot.mGridY;
				attackers.Add(slot);
			}
		}

		// Fallback: use all owned units
		if (attackers.Count == 0)
		{
			int32 slotIdx = 0;
			for (let owned in save.mOwnedUnits)
			{
				if (mConfigs.GetUnit(owned.mUnitId) == null) continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = owned.mUnitId;
				slot.mGridX = (int32)(slotIdx / 3);
				slot.mGridY = (int32)(slotIdx % 3);
				attackers.Add(slot);
				slotIdx++;
				if (slotIdx >= mPlayerManager.MaxFormationSlots) break;
			}
		}

		// Enemy formation: single boss unit at center-right of grid
		let defenders = scope List<FormationSlot>();
		let bossSlot = scope :: FormationSlot();
		bossSlot.mUnitId = tmpl.mUnitId;
		bossSlot.mGridX = 6;
		bossSlot.mGridY = 1;
		defenders.Add(bossSlot);

		// Create simulation
		mCurrentSim = new BattleSimulation(mConfigs);
		mCurrentSim.Initialize(attackers, defenders, BattleConstants.DEFAULT_COLUMNS, BattleConstants.DEFAULT_ROWS, DateTime.Now.Ticks);

		// Apply boss scaling
		if (tmpl.mHPScale != 1.0f || tmpl.mDamageScale != 1.0f || tmpl.mDefenseScale != 1.0f)
			mCurrentSim.ApplyDefenderScaling(tmpl.mHPScale, tmpl.mDamageScale, tmpl.mDefenseScale);

		mCurrentSim.Difficulty = .Hard;
		StampUnitLevels();

		// Set boss phase transitions — find the boss unit index in the simulation
		int32 bossUnitIdx = -1;
		for (int32 i = 0; i < mCurrentSim.UnitCount; i++)
		{
			let unit = mCurrentSim.GetUnit(i);
			if (unit != null && unit.mForce == .Defender && unit.mConfig.mId == tmpl.mUnitId)
			{
				bossUnitIdx = i;
				break;
			}
		}
		if (bossUnitIdx >= 0)
		{
			mBossRushManager.ResetPhases(bossIndex);
			mCurrentSim.SetBossPhases(bossUnitIdx, tmpl.mPhases);
		}

		Console.WriteLine("Boss battle created: '{}' — {}v1 on default grid",
			tmpl.mName, attackers.Count);

		// Create battle scene
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		mBattleScene = new BattleScene();
		mBattleScene.Initialize(mMainScene, renderModule, mRenderSystem, mOverlayFeature, mCurrentSim, 1.0f);

		let settings = GetSaveData().mGameSettings;
		mBattleScene.ApplySettings(settings.mAutoStepDefault, settings.mAutoBattleDefault, (float)settings.mDefaultBattleSpeed, settings.mInvertCameraPan);

		// Switch to battle HUD and enter deployment
		mUISubsystem.GUIContext.RootElement = mBattleHUD.RootElement;
		mBattleScene.EnterDeploymentMode();
		mBattleHUD.ShowDeploymentPanel();
		mBattleHUD.ResetResultState();
		mDeployRosterSelectedUnitId = -1;
		mDeployRosterDirty = true;
		mGameState = .BattlePrepare;
	}

	/// Create a battle for a tower floor.
	private void CreateTowerBattle(int32 floorIndex)
	{
		let floor = mTowerManager.GetFloor(floorIndex);
		if (floor == null) return;

		mCurrentTowerFloor = floorIndex;
		mCurrentCrusadeWave = -1;
		mCurrentChallengeIndex = -1;
		mCurrentBossIndex = -1;
		mCurrentStageId = 0;
		mCurrentBattleHardMode = false;
		mRewardsProcessed = false;

		// Build player formation, filtering out dead units
		let attackers = scope List<FormationSlot>();
		let save = GetSaveData();

		if (save.mFormationPresets.Count > 0 && save.mActiveFormationIndex < (int32)save.mFormationPresets.Count)
		{
			let preset = save.mFormationPresets[save.mActiveFormationIndex];
			for (let fSlot in preset.mSlots)
			{
				if (mConfigs.GetUnit(fSlot.mUnitId) == null) continue;
				if (save.GetOwnedUnit(fSlot.mUnitId) == null) continue;
				if (mTowerManager.IsUnitDead(fSlot.mUnitId)) continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = fSlot.mUnitId;
				slot.mGridX = fSlot.mGridX;
				slot.mGridY = fSlot.mGridY;
				attackers.Add(slot);
			}
		}

		if (attackers.Count == 0)
		{
			int32 slotIdx = 0;
			for (let owned in save.mOwnedUnits)
			{
				if (mConfigs.GetUnit(owned.mUnitId) == null) continue;
				if (mTowerManager.IsUnitDead(owned.mUnitId)) continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = owned.mUnitId;
				slot.mGridX = (int32)(slotIdx / 3);
				slot.mGridY = (int32)(slotIdx % 3);
				attackers.Add(slot);
				slotIdx++;
				if (slotIdx >= mPlayerManager.MaxFormationSlots) break;
			}
		}

		// Grid sizing from floor enemy positions
		int32 maxCol = 7, maxRow = 3;
		for (let slot in floor.mEnemyFormation)
		{
			if (slot.mGridX > maxCol) maxCol = slot.mGridX;
			if (slot.mGridY > maxRow) maxRow = slot.mGridY;
		}
		let columns = Math.Max(maxCol + 1, BattleConstants.MIN_COLUMNS);
		let rows = Math.Max(maxRow + 1, BattleConstants.MIN_ROWS);

		// Create simulation
		mCurrentSim = new BattleSimulation(mConfigs);
		mCurrentSim.Initialize(attackers, floor.mEnemyFormation, columns, rows, DateTime.Now.Ticks);

		if (floor.mDifficultyScale > 1.0f)
			mCurrentSim.ApplyDefenderScaling(floor.mDifficultyScale, floor.mDifficultyScale, floor.mDifficultyScale);

		mCurrentSim.Difficulty = .Normal;
		StampUnitLevels();
		RestorePersistentHP();

		Console.WriteLine("Tower battle created: '{}' — {}v{} on {}x{} grid (x{} difficulty)",
			floor.mName, attackers.Count, floor.mEnemyFormation.Count, columns, rows, floor.mDifficultyScale);

		// Create battle scene
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		mBattleScene = new BattleScene();
		mBattleScene.Initialize(mMainScene, renderModule, mRenderSystem, mOverlayFeature, mCurrentSim, 1.0f);

		let settings = GetSaveData().mGameSettings;
		mBattleScene.ApplySettings(settings.mAutoStepDefault, settings.mAutoBattleDefault, (float)settings.mDefaultBattleSpeed, settings.mInvertCameraPan);

		// Switch to battle HUD and enter deployment
		mUISubsystem.GUIContext.RootElement = mBattleHUD.RootElement;
		mBattleScene.EnterDeploymentMode();
		mBattleHUD.ShowDeploymentPanel();
		mBattleHUD.ResetResultState();
		mDeployRosterSelectedUnitId = -1;
		mDeployRosterDirty = true;
		mGameState = .BattlePrepare;
	}

	/// Create a battle for a crusade wave.
	private void CreateCrusadeBattle(int32 waveIndex)
	{
		let wave = mCrusadeManager.GetWave(waveIndex);
		if (wave == null) return;

		let stageConfig = mCrusadeManager.GetWaveStage(waveIndex);
		if (stageConfig == null)
		{
			Console.WriteLine("ERROR: Crusade wave {} references missing stage {}", waveIndex, wave.mStageId);
			return;
		}

		mCurrentCrusadeWave = waveIndex;
		mCurrentTowerFloor = -1;
		mCurrentChallengeIndex = -1;
		mCurrentBossIndex = -1;
		mCurrentStageId = 0;
		mCurrentBattleHardMode = false;
		mRewardsProcessed = false;

		// Build player formation, filtering unavailable units (dead or pool exceeded)
		let attackers = scope List<FormationSlot>();
		let save = GetSaveData();

		if (save.mFormationPresets.Count > 0 && save.mActiveFormationIndex < (int32)save.mFormationPresets.Count)
		{
			let preset = save.mFormationPresets[save.mActiveFormationIndex];
			for (let fSlot in preset.mSlots)
			{
				if (mConfigs.GetUnit(fSlot.mUnitId) == null) continue;
				if (save.GetOwnedUnit(fSlot.mUnitId) == null) continue;
				if (!mCrusadeManager.IsUnitAvailable(fSlot.mUnitId)) continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = fSlot.mUnitId;
				slot.mGridX = fSlot.mGridX;
				slot.mGridY = fSlot.mGridY;
				attackers.Add(slot);
			}
		}

		if (attackers.Count == 0)
		{
			int32 slotIdx = 0;
			for (let owned in save.mOwnedUnits)
			{
				if (mConfigs.GetUnit(owned.mUnitId) == null) continue;
				if (!mCrusadeManager.IsUnitAvailable(owned.mUnitId)) continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = owned.mUnitId;
				slot.mGridX = (int32)(slotIdx / 3);
				slot.mGridY = (int32)(slotIdx % 3);
				attackers.Add(slot);
				slotIdx++;
				if (slotIdx >= mPlayerManager.MaxFormationSlots) break;
			}
		}

		// Build defender formation, filtering out dead enemies from previous attempts
		let defenders = scope List<FormationSlot>();
		for (int32 fi = 0; fi < (int32)stageConfig.mEnemyFormation.Count; fi++)
		{
			if (mCrusadeManager.IsDefenderDead(fi)) continue;
			let src = stageConfig.mEnemyFormation[fi];
			let slot = scope :: FormationSlot();
			slot.mUnitId = src.mUnitId;
			slot.mStarLevel = src.mStarLevel;
			slot.mGridX = src.mGridX;
			slot.mGridY = src.mGridY;
			defenders.Add(slot);
		}

		// Grid sizing from defender positions
		int32 maxCol = 7, maxRow = 3;
		for (let slot in defenders)
		{
			if (slot.mGridX > maxCol) maxCol = slot.mGridX;
			if (slot.mGridY > maxRow) maxRow = slot.mGridY;
		}
		let columns = Math.Max(maxCol + 1, BattleConstants.MIN_COLUMNS);
		let rows = Math.Max(maxRow + 1, BattleConstants.MIN_ROWS);

		// Create simulation
		mCurrentSim = new BattleSimulation(mConfigs);
		mCurrentSim.Initialize(attackers, defenders, columns, rows, DateTime.Now.Ticks);

		if (wave.mDifficultyScale > 1.0f)
			mCurrentSim.ApplyDefenderScaling(wave.mDifficultyScale, wave.mDifficultyScale, wave.mDifficultyScale);

		mCurrentSim.Difficulty = .Normal;
		StampUnitLevels();
		RestorePersistentHP();

		// Restore defender HP from previous attempts
		mCrusadeManager.RestoreDefenderHP(mCurrentSim);

		Console.WriteLine("Crusade battle created: '{}' (stage {}) — {}v{} on {}x{} grid (x{} difficulty)",
			wave.mName, wave.mStageId, attackers.Count, defenders.Count, columns, rows, wave.mDifficultyScale);

		// Create battle scene
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		mBattleScene = new BattleScene();
		mBattleScene.Initialize(mMainScene, renderModule, mRenderSystem, mOverlayFeature, mCurrentSim, 1.0f);

		let settings = GetSaveData().mGameSettings;
		mBattleScene.ApplySettings(settings.mAutoStepDefault, settings.mAutoBattleDefault, (float)settings.mDefaultBattleSpeed, settings.mInvertCameraPan);

		// Switch to battle HUD and enter deployment
		mUISubsystem.GUIContext.RootElement = mBattleHUD.RootElement;
		mBattleScene.EnterDeploymentMode();
		mBattleHUD.ShowDeploymentPanel();
		mBattleHUD.ResetResultState();
		mDeployRosterSelectedUnitId = -1;
		mDeployRosterDirty = true;
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
		// Create and initialize UI subsystem
		let shaderPath = scope String();
		GetAssetPath("Render/Shaders", shaderPath);

		mUISubsystem = new Sedulous.GUI.Runtime.GUISubsystem();
		mContext.RegisterSubsystem(mUISubsystem);

		if (mUISubsystem.InitializeRendering(mDevice, .BGRA8UnormSrgb, (int32)SwapChain.BufferCount, mShell, mWindow, scope StringView[](shaderPath)) case .Err)
		{
			Console.WriteLine("Failed to initialize UI rendering");
			return;
		}

		// Load font at different sizes
		let fontPath = scope String();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		int32[6] fontSizes = .(14, 16, 18, 20, 24, 32);
		for (let size in fontSizes)
		{
			FontLoadOptions options = .ExtendedLatin;
			options.PixelHeight = size;
			if (mUISubsystem.LoadFont("Roboto", fontPath, options) case .Err)
				Console.WriteLine("Failed to load font at size {}", size);
		}

		// Use GameTheme for dark UI with gold accents
		mUISubsystem.Theme = new GameTheme();

		// Create battle HUD (root element set later when entering battle/stage select)
		mBattleHUD = new BattleHUD();

		// Create city hub screen
		mCityHubScreen = new CityHubScreen();

		// Create roster screen
		mRosterScreen = new RosterScreen();
		mRosterScreen.OnBack.Subscribe(new () => {
			ShowCityHub();
		});
		mRosterScreen.OnStarUp.Subscribe(new (unitId) => {
			if (mRosterManager.TryStarUp(unitId))
			{
				mRosterScreen.Refresh(GetSaveData(), mConfigs, mRosterManager, mEquipmentManager);
				DoSave();
			}
			else
			{
				let shardsNeeded = mRosterManager.GetShardsForNextStar(unitId);
				if (shardsNeeded == 0)
					ShowToast("Already at max star level!");
				else
				{
					let owned = GetSaveData().GetOwnedUnit(unitId);
					let have = owned != null ? owned.mShards : 0;
					let msg = scope String();
					msg.AppendF("Need {} shards (have {})", shardsNeeded, have);
					ShowToast(msg);
				}
			}
		});
		mRosterScreen.OnEquipSlot.Subscribe(new (unitId, slot) => {
			mEquipSelectPopup.Show(mUISubsystem.GUIContext, unitId, slot, GetSaveData(), mConfigs, mEquipmentManager);
		});

		// Create equip select popup
		mEquipSelectPopup = new EquipSelectPopup();
		mEquipSelectPopup.OnEquipSelected.Subscribe(new (equipInstanceId) => {
			let unitId = mEquipSelectPopup.TargetUnitId;
			let slot = mEquipSelectPopup.TargetSlot;
			if (unitId >= 0)
			{
				if (equipInstanceId == 0)
				{
					mEquipmentManager.Unequip(unitId, slot);
				}
				else
				{
					mEquipmentManager.Equip(unitId, equipInstanceId, slot);
				}
				mRosterScreen.Refresh(GetSaveData(), mConfigs, mRosterManager, mEquipmentManager);
				DoSave();
			}
		});
		mEquipSelectPopup.OnClose.Subscribe(new () => {
			// Popup handles its own removal from PopupLayer
		});

		// Create inventory screen
		mInventoryScreen = new InventoryScreen();
		mInventoryScreen.OnBack.Subscribe(new () => {
			ShowCityHub();
		});
		mInventoryScreen.OnUse.Subscribe(new (itemId) => {
			// Items that need a target unit open the unit picker
			if (mInventoryManager.ItemNeedsTarget(itemId))
			{
				let itemConfig = mConfigs.GetItem(itemId);
				let title = scope String();
				title.AppendF("Use {}", itemConfig != null ? itemConfig.mName : "Item");
				mUnitSelectPopup.Show(mUISubsystem.GUIContext, itemId, title, GetSaveData(), mConfigs);
				return;
			}

			if (mInventoryManager.UseItem(itemId))
			{
				mInventoryScreen.Refresh(GetSaveData(), mConfigs, mInventoryManager);
				DoSave();
			}
			else
			{
				let config = mConfigs.GetItem(itemId);
				if (config != null && config.mConsumableEffect == .RestoreStamina)
					ShowToast("Stamina is already full!");
				else
					ShowToast("Cannot use this item");
			}
		});
		mInventoryScreen.OnSell.Subscribe(new (itemId) => {
			if (mInventoryManager.SellItem(itemId) > 0)
			{
				mInventoryScreen.Refresh(GetSaveData(), mConfigs, mInventoryManager);
				DoSave();
			}
		});

		// Create unit select popup (for EXP potions etc.)
		mUnitSelectPopup = new UnitSelectPopup();
		mUnitSelectPopup.OnUnitSelected.Subscribe(new (unitId) => {
			let itemId = mUnitSelectPopup.ItemId;
			if (mInventoryManager.UseItem(itemId, unitId))
			{
				mInventoryScreen.Refresh(GetSaveData(), mConfigs, mInventoryManager);
				DoSave();
				let config = mConfigs.GetItem(itemId);
				let msg = scope String();
				msg.AppendF("Used {} on unit", config != null ? StringView(config.mName) : "item");
				ShowToast(msg);
			}
			else
				ShowToast("Cannot use this item on that unit");
		});

		// Create shop screen
		mShopScreen = new ShopScreen();
		mShopScreen.OnBack.Subscribe(new () => {
			ShowCityHub();
		});
		mShopScreen.OnBuy.Subscribe(new (shopItemId) => {
			if (mShopManager.TryPurchase(shopItemId))
			{
				mShopScreen.Refresh(GetSaveData(), mConfigs, mShopManager);
				DoSave();
			}
			else
			{
				let remaining = mShopManager.GetRemainingPurchases(shopItemId);
				if (remaining == 0)
					ShowToast("Purchase limit reached!");
				else
					ShowToast("Not enough currency!");
			}
		});

		// Create gacha screen
		mGachaScreen = new GachaScreen();
		mGachaScreen.OnBack.Subscribe(new () => {
			ShowCityHub();
		});
		mGachaScreen.OnPullSingle.Subscribe(new () => {
			let result = mGachaManager.PullSingle();
			if (result != null)
			{
				mGachaScreen.ShowSingleResult(result, mConfigs);
				mGachaScreen.Refresh(GetSaveData());
				DoSave();
				delete result;
			}
			else
				ShowToast("Not enough gems for a pull!");
		});
		mGachaScreen.OnPullMulti.Subscribe(new () => {
			let results = mGachaManager.PullMulti();
			if (results.Count > 0)
			{
				mGachaScreen.ShowMultiResults(results, mConfigs);
				mGachaScreen.Refresh(GetSaveData());
				DoSave();
			}
			else
				ShowToast("Not enough gems for 10x pull!");
			for (let r in results) delete r;
			delete results;
		});

		// Create formation screen
		mFormationScreen = new FormationScreen();
		mFormationScreen.OnBack.Subscribe(new () => {
			ShowCityHub();
		});
		mFormationScreen.OnSave.Subscribe(new () => {
			DoSave();
			ShowCityHub();
		});
		mFormationScreen.OnMessage.Subscribe(new (msg) => {
			ShowToast(msg);
		});

		// Create settings screen
		mSettingsScreen = new SettingsScreen();
		mSettingsScreen.OnBack.Subscribe(new () => {
			DoSave();
			ShowCityHub();
		});
		mSettingsScreen.OnChanged.Subscribe(new () => {
			DoSave();
		});

		// Create campaign screen
		mCampaignScreen = new CampaignScreen();
		mCampaignScreen.OnBack.Subscribe(new () => {
			ShowCityHub();
		});
		mCampaignScreen.OnStageSelected.Subscribe(new (stageId, isHardMode) => {
			// Switch to battle HUD and create battle
			mUISubsystem.GUIContext.RootElement = mBattleHUD.RootElement;
			mBattleHUD.ResetResultState();
			CreateBattle(stageId, isHardMode);
		});
		mCampaignScreen.OnSweep.Subscribe(new (stageId, isHardMode) => {
			OnSweepStage(stageId, isHardMode);
		});

		// Create daily challenge screen
		mDailyChallengeScreen = new DailyChallengeScreen();
		mDailyChallengeScreen.OnBack.Subscribe(new () => {
			ShowCityHub();
		});
		mDailyChallengeScreen.OnStartChallenge.Subscribe(new (index) => {
			CreateChallengeBattle(index);
		});

		// Create boss rush screen
		mBossRushScreen = new BossRushScreen();
		mBossRushScreen.OnBack.Subscribe(new () => {
			ShowCityHub();
		});
		mBossRushScreen.OnStartBoss.Subscribe(new (index) => {
			CreateBossBattle(index);
		});

		// Create tower screen
		mTowerScreen = new TowerScreen();
		mTowerScreen.OnBack.Subscribe(new () => {
			ShowCityHub();
		});
		mTowerScreen.OnStartFloor.Subscribe(new (index) => {
			CreateTowerBattle(index);
		});

		// Create crusade screen
		mCrusadeScreen = new CrusadeScreen();
		mCrusadeScreen.OnBack.Subscribe(new () => {
			ShowCityHub();
		});
		mCrusadeScreen.OnStartWave.Subscribe(new (index) => {
			CreateCrusadeBattle(index);
		});

		// Wire city hub navigation events
		mCityHubScreen.OnCampaign.Subscribe(new () => {
			ShowStageSelect();
		});
		mCityHubScreen.OnChallenges.Subscribe(new () => {
			ShowDailyChallenges();
		});
		mCityHubScreen.OnBossRush.Subscribe(new () => {
			ShowBossRush();
		});
		mCityHubScreen.OnTower.Subscribe(new () => {
			ShowTower();
		});
		mCityHubScreen.OnCrusade.Subscribe(new () => {
			ShowCrusade();
		});
		mCityHubScreen.OnRoster.Subscribe(new () => {
			ShowRoster();
		});
		mCityHubScreen.OnInventory.Subscribe(new () => {
			ShowInventory();
		});
		mCityHubScreen.OnFormation.Subscribe(new () => {
			ShowFormation();
		});
		mCityHubScreen.OnShop.Subscribe(new () => {
			ShowShop();
		});
		mCityHubScreen.OnGacha.Subscribe(new () => {
			ShowGacha();
		});
		mCityHubScreen.OnSettings.Subscribe(new () => {
			ShowSettings();
		});

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
				// Check that at least one unit is deployed
				bool hasAttacker = false;
				for (int32 i = 0; i < mCurrentSim.UnitCount; i++)
				{
					let unit = mCurrentSim.GetUnit(i);
					if (unit != null && unit.mAlive && unit.mForce == .Attacker)
					{
						hasAttacker = true;
						break;
					}
				}
				if (!hasAttacker)
				{
					ShowToast("Deploy at least one unit!");
					return;
				}

				// For challenge battles, validate all deployed units pass restriction
				if (mCurrentChallengeIndex >= 0)
				{
					for (int32 i = 0; i < mCurrentSim.UnitCount; i++)
					{
						let unit = mCurrentSim.GetUnit(i);
						if (unit != null && unit.mAlive && unit.mForce == .Attacker)
						{
							if (!mDailyChallengeManager.IsUnitAllowed(mCurrentChallengeIndex, unit.mConfig))
							{
								ShowToast("Some units don't meet the challenge restriction!");
								return;
							}
						}
					}
					// No stamina cost for challenges
				}
				else if (mCurrentBossIndex >= 0 || mCurrentTowerFloor >= 0 || mCurrentCrusadeWave >= 0)
				{
					// No stamina cost for boss rush, tower, or crusade
				}
				else
				{
					// Spend stamina now that battle is actually starting
					let stageConfig = mConfigs.GetStage(mCurrentStageId);
					if (stageConfig != null)
						mPlayerManager.TrySpendStamina(stageConfig.mStaminaCost);
				}

				mBattleScene.StartBattle();
				mBattleHUD.HideDeploymentPanel();
				mGameState = .Battle;
				Console.WriteLine("Deployment complete — battle started!");
			}
		});
		mBattleHUD.OnPresetSelected.Subscribe(new (presetIndex) => {
			OnDeployPresetSelected(presetIndex);
		});
		mBattleHUD.OnRosterUnitSelected.Subscribe(new (unitId) => {
			OnDeployRosterUnitClicked(unitId);
		});
		mBattleHUD.OnSaveFormation.Subscribe(new (presetIndex) => {
			OnDeploySaveFormation(presetIndex);
		});
		mBattleHUD.OnRemoveUnit.Subscribe(new () => {
			OnDeployRemoveUnit();
		});
		mBattleHUD.OnContinue.Subscribe(new () => {
			if (mCurrentTowerFloor >= 0)
			{
				mCurrentTowerFloor = -1;
				ShowTower();
			}
			else if (mCurrentCrusadeWave >= 0)
			{
				mCurrentCrusadeWave = -1;
				ShowCrusade();
			}
			else if (mCurrentBossIndex >= 0)
			{
				mCurrentBossIndex = -1;
				ShowBossRush();
			}
			else if (mCurrentChallengeIndex >= 0)
			{
				mCurrentChallengeIndex = -1;
				ShowDailyChallenges();
			}
			else
				ShowStageSelect();
		});

		// Toast notification
		mToast = new ToastNotification();

		Console.WriteLine("UI system initialized");
	}

	private void ShowToast(StringView message)
	{
		mToast.Show(mUISubsystem.GUIContext, message);
	}

	/// Re-apply persistent HP from tower/crusade managers after redeployment.
	private void RestorePersistentHP()
	{
		if (mCurrentSim == null) return;
		if (mCurrentTowerFloor >= 0)
			mTowerManager.RestoreHP(mCurrentSim);
		else if (mCurrentCrusadeWave >= 0)
			mCrusadeManager.RestoreHP(mCurrentSim);
	}

	/// Stamp display-only level/star data on BattleUnits from player save data.
	private void StampUnitLevels()
	{
		if (mCurrentSim == null) return;
		let save = GetSaveData();
		for (int32 i = 0; i < mCurrentSim.UnitCount; i++)
		{
			let unit = mCurrentSim.GetUnit(i);
			if (unit == null) continue;
			let owned = save.GetOwnedUnit(unit.mConfig.mId);
			if (owned != null)
			{
				unit.mLevel = owned.mLevel;
				unit.mStarLevel = owned.mStarLevel;
			}
		}
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
		{
			// Escape from city exits; from battle/stage select returns to city
			if (mGameState == .City)
				Exit();
			else
				ShowCityHub();
			return;
		}

		// Always process keyboard input for camera/shortcuts
		if (mBattleScene != null)
			mBattleScene.HandleInput(keyboard, mouse, mDeltaTime);

		// Check if mouse is over an interactive UI element
		let hitElement = mUISubsystem?.GUIContext?.HitTest(mouse.X, mouse.Y);
		bool uiHovered = hitElement != null;

		if (mBattleScene != null && !uiHovered)
		{
			if (mouse.IsButtonPressed(.Left) && mBattleScene.HasHoveredHex)
			{
				if (mBattleScene.IsDeploymentMode)
				{
					if (mDeployRosterSelectedUnitId >= 0)
					{
						// Roster unit selected — place on grid
						OnDeployPlaceRosterUnit(mBattleScene.HoveredHex);
					}
					else
					{
						// No roster selection — existing swap/move behavior
						mBattleScene.DeploymentClickHex(mBattleScene.HoveredHex);
					}
					mDeployRosterDirty = true;
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

		// Update gacha reveal animation
		if (mGameState == .Gacha)
			mGachaScreen.Update(mDeltaTime);

		// Update daily challenge timer
		if (mGameState == .DailyChallenge)
			mDailyChallengeScreen.UpdateTimer(mDailyChallengeManager.SecondsUntilReset);

		// Update tower/crusade timers
		if (mGameState == .Tower)
			mTowerScreen.UpdateTimer(mTowerManager.SecondsUntilReset);
		if (mGameState == .Crusade)
			mCrusadeScreen.UpdateTimer(mCrusadeManager.SecondsUntilReset);

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

		// Update toast notification
		mToast.Update(mDeltaTime);

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
			// Update hint text
			if (mDeployRosterSelectedUnitId >= 0)
			{
				let config = mConfigs.GetUnit(mDeployRosterSelectedUnitId);
				if (config != null)
				{
					let hint = scope String();
					hint.AppendF("{} selected — click a deploy hex to place.", config.mName);
					mBattleHUD.UpdateDeploymentHint(hint);
				}
			}
			else if (mBattleScene.DeploySelectedUnit >= 0)
			{
				let selUnit = sim.GetUnit(mBattleScene.DeploySelectedUnit);
				if (selUnit != null)
				{
					let hint = scope String();
					hint.AppendF("{} selected — click a hex to move or another unit to swap.", selUnit.mConfig.mName);
					mBattleHUD.UpdateDeploymentHint(hint);
				}
			}
			else
			{
				mBattleHUD.UpdateDeploymentHint("Select a unit from roster or grid to deploy.");
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
					nameStr.AppendF("{} Lv.{}{}", hoveredUnit.mConfig.mName, hoveredUnit.mLevel, forceTag);

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

			// Update preset tabs and save targets
			if (mDeployRosterDirty)
			{
				let activeIdx = GetSaveData().mActiveFormationIndex;
				let count = mFormationManager.PresetCount;
				var names = scope StringView[count];
				for (int32 i = 0; i < count; i++)
				{
					let preset = mFormationManager.GetPreset(i);
					if (preset != null)
						names[i] = preset.mName;
					else
						names[i] = "?";
				}
				mBattleHUD.UpdateDeployPresetTabs(count, activeIdx, names);
				mBattleHUD.UpdateDeploySaveTargets(count, names);
			}

			// Update roster sidebar (rebuild only when dirty)
			if (mDeployRosterDirty)
			{
				mDeployRosterDirty = false;

				// Build list of deployed unit IDs
				let deployedIds = scope List<int32>();
				for (int32 i = 0; i < sim.UnitCount; i++)
				{
					let unit = sim.GetUnit(i);
					if (unit != null && unit.mAlive && unit.mForce == .Attacker)
						deployedIds.Add(unit.mConfig.mId);
				}

				// Build roster info from owned units
				let save = GetSaveData();
				var rosterInfos = scope RosterUnitInfo[save.mOwnedUnits.Count];
				int32 rosterCount = 0;
				for (let owned in save.mOwnedUnits)
				{
					let config = mConfigs.GetUnit(owned.mUnitId);
					if (config == null) continue;
					// Filter by challenge restriction
					if (mCurrentChallengeIndex >= 0 && !mDailyChallengeManager.IsUnitAllowed(mCurrentChallengeIndex, config))
						continue;
					// Filter unavailable units in tower/crusade
					if (mCurrentTowerFloor >= 0 && mTowerManager.IsUnitDead(owned.mUnitId))
						continue;
					if (mCurrentCrusadeWave >= 0 && !mCrusadeManager.IsUnitAvailable(owned.mUnitId))
						continue;
					var info = RosterUnitInfo();
					info.mUnitId = owned.mUnitId;
					info.mName = config.mName;
					info.mUnitClass = config.mUnitClass;
					info.mRarity = config.mRarity;
					info.mLevel = owned.mLevel;
					info.mStarLevel = owned.mStarLevel;
					info.mIsDeployed = deployedIds.Contains(owned.mUnitId);
					let stats = mRosterManager.GetEffectiveStats(owned.mUnitId);
					info.mHP = stats.mHP;
					info.mDamage = stats.mDamage;
					info.mDefense = stats.mDefense;
					info.mSpeed = stats.mActionSpeed;
					info.mPower = stats.mPower;
					if (rosterCount < rosterInfos.Count)
						rosterInfos[rosterCount++] = info;
				}
				mBattleHUD.UpdateDeployRoster(rosterInfos[0..<rosterCount]);
			}

			// Toggle "Remove Unit" button based on grid selection
			mBattleHUD.ShowRemoveUnitButton(mBattleScene.DeploySelectedUnit >= 0);

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

				let nameStr = scope String();
				nameStr.AppendF("{} Lv.{}", unit.mConfig.mName, unit.mLevel);

				mBattleHUD.UpdateCurrentUnit(
					nameStr,
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
				let targetName = scope String();
				targetName.AppendF("{} Lv.{}", targetUnit.mConfig.mName, targetUnit.mLevel);
				mBattleHUD.UpdateTargetInfo(targetName, targetUnit.mCurrentHP, targetUnit.mMaxHP, targetClass);
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

			// Process tower/crusade results (both victory and defeat)
			if (!mRewardsProcessed && mCurrentTowerFloor >= 0)
			{
				mRewardsProcessed = true;
				let floor = mTowerManager.GetFloor(mCurrentTowerFloor);
				if (floor != null)
				{
					if (sim.State == .AttackerWins)
					{
						mTowerManager.CaptureHP(sim);
						mTowerManager.AdvanceFloor();
						mPlayerManager.AddGold(floor.mGoldReward);
						mPlayerManager.AddHeroExp(floor.mExpReward);
						if (floor.mGemReward > 0)
							mPlayerManager.AddGems(floor.mGemReward);

						var emptyRewards = scope RewardDisplayInfo[0];
						mBattleHUD.ShowRewards(floor.mGoldReward, floor.mExpReward, floor.mGemReward, false, emptyRewards);

						Console.WriteLine("[Tower] Cleared floor {} '{}' — +{} gold, +{} EXP, +{} gems",
							mCurrentTowerFloor + 1, floor.mName, floor.mGoldReward, floor.mExpReward, floor.mGemReward);
					}
					else
					{
						mTowerManager.ClearHP();
						Console.WriteLine("[Tower] Defeated on floor {} — run ended", mCurrentTowerFloor + 1);
					}
					DoSave();
				}
			}
			else if (!mRewardsProcessed && mCurrentCrusadeWave >= 0)
			{
				mRewardsProcessed = true;
				let wave = mCrusadeManager.GetWave(mCurrentCrusadeWave);
				if (wave != null)
				{
					if (sim.State == .AttackerWins)
					{
						// Victory: save attacker HP, clear defender HP, advance wave
						mCrusadeManager.MergeCaptureHP(sim);
						mCrusadeManager.ClearDefenderHP();
						mCrusadeManager.AdvanceWave();
						mPlayerManager.AddGold(wave.mGoldReward);
						mPlayerManager.AddHeroExp(wave.mExpReward);
						if (wave.mGemReward > 0)
							mPlayerManager.AddGems(wave.mGemReward);

						var emptyRewards = scope RewardDisplayInfo[0];
						mBattleHUD.ShowRewards(wave.mGoldReward, wave.mExpReward, wave.mGemReward, false, emptyRewards);

						Console.WriteLine("[Crusade] Cleared wave {} '{}' — +{} gold, +{} EXP, +{} gems",
							mCurrentCrusadeWave + 1, wave.mName, wave.mGoldReward, wave.mExpReward, wave.mGemReward);
					}
					else
					{
						// Defeat: save attacker state (dead=0, survivors keep HP) + save defender HP
						mCrusadeManager.MergeCaptureHP(sim);
						mCrusadeManager.CaptureDefenderHP(sim);
						Console.WriteLine("[Crusade] Defeated on wave {} — retry with remaining units ({}/{} pool used)",
							mCurrentCrusadeWave + 1, mCrusadeManager.UsedUnitCount, mCrusadeManager.MaxUnitPool);
					}
					DoSave();
				}
			}

			// Process rewards once on victory (non-tower/crusade modes)
			else if (!mRewardsProcessed && sim.State == .AttackerWins)
			{
				mRewardsProcessed = true;

				if (mCurrentBossIndex >= 0)
				{
					// Boss rush rewards — gold/exp always, gems on first clear only
					let bossTmpl = mBossRushManager.GetBoss(mCurrentBossIndex);
					if (bossTmpl != null)
					{
						bool isFirstClear = !mBossRushManager.IsBossDefeated(mCurrentBossIndex);
						mPlayerManager.AddGold(bossTmpl.mGoldReward);
						mPlayerManager.AddHeroExp(bossTmpl.mExpReward);
						int32 gemsAwarded = 0;
						if (isFirstClear && bossTmpl.mFirstClearGems > 0)
						{
							mPlayerManager.AddGems(bossTmpl.mFirstClearGems);
							gemsAwarded = bossTmpl.mFirstClearGems;
						}
						if (isFirstClear)
							mBossRushManager.MarkBossDefeated(mCurrentBossIndex);
						DoSave();

						var emptyRewards = scope RewardDisplayInfo[0];
						mBattleHUD.ShowRewards(bossTmpl.mGoldReward, bossTmpl.mExpReward, gemsAwarded, isFirstClear, emptyRewards);

						Console.WriteLine("[Boss Rush] Defeated '{}'{} — +{} gold, +{} EXP, +{} gems",
							bossTmpl.mName, isFirstClear ? " (FIRST CLEAR)" : "", bossTmpl.mGoldReward, bossTmpl.mExpReward, gemsAwarded);
					}
				}
				else if (mCurrentChallengeIndex >= 0)
				{
					// Challenge rewards — flat gold/exp/gems
					let tmpl = mDailyChallengeManager.GetChallenge(mCurrentChallengeIndex);
					if (tmpl != null)
					{
						mPlayerManager.AddGold(tmpl.mGoldReward);
						if (tmpl.mGemReward > 0)
							mPlayerManager.AddGems(tmpl.mGemReward);
						mPlayerManager.AddHeroExp(tmpl.mExpReward);
						mDailyChallengeManager.MarkCompleted(mCurrentChallengeIndex);
						DoSave();

						var emptyRewards = scope RewardDisplayInfo[0];
						mBattleHUD.ShowRewards(tmpl.mGoldReward, tmpl.mExpReward, tmpl.mGemReward, false, emptyRewards);

						Console.WriteLine("[Challenge] Completed '{}' — +{} gold, +{} EXP, +{} gems",
							tmpl.mName, tmpl.mGoldReward, tmpl.mExpReward, tmpl.mGemReward);
					}
				}
				else
				{
					// Campaign rewards
					let rewards = mRewardProcessor.ProcessStageRewards(mCurrentStageId, result.mStarRating, mCurrentBattleHardMode);
					defer delete rewards;

					// Build display info for HUD
					var rewardInfos = scope RewardDisplayInfo[rewards.mItems.Count];
					for (int32 i = 0; i < (int32)rewards.mItems.Count; i++)
					{
						rewardInfos[i].mName = rewards.mItems[i].mItemName;
						rewardInfos[i].mQuantity = rewards.mItems[i].mQuantity;
					}

					mBattleHUD.ShowRewards(rewards.mGoldGained, rewards.mExpGained, rewards.mGemsGained, rewards.mIsFirstClear, rewardInfos);
					DoSave();

					Console.WriteLine("[Rewards] +{} gold, +{} EXP, {} items",
						rewards.mGoldGained, rewards.mExpGained, rewards.mItems.Count);
				}
			}
		}
	}

	// --- Deployment event handlers ---

	/// Handle preset tab selection during deployment.
	private void OnDeployPresetSelected(int32 presetIndex)
	{
		if (mBattleScene == null || mCurrentSim == null) return;

		mFormationManager.SetActivePreset(presetIndex);
		GetSaveData().mActiveFormationIndex = presetIndex;

		// Build attacker list from selected preset
		let preset = mFormationManager.GetPreset(presetIndex);
		let attackers = scope List<FormationSlot>();

		if (preset != null)
		{
			let save = GetSaveData();
			for (let fSlot in preset.mSlots)
			{
				let unitConfig = mConfigs.GetUnit(fSlot.mUnitId);
				if (unitConfig == null) continue;
				if (save.GetOwnedUnit(fSlot.mUnitId) == null) continue;
				// Filter by challenge restriction
				if (mCurrentChallengeIndex >= 0 && !mDailyChallengeManager.IsUnitAllowed(mCurrentChallengeIndex, unitConfig))
					continue;
				// Filter unavailable units in tower/crusade
				if (mCurrentTowerFloor >= 0 && mTowerManager.IsUnitDead(fSlot.mUnitId))
					continue;
				if (mCurrentCrusadeWave >= 0 && !mCrusadeManager.IsUnitAvailable(fSlot.mUnitId))
					continue;
				let slot = scope :: FormationSlot();
				slot.mUnitId = fSlot.mUnitId;
				slot.mGridX = fSlot.mGridX;
				slot.mGridY = fSlot.mGridY;
				attackers.Add(slot);
			}
		}

		mCurrentSim.RedeployAttackers(attackers);
		StampUnitLevels();
		RestorePersistentHP();
		mBattleScene.RebuildUnitViews();
		mDeployRosterSelectedUnitId = -1;
		mDeployRosterDirty = true;

		Console.WriteLine("[Deploy] Switched to preset {} — {} attackers", presetIndex, attackers.Count);
	}

	/// Handle roster unit click during deployment.
	private void OnDeployRosterUnitClicked(int32 unitId)
	{
		if (unitId == mDeployRosterSelectedUnitId)
			mDeployRosterSelectedUnitId = -1; // Deselect
		else
			mDeployRosterSelectedUnitId = unitId;
	}

	/// Place a roster-selected unit onto the deployment grid.
	private void OnDeployPlaceRosterUnit(HexCoord hex)
	{
		if (mBattleScene == null || mCurrentSim == null) return;
		if (mDeployRosterSelectedUnitId < 0) return;

		let deployColumns = mCurrentSim.DeployColumns;
		let (targetCol, targetRow) = hex.ToOffset();
		if (targetCol >= deployColumns || !mCurrentSim.Grid.InBounds(hex))
		{
			ShowToast("Must place in the deploy zone!");
			mDeployRosterSelectedUnitId = -1;
			return;
		}

		// Build current attacker list from simulation
		let attackers = scope List<FormationSlot>();
		mCurrentSim.GetDeployedAttackers(attackers);
		defer { for (let s in attackers) delete s; }

		// Check if the roster unit is already deployed
		int32 existingIdx = -1;
		for (int32 i = 0; i < (int32)attackers.Count; i++)
		{
			if (attackers[i].mUnitId == mDeployRosterSelectedUnitId)
			{
				existingIdx = i;
				break;
			}
		}

		// Check if target hex is occupied by a different unit
		int32 occupantIdx = -1;
		for (int32 i = 0; i < (int32)attackers.Count; i++)
		{
			if (attackers[i].mGridX == targetCol && attackers[i].mGridY == targetRow)
			{
				occupantIdx = i;
				break;
			}
		}

		if (existingIdx >= 0)
		{
			// Already deployed — move to target hex
			if (occupantIdx >= 0 && occupantIdx != existingIdx)
			{
				// Target occupied by different unit — remove occupant
				delete attackers[occupantIdx];
				attackers.RemoveAt(occupantIdx);
				// Adjust existingIdx if it was after removed
				if (existingIdx > occupantIdx) existingIdx--;
			}
			attackers[existingIdx].mGridX = targetCol;
			attackers[existingIdx].mGridY = targetRow;
		}
		else
		{
			// Not deployed — check slot limit
			if (attackers.Count >= mPlayerManager.MaxFormationSlots)
			{
				let msg = scope String();
				msg.AppendF("Formation full! Max {} units.", mPlayerManager.MaxFormationSlots);
				ShowToast(msg);
				mDeployRosterSelectedUnitId = -1;
				return;
			}

			// Remove occupant if target hex is occupied
			if (occupantIdx >= 0)
			{
				delete attackers[occupantIdx];
				attackers.RemoveAt(occupantIdx);
			}

			// Add new unit
			let slot = new FormationSlot();
			slot.mUnitId = mDeployRosterSelectedUnitId;
			slot.mGridX = targetCol;
			slot.mGridY = targetRow;
			attackers.Add(slot);
		}

		mCurrentSim.RedeployAttackers(attackers);
		StampUnitLevels();
		RestorePersistentHP();
		mBattleScene.RebuildUnitViews();
		mDeployRosterSelectedUnitId = -1;
		mDeployRosterDirty = true;
	}

	/// Remove the grid-selected unit during deployment.
	private void OnDeployRemoveUnit()
	{
		if (mBattleScene == null || mCurrentSim == null) return;

		let selIdx = mBattleScene.DeploySelectedUnit;
		if (selIdx < 0) return;

		let selUnit = mCurrentSim.GetUnit(selIdx);
		if (selUnit == null || !selUnit.mAlive || selUnit.mForce != .Attacker) return;

		// Build attacker list excluding the selected unit
		let attackers = scope List<FormationSlot>();
		mCurrentSim.GetDeployedAttackers(attackers);
		defer { for (let s in attackers) delete s; }

		// Find and remove the selected unit's ID
		let removeId = selUnit.mConfig.mId;
		for (int32 i = 0; i < (int32)attackers.Count; i++)
		{
			if (attackers[i].mUnitId == removeId)
			{
				delete attackers[i];
				attackers.RemoveAt(i);
				break;
			}
		}

		mCurrentSim.RedeployAttackers(attackers);
		StampUnitLevels();
		RestorePersistentHP();
		mBattleScene.RebuildUnitViews();
		mDeployRosterDirty = true;

		Console.WriteLine("[Deploy] Removed unit {}", removeId);
	}

	/// Handle sweep stage from campaign screen.
	private void OnSweepStage(int32 stageId, bool isHardMode = false)
	{
		let result = mRewardProcessor.SweepStage(stageId, isHardMode);
		if (result == null)
		{
			int32 stars = isHardMode ? mPlayerManager.GetHardStars(stageId) : mPlayerManager.GetBestStars(stageId);
			if (stars < 3)
				ShowToast("Need 3 stars to sweep!");
			else if (isHardMode ? !mPlayerManager.CanSweepHard(stageId) : !mPlayerManager.CanSweep(stageId))
				ShowToast("No sweeps remaining!");
			else
				ShowToast("Not enough stamina!");
			return;
		}
		defer delete result;

		Console.WriteLine("[Campaign] Swept stage {}{} — +{}G +{}EXP {} items",
			stageId, isHardMode ? " (HARD)" : "", result.mGoldGained, result.mExpGained, result.mItems.Count);

		DoSave();

		// Build item display info
		let stageConfig = mConfigs.GetStage(stageId);
		var itemInfos = scope RewardDisplayInfo[result.mItems.Count];
		for (int32 i = 0; i < (int32)result.mItems.Count; i++)
		{
			itemInfos[i].mName = result.mItems[i].mItemName;
			itemInfos[i].mQuantity = result.mItems[i].mQuantity;
		}

		// Show results in the popup
		let sweepCount = isHardMode ? GetSaveData().GetHardSweepCount(stageId) : GetSaveData().GetSweepCount(stageId);
		let sweepLimit = stageConfig != null ? stageConfig.mSweepLimit : 0;
		mCampaignScreen.ShowSweepResults(
			result.mGoldGained,
			result.mExpGained,
			itemInfos,
			sweepCount,
			sweepLimit,
			GetSaveData().mStamina
		);
	}

	/// Save the current deployment to a specific formation preset.
	private void OnDeploySaveFormation(int32 presetIndex)
	{
		if (mCurrentSim == null) return;

		let deployed = scope List<FormationSlot>();
		mCurrentSim.GetDeployedAttackers(deployed);
		defer { for (let s in deployed) delete s; }

		mFormationManager.OverwritePreset(presetIndex, deployed);
		DoSave();

		Console.WriteLine("[Deploy] Saved deployment as preset {} ({} units)", presetIndex, deployed.Count);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		// Deferred sky setup — must happen after first BeginFrame flushes the init transfer batch
		if (mNeedsSkySetup && mSkyFeature != null)
		{
			mNeedsSkySetup = false;
			let zenith = Color(60, 100, 160, 255);
			let horizon = Color(140, 170, 200, 255);
			mSkyFeature.CreateGradientSky(zenith, horizon, 32);
		}

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
			mRenderView.UpdateMatrices();

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
			mUISubsystem.Render(render.Encoder, render.SwapChain.CurrentTextureView,
				mSwapChain.Width, mSwapChain.Height, render.Frame.FrameIndex);
		}

		return true;
	}

	protected override void OnShutdown()
	{
		Profiler.Shutdown();

		// Cleanup in dependency order:
		// 1. UI screens — before UISubsystem is torn down by context
		delete mSettingsScreen;
		mSettingsScreen = null;
		delete mCampaignScreen;
		mCampaignScreen = null;
		delete mCrusadeScreen;
		mCrusadeScreen = null;
		delete mTowerScreen;
		mTowerScreen = null;
		delete mBossRushScreen;
		mBossRushScreen = null;
		delete mDailyChallengeScreen;
		mDailyChallengeScreen = null;
		delete mFormationScreen;
		mFormationScreen = null;
		delete mGachaScreen;
		mGachaScreen = null;
		delete mShopScreen;
		mShopScreen = null;
		delete mEquipSelectPopup;
		mEquipSelectPopup = null;
		delete mInventoryScreen;
		mInventoryScreen = null;
		delete mRosterScreen;
		mRosterScreen = null;
		delete mBattleHUD;
		mBattleHUD = null;
		delete mCityHubScreen;
		mCityHubScreen = null;
		delete mToast;
		mToast = null;
		delete mUnitSelectPopup;
		mUnitSelectPopup = null;
		delete mLoginScreen;
		mLoginScreen = null;

		// 2. Battle scene + simulation
		DestroyBattle();

		// 3. Metagame systems — save before exit
		DoSave();
		delete mCrusadeManager;
		mCrusadeManager = null;
		delete mTowerManager;
		mTowerManager = null;
		delete mBossRushManager;
		mBossRushManager = null;
		delete mDailyChallengeManager;
		mDailyChallengeManager = null;
		delete mRewardProcessor;
		mRewardProcessor = null;
		delete mRosterManager;
		mRosterManager = null;
		delete mFormationManager;
		mFormationManager = null;
		delete mGachaManager;
		mGachaManager = null;
		delete mShopManager;
		mShopManager = null;
		delete mEquipmentManager;
		mEquipmentManager = null;
		delete mInventoryManager;
		mInventoryManager = null;
		delete mPlayerManager;
		mPlayerManager = null;
		delete mSaveManager;
		mSaveManager = null;
		delete mServerSaveManager;
		mServerSaveManager = null;

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

		// Note: mMainScene is owned by SceneSubsystem — deleted during mContext.Shutdown()

		Console.WriteLine("Storm Tactics shutting down");
	}
}

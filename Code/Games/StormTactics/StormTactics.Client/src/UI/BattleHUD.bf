namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;
using StormTactics.Core;

delegate void BattleActionDelegate();
delegate void SpeedChangeDelegate(float speed);
delegate void SkillSelectDelegate(int32 skillId);
delegate void StageSelectDelegate(int32 stageId);
delegate void PresetSelectDelegate(int32 presetIndex);
delegate void DeployUnitDelegate(int32 unitId);

struct StageDisplayInfo
{
	public int32 mId;
	public StringView mName;
	public int32 mDifficulty;
	public int32 mEnemyCount;
}

struct SkillDisplayInfo
{
	public int32 mId;
	public StringView mName;
	public int32 mCooldownLeft;
	public bool mUsable;
}

struct TurnOrderEntry
{
	public StringView mName;
	public bool mIsAttacker;
	public bool mIsCurrent;
}

struct RosterUnitInfo
{
	public int32 mUnitId;
	public StringView mName;
	public UnitClass mUnitClass;
	public Rarity mRarity;
	public bool mIsDeployed;
	public int32 mHP;
	public int32 mDamage;
	public int32 mDefense;
	public int32 mSpeed;
	public int32 mPower;
}

struct RewardDisplayInfo
{
	public StringView mName;
	public int32 mQuantity;
}

/// Retained-mode battle HUD using Sedulous.GUI.
/// Provides turn info, speed controls, unit info panels, and battle result overlay.
class BattleHUD
{
	// Root layout
	private Grid mRoot ~ delete _;
	private DockPanel mHudPanel;

	// Turn order bar
	private Border mTurnOrderBar;
	private StackPanel mTurnOrderPanel;
	private const int32 TURN_ORDER_SLOTS = 12;
	private Border[TURN_ORDER_SLOTS] mTurnOrderSlots;
	private TextBlock[TURN_ORDER_SLOTS] mTurnOrderLabels;

	// Top bar elements
	private TextBlock mTitleLabel;
	private TextBlock mTurnLabel;
	private TextBlock mAttackerLabel;
	private TextBlock mDefenderLabel;
	private Button mSpeed1xButton;
	private Button mSpeed2xButton;
	private Button mSpeed4xButton;
	private Button mAutoButton;
	private Button mAutoStepButton;
	private Button mSkipButton;
	private Button mStepButton;

	// Bottom panel — current unit info
	private Border mBottomPanel;
	private TextBlock mUnitNameLabel;
	private TextBlock mUnitHPLabel;
	private TextBlock mUnitClassLabel;
	private TextBlock mUnitStatsLabel;
	private ProgressBar mUnitHPBar;

	// Bottom panel — target info (right side)
	private Border mTargetPanel;
	private TextBlock mTargetNameLabel;
	private TextBlock mTargetHPLabel;
	private TextBlock mTargetClassLabel;
	private ProgressBar mTargetHPBar;

	// Battle result overlay
	private Border mResultOverlay;
	private TextBlock mResultText;
	private TextBlock[3] mStarLabels;
	private TextBlock mStatTurns;
	private TextBlock mStatSurvivors;
	private TextBlock mStatKills;
	private TextBlock mStatDamage;
	private TextBlock mStatHealing;
	private Button mContinueButton;

	// Rewards section (in result overlay)
	private StackPanel mRewardsPanel;
	private TextBlock mRewardGoldLabel;
	private TextBlock mRewardExpLabel;
	private StackPanel mRewardItemsPanel;

	// Action panel (player turn)
	private Border mActionPanel;
	private Button mMoveButton;
	private Button mAttackButton;
	private Button mSkillButton;
	private Button mWaitButton;
	private Button mUndoButton;

	// Skill selection panel
	private Border mSkillPanel;
	private StackPanel mSkillListPanel;

	// Phase hint + cancel
	private TextBlock mPhaseHintLabel;
	private Button mCancelButton;

	// Deployment panel
	private Border mDeployPanel;
	private TextBlock mDeployHintLabel;
	private Button mStartBattleButton;

	// Deployment preset tabs
	private StackPanel mDeployPresetTabPanel;

	// Deployment roster sidebar
	private Border mDeployRosterPanel;
	private StackPanel mDeployRosterListPanel;
	private ScrollViewer mDeployRosterScroll;

	// Deployment action buttons
	private Button mSaveFormationButton;
	private Button mRemoveUnitButton;

	// Save-to-preset panel (shown when Save Formation is clicked)
	private Border mDeploySavePanel;
	private StackPanel mDeploySaveListPanel;

	// Stage selection panel
	private Border mStageSelectPanel;
	private StackPanel mStageListPanel;

	// State
	private bool mIsAutoPlaying;
	private float mCurrentSpeed = 1.0f;
	private bool mResultShown;

	// Icon cache for roster cards (keyed by unit ID, caller-owned OwnedImageData)
	private Dictionary<int32, OwnedImageData> mIconCache = new .() ~ { for (let v in _.Values) delete v; delete _; };

	// Events
	private EventAccessor<BattleActionDelegate> mOnAutoToggle = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnAutoStepToggle = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnSkip = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnStep = new .() ~ delete _;
	private EventAccessor<SpeedChangeDelegate> mOnSpeedChanged = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnContinue = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnMoveSelected = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnAttackSelected = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnSkillSelected = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnWaitSelected = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnCancelAction = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnUndoMove = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnStartBattle = new .() ~ delete _;
	private EventAccessor<PresetSelectDelegate> mOnPresetSelected = new .() ~ delete _;
	private EventAccessor<DeployUnitDelegate> mOnRosterUnitSelected = new .() ~ delete _;
	private EventAccessor<PresetSelectDelegate> mOnSaveFormation = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnRemoveUnit = new .() ~ delete _;
	private EventAccessor<StageSelectDelegate> mOnStageSelected = new .() ~ delete _;
	private EventAccessor<SkillSelectDelegate> mOnSkillChosen = new .() ~ delete _;

	public EventAccessor<BattleActionDelegate> OnAutoToggle => mOnAutoToggle;
	public EventAccessor<BattleActionDelegate> OnAutoStepToggle => mOnAutoStepToggle;
	public EventAccessor<BattleActionDelegate> OnSkip => mOnSkip;
	public EventAccessor<BattleActionDelegate> OnStep => mOnStep;
	public EventAccessor<SpeedChangeDelegate> OnSpeedChanged => mOnSpeedChanged;
	public EventAccessor<BattleActionDelegate> OnContinue => mOnContinue;
	public EventAccessor<BattleActionDelegate> OnMoveSelected => mOnMoveSelected;
	public EventAccessor<BattleActionDelegate> OnAttackSelected => mOnAttackSelected;
	public EventAccessor<BattleActionDelegate> OnSkillSelected => mOnSkillSelected;
	public EventAccessor<BattleActionDelegate> OnWaitSelected => mOnWaitSelected;
	public EventAccessor<BattleActionDelegate> OnCancelAction => mOnCancelAction;
	public EventAccessor<BattleActionDelegate> OnUndoMove => mOnUndoMove;
	public EventAccessor<BattleActionDelegate> OnStartBattle => mOnStartBattle;
	public EventAccessor<PresetSelectDelegate> OnPresetSelected => mOnPresetSelected;
	public EventAccessor<DeployUnitDelegate> OnRosterUnitSelected => mOnRosterUnitSelected;
	public EventAccessor<PresetSelectDelegate> OnSaveFormation => mOnSaveFormation;
	public EventAccessor<BattleActionDelegate> OnRemoveUnit => mOnRemoveUnit;
	public EventAccessor<StageSelectDelegate> OnStageSelected => mOnStageSelected;
	public EventAccessor<SkillSelectDelegate> OnSkillChosen => mOnSkillChosen;

	public UIElement RootElement => mRoot;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		// Grid as root — allows overlays on top of HUD
		mRoot = new Grid();
		mRoot.IsHitTestVisible = false; // Pass-through: children are hittable, empty space is not
		mRoot.RowDefinitions.Add(new .() { Height = .Star });
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });

		// DockPanel for HUD elements
		mHudPanel = new DockPanel();
		mHudPanel.IsHitTestVisible = false; // Pass-through: children are hittable, empty space is not
		mHudPanel.HorizontalAlignment = .Stretch;
		mHudPanel.VerticalAlignment = .Stretch;
		mHudPanel.LastChildFill = false;
		mRoot.AddChild(mHudPanel);

		BuildTopBar();
		BuildTurnOrderBar();
		BuildActionPanel();
		BuildDeploymentPanel();
		BuildStageSelectPanel();
		BuildBottomPanel();
		BuildResultOverlay();
	}

	private void BuildTopBar()
	{
		let topBar = new Border();
		topBar.Background = Color(15, 18, 25, 220);
		topBar.Height = .Fixed(44);
		topBar.Padding = Thickness(12, 6, 12, 6);
		DockPanelProperties.SetDock(topBar, .Top);

		// DockPanel: info on left, buttons on right
		let content = new DockPanel();
		content.LastChildFill = false;
		content.VerticalAlignment = .Center;
		topBar.Child = content;

		// Left side: info labels
		let infoPanel = new StackPanel();
		infoPanel.Orientation = .Horizontal;
		infoPanel.Spacing = 20;
		infoPanel.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(infoPanel, .Left);

		mTitleLabel = new TextBlock("STORM TACTICS");
		mTitleLabel.Foreground = Color(255, 215, 80);
		mTitleLabel.FontSize = 18;
		infoPanel.AddChild(mTitleLabel);

		let sep1 = new TextBlock("|");
		sep1.Foreground = Color(80, 85, 95);
		sep1.FontSize = 16;
		infoPanel.AddChild(sep1);

		mTurnLabel = new TextBlock("Turn: 0");
		mTurnLabel.Foreground = Color(200, 200, 200);
		mTurnLabel.FontSize = 16;
		infoPanel.AddChild(mTurnLabel);

		mAttackerLabel = new TextBlock("ATK: 0");
		mAttackerLabel.Foreground = Color(255, 100, 100);
		mAttackerLabel.FontSize = 16;
		infoPanel.AddChild(mAttackerLabel);

		mDefenderLabel = new TextBlock("DEF: 0");
		mDefenderLabel.Foreground = Color(100, 150, 255);
		mDefenderLabel.FontSize = 16;
		infoPanel.AddChild(mDefenderLabel);

		content.AddChild(infoPanel);

		// Right side: buttons
		let buttonPanel = new StackPanel();
		buttonPanel.Orientation = .Horizontal;
		buttonPanel.Spacing = 6;
		buttonPanel.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(buttonPanel, .Right);

		mStepButton = new Button("Step");
		mStepButton.Padding = Thickness(10, 4, 10, 4);
		mStepButton.Click.Subscribe(new (btn) => {
			mOnStep.[Friend]Invoke();
		});
		buttonPanel.AddChild(mStepButton);

		mSpeed1xButton = new Button("1x");
		mSpeed1xButton.Width = .Fixed(36);
		mSpeed1xButton.Padding = Thickness(4, 4, 4, 4);
		mSpeed1xButton.Click.Subscribe(new (btn) => {
			SetSpeedHighlight(1.0f);
			mOnSpeedChanged.[Friend]Invoke(1.0f);
		});
		buttonPanel.AddChild(mSpeed1xButton);

		mSpeed2xButton = new Button("2x");
		mSpeed2xButton.Width = .Fixed(36);
		mSpeed2xButton.Padding = Thickness(4, 4, 4, 4);
		mSpeed2xButton.Click.Subscribe(new (btn) => {
			SetSpeedHighlight(2.0f);
			mOnSpeedChanged.[Friend]Invoke(2.0f);
		});
		buttonPanel.AddChild(mSpeed2xButton);

		mSpeed4xButton = new Button("4x");
		mSpeed4xButton.Width = .Fixed(36);
		mSpeed4xButton.Padding = Thickness(4, 4, 4, 4);
		mSpeed4xButton.Click.Subscribe(new (btn) => {
			SetSpeedHighlight(4.0f);
			mOnSpeedChanged.[Friend]Invoke(4.0f);
		});
		buttonPanel.AddChild(mSpeed4xButton);

		mAutoStepButton = new Button("AutoStep");
		mAutoStepButton.Padding = Thickness(10, 4, 10, 4);
		mAutoStepButton.Click.Subscribe(new (btn) => {
			mOnAutoStepToggle.[Friend]Invoke();
		});
		buttonPanel.AddChild(mAutoStepButton);

		mAutoButton = new Button("Auto");
		mAutoButton.Padding = Thickness(10, 4, 10, 4);
		mAutoButton.Click.Subscribe(new (btn) => {
			mOnAutoToggle.[Friend]Invoke();
		});
		buttonPanel.AddChild(mAutoButton);

		mSkipButton = new Button("Skip");
		mSkipButton.Padding = Thickness(10, 4, 10, 4);
		mSkipButton.Click.Subscribe(new (btn) => {
			mOnSkip.[Friend]Invoke();
		});
		buttonPanel.AddChild(mSkipButton);

		content.AddChild(buttonPanel);

		mHudPanel.AddChild(topBar);

		// Set initial speed highlight
		SetSpeedHighlight(1.0f);
	}

	private void BuildTurnOrderBar()
	{
		mTurnOrderBar = new Border();
		mTurnOrderBar.Background = Color(10, 12, 18, 200);
		mTurnOrderBar.Height = .Fixed(30);
		mTurnOrderBar.Padding = Thickness(8, 3, 8, 3);
		DockPanelProperties.SetDock(mTurnOrderBar, .Top);

		mTurnOrderPanel = new StackPanel();
		mTurnOrderPanel.Orientation = .Horizontal;
		mTurnOrderPanel.Spacing = 3;
		mTurnOrderPanel.VerticalAlignment = .Center;
		mTurnOrderBar.Child = mTurnOrderPanel;

		// Pre-create fixed slots
		for (int32 i = 0; i < TURN_ORDER_SLOTS; i++)
		{
			let slot = new Border();
			slot.Width = .Fixed(70);
			slot.Height = .Fixed(22);
			slot.Padding = Thickness(4, 1, 4, 1);
			slot.Visibility = .Collapsed;

			let label = new TextBlock("");
			label.FontSize = 11;
			label.Foreground = Color(220, 220, 220);
			label.TextAlignment = .Center;
			label.VerticalAlignment = .Center;
			slot.Child = label;

			mTurnOrderSlots[i] = slot;
			mTurnOrderLabels[i] = label;
			mTurnOrderPanel.AddChild(slot);
		}

		mHudPanel.AddChild(mTurnOrderBar);
	}

	private void BuildActionPanel()
	{
		// Action panel — centered horizontally, above bottom panel
		// Contains Move/Attack/Skill/Wait buttons + phase hint + cancel
		mActionPanel = new Border();
		mActionPanel.Background = Color(20, 25, 35, 230);
		mActionPanel.Padding = Thickness(16, 10, 16, 10);
		mActionPanel.HorizontalAlignment = .Center;
		mActionPanel.VerticalAlignment = .Bottom;
		mActionPanel.Margin = Thickness(0, 0, 0, 90); // Above bottom panel
		mActionPanel.Visibility = .Collapsed;

		let actionContent = new StackPanel();
		actionContent.Orientation = .Vertical;
		actionContent.Spacing = 8;
		actionContent.HorizontalAlignment = .Center;
		mActionPanel.Child = actionContent;

		// Phase hint text
		mPhaseHintLabel = new TextBlock("");
		mPhaseHintLabel.Foreground = Color(200, 200, 220);
		mPhaseHintLabel.FontSize = 14;
		mPhaseHintLabel.TextAlignment = .Center;
		mPhaseHintLabel.Visibility = .Collapsed;
		actionContent.AddChild(mPhaseHintLabel);

		// Button row
		let buttonRow = new StackPanel();
		buttonRow.Orientation = .Horizontal;
		buttonRow.Spacing = 8;
		buttonRow.HorizontalAlignment = .Center;

		mMoveButton = new Button("Move");
		mMoveButton.Padding = Thickness(16, 8, 16, 8);
		mMoveButton.Click.Subscribe(new (btn) => {
			mOnMoveSelected.[Friend]Invoke();
		});
		buttonRow.AddChild(mMoveButton);

		mAttackButton = new Button("Attack");
		mAttackButton.Padding = Thickness(16, 8, 16, 8);
		mAttackButton.Click.Subscribe(new (btn) => {
			mOnAttackSelected.[Friend]Invoke();
		});
		buttonRow.AddChild(mAttackButton);

		mSkillButton = new Button("Skill");
		mSkillButton.Padding = Thickness(16, 8, 16, 8);
		mSkillButton.Click.Subscribe(new (btn) => {
			mOnSkillSelected.[Friend]Invoke();
		});
		buttonRow.AddChild(mSkillButton);

		mWaitButton = new Button("Wait");
		mWaitButton.Padding = Thickness(16, 8, 16, 8);
		mWaitButton.Click.Subscribe(new (btn) => {
			mOnWaitSelected.[Friend]Invoke();
		});
		buttonRow.AddChild(mWaitButton);

		mUndoButton = new Button("Undo Move");
		mUndoButton.Padding = Thickness(16, 8, 16, 8);
		mUndoButton.Visibility = .Collapsed;
		mUndoButton.Click.Subscribe(new (btn) => {
			mOnUndoMove.[Friend]Invoke();
		});
		buttonRow.AddChild(mUndoButton);

		mCancelButton = new Button("Cancel");
		mCancelButton.Padding = Thickness(16, 8, 16, 8);
		mCancelButton.Visibility = .Collapsed;
		mCancelButton.Click.Subscribe(new (btn) => {
			mOnCancelAction.[Friend]Invoke();
		});
		buttonRow.AddChild(mCancelButton);

		actionContent.AddChild(buttonRow);

		// Skill sub-panel (hidden by default)
		mSkillPanel = new Border();
		mSkillPanel.Background = Color(25, 30, 40, 240);
		mSkillPanel.Padding = Thickness(8, 6, 8, 6);
		mSkillPanel.Visibility = .Collapsed;

		mSkillListPanel = new StackPanel();
		mSkillListPanel.Orientation = .Vertical;
		mSkillListPanel.Spacing = 4;
		mSkillPanel.Child = mSkillListPanel;

		actionContent.AddChild(mSkillPanel);

		// Add to root grid (not dock panel — so it overlays freely)
		mRoot.AddChild(mActionPanel);
	}

	private void BuildDeploymentPanel()
	{
		// Deploy panel sits between top bar (44px) and bottom panel (80px).
		// Uses a Grid so the center area (3D scene) passes input through.
		mDeployPanel = new Border();
		mDeployPanel.IsHitTestVisible = false; // Pass-through: children handle their own hits
		mDeployPanel.HorizontalAlignment = .Stretch;
		mDeployPanel.VerticalAlignment = .Stretch;
		mDeployPanel.Margin = Thickness(0, 44, 0, 80); // Below top bar, above bottom panel
		mDeployPanel.Visibility = .Collapsed;

		let grid = new Grid();
		grid.IsHitTestVisible = false; // Pass-through
		grid.RowDefinitions.Add(new .() { Height = .Pixels(36) });  // Preset tabs
		grid.RowDefinitions.Add(new .() { Height = .Star });        // Main area
		grid.RowDefinitions.Add(new .() { Height = .Auto });        // Action bar
		grid.ColumnDefinitions.Add(new .() { Width = .Pixels(260) }); // Roster sidebar
		grid.ColumnDefinitions.Add(new .() { Width = .Star });        // Center (pass-through)
		mDeployPanel.Child = grid;

		// --- Row 0: Preset tab bar (spans both columns) ---
		let presetBar = new Border();
		presetBar.Background = Color(16, 18, 28, 240);
		presetBar.Padding = Thickness(8, 4, 8, 4);
		GridProperties.SetRow(presetBar, 0);
		GridProperties.SetColumnSpan(presetBar, 2);

		mDeployPresetTabPanel = new StackPanel();
		mDeployPresetTabPanel.Orientation = .Horizontal;
		mDeployPresetTabPanel.Spacing = 6;
		mDeployPresetTabPanel.VerticalAlignment = .Center;
		presetBar.Child = mDeployPresetTabPanel;
		grid.AddChild(presetBar);

		// --- Row 1, Col 0: Roster sidebar ---
		mDeployRosterPanel = new Border();
		mDeployRosterPanel.Background = Color(16, 18, 28, 240);
		mDeployRosterPanel.Padding = Thickness(6, 6, 6, 6);
		GridProperties.SetRow(mDeployRosterPanel, 1);
		GridProperties.SetColumn(mDeployRosterPanel, 0);

		let rosterLayout = new StackPanel();
		rosterLayout.Orientation = .Vertical;
		rosterLayout.Spacing = 6;
		mDeployRosterPanel.Child = rosterLayout;

		let rosterTitle = new TextBlock("ROSTER");
		rosterTitle.Foreground = Color(255, 215, 80);
		rosterTitle.FontSize = 14;
		rosterTitle.TextAlignment = .Center;
		rosterLayout.AddChild(rosterTitle);

		mDeployRosterScroll = new ScrollViewer();
		mDeployRosterScroll.VerticalScrollBarVisibility = .Auto;
		mDeployRosterScroll.HorizontalScrollBarVisibility = .Disabled;
		rosterLayout.AddChild(mDeployRosterScroll);

		mDeployRosterListPanel = new StackPanel();
		mDeployRosterListPanel.Orientation = .Vertical;
		mDeployRosterListPanel.Spacing = 3;
		mDeployRosterScroll.Content = mDeployRosterListPanel;

		grid.AddChild(mDeployRosterPanel);

		// --- Row 1, Col 1: Center area — EMPTY, input passes through to 3D scene ---

		// --- Row 2: Action bar (spans both columns) ---
		let actionBar = new Border();
		actionBar.Background = Color(20, 25, 35, 230);
		actionBar.Padding = Thickness(16, 8, 16, 8);
		GridProperties.SetRow(actionBar, 2);
		GridProperties.SetColumnSpan(actionBar, 2);

		let actionContent = new StackPanel();
		actionContent.Orientation = .Vertical;
		actionContent.Spacing = 6;
		actionContent.HorizontalAlignment = .Center;
		actionBar.Child = actionContent;

		// Main action row
		let actionRow = new StackPanel();
		actionRow.Orientation = .Horizontal;
		actionRow.Spacing = 12;
		actionRow.HorizontalAlignment = .Center;
		actionContent.AddChild(actionRow);

		mDeployHintLabel = new TextBlock("Select a unit from roster or grid to deploy.");
		mDeployHintLabel.Foreground = Color(200, 200, 220);
		mDeployHintLabel.FontSize = 13;
		mDeployHintLabel.VerticalAlignment = .Center;
		actionRow.AddChild(mDeployHintLabel);

		mRemoveUnitButton = new Button("Remove Unit");
		mRemoveUnitButton.Padding = Thickness(12, 6, 12, 6);
		mRemoveUnitButton.Visibility = .Collapsed;
		mRemoveUnitButton.Click.Subscribe(new (btn) => {
			mOnRemoveUnit.[Friend]Invoke();
		});
		actionRow.AddChild(mRemoveUnitButton);

		mSaveFormationButton = new Button("Save Formation");
		mSaveFormationButton.Padding = Thickness(12, 6, 12, 6);
		mSaveFormationButton.Click.Subscribe(new (btn) => {
			// Toggle save target panel
			mDeploySavePanel.Visibility = (mDeploySavePanel.Visibility == .Visible) ? .Collapsed : .Visible;
		});
		actionRow.AddChild(mSaveFormationButton);

		mStartBattleButton = new Button("Start Battle");
		mStartBattleButton.Padding = Thickness(16, 8, 16, 8);
		mStartBattleButton.Click.Subscribe(new (btn) => {
			mOnStartBattle.[Friend]Invoke();
		});
		actionRow.AddChild(mStartBattleButton);

		// Save-to-preset panel (hidden by default)
		mDeploySavePanel = new Border();
		mDeploySavePanel.Background = Color(25, 30, 40, 240);
		mDeploySavePanel.Padding = Thickness(8, 6, 8, 6);
		mDeploySavePanel.HorizontalAlignment = .Center;
		mDeploySavePanel.Visibility = .Collapsed;

		mDeploySaveListPanel = new StackPanel();
		mDeploySaveListPanel.Orientation = .Horizontal;
		mDeploySaveListPanel.Spacing = 6;
		mDeploySavePanel.Child = mDeploySaveListPanel;
		actionContent.AddChild(mDeploySavePanel);

		grid.AddChild(actionBar);

		mRoot.AddChild(mDeployPanel);
	}

	private void BuildStageSelectPanel()
	{
		mStageSelectPanel = new Border();
		mStageSelectPanel.Background = Color(0, 0, 0, 180);
		mStageSelectPanel.HorizontalAlignment = .Stretch;
		mStageSelectPanel.VerticalAlignment = .Stretch;
		mStageSelectPanel.Visibility = .Collapsed;

		// Card container
		let card = new Border();
		card.Background = Color(18, 22, 32, 240);
		card.Padding = Thickness(32, 24, 32, 24);
		card.HorizontalAlignment = .Center;
		card.VerticalAlignment = .Center;
		card.Width = .Fixed(400);
		mStageSelectPanel.Child = card;

		let layout = new StackPanel();
		layout.Orientation = .Vertical;
		layout.Spacing = 16;
		layout.HorizontalAlignment = .Stretch;
		card.Child = layout;

		let title = new TextBlock("SELECT STAGE");
		title.Foreground = Color(255, 215, 80);
		title.FontSize = 24;
		title.TextAlignment = .Center;
		title.HorizontalAlignment = .Center;
		layout.AddChild(title);

		// Divider
		let divider = new Border();
		divider.Background = Color(60, 65, 80);
		divider.Height = .Fixed(1);
		divider.HorizontalAlignment = .Stretch;
		layout.AddChild(divider);

		// Stage list (populated dynamically)
		mStageListPanel = new StackPanel();
		mStageListPanel.Orientation = .Vertical;
		mStageListPanel.Spacing = 8;
		mStageListPanel.HorizontalAlignment = .Stretch;
		layout.AddChild(mStageListPanel);

		mRoot.AddChild(mStageSelectPanel);
	}

	private void BuildBottomPanel()
	{
		mBottomPanel = new Border();
		mBottomPanel.Background = Color(15, 18, 25, 220);
		mBottomPanel.Height = .Fixed(80);
		mBottomPanel.Padding = Thickness(16, 8, 16, 8);
		DockPanelProperties.SetDock(mBottomPanel, .Bottom);

		let content = new StackPanel();
		content.Orientation = .Horizontal;
		content.Spacing = 40;
		content.VerticalAlignment = .Center;
		mBottomPanel.Child = content;

		// Current unit info (left side)
		{
			let unitPanel = new StackPanel();
			unitPanel.Orientation = .Vertical;
			unitPanel.Spacing = 2;
			unitPanel.Width = .Fixed(250);

			mUnitNameLabel = new TextBlock("---");
			mUnitNameLabel.Foreground = Color(255, 215, 80);
			mUnitNameLabel.FontSize = 16;
			unitPanel.AddChild(mUnitNameLabel);

			// HP bar + text row
			let hpRow = new StackPanel();
			hpRow.Orientation = .Horizontal;
			hpRow.Spacing = 8;

			mUnitHPBar = new ProgressBar();
			mUnitHPBar.Width = .Fixed(120);
			mUnitHPBar.Height = .Fixed(12);
			mUnitHPBar.Minimum = 0;
			mUnitHPBar.Maximum = 100;
			mUnitHPBar.Value = 100;
			hpRow.AddChild(mUnitHPBar);

			mUnitHPLabel = new TextBlock("HP: ---");
			mUnitHPLabel.Foreground = Color(180, 255, 180);
			mUnitHPLabel.FontSize = 14;
			hpRow.AddChild(mUnitHPLabel);

			unitPanel.AddChild(hpRow);

			mUnitClassLabel = new TextBlock("");
			mUnitClassLabel.Foreground = Color(170, 170, 180);
			mUnitClassLabel.FontSize = 14;
			unitPanel.AddChild(mUnitClassLabel);

			mUnitStatsLabel = new TextBlock("");
			mUnitStatsLabel.Foreground = Color(160, 160, 170);
			mUnitStatsLabel.FontSize = 13;
			unitPanel.AddChild(mUnitStatsLabel);

			content.AddChild(unitPanel);
		}

		// Separator
		{
			let sep = new Border();
			sep.Background = Color(60, 65, 75);
			sep.Width = .Fixed(1);
			sep.VerticalAlignment = .Stretch;
			content.AddChild(sep);
		}

		// Target info (right side, hidden by default)
		{
			mTargetPanel = new Border();
			mTargetPanel.Visibility = .Collapsed;

			let targetContent = new StackPanel();
			targetContent.Orientation = .Vertical;
			targetContent.Spacing = 2;
			targetContent.Width = .Fixed(220);
			mTargetPanel.Child = targetContent;

			let targetHeader = new TextBlock("TARGET");
			targetHeader.Foreground = Color(150, 150, 160);
			targetHeader.FontSize = 12;
			targetContent.AddChild(targetHeader);

			mTargetNameLabel = new TextBlock("");
			mTargetNameLabel.Foreground = Color(255, 180, 100);
			mTargetNameLabel.FontSize = 16;
			targetContent.AddChild(mTargetNameLabel);

			let targetHPRow = new StackPanel();
			targetHPRow.Orientation = .Horizontal;
			targetHPRow.Spacing = 8;

			mTargetHPBar = new ProgressBar();
			mTargetHPBar.Width = .Fixed(100);
			mTargetHPBar.Height = .Fixed(12);
			mTargetHPBar.Minimum = 0;
			mTargetHPBar.Maximum = 100;
			mTargetHPBar.Value = 100;
			targetHPRow.AddChild(mTargetHPBar);

			mTargetHPLabel = new TextBlock("HP: ---");
			mTargetHPLabel.Foreground = Color(180, 255, 180);
			mTargetHPLabel.FontSize = 14;
			targetHPRow.AddChild(mTargetHPLabel);

			targetContent.AddChild(targetHPRow);

			mTargetClassLabel = new TextBlock("");
			mTargetClassLabel.Foreground = Color(170, 170, 180);
			mTargetClassLabel.FontSize = 14;
			targetContent.AddChild(mTargetClassLabel);

			content.AddChild(mTargetPanel);
		}

		mHudPanel.AddChild(mBottomPanel);
	}

	private void BuildResultOverlay()
	{
		mResultOverlay = new Border();
		mResultOverlay.Background = Color(0, 0, 0, 160);
		mResultOverlay.HorizontalAlignment = .Stretch;
		mResultOverlay.VerticalAlignment = .Stretch;
		mResultOverlay.Visibility = .Collapsed;

		// Card container
		let card = new Border();
		card.Background = Color(18, 22, 32, 240);
		card.Padding = Thickness(32, 24, 32, 24);
		card.HorizontalAlignment = .Center;
		card.VerticalAlignment = .Center;
		card.Width = .Fixed(340);
		mResultOverlay.Child = card;

		let layout = new StackPanel();
		layout.Orientation = .Vertical;
		layout.Spacing = 16;
		layout.HorizontalAlignment = .Center;
		card.Child = layout;

		// Result banner
		mResultText = new TextBlock("VICTORY!");
		mResultText.Foreground = Color(255, 215, 80);
		mResultText.FontSize = 32;
		mResultText.TextAlignment = .Center;
		mResultText.HorizontalAlignment = .Center;
		layout.AddChild(mResultText);

		// Star row — 3 individual stars
		let starRow = new StackPanel();
		starRow.Orientation = .Horizontal;
		starRow.HorizontalAlignment = .Center;
		starRow.Spacing = 8;

		for (int32 i = 0; i < 3; i++)
		{
			let star = new TextBlock("\u{2606}");
			star.FontSize = 28;
			star.Foreground = Color(80, 80, 90);
			mStarLabels[i] = star;
			starRow.AddChild(star);
		}
		layout.AddChild(starRow);

		// Divider
		let divider = new Border();
		divider.Background = Color(60, 65, 80);
		divider.Height = .Fixed(1);
		divider.HorizontalAlignment = .Stretch;
		layout.AddChild(divider);

		// Stats section
		let statsPanel = new StackPanel();
		statsPanel.Orientation = .Vertical;
		statsPanel.Spacing = 6;
		statsPanel.HorizontalAlignment = .Stretch;

		mStatTurns = BuildStatRow(statsPanel, "Turns");
		mStatSurvivors = BuildStatRow(statsPanel, "Survivors");
		mStatKills = BuildStatRow(statsPanel, "Kills");
		mStatDamage = BuildStatRow(statsPanel, "Damage Dealt");
		mStatHealing = BuildStatRow(statsPanel, "Healing Done");

		layout.AddChild(statsPanel);

		// Divider
		let divider2 = new Border();
		divider2.Background = Color(60, 65, 80);
		divider2.Height = .Fixed(1);
		divider2.HorizontalAlignment = .Stretch;
		layout.AddChild(divider2);

		// Rewards section (hidden until populated)
		mRewardsPanel = new StackPanel();
		mRewardsPanel.Orientation = .Vertical;
		mRewardsPanel.Spacing = 4;
		mRewardsPanel.HorizontalAlignment = .Stretch;
		mRewardsPanel.Visibility = .Collapsed;

		let rewardsHeader = new TextBlock("REWARDS");
		rewardsHeader.Foreground = Color(255, 215, 80);
		rewardsHeader.FontSize = 16;
		rewardsHeader.TextAlignment = .Center;
		mRewardsPanel.AddChild(rewardsHeader);

		mRewardGoldLabel = new TextBlock("");
		mRewardGoldLabel.Foreground = Color(255, 215, 80);
		mRewardGoldLabel.FontSize = 14;
		mRewardsPanel.AddChild(mRewardGoldLabel);

		mRewardExpLabel = new TextBlock("");
		mRewardExpLabel.Foreground = Color(100, 200, 255);
		mRewardExpLabel.FontSize = 14;
		mRewardsPanel.AddChild(mRewardExpLabel);

		mRewardItemsPanel = new StackPanel();
		mRewardItemsPanel.Orientation = .Vertical;
		mRewardItemsPanel.Spacing = 2;
		mRewardsPanel.AddChild(mRewardItemsPanel);

		layout.AddChild(mRewardsPanel);

		// Divider
		let divider3 = new Border();
		divider3.Background = Color(60, 65, 80);
		divider3.Height = .Fixed(1);
		divider3.HorizontalAlignment = .Stretch;
		layout.AddChild(divider3);

		// Continue button
		mContinueButton = new Button("Continue");
		mContinueButton.Padding = Thickness(24, 10, 24, 10);
		mContinueButton.HorizontalAlignment = .Center;
		mContinueButton.Click.Subscribe(new (btn) => {
			mOnContinue.[Friend]Invoke();
		});
		layout.AddChild(mContinueButton);

		// Add overlay directly to root grid (on top of HUD)
		mRoot.AddChild(mResultOverlay);
	}

	/// Helper: creates a label + value row and returns the value TextBlock.
	private TextBlock BuildStatRow(StackPanel parent, StringView labelText)
	{
		let row = new DockPanel();
		row.HorizontalAlignment = .Stretch;
		row.LastChildFill = false;

		let label = new TextBlock(labelText);
		label.Foreground = Color(150, 155, 170);
		label.FontSize = 14;
		DockPanelProperties.SetDock(label, .Left);
		row.AddChild(label);

		let value = new TextBlock("--");
		value.Foreground = Color(230, 230, 240);
		value.FontSize = 14;
		DockPanelProperties.SetDock(value, .Right);
		row.AddChild(value);

		parent.AddChild(row);
		return value;
	}

	// --- Public update methods ---

	public void UpdateTurnInfo(int32 turnCount, int32 attackersAlive, int32 defendersAlive)
	{
		let turnStr = scope String();
		turnStr.AppendF("Turn: {}", turnCount);
		mTurnLabel.Text = turnStr;

		let atkStr = scope String();
		atkStr.AppendF("ATK: {}", attackersAlive);
		mAttackerLabel.Text = atkStr;

		let defStr = scope String();
		defStr.AppendF("DEF: {}", defendersAlive);
		mDefenderLabel.Text = defStr;
	}

	public void UpdateTurnOrder(Span<TurnOrderEntry> entries)
	{
		for (int32 i = 0; i < TURN_ORDER_SLOTS; i++)
		{
			if (i < entries.Length)
			{
				let entry = entries[i];
				mTurnOrderSlots[i].Visibility = .Visible;
				mTurnOrderLabels[i].Text = entry.mName;

				if (entry.mIsCurrent)
				{
					mTurnOrderSlots[i].Background = entry.mIsAttacker
						? Color(180, 80, 60, 255)
						: Color(60, 80, 180, 255);
					mTurnOrderLabels[i].Foreground = Color(255, 255, 200);
				}
				else
				{
					mTurnOrderSlots[i].Background = entry.mIsAttacker
						? Color(100, 40, 35, 200)
						: Color(35, 45, 100, 200);
					mTurnOrderLabels[i].Foreground = Color(200, 200, 210);
				}
			}
			else
			{
				mTurnOrderSlots[i].Visibility = .Collapsed;
			}
		}
	}

	public void UpdateCurrentUnit(StringView name, int32 hp, int32 maxHp, StringView unitClass,
		int32 atk, int32 def, int32 spd)
	{
		mUnitNameLabel.Text = name;

		let hpStr = scope String();
		hpStr.AppendF("HP: {}/{}", hp, maxHp);
		mUnitHPLabel.Text = hpStr;

		if (maxHp > 0)
		{
			mUnitHPBar.Maximum = (float)maxHp;
			mUnitHPBar.Value = (float)hp;
		}

		mUnitClassLabel.Text = unitClass;

		let statsStr = scope String();
		statsStr.AppendF("ATK:{}  DEF:{}  SPD:{}", atk, def, spd);
		mUnitStatsLabel.Text = statsStr;
	}

	public void ClearCurrentUnit()
	{
		mUnitNameLabel.Text = "---";
		mUnitHPLabel.Text = "HP: ---";
		mUnitHPBar.Value = 0;
		mUnitClassLabel.Text = "";
		mUnitStatsLabel.Text = "";
	}

	public void UpdateTargetInfo(StringView name, int32 hp, int32 maxHp, StringView unitClass)
	{
		mTargetPanel.Visibility = .Visible;

		mTargetNameLabel.Text = name;

		let hpStr = scope String();
		hpStr.AppendF("HP: {}/{}", hp, maxHp);
		mTargetHPLabel.Text = hpStr;

		if (maxHp > 0)
		{
			mTargetHPBar.Maximum = (float)maxHp;
			mTargetHPBar.Value = (float)hp;
		}

		mTargetClassLabel.Text = unitClass;
	}

	public void ClearTargetInfo()
	{
		mTargetPanel.Visibility = .Collapsed;
	}

	public void ShowBattleResult(StringView result, int32 stars, int32 turns, int32 surviving, int32 total,
		int32 damageDealt, int32 healingDone, int32 unitsKilled)
	{
		if (mResultShown) return;
		mResultShown = true;

		mResultText.Text = result;

		// Light up earned stars
		let goldColor = Color(255, 215, 80);
		let dimColor = Color(80, 80, 90);
		for (int32 i = 0; i < 3; i++)
		{
			mStarLabels[i].Text = i < stars ? "\u{2605}" : "\u{2606}";
			mStarLabels[i].Foreground = i < stars ? goldColor : dimColor;
		}

		// Populate stat values
		let turnsStr = scope String();
		turnsStr.AppendF("{}", turns);
		mStatTurns.Text = turnsStr;

		let survStr = scope String();
		survStr.AppendF("{} / {}", surviving, total);
		mStatSurvivors.Text = survStr;

		let killsStr = scope String();
		killsStr.AppendF("{}", unitsKilled);
		mStatKills.Text = killsStr;

		let dmgStr = scope String();
		dmgStr.AppendF("{}", damageDealt);
		mStatDamage.Text = dmgStr;

		let healStr = scope String();
		healStr.AppendF("{}", healingDone);
		mStatHealing.Text = healStr;

		mResultOverlay.Visibility = .Visible;
	}

	public void ResetResultState()
	{
		mResultShown = false;
		mResultOverlay.Visibility = .Collapsed;
		mRewardsPanel.Visibility = .Collapsed;
		mRewardItemsPanel.ClearChildren();
	}

	/// Show rewards in the result overlay. Call after ShowBattleResult.
	public void ShowRewards(int32 gold, int32 exp, Span<RewardDisplayInfo> items)
	{
		mRewardsPanel.Visibility = .Visible;

		let goldStr = scope String();
		goldStr.AppendF("Gold: +{}", gold);
		mRewardGoldLabel.Text = goldStr;

		let expStr = scope String();
		expStr.AppendF("EXP: +{}", exp);
		mRewardExpLabel.Text = expStr;

		mRewardItemsPanel.ClearChildren();
		for (let item in items)
		{
			let itemStr = scope String();
			itemStr.AppendF("{} x{}", item.mName, item.mQuantity);
			let label = new TextBlock(itemStr);
			label.Foreground = Color(200, 200, 210);
			label.FontSize = 13;
			mRewardItemsPanel.AddChild(label);
		}
	}

	public void SetAutoPlaying(bool isAuto)
	{
		mIsAutoPlaying = isAuto;
		if (isAuto)
			mAutoButton.Background = Color(60, 140, 60, 255);
		else
			mAutoButton.[Friend]mBackground = null; // Revert to theme default
	}

	public void SetAutoStepping(bool isAutoStep)
	{
		if (isAutoStep)
			mAutoStepButton.Background = Color(60, 140, 180, 255);
		else
			mAutoStepButton.[Friend]mBackground = null;
	}

	// --- Action panel methods ---

	public void ShowActionPanel(bool canMove, bool canAttack, bool hasSkills, bool isPostMove = false)
	{
		mActionPanel.Visibility = .Visible;
		mMoveButton.Visibility = isPostMove ? .Collapsed : .Visible;
		mAttackButton.Visibility = .Visible;
		mSkillButton.Visibility = hasSkills ? .Visible : .Collapsed;
		mWaitButton.Visibility = .Visible;
		mUndoButton.Visibility = isPostMove ? .Visible : .Collapsed;
		mCancelButton.Visibility = .Collapsed;
		mSkillPanel.Visibility = .Collapsed;
		mPhaseHintLabel.Visibility = .Collapsed;

		// Dim buttons for unavailable actions
		if (!isPostMove)
			mMoveButton.[Friend]mBackground = canMove ? null : Color(60, 60, 60, 255);
		mAttackButton.[Friend]mBackground = canAttack ? null : Color(60, 60, 60, 255);
	}

	public void HideActionPanel()
	{
		mActionPanel.Visibility = .Collapsed;
	}

	public void ShowSelectingMode(StringView hint)
	{
		mActionPanel.Visibility = .Visible;
		mMoveButton.Visibility = .Collapsed;
		mAttackButton.Visibility = .Collapsed;
		mSkillButton.Visibility = .Collapsed;
		mWaitButton.Visibility = .Collapsed;
		mSkillPanel.Visibility = .Collapsed;
		mCancelButton.Visibility = .Visible;

		mPhaseHintLabel.Visibility = .Visible;
		mPhaseHintLabel.Text = hint;
	}

	public void ShowSkillPanel(Span<SkillDisplayInfo> skills)
	{
		mActionPanel.Visibility = .Visible;
		mMoveButton.Visibility = .Collapsed;
		mAttackButton.Visibility = .Collapsed;
		mSkillButton.Visibility = .Collapsed;
		mWaitButton.Visibility = .Collapsed;
		mCancelButton.Visibility = .Visible;
		mPhaseHintLabel.Visibility = .Collapsed;

		// Clear old skill buttons
		mSkillListPanel.ClearChildren();
		mSkillPanel.Visibility = .Visible;

		for (let skill in skills)
		{
			let label = scope String();
			label.AppendF("{}", skill.mName);
			if (skill.mCooldownLeft > 0)
				label.AppendF(" (CD: {})", skill.mCooldownLeft);
			else
				label.Append(" (Ready)");

			let btn = new Button(label);
			btn.Padding = Thickness(12, 6, 12, 6);
			btn.HorizontalAlignment = .Stretch;

			if (!skill.mUsable)
				btn.[Friend]mBackground = Color(60, 60, 60, 255);

			let capturedSkillId = skill.mId;
			btn.Click.Subscribe(new (b) => {
				mOnSkillChosen.[Friend]Invoke(capturedSkillId);
			});
			mSkillListPanel.AddChild(btn);
		}
	}

	// --- Deployment panel methods ---

	public void ShowDeploymentPanel()
	{
		mDeployPanel.Visibility = .Visible;
		// Hide battle-specific controls during deployment (bottom panel stays for unit info)
		mTurnOrderBar.Visibility = .Collapsed;
		mActionPanel.Visibility = .Collapsed;
		mTitleLabel.Text = "DEPLOYMENT";
	}

	public void HideDeploymentPanel()
	{
		mDeployPanel.Visibility = .Collapsed;
		mDeploySavePanel.Visibility = .Collapsed;
		// Restore battle controls
		mTurnOrderBar.Visibility = .Visible;
		mBottomPanel.Visibility = .Visible;
		mTitleLabel.Text = "STORM TACTICS";
	}

	public void UpdateDeploymentHint(StringView text)
	{
		mDeployHintLabel.Text = text;
	}

	/// Rebuild the formation preset tabs during deployment.
	public void UpdateDeployPresetTabs(int32 presetCount, int32 activeIndex, Span<StringView> presetNames)
	{
		mDeployPresetTabPanel.ClearChildren();

		for (int32 i = 0; i < presetCount && i < presetNames.Length; i++)
		{
			let tabIdx = i;
			let tab = new Button(presetNames[i]);
			tab.Padding = Thickness(10, 3, 10, 3);
			if (i == activeIndex)
				tab.[Friend]mBackground = Color(60, 70, 100, 255);
			tab.Click.Subscribe(new (btn) => {
				mOnPresetSelected.[Friend]Invoke(tabIdx);
			});
			mDeployPresetTabPanel.AddChild(tab);
		}
	}

	/// Rebuild the roster unit list in the deployment sidebar.
	public void UpdateDeployRoster(Span<RosterUnitInfo> units)
	{
		mDeployRosterListPanel.ClearChildren();

		for (let info in units)
		{
			let unitId = info.mUnitId;
			let icon = GetOrCreateIcon(unitId, info.mUnitClass, info.mRarity);

			// Card content: icon left, info right
			let cardRow = new StackPanel();
			cardRow.Orientation = .Horizontal;
			cardRow.Spacing = 8;
			cardRow.VerticalAlignment = .Center;
			cardRow.IsHitTestVisible = false;

			// Unit icon
			let iconImg = new Image(icon);
			iconImg.Width = .Fixed(40);
			iconImg.Height = .Fixed(40);
			iconImg.Stretch = .UniformToFill;
			cardRow.AddChild(iconImg);

			// Info column
			let infoCol = new StackPanel();
			infoCol.Orientation = .Vertical;
			infoCol.Spacing = 1;
			infoCol.VerticalAlignment = .Center;

			let nameLabel = new TextBlock(info.mName);
			nameLabel.Foreground = info.mIsDeployed ? Color(150, 220, 150) : Color(220, 220, 230);
			nameLabel.FontSize = 13;
			infoCol.AddChild(nameLabel);

			// Class + deployed indicator
			let detailStr = scope String();
			info.mUnitClass.ToString(detailStr);
			if (info.mIsDeployed) detailStr.Append("  [D]");
			let detailLabel = new TextBlock(detailStr);
			detailLabel.Foreground = info.mIsDeployed ? Color(100, 170, 100) : Color(130, 130, 150);
			detailLabel.FontSize = 11;
			infoCol.AddChild(detailLabel);

			// Stats line
			let statsStr = scope String();
			statsStr.AppendF("HP:{} ATK:{} DEF:{} SPD:{}", info.mHP, info.mDamage, info.mDefense, info.mSpeed);
			let statsLabel = new TextBlock(statsStr);
			statsLabel.Foreground = Color(110, 120, 140);
			statsLabel.FontSize = 10;
			infoCol.AddChild(statsLabel);

			cardRow.AddChild(infoCol);

			// Button wrapping the card
			let btn = new Button();
			btn.Padding = Thickness(6, 4, 6, 4);
			btn.HorizontalAlignment = .Stretch;
			btn.[Friend]mBackground = info.mIsDeployed ? Color(30, 45, 35, 255) : Color(25, 30, 45, 255);
			btn.Content = cardRow;
			btn.Click.Subscribe(new (b) => {
				mOnRosterUnitSelected.[Friend]Invoke(unitId);
			});

			mDeployRosterListPanel.AddChild(btn);
		}
	}

	private OwnedImageData GetOrCreateIcon(int32 unitId, UnitClass unitClass, Rarity rarity)
	{
		if (mIconCache.TryGetValue(unitId, let existing))
			return existing;

		let icon = IconGenerator.GenerateUnitIcon(unitClass, rarity);
		mIconCache[unitId] = icon;
		return icon;
	}

	/// Toggle visibility of the "Remove Unit" button during deployment.
	public void ShowRemoveUnitButton(bool show)
	{
		mRemoveUnitButton.Visibility = show ? .Visible : .Collapsed;
	}

	/// Update the save-to-preset target buttons.
	public void UpdateDeploySaveTargets(int32 presetCount, Span<StringView> presetNames)
	{
		mDeploySaveListPanel.ClearChildren();

		let label = new TextBlock("Save to:");
		label.Foreground = Color(200, 200, 220);
		label.FontSize = 13;
		label.VerticalAlignment = .Center;
		mDeploySaveListPanel.AddChild(label);

		for (int32 i = 0; i < presetCount && i < presetNames.Length; i++)
		{
			let idx = i;
			let btn = new Button(presetNames[i]);
			btn.Padding = Thickness(10, 4, 10, 4);
			btn.Click.Subscribe(new (b) => {
				mOnSaveFormation.[Friend]Invoke(idx);
				mDeploySavePanel.Visibility = .Collapsed;
			});
			mDeploySaveListPanel.AddChild(btn);
		}

		let cancelBtn = new Button("Cancel");
		cancelBtn.Padding = Thickness(10, 4, 10, 4);
		cancelBtn.Click.Subscribe(new (b) => {
			mDeploySavePanel.Visibility = .Collapsed;
		});
		mDeploySaveListPanel.AddChild(cancelBtn);
	}

	// --- Stage selection methods ---

	public void ShowStageSelect(Span<StageDisplayInfo> stages)
	{
		// Hide battle HUD
		mHudPanel.Visibility = .Collapsed;
		mActionPanel.Visibility = .Collapsed;
		mDeployPanel.Visibility = .Collapsed;
		mResultOverlay.Visibility = .Collapsed;

		// Populate stage buttons
		mStageListPanel.ClearChildren();
		for (let stage in stages)
		{
			let stageBtn = new Border();
			stageBtn.Background = Color(30, 35, 50, 255);
			stageBtn.Padding = Thickness(16, 10, 16, 10);
			stageBtn.HorizontalAlignment = .Stretch;

			let row = new DockPanel();
			row.HorizontalAlignment = .Stretch;
			row.LastChildFill = false;
			stageBtn.Child = row;

			// Stage name (left)
			let nameLabel = new TextBlock(stage.mName);
			nameLabel.Foreground = Color(230, 230, 240);
			nameLabel.FontSize = 16;
			DockPanelProperties.SetDock(nameLabel, .Left);
			row.AddChild(nameLabel);

			// Difficulty + enemy count (right)
			let infoStr = scope String();
			infoStr.AppendF("Diff:{} | {}x", stage.mDifficulty, stage.mEnemyCount);
			let infoLabel = new TextBlock(infoStr);
			infoLabel.Foreground = Color(150, 155, 170);
			infoLabel.FontSize = 14;
			DockPanelProperties.SetDock(infoLabel, .Right);
			row.AddChild(infoLabel);

			// Make the whole border clickable via a transparent button overlay
			let btn = new Button("");
			btn.Background = Color(0, 0, 0, 0);
			btn.HorizontalAlignment = .Stretch;
			btn.VerticalAlignment = .Stretch;
			btn.Padding = Thickness(0);
			let capturedId = stage.mId;
			btn.Click.Subscribe(new (b) => {
				mOnStageSelected.[Friend]Invoke(capturedId);
			});

			// Wrap in a grid so button overlays the border content
			let wrapper = new Grid();
			wrapper.HorizontalAlignment = .Stretch;
			wrapper.RowDefinitions.Add(new .() { Height = .Auto });
			wrapper.ColumnDefinitions.Add(new .() { Width = .Star });
			wrapper.AddChild(stageBtn);
			wrapper.AddChild(btn);

			mStageListPanel.AddChild(wrapper);
		}

		mStageSelectPanel.Visibility = .Visible;
	}

	public void HideStageSelect()
	{
		mStageSelectPanel.Visibility = .Collapsed;
		mHudPanel.Visibility = .Visible;
	}

	// --- Helpers ---

	private void SetSpeedHighlight(float speed)
	{
		mCurrentSpeed = speed;
		let activeColor = Color(60, 140, 180, 255);

		mSpeed1xButton.[Friend]mBackground = (speed == 1.0f) ? activeColor : null;
		mSpeed2xButton.[Friend]mBackground = (speed == 2.0f) ? activeColor : null;
		mSpeed4xButton.[Friend]mBackground = (speed == 4.0f) ? activeColor : null;
	}
}

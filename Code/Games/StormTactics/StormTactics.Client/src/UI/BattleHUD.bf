namespace StormTactics.Client;

using System;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;

delegate void BattleActionDelegate();
delegate void SpeedChangeDelegate(float speed);
delegate void SkillSelectDelegate(int32 skillId);

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
	private Button mContinueButton;

	// Action panel (player turn)
	private Border mActionPanel;
	private Button mMoveButton;
	private Button mAttackButton;
	private Button mSkillButton;
	private Button mWaitButton;

	// Skill selection panel
	private Border mSkillPanel;
	private StackPanel mSkillListPanel;

	// Phase hint + cancel
	private TextBlock mPhaseHintLabel;
	private Button mCancelButton;

	// State
	private bool mIsAutoPlaying;
	private float mCurrentSpeed = 1.0f;
	private bool mResultShown;

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

		let centerPanel = new StackPanel();
		centerPanel.Orientation = .Vertical;
		centerPanel.HorizontalAlignment = .Center;
		centerPanel.VerticalAlignment = .Center;
		centerPanel.Spacing = 20;
		mResultOverlay.Child = centerPanel;

		mResultText = new TextBlock("VICTORY!");
		mResultText.Foreground = Color(255, 215, 80);
		mResultText.FontSize = 32;
		mResultText.TextAlignment = .Center;
		centerPanel.AddChild(mResultText);

		mContinueButton = new Button("Continue");
		mContinueButton.Padding = Thickness(24, 10, 24, 10);
		mContinueButton.HorizontalAlignment = .Center;
		mContinueButton.Click.Subscribe(new (btn) => {
			mOnContinue.[Friend]Invoke();
		});
		centerPanel.AddChild(mContinueButton);

		// Add overlay directly to root grid (on top of HUD)
		mRoot.AddChild(mResultOverlay);
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

	public void ShowBattleResult(StringView result)
	{
		if (mResultShown) return;
		mResultShown = true;

		mResultText.Text = result;
		mResultOverlay.Visibility = .Visible;
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

	public void ShowActionPanel(bool canMove, bool canAttack, bool hasSkills)
	{
		mActionPanel.Visibility = .Visible;
		mMoveButton.Visibility = .Visible;
		mAttackButton.Visibility = .Visible;
		mSkillButton.Visibility = hasSkills ? .Visible : .Collapsed;
		mWaitButton.Visibility = .Visible;
		mCancelButton.Visibility = .Collapsed;
		mSkillPanel.Visibility = .Collapsed;
		mPhaseHintLabel.Visibility = .Collapsed;

		// Dim buttons for unavailable actions
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

namespace StormTactics.Client;

using System;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;

delegate void BattleActionDelegate();
delegate void SpeedChangeDelegate(float speed);

/// Retained-mode battle HUD using Sedulous.GUI.
/// Provides turn info, speed controls, unit info panels, and battle result overlay.
class BattleHUD
{
	// Root layout
	private Grid mRoot ~ delete _;
	private DockPanel mHudPanel;

	// Top bar elements
	private TextBlock mTitleLabel;
	private TextBlock mTurnLabel;
	private TextBlock mAttackerLabel;
	private TextBlock mDefenderLabel;
	private Button mSpeed1xButton;
	private Button mSpeed2xButton;
	private Button mSpeed4xButton;
	private Button mAutoButton;
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

	// State
	private bool mIsAutoPlaying;
	private float mCurrentSpeed = 1.0f;
	private bool mResultShown;

	// Events
	private EventAccessor<BattleActionDelegate> mOnAutoToggle = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnSkip = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnStep = new .() ~ delete _;
	private EventAccessor<SpeedChangeDelegate> mOnSpeedChanged = new .() ~ delete _;
	private EventAccessor<BattleActionDelegate> mOnContinue = new .() ~ delete _;

	public EventAccessor<BattleActionDelegate> OnAutoToggle => mOnAutoToggle;
	public EventAccessor<BattleActionDelegate> OnSkip => mOnSkip;
	public EventAccessor<BattleActionDelegate> OnStep => mOnStep;
	public EventAccessor<SpeedChangeDelegate> OnSpeedChanged => mOnSpeedChanged;
	public EventAccessor<BattleActionDelegate> OnContinue => mOnContinue;

	public UIElement RootElement => mRoot;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		// Grid as root — allows overlays on top of HUD
		mRoot = new Grid();
		mRoot.Background = Color.Transparent;
		mRoot.RowDefinitions.Add(new .() { Height = .Star });
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });

		// DockPanel for HUD elements
		mHudPanel = new DockPanel();
		mHudPanel.Background = Color.Transparent;
		mHudPanel.HorizontalAlignment = .Stretch;
		mHudPanel.VerticalAlignment = .Stretch;
		mHudPanel.LastChildFill = false;
		mRoot.AddChild(mHudPanel);

		BuildTopBar();
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

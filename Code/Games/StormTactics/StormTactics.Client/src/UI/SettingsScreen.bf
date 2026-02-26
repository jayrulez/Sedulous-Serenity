namespace StormTactics.Client;

using System;
using Sedulous.GUI;
using Sedulous.Foundation.Mathematics;
using Sedulous.Foundation.Core;
using StormTactics.Core;

delegate void SettingsBackDelegate();
delegate void SettingsChangedDelegate();

/// Settings screen: toggle options for camera, battle, and display settings.
class SettingsScreen
{
	private Grid mRoot ~ delete _;

	// Toggle buttons
	private Button mCameraPanToggle;
	private TextBlock mCameraPanValue;
	private Button mAutoStepToggle;
	private TextBlock mAutoStepValue;
	private Button mAutoBattleToggle;
	private TextBlock mAutoBattleValue;
	private Button mBattleSpeedToggle;
	private TextBlock mBattleSpeedValue;

	// Current settings reference
	private GameSettings mSettings;

	// Events
	private EventAccessor<SettingsBackDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<SettingsChangedDelegate> mOnChanged = new .() ~ delete _;

	public EventAccessor<SettingsBackDelegate> OnBack => mOnBack;
	public EventAccessor<SettingsChangedDelegate> OnChanged => mOnChanged;
	public UIElement RootElement => mRoot;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		mRoot = new Grid();
		mRoot.Background = Color(12, 14, 22, 255);
		mRoot.HorizontalAlignment = .Stretch;
		mRoot.VerticalAlignment = .Stretch;
		mRoot.RowDefinitions.Add(new .() { Height = .Pixels(48) }); // Top bar
		mRoot.RowDefinitions.Add(new .() { Height = .Star });       // Content
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });

		BuildTopBar();
		BuildContent();
	}

	private void BuildTopBar()
	{
		let topBar = new Border();
		topBar.Background = Color(18, 22, 32, 240);
		topBar.Padding = Thickness(12, 8, 12, 8);
		GridProperties.SetRow(topBar, 0);

		let content = new DockPanel();
		content.LastChildFill = false;
		content.VerticalAlignment = .Center;
		topBar.Child = content;

		let backBtn = new Button("Back");
		backBtn.Padding = Thickness(16, 4, 16, 4);
		backBtn.Click.Subscribe(new (btn) => { mOnBack.[Friend]Invoke(); });
		DockPanelProperties.SetDock(backBtn, .Left);
		content.AddChild(backBtn);

		let title = new TextBlock("SETTINGS");
		title.Foreground = Color(255, 215, 80);
		title.FontSize = 20;
		title.Margin = Thickness(16, 0, 0, 0);
		title.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(title, .Left);
		content.AddChild(title);

		mRoot.AddChild(topBar);
	}

	private void BuildContent()
	{
		let centerPanel = new StackPanel();
		centerPanel.Orientation = .Vertical;
		centerPanel.Spacing = 16;
		centerPanel.HorizontalAlignment = .Center;
		centerPanel.VerticalAlignment = .Center;
		centerPanel.Width = .Fixed(400);
		GridProperties.SetRow(centerPanel, 1);

		// Section: Camera
		AddSectionHeader(centerPanel, "Camera");

		(mCameraPanToggle, mCameraPanValue) = AddToggleRow(centerPanel, "Camera Pan Mode", "Normal");
		mCameraPanToggle.Click.Subscribe(new (btn) => {
			if (mSettings != null)
			{
				mSettings.mInvertCameraPan = !mSettings.mInvertCameraPan;
				if (mRoot.Context != null)
				{
					mRoot.Context.MutationQueue.QueueAction(new () => {
						RefreshValues();
						mOnChanged.[Friend]Invoke();
					});
				}
			}
		});

		// Divider
		AddDivider(centerPanel);

		// Section: Battle
		AddSectionHeader(centerPanel, "Battle");

		(mAutoStepToggle, mAutoStepValue) = AddToggleRow(centerPanel, "Auto-Step Enemy Turns", "ON");
		mAutoStepToggle.Click.Subscribe(new (btn) => {
			if (mSettings != null)
			{
				mSettings.mAutoStepDefault = !mSettings.mAutoStepDefault;
				if (mRoot.Context != null)
				{
					mRoot.Context.MutationQueue.QueueAction(new () => {
						RefreshValues();
						mOnChanged.[Friend]Invoke();
					});
				}
			}
		});

		(mAutoBattleToggle, mAutoBattleValue) = AddToggleRow(centerPanel, "Auto-Battle Default", "OFF");
		mAutoBattleToggle.Click.Subscribe(new (btn) => {
			if (mSettings != null)
			{
				mSettings.mAutoBattleDefault = !mSettings.mAutoBattleDefault;
				if (mRoot.Context != null)
				{
					mRoot.Context.MutationQueue.QueueAction(new () => {
						RefreshValues();
						mOnChanged.[Friend]Invoke();
					});
				}
			}
		});

		(mBattleSpeedToggle, mBattleSpeedValue) = AddToggleRow(centerPanel, "Default Battle Speed", "1x");
		mBattleSpeedToggle.Click.Subscribe(new (btn) => {
			if (mSettings != null)
			{
				// Cycle through 1 → 2 → 4 → 1
				switch (mSettings.mDefaultBattleSpeed)
				{
				case 1: mSettings.mDefaultBattleSpeed = 2;
				case 2: mSettings.mDefaultBattleSpeed = 4;
				default: mSettings.mDefaultBattleSpeed = 1;
				}
				if (mRoot.Context != null)
				{
					mRoot.Context.MutationQueue.QueueAction(new () => {
						RefreshValues();
						mOnChanged.[Friend]Invoke();
					});
				}
			}
		});

		mRoot.AddChild(centerPanel);
	}

	private void AddSectionHeader(StackPanel parent, StringView text)
	{
		let label = new TextBlock(text);
		label.Foreground = Color(255, 215, 80);
		label.FontSize = 18;
		label.Margin = Thickness(0, 8, 0, 4);
		parent.AddChild(label);
	}

	private void AddDivider(StackPanel parent)
	{
		let div = new Border();
		div.Background = Color(60, 65, 80);
		div.Height = .Fixed(1);
		div.HorizontalAlignment = .Stretch;
		div.Margin = Thickness(0, 8, 0, 8);
		parent.AddChild(div);
	}

	private (Button, TextBlock) AddToggleRow(StackPanel parent, StringView label, StringView initialValue)
	{
		let row = new DockPanel();
		row.HorizontalAlignment = .Stretch;
		row.LastChildFill = false;

		let nameLabel = new TextBlock(label);
		nameLabel.Foreground = Color(200, 200, 220);
		nameLabel.FontSize = 16;
		nameLabel.VerticalAlignment = .Center;
		nameLabel.IsHitTestVisible = false;
		DockPanelProperties.SetDock(nameLabel, .Left);
		row.AddChild(nameLabel);

		let btn = new Button();
		btn.Width = .Fixed(120);
		btn.Padding = Thickness(8, 6, 8, 6);
		DockPanelProperties.SetDock(btn, .Right);

		let valueLabel = new TextBlock(initialValue);
		valueLabel.Foreground = Color(220, 220, 240);
		valueLabel.FontSize = 16;
		valueLabel.TextAlignment = .Center;
		valueLabel.HorizontalAlignment = .Center;
		valueLabel.IsHitTestVisible = false;
		btn.Content = valueLabel;

		row.AddChild(btn);
		parent.AddChild(row);

		return (btn, valueLabel);
	}

	/// Refresh the screen with the given settings.
	public void Refresh(GameSettings settings)
	{
		mSettings = settings;
		RefreshValues();
	}

	private void RefreshValues()
	{
		if (mSettings == null) return;

		mCameraPanValue.Text = mSettings.mInvertCameraPan ? "Inverted" : "Normal";
		mAutoStepValue.Text = mSettings.mAutoStepDefault ? "ON" : "OFF";
		mAutoBattleValue.Text = mSettings.mAutoBattleDefault ? "ON" : "OFF";

		let speedStr = scope String();
		speedStr.AppendF("{}x", mSettings.mDefaultBattleSpeed);
		mBattleSpeedValue.Text = speedStr;
	}
}

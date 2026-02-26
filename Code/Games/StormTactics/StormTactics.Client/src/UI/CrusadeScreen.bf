namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Foundation.Mathematics;
using Sedulous.Foundation.Core;
using StormTactics.Core;
using StormTactics.Game;

delegate void WaveSelectDelegate(int32 waveIndex);

/// Crusade screen showing sequential wave cards with progress and weekly reset timer.
class CrusadeScreen
{
	private Grid mRoot ~ delete _;

	// Top bar
	private TextBlock mTimerLabel;
	private TextBlock mProgressLabel;

	// Wave cards (dynamic count)
	private List<Border> mCardBorders = new .() ~ delete _;
	private List<TextBlock> mCardNames = new .() ~ delete _;
	private List<TextBlock> mCardRewards = new .() ~ delete _;
	private List<Button> mCardButtons = new .() ~ delete _;
	private List<TextBlock> mCardButtonLabels = new .() ~ delete _;
	private StackPanel mCardStack;

	// Events
	private EventAccessor<HubNavigationDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<WaveSelectDelegate> mOnStartWave = new .() ~ delete _;

	public EventAccessor<HubNavigationDelegate> OnBack => mOnBack;
	public EventAccessor<WaveSelectDelegate> OnStartWave => mOnStartWave;
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

		mRoot.RowDefinitions.Add(new .() { Height = .Pixels(48) });
		mRoot.RowDefinitions.Add(new .() { Height = .Star });
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });

		BuildTopBar();
		BuildCardList();
	}

	private void BuildTopBar()
	{
		let topBar = new Border();
		topBar.Background = Color(18, 22, 32, 240);
		topBar.Padding = Thickness(12, 8, 16, 8);
		GridProperties.SetRow(topBar, 0);

		let content = new DockPanel();
		content.LastChildFill = false;
		content.VerticalAlignment = .Center;
		topBar.Child = content;

		// Left: Back button + title
		let leftPanel = new StackPanel();
		leftPanel.Orientation = .Horizontal;
		leftPanel.Spacing = 12;
		leftPanel.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(leftPanel, .Left);

		let backBtn = new Button();
		backBtn.Width = .Fixed(70);
		backBtn.Height = .Fixed(30);
		backBtn.Background = Color(60, 30, 30);

		let backLabel = new TextBlock("< Back");
		backLabel.Foreground = Color(200, 200, 200);
		backLabel.FontSize = 14;
		backLabel.TextAlignment = .Center;
		backLabel.HorizontalAlignment = .Center;
		backLabel.IsHitTestVisible = false;
		backBtn.Content = backLabel;
		backBtn.Click.Subscribe(new (btn) => { mOnBack.[Friend]Invoke(); });
		leftPanel.AddChild(backBtn);

		let title = new TextBlock("CRUSADE");
		title.Foreground = Color(60, 120, 140);
		title.FontSize = 20;
		leftPanel.AddChild(title);

		mProgressLabel = new TextBlock("0/15 waves");
		mProgressLabel.Foreground = Color(160, 160, 180);
		mProgressLabel.FontSize = 14;
		mProgressLabel.VerticalAlignment = .Center;
		leftPanel.AddChild(mProgressLabel);

		content.AddChild(leftPanel);

		// Right: Reset timer
		let rightPanel = new StackPanel();
		rightPanel.Orientation = .Horizontal;
		rightPanel.Spacing = 8;
		rightPanel.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(rightPanel, .Right);

		let timerCaption = new TextBlock("Resets in:");
		timerCaption.Foreground = Color(140, 140, 160);
		timerCaption.FontSize = 14;
		rightPanel.AddChild(timerCaption);

		mTimerLabel = new TextBlock("--:--:--");
		mTimerLabel.Foreground = Color(200, 200, 220);
		mTimerLabel.FontSize = 16;
		rightPanel.AddChild(mTimerLabel);

		content.AddChild(rightPanel);

		mRoot.AddChild(topBar);
	}

	private void BuildCardList()
	{
		let scroll = new ScrollViewer();
		scroll.HorizontalAlignment = .Stretch;
		scroll.VerticalAlignment = .Stretch;
		scroll.Padding = Thickness(24, 16, 24, 16);
		GridProperties.SetRow(scroll, 1);

		mCardStack = new StackPanel();
		mCardStack.Orientation = .Vertical;
		mCardStack.Spacing = 8;
		mCardStack.HorizontalAlignment = .Stretch;
		scroll.Content = mCardStack;

		mRoot.AddChild(scroll);
	}

	private void BuildWaveCard(int32 index)
	{
		let card = new Border();
		card.Background = Color(22, 26, 38, 255);
		card.BorderBrush = Color(50, 55, 70);
		card.BorderThickness = Thickness(1);
		card.Padding = Thickness(16, 10, 16, 10);
		card.HorizontalAlignment = .Stretch;
		mCardBorders.Add(card);

		let dock = new DockPanel();
		dock.LastChildFill = true;
		card.Child = dock;

		// Right: Button
		let btnPanel = new StackPanel();
		btnPanel.Orientation = .Vertical;
		btnPanel.VerticalAlignment = .Center;
		btnPanel.Margin = Thickness(16, 0, 0, 0);
		DockPanelProperties.SetDock(btnPanel, .Right);

		let btn = new Button();
		btn.Width = .Fixed(100);
		btn.Height = .Fixed(34);
		btn.Background = Color(80, 80, 90);
		mCardButtons.Add(btn);

		let btnLabel = new TextBlock("LOCKED");
		btnLabel.Foreground = Color.White;
		btnLabel.FontSize = 14;
		btnLabel.TextAlignment = .Center;
		btnLabel.HorizontalAlignment = .Center;
		btnLabel.IsHitTestVisible = false;
		mCardButtonLabels.Add(btnLabel);
		btn.Content = btnLabel;

		let capturedIndex = index;
		btn.Click.Subscribe(new (b) => {
			mOnStartWave.[Friend]Invoke(capturedIndex);
		});

		btnPanel.AddChild(btn);
		dock.AddChild(btnPanel);

		// Left: Name + rewards
		let infoPanel = new StackPanel();
		infoPanel.Orientation = .Vertical;
		infoPanel.Spacing = 3;

		let nameLabel = new TextBlock();
		nameLabel.Foreground = Color(60, 120, 140);
		nameLabel.FontSize = 16;
		mCardNames.Add(nameLabel);
		infoPanel.AddChild(nameLabel);

		let rewardLabel = new TextBlock();
		rewardLabel.Foreground = Color(140, 140, 160);
		rewardLabel.FontSize = 13;
		mCardRewards.Add(rewardLabel);
		infoPanel.AddChild(rewardLabel);

		dock.AddChild(infoPanel);

		mCardStack.AddChild(card);
	}

	/// Refresh the screen with current crusade data.
	public void Show(CrusadeManager manager)
	{
		// Rebuild cards if count changed
		if (mCardBorders.Count != manager.WaveCount)
		{
			mCardBorders.Clear();
			mCardNames.Clear();
			mCardRewards.Clear();
			mCardButtons.Clear();
			mCardButtonLabels.Clear();
			mCardStack.ClearChildren();

			for (int32 i = 0; i < manager.WaveCount; i++)
				BuildWaveCard(i);
		}

		// Update progress + pool usage
		let progStr = scope String();
		progStr.AppendF("{}/{} waves   Units: {}/{}", manager.CurrentWave, manager.WaveCount,
			manager.UsedUnitCount, manager.MaxUnitPool);
		mProgressLabel.Text = progStr;

		for (int32 i = 0; i < manager.WaveCount; i++)
		{
			let wave = manager.GetWave(i);
			if (wave == null) continue;

			// Name
			mCardNames[i].Text = wave.mName;

			// Rewards
			let rewardStr = scope String();
			rewardStr.AppendF("Rewards:  {} Gold   {} EXP", wave.mGoldReward, wave.mExpReward);
			if (wave.mGemReward > 0)
				rewardStr.AppendF("   {} Gems", wave.mGemReward);
			mCardRewards[i].Text = rewardStr;

			// Button state: wave IDs are 1-based, CurrentWave is count of cleared waves
			let waveNum = i + 1;
			if (waveNum <= manager.CurrentWave)
			{
				mCardButtonLabels[i].Text = "CLEARED";
				mCardButtons[i].Background = Color(40, 100, 40);
				mCardButtons[i].IsEnabled = false;
				mCardBorders[i].BorderBrush = Color(40, 100, 40);
			}
			else if (waveNum == manager.CurrentWave + 1)
			{
				mCardButtonLabels[i].Text = "BATTLE";
				mCardButtons[i].Background = Color(60, 120, 140);
				mCardButtons[i].IsEnabled = true;
				mCardBorders[i].BorderBrush = Color(60, 120, 140);
			}
			else
			{
				mCardButtonLabels[i].Text = "LOCKED";
				mCardButtons[i].Background = Color(50, 55, 70);
				mCardButtons[i].IsEnabled = false;
				mCardBorders[i].BorderBrush = Color(50, 55, 70);
			}
		}

		if (manager.IsComplete)
		{
			mProgressLabel.Text = "COMPLETE!";
		}
	}

	/// Update the reset countdown timer display.
	public void UpdateTimer(int32 secondsRemaining)
	{
		let days = secondsRemaining / 86400;
		let hours = (secondsRemaining % 86400) / 3600;
		let minutes = (secondsRemaining % 3600) / 60;
		let seconds = secondsRemaining % 60;

		let timerStr = scope String();
		if (days > 0)
			timerStr.AppendF("{}d {:02}:{:02}:{:02}", days, hours, minutes, seconds);
		else
			timerStr.AppendF("{:02}:{:02}:{:02}", hours, minutes, seconds);
		mTimerLabel.Text = timerStr;
	}
}

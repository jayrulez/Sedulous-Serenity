namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;
using StormTactics.Core;
using StormTactics.Game;

delegate void FloorSelectDelegate(int32 floorIndex);

/// Tower screen showing sequential floor cards with progress and daily reset timer.
class TowerScreen
{
	private Grid mRoot ~ delete _;

	// Top bar
	private TextBlock mTimerLabel;
	private TextBlock mProgressLabel;

	// Floor cards (dynamic count)
	private List<Border> mCardBorders = new .() ~ delete _;
	private List<TextBlock> mCardNames = new .() ~ delete _;
	private List<TextBlock> mCardRewards = new .() ~ delete _;
	private List<Button> mCardButtons = new .() ~ delete _;
	private List<TextBlock> mCardButtonLabels = new .() ~ delete _;
	private StackPanel mCardStack;

	// Events
	private EventAccessor<HubNavigationDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<FloorSelectDelegate> mOnStartFloor = new .() ~ delete _;

	public EventAccessor<HubNavigationDelegate> OnBack => mOnBack;
	public EventAccessor<FloorSelectDelegate> OnStartFloor => mOnStartFloor;
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

		let title = new TextBlock("TOWER");
		title.Foreground = Color(140, 100, 60);
		title.FontSize = 20;
		leftPanel.AddChild(title);

		mProgressLabel = new TextBlock("0/10 cleared");
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

	private void BuildFloorCard(int32 index)
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
			mOnStartFloor.[Friend]Invoke(capturedIndex);
		});

		btnPanel.AddChild(btn);
		dock.AddChild(btnPanel);

		// Left: Name + rewards
		let infoPanel = new StackPanel();
		infoPanel.Orientation = .Vertical;
		infoPanel.Spacing = 3;

		let nameLabel = new TextBlock();
		nameLabel.Foreground = Color(140, 100, 60);
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

	/// Refresh the screen with current tower data.
	public void Show(TowerManager manager)
	{
		// Rebuild cards if count changed
		if (mCardBorders.Count != manager.FloorCount)
		{
			mCardBorders.Clear();
			mCardNames.Clear();
			mCardRewards.Clear();
			mCardButtons.Clear();
			mCardButtonLabels.Clear();
			mCardStack.ClearChildren();

			for (int32 i = 0; i < manager.FloorCount; i++)
				BuildFloorCard(i);
		}

		// Update progress
		let progStr = scope String();
		progStr.AppendF("{}/{} cleared", manager.CurrentFloor, manager.FloorCount);
		mProgressLabel.Text = progStr;

		for (int32 i = 0; i < manager.FloorCount; i++)
		{
			let floor = manager.GetFloor(i);
			if (floor == null) continue;

			// Name
			mCardNames[i].Text = floor.mName;

			// Rewards
			let rewardStr = scope String();
			rewardStr.AppendF("Rewards:  {} Gold   {} EXP", floor.mGoldReward, floor.mExpReward);
			if (floor.mGemReward > 0)
				rewardStr.AppendF("   {} Gems", floor.mGemReward);
			mCardRewards[i].Text = rewardStr;

			// Button state: floor IDs are 1-based, CurrentFloor is count of cleared floors
			let floorNum = i + 1; // 1-based floor number
			if (floorNum <= manager.CurrentFloor)
			{
				// Cleared
				mCardButtonLabels[i].Text = "CLEARED";
				mCardButtons[i].Background = Color(40, 100, 40);
				mCardButtons[i].IsEnabled = false;
				mCardBorders[i].BorderBrush = Color(40, 100, 40);
			}
			else if (floorNum == manager.CurrentFloor + 1)
			{
				// Next floor to fight
				mCardButtonLabels[i].Text = "BATTLE";
				mCardButtons[i].Background = Color(140, 100, 60);
				mCardButtons[i].IsEnabled = true;
				mCardBorders[i].BorderBrush = Color(140, 100, 60);
			}
			else
			{
				// Locked
				mCardButtonLabels[i].Text = "LOCKED";
				mCardButtons[i].Background = Color(50, 55, 70);
				mCardButtons[i].IsEnabled = false;
				mCardBorders[i].BorderBrush = Color(50, 55, 70);
			}
		}

		// If complete, show all as cleared
		if (manager.IsComplete)
		{
			mProgressLabel.Text = "COMPLETE!";
		}
	}

	/// Update the reset countdown timer display.
	public void UpdateTimer(int32 secondsRemaining)
	{
		let hours = secondsRemaining / 3600;
		let minutes = (secondsRemaining % 3600) / 60;
		let seconds = secondsRemaining % 60;

		let timerStr = scope String();
		timerStr.AppendF("{:02}:{:02}:{:02}", hours, minutes, seconds);
		mTimerLabel.Text = timerStr;
	}
}

namespace StormTactics.Client;

using System;
using Sedulous.GUI;
using Sedulous.Foundation.Mathematics;
using Sedulous.Foundation.Core;
using StormTactics.Core;
using StormTactics.Game;

delegate void DailyChallengeDelegate(int32 challengeIndex);

/// Daily challenge screen showing 3 rotating challenge cards with restrictions.
class DailyChallengeScreen
{
	private Grid mRoot ~ delete _;

	// Top bar
	private TextBlock mTimerLabel;

	// Challenge cards
	private Border[3] mCardBorders;
	private TextBlock[3] mCardNames;
	private TextBlock[3] mCardDescs;
	private TextBlock[3] mCardRewards;
	private Button[3] mCardButtons;
	private TextBlock[3] mCardButtonLabels;

	// Events
	private EventAccessor<HubNavigationDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<DailyChallengeDelegate> mOnStartChallenge = new .() ~ delete _;

	public EventAccessor<HubNavigationDelegate> OnBack => mOnBack;
	public EventAccessor<DailyChallengeDelegate> OnStartChallenge => mOnStartChallenge;
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

		mRoot.RowDefinitions.Add(new .() { Height = .Pixels(48) });  // Top bar
		mRoot.RowDefinitions.Add(new .() { Height = .Star });        // Card list
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

		let title = new TextBlock("DAILY CHALLENGES");
		title.Foreground = Color(200, 120, 40);
		title.FontSize = 20;
		leftPanel.AddChild(title);

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

		let cardStack = new StackPanel();
		cardStack.Orientation = .Vertical;
		cardStack.Spacing = 12;
		cardStack.HorizontalAlignment = .Stretch;
		scroll.Content = cardStack;

		for (int32 i = 0; i < 3; i++)
		{
			let card = BuildChallengeCard(i);
			cardStack.AddChild(card);
		}

		mRoot.AddChild(scroll);
	}

	private Border BuildChallengeCard(int32 index)
	{
		let card = new Border();
		card.Background = Color(22, 26, 38, 255);
		card.BorderBrush = Color(50, 55, 70);
		card.BorderThickness = Thickness(1);
		card.Padding = Thickness(16, 12, 16, 12);
		card.HorizontalAlignment = .Stretch;
		mCardBorders[index] = card;

		let dock = new DockPanel();
		dock.LastChildFill = true;
		card.Child = dock;

		// Right side: Battle / Completed button
		let btnPanel = new StackPanel();
		btnPanel.Orientation = .Vertical;
		btnPanel.VerticalAlignment = .Center;
		btnPanel.Margin = Thickness(16, 0, 0, 0);
		DockPanelProperties.SetDock(btnPanel, .Right);

		let battleBtn = new Button();
		battleBtn.Width = .Fixed(110);
		battleBtn.Height = .Fixed(38);
		battleBtn.Background = Color(180, 90, 30);
		mCardButtons[index] = battleBtn;

		let btnLabel = new TextBlock("BATTLE");
		btnLabel.Foreground = Color.White;
		btnLabel.FontSize = 16;
		btnLabel.TextAlignment = .Center;
		btnLabel.HorizontalAlignment = .Center;
		btnLabel.IsHitTestVisible = false;
		mCardButtonLabels[index] = btnLabel;
		battleBtn.Content = btnLabel;

		let capturedIndex = index;
		battleBtn.Click.Subscribe(new (btn) => {
			mOnStartChallenge.[Friend]Invoke(capturedIndex);
		});

		btnPanel.AddChild(battleBtn);
		dock.AddChild(btnPanel);

		// Left side: Name, description, rewards
		let infoPanel = new StackPanel();
		infoPanel.Orientation = .Vertical;
		infoPanel.Spacing = 4;

		// Challenge number + name
		let nameLabel = new TextBlock();
		nameLabel.Foreground = Color(200, 120, 40);
		nameLabel.FontSize = 18;
		mCardNames[index] = nameLabel;
		infoPanel.AddChild(nameLabel);

		// Description (restriction)
		let descLabel = new TextBlock();
		descLabel.Foreground = Color(160, 160, 180);
		descLabel.FontSize = 14;
		mCardDescs[index] = descLabel;
		infoPanel.AddChild(descLabel);

		// Rewards line
		let rewardLabel = new TextBlock();
		rewardLabel.Foreground = Color(140, 140, 160);
		rewardLabel.FontSize = 13;
		mCardRewards[index] = rewardLabel;
		infoPanel.AddChild(rewardLabel);

		dock.AddChild(infoPanel);

		return card;
	}

	/// Refresh the screen with today's challenge data.
	public void Show(DailyChallengeManager manager)
	{
		for (int32 i = 0; i < 3; i++)
		{
			let tmpl = manager.GetChallenge(i);
			if (tmpl == null) continue;

			let completed = manager.IsChallengeCompleted(i);

			// Name
			let nameStr = scope String();
			nameStr.AppendF("{}. {}", i + 1, tmpl.mName);
			mCardNames[i].Text = nameStr;

			// Description
			mCardDescs[i].Text = tmpl.mDescription;

			// Rewards
			let rewardStr = scope String();
			rewardStr.AppendF("Rewards:  {} Gold   {} EXP", tmpl.mGoldReward, tmpl.mExpReward);
			if (tmpl.mGemReward > 0)
				rewardStr.AppendF("   {} Gems", tmpl.mGemReward);
			if (tmpl.mDifficultyScale > 1.0f)
				rewardStr.AppendF("   (x{:.1} difficulty)", tmpl.mDifficultyScale);
			mCardRewards[i].Text = rewardStr;

			// Button state
			if (completed)
			{
				mCardButtonLabels[i].Text = "COMPLETED";
				mCardButtons[i].Background = Color(40, 100, 40);
				mCardButtons[i].IsEnabled = false;
				mCardBorders[i].BorderBrush = Color(40, 100, 40);
			}
			else
			{
				mCardButtonLabels[i].Text = "BATTLE";
				mCardButtons[i].Background = Color(180, 90, 30);
				mCardButtons[i].IsEnabled = true;
				mCardBorders[i].BorderBrush = Color(50, 55, 70);
			}
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

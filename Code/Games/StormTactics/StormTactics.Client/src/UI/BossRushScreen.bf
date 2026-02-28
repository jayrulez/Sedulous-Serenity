namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Core.Mathematics;
using Sedulous.Core.Core;
using StormTactics.Core;
using StormTactics.Game;

delegate void BossSelectDelegate(int32 bossIndex);

/// Boss rush selection screen showing boss cards with mechanics and rewards.
class BossRushScreen
{
	private Grid mRoot ~ delete _;

	// Boss cards (dynamic count)
	private List<Border> mCardBorders = new .() ~ delete _;
	private List<TextBlock> mCardNames = new .() ~ delete _;
	private List<TextBlock> mCardDescs = new .() ~ delete _;
	private List<TextBlock> mCardHints = new .() ~ delete _;
	private List<TextBlock> mCardRewards = new .() ~ delete _;
	private List<Button> mCardButtons = new .() ~ delete _;
	private List<TextBlock> mCardStatuses = new .() ~ delete _;
	private StackPanel mCardStack;

	// Events
	private EventAccessor<HubNavigationDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<BossSelectDelegate> mOnStartBoss = new .() ~ delete _;

	public EventAccessor<HubNavigationDelegate> OnBack => mOnBack;
	public EventAccessor<BossSelectDelegate> OnStartBoss => mOnStartBoss;
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

		let title = new TextBlock("BOSS RUSH");
		title.Foreground = Color(180, 40, 40);
		title.FontSize = 20;
		leftPanel.AddChild(title);

		content.AddChild(leftPanel);

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
		mCardStack.Spacing = 12;
		mCardStack.HorizontalAlignment = .Stretch;
		scroll.Content = mCardStack;

		mRoot.AddChild(scroll);
	}

	private void BuildBossCard(int32 index)
	{
		let card = new Border();
		card.Background = Color(22, 26, 38, 255);
		card.BorderBrush = Color(50, 55, 70);
		card.BorderThickness = Thickness(1);
		card.Padding = Thickness(16, 12, 16, 12);
		card.HorizontalAlignment = .Stretch;
		mCardBorders.Add(card);

		let dock = new DockPanel();
		dock.LastChildFill = true;
		card.Child = dock;

		// Right side: Battle button
		let btnPanel = new StackPanel();
		btnPanel.Orientation = .Vertical;
		btnPanel.VerticalAlignment = .Center;
		btnPanel.Margin = Thickness(16, 0, 0, 0);
		DockPanelProperties.SetDock(btnPanel, .Right);

		let battleBtn = new Button();
		battleBtn.Width = .Fixed(110);
		battleBtn.Height = .Fixed(38);
		battleBtn.Background = Color(180, 40, 40);
		mCardButtons.Add(battleBtn);

		let btnLabel = new TextBlock("BATTLE");
		btnLabel.Foreground = Color.White;
		btnLabel.FontSize = 16;
		btnLabel.TextAlignment = .Center;
		btnLabel.HorizontalAlignment = .Center;
		btnLabel.IsHitTestVisible = false;
		battleBtn.Content = btnLabel;

		let capturedIndex = index;
		battleBtn.Click.Subscribe(new (btn) => {
			mOnStartBoss.[Friend]Invoke(capturedIndex);
		});

		btnPanel.AddChild(battleBtn);
		dock.AddChild(btnPanel);

		// Left side: Name, description, mechanic, rewards, status
		let infoPanel = new StackPanel();
		infoPanel.Orientation = .Vertical;
		infoPanel.Spacing = 4;

		// Boss name
		let nameLabel = new TextBlock();
		nameLabel.Foreground = Color(180, 40, 40);
		nameLabel.FontSize = 18;
		mCardNames.Add(nameLabel);
		infoPanel.AddChild(nameLabel);

		// Description
		let descLabel = new TextBlock();
		descLabel.Foreground = Color(160, 160, 180);
		descLabel.FontSize = 14;
		mCardDescs.Add(descLabel);
		infoPanel.AddChild(descLabel);

		// Mechanic hint
		let hintLabel = new TextBlock();
		hintLabel.Foreground = Color(220, 160, 40);
		hintLabel.FontSize = 13;
		mCardHints.Add(hintLabel);
		infoPanel.AddChild(hintLabel);

		// Rewards line
		let rewardLabel = new TextBlock();
		rewardLabel.Foreground = Color(140, 140, 160);
		rewardLabel.FontSize = 13;
		mCardRewards.Add(rewardLabel);
		infoPanel.AddChild(rewardLabel);

		// Defeated status
		let statusLabel = new TextBlock();
		statusLabel.Foreground = Color(40, 180, 40);
		statusLabel.FontSize = 13;
		mCardStatuses.Add(statusLabel);
		infoPanel.AddChild(statusLabel);

		dock.AddChild(infoPanel);

		mCardStack.AddChild(card);
	}

	/// Refresh the screen with current boss data.
	public void Show(BossRushManager manager)
	{
		// Rebuild cards if count changed
		if (mCardBorders.Count != manager.BossCount)
		{
			mCardBorders.Clear();
			mCardNames.Clear();
			mCardDescs.Clear();
			mCardHints.Clear();
			mCardRewards.Clear();
			mCardButtons.Clear();
			mCardStatuses.Clear();
			mCardStack.ClearChildren();

			for (int32 i = 0; i < manager.BossCount; i++)
				BuildBossCard(i);
		}

		for (int32 i = 0; i < manager.BossCount; i++)
		{
			let tmpl = manager.GetBoss(i);
			if (tmpl == null) continue;

			let defeated = manager.IsBossDefeated(i);

			// Name
			mCardNames[i].Text = tmpl.mName;

			// Description
			mCardDescs[i].Text = tmpl.mDescription;

			// Mechanic hint
			let hintStr = scope String();
			hintStr.AppendF("! {}", tmpl.mMechanicHint);
			mCardHints[i].Text = hintStr;

			// Rewards
			let rewardStr = scope String();
			rewardStr.AppendF("Rewards:  {} Gold   {} EXP", tmpl.mGoldReward, tmpl.mExpReward);
			if (tmpl.mFirstClearGems > 0)
			{
				if (defeated)
					rewardStr.AppendF("   ({} Gems first clear - claimed)", tmpl.mFirstClearGems);
				else
					rewardStr.AppendF("   {} Gems (first clear)", tmpl.mFirstClearGems);
			}
			mCardRewards[i].Text = rewardStr;

			// Status
			if (defeated)
				mCardStatuses[i].Text = "DEFEATED";
			else
				mCardStatuses[i].Text = "";
		}
	}
}

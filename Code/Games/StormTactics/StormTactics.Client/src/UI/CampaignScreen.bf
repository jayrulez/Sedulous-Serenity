namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;
using Sedulous.Core.Core;
using StormTactics.Core;
using StormTactics.Game;

delegate void CampaignBackDelegate();
delegate void CampaignStageDelegate(int32 stageId, bool isHardMode);
delegate void CampaignSweepDelegate(int32 stageId, bool isHardMode);

struct CampaignStageInfo
{
	public int32 mId;
	public StringView mName;
	public int32 mChapter;
	public int32 mDifficulty;
	public int32 mStaminaCost;
	public int32 mRecommendedPower;
	public int32 mEnemyCount;
	public int32 mBestStars; // 0 = never cleared
	public bool mIsLocked;
	public bool mIsBoss;
	public int32 mFirstClearGold;
	public int32 mFirstClearGems;
	public int32 mSweepLimit;
	public int32 mSweepCount;
	public bool mHardUnlocked;   // Whether hard mode is available
	public int32 mHardStars;     // Hard mode best stars (0-3)
	public int32 mHardSweepCount;
}

/// Campaign screen with chapter tabs, stage nodes, info popup, and sweep.
class CampaignScreen
{
	private Grid mRoot ~ delete _;

	// Chapter tabs
	private StackPanel mChapterTabPanel;
	private int32 mActiveChapter = 1;

	// Difficulty toggle
	private Button mNormalModeBtn;
	private Button mHardModeBtn;

	// Player info bar
	private TextBlock mStaminaLabel;
	private TextBlock mPowerLabel;

	// Stage list
	private ScrollViewer mStageScroll;
	private StackPanel mStageListPanel;

	// Stage info popup
	private Popup mInfoPopup ~ delete _;
	private TextBlock mInfoName;
	private TextBlock mInfoDifficulty;
	private TextBlock mInfoStamina;
	private TextBlock mInfoPower;
	private TextBlock mInfoEnemies;
	private TextBlock mInfoStars;
	private TextBlock mInfoFirstClear;
	private StackPanel mInfoRewardsPanel;
	private Button mInfoBattleBtn;
	private Button mInfoSweepBtn;
	private Button mInfoCloseBtn;
	private int32 mInfoStageId = -1;

	// Sweep info
	private TextBlock mInfoSweepInfo;

	// Sweep results area
	private StackPanel mSweepResultsPanel;
	private int32 mSweepCount;

	// State
	private List<CampaignStageInfo> mStages = new .() ~ delete _;
	private int32 mPlayerStamina;
	private int32 mMaxStamina;
	private bool mHardMode = false;

	// Events
	private EventAccessor<CampaignBackDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<CampaignStageDelegate> mOnStageSelected = new .() ~ delete _;
	private EventAccessor<CampaignSweepDelegate> mOnSweep = new .() ~ delete _;

	public EventAccessor<CampaignBackDelegate> OnBack => mOnBack;
	public EventAccessor<CampaignStageDelegate> OnStageSelected => mOnStageSelected;
	public EventAccessor<CampaignSweepDelegate> OnSweep => mOnSweep;
	public UIElement RootElement => mRoot;

	// References for refresh after sweep
	private PlayerManager mPlayerMgr;
	private PlayerSaveData mSaveData;
	private ConfigDatabase mConfigs;

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
		mRoot.RowDefinitions.Add(new .() { Height = .Pixels(36) });  // Chapter tabs
		mRoot.RowDefinitions.Add(new .() { Height = .Star });        // Stage list
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });

		BuildTopBar();
		BuildChapterTabs();
		BuildStageList();
		BuildInfoPopup();
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

		let title = new TextBlock("CAMPAIGN");
		title.Foreground = Color(255, 215, 80);
		title.FontSize = 20;
		title.Margin = Thickness(16, 0, 0, 0);
		title.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(title, .Left);
		content.AddChild(title);

		// Right: stamina + power
		let infoPanel = new StackPanel();
		infoPanel.Orientation = .Horizontal;
		infoPanel.Spacing = 20;
		infoPanel.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(infoPanel, .Right);

		mPowerLabel = new TextBlock("PWR: ---");
		mPowerLabel.Foreground = Color(255, 180, 80);
		mPowerLabel.FontSize = 14;
		infoPanel.AddChild(mPowerLabel);

		mStaminaLabel = new TextBlock("STA: ---");
		mStaminaLabel.Foreground = Color(100, 200, 100);
		mStaminaLabel.FontSize = 14;
		infoPanel.AddChild(mStaminaLabel);

		content.AddChild(infoPanel);

		mRoot.AddChild(topBar);
	}

	private void BuildChapterTabs()
	{
		let tabBar = new Border();
		tabBar.Background = Color(16, 18, 28, 255);
		tabBar.Padding = Thickness(8, 4, 8, 4);
		GridProperties.SetRow(tabBar, 1);

		let tabBarContent = new DockPanel();
		tabBarContent.LastChildFill = false;
		tabBarContent.HorizontalAlignment = .Stretch;
		tabBarContent.VerticalAlignment = .Center;
		tabBar.Child = tabBarContent;

		mChapterTabPanel = new StackPanel();
		mChapterTabPanel.Orientation = .Horizontal;
		mChapterTabPanel.Spacing = 6;
		mChapterTabPanel.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(mChapterTabPanel, .Left);
		tabBarContent.AddChild(mChapterTabPanel);

		// Difficulty toggle (right side)
		let diffToggle = new StackPanel();
		diffToggle.Orientation = .Horizontal;
		diffToggle.Spacing = 4;
		diffToggle.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(diffToggle, .Right);

		mNormalModeBtn = new Button("NORMAL");
		mNormalModeBtn.Padding = Thickness(10, 2, 10, 2);
		mNormalModeBtn.Click.Subscribe(new (btn) => {
			if (mHardMode)
			{
				mHardMode = false;
				if (mRoot.Context != null)
					mRoot.Context.MutationQueue.QueueAction(new () => { RefreshDifficultyToggle(); RefreshStageList(); });
				else { RefreshDifficultyToggle(); RefreshStageList(); }
			}
		});
		diffToggle.AddChild(mNormalModeBtn);

		mHardModeBtn = new Button("HARD");
		mHardModeBtn.Padding = Thickness(10, 2, 10, 2);
		mHardModeBtn.Click.Subscribe(new (btn) => {
			if (!mHardMode)
			{
				mHardMode = true;
				if (mRoot.Context != null)
					mRoot.Context.MutationQueue.QueueAction(new () => { RefreshDifficultyToggle(); RefreshStageList(); });
				else { RefreshDifficultyToggle(); RefreshStageList(); }
			}
		});
		diffToggle.AddChild(mHardModeBtn);

		tabBarContent.AddChild(diffToggle);

		mRoot.AddChild(tabBar);
	}

	private void BuildStageList()
	{
		let listBorder = new Border();
		listBorder.Padding = Thickness(16, 8, 16, 8);
		GridProperties.SetRow(listBorder, 2);

		mStageScroll = new ScrollViewer();
		mStageScroll.VerticalScrollBarVisibility = .Auto;
		mStageScroll.HorizontalScrollBarVisibility = .Disabled;
		listBorder.Child = mStageScroll;

		mStageListPanel = new StackPanel();
		mStageListPanel.Orientation = .Vertical;
		mStageListPanel.Spacing = 6;
		mStageListPanel.HorizontalAlignment = .Stretch;
		mStageScroll.Content = mStageListPanel;

		mRoot.AddChild(listBorder);
	}

	private void BuildInfoPopup()
	{
		mInfoPopup = new Popup();
		mInfoPopup.Background = Color(18, 22, 32, 250);
		mInfoPopup.Width = .Fixed(420);
		mInfoPopup.Height = .Fixed(560);
		mInfoPopup.Padding = Thickness(24, 20, 24, 20);
		mInfoPopup.Behavior = .CloseOnClickOutside | .CloseOnEscape;
		mInfoPopup.Closed.Subscribe(new (popup) => {
			// Refresh campaign screen after popup closes (stamina/sweep counts may have changed)
			if (mConfigs != null && mPlayerMgr != null && mSaveData != null)
				Show(mConfigs, mPlayerMgr, mSaveData);
		});

		let scroll = new ScrollViewer();
		scroll.VerticalScrollBarVisibility = .Auto;
		scroll.HorizontalScrollBarVisibility = .Disabled;
		scroll.HorizontalAlignment = .Stretch;
		scroll.VerticalAlignment = .Stretch;
		mInfoPopup.Content = scroll;

		let layout = new StackPanel();
		layout.Orientation = .Vertical;
		layout.Spacing = 10;
		layout.HorizontalAlignment = .Stretch;
		scroll.Content = layout;

		// Stage name
		mInfoName = new TextBlock("");
		mInfoName.Foreground = Color(255, 215, 80);
		mInfoName.FontSize = 22;
		mInfoName.TextAlignment = .Center;
		mInfoName.HorizontalAlignment = .Center;
		layout.AddChild(mInfoName);

		// Divider
		let divider = new Border();
		divider.Background = Color(60, 65, 80);
		divider.Height = .Fixed(1);
		divider.HorizontalAlignment = .Stretch;
		layout.AddChild(divider);

		// Info rows
		let infoGrid = new StackPanel();
		infoGrid.Orientation = .Vertical;
		infoGrid.Spacing = 4;
		infoGrid.HorizontalAlignment = .Stretch;
		layout.AddChild(infoGrid);

		mInfoDifficulty = BuildInfoRow(infoGrid, "Difficulty");
		mInfoStamina = BuildInfoRow(infoGrid, "Stamina Cost");
		mInfoPower = BuildInfoRow(infoGrid, "Rec. Power");
		mInfoEnemies = BuildInfoRow(infoGrid, "Enemies");
		mInfoStars = BuildInfoRow(infoGrid, "Best Rating");
		mInfoSweepInfo = BuildInfoRow(infoGrid, "Sweeps");
		mInfoFirstClear = BuildInfoRow(infoGrid, "First Clear");

		// Rewards section
		let rewardsDivider = new Border();
		rewardsDivider.Background = Color(60, 65, 80);
		rewardsDivider.Height = .Fixed(1);
		rewardsDivider.HorizontalAlignment = .Stretch;
		layout.AddChild(rewardsDivider);

		let rewardsHeader = new TextBlock("REWARDS");
		rewardsHeader.Foreground = Color(200, 200, 210);
		rewardsHeader.FontSize = 14;
		rewardsHeader.TextAlignment = .Center;
		layout.AddChild(rewardsHeader);

		mInfoRewardsPanel = new StackPanel();
		mInfoRewardsPanel.Orientation = .Vertical;
		mInfoRewardsPanel.Spacing = 2;
		mInfoRewardsPanel.HorizontalAlignment = .Stretch;
		layout.AddChild(mInfoRewardsPanel);

		// Buttons
		let btnRow = new StackPanel();
		btnRow.Orientation = .Horizontal;
		btnRow.Spacing = 10;
		btnRow.HorizontalAlignment = .Center;
		btnRow.Margin = Thickness(0, 6, 0, 0);
		layout.AddChild(btnRow);

		mInfoSweepBtn = new Button("Sweep");
		mInfoSweepBtn.Padding = Thickness(16, 8, 16, 8);
		mInfoSweepBtn.Visibility = .Collapsed;
		mInfoSweepBtn.Click.Subscribe(new (btn) => {
			if (mInfoStageId >= 0)
				mOnSweep.[Friend]Invoke(mInfoStageId, mHardMode);
		});
		btnRow.AddChild(mInfoSweepBtn);

		mInfoBattleBtn = new Button("Battle");
		mInfoBattleBtn.Padding = Thickness(20, 8, 20, 8);
		mInfoBattleBtn.Click.Subscribe(new (btn) => {
			if (mInfoStageId >= 0)
			{
				mOnStageSelected.[Friend]Invoke(mInfoStageId, mHardMode);
				mInfoPopup.Close();
			}
		});
		btnRow.AddChild(mInfoBattleBtn);

		mInfoCloseBtn = new Button("Close");
		mInfoCloseBtn.Padding = Thickness(16, 8, 16, 8);
		mInfoCloseBtn.Click.Subscribe(new (btn) => {
			mInfoPopup.Close();
		});
		btnRow.AddChild(mInfoCloseBtn);

		// Sweep results area (hidden by default)
		mSweepResultsPanel = new StackPanel();
		mSweepResultsPanel.Orientation = .Vertical;
		mSweepResultsPanel.Spacing = 3;
		mSweepResultsPanel.HorizontalAlignment = .Stretch;
		mSweepResultsPanel.Visibility = .Collapsed;
		layout.AddChild(mSweepResultsPanel);
	}

	private TextBlock BuildInfoRow(StackPanel parent, StringView label)
	{
		let row = new DockPanel();
		row.HorizontalAlignment = .Stretch;
		row.LastChildFill = false;

		let labelTb = new TextBlock(label);
		labelTb.Foreground = Color(150, 155, 170);
		labelTb.FontSize = 14;
		DockPanelProperties.SetDock(labelTb, .Left);
		row.AddChild(labelTb);

		let value = new TextBlock("--");
		value.Foreground = Color(230, 230, 240);
		value.FontSize = 14;
		DockPanelProperties.SetDock(value, .Right);
		row.AddChild(value);

		parent.AddChild(row);
		return value;
	}

	/// Refresh the campaign screen with current game data.
	public void Show(ConfigDatabase configs, PlayerManager playerMgr, PlayerSaveData save)
	{
		mConfigs = configs;
		mPlayerMgr = playerMgr;
		mSaveData = save;
		mStages.Clear();

		// Build stage info list
		let sortedStages = scope List<StageConfig>();
		for (let stage in configs.Stages)
			sortedStages.Add(stage);
		sortedStages.Sort(scope (a, b) => a.mId <=> b.mId);

		for (let stage in sortedStages)
		{
			var info = CampaignStageInfo();
			info.mId = stage.mId;
			info.mName = stage.mName;
			info.mChapter = stage.mChapter;
			info.mDifficulty = stage.mDifficulty;
			info.mStaminaCost = stage.mStaminaCost;
			info.mRecommendedPower = stage.mRecommendedPower;
			info.mEnemyCount = (int32)stage.mEnemyFormation.Count;
			info.mBestStars = save.GetBestStars(stage.mId);
			info.mIsLocked = !playerMgr.IsStageUnlocked(stage.mId);
			info.mIsBoss = stage.mIsBoss;
			info.mFirstClearGold = stage.mFirstClearGold;
			info.mFirstClearGems = stage.mFirstClearGems;
			info.mSweepLimit = stage.mSweepLimit;
			info.mSweepCount = save.GetSweepCount(stage.mId);
			info.mHardUnlocked = playerMgr.IsHardModeUnlocked(stage.mId);
			info.mHardStars = save.GetHardStars(stage.mId);
			info.mHardSweepCount = save.GetHardSweepCount(stage.mId);
			mStages.Add(info);
		}

		mPlayerStamina = save.mStamina;
		mMaxStamina = playerMgr.MaxStamina;

		// Update stamina display
		let staStr = scope String();
		staStr.AppendF("STA: {}/{}", mPlayerStamina, mMaxStamina);
		mStaminaLabel.Text = staStr;

		// Power is not tracked per-player yet — leave placeholder
		mPowerLabel.Text = "";

		// Build chapter tabs from unique chapters
		RefreshChapterTabs();
		RefreshStageList();
	}

	private void RefreshDifficultyToggle()
	{
		if (mNormalModeBtn != null)
			mNormalModeBtn.[Friend]mBackground = mHardMode ? Color(40, 42, 55, 255) : Color(60, 70, 100, 255);
		if (mHardModeBtn != null)
			mHardModeBtn.[Friend]mBackground = mHardMode ? Color(100, 50, 50, 255) : Color(40, 42, 55, 255);
	}

	private void RefreshChapterTabs()
	{
		mChapterTabPanel.ClearChildren();
		RefreshDifficultyToggle();

		// Collect unique chapters
		let chapters = scope List<int32>();
		for (let stage in mStages)
		{
			bool found = false;
			for (let c in chapters)
			{
				if (c == stage.mChapter) { found = true; break; }
			}
			if (!found) chapters.Add(stage.mChapter);
		}
		chapters.Sort(scope (a, b) => a <=> b);

		StringView[3] chapterNames = .("The Verdant March", "The Dark Frontier", "The Burning Wastes");

		for (let chapterNum in chapters)
		{
			let idx = chapterNum;
			let label = scope String();
			if (chapterNum >= 1 && chapterNum <= 3)
				label.AppendF("Ch.{}: {}", chapterNum, chapterNames[chapterNum - 1]);
			else
				label.AppendF("Chapter {}", chapterNum);

			let tab = new Button(label);
			tab.Padding = Thickness(12, 3, 12, 3);
			if (chapterNum == mActiveChapter)
				tab.[Friend]mBackground = Color(60, 70, 100, 255);
			tab.Click.Subscribe(new (btn) => {
				mActiveChapter = idx;
				if (mRoot.Context != null)
					mRoot.Context.MutationQueue.QueueAction(new () => { RefreshChapterTabs(); RefreshStageList(); });
				else { RefreshChapterTabs(); RefreshStageList(); }
			});
			mChapterTabPanel.AddChild(tab);
		}
	}

	private void RefreshStageList()
	{
		mStageListPanel.ClearChildren();

		for (let stage in mStages)
		{
			if (stage.mChapter != mActiveChapter) continue;

			let stageId = stage.mId;

			// Determine locked/stars based on current difficulty mode
			bool isLocked = mHardMode ? !stage.mHardUnlocked : stage.mIsLocked;
			int32 displayStars = mHardMode ? stage.mHardStars : stage.mBestStars;

			// Stage card
			let card = new Border();
			if (isLocked)
				card.Background = Color(20, 22, 30, 255);
			else if (mHardMode)
				card.Background = stage.mIsBoss ? Color(50, 20, 20, 255) : Color(40, 25, 35, 255);
			else if (stage.mIsBoss)
				card.Background = Color(40, 25, 20, 255);
			else
				card.Background = Color(25, 30, 45, 255);
			card.Padding = Thickness(12, 8, 12, 8);
			card.HorizontalAlignment = .Stretch;

			let row = new DockPanel();
			row.HorizontalAlignment = .Stretch;
			row.LastChildFill = false;
			card.Child = row;

			// Left: name + tags
			let leftCol = new StackPanel();
			leftCol.Orientation = .Vertical;
			leftCol.Spacing = 2;
			DockPanelProperties.SetDock(leftCol, .Left);

			// Name row with boss/hard tags
			let nameStr = scope String();
			nameStr.Set(stage.mName);
			if (stage.mIsBoss) nameStr.Append("  [BOSS]");
			if (mHardMode) nameStr.Append("  [HARD]");
			let nameLabel = new TextBlock(nameStr);
			if (isLocked)
				nameLabel.Foreground = Color(80, 80, 90);
			else if (mHardMode)
				nameLabel.Foreground = Color(255, 120, 120);
			else if (stage.mIsBoss)
				nameLabel.Foreground = Color(255, 150, 80);
			else
				nameLabel.Foreground = Color(230, 230, 240);
			nameLabel.FontSize = 16;
			leftCol.AddChild(nameLabel);

			// Info line: difficulty, stamina, enemies
			let infoStr = scope String();
			infoStr.AppendF("Diff:{} | STA:{} | {}x enemies | PWR:{}", stage.mDifficulty, stage.mStaminaCost, stage.mEnemyCount, stage.mRecommendedPower);
			let infoLabel = new TextBlock(infoStr);
			infoLabel.Foreground = isLocked ? Color(60, 60, 70) : Color(130, 135, 150);
			infoLabel.FontSize = 12;
			leftCol.AddChild(infoLabel);

			row.AddChild(leftCol);

			// Right: stars + locked
			let rightCol = new StackPanel();
			rightCol.Orientation = .Vertical;
			rightCol.Spacing = 2;
			rightCol.VerticalAlignment = .Center;
			DockPanelProperties.SetDock(rightCol, .Right);

			if (isLocked)
			{
				let lockLabel = new TextBlock(mHardMode ? "CLEAR NORMAL" : "LOCKED");
				lockLabel.Foreground = Color(100, 60, 60);
				lockLabel.FontSize = 14;
				lockLabel.TextAlignment = .Right;
				rightCol.AddChild(lockLabel);
			}
			else
			{
				// Star display
				let starStr = scope String();
				if (displayStars > 0)
					starStr.AppendF("{}/3 Stars", displayStars);
				else
					starStr.Set("No Stars");
				let starLabel = new TextBlock(starStr);
				starLabel.Foreground = displayStars > 0 ? Color(255, 215, 80) : Color(80, 80, 90);
				starLabel.FontSize = 14;
				starLabel.TextAlignment = .Right;
				rightCol.AddChild(starLabel);

				// First clear indicator
				if (displayStars == 0 && (stage.mFirstClearGold > 0 || stage.mFirstClearGems > 0))
				{
					let fcStr = scope String();
					fcStr.Append("1st:");
					if (stage.mFirstClearGold > 0)
						fcStr.AppendF(" {}G", stage.mFirstClearGold);
					if (stage.mFirstClearGems > 0)
						fcStr.AppendF(" {}Gem", stage.mFirstClearGems);
					let fcLabel = new TextBlock(fcStr);
					fcLabel.Foreground = Color(100, 200, 255);
					fcLabel.FontSize = 11;
					fcLabel.TextAlignment = .Right;
					rightCol.AddChild(fcLabel);
				}
			}

			row.AddChild(rightCol);

			// Click overlay (only if not locked)
			if (!isLocked)
			{
				let btn = new Button();
				btn.Background = Color(0, 0, 0, 0);
				btn.HorizontalAlignment = .Stretch;
				btn.VerticalAlignment = .Stretch;
				btn.Padding = Thickness(0);
				btn.Click.Subscribe(new (b) => {
					ShowInfoPopup(stageId);
				});

				let wrapper = new Grid();
				wrapper.HorizontalAlignment = .Stretch;
				wrapper.RowDefinitions.Add(new .() { Height = .Auto });
				wrapper.ColumnDefinitions.Add(new .() { Width = .Star });
				wrapper.AddChild(card);
				wrapper.AddChild(btn);
				mStageListPanel.AddChild(wrapper);
			}
			else
			{
				mStageListPanel.AddChild(card);
			}
		}
	}

	private void ShowInfoPopup(int32 stageId)
	{
		mInfoStageId = stageId;

		// Find stage info
		CampaignStageInfo info = default;
		bool found = false;
		for (let s in mStages)
		{
			if (s.mId == stageId) { info = s; found = true; break; }
		}
		if (!found) return;

		// Determine stars/sweep based on current difficulty mode
		int32 displayStars = mHardMode ? info.mHardStars : info.mBestStars;
		int32 displaySweepCount = mHardMode ? info.mHardSweepCount : info.mSweepCount;

		let nameStr = scope String();
		nameStr.Set(info.mName);
		if (mHardMode) nameStr.Append(" [HARD]");
		mInfoName.Text = nameStr;
		mInfoName.Foreground = mHardMode ? Color(255, 120, 120) : Color(255, 215, 80);

		mSweepResultsPanel.ClearChildren();
		mSweepResultsPanel.Visibility = .Collapsed;
		mSweepCount = 0;

		// Populate info rows
		let diffStr = scope String();
		diffStr.AppendF("{}", info.mDifficulty);
		if (info.mIsBoss) diffStr.Append("  [BOSS]");
		if (mHardMode) diffStr.Append("  (1.5x stats)");
		mInfoDifficulty.Text = diffStr;

		let staStr = scope String();
		staStr.AppendF("{}", info.mStaminaCost);
		if (mPlayerStamina < info.mStaminaCost)
			mInfoStamina.Foreground = Color(255, 100, 100);
		else
			mInfoStamina.Foreground = Color(230, 230, 240);
		mInfoStamina.Text = staStr;

		let pwrStr = scope String();
		pwrStr.AppendF("{}", info.mRecommendedPower);
		mInfoPower.Text = pwrStr;

		let enemyStr = scope String();
		enemyStr.AppendF("{}", info.mEnemyCount);
		mInfoEnemies.Text = enemyStr;

		// Stars
		let starStr = scope String();
		if (displayStars > 0)
		{
			starStr.AppendF("{}/3", displayStars);
			mInfoStars.Foreground = Color(255, 215, 80);
		}
		else
		{
			starStr.Set("Not cleared");
			mInfoStars.Foreground = Color(150, 150, 170);
		}
		mInfoStars.Text = starStr;

		// Sweep info
		if (displayStars >= 3)
		{
			let sweepStr = scope String();
			if (info.mSweepLimit > 0)
				sweepStr.AppendF("{}/{}", displaySweepCount, info.mSweepLimit);
			else
				sweepStr.AppendF("{} (unlimited)", displaySweepCount);
			mInfoSweepInfo.Text = sweepStr;
			mInfoSweepInfo.Foreground = (info.mSweepLimit > 0 && displaySweepCount >= info.mSweepLimit)
				? Color(255, 100, 100) : Color(230, 230, 240);
		}
		else
		{
			mInfoSweepInfo.Text = "---";
			mInfoSweepInfo.Foreground = Color(150, 150, 170);
		}

		// First clear
		if (displayStars == 0 && (info.mFirstClearGold > 0 || info.mFirstClearGems > 0))
		{
			let fcStr = scope String();
			if (info.mFirstClearGold > 0)
				fcStr.AppendF("+{}G ", info.mFirstClearGold);
			if (info.mFirstClearGems > 0)
				fcStr.AppendF("+{}Gems", info.mFirstClearGems);
			mInfoFirstClear.Text = fcStr;
			mInfoFirstClear.Foreground = Color(100, 200, 255);
		}
		else if (displayStars > 0)
		{
			mInfoFirstClear.Text = "Claimed";
			mInfoFirstClear.Foreground = Color(100, 150, 100);
		}
		else
		{
			mInfoFirstClear.Text = "None";
			mInfoFirstClear.Foreground = Color(150, 150, 170);
		}

		// Rewards
		mInfoRewardsPanel.ClearChildren();
		if (mConfigs != null)
		{
			let stageConfig = mConfigs.GetStage(stageId);
			if (stageConfig != null)
			{
				// Base gold/exp (show 1.5x for hard mode)
				int32 baseGold = stageConfig.mDifficulty * 50;
				int32 baseExp = stageConfig.mDifficulty * 30;
				if (mHardMode)
				{
					baseGold = (int32)((float)baseGold * 1.5f);
					baseExp = (int32)((float)baseExp * 1.5f);
				}
				let baseStr = scope String();
				baseStr.AppendF("Gold: ~{} | EXP: ~{}", baseGold, baseExp);
				let baseLabel = new TextBlock(baseStr);
				baseLabel.Foreground = Color(200, 200, 210);
				baseLabel.FontSize = 13;
				mInfoRewardsPanel.AddChild(baseLabel);

				for (let reward in stageConfig.mRewards)
				{
					let itemConfig = mConfigs.GetItem(reward.mItemId);
					let rStr = scope String();
					if (itemConfig != null)
						rStr.AppendF("{} x{}", itemConfig.mName, reward.mQuantity);
					else
						rStr.AppendF("Item #{} x{}", reward.mItemId, reward.mQuantity);
					if (reward.mDropChance < 1.0f)
					{
						let pct = (int32)(reward.mDropChance * 100);
						rStr.AppendF(" ({}%)", pct);
					}
					let rLabel = new TextBlock(rStr);
					rLabel.Foreground = Color(180, 180, 190);
					rLabel.FontSize = 12;
					mInfoRewardsPanel.AddChild(rLabel);
				}
			}
		}

		// Show sweep button only for 3-starred stages with sweeps remaining
		bool canSweep = displayStars >= 3 && (info.mSweepLimit == 0 || displaySweepCount < info.mSweepLimit);
		mInfoSweepBtn.Visibility = canSweep ? .Visible : .Collapsed;

		// Enable battle button
		mInfoBattleBtn.Visibility = .Visible;

		// Open centered in viewport
		let context = mRoot.Context;
		if (context != null)
		{
			let x = (context.ViewportWidth - 420) / 2;
			let y = (context.ViewportHeight - 560) / 2;
			mInfoPopup.OpenAt(context, x, y);
		}
	}

	/// Display sweep results in the popup and update sweep count/limit display.
	public void ShowSweepResults(int32 gold, int32 exp, Span<RewardDisplayInfo> items, int32 sweepCount, int32 sweepLimit, int32 newStamina)
	{
		mSweepCount++;
		mSweepResultsPanel.Visibility = .Visible;

		// Divider before first result
		if (mSweepCount == 1)
		{
			let divider = new Border();
			divider.Background = Color(60, 65, 80);
			divider.Height = .Fixed(1);
			divider.HorizontalAlignment = .Stretch;
			divider.Margin = Thickness(0, 4, 0, 2);
			mSweepResultsPanel.AddChild(divider);

			let header = new TextBlock("SWEEP RESULTS");
			header.Foreground = Color(100, 200, 255);
			header.FontSize = 14;
			header.TextAlignment = .Center;
			header.HorizontalAlignment = .Center;
			mSweepResultsPanel.AddChild(header);
		}

		// Result entry
		let resultStr = scope String();
		resultStr.AppendF("#{}: +{}G  +{}EXP", mSweepCount, gold, exp);
		for (let item in items)
			resultStr.AppendF("  {}x{}", item.mName, item.mQuantity);

		let resultLabel = new TextBlock(resultStr);
		resultLabel.Foreground = Color(200, 220, 200);
		resultLabel.FontSize = 12;
		resultLabel.HorizontalAlignment = .Center;
		mSweepResultsPanel.AddChild(resultLabel);

		// Update sweep info row
		let sweepStr = scope String();
		if (sweepLimit > 0)
			sweepStr.AppendF("{}/{}", sweepCount, sweepLimit);
		else
			sweepStr.AppendF("{} (unlimited)", sweepCount);
		mInfoSweepInfo.Text = sweepStr;
		mInfoSweepInfo.Foreground = (sweepLimit > 0 && sweepCount >= sweepLimit)
			? Color(255, 100, 100) : Color(230, 230, 240);

		// Update stamina display
		let staStr = scope String();
		staStr.AppendF("{}", newStamina);
		mInfoStamina.Text = staStr;
		mPlayerStamina = newStamina;

		// Hide sweep button if limit reached or not enough stamina for another
		bool limitReached = sweepLimit > 0 && sweepCount >= sweepLimit;
		bool noStamina = mInfoStageId >= 0 && mConfigs != null && mConfigs.GetStage(mInfoStageId) != null
			&& newStamina < mConfigs.GetStage(mInfoStageId).mStaminaCost;
		if (limitReached || noStamina)
			mInfoSweepBtn.Visibility = .Collapsed;
	}
}

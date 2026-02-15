namespace StormTactics.Client;

using System;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;

delegate void HubNavigationDelegate();

/// City hub screen — central navigation for metagame systems.
/// Shows player info bar at top and a grid of navigation buttons.
class CityHubScreen
{
	// Root layout
	private Grid mRoot ~ delete _;

	// Player info bar
	private TextBlock mLevelLabel;
	private ProgressBar mExpBar;
	private TextBlock mExpLabel;
	private TextBlock mGoldLabel;
	private TextBlock mGemsLabel;
	private TextBlock mStaminaLabel;

	// Navigation buttons
	private Button mCampaignButton;
	private Button mChallengesButton;
	private Button mRosterButton;
	private Button mInventoryButton;
	private Button mFormationButton;
	private Button mShopButton;
	private Button mGachaButton;
	private Button mBossRushButton;
	private Button mTowerButton;
	private Button mCrusadeButton;
	private Button mSettingsButton;

	// Events
	private EventAccessor<HubNavigationDelegate> mOnCampaign = new .() ~ delete _;
	private EventAccessor<HubNavigationDelegate> mOnChallenges = new .() ~ delete _;
	private EventAccessor<HubNavigationDelegate> mOnRoster = new .() ~ delete _;
	private EventAccessor<HubNavigationDelegate> mOnInventory = new .() ~ delete _;
	private EventAccessor<HubNavigationDelegate> mOnFormation = new .() ~ delete _;
	private EventAccessor<HubNavigationDelegate> mOnShop = new .() ~ delete _;
	private EventAccessor<HubNavigationDelegate> mOnGacha = new .() ~ delete _;
	private EventAccessor<HubNavigationDelegate> mOnBossRush = new .() ~ delete _;
	private EventAccessor<HubNavigationDelegate> mOnTower = new .() ~ delete _;
	private EventAccessor<HubNavigationDelegate> mOnCrusade = new .() ~ delete _;
	private EventAccessor<HubNavigationDelegate> mOnSettings = new .() ~ delete _;

	public EventAccessor<HubNavigationDelegate> OnCampaign => mOnCampaign;
	public EventAccessor<HubNavigationDelegate> OnChallenges => mOnChallenges;
	public EventAccessor<HubNavigationDelegate> OnRoster => mOnRoster;
	public EventAccessor<HubNavigationDelegate> OnInventory => mOnInventory;
	public EventAccessor<HubNavigationDelegate> OnFormation => mOnFormation;
	public EventAccessor<HubNavigationDelegate> OnShop => mOnShop;
	public EventAccessor<HubNavigationDelegate> OnGacha => mOnGacha;
	public EventAccessor<HubNavigationDelegate> OnBossRush => mOnBossRush;
	public EventAccessor<HubNavigationDelegate> OnTower => mOnTower;
	public EventAccessor<HubNavigationDelegate> OnCrusade => mOnCrusade;
	public EventAccessor<HubNavigationDelegate> OnSettings => mOnSettings;

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
		mRoot.RowDefinitions.Add(new .() { Height = .Star });
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });

		let mainLayout = new DockPanel();
		mainLayout.HorizontalAlignment = .Stretch;
		mainLayout.VerticalAlignment = .Stretch;
		mainLayout.LastChildFill = true;
		mRoot.AddChild(mainLayout);

		BuildPlayerInfoBar(mainLayout);
		BuildNavigationGrid(mainLayout);
	}

	private void BuildPlayerInfoBar(DockPanel parent)
	{
		let topBar = new Border();
		topBar.Background = Color(18, 22, 32, 240);
		topBar.Height = .Fixed(56);
		topBar.Padding = Thickness(16, 8, 16, 8);
		DockPanelProperties.SetDock(topBar, .Top);

		let content = new DockPanel();
		content.LastChildFill = false;
		content.VerticalAlignment = .Center;
		topBar.Child = content;

		// Left side: Title + Level
		let leftPanel = new StackPanel();
		leftPanel.Orientation = .Horizontal;
		leftPanel.Spacing = 16;
		leftPanel.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(leftPanel, .Left);

		let title = new TextBlock("STORM TACTICS");
		title.Foreground = Color(255, 215, 80);
		title.FontSize = 20;
		leftPanel.AddChild(title);

		let sep = new TextBlock("|");
		sep.Foreground = Color(60, 65, 80);
		sep.FontSize = 18;
		leftPanel.AddChild(sep);

		mLevelLabel = new TextBlock("Lv. 1");
		mLevelLabel.Foreground = Color(220, 220, 230);
		mLevelLabel.FontSize = 18;
		leftPanel.AddChild(mLevelLabel);

		// EXP bar + text
		let expPanel = new StackPanel();
		expPanel.Orientation = .Horizontal;
		expPanel.Spacing = 6;
		expPanel.VerticalAlignment = .Center;

		mExpBar = new ProgressBar();
		mExpBar.Width = .Fixed(100);
		mExpBar.Height = .Fixed(10);
		mExpBar.Minimum = 0;
		mExpBar.Maximum = 100;
		mExpBar.Value = 0;
		expPanel.AddChild(mExpBar);

		mExpLabel = new TextBlock("0/0 EXP");
		mExpLabel.Foreground = Color(160, 160, 180);
		mExpLabel.FontSize = 13;
		expPanel.AddChild(mExpLabel);

		leftPanel.AddChild(expPanel);

		content.AddChild(leftPanel);

		// Right side: Currencies
		let rightPanel = new StackPanel();
		rightPanel.Orientation = .Horizontal;
		rightPanel.Spacing = 20;
		rightPanel.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(rightPanel, .Right);

		mStaminaLabel = new TextBlock("STA: 30/30");
		mStaminaLabel.Foreground = Color(100, 200, 100);
		mStaminaLabel.FontSize = 16;
		rightPanel.AddChild(mStaminaLabel);

		mGoldLabel = new TextBlock("Gold: 500");
		mGoldLabel.Foreground = Color(255, 215, 80);
		mGoldLabel.FontSize = 16;
		rightPanel.AddChild(mGoldLabel);

		mGemsLabel = new TextBlock("Gems: 100");
		mGemsLabel.Foreground = Color(100, 200, 255);
		mGemsLabel.FontSize = 16;
		rightPanel.AddChild(mGemsLabel);

		content.AddChild(rightPanel);

		parent.AddChild(topBar);
	}

	private void BuildNavigationGrid(DockPanel parent)
	{
		// Center content — "City" label + navigation buttons
		let centerPanel = new StackPanel();
		centerPanel.Orientation = .Vertical;
		centerPanel.Spacing = 24;
		centerPanel.HorizontalAlignment = .Center;
		centerPanel.VerticalAlignment = .Center;

		let cityLabel = new TextBlock("CITY HUB");
		cityLabel.Foreground = Color(200, 200, 220);
		cityLabel.FontSize = 32;
		cityLabel.TextAlignment = .Center;
		cityLabel.HorizontalAlignment = .Center;
		centerPanel.AddChild(cityLabel);

		// Divider
		let divider = new Border();
		divider.Background = Color(60, 65, 80);
		divider.Height = .Fixed(1);
		divider.Width = .Fixed(400);
		divider.HorizontalAlignment = .Center;
		centerPanel.AddChild(divider);

		// Navigation grid: 2 rows of 3 buttons
		let row1 = new StackPanel();
		row1.Orientation = .Horizontal;
		row1.Spacing = 16;
		row1.HorizontalAlignment = .Center;

		mCampaignButton = CreateNavButton("Campaign", "Battle through stages", Color(180, 80, 60));
		mCampaignButton.Click.Subscribe(new (btn) => { mOnCampaign.[Friend]Invoke(); });
		row1.AddChild(mCampaignButton);

		mChallengesButton = CreateNavButton("Challenges", "Daily battles", Color(200, 120, 40));
		mChallengesButton.Click.Subscribe(new (btn) => { mOnChallenges.[Friend]Invoke(); });
		row1.AddChild(mChallengesButton);

		mRosterButton = CreateNavButton("Roster", "Manage your units", Color(60, 140, 180));
		mRosterButton.Click.Subscribe(new (btn) => { mOnRoster.[Friend]Invoke(); });
		row1.AddChild(mRosterButton);

		mFormationButton = CreateNavButton("Formation", "Arrange battle teams", Color(100, 160, 60));
		mFormationButton.Click.Subscribe(new (btn) => { mOnFormation.[Friend]Invoke(); });
		row1.AddChild(mFormationButton);

		centerPanel.AddChild(row1);

		let row2 = new StackPanel();
		row2.Orientation = .Horizontal;
		row2.Spacing = 16;
		row2.HorizontalAlignment = .Center;

		mInventoryButton = CreateNavButton("Inventory", "View your items", Color(140, 120, 60));
		mInventoryButton.Click.Subscribe(new (btn) => { mOnInventory.[Friend]Invoke(); });
		row2.AddChild(mInventoryButton);

		mShopButton = CreateNavButton("Shop", "Buy items & gear", Color(200, 160, 40));
		mShopButton.Click.Subscribe(new (btn) => { mOnShop.[Friend]Invoke(); });
		row2.AddChild(mShopButton);

		mGachaButton = CreateNavButton("Summon", "Draw new units", Color(160, 80, 200));
		mGachaButton.Click.Subscribe(new (btn) => { mOnGacha.[Friend]Invoke(); });
		row2.AddChild(mGachaButton);

		mBossRushButton = CreateNavButton("Boss Rush", "Fight powerful bosses", Color(180, 40, 40));
		mBossRushButton.Click.Subscribe(new (btn) => { mOnBossRush.[Friend]Invoke(); });
		row2.AddChild(mBossRushButton);

		centerPanel.AddChild(row2);

		let row3 = new StackPanel();
		row3.Orientation = .Horizontal;
		row3.Spacing = 16;
		row3.HorizontalAlignment = .Center;

		mTowerButton = CreateNavButton("Tower", "Climb 10 floors", Color(140, 100, 60));
		mTowerButton.Click.Subscribe(new (btn) => { mOnTower.[Friend]Invoke(); });
		row3.AddChild(mTowerButton);

		mCrusadeButton = CreateNavButton("Crusade", "Survive 15 waves", Color(60, 120, 140));
		mCrusadeButton.Click.Subscribe(new (btn) => { mOnCrusade.[Friend]Invoke(); });
		row3.AddChild(mCrusadeButton);

		mSettingsButton = CreateNavButton("Settings", "Game options", Color(120, 130, 150));
		mSettingsButton.Click.Subscribe(new (btn) => { mOnSettings.[Friend]Invoke(); });
		row3.AddChild(mSettingsButton);

		centerPanel.AddChild(row3);

		parent.AddChild(centerPanel);
	}

	/// Create a navigation button with title, subtitle, and accent color.
	private Button CreateNavButton(StringView title, StringView subtitle, Color accentColor)
	{
		let btn = new Button();
		btn.Width = .Fixed(160);
		btn.Height = .Fixed(80);
		btn.Padding = Thickness(12, 8, 12, 8);
		btn.Background = Color(25, 30, 45, 255);

		let content = new StackPanel();
		content.Orientation = .Vertical;
		content.Spacing = 4;
		content.VerticalAlignment = .Center;
		content.HorizontalAlignment = .Center;

		let titleLabel = new TextBlock(title);
		titleLabel.Foreground = accentColor;
		titleLabel.FontSize = 18;
		titleLabel.TextAlignment = .Center;
		titleLabel.HorizontalAlignment = .Center;
		titleLabel.IsHitTestVisible = false;
		content.AddChild(titleLabel);

		let subLabel = new TextBlock(subtitle);
		subLabel.Foreground = Color(140, 140, 160);
		subLabel.FontSize = 12;
		subLabel.TextAlignment = .Center;
		subLabel.HorizontalAlignment = .Center;
		subLabel.IsHitTestVisible = false;
		content.AddChild(subLabel);

		btn.Content = content;
		return btn;
	}

	// --- Update Methods ---

	/// Update all player info displays.
	public void UpdatePlayerInfo(int32 level, int32 exp, int32 expToNext,
		int32 gold, int32 gems, int32 stamina, int32 maxStamina)
	{
		let lvlStr = scope String();
		lvlStr.AppendF("Lv. {}", level);
		mLevelLabel.Text = lvlStr;

		if (expToNext > 0)
		{
			mExpBar.Maximum = (float)expToNext;
			mExpBar.Value = (float)exp;
			let expStr = scope String();
			expStr.AppendF("{}/{} EXP", exp, expToNext);
			mExpLabel.Text = expStr;
		}
		else
		{
			mExpBar.Maximum = 1;
			mExpBar.Value = 1;
			mExpLabel.Text = "MAX";
		}

		let goldStr = scope String();
		goldStr.AppendF("Gold: {}", gold);
		mGoldLabel.Text = goldStr;

		let gemStr = scope String();
		gemStr.AppendF("Gems: {}", gems);
		mGemsLabel.Text = gemStr;

		let staStr = scope String();
		staStr.AppendF("STA: {}/{}", stamina, maxStamina);
		mStaminaLabel.Text = staStr;
	}
}

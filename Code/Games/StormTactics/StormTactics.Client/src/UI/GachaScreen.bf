namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;
using StormTactics.Core;
using StormTactics.Game;

delegate void GachaBackDelegate();
delegate void GachaPullSingleDelegate();
delegate void GachaPullMultiDelegate();

/// Gacha summoning screen: portal visual, pull buttons, result display with reveal animation.
class GachaScreen
{
	private Grid mRoot ~ delete _;

	// Top bar
	private TextBlock mGemsLabel;
	private TextBlock mPityLabel;

	// Main area
	private Border mPortalVisual;
	private StackPanel mButtonPanel;
	private Button mSinglePullBtn;
	private Button mMultiPullBtn;

	// Results overlay
	private Border mResultsOverlay;
	private StackPanel mResultsPanel;
	private Button mResultsCloseBtn;
	private Button mResultsSkipBtn;
	private TextBlock mRevealCountLabel;

	// Animation state
	private List<Border> mResultCards = new .() ~ delete _;
	private int32 mRevealedCount;
	private int32 mTotalResults;
	private float mRevealTimer;
	private bool mIsAnimating;
	private const float REVEAL_DELAY_SINGLE = 0.5f;
	private const float REVEAL_DELAY_MULTI = 0.3f;
	private float mCurrentRevealDelay;

	// State
	private Dictionary<int32, OwnedImageData> mIconCache = new .() ~ { for (let v in _.Values) delete v; delete _; };

	// Events
	private EventAccessor<GachaBackDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<GachaPullSingleDelegate> mOnPullSingle = new .() ~ delete _;
	private EventAccessor<GachaPullMultiDelegate> mOnPullMulti = new .() ~ delete _;

	public EventAccessor<GachaBackDelegate> OnBack => mOnBack;
	public EventAccessor<GachaPullSingleDelegate> OnPullSingle => mOnPullSingle;
	public EventAccessor<GachaPullMultiDelegate> OnPullMulti => mOnPullMulti;
	public UIElement RootElement => mRoot;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		mRoot = new Grid();
		mRoot.Background = Color(8, 10, 20, 255);
		mRoot.HorizontalAlignment = .Stretch;
		mRoot.VerticalAlignment = .Stretch;

		mRoot.RowDefinitions.Add(new .() { Height = .Pixels(48) }); // Top bar
		mRoot.RowDefinitions.Add(new .() { Height = .Star });       // Content
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });     // Full width

		BuildTopBar();
		BuildMainContent();
		BuildResultsOverlay();
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

		let title = new TextBlock("SUMMON");
		title.Foreground = Color(180, 120, 255);
		title.FontSize = 20;
		title.Margin = Thickness(16, 0, 0, 0);
		title.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(title, .Left);
		content.AddChild(title);

		// Currency + pity (right)
		let infoPanel = new StackPanel();
		infoPanel.Orientation = .Horizontal;
		infoPanel.Spacing = 16;
		infoPanel.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(infoPanel, .Right);

		mPityLabel = new TextBlock("Pity: 0/90");
		mPityLabel.Foreground = Color(150, 150, 170);
		mPityLabel.FontSize = 13;
		infoPanel.AddChild(mPityLabel);

		mGemsLabel = new TextBlock("Gems: 0");
		mGemsLabel.Foreground = Color(130, 200, 255);
		mGemsLabel.FontSize = 14;
		infoPanel.AddChild(mGemsLabel);

		content.AddChild(infoPanel);
		mRoot.AddChild(topBar);
	}

	private void BuildMainContent()
	{
		let contentLayout = new StackPanel();
		contentLayout.Orientation = .Vertical;
		contentLayout.Spacing = 24;
		contentLayout.HorizontalAlignment = .Center;
		contentLayout.VerticalAlignment = .Center;
		GridProperties.SetRow(contentLayout, 1);

		// Portal visual (animated border representing summoning portal)
		mPortalVisual = new Border();
		mPortalVisual.Background = Color(30, 20, 60, 255);
		mPortalVisual.Width = .Fixed(200);
		mPortalVisual.Height = .Fixed(200);
		mPortalVisual.HorizontalAlignment = .Center;

		let portalInner = new Border();
		portalInner.Background = Color(60, 40, 120, 200);
		portalInner.Width = .Fixed(160);
		portalInner.Height = .Fixed(160);
		portalInner.HorizontalAlignment = .Center;
		portalInner.VerticalAlignment = .Center;
		mPortalVisual.Child = portalInner;

		let portalCore = new Border();
		portalCore.Background = Color(120, 80, 200, 180);
		portalCore.Width = .Fixed(100);
		portalCore.Height = .Fixed(100);
		portalCore.HorizontalAlignment = .Center;
		portalCore.VerticalAlignment = .Center;
		portalInner.Child = portalCore;

		let portalText = new TextBlock("SUMMON");
		portalText.Foreground = Color(200, 180, 255);
		portalText.FontSize = 18;
		portalText.HorizontalAlignment = .Center;
		portalText.VerticalAlignment = .Center;
		portalText.TextAlignment = .Center;
		portalCore.Child = portalText;

		contentLayout.AddChild(mPortalVisual);

		// Rates info
		let ratesInfo = new TextBlock("3% Legendary | 12% Epic | 35% Rare | 50% Common");
		ratesInfo.Foreground = Color(120, 120, 140);
		ratesInfo.FontSize = 12;
		ratesInfo.TextAlignment = .Center;
		ratesInfo.HorizontalAlignment = .Center;
		contentLayout.AddChild(ratesInfo);

		// Pull buttons
		mButtonPanel = new StackPanel();
		mButtonPanel.Orientation = .Horizontal;
		mButtonPanel.Spacing = 20;
		mButtonPanel.HorizontalAlignment = .Center;

		mSinglePullBtn = new Button();
		let singleContent = new StackPanel();
		singleContent.Orientation = .Vertical;
		singleContent.Spacing = 2;
		singleContent.HorizontalAlignment = .Center;
		let s1 = new TextBlock("Summon x1");
		s1.FontSize = 15;
		s1.Foreground = Color(220, 220, 230);
		s1.TextAlignment = .Center;
		singleContent.AddChild(s1);
		let s2 = new TextBlock("300 Gems");
		s2.FontSize = 12;
		s2.Foreground = Color(130, 200, 255);
		s2.TextAlignment = .Center;
		singleContent.AddChild(s2);
		mSinglePullBtn.Content = singleContent;
		mSinglePullBtn.Padding = Thickness(20, 8, 20, 8);
		mSinglePullBtn.Click.Subscribe(new (btn) => { mOnPullSingle.[Friend]Invoke(); });
		mButtonPanel.AddChild(mSinglePullBtn);

		mMultiPullBtn = new Button();
		let multiContent = new StackPanel();
		multiContent.Orientation = .Vertical;
		multiContent.Spacing = 2;
		multiContent.HorizontalAlignment = .Center;
		let m1 = new TextBlock("Summon x10");
		m1.FontSize = 15;
		m1.Foreground = Color(220, 220, 230);
		m1.TextAlignment = .Center;
		multiContent.AddChild(m1);
		let m2 = new TextBlock("2700 Gems");
		m2.FontSize = 12;
		m2.Foreground = Color(130, 200, 255);
		m2.TextAlignment = .Center;
		multiContent.AddChild(m2);
		mMultiPullBtn.Content = multiContent;
		mMultiPullBtn.Padding = Thickness(20, 8, 20, 8);
		mMultiPullBtn.Click.Subscribe(new (btn) => { mOnPullMulti.[Friend]Invoke(); });
		mButtonPanel.AddChild(mMultiPullBtn);

		contentLayout.AddChild(mButtonPanel);
		mRoot.AddChild(contentLayout);
	}

	private void BuildResultsOverlay()
	{
		mResultsOverlay = new Border();
		mResultsOverlay.Background = Color(0, 0, 0, 200);
		mResultsOverlay.HorizontalAlignment = .Stretch;
		mResultsOverlay.VerticalAlignment = .Stretch;
		mResultsOverlay.Visibility = .Collapsed;
		GridProperties.SetRow(mResultsOverlay, 1);

		let card = new Border();
		card.Background = Color(22, 26, 38, 250);
		card.Padding = Thickness(20, 16, 20, 16);
		card.Width = .Fixed(500);
		card.HorizontalAlignment = .Center;
		card.VerticalAlignment = .Center;
		mResultsOverlay.Child = card;

		let layout = new StackPanel();
		layout.Orientation = .Vertical;
		layout.Spacing = 12;
		card.Child = layout;

		let resultTitle = new TextBlock("Summoning Results");
		resultTitle.Foreground = Color(255, 215, 80);
		resultTitle.FontSize = 20;
		resultTitle.TextAlignment = .Center;
		layout.AddChild(resultTitle);

		// Reveal counter (e.g. "3 / 10")
		mRevealCountLabel = new TextBlock("");
		mRevealCountLabel.Foreground = Color(150, 150, 170);
		mRevealCountLabel.FontSize = 13;
		mRevealCountLabel.TextAlignment = .Center;
		mRevealCountLabel.Visibility = .Collapsed;
		layout.AddChild(mRevealCountLabel);

		let div = new Border();
		div.Background = Color(60, 65, 80);
		div.Height = .Fixed(1);
		div.HorizontalAlignment = .Stretch;
		layout.AddChild(div);

		// Scrollable results panel
		let scroll = new ScrollViewer();
		scroll.VerticalScrollBarVisibility = .Auto;
		scroll.HorizontalScrollBarVisibility = .Disabled;
		scroll.Height = .Fixed(300);
		layout.AddChild(scroll);

		mResultsPanel = new StackPanel();
		mResultsPanel.Orientation = .Vertical;
		mResultsPanel.Spacing = 6;
		scroll.Content = mResultsPanel;

		// Button row
		let btnRow = new StackPanel();
		btnRow.Orientation = .Horizontal;
		btnRow.Spacing = 16;
		btnRow.HorizontalAlignment = .Center;

		mResultsSkipBtn = new Button("Skip");
		mResultsSkipBtn.Padding = Thickness(20, 8, 20, 8);
		mResultsSkipBtn.Click.Subscribe(new (btn) => {
			RevealAll();
		});
		btnRow.AddChild(mResultsSkipBtn);

		mResultsCloseBtn = new Button("Continue");
		mResultsCloseBtn.Padding = Thickness(24, 8, 24, 8);
		mResultsCloseBtn.Click.Subscribe(new (btn) => {
			mResultsOverlay.Visibility = .Collapsed;
			mIsAnimating = false;
		});
		btnRow.AddChild(mResultsCloseBtn);

		layout.AddChild(btnRow);

		mRoot.AddChild(mResultsOverlay);
	}

	/// Refresh header info.
	public void Refresh(PlayerSaveData save)
	{
		let gemsStr = scope String();
		gemsStr.AppendF("Gems: {}", save.mGems);
		mGemsLabel.Text = gemsStr;

		let pityStr = scope String();
		pityStr.AppendF("Pity: {}/{}", save.mGachaPityCounter, GachaManager.PITY_THRESHOLD);
		mPityLabel.Text = pityStr;
	}

	/// Show results of a single pull with reveal animation.
	public void ShowSingleResult(GachaResult result, ConfigDatabase configs)
	{
		mResultsPanel.ClearChildren();
		mResultCards.Clear();
		mTotalResults = 1;
		mRevealedCount = 0;
		mRevealTimer = 0;
		mCurrentRevealDelay = REVEAL_DELAY_SINGLE;

		AddResultCard(result, configs, hidden: true);

		mResultsOverlay.Visibility = .Visible;
		mResultsCloseBtn.Visibility = .Collapsed;
		mResultsSkipBtn.Visibility = .Visible;
		mRevealCountLabel.Visibility = .Collapsed;
		mIsAnimating = true;
	}

	/// Show results of a multi-pull with sequential reveal animation.
	public void ShowMultiResults(List<GachaResult> results, ConfigDatabase configs)
	{
		mResultsPanel.ClearChildren();
		mResultCards.Clear();
		mTotalResults = (int32)results.Count;
		mRevealedCount = 0;
		mRevealTimer = 0;
		mCurrentRevealDelay = REVEAL_DELAY_MULTI;

		for (let result in results)
			AddResultCard(result, configs, hidden: true);

		mResultsOverlay.Visibility = .Visible;
		mResultsCloseBtn.Visibility = .Collapsed;
		mResultsSkipBtn.Visibility = .Visible;
		mRevealCountLabel.Visibility = .Visible;
		UpdateRevealCount();
		mIsAnimating = true;
	}

	/// Call each frame to advance the reveal animation.
	public void Update(float dt)
	{
		if (!mIsAnimating) return;
		if (mRevealedCount >= mTotalResults) return;

		mRevealTimer += dt;
		if (mRevealTimer >= mCurrentRevealDelay)
		{
			mRevealTimer -= mCurrentRevealDelay;
			RevealNext();
		}
	}

	private void RevealNext()
	{
		if (mRevealedCount >= mTotalResults) return;

		if (mRevealedCount < (int32)mResultCards.Count)
			mResultCards[mRevealedCount].Visibility = .Visible;

		mRevealedCount++;
		UpdateRevealCount();

		if (mRevealedCount >= mTotalResults)
			OnRevealComplete();
	}

	private void RevealAll()
	{
		while (mRevealedCount < mTotalResults && mRevealedCount < (int32)mResultCards.Count)
		{
			mResultCards[mRevealedCount].Visibility = .Visible;
			mRevealedCount++;
		}
		UpdateRevealCount();
		OnRevealComplete();
	}

	private void OnRevealComplete()
	{
		mIsAnimating = false;
		mResultsCloseBtn.Visibility = .Visible;
		mResultsSkipBtn.Visibility = .Collapsed;
	}

	private void UpdateRevealCount()
	{
		if (mTotalResults <= 1)
		{
			mRevealCountLabel.Visibility = .Collapsed;
			return;
		}

		let str = scope String();
		str.AppendF("{} / {}", mRevealedCount, mTotalResults);
		mRevealCountLabel.Text = str;
	}

	private void AddResultCard(GachaResult result, ConfigDatabase configs, bool hidden)
	{
		let config = configs.GetUnit(result.mUnitId);

		let card = new Border();
		card.Background = GetRarityBgColor(result.mRarity);
		card.Padding = Thickness(10, 6, 10, 6);
		card.HorizontalAlignment = .Stretch;
		if (hidden)
			card.Visibility = .Collapsed;

		let row = new StackPanel();
		row.Orientation = .Horizontal;
		row.Spacing = 10;
		row.VerticalAlignment = .Center;
		card.Child = row;

		// Icon
		if (config != null)
		{
			let icon = GetOrCreateIcon(config);
			let iconImg = new Image(icon);
			iconImg.Width = .Fixed(40);
			iconImg.Height = .Fixed(40);
			iconImg.Stretch = .UniformToFill;
			row.AddChild(iconImg);
		}

		// Info
		let infoCol = new StackPanel();
		infoCol.Orientation = .Vertical;
		infoCol.Spacing = 1;

		let nameStr = scope String();
		nameStr.Set(result.mUnitName);
		if (result.mIsNew)
			nameStr.Append("  NEW!");

		let nameLabel = new TextBlock(nameStr);
		nameLabel.Foreground = result.mIsNew ? Color(255, 220, 80) : Color(220, 220, 230);
		nameLabel.FontSize = 15;
		infoCol.AddChild(nameLabel);

		let detailStr = scope String();
		result.mRarity.ToString(detailStr);
		if (!result.mIsNew)
			detailStr.AppendF(" — +{} shards", result.mShardsGained);

		let detailLabel = new TextBlock(detailStr);
		detailLabel.Foreground = GetRarityTextColor(result.mRarity);
		detailLabel.FontSize = 12;
		infoCol.AddChild(detailLabel);

		row.AddChild(infoCol);
		mResultsPanel.AddChild(card);
		mResultCards.Add(card);
	}

	private Color GetRarityBgColor(Rarity rarity)
	{
		switch (rarity)
		{
		case .Common:    return Color(30, 35, 45, 255);
		case .Uncommon:  return Color(25, 40, 30, 255);
		case .Rare:      return Color(25, 30, 50, 255);
		case .Epic:      return Color(35, 25, 50, 255);
		case .Legendary: return Color(50, 40, 20, 255);
		default:         return Color(30, 35, 45, 255);
		}
	}

	private Color GetRarityTextColor(Rarity rarity)
	{
		switch (rarity)
		{
		case .Common:    return Color(180, 180, 180);
		case .Uncommon:  return Color(60, 200, 60);
		case .Rare:      return Color(60, 120, 240);
		case .Epic:      return Color(180, 60, 240);
		case .Legendary: return Color(255, 200, 40);
		default:         return Color(180, 180, 180);
		}
	}

	private OwnedImageData GetOrCreateIcon(UnitConfig config)
	{
		if (mIconCache.TryGetValue(config.mId, let existing))
			return existing;

		let icon = IconGenerator.GenerateUnitIcon(config.mUnitClass, config.mRarity);
		mIconCache[config.mId] = icon;
		return icon;
	}
}

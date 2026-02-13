namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;
using StormTactics.Core;
using StormTactics.Game;

delegate void ShopBackDelegate();
delegate void ShopBuyDelegate(int32 shopItemId);

/// Shop screen: scrollable list of purchasable items with currency display.
class ShopScreen
{
	private Grid mRoot ~ delete _;

	// Top bar
	private TextBlock mGoldLabel;
	private TextBlock mGemsLabel;
	private TextBlock mRefreshLabel;

	// Item list
	private StackPanel mItemListPanel;
	private ScrollViewer mItemListScroll;

	// State
	private Dictionary<int32, OwnedImageData> mIconCache = new .() ~ { for (let v in _.Values) delete v; delete _; };

	// Events
	private EventAccessor<ShopBackDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<ShopBuyDelegate> mOnBuy = new .() ~ delete _;

	public EventAccessor<ShopBackDelegate> OnBack => mOnBack;
	public EventAccessor<ShopBuyDelegate> OnBuy => mOnBuy;
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
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });     // Full width

		BuildTopBar();
		BuildItemList();
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

		let title = new TextBlock("SHOP");
		title.Foreground = Color(255, 215, 80);
		title.FontSize = 20;
		title.Margin = Thickness(16, 0, 0, 0);
		title.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(title, .Left);
		content.AddChild(title);

		// Currency display (right side)
		let currencyPanel = new StackPanel();
		currencyPanel.Orientation = .Horizontal;
		currencyPanel.Spacing = 16;
		currencyPanel.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(currencyPanel, .Right);

		mGoldLabel = new TextBlock("Gold: 0");
		mGoldLabel.Foreground = Color(255, 215, 80);
		mGoldLabel.FontSize = 14;
		currencyPanel.AddChild(mGoldLabel);

		mGemsLabel = new TextBlock("Gems: 0");
		mGemsLabel.Foreground = Color(130, 200, 255);
		mGemsLabel.FontSize = 14;
		currencyPanel.AddChild(mGemsLabel);

		mRefreshLabel = new TextBlock("");
		mRefreshLabel.Foreground = Color(120, 180, 120);
		mRefreshLabel.FontSize = 12;
		mRefreshLabel.Margin = Thickness(16, 0, 0, 0);
		mRefreshLabel.VerticalAlignment = .Center;
		currencyPanel.AddChild(mRefreshLabel);

		content.AddChild(currencyPanel);

		mRoot.AddChild(topBar);
	}

	private void BuildItemList()
	{
		let listBorder = new Border();
		listBorder.Background = Color(16, 18, 28, 255);
		listBorder.Padding = Thickness(16, 12, 16, 12);
		GridProperties.SetRow(listBorder, 1);

		mItemListScroll = new ScrollViewer();
		mItemListScroll.VerticalScrollBarVisibility = .Auto;
		mItemListScroll.HorizontalScrollBarVisibility = .Disabled;
		listBorder.Child = mItemListScroll;

		mItemListPanel = new StackPanel();
		mItemListPanel.Orientation = .Vertical;
		mItemListPanel.Spacing = 6;
		mItemListScroll.Content = mItemListPanel;

		mRoot.AddChild(listBorder);
	}

	/// Refresh the shop display.
	public void Refresh(PlayerSaveData save, ConfigDatabase configs, ShopManager shopMgr)
	{
		// Update currency
		let goldStr = scope String();
		goldStr.AppendF("Gold: {}", save.mGold);
		mGoldLabel.Text = goldStr;

		let gemsStr = scope String();
		gemsStr.AppendF("Gems: {}", save.mGems);
		mGemsLabel.Text = gemsStr;

		// Refresh timer
		let refreshSecs = shopMgr.SecondsUntilRefresh;
		if (refreshSecs > 0)
		{
			let hours = refreshSecs / 3600;
			let mins = (refreshSecs % 3600) / 60;
			let refreshStr = scope String();
			refreshStr.AppendF("Refresh: {}h {}m", hours, mins);
			mRefreshLabel.Text = refreshStr;
		}
		else
			mRefreshLabel.Text = "Refreshed!";

		// Rebuild item list — featured items first
		mItemListPanel.ClearChildren();

		// Sort: featured first, then by ID
		let sortedItems = scope List<ShopItemConfig>();
		for (let item in configs.ShopItems)
			sortedItems.Add(item);
		sortedItems.Sort(scope (a, b) => {
			if (a.mFeatured != b.mFeatured)
				return a.mFeatured ? -1 : 1;
			return a.mId <=> b.mId;
		});

		bool addedFeaturedHeader = false;
		bool addedRegularHeader = false;

		for (let shopConfig in sortedItems)
		{
			let itemConfig = configs.GetItem(shopConfig.mItemId);
			if (itemConfig == null) continue;

			// Section headers
			if (shopConfig.mFeatured && !addedFeaturedHeader)
			{
				addedFeaturedHeader = true;
				let header = new TextBlock("FEATURED");
				header.Foreground = Color(255, 200, 40);
				header.FontSize = 16;
				header.Margin = Thickness(0, 4, 0, 4);
				mItemListPanel.AddChild(header);
			}
			else if (!shopConfig.mFeatured && !addedRegularHeader)
			{
				addedRegularHeader = true;
				if (addedFeaturedHeader)
				{
					let div = new Border();
					div.Background = Color(60, 65, 80);
					div.Height = .Fixed(1);
					div.HorizontalAlignment = .Stretch;
					div.Margin = Thickness(0, 8, 0, 4);
					mItemListPanel.AddChild(div);
				}
				let header = new TextBlock("ALL ITEMS");
				header.Foreground = Color(160, 160, 180);
				header.FontSize = 14;
				header.Margin = Thickness(0, 0, 0, 4);
				mItemListPanel.AddChild(header);
			}

			bool soldOut = shopMgr.IsSoldOut(shopConfig.mId);
			bool canBuy = shopMgr.CanPurchase(shopConfig.mId);
			int32 remaining = shopMgr.GetRemainingPurchases(shopConfig.mId);
			let shopItemId = shopConfig.mId;

			let icon = GetOrCreateIcon(itemConfig);

			// Row card — featured items get a gold-tinted background
			let card = new Border();
			if (soldOut)
				card.Background = Color(20, 20, 28, 200);
			else if (shopConfig.mFeatured)
				card.Background = Color(40, 35, 20, 255);
			else
				card.Background = Color(25, 30, 48, 255);
			card.Padding = Thickness(12, 8, 12, 8);
			card.HorizontalAlignment = .Stretch;

			let row = new DockPanel();
			row.LastChildFill = true;
			row.VerticalAlignment = .Center;
			card.Child = row;

			// Icon (left)
			let iconImg = new Image(icon);
			iconImg.Width = .Fixed(40);
			iconImg.Height = .Fixed(40);
			iconImg.Stretch = .UniformToFill;
			iconImg.Margin = Thickness(0, 0, 12, 0);
			DockPanelProperties.SetDock(iconImg, .Left);
			row.AddChild(iconImg);

			// Price + limit + buy button column (right)
			let buyCol = new StackPanel();
			buyCol.Orientation = .Vertical;
			buyCol.Spacing = 4;
			buyCol.HorizontalAlignment = .Right;
			buyCol.VerticalAlignment = .Center;
			buyCol.Margin = Thickness(12, 0, 0, 0);
			DockPanelProperties.SetDock(buyCol, .Right);

			// Info column (fills remaining space)
			let infoCol = new StackPanel();
			infoCol.Orientation = .Vertical;
			infoCol.Spacing = 2;
			infoCol.VerticalAlignment = .Center;

			let nameStr = scope String();
			nameStr.AppendF("{}", itemConfig.mName);
			if (shopConfig.mQuantity > 1)
				nameStr.AppendF(" x{}", shopConfig.mQuantity);

			let nameLabel = new TextBlock(nameStr);
			if (soldOut)
				nameLabel.Foreground = Color(80, 80, 90);
			else if (shopConfig.mFeatured)
				nameLabel.Foreground = Color(255, 220, 100);
			else
				nameLabel.Foreground = Color(220, 220, 230);
			nameLabel.FontSize = 15;
			infoCol.AddChild(nameLabel);

			let descLabel = new TextBlock(itemConfig.mDescription);
			descLabel.Foreground = Color(130, 130, 150);
			descLabel.FontSize = 12;
			infoCol.AddChild(descLabel);

			// Populate buyCol before adding children to DockPanel
			// (docked children must be added before the fill child)

			// Price label
			let currStr = scope String();
			let currName = scope String();
			shopConfig.mCurrencyType.ToString(currName);
			currStr.AppendF("{} {}", shopConfig.mCost, currName);

			let priceLabel = new TextBlock(currStr);
			priceLabel.Foreground = shopConfig.mCurrencyType == .Gold
				? Color(255, 215, 80)
				: Color(130, 200, 255);
			priceLabel.FontSize = 13;
			priceLabel.TextAlignment = .Right;
			buyCol.AddChild(priceLabel);

			// Remaining label
			if (remaining >= 0)
			{
				let remStr = scope String();
				remStr.AppendF("{}/{} left", remaining, shopConfig.mPurchaseLimit);
				let remLabel = new TextBlock(remStr);
				remLabel.Foreground = remaining > 0 ? Color(150, 150, 170) : Color(200, 80, 80);
				remLabel.FontSize = 11;
				remLabel.TextAlignment = .Right;
				buyCol.AddChild(remLabel);
			}

			if (soldOut)
			{
				let soldLabel = new TextBlock("SOLD OUT");
				soldLabel.Foreground = Color(200, 80, 80);
				soldLabel.FontSize = 13;
				soldLabel.TextAlignment = .Right;
				buyCol.AddChild(soldLabel);
			}
			else
			{
				let buyBtn = new Button("Buy");
				buyBtn.Padding = Thickness(12, 4, 12, 4);
				if (!canBuy)
					buyBtn.[Friend]mBackground = Color(60, 60, 60, 255);
				buyBtn.Click.Subscribe(new (b) => {
					// Defer event — handler calls Refresh which clears this button's parent
					if (mRoot.Context != null)
						mRoot.Context.MutationQueue.QueueAction(new () => { mOnBuy.[Friend]Invoke(shopItemId); });
					else
						mOnBuy.[Friend]Invoke(shopItemId);
				});
				buyCol.AddChild(buyBtn);
			}

			// Add docked children first, then fill child last
			row.AddChild(buyCol);
			row.AddChild(infoCol);
			mItemListPanel.AddChild(card);
		}
	}

	private OwnedImageData GetOrCreateIcon(ItemConfig config)
	{
		if (mIconCache.TryGetValue(config.mId, let existing))
			return existing;

		let icon = IconGenerator.GenerateItemIcon(config.mType);
		mIconCache[config.mId] = icon;
		return icon;
	}
}

namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;
using Sedulous.Core;
using StormTactics.Core;
using StormTactics.Game;

delegate void InventoryBackDelegate();
delegate void InventoryUseDelegate(int32 itemId);
delegate void InventorySellDelegate(int32 itemId);

/// Inventory screen: grid of item slots on left, selected item detail on right.
class InventoryScreen
{
	private Grid mRoot ~ delete _;

	// Item grid (left)
	private WrapPanel mItemGrid;
	private ScrollViewer mItemScroll;

	// Detail panel (right)
	private TextBlock mDetailName;
	private TextBlock mDetailType;
	private TextBlock mDetailDesc;
	private TextBlock mDetailQuantity;
	private TextBlock mDetailSellPrice;
	private Image mDetailIcon;
	private TextBlock mNoSelectionLabel;
	private Button mUseButton;
	private Button mSellButton;

	// State
	private int32 mSelectedItemId = -1;
	private Dictionary<int32, OwnedImageData> mItemIconCache = new .() ~ { for (let v in _.Values) delete v; delete _; };

	// Cached references for deferred refresh from click handlers
	private PlayerSaveData mCachedSave;
	private ConfigDatabase mCachedConfigs;
	private InventoryManager mCachedInvMgr;

	// Events
	private EventAccessor<InventoryBackDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<InventoryUseDelegate> mOnUse = new .() ~ delete _;
	private EventAccessor<InventorySellDelegate> mOnSell = new .() ~ delete _;
	public EventAccessor<InventoryBackDelegate> OnBack => mOnBack;
	public EventAccessor<InventoryUseDelegate> OnUse => mOnUse;
	public EventAccessor<InventorySellDelegate> OnSell => mOnSell;
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

		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });        // Item grid
		mRoot.ColumnDefinitions.Add(new .() { Width = .Pixels(280) });  // Detail panel
		mRoot.RowDefinitions.Add(new .() { Height = .Pixels(48) });     // Top bar
		mRoot.RowDefinitions.Add(new .() { Height = .Star });          // Content

		BuildTopBar();
		BuildItemGrid();
		BuildDetailPanel();
	}

	private void BuildTopBar()
	{
		let topBar = new Border();
		topBar.Background = Color(18, 22, 32, 240);
		topBar.Padding = Thickness(12, 8, 12, 8);
		GridProperties.SetRow(topBar, 0);
		GridProperties.SetColumnSpan(topBar, 2);

		let content = new DockPanel();
		content.LastChildFill = false;
		content.VerticalAlignment = .Center;
		topBar.Child = content;

		let backBtn = new Button("Back");
		backBtn.Padding = Thickness(16, 4, 16, 4);
		backBtn.Click.Subscribe(new (btn) => { mOnBack.[Friend]Invoke(); });
		DockPanelProperties.SetDock(backBtn, .Left);
		content.AddChild(backBtn);

		let title = new TextBlock("INVENTORY");
		title.Foreground = Color(255, 215, 80);
		title.FontSize = 20;
		title.Margin = Thickness(16, 0, 0, 0);
		title.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(title, .Left);
		content.AddChild(title);

		mRoot.AddChild(topBar);
	}

	private void BuildItemGrid()
	{
		let gridBorder = new Border();
		gridBorder.Background = Color(16, 18, 28, 255);
		gridBorder.Padding = Thickness(8, 8, 8, 8);
		GridProperties.SetRow(gridBorder, 1);
		GridProperties.SetColumn(gridBorder, 0);

		mItemScroll = new ScrollViewer();
		mItemScroll.VerticalScrollBarVisibility = .Auto;
		mItemScroll.HorizontalScrollBarVisibility = .Disabled;
		gridBorder.Child = mItemScroll;

		mItemGrid = new WrapPanel();
		mItemGrid.Orientation = .Horizontal;
		mItemGrid.ItemWidth = 72;
		mItemGrid.ItemHeight = 72;
		mItemScroll.Content = mItemGrid;

		mRoot.AddChild(gridBorder);
	}

	private void BuildDetailPanel()
	{
		let detailBorder = new Border();
		detailBorder.Background = Color(18, 22, 32, 240);
		detailBorder.Padding = Thickness(16, 16, 16, 16);
		GridProperties.SetRow(detailBorder, 1);
		GridProperties.SetColumn(detailBorder, 1);

		let layout = new StackPanel();
		layout.Orientation = .Vertical;
		layout.Spacing = 8;
		layout.VerticalAlignment = .Center;
		layout.HorizontalAlignment = .Center;
		detailBorder.Child = layout;

		mNoSelectionLabel = new TextBlock("Select an item");
		mNoSelectionLabel.Foreground = Color(100, 100, 120);
		mNoSelectionLabel.FontSize = 16;
		mNoSelectionLabel.TextAlignment = .Center;
		layout.AddChild(mNoSelectionLabel);

		mDetailIcon = new Image();
		mDetailIcon.Width = .Fixed(80);
		mDetailIcon.Height = .Fixed(80);
		mDetailIcon.HorizontalAlignment = .Center;
		mDetailIcon.Stretch = .UniformToFill;
		mDetailIcon.Visibility = .Collapsed;
		layout.AddChild(mDetailIcon);

		mDetailName = new TextBlock("");
		mDetailName.Foreground = Color(255, 215, 80);
		mDetailName.FontSize = 20;
		mDetailName.TextAlignment = .Center;
		mDetailName.Visibility = .Collapsed;
		layout.AddChild(mDetailName);

		mDetailType = new TextBlock("");
		mDetailType.Foreground = Color(170, 170, 190);
		mDetailType.FontSize = 14;
		mDetailType.TextAlignment = .Center;
		mDetailType.Visibility = .Collapsed;
		layout.AddChild(mDetailType);

		let div = new Border();
		div.Background = Color(60, 65, 80);
		div.Height = .Fixed(1);
		div.Width = .Fixed(200);
		div.HorizontalAlignment = .Center;
		layout.AddChild(div);

		mDetailDesc = new TextBlock("");
		mDetailDesc.Foreground = Color(180, 180, 200);
		mDetailDesc.FontSize = 14;
		mDetailDesc.TextAlignment = .Center;
		mDetailDesc.Visibility = .Collapsed;
		layout.AddChild(mDetailDesc);

		mDetailQuantity = new TextBlock("");
		mDetailQuantity.Foreground = Color(200, 200, 220);
		mDetailQuantity.FontSize = 16;
		mDetailQuantity.TextAlignment = .Center;
		mDetailQuantity.Visibility = .Collapsed;
		layout.AddChild(mDetailQuantity);

		mDetailSellPrice = new TextBlock("");
		mDetailSellPrice.Foreground = Color(255, 215, 80);
		mDetailSellPrice.FontSize = 13;
		mDetailSellPrice.TextAlignment = .Center;
		mDetailSellPrice.Visibility = .Collapsed;
		layout.AddChild(mDetailSellPrice);

		// Action buttons
		let buttonPanel = new StackPanel();
		buttonPanel.Orientation = .Horizontal;
		buttonPanel.Spacing = 8;
		buttonPanel.HorizontalAlignment = .Center;
		buttonPanel.Margin = Thickness(0, 8, 0, 0);
		layout.AddChild(buttonPanel);

		mUseButton = new Button("Use");
		mUseButton.Padding = Thickness(20, 6, 20, 6);
		mUseButton.Visibility = .Collapsed;
		mUseButton.Click.Subscribe(new (btn) => {
			let itemId = mSelectedItemId;
			if (mRoot.Context != null)
				mRoot.Context.MutationQueue.QueueAction(new () => { mOnUse.[Friend]Invoke(itemId); });
		});
		buttonPanel.AddChild(mUseButton);

		mSellButton = new Button("Sell");
		mSellButton.Padding = Thickness(20, 6, 20, 6);
		mSellButton.Visibility = .Collapsed;
		mSellButton.Click.Subscribe(new (btn) => {
			let itemId = mSelectedItemId;
			if (mRoot.Context != null)
				mRoot.Context.MutationQueue.QueueAction(new () => { mOnSell.[Friend]Invoke(itemId); });
		});
		buttonPanel.AddChild(mSellButton);

		mRoot.AddChild(detailBorder);
	}

	/// Refresh the inventory display.
	public void Refresh(PlayerSaveData save, ConfigDatabase configs, InventoryManager invMgr = null)
	{
		mCachedSave = save;
		mCachedConfigs = configs;
		if (invMgr != null)
			mCachedInvMgr = invMgr;
		mItemGrid.ClearChildren();

		for (let slot in save.mInventory)
		{
			let config = configs.GetItem(slot.mItemId);
			if (config == null) continue;

			let icon = GetOrCreateItemIcon(config);
			let itemId = slot.mItemId;

			// Slot wrapper
			let slotBorder = new Border();
			slotBorder.Background = (itemId == mSelectedItemId)
				? Color(50, 60, 80, 255)
				: Color(30, 35, 50, 255);
			slotBorder.Width = .Fixed(64);
			slotBorder.Height = .Fixed(64);
			slotBorder.Padding = Thickness(2);

			let slotLayout = new Grid();
			slotLayout.RowDefinitions.Add(new .() { Height = .Star });
			slotLayout.ColumnDefinitions.Add(new .() { Width = .Star });
			slotBorder.Child = slotLayout;

			let iconImg = new Image(icon);
			iconImg.Stretch = .UniformToFill;
			iconImg.IsHitTestVisible = false;
			slotLayout.AddChild(iconImg);

			// Quantity label (bottom right)
			let qtyLabel = new TextBlock(scope String()..AppendF("{}", slot.mQuantity));
			qtyLabel.Foreground = Color(255, 255, 255);
			qtyLabel.FontSize = 11;
			qtyLabel.HorizontalAlignment = .Right;
			qtyLabel.VerticalAlignment = .Bottom;
			qtyLabel.IsHitTestVisible = false;
			slotLayout.AddChild(qtyLabel);

			// Click overlay
			let clickBtn = new Button();
			clickBtn.Background = Color(0, 0, 0, 0);
			clickBtn.HorizontalAlignment = .Stretch;
			clickBtn.VerticalAlignment = .Stretch;
			clickBtn.Padding = Thickness(0);
			clickBtn.Click.Subscribe(new (btn) => {
				mSelectedItemId = itemId;
				if (mRoot.Context != null)
				{
					mRoot.Context.MutationQueue.QueueAction(new () => {
						if (mCachedSave != null && mCachedConfigs != null)
							Refresh(mCachedSave, mCachedConfigs);
					});
				}
			});

			let wrapper = new Grid();
			wrapper.RowDefinitions.Add(new .() { Height = .Auto });
			wrapper.ColumnDefinitions.Add(new .() { Width = .Auto });
			wrapper.AddChild(slotBorder);
			wrapper.AddChild(clickBtn);

			mItemGrid.AddChild(wrapper);
		}

		RefreshDetail(save, configs);
	}

	private void RefreshDetail(PlayerSaveData save, ConfigDatabase configs)
	{
		let slot = save.GetInventorySlot(mSelectedItemId);
		let config = (mSelectedItemId >= 0) ? configs.GetItem(mSelectedItemId) : null;

		if (slot == null || config == null)
		{
			mNoSelectionLabel.Visibility = .Visible;
			mDetailIcon.Visibility = .Collapsed;
			mDetailName.Visibility = .Collapsed;
			mDetailType.Visibility = .Collapsed;
			mDetailDesc.Visibility = .Collapsed;
			mDetailQuantity.Visibility = .Collapsed;
			mDetailSellPrice.Visibility = .Collapsed;
			mUseButton.Visibility = .Collapsed;
			mSellButton.Visibility = .Collapsed;
			return;
		}

		mNoSelectionLabel.Visibility = .Collapsed;
		mDetailIcon.Visibility = .Visible;
		mDetailName.Visibility = .Visible;
		mDetailType.Visibility = .Visible;
		mDetailDesc.Visibility = .Visible;
		mDetailQuantity.Visibility = .Visible;

		let icon = GetOrCreateItemIcon(config);
		mDetailIcon.Source = icon;

		mDetailName.Text = config.mName;

		let typeStr = scope String();
		config.mType.ToString(typeStr);
		mDetailType.Text = typeStr;

		mDetailDesc.Text = config.mDescription;

		let qtyStr = scope String();
		qtyStr.AppendF("Quantity: {}", slot.mQuantity);
		mDetailQuantity.Text = qtyStr;

		// Sell price
		if (config.mSellPrice > 0 && config.mType != .Currency)
		{
			let sellStr = scope String();
			sellStr.AppendF("Sell: {} gold each", config.mSellPrice);
			mDetailSellPrice.Text = sellStr;
			mDetailSellPrice.Visibility = .Visible;
		}
		else
			mDetailSellPrice.Visibility = .Collapsed;

		// Use button: show for all consumables (target selection handled by caller)
		bool canUse = mCachedInvMgr != null && mCachedInvMgr.CanUseItem(mSelectedItemId);
		mUseButton.Visibility = canUse ? .Visible : .Collapsed;

		// Sell button: show for sellable items
		bool canSell = mCachedInvMgr != null && mCachedInvMgr.CanSellItem(mSelectedItemId);
		mSellButton.Visibility = canSell ? .Visible : .Collapsed;
	}

	private OwnedImageData GetOrCreateItemIcon(ItemConfig config)
	{
		if (mItemIconCache.TryGetValue(config.mId, let existing))
			return existing;

		let icon = IconGenerator.GenerateItemIcon(config.mType);
		mItemIconCache[config.mId] = icon;
		return icon;
	}
}

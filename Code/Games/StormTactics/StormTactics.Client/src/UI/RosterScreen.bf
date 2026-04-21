namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;
using Sedulous.Core;
using StormTactics.Core;
using StormTactics.Game;
using Sedulous.ImageData;

delegate void RosterBackDelegate();
delegate void RosterStarUpDelegate(int32 unitId);
delegate void RosterEquipSlotDelegate(int32 unitId, EquipSlot slot);

/// Unit roster screen: scrollable list on left, detail panel on right.
class RosterScreen
{
	// Root
	private Grid mRoot ~ delete _;

	// Unit list (left side)
	private StackPanel mUnitListPanel;
	private ScrollViewer mUnitListScroll;

	// Detail panel (right side)
	private Border mDetailPanel;
	private Image mDetailIcon;
	private TextBlock mDetailName;
	private TextBlock mDetailClass;
	private TextBlock mDetailRarity;
	private TextBlock mDetailStars;
	private TextBlock mDetailLevel;
	private TextBlock mDetailHP;
	private TextBlock mDetailDamage;
	private TextBlock mDetailDefense;
	private TextBlock mDetailSpeed;
	private TextBlock mDetailPower;
	private TextBlock mDetailShards;
	private ProgressBar mShardBar;
	private Button mStarUpButton;
	private TextBlock mNoSelectionLabel;

	// Equip slots
	private Button mWeaponSlotBtn;
	private Button mArmorSlotBtn;
	private Button mAccessorySlotBtn;
	private TextBlock mWeaponSlotLabel;
	private TextBlock mArmorSlotLabel;
	private TextBlock mAccessorySlotLabel;

	// State
	private int32 mSelectedUnitId = -1;
	private Dictionary<int32, OwnedImageData> mIconCache = new .() ~ { for (let v in _.Values) delete v; delete _; };

	// Cached references for refresh from click handlers
	private PlayerSaveData mCachedSave;
	private ConfigDatabase mCachedConfigs;
	private RosterManager mCachedRoster;
	private EquipmentManager mCachedEquipMgr;

	// Events
	private EventAccessor<RosterBackDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<RosterStarUpDelegate> mOnStarUp = new .() ~ delete _;
	private EventAccessor<RosterEquipSlotDelegate> mOnEquipSlot = new .() ~ delete _;

	public EventAccessor<RosterBackDelegate> OnBack => mOnBack;
	public EventAccessor<RosterStarUpDelegate> OnStarUp => mOnStarUp;
	public EventAccessor<RosterEquipSlotDelegate> OnEquipSlot => mOnEquipSlot;
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

		// Two columns: unit list (left), detail (right)
		mRoot.ColumnDefinitions.Add(new .() { Width = .Pixels(280) });
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });
		mRoot.RowDefinitions.Add(new .() { Height = .Pixels(48) }); // Top bar
		mRoot.RowDefinitions.Add(new .() { Height = .Star });      // Content

		BuildTopBar();
		BuildUnitList();
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

		let title = new TextBlock("UNIT ROSTER");
		title.Foreground = Color(255, 215, 80);
		title.FontSize = 20;
		title.Margin = Thickness(16, 0, 0, 0);
		title.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(title, .Left);
		content.AddChild(title);

		mRoot.AddChild(topBar);
	}

	private void BuildUnitList()
	{
		let listBorder = new Border();
		listBorder.Background = Color(16, 18, 28, 255);
		listBorder.Padding = Thickness(8, 8, 8, 8);
		GridProperties.SetRow(listBorder, 1);
		GridProperties.SetColumn(listBorder, 0);

		mUnitListScroll = new ScrollViewer();
		mUnitListScroll.VerticalScrollBarVisibility = .Auto;
		mUnitListScroll.HorizontalScrollBarVisibility = .Disabled;
		listBorder.Child = mUnitListScroll;

		mUnitListPanel = new StackPanel();
		mUnitListPanel.Orientation = .Vertical;
		mUnitListPanel.Spacing = 4;
		mUnitListScroll.Content = mUnitListPanel;

		mRoot.AddChild(listBorder);
	}

	private void BuildDetailPanel()
	{
		mDetailPanel = new Border();
		mDetailPanel.Background = Color(18, 22, 32, 240);
		mDetailPanel.Padding = Thickness(24, 16, 24, 16);
		GridProperties.SetRow(mDetailPanel, 1);
		GridProperties.SetColumn(mDetailPanel, 1);

		let layout = new StackPanel();
		layout.Orientation = .Vertical;
		layout.Spacing = 8;
		layout.HorizontalAlignment = .Center;
		layout.VerticalAlignment = .Center;
		mDetailPanel.Child = layout;

		// No selection placeholder
		mNoSelectionLabel = new TextBlock("Select a unit to view details");
		mNoSelectionLabel.Foreground = Color(100, 100, 120);
		mNoSelectionLabel.FontSize = 18;
		mNoSelectionLabel.TextAlignment = .Center;
		layout.AddChild(mNoSelectionLabel);

		// Large icon
		mDetailIcon = new Image();
		mDetailIcon.Width = .Fixed(96);
		mDetailIcon.Height = .Fixed(96);
		mDetailIcon.HorizontalAlignment = .Center;
		mDetailIcon.Stretch = .UniformToFill;
		mDetailIcon.Visibility = .Collapsed;
		layout.AddChild(mDetailIcon);

		// Name
		mDetailName = new TextBlock("");
		mDetailName.Foreground = Color(255, 215, 80);
		mDetailName.FontSize = 24;
		mDetailName.TextAlignment = .Center;
		mDetailName.Visibility = .Collapsed;
		layout.AddChild(mDetailName);

		// Class + Rarity row
		let classRow = new StackPanel();
		classRow.Orientation = .Horizontal;
		classRow.Spacing = 16;
		classRow.HorizontalAlignment = .Center;

		mDetailClass = new TextBlock("");
		mDetailClass.Foreground = Color(170, 170, 190);
		mDetailClass.FontSize = 16;
		mDetailClass.Visibility = .Collapsed;
		classRow.AddChild(mDetailClass);

		mDetailRarity = new TextBlock("");
		mDetailRarity.FontSize = 16;
		mDetailRarity.Visibility = .Collapsed;
		classRow.AddChild(mDetailRarity);

		layout.AddChild(classRow);

		// Stars + Level
		mDetailStars = new TextBlock("");
		mDetailStars.FontSize = 20;
		mDetailStars.Foreground = Color(255, 215, 80);
		mDetailStars.TextAlignment = .Center;
		mDetailStars.Visibility = .Collapsed;
		layout.AddChild(mDetailStars);

		mDetailLevel = new TextBlock("");
		mDetailLevel.Foreground = Color(200, 200, 220);
		mDetailLevel.FontSize = 16;
		mDetailLevel.TextAlignment = .Center;
		mDetailLevel.Visibility = .Collapsed;
		layout.AddChild(mDetailLevel);

		// Divider
		let div = new Border();
		div.Background = Color(60, 65, 80);
		div.Height = .Fixed(1);
		div.Width = .Fixed(200);
		div.HorizontalAlignment = .Center;
		layout.AddChild(div);

		// Stats
		mDetailHP = new TextBlock("");
		mDetailHP.Foreground = Color(100, 220, 100);
		mDetailHP.FontSize = 15;
		mDetailHP.TextAlignment = .Center;
		mDetailHP.Visibility = .Collapsed;
		layout.AddChild(mDetailHP);

		mDetailDamage = new TextBlock("");
		mDetailDamage.Foreground = Color(220, 100, 100);
		mDetailDamage.FontSize = 15;
		mDetailDamage.TextAlignment = .Center;
		mDetailDamage.Visibility = .Collapsed;
		layout.AddChild(mDetailDamage);

		mDetailDefense = new TextBlock("");
		mDetailDefense.Foreground = Color(100, 150, 220);
		mDetailDefense.FontSize = 15;
		mDetailDefense.TextAlignment = .Center;
		mDetailDefense.Visibility = .Collapsed;
		layout.AddChild(mDetailDefense);

		mDetailSpeed = new TextBlock("");
		mDetailSpeed.Foreground = Color(200, 200, 100);
		mDetailSpeed.FontSize = 15;
		mDetailSpeed.TextAlignment = .Center;
		mDetailSpeed.Visibility = .Collapsed;
		layout.AddChild(mDetailSpeed);

		mDetailPower = new TextBlock("");
		mDetailPower.Foreground = Color(255, 180, 60);
		mDetailPower.FontSize = 16;
		mDetailPower.TextAlignment = .Center;
		mDetailPower.Visibility = .Collapsed;
		layout.AddChild(mDetailPower);

		// Divider 2
		let div2 = new Border();
		div2.Background = Color(60, 65, 80);
		div2.Height = .Fixed(1);
		div2.Width = .Fixed(200);
		div2.HorizontalAlignment = .Center;
		layout.AddChild(div2);

		// Shard progress
		mDetailShards = new TextBlock("");
		mDetailShards.Foreground = Color(180, 180, 200);
		mDetailShards.FontSize = 14;
		mDetailShards.TextAlignment = .Center;
		mDetailShards.Visibility = .Collapsed;
		layout.AddChild(mDetailShards);

		mShardBar = new ProgressBar();
		mShardBar.Width = .Fixed(200);
		mShardBar.Height = .Fixed(12);
		mShardBar.Minimum = 0;
		mShardBar.Maximum = 100;
		mShardBar.Value = 0;
		mShardBar.HorizontalAlignment = .Center;
		mShardBar.Visibility = .Collapsed;
		layout.AddChild(mShardBar);

		// Star-up button
		mStarUpButton = new Button("Star Up");
		mStarUpButton.Padding = Thickness(20, 8, 20, 8);
		mStarUpButton.HorizontalAlignment = .Center;
		mStarUpButton.Visibility = .Collapsed;
		mStarUpButton.Click.Subscribe(new (btn) => {
			if (mSelectedUnitId >= 0)
				mOnStarUp.[Friend]Invoke(mSelectedUnitId);
		});
		layout.AddChild(mStarUpButton);

		// Equip slots divider
		let div3 = new Border();
		div3.Background = Color(60, 65, 80);
		div3.Height = .Fixed(1);
		div3.Width = .Fixed(200);
		div3.HorizontalAlignment = .Center;
		layout.AddChild(div3);

		let equipTitle = new TextBlock("Equipment");
		equipTitle.Foreground = Color(180, 180, 200);
		equipTitle.FontSize = 14;
		equipTitle.TextAlignment = .Center;
		equipTitle.Visibility = .Collapsed;
		layout.AddChild(equipTitle);

		// Weapon slot
		mWeaponSlotBtn = CreateEquipSlotButton("Weapon", .Weapon, out mWeaponSlotLabel);
		layout.AddChild(mWeaponSlotBtn);

		// Armor slot
		mArmorSlotBtn = CreateEquipSlotButton("Armor", .Armor, out mArmorSlotLabel);
		layout.AddChild(mArmorSlotBtn);

		// Accessory slot
		mAccessorySlotBtn = CreateEquipSlotButton("Accessory", .Accessory, out mAccessorySlotLabel);
		layout.AddChild(mAccessorySlotBtn);

		mRoot.AddChild(mDetailPanel);
	}

	/// Refresh the unit list from save data.
	public void RefreshUnitList(PlayerSaveData save, ConfigDatabase configs, RosterManager roster)
	{
		mUnitListPanel.ClearChildren();

		for (let owned in save.mOwnedUnits)
		{
			let config = configs.GetUnit(owned.mUnitId);
			if (config == null) continue;

			let icon = GetOrCreateIcon(config);
			let stats = roster.GetEffectiveStats(owned.mUnitId);
			let cardUnitId = owned.mUnitId;

			// Card row: icon + info
			let card = new Border();
			card.Background = (cardUnitId == mSelectedUnitId)
				? Color(40, 50, 70, 255)
				: Color(25, 30, 45, 255);
			card.Padding = Thickness(8, 6, 8, 6);
			card.HorizontalAlignment = .Stretch;

			let row = new StackPanel();
			row.Orientation = .Horizontal;
			row.Spacing = 10;
			row.VerticalAlignment = .Center;
			card.Child = row;

			// Small icon
			let iconImg = new Image(icon);
			iconImg.Width = .Fixed(40);
			iconImg.Height = .Fixed(40);
			iconImg.Stretch = .UniformToFill;
			iconImg.IsHitTestVisible = false;
			row.AddChild(iconImg);

			// Info column
			let infoCol = new StackPanel();
			infoCol.Orientation = .Vertical;
			infoCol.Spacing = 1;
			infoCol.IsHitTestVisible = false;

			let nameLabel = new TextBlock(config.mName);
			nameLabel.Foreground = Color(220, 220, 230);
			nameLabel.FontSize = 15;
			nameLabel.IsHitTestVisible = false;
			infoCol.AddChild(nameLabel);

			let subStr = scope String();
			subStr.AppendF("Lv.{} | {}* | PWR:{}", owned.mLevel, owned.mStarLevel, stats.mPower);

			let subLabel = new TextBlock(subStr);
			subLabel.Foreground = Color(140, 140, 160);
			subLabel.FontSize = 12;
			subLabel.IsHitTestVisible = false;
			infoCol.AddChild(subLabel);

			row.AddChild(infoCol);

			// Clickable overlay
			let clickBtn = new Button();
			clickBtn.Background = Color(0, 0, 0, 0);
			clickBtn.HorizontalAlignment = .Stretch;
			clickBtn.VerticalAlignment = .Stretch;
			clickBtn.Padding = Thickness(0);
			clickBtn.Click.Subscribe(new (btn) => {
				mSelectedUnitId = cardUnitId;
				// Defer detail refresh + list rebuild to avoid modifying tree during event
				if (mRoot.Context != null)
				{
					mRoot.Context.MutationQueue.QueueAction(new () => {
						if (mCachedSave != null && mCachedConfigs != null && mCachedRoster != null)
						{
							RefreshUnitList(mCachedSave, mCachedConfigs, mCachedRoster);
							RefreshDetailPanel(mCachedSave, mCachedConfigs, mCachedRoster, mCachedEquipMgr);
						}
					});
				}
			});

			let wrapper = new Grid();
			wrapper.HorizontalAlignment = .Stretch;
			wrapper.RowDefinitions.Add(new .() { Height = .Auto });
			wrapper.ColumnDefinitions.Add(new .() { Width = .Star });
			wrapper.AddChild(card);
			wrapper.AddChild(clickBtn);

			mUnitListPanel.AddChild(wrapper);
		}
	}

	/// Update the detail panel for the currently selected unit.
	public void RefreshDetailPanel(PlayerSaveData save, ConfigDatabase configs, RosterManager roster, EquipmentManager equipMgr = null)
	{
		let owned = save.GetOwnedUnit(mSelectedUnitId);
		let config = (mSelectedUnitId >= 0) ? configs.GetUnit(mSelectedUnitId) : null;

		if (owned == null || config == null)
		{
			// No selection — show placeholder
			mNoSelectionLabel.Visibility = .Visible;
			SetDetailVisibility(.Collapsed);
			return;
		}

		mNoSelectionLabel.Visibility = .Collapsed;
		SetDetailVisibility(.Visible);

		// Icon
		let icon = GetOrCreateIcon(config);
		mDetailIcon.Source = icon;

		// Name
		mDetailName.Text = config.mName;

		// Class
		let className = scope String();
		config.mUnitClass.ToString(className);
		mDetailClass.Text = className;

		// Rarity
		let rarityStr = scope String();
		config.mRarity.ToString(rarityStr);
		mDetailRarity.Text = rarityStr;
		mDetailRarity.Foreground = GetRarityColor(config.mRarity);

		// Stars
		let starStr = scope String();
		starStr.AppendF("{}/5 Stars", owned.mStarLevel);
		mDetailStars.Text = starStr;

		// Level + EXP
		let lvlStr = scope String();
		let expNeeded = roster.GetUnitExpToNextLevel(mSelectedUnitId);
		if (expNeeded > 0)
			lvlStr.AppendF("Level {}  (EXP: {}/{})", owned.mLevel, owned.mExp, expNeeded);
		else
			lvlStr.AppendF("Level {} (MAX)", owned.mLevel);
		mDetailLevel.Text = lvlStr;

		// Stats
		let stats = roster.GetEffectiveStats(mSelectedUnitId);

		let hpStr = scope String();
		hpStr.AppendF("HP: {}", stats.mHP);
		mDetailHP.Text = hpStr;

		let dmgStr = scope String();
		dmgStr.AppendF("Damage: {}", stats.mDamage);
		mDetailDamage.Text = dmgStr;

		let defStr = scope String();
		defStr.AppendF("Defense: {}", stats.mDefense);
		mDetailDefense.Text = defStr;

		let spdStr = scope String();
		spdStr.AppendF("Speed: {}", stats.mActionSpeed);
		mDetailSpeed.Text = spdStr;

		let pwrStr = scope String();
		pwrStr.AppendF("Power: {}", stats.mPower);
		mDetailPower.Text = pwrStr;

		// Shards
		int32 shardsNeeded = roster.GetShardsForNextStar(mSelectedUnitId);
		if (shardsNeeded > 0)
		{
			let shardStr = scope String();
			shardStr.AppendF("Shards: {} / {}", owned.mShards, shardsNeeded);
			mDetailShards.Text = shardStr;
			mShardBar.Maximum = (float)shardsNeeded;
			mShardBar.Value = (float)Math.Min(owned.mShards, shardsNeeded);
			mShardBar.Visibility = .Visible;
			mDetailShards.Visibility = .Visible;

			// Star-up button
			if (roster.CanStarUp(mSelectedUnitId))
			{
				mStarUpButton.Visibility = .Visible;
				mStarUpButton.[Friend]mBackground = null;
			}
			else
			{
				mStarUpButton.Visibility = .Visible;
				mStarUpButton.[Friend]mBackground = Color(60, 60, 60, 255);
			}
		}
		else
		{
			mDetailShards.Text = "MAX STAR";
			mDetailShards.Visibility = .Visible;
			mShardBar.Visibility = .Collapsed;
			mStarUpButton.Visibility = .Collapsed;
		}

		// Equipment slots
		UpdateEquipSlotLabel(mWeaponSlotLabel, owned.mEquipWeaponId, save, configs);
		UpdateEquipSlotLabel(mArmorSlotLabel, owned.mEquipArmorId, save, configs);
		UpdateEquipSlotLabel(mAccessorySlotLabel, owned.mEquipAccessoryId, save, configs);
	}

	private void UpdateEquipSlotLabel(TextBlock label, int32 equipInstanceId, PlayerSaveData save, ConfigDatabase configs)
	{
		if (equipInstanceId == 0)
		{
			label.Text = "[Empty]";
			label.Foreground = Color(100, 100, 120);
			return;
		}

		let equip = save.GetOwnedEquip(equipInstanceId);
		if (equip != null)
		{
			let config = configs.GetEquip(equip.mEquipId);
			if (config != null)
			{
				let nameStr = scope String();
				nameStr.Append(config.mName);
				if (equip.mEnhanceLevel > 0)
					nameStr.AppendF(" +{}", equip.mEnhanceLevel);
				label.Text = nameStr;
				label.Foreground = Color(200, 200, 220);
				return;
			}
		}

		label.Text = "[Unknown]";
		label.Foreground = Color(100, 100, 120);
	}

	/// Full refresh: list + detail.
	public void Refresh(PlayerSaveData save, ConfigDatabase configs, RosterManager roster, EquipmentManager equipMgr = null)
	{
		mCachedSave = save;
		mCachedConfigs = configs;
		mCachedRoster = roster;
		mCachedEquipMgr = equipMgr;
		RefreshUnitList(save, configs, roster);
		RefreshDetailPanel(save, configs, roster, equipMgr);
	}

	public int32 SelectedUnitId => mSelectedUnitId;

	private void SetDetailVisibility(Visibility vis)
	{
		mDetailIcon.Visibility = vis;
		mDetailName.Visibility = vis;
		mDetailClass.Visibility = vis;
		mDetailRarity.Visibility = vis;
		mDetailStars.Visibility = vis;
		mDetailLevel.Visibility = vis;
		mDetailHP.Visibility = vis;
		mDetailDamage.Visibility = vis;
		mDetailDefense.Visibility = vis;
		mDetailSpeed.Visibility = vis;
		mDetailPower.Visibility = vis;
		mDetailShards.Visibility = vis;
		mShardBar.Visibility = vis;
		mStarUpButton.Visibility = vis;
		mWeaponSlotBtn.Visibility = vis;
		mArmorSlotBtn.Visibility = vis;
		mAccessorySlotBtn.Visibility = vis;
	}

	private Button CreateEquipSlotButton(StringView slotName, EquipSlot slot, out TextBlock label)
	{
		let btn = new Button();
		btn.Padding = Thickness(8, 4, 8, 4);
		btn.HorizontalAlignment = .Center;
		btn.Width = .Fixed(220);
		btn.Visibility = .Collapsed;

		let content = new StackPanel();
		content.Orientation = .Horizontal;
		content.Spacing = 8;
		content.VerticalAlignment = .Center;

		let slotLabel = new TextBlock(slotName);
		slotLabel.Foreground = Color(140, 140, 160);
		slotLabel.FontSize = 12;
		slotLabel.Width = .Fixed(70);
		content.AddChild(slotLabel);

		label = new TextBlock("[Empty]");
		label.Foreground = Color(100, 100, 120);
		label.FontSize = 12;
		content.AddChild(label);

		btn.Content = content;
		btn.Click.Subscribe(new (b) => {
			if (mSelectedUnitId >= 0)
				mOnEquipSlot.[Friend]Invoke(mSelectedUnitId, slot);
		});

		return btn;
	}

	private OwnedImageData GetOrCreateIcon(UnitConfig config)
	{
		if (mIconCache.TryGetValue(config.mId, let existing))
			return existing;

		let icon = IconGenerator.GenerateUnitIcon(config.mUnitClass, config.mRarity);
		mIconCache[config.mId] = icon;
		return icon;
	}

	private Color GetRarityColor(Rarity rarity)
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
}

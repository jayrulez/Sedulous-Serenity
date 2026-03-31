namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;
using Sedulous.Core;
using StormTactics.Core;
using StormTactics.Game;

delegate void EquipSelectedDelegate(int32 equipInstanceId);
delegate void EquipPopupCloseDelegate();

/// Modal popup for selecting equipment to place in a slot.
class EquipSelectPopup
{
	private Popup mPopup ~ delete _;
	private TextBlock mTitleLabel;
	private StackPanel mEquipListPanel;
	private ScrollViewer mEquipListScroll;

	// State
	private int32 mTargetUnitId;
	private EquipSlot mTargetSlot;
	private Dictionary<int32, OwnedImageData> mEquipIconCache = new .() ~ { for (let v in _.Values) delete v; delete _; };

	// Events
	private EventAccessor<EquipSelectedDelegate> mOnEquipSelected = new .() ~ delete _;
	private EventAccessor<EquipPopupCloseDelegate> mOnClose = new .() ~ delete _;

	public EventAccessor<EquipSelectedDelegate> OnEquipSelected => mOnEquipSelected;
	public EventAccessor<EquipPopupCloseDelegate> OnClose => mOnClose;
	public int32 TargetUnitId => mTargetUnitId;
	public EquipSlot TargetSlot => mTargetSlot;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		mPopup = new Popup();
		mPopup.Background = Color(22, 26, 38, 250);
		mPopup.Width = .Fixed(360);
		mPopup.Height = .Fixed(400);
		mPopup.Padding = Thickness(16, 12, 16, 12);
		mPopup.Behavior = .CloseOnClickOutside | .CloseOnEscape;
		mPopup.Closed.Subscribe(new (popup) => {
			mOnClose.[Friend]Invoke();
		});

		let layout = new StackPanel();
		layout.Orientation = .Vertical;
		layout.Spacing = 8;
		mPopup.Content = layout;

		// Title
		mTitleLabel = new TextBlock("Select Equipment");
		mTitleLabel.Foreground = Color(255, 215, 80);
		mTitleLabel.FontSize = 18;
		mTitleLabel.TextAlignment = .Center;
		mTitleLabel.HorizontalAlignment = .Center;
		layout.AddChild(mTitleLabel);

		// Divider
		let div = new Border();
		div.Background = Color(60, 65, 80);
		div.Height = .Fixed(1);
		div.HorizontalAlignment = .Stretch;
		layout.AddChild(div);

		// Scrollable equip list
		mEquipListScroll = new ScrollViewer();
		mEquipListScroll.VerticalScrollBarVisibility = .Auto;
		mEquipListScroll.HorizontalScrollBarVisibility = .Disabled;
		mEquipListScroll.HorizontalAlignment = .Stretch;
		layout.AddChild(mEquipListScroll);

		mEquipListPanel = new StackPanel();
		mEquipListPanel.Orientation = .Vertical;
		mEquipListPanel.Spacing = 4;
		mEquipListScroll.Content = mEquipListPanel;

		// Unequip + Close buttons row
		let btnRow = new StackPanel();
		btnRow.Orientation = .Horizontal;
		btnRow.Spacing = 12;
		btnRow.HorizontalAlignment = .Center;
		layout.AddChild(btnRow);

		let unequipBtn = new Button("Unequip");
		unequipBtn.Padding = Thickness(16, 6, 16, 6);
		unequipBtn.Click.Subscribe(new (btn) => {
			mOnEquipSelected.[Friend]Invoke(0); // 0 = unequip
			Hide();
		});
		btnRow.AddChild(unequipBtn);

		let closeBtn = new Button("Close");
		closeBtn.Padding = Thickness(16, 6, 16, 6);
		closeBtn.Click.Subscribe(new (btn) => {
			Hide();
		});
		btnRow.AddChild(closeBtn);
	}

	/// Show the popup for a given unit and equip slot.
	public void Show(GUIContext context, int32 unitId, EquipSlot slot, PlayerSaveData save, ConfigDatabase configs, EquipmentManager equipMgr)
	{
		mTargetUnitId = unitId;
		mTargetSlot = slot;

		// Title
		let slotStr = scope String();
		slot.ToString(slotStr);
		let titleStr = scope String();
		titleStr.AppendF("Select {}", slotStr);
		mTitleLabel.Text = titleStr;

		// Build equip list
		mEquipListPanel.ClearChildren();

		int32 currentEquipInSlot = equipMgr.GetEquipInSlot(unitId, slot);

		for (let ownedEquip in save.mOwnedEquips)
		{
			let config = configs.GetEquip(ownedEquip.mEquipId);
			if (config == null) continue;
			if (config.mSlot != slot) continue; // Only show matching slot type

			let instanceId = ownedEquip.mInstanceId;
			bool isCurrentlyEquipped = (instanceId == currentEquipInSlot);
			bool isEquippedByOther = !isCurrentlyEquipped && equipMgr.IsEquipped(instanceId);

			let icon = GetOrCreateEquipIcon(config);

			// Row: icon + info + equip indicator
			let row = new Border();
			row.Background = isCurrentlyEquipped
				? Color(40, 60, 50, 255)
				: Color(28, 32, 48, 255);
			row.Padding = Thickness(8, 6, 8, 6);
			row.HorizontalAlignment = .Stretch;

			let content = new StackPanel();
			content.Orientation = .Horizontal;
			content.Spacing = 10;
			content.VerticalAlignment = .Center;
			row.Child = content;

			let iconImg = new Image(icon);
			iconImg.Width = .Fixed(36);
			iconImg.Height = .Fixed(36);
			iconImg.Stretch = .UniformToFill;
			iconImg.IsHitTestVisible = false;
			content.AddChild(iconImg);

			let infoCol = new StackPanel();
			infoCol.Orientation = .Vertical;
			infoCol.Spacing = 1;
			infoCol.IsHitTestVisible = false;

			let nameLabel = new TextBlock(config.mName);
			nameLabel.Foreground = Color(220, 220, 230);
			nameLabel.FontSize = 14;
			nameLabel.IsHitTestVisible = false;
			infoCol.AddChild(nameLabel);

			// Stat summary line
			let statsStr = scope String();
			for (let mod in config.mStatBonuses)
			{
				if (statsStr.Length > 0) statsStr.Append(", ");
				let attrStr = scope String();
				mod.mAttribute.ToString(attrStr);
				if (mod.mFlatValue != 0)
					statsStr.AppendF("+{} {}", (int32)mod.mFlatValue, attrStr);
				else if (mod.mPercentValue != 0)
					statsStr.AppendF("+{}% {}", (int32)(mod.mPercentValue * 100), attrStr);
			}
			if (isEquippedByOther)
				statsStr.Append(" [Equipped]");
			if (isCurrentlyEquipped)
				statsStr.Append(" [Current]");

			let statLabel = new TextBlock(statsStr);
			statLabel.Foreground = isEquippedByOther ? Color(120, 120, 140) : Color(150, 180, 150);
			statLabel.FontSize = 11;
			statLabel.IsHitTestVisible = false;
			infoCol.AddChild(statLabel);

			content.AddChild(infoCol);

			// Click overlay
			let clickBtn = new Button();
			clickBtn.Background = Color(0, 0, 0, 0);
			clickBtn.HorizontalAlignment = .Stretch;
			clickBtn.VerticalAlignment = .Stretch;
			clickBtn.Padding = Thickness(0);
			clickBtn.Click.Subscribe(new (btn) => {
				mOnEquipSelected.[Friend]Invoke(instanceId);
				Hide();
			});

			let wrapper = new Grid();
			wrapper.HorizontalAlignment = .Stretch;
			wrapper.RowDefinitions.Add(new .() { Height = .Auto });
			wrapper.ColumnDefinitions.Add(new .() { Width = .Star });
			wrapper.AddChild(row);
			wrapper.AddChild(clickBtn);

			mEquipListPanel.AddChild(wrapper);
		}

		// If no matching equips found
		if (mEquipListPanel.ChildCount == 0)
		{
			let emptyLabel = new TextBlock("No equipment available for this slot");
			emptyLabel.Foreground = Color(100, 100, 120);
			emptyLabel.FontSize = 14;
			emptyLabel.TextAlignment = .Center;
			emptyLabel.HorizontalAlignment = .Center;
			emptyLabel.Margin = Thickness(0, 16, 0, 16);
			mEquipListPanel.AddChild(emptyLabel);
		}

		// Open centered in viewport
		let x = (context.ViewportWidth - 360) / 2;
		let y = (context.ViewportHeight - 400) / 2;
		mPopup.OpenAt(context, x, y);
	}

	public void Hide()
	{
		mPopup.Close();
	}

	public bool IsVisible => mPopup.IsOpen;

	private OwnedImageData GetOrCreateEquipIcon(EquipConfig config)
	{
		if (mEquipIconCache.TryGetValue(config.mId, let existing))
			return existing;

		let icon = IconGenerator.GenerateEquipIcon(config.mSlot, config.mRarity);
		mEquipIconCache[config.mId] = icon;
		return icon;
	}
}

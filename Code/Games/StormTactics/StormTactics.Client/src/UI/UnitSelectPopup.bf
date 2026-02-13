namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;
using StormTactics.Core;
using StormTactics.Game;

delegate void UnitSelectedDelegate(int32 unitId);

/// Modal popup for selecting a unit (e.g. to use an EXP potion on).
class UnitSelectPopup
{
	private Popup mPopup ~ delete _;
	private TextBlock mTitleLabel;
	private StackPanel mUnitListPanel;
	private ScrollViewer mUnitListScroll;

	// State
	private int32 mItemId;

	// Events
	private EventAccessor<UnitSelectedDelegate> mOnUnitSelected = new .() ~ delete _;

	public EventAccessor<UnitSelectedDelegate> OnUnitSelected => mOnUnitSelected;
	public int32 ItemId => mItemId;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		mPopup = new Popup();
		mPopup.Background = Color(22, 26, 38, 250);
		mPopup.Width = .Fixed(320);
		mPopup.Height = .Fixed(380);
		mPopup.Padding = Thickness(16, 12, 16, 12);
		mPopup.Behavior = .CloseOnClickOutside | .CloseOnEscape;

		let layout = new StackPanel();
		layout.Orientation = .Vertical;
		layout.Spacing = 8;
		mPopup.Content = layout;

		mTitleLabel = new TextBlock("Select Unit");
		mTitleLabel.Foreground = Color(255, 215, 80);
		mTitleLabel.FontSize = 18;
		mTitleLabel.TextAlignment = .Center;
		mTitleLabel.HorizontalAlignment = .Center;
		layout.AddChild(mTitleLabel);

		let div = new Border();
		div.Background = Color(60, 65, 80);
		div.Height = .Fixed(1);
		div.HorizontalAlignment = .Stretch;
		layout.AddChild(div);

		mUnitListScroll = new ScrollViewer();
		mUnitListScroll.VerticalScrollBarVisibility = .Auto;
		mUnitListScroll.HorizontalScrollBarVisibility = .Disabled;
		mUnitListScroll.HorizontalAlignment = .Stretch;
		layout.AddChild(mUnitListScroll);

		mUnitListPanel = new StackPanel();
		mUnitListPanel.Orientation = .Vertical;
		mUnitListPanel.Spacing = 4;
		mUnitListScroll.Content = mUnitListPanel;

		let closeBtn = new Button("Cancel");
		closeBtn.Padding = Thickness(16, 6, 16, 6);
		closeBtn.HorizontalAlignment = .Center;
		closeBtn.Click.Subscribe(new (btn) => {
			mPopup.Close();
		});
		layout.AddChild(closeBtn);
	}

	/// Show the popup with owned units to pick from.
	public void Show(GUIContext context, int32 itemId, StringView title, PlayerSaveData save, ConfigDatabase configs)
	{
		mItemId = itemId;
		mTitleLabel.Text = title;
		mUnitListPanel.ClearChildren();

		for (let owned in save.mOwnedUnits)
		{
			let config = configs.GetUnit(owned.mUnitId);
			if (config == null) continue;

			let unitId = owned.mUnitId;

			let row = new Border();
			row.Background = Color(28, 32, 48, 255);
			row.Padding = Thickness(10, 6, 10, 6);
			row.HorizontalAlignment = .Stretch;

			let content = new StackPanel();
			content.Orientation = .Horizontal;
			content.Spacing = 10;
			content.VerticalAlignment = .Center;
			content.IsHitTestVisible = false;
			row.Child = content;

			// Stars
			let starStr = scope String();
			starStr.AppendF("{}*", owned.mStarLevel);
			let starLabel = new TextBlock(starStr);
			starLabel.Foreground = Color(255, 215, 80);
			starLabel.FontSize = 12;
			starLabel.IsHitTestVisible = false;
			content.AddChild(starLabel);

			// Name + level
			let nameStr = scope String();
			nameStr.AppendF("{} Lv.{}", config.mName, owned.mLevel);
			let nameLabel = new TextBlock(nameStr);
			nameLabel.Foreground = Color(220, 220, 230);
			nameLabel.FontSize = 14;
			nameLabel.IsHitTestVisible = false;
			content.AddChild(nameLabel);

			// Click overlay
			let clickBtn = new Button();
			clickBtn.Background = Color(0, 0, 0, 0);
			clickBtn.HorizontalAlignment = .Stretch;
			clickBtn.VerticalAlignment = .Stretch;
			clickBtn.Padding = Thickness(0);
			clickBtn.Click.Subscribe(new (btn) => {
				mOnUnitSelected.[Friend]Invoke(unitId);
				mPopup.Close();
			});

			let wrapper = new Grid();
			wrapper.HorizontalAlignment = .Stretch;
			wrapper.RowDefinitions.Add(new .() { Height = .Auto });
			wrapper.ColumnDefinitions.Add(new .() { Width = .Star });
			wrapper.AddChild(row);
			wrapper.AddChild(clickBtn);

			mUnitListPanel.AddChild(wrapper);
		}

		let x = (context.ViewportWidth - 320) / 2;
		let y = (context.ViewportHeight - 380) / 2;
		mPopup.OpenAt(context, x, y);
	}

	public void Hide()
	{
		mPopup.Close();
	}
}

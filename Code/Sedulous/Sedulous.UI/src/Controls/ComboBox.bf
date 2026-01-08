using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Represents an item in a ComboBox.
class ComboBoxItem
{
	private String mText ~ delete _;
	private Object mData;
	private bool mIsEnabled = true;

	/// Gets or sets the display text.
	public StringView Text
	{
		get => mText ?? "";
		set => String.NewOrSet!(mText, value);
	}

	/// Gets or sets the associated data.
	public Object Data
	{
		get => mData;
		set => mData = value;
	}

	/// Gets or sets whether the item is enabled.
	public bool IsEnabled
	{
		get => mIsEnabled;
		set => mIsEnabled = value;
	}

	/// Creates a combo box item with text.
	public this(StringView text)
	{
		mText = new String(text);
	}

	/// Creates a combo box item with text and data.
	public this(StringView text, Object data) : this(text)
	{
		mData = data;
	}
}

/// A dropdown control for selecting from a list of items.
class ComboBox : Widget
{
	private List<ComboBoxItem> mItems = new .() ~ DeleteContainerAndItems!(_);
	private int32 mSelectedIndex = -1;
	private bool mIsDropDownOpen = false;
	private int32 mHoveredIndex = -1;
	private float mDropDownMaxHeight = 200;

	// Visual properties
	private Color mBackgroundColor = Color(50, 50, 50, 255);
	private Color mHoverBackgroundColor = Color(60, 60, 60, 255);
	private Color mDropDownBackground = Color(45, 45, 45, 255);
	private Color mItemHoverBackground = Color(70, 100, 150, 255);
	private Color mItemSelectedBackground = Color(60, 90, 140, 255);
	private Color mTextColor = .White;
	private Color mDisabledTextColor = Color(128, 128, 128, 255);
	private Color mBorderColor = Color(80, 80, 80, 255);
	private Color mArrowColor = Color(180, 180, 180, 255);
	private float mBorderWidth = 1;
	private CornerRadius mCornerRadius = .Uniform(4);
	private FontHandle mFont;
	private float mFontSize = 13;
	private float mItemHeight = 24;
	private Thickness mItemPadding = Thickness(8, 4, 8, 4);

	// State
	private bool mIsHovered;
	private bool mIsPressed;

	/// Event raised when selection changes.
	public Event<delegate void(int32 oldIndex, int32 newIndex)> OnSelectionChanged ~ _.Dispose();

	/// Event raised when dropdown opens or closes.
	public Event<delegate void(bool isOpen)> OnDropDownStateChanged ~ _.Dispose();

	/// Gets the items collection.
	public List<ComboBoxItem> Items => mItems;

	/// Gets or sets the selected index.
	public int32 SelectedIndex
	{
		get => mSelectedIndex;
		set
		{
			let newIndex = Math.Clamp(value, -1, (int32)mItems.Count - 1);
			if (mSelectedIndex != newIndex)
			{
				let oldIndex = mSelectedIndex;
				mSelectedIndex = newIndex;
				OnSelectionChanged(oldIndex, newIndex);
				InvalidateVisual();
			}
		}
	}

	/// Gets the selected item.
	public ComboBoxItem SelectedItem
	{
		get => (mSelectedIndex >= 0 && mSelectedIndex < mItems.Count) ? mItems[mSelectedIndex] : null;
	}

	/// Gets or sets whether the dropdown is open.
	public bool IsDropDownOpen
	{
		get => mIsDropDownOpen;
		set
		{
			if (mIsDropDownOpen != value)
			{
				mIsDropDownOpen = value;
				mHoveredIndex = -1;
				OnDropDownStateChanged(value);
				InvalidateVisual();
			}
		}
	}

	/// Gets or sets the maximum dropdown height.
	public float DropDownMaxHeight
	{
		get => mDropDownMaxHeight;
		set => mDropDownMaxHeight = value;
	}

	/// Gets or sets the font.
	public FontHandle Font
	{
		get => mFont;
		set => mFont = value;
	}

	/// Gets or sets the font size.
	public float FontSize
	{
		get => mFontSize;
		set => mFontSize = value;
	}

	/// Gets or sets the item height.
	public float ItemHeight
	{
		get => mItemHeight;
		set => mItemHeight = value;
	}

	/// Adds an item with text.
	public ComboBoxItem AddItem(StringView text)
	{
		let item = new ComboBoxItem(text);
		mItems.Add(item);

		// Auto-select first item
		if (mSelectedIndex < 0)
			SelectedIndex = 0;

		return item;
	}

	/// Adds an item with text and data.
	public ComboBoxItem AddItem(StringView text, Object data)
	{
		let item = new ComboBoxItem(text, data);
		mItems.Add(item);

		if (mSelectedIndex < 0)
			SelectedIndex = 0;

		return item;
	}

	/// Removes an item by index.
	public void RemoveItem(int32 index)
	{
		if (index < 0 || index >= mItems.Count)
			return;

		let item = mItems[index];
		mItems.RemoveAt(index);
		delete item;

		if (mSelectedIndex >= mItems.Count)
			SelectedIndex = (int32)mItems.Count - 1;

		InvalidateVisual();
	}

	/// Clears all items.
	public void ClearItems()
	{
		for (let item in mItems)
			delete item;
		mItems.Clear();
		mSelectedIndex = -1;
		IsDropDownOpen = false;
		InvalidateVisual();
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		// Base size for the combo box header
		float width = 120; // Default min width
		float height = mItemHeight + mItemPadding.VerticalThickness;

		// Estimate based on items
		for (let item in mItems)
		{
			float itemWidth = item.Text.Length * mFontSize * 0.5f + mItemPadding.HorizontalThickness + 24; // +24 for arrow
			width = Math.Max(width, itemWidth);
		}

		return Vector2(
			width + Padding.HorizontalThickness,
			height + Padding.VerticalThickness
		);
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		// ComboBox doesn't have children to arrange in the normal sense
	}

	protected override void OnRender(DrawContext dc)
	{
		let contentBounds = ContentBounds;

		// Main box background
		Color bgColor = mIsPressed ? mItemSelectedBackground : (mIsHovered ? mHoverBackgroundColor : mBackgroundColor);
		dc.FillRoundedRect(contentBounds, mCornerRadius, bgColor);
		dc.DrawRoundedRect(contentBounds, mCornerRadius, mBorderColor, mBorderWidth);

		// Selected text
		if (SelectedItem != null)
		{
			let textRect = RectangleF(contentBounds.X + mItemPadding.Left, contentBounds.Y, contentBounds.Width - mItemPadding.HorizontalThickness - 20, contentBounds.Height);
			dc.DrawText(SelectedItem.Text, mFont, mFontSize, textRect, mTextColor, .Start, .Center, false);
		}

		// Arrow (draw as small triangle using path)
		let arrowSize = 8f;
		let arrowX = contentBounds.Right - mItemPadding.Right - arrowSize;
		let arrowY = contentBounds.Y + (contentBounds.Height - arrowSize / 2) / 2;

		Vector2[3] arrowPoints;
		if (mIsDropDownOpen)
		{
			// Up arrow
			arrowPoints = .(
				Vector2(arrowX, arrowY + arrowSize / 2),
				Vector2(arrowX + arrowSize, arrowY + arrowSize / 2),
				Vector2(arrowX + arrowSize / 2, arrowY - arrowSize / 4)
			);
		}
		else
		{
			// Down arrow
			arrowPoints = .(
				Vector2(arrowX, arrowY - arrowSize / 4),
				Vector2(arrowX + arrowSize, arrowY - arrowSize / 4),
				Vector2(arrowX + arrowSize / 2, arrowY + arrowSize / 2)
			);
		}
		dc.FillPath(arrowPoints, mArrowColor);

		// Dropdown list
		if (mIsDropDownOpen && mItems.Count > 0)
		{
			let dropdownHeight = Math.Min(mDropDownMaxHeight, mItems.Count * mItemHeight);
			let dropdownRect = RectangleF(
				contentBounds.X,
				contentBounds.Bottom + 2,
				contentBounds.Width,
				dropdownHeight
			);

			// Dropdown background
			dc.FillRoundedRect(dropdownRect, CornerRadius.Uniform(4), mDropDownBackground);
			dc.DrawRoundedRect(dropdownRect, CornerRadius.Uniform(4), mBorderColor, mBorderWidth);

			// Items
			float itemY = dropdownRect.Y;
			for (int32 i = 0; i < mItems.Count; i++)
			{
				if (itemY + mItemHeight > dropdownRect.Bottom)
					break;

				let item = mItems[i];
				let itemRect = RectangleF(dropdownRect.X, itemY, dropdownRect.Width, mItemHeight);

				// Item background
				if (i == mHoveredIndex)
					dc.FillRect(itemRect, mItemHoverBackground);
				else if (i == mSelectedIndex)
					dc.FillRect(itemRect, mItemSelectedBackground);

				// Item text
				let textRect = RectangleF(itemRect.X + mItemPadding.Left, itemRect.Y, itemRect.Width - mItemPadding.HorizontalThickness, itemRect.Height);
				let textColor = item.IsEnabled ? mTextColor : mDisabledTextColor;
				dc.DrawText(item.Text, mFont, mFontSize, textRect, textColor, .Start, .Center, false);

				itemY += mItemHeight;
			}
		}
	}

	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		let contentBounds = ContentBounds;

		// Check if over main box
		bool wasHovered = mIsHovered;
		mIsHovered = contentBounds.Contains(e.Position);

		// Check dropdown hover
		if (mIsDropDownOpen)
		{
			let dropdownHeight = Math.Min(mDropDownMaxHeight, mItems.Count * mItemHeight);
			let dropdownRect = RectangleF(contentBounds.X, contentBounds.Bottom + 2, contentBounds.Width, dropdownHeight);

			if (dropdownRect.Contains(e.Position))
			{
				let relativeY = e.Position.Y - dropdownRect.Y;
				let newHovered = (int32)(relativeY / mItemHeight);
				if (newHovered >= 0 && newHovered < mItems.Count && mHoveredIndex != newHovered)
				{
					mHoveredIndex = newHovered;
					InvalidateVisual();
				}
			}
			else if (mHoveredIndex != -1)
			{
				mHoveredIndex = -1;
				InvalidateVisual();
			}
		}

		if (wasHovered != mIsHovered)
			InvalidateVisual();

		return true;
	}

	protected override bool OnMouseLeave(MouseEventArgs e)
	{
		mIsHovered = false;
		if (!mIsDropDownOpen)
		{
			mHoveredIndex = -1;
		}
		InvalidateVisual();
		return false;
	}

	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return false;

		let contentBounds = ContentBounds;

		// Click on main box
		if (contentBounds.Contains(e.Position))
		{
			mIsPressed = true;
			IsDropDownOpen = !mIsDropDownOpen;
			return true;
		}

		// Click on dropdown item
		if (mIsDropDownOpen)
		{
			let dropdownHeight = Math.Min(mDropDownMaxHeight, mItems.Count * mItemHeight);
			let dropdownRect = RectangleF(contentBounds.X, contentBounds.Bottom + 2, contentBounds.Width, dropdownHeight);

			if (dropdownRect.Contains(e.Position))
			{
				if (mHoveredIndex >= 0 && mHoveredIndex < mItems.Count)
				{
					let item = mItems[mHoveredIndex];
					if (item.IsEnabled)
					{
						SelectedIndex = mHoveredIndex;
						IsDropDownOpen = false;
					}
				}
				return true;
			}
			else
			{
				// Click outside - close dropdown
				IsDropDownOpen = false;
			}
		}

		return false;
	}

	protected override bool OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Left)
		{
			mIsPressed = false;
			InvalidateVisual();
		}
		return true;
	}

	protected override bool OnKeyDown(KeyEventArgs e)
	{
		if (!mIsDropDownOpen)
		{
			if (e.Key == .Space || e.Key == .Enter)
			{
				IsDropDownOpen = true;
				return true;
			}
		}
		else
		{
			switch (e.Key)
			{
			case .Escape:
				IsDropDownOpen = false;
				return true;
			case .Enter, .Space:
				if (mHoveredIndex >= 0)
					SelectedIndex = mHoveredIndex;
				IsDropDownOpen = false;
				return true;
			case .Up:
				if (mHoveredIndex > 0)
				{
					mHoveredIndex--;
					InvalidateVisual();
				}
				return true;
			case .Down:
				if (mHoveredIndex < mItems.Count - 1)
				{
					mHoveredIndex++;
					InvalidateVisual();
				}
				return true;
			default:
			}
		}

		// Arrow keys to change selection when closed
		if (!mIsDropDownOpen)
		{
			if (e.Key == .Up && mSelectedIndex > 0)
			{
				SelectedIndex--;
				return true;
			}
			if (e.Key == .Down && mSelectedIndex < mItems.Count - 1)
			{
				SelectedIndex++;
				return true;
			}
		}

		return false;
	}
}

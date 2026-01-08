using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Represents an item in a ListBox.
class ListBoxItem
{
	private String mText ~ delete _;
	private Object mData;
	private bool mIsEnabled = true;
	private bool mIsSelected = false;
	private TextureHandle mIcon;

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

	/// Gets or sets whether the item is selected.
	public bool IsSelected
	{
		get => mIsSelected;
		set => mIsSelected = value;
	}

	/// Gets or sets the icon texture.
	public TextureHandle Icon
	{
		get => mIcon;
		set => mIcon = value;
	}

	/// Creates a list box item with text.
	public this(StringView text)
	{
		mText = new String(text);
	}

	/// Creates a list box item with text and data.
	public this(StringView text, Object data) : this(text)
	{
		mData = data;
	}
}

/// A scrollable list of selectable items.
class ListBox : Widget
{
	private List<ListBoxItem> mItems = new .() ~ DeleteContainerAndItems!(_);
	private SelectionMode mSelectionMode = .Single;
	private int32 mSelectedIndex = -1;
	private List<int32> mSelectedIndices = new .() ~ delete _;
	private int32 mHoveredIndex = -1;

	// Visual properties
	private Color mBackgroundColor = Color(45, 45, 45, 255);
	private Color mItemHoverBackground = Color(60, 60, 60, 255);
	private Color mItemSelectedBackground = Color(70, 100, 150, 255);
	private Color mTextColor = .White;
	private Color mDisabledTextColor = Color(128, 128, 128, 255);
	private Color mBorderColor = Color(70, 70, 70, 255);
	private float mBorderWidth = 1;
	private FontHandle mFont;
	private float mFontSize = 13;
	private float mItemHeight = 24;
	private float mIconSize = 16;
	private Thickness mItemPadding = Thickness(8, 4, 8, 4);

	// Scroll state
	private float mScrollOffset = 0;

	/// Event raised when selection changes.
	public Event<delegate void()> OnSelectionChanged ~ _.Dispose();

	/// Event raised when an item is double-clicked.
	public Event<delegate void(int32 index)> OnItemDoubleClick ~ _.Dispose();

	/// Gets the items collection.
	public List<ListBoxItem> Items => mItems;

	/// Gets or sets the selection mode.
	public SelectionMode SelectionMode
	{
		get => mSelectionMode;
		set
		{
			if (mSelectionMode != value)
			{
				mSelectionMode = value;
				ClearSelection();
			}
		}
	}

	/// Gets or sets the selected index (for single selection mode).
	public int32 SelectedIndex
	{
		get => mSelectedIndex;
		set
		{
			if (mSelectionMode == .None)
				return;

			let newIndex = Math.Clamp(value, -1, (int32)mItems.Count - 1);
			if (mSelectedIndex != newIndex)
			{
				// Clear previous selection
				if (mSelectedIndex >= 0 && mSelectedIndex < mItems.Count)
					mItems[mSelectedIndex].IsSelected = false;

				mSelectedIndex = newIndex;
				mSelectedIndices.Clear();

				// Set new selection
				if (mSelectedIndex >= 0 && mSelectedIndex < mItems.Count)
				{
					mItems[mSelectedIndex].IsSelected = true;
					mSelectedIndices.Add(mSelectedIndex);
				}

				OnSelectionChanged();
				InvalidateVisual();
			}
		}
	}

	/// Gets the selected item (for single selection mode).
	public ListBoxItem SelectedItem
	{
		get => (mSelectedIndex >= 0 && mSelectedIndex < mItems.Count) ? mItems[mSelectedIndex] : null;
	}

	/// Gets the selected indices (for multiple selection mode).
	public List<int32> SelectedIndices => mSelectedIndices;

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
		set { mItemHeight = value; InvalidateMeasure(); }
	}

	/// Gets or sets the scroll offset.
	public float ScrollOffset
	{
		get => mScrollOffset;
		set
		{
			let maxScroll = Math.Max(0, mItems.Count * mItemHeight - (Bounds.Height - Padding.VerticalThickness));
			let newOffset = Math.Clamp(value, 0, maxScroll);
			if (mScrollOffset != newOffset)
			{
				mScrollOffset = newOffset;
				InvalidateVisual();
			}
		}
	}

	/// Adds an item with text.
	public ListBoxItem AddItem(StringView text)
	{
		let item = new ListBoxItem(text);
		mItems.Add(item);
		InvalidateMeasure();
		return item;
	}

	/// Adds an item with text and data.
	public ListBoxItem AddItem(StringView text, Object data)
	{
		let item = new ListBoxItem(text, data);
		mItems.Add(item);
		InvalidateMeasure();
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

		// Update selection
		mSelectedIndices.Remove(index);
		for (int32 i = 0; i < mSelectedIndices.Count; i++)
		{
			if (mSelectedIndices[i] > index)
				mSelectedIndices[i]--;
		}

		if (mSelectedIndex >= mItems.Count)
			mSelectedIndex = (int32)mItems.Count - 1;

		InvalidateMeasure();
	}

	/// Clears all items.
	public void ClearItems()
	{
		for (let item in mItems)
			delete item;
		mItems.Clear();
		ClearSelection();
		InvalidateMeasure();
	}

	/// Clears the selection.
	public void ClearSelection()
	{
		for (let item in mItems)
			item.IsSelected = false;
		mSelectedIndex = -1;
		mSelectedIndices.Clear();
		OnSelectionChanged();
		InvalidateVisual();
	}

	/// Selects all items (for multiple selection mode).
	public void SelectAll()
	{
		if (mSelectionMode != .Multiple && mSelectionMode != .Extended)
			return;

		mSelectedIndices.Clear();
		for (int32 i = 0; i < mItems.Count; i++)
		{
			mItems[i].IsSelected = true;
			mSelectedIndices.Add(i);
		}

		if (mItems.Count > 0)
			mSelectedIndex = 0;

		OnSelectionChanged();
		InvalidateVisual();
	}

	/// Scrolls to make an item visible.
	public void ScrollIntoView(int32 index)
	{
		if (index < 0 || index >= mItems.Count)
			return;

		let itemTop = index * mItemHeight;
		let itemBottom = itemTop + mItemHeight;
		let viewportHeight = Bounds.Height - Padding.VerticalThickness;

		if (itemTop < mScrollOffset)
			ScrollOffset = itemTop;
		else if (itemBottom > mScrollOffset + viewportHeight)
			ScrollOffset = itemBottom - viewportHeight;
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		float width = 120; // Min width

		// Estimate based on items (approximate)
		for (let item in mItems)
		{
			float itemWidth = item.Text.Length * mFontSize * 0.5f + mItemPadding.HorizontalThickness;
			if (item.Icon.Value != 0)
				itemWidth += mIconSize + 4;
			width = Math.Max(width, itemWidth);
		}

		let height = mItems.Count * mItemHeight;

		return Vector2(
			width + Padding.HorizontalThickness,
			height + Padding.VerticalThickness
		);
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		// ListBox handles its own layout in OnRender
	}

	protected override void OnRender(DrawContext dc)
	{
		let contentBounds = ContentBounds;

		// Background
		dc.FillRect(contentBounds, mBackgroundColor);
		dc.DrawRect(contentBounds, mBorderColor, mBorderWidth);

		// Render visible items
		int32 firstVisible = (int32)(mScrollOffset / mItemHeight);
		int32 visibleCount = (int32)Math.Ceiling(contentBounds.Height / mItemHeight) + 1;

		for (int32 i = firstVisible; i < firstVisible + visibleCount && i < mItems.Count; i++)
		{
			let item = mItems[i];
			let y = contentBounds.Y + i * mItemHeight - mScrollOffset;
			let itemRect = RectangleF(contentBounds.X, y, contentBounds.Width, mItemHeight);

			// Skip if not visible
			if (y + mItemHeight < contentBounds.Y || y > contentBounds.Bottom)
				continue;

			// Selection/hover background
			if (item.IsSelected)
				dc.FillRect(itemRect, mItemSelectedBackground);
			else if (i == mHoveredIndex)
				dc.FillRect(itemRect, mItemHoverBackground);

			// Icon
			float textX = itemRect.X + mItemPadding.Left;
			if (item.Icon.Value != 0)
			{
				let iconY = itemRect.Y + (itemRect.Height - mIconSize) / 2;
				dc.DrawImage(item.Icon, RectangleF(textX, iconY, mIconSize, mIconSize), Color.White);
				textX += mIconSize + 4;
			}

			// Text
			let textRect = RectangleF(textX, itemRect.Y, itemRect.Width - (textX - itemRect.X) - mItemPadding.Right, itemRect.Height);
			let textColor = item.IsEnabled ? mTextColor : mDisabledTextColor;
			dc.DrawText(item.Text, mFont, mFontSize, textRect, textColor, .Start, .Center, false);
		}
	}

	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		let contentBounds = ContentBounds;
		if (!contentBounds.Contains(e.Position))
		{
			if (mHoveredIndex != -1)
			{
				mHoveredIndex = -1;
				InvalidateVisual();
			}
			return false;
		}

		let relativeY = e.Position.Y - contentBounds.Y + mScrollOffset;
		var newHovered = (int32)(relativeY / mItemHeight);

		if (newHovered < 0 || newHovered >= mItems.Count)
			newHovered = -1;

		if (mHoveredIndex != newHovered)
		{
			mHoveredIndex = newHovered;
			InvalidateVisual();
		}

		return true;
	}

	protected override bool OnMouseLeave(MouseEventArgs e)
	{
		if (mHoveredIndex != -1)
		{
			mHoveredIndex = -1;
			InvalidateVisual();
		}
		return false;
	}

	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return false;

		if (mHoveredIndex < 0 || mHoveredIndex >= mItems.Count)
			return false;

		let item = mItems[mHoveredIndex];
		if (!item.IsEnabled)
			return false;

		switch (mSelectionMode)
		{
		case .None:
			return false;

		case .Single:
			SelectedIndex = mHoveredIndex;

		case .Multiple:
			// Toggle selection
			item.IsSelected = !item.IsSelected;
			if (item.IsSelected)
			{
				if (!mSelectedIndices.Contains(mHoveredIndex))
					mSelectedIndices.Add(mHoveredIndex);
			}
			else
			{
				mSelectedIndices.Remove(mHoveredIndex);
			}
			mSelectedIndex = mSelectedIndices.Count > 0 ? mSelectedIndices[mSelectedIndices.Count - 1] : -1;
			OnSelectionChanged();
			InvalidateVisual();

		case .Extended:
			if (e.Modifiers.HasFlag(.Control))
			{
				// Toggle selection
				item.IsSelected = !item.IsSelected;
				if (item.IsSelected)
				{
					if (!mSelectedIndices.Contains(mHoveredIndex))
						mSelectedIndices.Add(mHoveredIndex);
				}
				else
				{
					mSelectedIndices.Remove(mHoveredIndex);
				}
			}
			else if (e.Modifiers.HasFlag(.Shift) && mSelectedIndex >= 0)
			{
				// Range selection
				int32 start = Math.Min(mSelectedIndex, mHoveredIndex);
				int32 end = Math.Max(mSelectedIndex, mHoveredIndex);

				for (int32 i = 0; i < mItems.Count; i++)
				{
					let isInRange = i >= start && i <= end;
					mItems[i].IsSelected = isInRange;
					if (isInRange && !mSelectedIndices.Contains(i))
						mSelectedIndices.Add(i);
					else if (!isInRange)
						mSelectedIndices.Remove(i);
				}
			}
			else
			{
				// Single selection (clear others)
				for (let it in mItems)
					it.IsSelected = false;
				mSelectedIndices.Clear();

				item.IsSelected = true;
				mSelectedIndices.Add(mHoveredIndex);
			}
			mSelectedIndex = mHoveredIndex;
			OnSelectionChanged();
			InvalidateVisual();
		}

		return true;
	}

	protected override bool OnMouseWheel(MouseWheelEventArgs e)
	{
		ScrollOffset -= e.DeltaY * mItemHeight * 3;
		return true;
	}

	protected override bool OnKeyDown(KeyEventArgs e)
	{
		switch (e.Key)
		{
		case .Up:
			if (mSelectedIndex > 0)
			{
				SelectedIndex--;
				ScrollIntoView(mSelectedIndex);
			}
			return true;

		case .Down:
			if (mSelectedIndex < mItems.Count - 1)
			{
				SelectedIndex++;
				ScrollIntoView(mSelectedIndex);
			}
			return true;

		case .Home:
			if (mItems.Count > 0)
			{
				SelectedIndex = 0;
				ScrollIntoView(0);
			}
			return true;

		case .End:
			if (mItems.Count > 0)
			{
				SelectedIndex = (int32)mItems.Count - 1;
				ScrollIntoView(mSelectedIndex);
			}
			return true;

		case .PageUp:
			{
				let visibleCount = (int32)(Bounds.Height / mItemHeight);
				SelectedIndex = Math.Max(0, mSelectedIndex - visibleCount);
				ScrollIntoView(mSelectedIndex);
			}
			return true;

		case .PageDown:
			{
				let visibleCount = (int32)(Bounds.Height / mItemHeight);
				SelectedIndex = Math.Min((int32)mItems.Count - 1, mSelectedIndex + visibleCount);
				ScrollIntoView(mSelectedIndex);
			}
			return true;

		case .Space, .Enter:
			if (mSelectedIndex >= 0)
				OnItemDoubleClick(mSelectedIndex);
			return true;

		case .A:
			if (e.Modifiers.HasFlag(.Control) && (mSelectionMode == .Multiple || mSelectionMode == .Extended))
			{
				SelectAll();
				return true;
			}
		default:
		}

		return false;
	}
}

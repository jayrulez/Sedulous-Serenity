using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// Selection mode for ListBox.
public enum SelectionMode
{
	/// No selection allowed.
	None,
	/// Only one item can be selected at a time.
	Single,
	/// Multiple items can be selected by clicking.
	Multiple,
	/// Multiple items can be selected using Ctrl+Click and Shift+Click.
	Extended
}

/// A scrollable list of selectable items.
public class ListBox : Control, IVisualChildProvider
{
	private ScrollViewer mScrollViewer ~ delete _; // Owned as child
	private StackPanel mItemsPanel ~ { }; // Owned by scroll viewer
	private List<ListBoxItem> mItems = new .() ~ delete _; // List owns nothing, items are children of mItemsPanel
	private List<ListBoxItem> mSelectedItems = new .() ~ delete _; // Just references, no ownership
	private int mSelectedIndex = -1;
	private int mAnchorIndex = -1; // For shift+click selection
	private float mItemHeight = 24;

	// Events
	private EventAccessor<delegate void(ListBox, int, int)> mSelectionChangedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(ListBox, ListBoxItem)> mItemDoubleClickEvent = new .() ~ delete _;

	/// The items in this list box.
	public List<ListBoxItem> Items => mItems;

	/// The currently selected item index (-1 if none).
	public int SelectedIndex
	{
		get => mSelectedIndex;
		set
		{
			var value;
			if (value < -1 || value >= mItems.Count)
				value = -1;

			if (mSelectedIndex != value)
			{
				let oldIndex = mSelectedIndex;
				SetSelectedIndex(value);
				mSelectionChangedEvent.[Friend]Invoke(this, oldIndex, mSelectedIndex);
			}
		}
	}

	/// The currently selected item (null if none).
	public ListBoxItem SelectedItem
	{
		get => mSelectedIndex >= 0 && mSelectedIndex < mItems.Count ? mItems[mSelectedIndex] : null;
		set
		{
			if (value == null)
				SelectedIndex = -1;
			else
				SelectedIndex = mItems.IndexOf(value);
		}
	}

	/// All currently selected items (for multi-select modes).
	public List<ListBoxItem> SelectedItems => mSelectedItems;

	/// The selection mode.
	public SelectionMode SelectionMode { get; set; } = .Single;

	/// Fixed height for each item.
	public float ItemHeight
	{
		get => mItemHeight;
		set
		{
			if (mItemHeight != value)
			{
				mItemHeight = Math.Max(16, value);
				for (let item in mItems)
					item.Height = .Fixed(mItemHeight);
				InvalidateMeasure();
			}
		}
	}

	/// Fired when selection changes.
	public EventAccessor<delegate void(ListBox, int, int)> SelectionChanged => mSelectionChangedEvent;

	/// Fired when an item is double-clicked.
	public EventAccessor<delegate void(ListBox, ListBoxItem)> ItemDoubleClick => mItemDoubleClickEvent;

	public this()
	{
		Focusable = true;
		BorderThickness = Thickness(1);

		// Create internal scroll viewer and items panel
		mScrollViewer = new ScrollViewer();
		mScrollViewer.HorizontalScrollBarVisibility = .Disabled;
		mScrollViewer.VerticalScrollBarVisibility = .Auto;
		mScrollViewer.[Friend]mParent = this;

		mItemsPanel = new StackPanel();
		mItemsPanel.Orientation = .Vertical;
		mItemsPanel.Spacing = 0;
		mScrollViewer.Content = mItemsPanel;
	}

	/// Adds an item to the list.
	public void AddItem(ListBoxItem item)
	{
		item.Height = .Fixed(mItemHeight);
		mItems.Add(item);
		mItemsPanel.AddChild(item);
		InvalidateMeasure();
	}

	/// Adds a text item to the list.
	public ListBoxItem AddItem(StringView text)
	{
		let item = new ListBoxItem(text);
		AddItem(item);
		return item;
	}

	/// Removes an item from the list.
	public void RemoveItem(ListBoxItem item)
	{
		let index = mItems.IndexOf(item);
		if (index >= 0)
		{
			// Update selection
			if (item.IsSelected)
			{
				item.IsSelected = false;
				mSelectedItems.Remove(item);
			}

			mItems.RemoveAt(index);
			mItemsPanel.RemoveChild(item);

			// Adjust selected index if needed
			if (mSelectedIndex >= mItems.Count)
				mSelectedIndex = mItems.Count - 1;

			InvalidateMeasure();
		}
	}

	/// Removes all items from the list.
	public void ClearItems()
	{
		mSelectedItems.Clear();
		mSelectedIndex = -1;
		mAnchorIndex = -1;

		for (let item in mItems)
			item.IsSelected = false;

		mItems.Clear();
		mItemsPanel.ClearChildren();
		InvalidateMeasure();
	}

	/// Scrolls to make the specified item visible.
	public void ScrollIntoView(ListBoxItem item)
	{
		if (item != null)
			mScrollViewer.ScrollIntoView(item);
	}

	private void SetSelectedIndex(int index)
	{
		// Clear old selection in single mode
		if (SelectionMode == .Single || SelectionMode == .None)
		{
			for (let item in mSelectedItems)
				item.IsSelected = false;
			mSelectedItems.Clear();
		}

		mSelectedIndex = index;

		// Set new selection
		if (mSelectedIndex >= 0 && mSelectedIndex < mItems.Count && SelectionMode != .None)
		{
			let item = mItems[mSelectedIndex];
			if (!item.IsSelected)
			{
				item.IsSelected = true;
				if (!mSelectedItems.Contains(item))
					mSelectedItems.Add(item);
			}
			mAnchorIndex = mSelectedIndex;
		}

		InvalidateVisual();
	}

	private void SelectRange(int fromIndex, int toIndex)
	{
		let start = Math.Min(fromIndex, toIndex);
		let end = Math.Max(fromIndex, toIndex);

		for (int i = start; i <= end; i++)
		{
			if (i >= 0 && i < mItems.Count)
			{
				let item = mItems[i];
				if (!item.IsSelected)
				{
					item.IsSelected = true;
					mSelectedItems.Add(item);
				}
			}
		}

		InvalidateVisual();
	}

	private void ToggleSelection(int index)
	{
		if (index < 0 || index >= mItems.Count)
			return;

		let item = mItems[index];
		item.IsSelected = !item.IsSelected;

		if (item.IsSelected)
		{
			if (!mSelectedItems.Contains(item))
				mSelectedItems.Add(item);
			mSelectedIndex = index;
		}
		else
		{
			mSelectedItems.Remove(item);
			// Update selected index to first selected item
			mSelectedIndex = -1;
			for (int i < mItems.Count)
			{
				if (mItems[i].IsSelected)
				{
					mSelectedIndex = i;
					break;
				}
			}
		}

		mAnchorIndex = index;
		InvalidateVisual();
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		mScrollViewer.Measure(constraints);
		return mScrollViewer.DesiredSize;
	}

	protected override void ArrangeContent(RectangleF contentBounds)
	{
		mScrollViewer.Arrange(contentBounds);
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		// Background
		let bg = Background ?? theme?.GetColor("Background") ?? Color.White;
		drawContext.FillRect(bounds, bg);

		// Border
		let borderColor = IsFocused
			? (theme?.GetColor("BorderFocused") ?? Color(0, 120, 215))
			: (BorderBrush ?? theme?.GetColor("Border") ?? Color(204, 204, 204));

		let bt = BorderThickness;
		if (bt.Top > 0)
			drawContext.FillRect(.(bounds.X, bounds.Y, bounds.Width, bt.Top), borderColor);
		if (bt.Bottom > 0)
			drawContext.FillRect(.(bounds.X, bounds.Bottom - bt.Bottom, bounds.Width, bt.Bottom), borderColor);
		if (bt.Left > 0)
			drawContext.FillRect(.(bounds.X, bounds.Y + bt.Top, bt.Left, bounds.Height - bt.TotalVertical), borderColor);
		if (bt.Right > 0)
			drawContext.FillRect(.(bounds.Right - bt.Right, bounds.Y + bt.Top, bt.Right, bounds.Height - bt.TotalVertical), borderColor);

		// Render scroll viewer and items
		RenderContent(drawContext);
	}

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		base.OnMouseDownRouted(args);

		if (args.Button == .Left && SelectionMode != .None)
		{
			// Find which item was clicked
			// LocalY is relative to ListBox, add scroll offset to get content position
			let contentY = args.LocalY + mScrollViewer.VerticalOffset;
			let clickedIndex = (int)(contentY / mItemHeight);

			if (clickedIndex >= 0 && clickedIndex < mItems.Count)
			{
				let oldIndex = mSelectedIndex;

				switch (SelectionMode)
				{
				case .Single:
					SetSelectedIndex(clickedIndex);

				case .Multiple:
					ToggleSelection(clickedIndex);

				case .Extended:
					if (args.HasModifier(.Shift) && mAnchorIndex >= 0)
					{
						// Shift+click: select range
						// First clear non-anchor selection
						for (let item in mSelectedItems)
							item.IsSelected = false;
						mSelectedItems.Clear();

						SelectRange(mAnchorIndex, clickedIndex);
						mSelectedIndex = clickedIndex;
					}
					else if (args.HasModifier(.Ctrl))
					{
						// Ctrl+click: toggle
						ToggleSelection(clickedIndex);
					}
					else
					{
						// Normal click: single select
						for (let item in mSelectedItems)
							item.IsSelected = false;
						mSelectedItems.Clear();

						SetSelectedIndex(clickedIndex);
					}

				case .None:
				}

				if (mSelectedIndex != oldIndex)
					mSelectionChangedEvent.[Friend]Invoke(this, oldIndex, mSelectedIndex);

				// Focus the listbox
				Context?.SetFocus(this);
				args.Handled = true;
			}
		}
	}

	protected override void OnKeyDownRouted(KeyEventArgs args)
	{
		base.OnKeyDownRouted(args);

		if (SelectionMode == .None || mItems.Count == 0)
			return;

		var handled = false;
		let oldIndex = mSelectedIndex;
		var newIndex = mSelectedIndex;

		switch (args.Key)
		{
		case .Up:
			newIndex = Math.Max(0, mSelectedIndex - 1);
			handled = true;

		case .Down:
			newIndex = Math.Min(mItems.Count - 1, mSelectedIndex + 1);
			handled = true;

		case .Home:
			newIndex = 0;
			handled = true;

		case .End:
			newIndex = mItems.Count - 1;
			handled = true;

		case .PageUp:
			let visibleCount = (int)(Bounds.Height / mItemHeight);
			newIndex = Math.Max(0, mSelectedIndex - visibleCount);
			handled = true;

		case .PageDown:
			let visibleCount = (int)(Bounds.Height / mItemHeight);
			newIndex = Math.Min(mItems.Count - 1, mSelectedIndex + visibleCount);
			handled = true;

		case .Space:
			if (SelectionMode == .Multiple || SelectionMode == .Extended)
			{
				if (mSelectedIndex >= 0)
					ToggleSelection(mSelectedIndex);
				handled = true;
			}

		default:
		}

		if (handled && newIndex != oldIndex && newIndex >= 0)
		{
			if (SelectionMode == .Extended && args.HasModifier(.Shift) && mAnchorIndex >= 0)
			{
				// Extend selection with shift
				for (let item in mSelectedItems)
					item.IsSelected = false;
				mSelectedItems.Clear();

				SelectRange(mAnchorIndex, newIndex);
				mSelectedIndex = newIndex;
			}
			else if (SelectionMode == .Extended)
			{
				// Extended mode without Shift: clear selection and select only new item
				for (let item in mSelectedItems)
					item.IsSelected = false;
				mSelectedItems.Clear();
				SetSelectedIndex(newIndex);
			}
			else if (SelectionMode != .Multiple)
			{
				SetSelectedIndex(newIndex);
			}
			else
			{
				mSelectedIndex = newIndex;
			}

			if (mSelectedIndex != oldIndex)
				mSelectionChangedEvent.[Friend]Invoke(this, oldIndex, mSelectedIndex);

			// Scroll to show selection
			if (mSelectedIndex >= 0)
				ScrollIntoView(mItems[mSelectedIndex]);

			args.Handled = true;
		}
		else if (handled)
		{
			args.Handled = true;
		}
	}

	protected override void OnGotFocus()
	{
		base.OnGotFocus();
		InvalidateVisual();
	}

	protected override void OnLostFocus()
	{
		base.OnLostFocus();
		InvalidateVisual();
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		mScrollViewer.Render(drawContext);
	}

	/// Override HitTest to check scroll viewer.
	public override UIElement HitTest(float x, float y)
	{
		if (Visibility != .Visible)
			return null;

		if (!Bounds.Contains(x, y))
			return null;

		// Check scroll viewer
		let result = mScrollViewer.HitTest(x, y);
		if (result != null)
			return result;

		return this;
	}

	/// Override FindElementById to search scroll viewer.
	public override UIElement FindElementById(UIElementId id)
	{
		if (Id == id)
			return this;

		let result = mScrollViewer.FindElementById(id);
		if (result != null)
			return result;

		return null;
	}

	// === IVisualChildProvider ===

	/// Visits all visual children of this element.
	public void VisitVisualChildren(delegate void(UIElement) visitor)
	{
		if (mScrollViewer != null)
			visitor(mScrollViewer);
	}
}

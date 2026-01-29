using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// A grid view of items displayed as tiles with icons and labels.
public class TileView : Control, IVisualChildProvider
{
	private ScrollViewer mScrollViewer ~ delete _;
	private WrapPanel mItemsPanel ~ { }; // Owned by scroll viewer
	private List<TileViewItem> mItems = new .() ~ delete _; // References, items owned by panel
	private List<TileViewItem> mSelectedItems = new .() ~ delete _; // Just references
	private TileViewItem mSelectedItem;
	private float mTileWidth = 80;
	private float mTileHeight = 90;
	private float mTileSpacing = 8;

	// Events
	private EventAccessor<delegate void(TileView, TileViewItem)> mSelectionChangedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(TileView, TileViewItem)> mItemDoubleClickEvent = new .() ~ delete _;

	/// The items in this tile view.
	public List<TileViewItem> Items => mItems;

	/// The currently selected item (null if none).
	public TileViewItem SelectedItem
	{
		get => mSelectedItem;
		set
		{
			if (mSelectedItem != value)
			{
				// Clear old selection
				if (mSelectedItem != null)
					mSelectedItem.IsSelected = false;
				for (let item in mSelectedItems)
					item.IsSelected = false;
				mSelectedItems.Clear();

				mSelectedItem = value;

				if (mSelectedItem != null)
				{
					mSelectedItem.IsSelected = true;
					mSelectedItems.Add(mSelectedItem);
				}

				mSelectionChangedEvent.[Friend]Invoke(this, mSelectedItem);
				InvalidateVisual();
			}
		}
	}

	/// All currently selected items (for multi-select).
	public List<TileViewItem> SelectedItems => mSelectedItems;

	/// The selection mode.
	public SelectionMode SelectionMode { get; set; } = .Single;

	/// Width of each tile.
	public float TileWidth
	{
		get => mTileWidth;
		set
		{
			if (mTileWidth != value)
			{
				mTileWidth = Math.Max(48, value);
				UpdateTileSizes();
				InvalidateMeasure();
			}
		}
	}

	/// Height of each tile.
	public float TileHeight
	{
		get => mTileHeight;
		set
		{
			if (mTileHeight != value)
			{
				mTileHeight = Math.Max(48, value);
				UpdateTileSizes();
				InvalidateMeasure();
			}
		}
	}

	/// Spacing between tiles.
	public float TileSpacing
	{
		get => mTileSpacing;
		set
		{
			if (mTileSpacing != value)
			{
				mTileSpacing = Math.Max(0, value);
				mItemsPanel.HorizontalSpacing = mTileSpacing;
				mItemsPanel.VerticalSpacing = mTileSpacing;
				InvalidateMeasure();
			}
		}
	}

	/// Fired when selection changes.
	public EventAccessor<delegate void(TileView, TileViewItem)> SelectionChanged => mSelectionChangedEvent;

	/// Fired when an item is double-clicked.
	public EventAccessor<delegate void(TileView, TileViewItem)> ItemDoubleClick => mItemDoubleClickEvent;

	public this()
	{
		Focusable = true;
		BorderThickness = Thickness(1);

		// Create internal scroll viewer and items panel
		mScrollViewer = new ScrollViewer();
		mScrollViewer.HorizontalScrollBarVisibility = .Disabled;
		mScrollViewer.VerticalScrollBarVisibility = .Auto;
		mScrollViewer.[Friend]mParent = this;

		mItemsPanel = new WrapPanel();
		mItemsPanel.Orientation = .Horizontal;
		mItemsPanel.HorizontalSpacing = mTileSpacing;
		mItemsPanel.VerticalSpacing = mTileSpacing;
		mScrollViewer.Content = mItemsPanel;
	}

	/// Adds an item to the view.
	public void AddItem(TileViewItem item)
	{
		item.Width = .Fixed(mTileWidth);
		item.Height = .Fixed(mTileHeight);
		mItems.Add(item);
		mItemsPanel.AddChild(item);
		InvalidateMeasure();
	}

	/// Adds an item with text.
	public TileViewItem AddItem(StringView text)
	{
		let item = new TileViewItem(text);
		AddItem(item);
		return item;
	}

	/// Adds an item with text and icon.
	public TileViewItem AddItem(StringView text, IImageData icon)
	{
		let item = new TileViewItem(text, icon);
		AddItem(item);
		return item;
	}

	/// Removes an item from the view.
	public void RemoveItem(TileViewItem item)
	{
		let index = mItems.IndexOf(item);
		if (index >= 0)
		{
			// Update selection
			if (item.IsSelected)
			{
				item.IsSelected = false;
				mSelectedItems.Remove(item);
				if (mSelectedItem == item)
					mSelectedItem = mSelectedItems.Count > 0 ? mSelectedItems[0] : null;
			}

			mItems.RemoveAt(index);
			mItemsPanel.RemoveChild(item);
			InvalidateMeasure();
		}
	}

	/// Clears all items from the view.
	public void ClearItems()
	{
		mSelectedItems.Clear();
		mSelectedItem = null;
		mItems.Clear();
		mItemsPanel.ClearChildren();
		InvalidateMeasure();
	}

	/// Scrolls to make the specified item visible.
	public void ScrollIntoView(TileViewItem item)
	{
		if (item != null)
			mScrollViewer.ScrollIntoView(item);
	}

	private void UpdateTileSizes()
	{
		for (let item in mItems)
		{
			item.Width = .Fixed(mTileWidth);
			item.Height = .Fixed(mTileHeight);
		}
	}

	private void ToggleSelection(TileViewItem item)
	{
		item.IsSelected = !item.IsSelected;

		if (item.IsSelected)
		{
			if (!mSelectedItems.Contains(item))
				mSelectedItems.Add(item);
			mSelectedItem = item;
		}
		else
		{
			mSelectedItems.Remove(item);
			mSelectedItem = mSelectedItems.Count > 0 ? mSelectedItems[0] : null;
		}
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
		let bg = Background ?? theme?.GetColor("TileViewBackground") ?? theme?.GetColor("Background") ?? Color(37, 37, 38);
		drawContext.FillRect(bounds, bg);

		// Border
		let borderColor = IsFocused
			? (theme?.GetColor("BorderFocused") ?? Color(0, 120, 215))
			: (BorderBrush ?? theme?.GetColor("Border") ?? Color(60, 60, 60));

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
			// Find which item was clicked via hit test
			TileViewItem clickedItem = null;
			for (let item in mItems)
			{
				if (item.Bounds.Contains(args.ScreenX, args.ScreenY))
				{
					clickedItem = item;
					break;
				}
			}

			if (clickedItem != null)
			{
				switch (SelectionMode)
				{
				case .Single:
					SelectedItem = clickedItem;

				case .Multiple:
					ToggleSelection(clickedItem);
					mSelectionChangedEvent.[Friend]Invoke(this, mSelectedItem);

				case .Extended:
					if (args.HasModifier(.Ctrl))
					{
						ToggleSelection(clickedItem);
						mSelectionChangedEvent.[Friend]Invoke(this, mSelectedItem);
					}
					else
					{
						// Clear and select single
						for (let item in mSelectedItems)
							item.IsSelected = false;
						mSelectedItems.Clear();
						SelectedItem = clickedItem;
					}

				case .None:
				}

				// Handle double-click
				if (args.ClickCount == 2)
				{
					mItemDoubleClickEvent.[Friend]Invoke(this, clickedItem);
				}

				Context?.SetFocus(this);
				args.Handled = true;
			}
			else
			{
				// Clicked on empty space - clear selection
				if (SelectionMode != .Extended || !args.HasModifier(.Ctrl))
				{
					for (let item in mSelectedItems)
						item.IsSelected = false;
					mSelectedItems.Clear();

					let oldSelected = mSelectedItem;
					mSelectedItem = null;

					if (oldSelected != null)
						mSelectionChangedEvent.[Friend]Invoke(this, null);
				}

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
		let currentIndex = mSelectedItem != null ? mItems.IndexOf(mSelectedItem) : -1;
		var newIndex = currentIndex;

		// Calculate items per row
		let itemsPerRow = Math.Max(1, (int)((ContentBounds.Width + mTileSpacing) / (mTileWidth + mTileSpacing)));

		switch (args.Key)
		{
		case .Left:
			newIndex = Math.Max(0, currentIndex - 1);
			handled = true;

		case .Right:
			newIndex = Math.Min(mItems.Count - 1, currentIndex + 1);
			handled = true;

		case .Up:
			newIndex = Math.Max(0, currentIndex - itemsPerRow);
			handled = true;

		case .Down:
			newIndex = Math.Min(mItems.Count - 1, currentIndex + itemsPerRow);
			handled = true;

		case .Home:
			newIndex = 0;
			handled = true;

		case .End:
			newIndex = mItems.Count - 1;
			handled = true;

		case .Return:
			if (mSelectedItem != null)
				mItemDoubleClickEvent.[Friend]Invoke(this, mSelectedItem);
			handled = true;

		default:
		}

		if (handled && newIndex != currentIndex && newIndex >= 0 && newIndex < mItems.Count)
		{
			if (SelectionMode == .Single || !args.HasModifier(.Ctrl))
			{
				SelectedItem = mItems[newIndex];
			}
			else
			{
				mSelectedItem = mItems[newIndex];
			}
			ScrollIntoView(mSelectedItem);
		}

		if (handled)
			args.Handled = true;
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

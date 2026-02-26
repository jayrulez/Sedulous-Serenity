using System;
using System.Collections;
using Sedulous.Foundation.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// A hierarchical view of items that can be expanded and collapsed.
public class TreeView : Control, IVisualChildProvider
{
	private ScrollViewer mScrollViewer ~ delete _;
	private StackPanel mItemsPanel ~ { }; // Owned by scroll viewer
	private List<TreeViewItem> mRootItems = new .() ~ DeleteContainerAndItems!(_); // Owns root items (and their children recursively)
	private List<TreeViewItem> mVisibleItems = new .() ~ delete _; // Flattened visible list (references only)
	private TreeViewItem mSelectedItem;
	private float mItemHeight = 22;

	// Events
	private EventAccessor<delegate void(TreeView, TreeViewItem)> mSelectionChangedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(TreeView, TreeViewItem)> mItemDoubleClickEvent = new .() ~ delete _;
	private EventAccessor<delegate void(TreeView, TreeViewItem)> mItemExpandedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(TreeView, TreeViewItem)> mItemCollapsedEvent = new .() ~ delete _;

	/// The root items in this tree.
	public List<TreeViewItem> RootItems => mRootItems;

	/// The currently selected item (null if none).
	public TreeViewItem SelectedItem
	{
		get => mSelectedItem;
		set
		{
			if (mSelectedItem != value)
			{
				if (mSelectedItem != null)
					mSelectedItem.IsSelected = false;

				mSelectedItem = value;

				if (mSelectedItem != null)
					mSelectedItem.IsSelected = true;

				mSelectionChangedEvent.[Friend]Invoke(this, mSelectedItem);
				InvalidateVisual();
			}
		}
	}

	/// Fixed height for each item.
	public float ItemHeight
	{
		get => mItemHeight;
		set
		{
			if (mItemHeight != value)
			{
				mItemHeight = Math.Max(16, value);
				RebuildVisibleItems();
				InvalidateMeasure();
			}
		}
	}

	/// Fired when selection changes.
	public EventAccessor<delegate void(TreeView, TreeViewItem)> SelectionChanged => mSelectionChangedEvent;

	/// Fired when an item is double-clicked.
	public EventAccessor<delegate void(TreeView, TreeViewItem)> ItemDoubleClick => mItemDoubleClickEvent;

	/// Fired when an item is expanded.
	public EventAccessor<delegate void(TreeView, TreeViewItem)> ItemExpanded => mItemExpandedEvent;

	/// Fired when an item is collapsed.
	public EventAccessor<delegate void(TreeView, TreeViewItem)> ItemCollapsed => mItemCollapsedEvent;

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

	/// Adds a root item to the tree.
	public void AddItem(TreeViewItem item)
	{
		item.IndentLevel = 0;
		mRootItems.Add(item);
		RebuildVisibleItems();
	}

	/// Adds a root item with text.
	public TreeViewItem AddItem(StringView text)
	{
		let item = new TreeViewItem(text);
		AddItem(item);
		return item;
	}

	/// Removes a root item from the tree.
	public void RemoveItem(TreeViewItem item)
	{
		if (mRootItems.Remove(item))
		{
			// Clear selection if needed
			if (IsItemOrDescendant(mSelectedItem, item))
				SelectedItem = null;

			RebuildVisibleItems();
		}
	}

	/// Clears all items from the tree.
	public void ClearItems()
	{
		mSelectedItem = null;
		mVisibleItems.Clear();

		// Detach items from panel (don't delete - they're owned by mRootItems)
		mItemsPanel.DetachChildren();

		// Delete all root items (and their children recursively via TreeViewItem destructor)
		for (let item in mRootItems)
			delete item;
		mRootItems.Clear();

		InvalidateMeasure();
	}

	/// Expands all items.
	public void ExpandAll()
	{
		for (let item in mRootItems)
			ExpandAllRecursive(item);
		RebuildVisibleItems();
	}

	/// Collapses all items.
	public void CollapseAll()
	{
		for (let item in mRootItems)
			CollapseAllRecursive(item);
		RebuildVisibleItems();
	}

	/// Expands to and selects the specified item.
	public void SelectAndScrollTo(TreeViewItem item)
	{
		if (item == null)
			return;

		// Expand all ancestors
		var parent = item.ParentItem;
		while (parent != null)
		{
			if (!parent.IsExpanded)
				parent.IsExpanded = true;
			parent = parent.ParentItem;
		}

		// Select and scroll
		SelectedItem = item;
		ScrollIntoView(item);
	}

	/// Scrolls to make the specified item visible.
	public void ScrollIntoView(TreeViewItem item)
	{
		if (item != null)
		{
			RebuildVisibleItems(); // Ensure visible items list is current
			let index = mVisibleItems.IndexOf(item);
			if (index >= 0)
			{
				let itemTop = index * mItemHeight;
				let itemBottom = itemTop + mItemHeight;

				let viewTop = mScrollViewer.VerticalOffset;
				let viewBottom = viewTop + mScrollViewer.ContentBounds.Height;

				if (itemTop < viewTop)
					mScrollViewer.VerticalOffset = itemTop;
				else if (itemBottom > viewBottom)
					mScrollViewer.VerticalOffset = itemBottom - mScrollViewer.ContentBounds.Height;
			}
		}
	}

	/// Called when an item's expanded state changes.
	private void OnItemExpandedChanged(TreeViewItem item)
	{
		RebuildVisibleItems();

		if (item.IsExpanded)
			mItemExpandedEvent.[Friend]Invoke(this, item);
		else
			mItemCollapsedEvent.[Friend]Invoke(this, item);
	}

	/// Rebuilds the flattened visible items list.
	private void RebuildVisibleItems()
	{
		// Detach visual children (don't delete - they're owned by mRootItems)
		mItemsPanel.DetachChildren();
		mVisibleItems.Clear();

		// Rebuild visible items
		for (let item in mRootItems)
			item.EnumerateVisible(mVisibleItems);

		// Add visible items to panel
		for (let item in mVisibleItems)
		{
			item.Height = .Fixed(mItemHeight);
			mItemsPanel.AddChild(item);
		}

		InvalidateMeasure();
	}

	private void ExpandAllRecursive(TreeViewItem item)
	{
		if (item.HasChildren)
		{
			item.[Friend]mIsExpanded = true; // Bypass event firing
			for (let child in item.Children)
				ExpandAllRecursive(child);
		}
	}

	private void CollapseAllRecursive(TreeViewItem item)
	{
		if (item.HasChildren)
		{
			item.[Friend]mIsExpanded = false; // Bypass event firing
			for (let child in item.Children)
				CollapseAllRecursive(child);
		}
	}

	private bool IsItemOrDescendant(TreeViewItem candidate, TreeViewItem root)
	{
		if (candidate == null)
			return false;
		if (candidate == root)
			return true;
		for (let child in root.Children)
		{
			if (IsItemOrDescendant(candidate, child))
				return true;
		}
		return false;
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
		let bg = Background ?? theme?.GetColor("TreeBackground") ?? theme?.GetColor("Background") ?? Color(37, 37, 38);
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

		if (args.Button == .Left)
		{
			// Find which item was clicked
			let contentY = args.LocalY + mScrollViewer.VerticalOffset;
			let clickedIndex = (int)(contentY / mItemHeight);

			if (clickedIndex >= 0 && clickedIndex < mVisibleItems.Count)
			{
				let item = mVisibleItems[clickedIndex];
				let localX = args.LocalX;

				// Check if clicked on expander
				if (item.HasChildren && item.IsInExpanderArea(localX))
				{
					item.IsExpanded = !item.IsExpanded;
				}
				else
				{
					// Select item
					SelectedItem = item;

					// Handle double-click
					if (args.ClickCount == 2)
					{
						// Toggle expansion on double-click if has children
						if (item.HasChildren)
							item.IsExpanded = !item.IsExpanded;

						mItemDoubleClickEvent.[Friend]Invoke(this, item);
					}
				}

				// Focus the tree
				Context?.SetFocus(this);
				args.Handled = true;
			}
		}
	}


	protected override void OnKeyDownRouted(KeyEventArgs args)
	{
		base.OnKeyDownRouted(args);

		if (mVisibleItems.Count == 0)
			return;

		var handled = false;
		let currentIndex = mSelectedItem != null ? mVisibleItems.IndexOf(mSelectedItem) : -1;
		var newIndex = currentIndex;

		switch (args.Key)
		{
		case .Up:
			newIndex = Math.Max(0, currentIndex - 1);
			handled = true;

		case .Down:
			newIndex = Math.Min(mVisibleItems.Count - 1, currentIndex + 1);
			handled = true;

		case .Home:
			newIndex = 0;
			handled = true;

		case .End:
			newIndex = mVisibleItems.Count - 1;
			handled = true;

		case .Left:
			if (mSelectedItem != null)
			{
				if (mSelectedItem.IsExpanded && mSelectedItem.HasChildren)
				{
					// Collapse
					mSelectedItem.IsExpanded = false;
				}
				else if (mSelectedItem.ParentItem != null)
				{
					// Go to parent
					SelectedItem = mSelectedItem.ParentItem;
				}
			}
			handled = true;

		case .Right:
			if (mSelectedItem != null)
			{
				if (!mSelectedItem.IsExpanded && mSelectedItem.HasChildren)
				{
					// Expand
					mSelectedItem.IsExpanded = true;
				}
				else if (mSelectedItem.IsExpanded && mSelectedItem.Children.Count > 0)
				{
					// Go to first child
					SelectedItem = mSelectedItem.Children[0];
				}
			}
			handled = true;

		case .Space, .Return:
			if (mSelectedItem != null && mSelectedItem.HasChildren)
			{
				mSelectedItem.IsExpanded = !mSelectedItem.IsExpanded;
			}
			if (args.Key == .Return && mSelectedItem != null)
			{
				mItemDoubleClickEvent.[Friend]Invoke(this, mSelectedItem);
			}
			handled = true;

		case .PageUp:
			let visibleCount = (int)(Bounds.Height / mItemHeight);
			newIndex = Math.Max(0, currentIndex - visibleCount);
			handled = true;

		case .PageDown:
			let visibleCount = (int)(Bounds.Height / mItemHeight);
			newIndex = Math.Min(mVisibleItems.Count - 1, currentIndex + visibleCount);
			handled = true;

		default:
		}

		if (handled && newIndex != currentIndex && newIndex >= 0 && newIndex < mVisibleItems.Count)
		{
			SelectedItem = mVisibleItems[newIndex];
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

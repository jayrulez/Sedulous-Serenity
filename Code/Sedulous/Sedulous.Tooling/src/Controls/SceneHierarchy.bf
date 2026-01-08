using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Mathematics;

namespace Sedulous.Tooling;

/// Represents a node in the scene hierarchy.
class HierarchyNode
{
	private String mName ~ delete _;
	private Object mEntity;
	private HierarchyNode mParent;
	private List<HierarchyNode> mChildren = new .() ~ DeleteContainerAndItems!(_);
	private bool mIsExpanded = true;
	private bool mIsSelected = false;
	private bool mIsVisible = true;
	private bool mIsLocked = false;
	private TextureHandle mIcon;

	/// Gets or sets the node name.
	public StringView Name
	{
		get => mName ?? "";
		set => String.NewOrSet!(mName, value);
	}

	/// Gets or sets the associated entity.
	public Object Entity
	{
		get => mEntity;
		set => mEntity = value;
	}

	/// Gets the parent node.
	public HierarchyNode Parent => mParent;

	/// Gets the children.
	public List<HierarchyNode> Children => mChildren;

	/// Gets or sets whether the node is expanded.
	public bool IsExpanded
	{
		get => mIsExpanded;
		set => mIsExpanded = value;
	}

	/// Gets or sets whether the node is selected.
	public bool IsSelected
	{
		get => mIsSelected;
		set => mIsSelected = value;
	}

	/// Gets or sets whether the entity is visible.
	public bool IsVisible
	{
		get => mIsVisible;
		set => mIsVisible = value;
	}

	/// Gets or sets whether the entity is locked.
	public bool IsLocked
	{
		get => mIsLocked;
		set => mIsLocked = value;
	}

	/// Gets or sets the icon.
	public TextureHandle Icon
	{
		get => mIcon;
		set => mIcon = value;
	}

	/// Gets the depth in the hierarchy.
	public int32 Depth
	{
		get
		{
			int32 depth = 0;
			var current = mParent;
			while (current != null)
			{
				depth++;
				current = current.mParent;
			}
			return depth;
		}
	}

	/// Creates a hierarchy node.
	public this(StringView name)
	{
		mName = new String(name);
	}

	/// Creates a hierarchy node with an entity.
	public this(StringView name, Object entity) : this(name)
	{
		mEntity = entity;
	}

	/// Adds a child node.
	public void AddChild(HierarchyNode child)
	{
		child.mParent = this;
		mChildren.Add(child);
	}

	/// Removes a child node.
	public void RemoveChild(HierarchyNode child)
	{
		child.mParent = null;
		mChildren.Remove(child);
	}

	/// Removes this node from its parent.
	public void RemoveFromParent()
	{
		if (mParent != null)
			mParent.RemoveChild(this);
	}

	/// Gets the total visible row count (including expanded children).
	public int32 GetVisibleRowCount()
	{
		int32 count = 1;
		if (mIsExpanded)
		{
			for (let child in mChildren)
				count += child.GetVisibleRowCount();
		}
		return count;
	}

	/// Finds a node by entity.
	public HierarchyNode FindByEntity(Object entity)
	{
		if (mEntity == entity)
			return this;

		for (let child in mChildren)
		{
			let found = child.FindByEntity(entity);
			if (found != null)
				return found;
		}

		return null;
	}
}

/// A panel that displays the scene hierarchy as a tree.
class SceneHierarchy : ToolPanel
{
	private HierarchyNode mRootNode ~ delete _;
	private List<HierarchyNode> mSelectedNodes = new .() ~ delete _;
	private HierarchyNode mHoveredNode;
	private float mScrollOffset = 0;
	private bool mAllowMultiSelect = false;
	private bool mAllowDragDrop = true;
	private String mSearchFilter ~ delete _;

	// Visual properties
	private Color mBackgroundColor = Color(35, 35, 35, 255);
	private Color mRowBackground = Color(40, 40, 40, 255);
	private Color mRowAlternateBackground = Color(45, 45, 45, 255);
	private Color mRowHoverBackground = Color(50, 50, 50, 255);
	private Color mRowSelectedBackground = Color(70, 100, 150, 255);
	private Color mTextColor = Color(200, 200, 200, 255);
	private Color mSecondaryTextColor = Color(140, 140, 140, 255);
	private Color mExpanderColor = Color(160, 160, 160, 255);
	private Color mVisibilityIconColor = Color(180, 180, 180, 255);
	private Color mLockIconColor = Color(200, 160, 100, 255);
	private float mRowHeight = 22;
	private float mIndentSize = 16;
	private float mExpanderSize = 12;
	private float mIconSize = 16;
	private float mSearchBarHeight = 26;

	// State
	private bool mShowSearchBar = true;
	private int32 mVisibleRowIndex = 0;

	/// Event raised when an entity is selected.
	public Event<delegate void(Object entity)> OnEntitySelected ~ _.Dispose();

	/// Event raised when an entity is renamed.
	public Event<delegate void(Object entity, StringView newName)> OnEntityRenamed ~ _.Dispose();

	/// Event raised when an entity is deleted.
	public Event<delegate void(Object entity)> OnEntityDeleted ~ _.Dispose();

	/// Event raised when an entity is reparented.
	public Event<delegate void(Object entity, Object newParent)> OnEntityReparented ~ _.Dispose();

	/// Gets or sets the root node.
	public HierarchyNode RootNode
	{
		get => mRootNode;
		set
		{
			delete mRootNode;
			mRootNode = value;
			mSelectedNodes.Clear();
			mHoveredNode = null;
			mScrollOffset = 0;
			InvalidateMeasure();
		}
	}

	/// Gets the selected nodes.
	public List<HierarchyNode> SelectedNodes => mSelectedNodes;

	/// Gets or sets whether multi-select is allowed.
	public bool AllowMultiSelect
	{
		get => mAllowMultiSelect;
		set => mAllowMultiSelect = value;
	}

	/// Gets or sets whether drag-drop is allowed.
	public bool AllowDragDrop
	{
		get => mAllowDragDrop;
		set => mAllowDragDrop = value;
	}

	/// Gets or sets the search filter.
	public StringView SearchFilter
	{
		get => mSearchFilter ?? "";
		set
		{
			String.NewOrSet!(mSearchFilter, value);
			InvalidateVisual();
		}
	}

	/// Gets or sets whether to show the search bar.
	public bool ShowSearchBar
	{
		get => mShowSearchBar;
		set
		{
			mShowSearchBar = value;
			InvalidateMeasure();
		}
	}

	/// Creates a scene hierarchy panel.
	public this() : base("Hierarchy")
	{
		mRootNode = new HierarchyNode("Scene");
	}

	protected override void OnBuildUI()
	{
		// SceneHierarchy manages its own content
	}

	/// Selects a node.
	public void SelectNode(HierarchyNode node, bool addToSelection = false)
	{
		if (!mAllowMultiSelect || !addToSelection)
		{
			// Clear previous selection
			for (let selected in mSelectedNodes)
				selected.IsSelected = false;
			mSelectedNodes.Clear();
		}

		if (node != null)
		{
			node.IsSelected = true;
			if (!mSelectedNodes.Contains(node))
				mSelectedNodes.Add(node);

			if (node.Entity != null)
				OnEntitySelected(node.Entity);
		}

		InvalidateVisual();
	}

	/// Clears the selection.
	public void ClearSelection()
	{
		for (let node in mSelectedNodes)
			node.IsSelected = false;
		mSelectedNodes.Clear();
		InvalidateVisual();
	}

	/// Expands all nodes.
	public void ExpandAll()
	{
		if (mRootNode != null)
			ExpandRecursive(mRootNode, true);
		InvalidateVisual();
	}

	/// Collapses all nodes.
	public void CollapseAll()
	{
		if (mRootNode != null)
			ExpandRecursive(mRootNode, false);
		InvalidateVisual();
	}

	private void ExpandRecursive(HierarchyNode node, bool expand)
	{
		node.IsExpanded = expand;
		for (let child in node.Children)
			ExpandRecursive(child, expand);
	}

	/// Scrolls to make a node visible.
	public void ScrollToNode(HierarchyNode node)
	{
		if (node == null || mRootNode == null)
			return;

		// Ensure parents are expanded
		var current = node.Parent;
		while (current != null)
		{
			current.IsExpanded = true;
			current = current.Parent;
		}

		// Calculate node position
		int32 rowIndex = 0;
		if (FindNodeRow(mRootNode, node, ref rowIndex))
		{
			let nodeY = rowIndex * mRowHeight;
			let contentHeight = ContentBounds.Height - HeaderHeight - (mShowSearchBar ? mSearchBarHeight : 0);

			if (nodeY < mScrollOffset)
				mScrollOffset = nodeY;
			else if (nodeY + mRowHeight > mScrollOffset + contentHeight)
				mScrollOffset = nodeY + mRowHeight - contentHeight;
		}

		InvalidateVisual();
	}

	private bool FindNodeRow(HierarchyNode current, HierarchyNode target, ref int32 rowIndex)
	{
		if (current == target)
			return true;

		rowIndex++;

		if (current.IsExpanded)
		{
			for (let child in current.Children)
			{
				if (FindNodeRow(child, target, ref rowIndex))
					return true;
			}
		}

		return false;
	}

	protected override void OnRender(DrawContext dc)
	{
		base.OnRender(dc);

		let contentBounds = ContentBounds;
		let hierarchyBounds = RectangleF(
			contentBounds.X,
			contentBounds.Y + HeaderHeight,
			contentBounds.Width,
			contentBounds.Height - HeaderHeight
		);

		// Search bar
		if (mShowSearchBar)
		{
			let searchRect = RectangleF(hierarchyBounds.X, hierarchyBounds.Y, hierarchyBounds.Width, mSearchBarHeight);
			dc.FillRect(searchRect, Color(45, 45, 45, 255));

			let searchTextRect = RectangleF(searchRect.X + 24, searchRect.Y, searchRect.Width - 28, searchRect.Height);
			if (mSearchFilter != null && mSearchFilter.Length > 0)
				dc.DrawText(mSearchFilter, Font, FontSize, searchTextRect, mTextColor, .Start, .Center, false);
			else
				dc.DrawText("Search...", Font, FontSize, searchTextRect, mSecondaryTextColor, .Start, .Center, false);

			// Search icon placeholder
			dc.DrawText("?", Font, FontSize, RectangleF(searchRect.X + 6, searchRect.Y, 16, searchRect.Height), mSecondaryTextColor, .Center, .Center, false);
		}

		// Tree content
		let treeRect = RectangleF(
			hierarchyBounds.X,
			hierarchyBounds.Y + (mShowSearchBar ? mSearchBarHeight : 0),
			hierarchyBounds.Width,
			hierarchyBounds.Height - (mShowSearchBar ? mSearchBarHeight : 0)
		);
		dc.FillRect(treeRect, mBackgroundColor);

		// Render tree
		if (mRootNode != null)
		{
			mVisibleRowIndex = 0;
			RenderNode(dc, mRootNode, treeRect, treeRect.Y - mScrollOffset);
		}
	}

	private float RenderNode(DrawContext dc, HierarchyNode node, RectangleF treeRect, float yPos)
	{
		var y = yPos;
		let rowRect = RectangleF(treeRect.X, y, treeRect.Width, mRowHeight);
		let indent = node.Depth * mIndentSize;

		// Only render if visible
		if (rowRect.Bottom > treeRect.Y && rowRect.Y < treeRect.Bottom)
		{
			// Background
			Color bgColor;
			if (node.IsSelected)
				bgColor = mRowSelectedBackground;
			else if (node == mHoveredNode)
				bgColor = mRowHoverBackground;
			else if (mVisibleRowIndex % 2 == 0)
				bgColor = mRowBackground;
			else
				bgColor = mRowAlternateBackground;

			dc.FillRect(rowRect, bgColor);

			float x = rowRect.X + indent + 4;

			// Expander
			if (node.Children.Count > 0)
			{
				let expanderRect = RectangleF(x, rowRect.Y + (mRowHeight - mExpanderSize) / 2, mExpanderSize, mExpanderSize);

				Vector2[3] arrow;
				if (node.IsExpanded)
				{
					// Down arrow
					arrow = .(
						Vector2(expanderRect.X, expanderRect.Y + 2),
						Vector2(expanderRect.Right, expanderRect.Y + 2),
						Vector2(expanderRect.X + mExpanderSize / 2, expanderRect.Bottom - 2)
					);
				}
				else
				{
					// Right arrow
					arrow = .(
						Vector2(expanderRect.X + 2, expanderRect.Y),
						Vector2(expanderRect.Right - 2, expanderRect.Y + mExpanderSize / 2),
						Vector2(expanderRect.X + 2, expanderRect.Bottom)
					);
				}
				dc.FillPath(arrow, mExpanderColor);
			}
			x += mExpanderSize + 4;

			// Icon
			if (node.Icon.Value != 0)
			{
				let iconRect = RectangleF(x, rowRect.Y + (mRowHeight - mIconSize) / 2, mIconSize, mIconSize);
				dc.DrawImage(node.Icon, iconRect, Color.White);
				x += mIconSize + 4;
			}

			// Name
			let nameRect = RectangleF(x, rowRect.Y, rowRect.Right - x - 40, mRowHeight);
			dc.DrawText(node.Name, Font, FontSize, nameRect, mTextColor, .Start, .Center, false);

			// Visibility toggle
			let visRect = RectangleF(rowRect.Right - 36, rowRect.Y + (mRowHeight - 12) / 2, 12, 12);
			let visColor = node.IsVisible ? mVisibilityIconColor : Color(80, 80, 80, 255);
			dc.DrawText("O", Font, 10, visRect, visColor, .Center, .Center, false);

			// Lock toggle
			let lockRect = RectangleF(rowRect.Right - 18, rowRect.Y + (mRowHeight - 12) / 2, 12, 12);
			if (node.IsLocked)
				dc.DrawText("L", Font, 10, lockRect, mLockIconColor, .Center, .Center, false);
		}

		mVisibleRowIndex++;
		y += mRowHeight;

		// Render children
		if (node.IsExpanded)
		{
			for (let child in node.Children)
			{
				y = RenderNode(dc, child, treeRect, y);
			}
		}

		return y;
	}

	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		let contentBounds = ContentBounds;
		let treeRect = RectangleF(
			contentBounds.X,
			contentBounds.Y + HeaderHeight + (mShowSearchBar ? mSearchBarHeight : 0),
			contentBounds.Width,
			contentBounds.Height - HeaderHeight - (mShowSearchBar ? mSearchBarHeight : 0)
		);

		HierarchyNode newHovered = null;

		if (treeRect.Contains(e.Position) && mRootNode != null)
		{
			let relY = e.Position.Y - treeRect.Y + mScrollOffset;
			let rowIndex = (int32)(relY / mRowHeight);
			int32 currentRow = 0;
			newHovered = FindNodeAtRow(mRootNode, rowIndex, &currentRow);
		}

		if (mHoveredNode != newHovered)
		{
			mHoveredNode = newHovered;
			InvalidateVisual();
		}

		return base.OnMouseMove(e);
	}

	private HierarchyNode FindNodeAtRow(HierarchyNode node, int32 targetRow, int32* currentRow)
	{
		if (*currentRow == targetRow)
			return node;

		(*currentRow)++;

		if (node.IsExpanded)
		{
			for (let child in node.Children)
			{
				let found = FindNodeAtRow(child, targetRow, currentRow);
				if (found != null)
					return found;
			}
		}

		return null;
	}

	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return base.OnMouseDown(e);

		if (mHoveredNode != null)
		{
			let contentBounds = ContentBounds;
			let treeRect = RectangleF(
				contentBounds.X,
				contentBounds.Y + HeaderHeight + (mShowSearchBar ? mSearchBarHeight : 0),
				contentBounds.Width,
				contentBounds.Height - HeaderHeight - (mShowSearchBar ? mSearchBarHeight : 0)
			);

			// Check if click is on expander
			int32 rowIndex = 0;
			if (FindNodeRow(mRootNode, mHoveredNode, ref rowIndex))
			{
				let rowY = treeRect.Y + rowIndex * mRowHeight - mScrollOffset;
				let indent = mHoveredNode.Depth * mIndentSize;
				let expanderRect = RectangleF(
					treeRect.X + indent + 4,
					rowY + (mRowHeight - mExpanderSize) / 2,
					mExpanderSize,
					mExpanderSize
				);

				if (expanderRect.Contains(e.Position) && mHoveredNode.Children.Count > 0)
				{
					mHoveredNode.IsExpanded = !mHoveredNode.IsExpanded;
					InvalidateVisual();
					return true;
				}

				// Check visibility toggle
				let visRect = RectangleF(treeRect.Right - 36, rowY + (mRowHeight - 12) / 2, 12, 12);
				if (visRect.Contains(e.Position))
				{
					mHoveredNode.IsVisible = !mHoveredNode.IsVisible;
					InvalidateVisual();
					return true;
				}

				// Check lock toggle
				let lockRect = RectangleF(treeRect.Right - 18, rowY + (mRowHeight - 12) / 2, 12, 12);
				if (lockRect.Contains(e.Position))
				{
					mHoveredNode.IsLocked = !mHoveredNode.IsLocked;
					InvalidateVisual();
					return true;
				}
			}

			// Select node
			let addToSelection = mAllowMultiSelect && e.Modifiers.HasFlag(.Control);
			SelectNode(mHoveredNode, addToSelection);
			return true;
		}

		return base.OnMouseDown(e);
	}

	protected override bool OnMouseWheel(MouseWheelEventArgs e)
	{
		mScrollOffset = Math.Max(0, mScrollOffset - e.DeltaY * mRowHeight * 3);
		InvalidateVisual();
		return true;
	}

	protected override bool OnKeyDown(KeyEventArgs e)
	{
		switch (e.Key)
		{
		case .Delete:
			if (mSelectedNodes.Count > 0)
			{
				for (let node in mSelectedNodes)
				{
					if (node.Entity != null)
						OnEntityDeleted(node.Entity);
				}
				return true;
			}
		case .Left:
			if (mSelectedNodes.Count == 1)
			{
				let node = mSelectedNodes[0];
				if (node.IsExpanded && node.Children.Count > 0)
				{
					node.IsExpanded = false;
					InvalidateVisual();
				}
				else if (node.Parent != null)
				{
					SelectNode(node.Parent);
				}
				return true;
			}
		case .Right:
			if (mSelectedNodes.Count == 1)
			{
				let node = mSelectedNodes[0];
				if (!node.IsExpanded && node.Children.Count > 0)
				{
					node.IsExpanded = true;
					InvalidateVisual();
				}
				else if (node.Children.Count > 0)
				{
					SelectNode(node.Children[0]);
				}
				return true;
			}
		default:
		}

		return base.OnKeyDown(e);
	}
}

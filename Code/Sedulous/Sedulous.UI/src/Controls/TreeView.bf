using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Represents a node in a TreeView.
class TreeViewNode
{
	private String mText ~ delete _;
	private List<TreeViewNode> mChildren = new .() ~ DeleteContainerAndItems!(_);
	private TreeViewNode mParent;
	private bool mIsExpanded = false;
	private bool mIsSelected = false;
	private Object mTag;
	private TextureHandle mIcon;

	/// Event raised when expanded state changes.
	public Event<delegate void(bool isExpanded)> OnExpandedChanged ~ _.Dispose();

	/// Gets or sets the display text.
	public StringView Text
	{
		get => mText ?? "";
		set => String.NewOrSet!(mText, value);
	}

	/// Gets the children collection.
	public List<TreeViewNode> Children => mChildren;

	/// Gets the parent node.
	public TreeViewNode Parent => mParent;

	/// Gets or sets whether this node is expanded.
	public bool IsExpanded
	{
		get => mIsExpanded;
		set
		{
			if (mIsExpanded != value && mChildren.Count > 0)
			{
				mIsExpanded = value;
				OnExpandedChanged(value);
			}
		}
	}

	/// Gets or sets whether this node is selected.
	public bool IsSelected
	{
		get => mIsSelected;
		set => mIsSelected = value;
	}

	/// Gets or sets a custom tag object.
	public Object Tag
	{
		get => mTag;
		set => mTag = value;
	}

	/// Gets or sets the icon texture.
	public TextureHandle Icon
	{
		get => mIcon;
		set => mIcon = value;
	}

	/// Gets whether this node has children.
	public bool HasChildren => mChildren.Count > 0;

	/// Gets the depth level of this node.
	public int32 Level
	{
		get
		{
			int32 level = 0;
			var node = mParent;
			while (node != null)
			{
				level++;
				node = node.mParent;
			}
			return level;
		}
	}

	/// Creates a tree view node with text.
	public this(StringView text)
	{
		mText = new String(text);
	}

	/// Adds a child node.
	public TreeViewNode AddChild(StringView text)
	{
		let child = new TreeViewNode(text);
		child.mParent = this;
		mChildren.Add(child);
		return child;
	}

	/// Adds an existing node as a child.
	public void AddChild(TreeViewNode node)
	{
		node.mParent = this;
		mChildren.Add(node);
	}

	/// Removes a child node.
	public void RemoveChild(TreeViewNode node)
	{
		if (mChildren.Remove(node))
		{
			node.mParent = null;
		}
	}

	/// Clears all children.
	public void ClearChildren()
	{
		for (let child in mChildren)
		{
			child.mParent = null;
			delete child;
		}
		mChildren.Clear();
	}

	/// Expands this node and all ancestors.
	public void ExpandPath()
	{
		IsExpanded = true;
		mParent?.ExpandPath();
	}

	/// Collapses this node and all descendants.
	public void CollapseAll()
	{
		IsExpanded = false;
		for (let child in mChildren)
			child.CollapseAll();
	}

	/// Expands all descendants.
	public void ExpandAll()
	{
		IsExpanded = true;
		for (let child in mChildren)
			child.ExpandAll();
	}
}

/// A hierarchical tree control.
class TreeView : Widget
{
	private List<TreeViewNode> mRootNodes = new .() ~ DeleteContainerAndItems!(_);
	private TreeViewNode mSelectedNode;
	private TreeViewNode mHoveredNode;

	// Visual properties
	private Color mBackgroundColor = Color(45, 45, 45, 255);
	private Color mItemHoverBackground = Color(60, 60, 60, 255);
	private Color mItemSelectedBackground = Color(70, 100, 150, 255);
	private Color mTextColor = .White;
	private Color mExpanderColor = Color(180, 180, 180, 255);
	private Color mLineColor = Color(80, 80, 80, 255);
	private Color mBorderColor = Color(70, 70, 70, 255);
	private float mBorderWidth = 1;
	private FontHandle mFont;
	private float mFontSize = 13;
	private float mItemHeight = 22;
	private float mIndentWidth = 18;
	private float mExpanderSize = 12;
	private float mIconSize = 16;
	private bool mShowLines = false;

	// Scroll state
	private float mScrollOffset = 0;
	private float mTotalHeight = 0;

	/// Event raised when selection changes.
	public Event<delegate void(TreeViewNode oldNode, TreeViewNode newNode)> OnSelectionChanged ~ _.Dispose();

	/// Event raised when a node is expanded.
	public Event<delegate void(TreeViewNode node)> OnNodeExpanded ~ _.Dispose();

	/// Event raised when a node is collapsed.
	public Event<delegate void(TreeViewNode node)> OnNodeCollapsed ~ _.Dispose();

	/// Event raised when a node is double-clicked.
	public Event<delegate void(TreeViewNode node)> OnNodeDoubleClick ~ _.Dispose();

	/// Gets the root nodes collection.
	public List<TreeViewNode> RootNodes => mRootNodes;

	/// Gets or sets the selected node.
	public TreeViewNode SelectedNode
	{
		get => mSelectedNode;
		set
		{
			if (mSelectedNode != value)
			{
				let oldNode = mSelectedNode;
				if (mSelectedNode != null)
					mSelectedNode.IsSelected = false;

				mSelectedNode = value;

				if (mSelectedNode != null)
					mSelectedNode.IsSelected = true;

				OnSelectionChanged(oldNode, value);
				InvalidateVisual();
			}
		}
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

	/// Gets or sets whether to show tree lines.
	public bool ShowLines
	{
		get => mShowLines;
		set { mShowLines = value; InvalidateVisual(); }
	}

	/// Gets or sets the scroll offset.
	public float ScrollOffset
	{
		get => mScrollOffset;
		set
		{
			let newOffset = Math.Clamp(value, 0, Math.Max(0, mTotalHeight - Bounds.Height));
			if (mScrollOffset != newOffset)
			{
				mScrollOffset = newOffset;
				InvalidateVisual();
			}
		}
	}

	/// Adds a root node.
	public TreeViewNode AddNode(StringView text)
	{
		let node = new TreeViewNode(text);
		mRootNodes.Add(node);
		InvalidateMeasure();
		return node;
	}

	/// Adds an existing node as a root.
	public void AddNode(TreeViewNode node)
	{
		mRootNodes.Add(node);
		InvalidateMeasure();
	}

	/// Removes a root node.
	public void RemoveNode(TreeViewNode node)
	{
		if (mRootNodes.Remove(node))
		{
			if (mSelectedNode == node)
				SelectedNode = null;
			InvalidateMeasure();
		}
	}

	/// Clears all nodes.
	public void ClearNodes()
	{
		for (let node in mRootNodes)
			delete node;
		mRootNodes.Clear();
		mSelectedNode = null;
		mHoveredNode = null;
		InvalidateMeasure();
	}

	/// Scrolls to make a node visible.
	public void ScrollIntoView(TreeViewNode node)
	{
		if (node == null)
			return;

		// Expand ancestors
		node.Parent?.ExpandPath();

		// Calculate node position
		float nodeY = 0;
		bool found = false;
		CalculateNodePosition(mRootNodes, node, ref nodeY, ref found);

		if (found)
		{
			let viewportHeight = Bounds.Height - Padding.VerticalThickness;
			if (nodeY < mScrollOffset)
				ScrollOffset = nodeY;
			else if (nodeY + mItemHeight > mScrollOffset + viewportHeight)
				ScrollOffset = nodeY + mItemHeight - viewportHeight;
		}
	}

	private void CalculateNodePosition(List<TreeViewNode> nodes, TreeViewNode target, ref float y, ref bool found)
	{
		for (let node in nodes)
		{
			if (node == target)
			{
				found = true;
				return;
			}

			y += mItemHeight;

			if (node.IsExpanded && node.Children.Count > 0)
			{
				CalculateNodePosition(node.Children, target, ref y, ref found);
				if (found)
					return;
			}
		}
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		// Calculate total height
		mTotalHeight = 0;
		CountVisibleNodes(mRootNodes, ref mTotalHeight);

		return Vector2(
			Padding.HorizontalThickness + 200, // Min width
			mTotalHeight + Padding.VerticalThickness
		);
	}

	private void CountVisibleNodes(List<TreeViewNode> nodes, ref float height)
	{
		for (let node in nodes)
		{
			height += mItemHeight;

			if (node.IsExpanded && node.Children.Count > 0)
				CountVisibleNodes(node.Children, ref height);
		}
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		// TreeView handles its own layout in OnRender
	}

	protected override void OnRender(DrawContext dc)
	{
		let contentBounds = ContentBounds;

		// Background
		dc.FillRect(contentBounds, mBackgroundColor);
		dc.DrawRect(contentBounds, mBorderColor, mBorderWidth);

		// Clip to content area
		dc.PushClip(contentBounds);

		// Render visible nodes
		float y = contentBounds.Y - mScrollOffset;
		RenderNodes(dc, mRootNodes, contentBounds.X, ref y, contentBounds);

		dc.PopClip();
	}

	private void RenderNodes(DrawContext dc, List<TreeViewNode> nodes, float baseX, ref float y, RectangleF clipBounds)
	{
		for (int32 i = 0; i < nodes.Count; i++)
		{
			let node = nodes[i];
			let level = node.Level;
			let x = baseX + level * mIndentWidth;

			// Skip if not visible
			if (y + mItemHeight < clipBounds.Y)
			{
				y += mItemHeight;
				if (node.IsExpanded && node.Children.Count > 0)
					SkipNodes(node.Children, ref y);
				continue;
			}

			// Stop if past visible area
			if (y > clipBounds.Bottom)
				break;

			let itemRect = RectangleF(clipBounds.X, y, clipBounds.Width, mItemHeight);

			// Selection/hover background
			if (node.IsSelected)
				dc.FillRect(itemRect, mItemSelectedBackground);
			else if (node == mHoveredNode)
				dc.FillRect(itemRect, mItemHoverBackground);

			// Expander
			if (node.HasChildren)
			{
				let expanderX = x;
				let expanderY = y + (mItemHeight - mExpanderSize) / 2;

				Vector2[3] arrowPoints;
				if (node.IsExpanded)
				{
					// Down arrow
					arrowPoints = .(
						Vector2(expanderX + 2, expanderY + 3),
						Vector2(expanderX + mExpanderSize - 2, expanderY + 3),
						Vector2(expanderX + mExpanderSize / 2, expanderY + mExpanderSize - 3)
					);
				}
				else
				{
					// Right arrow
					arrowPoints = .(
						Vector2(expanderX + 3, expanderY + 2),
						Vector2(expanderX + 3, expanderY + mExpanderSize - 2),
						Vector2(expanderX + mExpanderSize - 3, expanderY + mExpanderSize / 2)
					);
				}
				dc.FillPath(arrowPoints, mExpanderColor);
			}

			// Icon
			float textX = x + mIndentWidth;
			if (node.Icon.Value != 0)
			{
				let iconX = textX;
				let iconY = y + (mItemHeight - mIconSize) / 2;
				dc.DrawImage(node.Icon, RectangleF(iconX, iconY, mIconSize, mIconSize), Color.White);
				textX += mIconSize + 4;
			}

			// Text
			let textRect = RectangleF(textX, y, clipBounds.Right - textX, mItemHeight);
			dc.DrawText(node.Text, mFont, mFontSize, textRect, mTextColor, .Start, .Center, false);

			// Tree lines (simplified)
			if (mShowLines && level > 0)
			{
				let lineY = y + mItemHeight / 2;
				dc.DrawLine(Vector2(x - mIndentWidth / 2, lineY), Vector2(x, lineY), mLineColor, 1);
			}

			y += mItemHeight;

			// Render children
			if (node.IsExpanded && node.Children.Count > 0)
				RenderNodes(dc, node.Children, baseX, ref y, clipBounds);
		}
	}

	private void SkipNodes(List<TreeViewNode> nodes, ref float y)
	{
		for (let node in nodes)
		{
			y += mItemHeight;
			if (node.IsExpanded && node.Children.Count > 0)
				SkipNodes(node.Children, ref y);
		}
	}

	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		let contentBounds = ContentBounds;
		if (!contentBounds.Contains(e.Position))
		{
			if (mHoveredNode != null)
			{
				mHoveredNode = null;
				InvalidateVisual();
			}
			return false;
		}

		// Find node at position
		float y = contentBounds.Y - mScrollOffset;
		let newHovered = FindNodeAtY(mRootNodes, e.Position.Y, ref y);

		if (mHoveredNode != newHovered)
		{
			mHoveredNode = newHovered;
			InvalidateVisual();
		}

		return true;
	}

	private TreeViewNode FindNodeAtY(List<TreeViewNode> nodes, float targetY, ref float y)
	{
		for (let node in nodes)
		{
			if (targetY >= y && targetY < y + mItemHeight)
				return node;

			y += mItemHeight;

			if (node.IsExpanded && node.Children.Count > 0)
			{
				let found = FindNodeAtY(node.Children, targetY, ref y);
				if (found != null)
					return found;
			}
		}
		return null;
	}

	protected override bool OnMouseLeave(MouseEventArgs e)
	{
		if (mHoveredNode != null)
		{
			mHoveredNode = null;
			InvalidateVisual();
		}
		return false;
	}

	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return false;

		let contentBounds = ContentBounds;
		if (!contentBounds.Contains(e.Position))
			return false;

		if (mHoveredNode != null)
		{
			// Check if clicked on expander
			let level = mHoveredNode.Level;
			let expanderX = contentBounds.X + level * mIndentWidth;

			if (mHoveredNode.HasChildren && e.Position.X >= expanderX && e.Position.X < expanderX + mExpanderSize)
			{
				// Toggle expansion
				mHoveredNode.IsExpanded = !mHoveredNode.IsExpanded;
				if (mHoveredNode.IsExpanded)
					OnNodeExpanded(mHoveredNode);
				else
					OnNodeCollapsed(mHoveredNode);
				InvalidateMeasure();
			}
			else
			{
				// Select node
				SelectedNode = mHoveredNode;
			}

			return true;
		}

		return false;
	}

	protected override bool OnMouseWheel(MouseWheelEventArgs e)
	{
		ScrollOffset -= e.DeltaY * mItemHeight * 3;
		return true;
	}

	protected override bool OnKeyDown(KeyEventArgs e)
	{
		if (mSelectedNode == null && mRootNodes.Count > 0)
		{
			SelectedNode = mRootNodes[0];
			return true;
		}

		switch (e.Key)
		{
		case .Up:
			SelectPreviousNode();
			return true;
		case .Down:
			SelectNextNode();
			return true;
		case .Left:
			if (mSelectedNode != null)
			{
				if (mSelectedNode.IsExpanded)
				{
					mSelectedNode.IsExpanded = false;
					OnNodeCollapsed(mSelectedNode);
					InvalidateMeasure();
				}
				else if (mSelectedNode.Parent != null)
				{
					SelectedNode = mSelectedNode.Parent;
				}
			}
			return true;
		case .Right:
			if (mSelectedNode != null && mSelectedNode.HasChildren)
			{
				if (!mSelectedNode.IsExpanded)
				{
					mSelectedNode.IsExpanded = true;
					OnNodeExpanded(mSelectedNode);
					InvalidateMeasure();
				}
				else
				{
					SelectedNode = mSelectedNode.Children[0];
				}
			}
			return true;
		case .Enter, .Space:
			if (mSelectedNode != null)
				OnNodeDoubleClick(mSelectedNode);
			return true;
		default:
		}

		return false;
	}

	private void SelectPreviousNode()
	{
		if (mSelectedNode == null)
			return;

		TreeViewNode prev = null;
		FindPreviousNode(mRootNodes, mSelectedNode, ref prev);

		if (prev != null)
		{
			SelectedNode = prev;
			ScrollIntoView(prev);
		}
	}

	private bool FindPreviousNode(List<TreeViewNode> nodes, TreeViewNode target, ref TreeViewNode prev)
	{
		for (let node in nodes)
		{
			if (node == target)
				return true;

			prev = node;

			// Check expanded children
			if (node.IsExpanded && node.Children.Count > 0)
			{
				if (FindPreviousNode(node.Children, target, ref prev))
					return true;
			}
		}
		return false;
	}

	private void SelectNextNode()
	{
		if (mSelectedNode == null)
			return;

		TreeViewNode next = null;
		bool foundCurrent = false;
		FindNextNode(mRootNodes, mSelectedNode, ref next, ref foundCurrent);

		if (next != null)
		{
			SelectedNode = next;
			ScrollIntoView(next);
		}
	}

	private void FindNextNode(List<TreeViewNode> nodes, TreeViewNode target, ref TreeViewNode next, ref bool foundCurrent)
	{
		for (let node in nodes)
		{
			if (foundCurrent && next == null)
			{
				next = node;
				return;
			}

			if (node == target)
			{
				foundCurrent = true;

				// First child if expanded
				if (node.IsExpanded && node.Children.Count > 0)
				{
					next = node.Children[0];
					return;
				}
				continue;
			}

			// Check expanded children
			if (node.IsExpanded && node.Children.Count > 0)
			{
				FindNextNode(node.Children, target, ref next, ref foundCurrent);
				if (next != null)
					return;
			}
		}
	}
}

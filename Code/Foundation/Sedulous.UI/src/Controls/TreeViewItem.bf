using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// An item in a TreeView that can contain child items.
public class TreeViewItem : Control
{
	private String mText ~ delete _;
	private bool mIsSelected;
	private bool mIsExpanded;
	private Object mTag;
	private TreeViewItem mParentItem;
	private List<TreeViewItem> mChildren = new .() ~ DeleteContainerAndItems!(_);
	private int mIndentLevel;

	// Layout constants
	private const float cExpanderSize = 16;
	private const float cIndentWidth = 20;
	private const float cItemHeight = 22;

	/// The text displayed for this item.
	public StringView Text
	{
		get => mText ?? "";
		set
		{
			if (mText == null)
				mText = new String();
			mText.Set(value);
			InvalidateMeasure();
		}
	}

	/// Whether this item is currently selected.
	public bool IsSelected
	{
		get => mIsSelected;
		set
		{
			if (mIsSelected != value)
			{
				mIsSelected = value;
				InvalidateVisual();
			}
		}
	}

	/// Whether this item's children are visible.
	public bool IsExpanded
	{
		get => mIsExpanded;
		set
		{
			if (mIsExpanded != value)
			{
				mIsExpanded = value;
				InvalidateMeasure();

				// Notify tree of expansion change
				if (let tree = FindParentTree())
					tree.[Friend]OnItemExpandedChanged(this);
			}
		}
	}

	/// Whether this item has child items.
	public bool HasChildren => mChildren.Count > 0;

	/// The child items.
	public List<TreeViewItem> Children => mChildren;

	/// The parent tree item (null for root items).
	public TreeViewItem ParentItem => mParentItem;

	/// The indentation level (0 for root items).
	public int IndentLevel
	{
		get => mIndentLevel;
		set => mIndentLevel = value;
	}

	/// User-defined data associated with this item.
	public Object Tag
	{
		get => mTag;
		set => mTag = value;
	}

	public this()
	{
		Focusable = false;
		Height = .Fixed(cItemHeight);
		Padding = Thickness(2);
	}

	public this(StringView text) : this()
	{
		Text = text;
	}

	/// Adds a child item.
	public TreeViewItem AddChild(StringView text)
	{
		let child = new TreeViewItem(text);
		AddChild(child);
		return child;
	}

	/// Adds a child item.
	public void AddChild(TreeViewItem item)
	{
		item.mParentItem = this;
		item.mIndentLevel = mIndentLevel + 1;
		mChildren.Add(item);
		InvalidateMeasure();
	}

	/// Removes a child item.
	public void RemoveChild(TreeViewItem item)
	{
		if (mChildren.Remove(item))
		{
			item.mParentItem = null;
			item.mIndentLevel = 0;
			InvalidateMeasure();
		}
	}

	/// Clears all child items.
	public void ClearChildren()
	{
		for (let child in mChildren)
		{
			child.mParentItem = null;
			child.mIndentLevel = 0;
		}
		DeleteContainerAndItems!(mChildren);
		mChildren = new .();
		InvalidateMeasure();
	}

	/// Updates indent level recursively.
	internal void UpdateIndentLevels(int parentLevel)
	{
		mIndentLevel = parentLevel + 1;
		for (let child in mChildren)
			child.UpdateIndentLevels(mIndentLevel);
	}

	/// Finds the parent TreeView.
	private TreeView FindParentTree()
	{
		var element = Parent;
		while (element != null)
		{
			if (let tree = element as TreeView)
				return tree;
			element = element.Parent;
		}
		return null;
	}

	/// Gets the total height of this item and all visible descendants.
	public float GetTotalHeight()
	{
		var height = cItemHeight;
		if (mIsExpanded)
		{
			for (let child in mChildren)
				height += child.GetTotalHeight();
		}
		return height;
	}

	/// Enumerates all visible items (this item and expanded children).
	public void EnumerateVisible(List<TreeViewItem> outItems)
	{
		outItems.Add(this);
		if (mIsExpanded)
		{
			for (let child in mChildren)
				child.EnumerateVisible(outItems);
		}
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		let fontSize = FontSize;
		var width = mIndentLevel * cIndentWidth + cExpanderSize + 4;

		if (mText != null && mText.Length > 0)
			width += mText.Length * fontSize * 0.6f;

		return .(width, cItemHeight);
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;
		let indent = mIndentLevel * cIndentWidth;

		// Background based on selection/hover state
		if (mIsSelected)
		{
			let selectedBg = theme?.GetColor("TreeItemSelected") ?? theme?.GetColor("ListItemSelected") ?? theme?.GetColor("Selected") ?? Color(51, 51, 51);
			drawContext.FillRect(bounds, selectedBg);
		}
		else if (IsMouseOver)
		{
			let hoverBg = theme?.GetColor("TreeItemHover") ?? theme?.GetColor("ListItemHover") ?? theme?.GetColor("Hover") ?? Color(62, 62, 64);
			drawContext.FillRect(bounds, hoverBg);
		}

		// Expander (triangle or plus/minus)
		if (HasChildren)
		{
			let expanderX = bounds.X + indent + 2;
			let expanderY = bounds.Y + (cItemHeight - cExpanderSize) / 2;
			let arrowColor = theme?.GetColor("TreeExpander") ?? theme?.GetColor("Foreground") ?? Color(200, 200, 200);

			if (mIsExpanded)
			{
				// Down arrow (expanded)
				Vector2[3] downArrow = .(
					.(expanderX + 3, expanderY + 5),
					.(expanderX + cExpanderSize - 3, expanderY + 5),
					.(expanderX + cExpanderSize / 2, expanderY + cExpanderSize - 5)
				);
				drawContext.FillPolygon(downArrow, arrowColor);
			}
			else
			{
				// Right arrow (collapsed)
				Vector2[3] rightArrow = .(
					.(expanderX + 5, expanderY + 3),
					.(expanderX + 5, expanderY + cExpanderSize - 3),
					.(expanderX + cExpanderSize - 3, expanderY + cExpanderSize / 2)
				);
				drawContext.FillPolygon(rightArrow, arrowColor);
			}
		}

		// Text
		if (mText != null && mText.Length > 0)
		{
			let foreground = Foreground ?? theme?.GetColor("Foreground") ?? Color(220, 220, 220);
			let textX = bounds.X + indent + cExpanderSize + 4;
			let textBounds = RectangleF(textX, bounds.Y, bounds.Width - textX + bounds.X, bounds.Height);

			let fontService = GetFontService();
			let cachedFont = fontService?.GetFont(FontFamily, FontSize);

			if (fontService != null && cachedFont != null)
			{
				let font = cachedFont.Font;
				let atlas = cachedFont.Atlas;
				let atlasTexture = fontService.GetAtlasTexture(cachedFont);

				if (atlas != null && atlasTexture != null)
				{
					drawContext.DrawText(mText, font, atlas, atlasTexture, textBounds, .Left, .Middle, foreground);
				}
			}
		}
	}

	protected override void OnMouseEnter()
	{
		base.OnMouseEnter();
		InvalidateVisual();
	}

	protected override void OnMouseLeave()
	{
		base.OnMouseLeave();
		InvalidateVisual();
	}

	/// Gets the font service from the context.
	private IFontService GetFontService()
	{
		let context = Context;
		if (context != null)
		{
			if (context.GetService<IFontService>() case .Ok(let service))
				return service;
		}
		return null;
	}

	/// Checks if a point is in the expander area.
	public bool IsInExpanderArea(float localX)
	{
		let indent = mIndentLevel * cIndentWidth;
		return localX >= indent && localX < indent + cExpanderSize + 4;
	}
}

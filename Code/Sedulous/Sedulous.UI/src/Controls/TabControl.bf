using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Represents a single tab item.
class TabItem : StackPanel
{
	private String mHeader ~ delete _;
	private Widget mContent;
	private bool mIsSelected;
	private bool mIsEnabled = true;
	private Object mTag;

	/// Event raised when selection state changes.
	public Event<delegate void(bool isSelected)> OnSelectionChanged ~ _.Dispose();

	/// Gets or sets the header text.
	public StringView Header
	{
		get => mHeader ?? "";
		set
		{
			String.NewOrSet!(mHeader, value);
			InvalidateMeasure();
		}
	}

	/// Gets or sets the content widget.
	public Widget Content
	{
		get => mContent;
		set => mContent = value;
	}

	/// Gets or sets whether this tab is selected.
	public bool IsSelected
	{
		get => mIsSelected;
		set
		{
			if (mIsSelected != value)
			{
				mIsSelected = value;
				OnSelectionChanged(value);
				InvalidateVisual();
			}
		}
	}

	/// Gets or sets whether this tab is enabled.
	public bool IsTabEnabled
	{
		get => mIsEnabled;
		set
		{
			if (mIsEnabled != value)
			{
				mIsEnabled = value;
				InvalidateVisual();
			}
		}
	}

	/// Gets or sets a custom tag object.
	public Object Tag
	{
		get => mTag;
		set => mTag = value;
	}

	/// Creates a tab item with a header.
	public this(StringView header)
	{
		mHeader = new String(header);
		Orientation = .Vertical;
	}

	/// Creates a tab item with header and content.
	public this(StringView header, Widget content) : this(header)
	{
		mContent = content;
	}
}

/// Tab strip position relative to content.
enum TabStripPlacement
{
	/// Tabs at the top.
	Top,
	/// Tabs at the bottom.
	Bottom,
	/// Tabs on the left.
	Left,
	/// Tabs on the right.
	Right
}

/// A control with multiple tabs, each containing different content.
class TabControl : Widget
{
	private List<TabItem> mTabs = new .() ~ DeleteContainerAndItems!(_);
	private int32 mSelectedIndex = -1;
	private TabStripPlacement mTabPlacement = .Top;

	// Visual properties
	private float mTabHeight = 28;
	private float mTabMinWidth = 60;
	private float mTabPadding = 12;
	private float mTabSpacing = 2;
	private Color mTabStripBackground = Color(40, 40, 40, 255);
	private Color mContentBackground = Color(50, 50, 50, 255);
	private Color mTabBackground = Color(45, 45, 45, 255);
	private Color mTabSelectedBackground = Color(60, 60, 60, 255);
	private Color mTabHoverBackground = Color(55, 55, 55, 255);
	private Color mTabTextColor = Color(180, 180, 180, 255);
	private Color mTabSelectedTextColor = .White;
	private Color mBorderColor = Color(70, 70, 70, 255);
	private FontHandle mFont;
	private float mFontSize = 13;

	// State
	private int32 mHoveredTabIndex = -1;

	/// Event raised when the selected tab changes.
	public Event<delegate void(int32 oldIndex, int32 newIndex)> OnSelectionChanged ~ _.Dispose();

	/// Gets the tabs collection.
	public List<TabItem> Tabs => mTabs;

	/// Gets or sets the selected tab index.
	public int32 SelectedIndex
	{
		get => mSelectedIndex;
		set
		{
			let newIndex = Math.Clamp(value, -1, (int32)mTabs.Count - 1);
			if (mSelectedIndex != newIndex)
			{
				let oldIndex = mSelectedIndex;

				// Deselect old tab
				if (mSelectedIndex >= 0 && mSelectedIndex < mTabs.Count)
					mTabs[mSelectedIndex].IsSelected = false;

				mSelectedIndex = newIndex;

				// Select new tab
				if (mSelectedIndex >= 0 && mSelectedIndex < mTabs.Count)
					mTabs[mSelectedIndex].IsSelected = true;

				OnSelectionChanged(oldIndex, newIndex);
				InvalidateArrange();
			}
		}
	}

	/// Gets the currently selected tab.
	public TabItem SelectedTab
	{
		get => (mSelectedIndex >= 0 && mSelectedIndex < mTabs.Count) ? mTabs[mSelectedIndex] : null;
	}

	/// Gets or sets the tab strip placement.
	public TabStripPlacement TabPlacement
	{
		get => mTabPlacement;
		set
		{
			if (mTabPlacement != value)
			{
				mTabPlacement = value;
				InvalidateMeasure();
			}
		}
	}

	/// Gets or sets the tab height.
	public float TabHeight
	{
		get => mTabHeight;
		set { mTabHeight = value; InvalidateMeasure(); }
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

	/// Adds a new tab.
	public TabItem AddTab(StringView header, Widget content = null)
	{
		let tab = new TabItem(header, content);
		mTabs.Add(tab);

		// Auto-select first tab
		if (mSelectedIndex < 0)
			SelectedIndex = 0;

		InvalidateMeasure();
		return tab;
	}

	/// Removes a tab by index.
	public void RemoveTab(int32 index)
	{
		if (index < 0 || index >= mTabs.Count)
			return;

		let tab = mTabs[index];
		mTabs.RemoveAt(index);
		delete tab;

		// Adjust selection
		if (mSelectedIndex >= mTabs.Count)
			SelectedIndex = (int32)mTabs.Count - 1;
		else if (mSelectedIndex == index)
			SelectedIndex = mSelectedIndex; // Re-trigger selection

		InvalidateMeasure();
	}

	/// Removes all tabs.
	public void ClearTabs()
	{
		for (let tab in mTabs)
			delete tab;
		mTabs.Clear();
		mSelectedIndex = -1;
		InvalidateMeasure();
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		let isHorizontal = (mTabPlacement == .Top || mTabPlacement == .Bottom);
		float tabStripSize = mTabHeight;

		// Measure content
		Vector2 contentSize = .Zero;
		if (SelectedTab?.Content != null)
		{
			let contentAvailable = isHorizontal
				? Vector2(availableSize.X - Padding.HorizontalThickness, availableSize.Y - Padding.VerticalThickness - tabStripSize)
				: Vector2(availableSize.X - Padding.HorizontalThickness - tabStripSize, availableSize.Y - Padding.VerticalThickness);

			SelectedTab.Content.Measure(contentAvailable);
			contentSize = SelectedTab.Content.DesiredSize;
		}

		// Calculate total size
		if (isHorizontal)
		{
			return Vector2(
				contentSize.X + Padding.HorizontalThickness,
				contentSize.Y + tabStripSize + Padding.VerticalThickness
			);
		}
		else
		{
			return Vector2(
				contentSize.X + tabStripSize + Padding.HorizontalThickness,
				contentSize.Y + Padding.VerticalThickness
			);
		}
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		let contentBounds = ContentBounds;

		// Calculate content rect
		RectangleF contentRect;

		switch (mTabPlacement)
		{
		case .Top:
			contentRect = RectangleF(contentBounds.X, contentBounds.Y + mTabHeight, contentBounds.Width, contentBounds.Height - mTabHeight);
		case .Bottom:
			contentRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, contentBounds.Height - mTabHeight);
		case .Left:
			contentRect = RectangleF(contentBounds.X + mTabHeight, contentBounds.Y, contentBounds.Width - mTabHeight, contentBounds.Height);
		case .Right:
			contentRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width - mTabHeight, contentBounds.Height);
		}

		// Arrange selected content
		if (SelectedTab?.Content != null)
		{
			SelectedTab.Content.Arrange(contentRect);
		}
	}

	protected override void OnRender(DrawContext dc)
	{
		let contentBounds = ContentBounds;
		let isHorizontal = (mTabPlacement == .Top || mTabPlacement == .Bottom);

		// Calculate rects
		RectangleF tabStripRect;
		RectangleF contentRect;

		switch (mTabPlacement)
		{
		case .Top:
			tabStripRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, mTabHeight);
			contentRect = RectangleF(contentBounds.X, contentBounds.Y + mTabHeight, contentBounds.Width, contentBounds.Height - mTabHeight);
		case .Bottom:
			tabStripRect = RectangleF(contentBounds.X, contentBounds.Bottom - mTabHeight, contentBounds.Width, mTabHeight);
			contentRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, contentBounds.Height - mTabHeight);
		case .Left:
			tabStripRect = RectangleF(contentBounds.X, contentBounds.Y, mTabHeight, contentBounds.Height);
			contentRect = RectangleF(contentBounds.X + mTabHeight, contentBounds.Y, contentBounds.Width - mTabHeight, contentBounds.Height);
		case .Right:
			tabStripRect = RectangleF(contentBounds.Right - mTabHeight, contentBounds.Y, mTabHeight, contentBounds.Height);
			contentRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width - mTabHeight, contentBounds.Height);
		}

		// Draw tab strip background
		dc.FillRect(tabStripRect, mTabStripBackground);

		// Draw tabs
		float tabOffset = 0;
		for (int32 i = 0; i < mTabs.Count; i++)
		{
			let tab = mTabs[i];
			let isSelected = (i == mSelectedIndex);
			let isHovered = (i == mHoveredTabIndex);

			// Calculate tab width (estimate)
			float tabWidth = mTabMinWidth;
			tabWidth = Math.Max(mTabMinWidth, tab.Header.Length * mFontSize * 0.5f + mTabPadding * 2);

			// Tab rect
			RectangleF tabRect;
			if (isHorizontal)
			{
				tabRect = RectangleF(tabStripRect.X + tabOffset, tabStripRect.Y, tabWidth, mTabHeight);
				tabOffset += tabWidth + mTabSpacing;
			}
			else
			{
				tabRect = RectangleF(tabStripRect.X, tabStripRect.Y + tabOffset, mTabHeight, tabWidth);
				tabOffset += tabWidth + mTabSpacing;
			}

			// Tab background
			Color bgColor = isSelected ? mTabSelectedBackground : (isHovered ? mTabHoverBackground : mTabBackground);
			dc.FillRect(tabRect, bgColor);

			// Tab text
			Color textColor = isSelected ? mTabSelectedTextColor : mTabTextColor;
			dc.DrawText(tab.Header, mFont, mFontSize, tabRect, textColor, .Center, .Center, false);

			// Selection indicator
			if (isSelected)
			{
				switch (mTabPlacement)
				{
				case .Top:
					dc.FillRect(RectangleF(tabRect.X, tabRect.Bottom - 2, tabRect.Width, 2), mTabSelectedTextColor);
				case .Bottom:
					dc.FillRect(RectangleF(tabRect.X, tabRect.Y, tabRect.Width, 2), mTabSelectedTextColor);
				case .Left:
					dc.FillRect(RectangleF(tabRect.Right - 2, tabRect.Y, 2, tabRect.Height), mTabSelectedTextColor);
				case .Right:
					dc.FillRect(RectangleF(tabRect.X, tabRect.Y, 2, tabRect.Height), mTabSelectedTextColor);
				}
			}
		}

		// Draw content background
		dc.FillRect(contentRect, mContentBackground);

		// Draw border
		dc.DrawRect(contentRect, mBorderColor, 1);
	}

	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		let contentBounds = ContentBounds;
		let isHorizontal = (mTabPlacement == .Top || mTabPlacement == .Bottom);

		RectangleF tabStripRect;
		switch (mTabPlacement)
		{
		case .Top:
			tabStripRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, mTabHeight);
		case .Bottom:
			tabStripRect = RectangleF(contentBounds.X, contentBounds.Bottom - mTabHeight, contentBounds.Width, mTabHeight);
		case .Left:
			tabStripRect = RectangleF(contentBounds.X, contentBounds.Y, mTabHeight, contentBounds.Height);
		case .Right:
			tabStripRect = RectangleF(contentBounds.Right - mTabHeight, contentBounds.Y, mTabHeight, contentBounds.Height);
		}

		// Find hovered tab
		int32 newHovered = -1;
		if (tabStripRect.Contains(e.Position))
		{
			float tabOffset = 0;
			for (int32 i = 0; i < mTabs.Count; i++)
			{
				let tab = mTabs[i];
				float tabWidth = Math.Max(mTabMinWidth, tab.Header.Length * mFontSize * 0.5f + mTabPadding * 2);

				RectangleF tabRect;
				if (isHorizontal)
				{
					tabRect = RectangleF(tabStripRect.X + tabOffset, tabStripRect.Y, tabWidth, mTabHeight);
					tabOffset += tabWidth + mTabSpacing;
				}
				else
				{
					tabRect = RectangleF(tabStripRect.X, tabStripRect.Y + tabOffset, mTabHeight, tabWidth);
					tabOffset += tabWidth + mTabSpacing;
				}

				if (tabRect.Contains(e.Position))
				{
					newHovered = i;
					break;
				}
			}
		}

		if (mHoveredTabIndex != newHovered)
		{
			mHoveredTabIndex = newHovered;
			InvalidateVisual();
		}

		return true;
	}

	protected override bool OnMouseLeave(MouseEventArgs e)
	{
		if (mHoveredTabIndex != -1)
		{
			mHoveredTabIndex = -1;
			InvalidateVisual();
		}
		return false;
	}

	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && mHoveredTabIndex >= 0)
		{
			SelectedIndex = mHoveredTabIndex;
			return true;
		}
		return false;
	}
}

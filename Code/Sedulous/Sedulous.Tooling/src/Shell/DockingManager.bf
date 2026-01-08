using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Mathematics;

namespace Sedulous.Tooling;

/// Represents a dock area that can contain panels or split into sub-areas.
class DockArea : Widget
{
	private List<DockArea> mChildren = new .() ~ DeleteContainerAndItems!(_);
	private List<ToolPanel> mPanels = new .() ~ delete _;
	private Orientation mSplitOrientation = .Horizontal;
	private float mSplitPosition = 0.5f;
	private int32 mSelectedTabIndex = 0;
	private int32 mHoveredTabIndex = -1;

	// Visual properties
	private Color mTabBackground = Color(50, 50, 50, 255);
	private Color mTabSelectedBackground = Color(60, 60, 60, 255);
	private Color mTabHoverBackground = Color(55, 55, 55, 255);
	private Color mTabTextColor = Color(180, 180, 180, 255);
	private Color mSplitterColor = Color(40, 40, 40, 255);
	private float mTabHeight = 24;
	private float mSplitterSize = 4;
	private FontHandle mFont;
	private float mFontSize = 11;

	// State
	private bool mIsDraggingSplitter = false;
	private float mDragStartPosition = 0;

	/// Gets the child dock areas.
	public List<DockArea> ChildAreas => mChildren;

	/// Gets the panels in this area.
	public List<ToolPanel> Panels => mPanels;

	/// Gets or sets the split orientation.
	public Orientation SplitOrientation
	{
		get => mSplitOrientation;
		set { mSplitOrientation = value; InvalidateMeasure(); }
	}

	/// Gets or sets the split position (0-1).
	public float SplitPosition
	{
		get => mSplitPosition;
		set
		{
			mSplitPosition = Math.Clamp(value, 0.1f, 0.9f);
			InvalidateArrange();
		}
	}

	/// Gets or sets the selected tab index.
	public int32 SelectedTabIndex
	{
		get => mSelectedTabIndex;
		set
		{
			let newIndex = Math.Clamp(value, 0, (int32)mPanels.Count - 1);
			if (mSelectedTabIndex != newIndex && mPanels.Count > 0)
			{
				// Deactivate old panel
				if (mSelectedTabIndex >= 0 && mSelectedTabIndex < mPanels.Count)
					mPanels[mSelectedTabIndex].[Friend]IsActive = false;

				mSelectedTabIndex = newIndex;

				// Activate new panel
				if (mSelectedTabIndex >= 0 && mSelectedTabIndex < mPanels.Count)
					mPanels[mSelectedTabIndex].[Friend]IsActive = true;

				InvalidateVisual();
			}
		}
	}

	/// Gets the currently selected panel.
	public ToolPanel SelectedPanel
	{
		get => (mSelectedTabIndex >= 0 && mSelectedTabIndex < mPanels.Count) ? mPanels[mSelectedTabIndex] : null;
	}

	/// Gets whether this area is a leaf (contains panels, not child areas).
	public bool IsLeaf => mChildren.Count == 0;

	/// Gets or sets the font.
	public FontHandle Font
	{
		get => mFont;
		set => mFont = value;
	}

	/// Adds a panel to this area.
	public void AddPanel(ToolPanel panel)
	{
		mPanels.Add(panel);
		Children.Add(panel);
		panel.OnClosed.Add(new () => { RemovePanel(panel); });

		if (mPanels.Count == 1)
		{
			mSelectedTabIndex = 0;
			panel.[Friend]IsActive = true;
		}

		InvalidateMeasure();
	}

	/// Removes a panel from this area.
	public void RemovePanel(ToolPanel panel)
	{
		let index = mPanels.IndexOf(panel);
		if (index < 0)
			return;

		mPanels.Remove(panel);
		Children.Remove(panel);

		if (mSelectedTabIndex >= mPanels.Count)
			mSelectedTabIndex = (int32)mPanels.Count - 1;

		if (mSelectedTabIndex >= 0 && mSelectedTabIndex < mPanels.Count)
			mPanels[mSelectedTabIndex].[Friend]IsActive = true;

		InvalidateMeasure();
	}

	/// Splits this area and moves content to the specified side.
	public DockArea Split(DockPosition position, ToolPanel newPanel)
	{
		if (position == .Center)
		{
			AddPanel(newPanel);
			return this;
		}

		// Create new child areas
		let existingArea = new DockArea();
		let newArea = new DockArea();

		// Move existing panels to existing area
		for (let panel in mPanels)
		{
			existingArea.mPanels.Add(panel);
			existingArea.Children.Add(panel);
			Children.Remove(panel);
		}
		mPanels.Clear();
		existingArea.mSelectedTabIndex = mSelectedTabIndex;

		// Add new panel to new area
		newArea.AddPanel(newPanel);

		// Setup split
		switch (position)
		{
		case .Left:
			mSplitOrientation = .Horizontal;
			mChildren.Add(newArea);
			mChildren.Add(existingArea);
			mSplitPosition = 0.25f;
		case .Right:
			mSplitOrientation = .Horizontal;
			mChildren.Add(existingArea);
			mChildren.Add(newArea);
			mSplitPosition = 0.75f;
		case .Top:
			mSplitOrientation = .Vertical;
			mChildren.Add(newArea);
			mChildren.Add(existingArea);
			mSplitPosition = 0.25f;
		case .Bottom:
			mSplitOrientation = .Vertical;
			mChildren.Add(existingArea);
			mChildren.Add(newArea);
			mSplitPosition = 0.75f;
		default:
		}

		Children.Add(newArea);
		Children.Add(existingArea);

		InvalidateMeasure();
		return newArea;
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		if (!IsLeaf)
		{
			// Measure child areas
			for (let child in mChildren)
			{
				child.Measure(availableSize);
			}
		}
		else if (mPanels.Count > 0)
		{
			// Measure selected panel
			let contentAvailable = Vector2(availableSize.X, availableSize.Y - mTabHeight);
			for (let panel in mPanels)
			{
				panel.Measure(contentAvailable);
			}
		}

		return availableSize;
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		let contentBounds = ContentBounds;

		if (!IsLeaf && mChildren.Count >= 2)
		{
			// Arrange split areas
			if (mSplitOrientation == .Horizontal)
			{
				let splitX = contentBounds.X + contentBounds.Width * mSplitPosition;
				let leftWidth = splitX - contentBounds.X - mSplitterSize / 2;
				let rightX = splitX + mSplitterSize / 2;
				let rightWidth = contentBounds.Right - rightX;

				mChildren[0].Arrange(RectangleF(contentBounds.X, contentBounds.Y, leftWidth, contentBounds.Height));
				mChildren[1].Arrange(RectangleF(rightX, contentBounds.Y, rightWidth, contentBounds.Height));
			}
			else
			{
				let splitY = contentBounds.Y + contentBounds.Height * mSplitPosition;
				let topHeight = splitY - contentBounds.Y - mSplitterSize / 2;
				let bottomY = splitY + mSplitterSize / 2;
				let bottomHeight = contentBounds.Bottom - bottomY;

				mChildren[0].Arrange(RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, topHeight));
				mChildren[1].Arrange(RectangleF(contentBounds.X, bottomY, contentBounds.Width, bottomHeight));
			}
		}
		else if (mPanels.Count > 0)
		{
			// Arrange panels below tab strip
			let panelRect = RectangleF(
				contentBounds.X,
				contentBounds.Y + mTabHeight,
				contentBounds.Width,
				contentBounds.Height - mTabHeight
			);

			for (let panel in mPanels)
			{
				panel.Arrange(panelRect);
			}
		}
	}

	protected override void OnRender(DrawContext dc)
	{
		let contentBounds = ContentBounds;

		if (!IsLeaf && mChildren.Count >= 2)
		{
			// Draw splitter
			RectangleF splitterRect;
			if (mSplitOrientation == .Horizontal)
			{
				let splitX = contentBounds.X + contentBounds.Width * mSplitPosition - mSplitterSize / 2;
				splitterRect = RectangleF(splitX, contentBounds.Y, mSplitterSize, contentBounds.Height);
			}
			else
			{
				let splitY = contentBounds.Y + contentBounds.Height * mSplitPosition - mSplitterSize / 2;
				splitterRect = RectangleF(contentBounds.X, splitY, contentBounds.Width, mSplitterSize);
			}
			dc.FillRect(splitterRect, mSplitterColor);

			// Render child areas
			for (let child in mChildren)
			{
				child.Render(dc);
			}
		}
		else if (mPanels.Count > 0)
		{
			// Draw tab strip
			let tabStripRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, mTabHeight);
			dc.FillRect(tabStripRect, mTabBackground);

			// Draw tabs
			float tabX = tabStripRect.X;
			for (int32 i = 0; i < mPanels.Count; i++)
			{
				let panel = mPanels[i];
				let tabWidth = Math.Max(60, panel.Title.Length * mFontSize * 0.5f + 24);
				let tabRect = RectangleF(tabX, tabStripRect.Y, tabWidth, mTabHeight);

				// Tab background
				if (i == mSelectedTabIndex)
					dc.FillRect(tabRect, mTabSelectedBackground);
				else if (i == mHoveredTabIndex)
					dc.FillRect(tabRect, mTabHoverBackground);

				// Tab icon
				float textX = tabRect.X + 6;
				if (panel.Icon.Value != 0)
				{
					let iconSize = mTabHeight - 8;
					let iconY = tabRect.Y + (mTabHeight - iconSize) / 2;
					dc.DrawImage(panel.Icon, RectangleF(textX, iconY, iconSize, iconSize), Color.White);
					textX += iconSize + 4;
				}

				// Tab text
				let titleRect = RectangleF(textX, tabRect.Y, tabRect.Width - (textX - tabRect.X) - 4, mTabHeight);
				dc.DrawText(panel.Title, mFont, mFontSize, titleRect, mTabTextColor, .Start, .Center, false);

				tabX += tabWidth + 1;
			}

			// Render selected panel
			if (SelectedPanel != null)
			{
				SelectedPanel.Render(dc);
			}
		}
	}

	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		if (mIsDraggingSplitter)
		{
			let contentBounds = ContentBounds;
			if (mSplitOrientation == .Horizontal)
				SplitPosition = (e.Position.X - contentBounds.X) / contentBounds.Width;
			else
				SplitPosition = (e.Position.Y - contentBounds.Y) / contentBounds.Height;
			return true;
		}

		// Tab hover
		if (IsLeaf && mPanels.Count > 1)
		{
			let contentBounds = ContentBounds;
			let tabStripRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, mTabHeight);

			if (tabStripRect.Contains(e.Position))
			{
				float tabX = tabStripRect.X;
				int32 newHovered = -1;

				for (int32 i = 0; i < mPanels.Count; i++)
				{
					let panel = mPanels[i];
					let tabWidth = Math.Max(60, panel.Title.Length * mFontSize * 0.5f + 24);
					let tabRect = RectangleF(tabX, tabStripRect.Y, tabWidth, mTabHeight);

					if (tabRect.Contains(e.Position))
					{
						newHovered = i;
						break;
					}
					tabX += tabWidth + 1;
				}

				if (mHoveredTabIndex != newHovered)
				{
					mHoveredTabIndex = newHovered;
					InvalidateVisual();
				}
				return true;
			}
		}

		return false;
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
		if (e.Button != .Left)
			return false;

		let contentBounds = ContentBounds;

		// Check splitter click
		if (!IsLeaf && mChildren.Count >= 2)
		{
			RectangleF splitterRect;
			if (mSplitOrientation == .Horizontal)
			{
				let splitX = contentBounds.X + contentBounds.Width * mSplitPosition - mSplitterSize / 2;
				splitterRect = RectangleF(splitX - 2, contentBounds.Y, mSplitterSize + 4, contentBounds.Height);
			}
			else
			{
				let splitY = contentBounds.Y + contentBounds.Height * mSplitPosition - mSplitterSize / 2;
				splitterRect = RectangleF(contentBounds.X, splitY - 2, contentBounds.Width, mSplitterSize + 4);
			}

			if (splitterRect.Contains(e.Position))
			{
				mIsDraggingSplitter = true;
				return true;
			}
		}

		// Tab click
		if (IsLeaf && mPanels.Count > 0)
		{
			let tabStripRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, mTabHeight);

			if (tabStripRect.Contains(e.Position))
			{
				float tabX = tabStripRect.X;
				for (int32 i = 0; i < mPanels.Count; i++)
				{
					let panel = mPanels[i];
					let tabWidth = Math.Max(60, panel.Title.Length * mFontSize * 0.5f + 24);
					let tabRect = RectangleF(tabX, tabStripRect.Y, tabWidth, mTabHeight);

					if (tabRect.Contains(e.Position))
					{
						SelectedTabIndex = i;
						return true;
					}
					tabX += tabWidth + 1;
				}
			}
		}

		return false;
	}

	protected override bool OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && mIsDraggingSplitter)
		{
			mIsDraggingSplitter = false;
			return true;
		}
		return false;
	}
}

/// Manages dockable panels within a window.
class DockingManager : Widget
{
	private DockArea mRootArea = new .() ~ delete _;
	private List<ToolPanel> mFloatingPanels = new .() ~ delete _;
	private ToolPanel mActivePanel;

	/// Gets the root dock area.
	public DockArea RootArea => mRootArea;

	/// Gets the floating panels.
	public List<ToolPanel> FloatingPanels => mFloatingPanels;

	/// Gets or sets the currently active panel.
	public ToolPanel ActivePanel
	{
		get => mActivePanel;
		set
		{
			if (mActivePanel != value)
			{
				if (mActivePanel != null)
					mActivePanel.[Friend]IsActive = false;
				mActivePanel = value;
				if (mActivePanel != null)
					mActivePanel.[Friend]IsActive = true;
			}
		}
	}

	public this()
	{
		Children.Add(mRootArea);
	}

	/// Docks a panel at the specified position.
	public void Dock(ToolPanel panel, DockPosition position)
	{
		if (mRootArea.Panels.Count == 0 && mRootArea.ChildAreas.Count == 0)
		{
			mRootArea.AddPanel(panel);
		}
		else
		{
			mRootArea.Split(position, panel);
		}
		InvalidateMeasure();
	}

	/// Docks a panel relative to another panel.
	public void DockTo(ToolPanel panel, ToolPanel target, DockPosition position)
	{
		let targetArea = FindAreaContaining(target);
		if (targetArea != null)
		{
			if (position == .Center)
			{
				targetArea.AddPanel(panel);
			}
			else
			{
				targetArea.Split(position, panel);
			}
		}
		else
		{
			Dock(panel, position);
		}
		InvalidateMeasure();
	}

	/// Floats a panel in a separate window area.
	public void Float(ToolPanel panel, RectangleF bounds)
	{
		// Remove from current dock area
		let area = FindAreaContaining(panel);
		if (area != null)
			area.RemovePanel(panel);

		mFloatingPanels.Add(panel);
		// Note: Actual floating window management would require shell integration
	}

	/// Closes a panel.
	public void Close(ToolPanel panel)
	{
		let area = FindAreaContaining(panel);
		if (area != null)
		{
			area.RemovePanel(panel);
		}
		else
		{
			mFloatingPanels.Remove(panel);
		}
	}

	/// Finds the dock area containing the specified panel.
	public DockArea FindAreaContaining(ToolPanel panel)
	{
		return FindAreaContainingRecursive(mRootArea, panel);
	}

	private DockArea FindAreaContainingRecursive(DockArea area, ToolPanel panel)
	{
		if (area.Panels.Contains(panel))
			return area;

		for (let child in area.ChildAreas)
		{
			let result = FindAreaContainingRecursive(child, panel);
			if (result != null)
				return result;
		}

		return null;
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		mRootArea.Measure(availableSize);
		return availableSize;
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		mRootArea.Arrange(ContentBounds);
	}

	protected override void OnRender(DrawContext dc)
	{
		mRootArea.Render(dc);
	}
}

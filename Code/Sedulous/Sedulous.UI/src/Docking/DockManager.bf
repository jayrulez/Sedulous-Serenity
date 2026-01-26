using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// Manages dockable panel layout with dock zones and floating panels.
public class DockManager : CompositeControl
{
	// Theming support (since we don't extend Control)
	private Color? mBackground;

	/// Background color.
	public Color? Background
	{
		get => mBackground;
		set { mBackground = value; InvalidateVisual(); }
	}

	private ITheme GetTheme()
	{
		let context = Context;
		if (context != null)
		{
			if (context.GetService<ITheme>() case .Ok(let theme))
				return theme;
		}
		return null;
	}

	private UIElement mCenterContent;
	private DockablePanel mLeftPanel;
	private DockablePanel mRightPanel;
	private DockablePanel mTopPanel;
	private DockablePanel mBottomPanel;
	private List<DockablePanel> mFloatingPanels = new .() ~ delete _;
	private Dictionary<DockablePanel, Vector2> mFloatingPositions = new .() ~ delete _;

	private Splitter mLeftSplitter;
	private Splitter mRightSplitter;
	private Splitter mTopSplitter;
	private Splitter mBottomSplitter;

	private float mLeftWidth = 100;
	private float mRightWidth = 100;
	private float mTopHeight = 80;
	private float mBottomHeight = 80;

	private DockZone mDragPreviewZone = .None;
	private DockablePanel mDraggingPanel;

	/// The main content area in the center.
	public UIElement CenterContent
	{
		get => mCenterContent;
		set
		{
			if (mCenterContent != value)
			{
				if (mCenterContent != null)
					RemoveChild(mCenterContent);

				mCenterContent = value;

				if (mCenterContent != null)
					AddChild(mCenterContent);

				InvalidateMeasure();
			}
		}
	}

	/// Panel docked to the left edge.
	public DockablePanel LeftPanel => mLeftPanel;

	/// Panel docked to the right edge.
	public DockablePanel RightPanel => mRightPanel;

	/// Panel docked to the top edge.
	public DockablePanel TopPanel => mTopPanel;

	/// Panel docked to the bottom edge.
	public DockablePanel BottomPanel => mBottomPanel;

	/// All floating panels.
	public List<DockablePanel> FloatingPanels => mFloatingPanels;

	/// Minimum size for the center content area.
	private const float MinCenterSize = 50;
	/// Minimum size for docked panels.
	private const float MinPanelSize = 50;
	/// Splitter thickness for calculations.
	private const float SplitterSize = 6;

	/// Width of the left dock zone.
	public float LeftWidth
	{
		get => mLeftWidth;
		set
		{
			let bounds = Bounds;
			if (bounds.Width > 0)
			{
				// Calculate available space for this panel
				var maxWidth = bounds.Width - MinCenterSize - SplitterSize;
				if (mRightPanel != null)
					maxWidth -= mRightWidth + SplitterSize;
				mLeftWidth = Math.Clamp(value, MinPanelSize, Math.Max(MinPanelSize, maxWidth));
			}
			else
			{
				mLeftWidth = Math.Max(MinPanelSize, value);
			}
			InvalidateArrange();
		}
	}

	/// Width of the right dock zone.
	public float RightWidth
	{
		get => mRightWidth;
		set
		{
			let bounds = Bounds;
			if (bounds.Width > 0)
			{
				var maxWidth = bounds.Width - MinCenterSize - SplitterSize;
				if (mLeftPanel != null)
					maxWidth -= mLeftWidth + SplitterSize;
				mRightWidth = Math.Clamp(value, MinPanelSize, Math.Max(MinPanelSize, maxWidth));
			}
			else
			{
				mRightWidth = Math.Max(MinPanelSize, value);
			}
			InvalidateArrange();
		}
	}

	/// Height of the top dock zone.
	public float TopHeight
	{
		get => mTopHeight;
		set
		{
			let bounds = Bounds;
			if (bounds.Height > 0)
			{
				var maxHeight = bounds.Height - MinCenterSize - SplitterSize;
				if (mBottomPanel != null)
					maxHeight -= mBottomHeight + SplitterSize;
				mTopHeight = Math.Clamp(value, MinPanelSize, Math.Max(MinPanelSize, maxHeight));
			}
			else
			{
				mTopHeight = Math.Max(MinPanelSize, value);
			}
			InvalidateArrange();
		}
	}

	/// Height of the bottom dock zone.
	public float BottomHeight
	{
		get => mBottomHeight;
		set
		{
			let bounds = Bounds;
			if (bounds.Height > 0)
			{
				var maxHeight = bounds.Height - MinCenterSize - SplitterSize;
				if (mTopPanel != null)
					maxHeight -= mTopHeight + SplitterSize;
				mBottomHeight = Math.Clamp(value, MinPanelSize, Math.Max(MinPanelSize, maxHeight));
			}
			else
			{
				mBottomHeight = Math.Max(MinPanelSize, value);
			}
			InvalidateArrange();
		}
	}

	public ~this()
	{
		// Delete splitters that are NOT children (they would be double-deleted otherwise)
		// If splitter's parent is this, it's a child and will be deleted by base class
		if (mLeftSplitter != null && mLeftSplitter.Parent != this)
			delete mLeftSplitter;
		if (mRightSplitter != null && mRightSplitter.Parent != this)
			delete mRightSplitter;
		if (mTopSplitter != null && mTopSplitter.Parent != this)
			delete mTopSplitter;
		if (mBottomSplitter != null && mBottomSplitter.Parent != this)
			delete mBottomSplitter;
	}

	public this()
	{
		ClipToBounds = true;

		// Create splitters
		mLeftSplitter = new Splitter();
		mLeftSplitter.Orientation = .Horizontal;
		mLeftSplitter.SplitterMoved.Subscribe(new (s, d) => { LeftWidth += d; });

		mRightSplitter = new Splitter();
		mRightSplitter.Orientation = .Horizontal;
		mRightSplitter.SplitterMoved.Subscribe(new (s, d) => { RightWidth -= d; });

		mTopSplitter = new Splitter();
		mTopSplitter.Orientation = .Vertical;
		mTopSplitter.SplitterMoved.Subscribe(new (s, d) => { TopHeight += d; });

		mBottomSplitter = new Splitter();
		mBottomSplitter.Orientation = .Vertical;
		mBottomSplitter.SplitterMoved.Subscribe(new (s, d) => { BottomHeight -= d; });
	}

	/// Docks a panel to the specified zone.
	public void Dock(DockablePanel panel, DockZone zone)
	{
		if (panel == null)
			return;

		// Capture panel's requested size before resetting (if it was explicitly set)
		float requestedWidth = panel.Width.IsFixed ? panel.Width.Value : 0;
		float requestedHeight = panel.Height.IsFixed ? panel.Height.Value : 0;

		// Remove panel from its current location
		UndockPanel(panel);

		// Reset size constraints so panel fills dock zone
		panel.Width = .Auto;
		panel.Height = .Auto;
		panel.Margin = Thickness(0);
		panel.HorizontalAlignment = .Stretch;
		panel.VerticalAlignment = .Stretch;

		// Undock existing panel in the target zone (if any)
		switch (zone)
		{
		case .Left:
			if (mLeftPanel != null && mLeftPanel != panel)
				UndockPanel(mLeftPanel);
			// Use panel's requested width if set
			if (requestedWidth > 0)
				mLeftWidth = requestedWidth;
		case .Right:
			if (mRightPanel != null && mRightPanel != panel)
				UndockPanel(mRightPanel);
			if (requestedWidth > 0)
				mRightWidth = requestedWidth;
		case .Top:
			if (mTopPanel != null && mTopPanel != panel)
				UndockPanel(mTopPanel);
			if (requestedHeight > 0)
				mTopHeight = requestedHeight;
		case .Bottom:
			if (mBottomPanel != null && mBottomPanel != panel)
				UndockPanel(mBottomPanel);
			if (requestedHeight > 0)
				mBottomHeight = requestedHeight;
		default:
		}

		switch (zone)
		{
		case .Left:
			mLeftPanel = panel;
			panel.DockZone = zone;
			AddChild(panel);
			AddChild(mLeftSplitter);

		case .Right:
			mRightPanel = panel;
			panel.DockZone = zone;
			AddChild(panel);
			AddChild(mRightSplitter);

		case .Top:
			mTopPanel = panel;
			panel.DockZone = zone;
			AddChild(panel);
			AddChild(mTopSplitter);

		case .Bottom:
			mBottomPanel = panel;
			panel.DockZone = zone;
			AddChild(panel);
			AddChild(mBottomSplitter);

		case .Float:
			panel.DockZone = zone;
			mFloatingPanels.Add(panel);
			AddChild(panel);
			SetupFloatingPanel(panel);

		case .Center, .None:
			// Can't dock to center or none
		}

		InvalidateMeasure();
	}

	/// Undocks a panel from its current location.
	public void UndockPanel(DockablePanel panel)
	{
		if (panel == null)
			return;

		if (panel == mLeftPanel)
		{
			RemoveChild(mLeftSplitter);
			RemoveChild(panel);
			mLeftPanel = null;
		}
		else if (panel == mRightPanel)
		{
			RemoveChild(mRightSplitter);
			RemoveChild(panel);
			mRightPanel = null;
		}
		else if (panel == mTopPanel)
		{
			RemoveChild(mTopSplitter);
			RemoveChild(panel);
			mTopPanel = null;
		}
		else if (panel == mBottomPanel)
		{
			RemoveChild(mBottomSplitter);
			RemoveChild(panel);
			mBottomPanel = null;
		}
		else if (mFloatingPanels.Contains(panel))
		{
			mFloatingPanels.Remove(panel);
			mFloatingPositions.Remove(panel);
			RemoveChild(panel);
		}

		panel.DockZone = .None;
		InvalidateMeasure();
	}

	/// Makes a panel float at the specified position.
	public void Float(DockablePanel panel, float x, float y)
	{
		// Capture current size before undocking
		let currentBounds = panel.Bounds;
		let floatWidth = currentBounds.Width > 0 ? currentBounds.Width : 250;
		let floatHeight = currentBounds.Height > 0 ? currentBounds.Height : 200;

		UndockPanel(panel);
		panel.DockZone = .Float;
		mFloatingPanels.Add(panel);
		AddChild(panel);
		SetupFloatingPanel(panel);

		// Set explicit size for floating panel
		panel.Width = .Fixed(floatWidth);
		panel.Height = .Fixed(floatHeight);

		// Track position separately (don't use Margin for positioning)
		panel.Margin = Thickness(0);
		panel.HorizontalAlignment = .Left;
		panel.VerticalAlignment = .Top;
		mFloatingPositions[panel] = .(x, y);

		InvalidateMeasure();
	}

	/// Closes and removes a panel.
	public void ClosePanel(DockablePanel panel)
	{
		UndockPanel(panel);
	}

	private void SetupFloatingPanel(DockablePanel panel)
	{
		// Subscribe to drag events for moving floating panels
		panel.Dragging.Subscribe(new [=](p, dx, dy) =>
		{
			if (p.IsFloating && mFloatingPositions.TryGetValue(p, let pos))
			{
				let newPos = Vector2(pos.X + dx, pos.Y + dy);
				mFloatingPositions[p] = newPos;
				InvalidateArrange();

				// Check for dock zone preview
				UpdateDragPreview(p, newPos.X, newPos.Y);
			}
		});

		panel.DragEnded.Subscribe(new [=](p) =>
		{
			// Check if should dock
			if (mDragPreviewZone != .None && mDragPreviewZone != .Float)
			{
				Dock(p, mDragPreviewZone);
			}
			mDragPreviewZone = .None;
			mDraggingPanel = null;
			InvalidateVisual();
		});

		panel.DragStarted.Subscribe(new [=](p, x, y) =>
		{
			mDraggingPanel = p;
		});
	}

	private void UpdateDragPreview(DockablePanel panel, float x, float y)
	{
		let bounds = Bounds;
		let edgeThreshold = 50f;

		mDragPreviewZone = .None;

		// Check which edge we're near
		if (x < edgeThreshold && mLeftPanel == null)
			mDragPreviewZone = .Left;
		else if (x > bounds.Width - edgeThreshold && mRightPanel == null)
			mDragPreviewZone = .Right;
		else if (y < edgeThreshold && mTopPanel == null)
			mDragPreviewZone = .Top;
		else if (y > bounds.Height - edgeThreshold && mBottomPanel == null)
			mDragPreviewZone = .Bottom;

		InvalidateVisual();
	}

	/// Gets the dock zone at the specified position.
	public DockZone GetDockZoneAt(float x, float y)
	{
		let bounds = Bounds;
		let edgeThreshold = 50f;

		if (x - bounds.X < edgeThreshold && mLeftPanel == null)
			return .Left;
		if (bounds.Right - x < edgeThreshold && mRightPanel == null)
			return .Right;
		if (y - bounds.Y < edgeThreshold && mTopPanel == null)
			return .Top;
		if (bounds.Bottom - y < edgeThreshold && mBottomPanel == null)
			return .Bottom;

		return .None;
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Measure all docked panels
		if (mLeftPanel != null)
			mLeftPanel.Measure(SizeConstraints.FromMaximum(mLeftWidth, constraints.MaxHeight));

		if (mRightPanel != null)
			mRightPanel.Measure(SizeConstraints.FromMaximum(mRightWidth, constraints.MaxHeight));

		if (mTopPanel != null)
			mTopPanel.Measure(SizeConstraints.FromMaximum(constraints.MaxWidth, mTopHeight));

		if (mBottomPanel != null)
			mBottomPanel.Measure(SizeConstraints.FromMaximum(constraints.MaxWidth, mBottomHeight));

		// Measure splitters
		if (mLeftPanel != null)
			mLeftSplitter.Measure(constraints);
		if (mRightPanel != null)
			mRightSplitter.Measure(constraints);
		if (mTopPanel != null)
			mTopSplitter.Measure(constraints);
		if (mBottomPanel != null)
			mBottomSplitter.Measure(constraints);

		// Measure center content
		if (mCenterContent != null)
		{
			var centerWidth = constraints.MaxWidth;
			var centerHeight = constraints.MaxHeight;

			if (mLeftPanel != null)
				centerWidth -= mLeftWidth + mLeftSplitter.SplitterThickness;
			if (mRightPanel != null)
				centerWidth -= mRightWidth + mRightSplitter.SplitterThickness;
			if (mTopPanel != null)
				centerHeight -= mTopHeight + mTopSplitter.SplitterThickness;
			if (mBottomPanel != null)
				centerHeight -= mBottomHeight + mBottomSplitter.SplitterThickness;

			mCenterContent.Measure(SizeConstraints.FromMaximum(centerWidth, centerHeight));
		}

		// Measure floating panels (they have explicit Width/Height set, so use full constraints)
		for (let panel in mFloatingPanels)
			panel.Measure(constraints);

		return .(constraints.MaxWidth, constraints.MaxHeight);
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		var left = contentBounds.X;
		var top = contentBounds.Y;
		var right = contentBounds.Right;
		var bottom = contentBounds.Bottom;
		let splitterSize = 6f;

		// Arrange left panel and splitter
		if (mLeftPanel != null)
		{
			mLeftPanel.Arrange(RectangleF(left, top, mLeftWidth, bottom - top));
			left += mLeftWidth;

			mLeftSplitter.Arrange(RectangleF(left, top, splitterSize, bottom - top));
			left += splitterSize;
		}

		// Arrange right panel and splitter
		if (mRightPanel != null)
		{
			// Panel at the right edge
			mRightPanel.Arrange(RectangleF(right - mRightWidth, top, mRightWidth, bottom - top));
			right -= mRightWidth;

			// Splitter to the left of the panel
			mRightSplitter.Arrange(RectangleF(right - splitterSize, top, splitterSize, bottom - top));
			right -= splitterSize;
		}

		// Arrange top panel and splitter
		if (mTopPanel != null)
		{
			mTopPanel.Arrange(RectangleF(left, top, right - left, mTopHeight));
			top += mTopHeight;

			mTopSplitter.Arrange(RectangleF(left, top, right - left, splitterSize));
			top += splitterSize;
		}

		// Arrange bottom panel and splitter
		if (mBottomPanel != null)
		{
			// Panel at the bottom edge
			mBottomPanel.Arrange(RectangleF(left, bottom - mBottomHeight, right - left, mBottomHeight));
			bottom -= mBottomHeight;

			// Splitter above the panel
			mBottomSplitter.Arrange(RectangleF(left, bottom - splitterSize, right - left, splitterSize));
			bottom -= splitterSize;
		}

		// Arrange center content
		if (mCenterContent != null)
		{
			mCenterContent.Arrange(RectangleF(left, top, right - left, bottom - top));
		}

		// Arrange floating panels using tracked positions
		for (let panel in mFloatingPanels)
		{
			let size = panel.DesiredSize;
			if (mFloatingPositions.TryGetValue(panel, let pos))
				panel.Arrange(RectangleF(pos.X, pos.Y, size.Width, size.Height));
			else
				panel.Arrange(RectangleF(0, 0, size.Width, size.Height));
		}
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		// Background
		let bg = Background ?? theme?.GetColor("Background") ?? Color(240, 240, 240);
		drawContext.FillRect(bounds, bg);

		// Draw dock zone preview during drag
		if (mDragPreviewZone != .None && mDraggingPanel != null)
		{
			let previewColor = theme?.GetColor("DockZonePreview") ?? Color(0, 120, 215, 80);
			var previewBounds = RectangleF.Empty;

			switch (mDragPreviewZone)
			{
			case .Left:
				previewBounds = RectangleF(bounds.X, bounds.Y, mLeftWidth, bounds.Height);
			case .Right:
				previewBounds = RectangleF(bounds.Right - mRightWidth, bounds.Y, mRightWidth, bounds.Height);
			case .Top:
				previewBounds = RectangleF(bounds.X, bounds.Y, bounds.Width, mTopHeight);
			case .Bottom:
				previewBounds = RectangleF(bounds.X, bounds.Bottom - mBottomHeight, bounds.Width, mBottomHeight);
			default:
			}

			if (!previewBounds.IsEmpty)
				drawContext.FillRect(previewBounds, previewColor);
		}

		// Render children (panels, splitters, floating panels)
		base.OnRender(drawContext);
	}
}

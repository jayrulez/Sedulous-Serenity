using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.GUI;

/// A panel that can be docked, floated, or tabbed within a DockManager.
/// Has a title bar with close and optional pin buttons.
public class DockablePanel : Control, IDragSource, IDropTarget
{
	private String mTitle ~ delete _;
	private UIElement mContent ~ delete _;
	private bool mIsCloseable = true;
	private bool mIsPinnable = false;
	private bool mIsPinned = false;
	private bool mIsCloseHovered = false;
	private bool mIsPinHovered = false;

	// Title bar layout
	private float mTitleBarHeight = 24;
	private RectangleF mTitleBarBounds;
	private RectangleF mCloseBounds;
	private RectangleF mPinBounds;
	private RectangleF mContentBounds;

	// Drag state
	private bool mDragPending = false;
	private Vector2 mDragStartPos;

	// Events
	private EventAccessor<delegate void(DockablePanel)> mCloseRequested = new .() ~ delete _;
	private EventAccessor<delegate void(DockablePanel)> mPinToggled = new .() ~ delete _;

	// Parent reference (set by DockTabGroup)
	public DockTabGroup ParentGroup;

	/// Creates a new DockablePanel.
	public this()
	{
		IsFocusable = false;
		IsTabStop = false;
	}

	/// Creates a new DockablePanel with a title.
	public this(StringView title) : this()
	{
		Title = title;
	}

	/// Creates a new DockablePanel with a title and content.
	public this(StringView title, UIElement content) : this()
	{
		Title = title;
		Content = content;
	}

	/// The control type name for theming.
	protected override StringView ControlTypeName => "DockablePanel";

	/// The panel title displayed in the title bar.
	public StringView Title
	{
		get => mTitle ?? "";
		set
		{
			if (mTitle == null)
				mTitle = new String();
			mTitle.Set(value);
			InvalidateLayout();
		}
	}

	/// The content element displayed in the panel.
	public UIElement Content
	{
		get => mContent;
		set
		{
			if (mContent != null)
			{
				mContent.SetParent(null);
				mContent.OnDetachedFromContext();
				delete mContent;
			}
			mContent = value;
			if (mContent != null)
			{
				mContent.SetParent(this);
				if (Context != null)
					mContent.OnAttachedToContext(Context);
			}
			InvalidateLayout();
		}
	}

	/// Whether the panel can be closed.
	public bool IsCloseable
	{
		get => mIsCloseable;
		set => mIsCloseable = value;
	}

	/// Whether the panel shows a pin button.
	public bool IsPinnable
	{
		get => mIsPinnable;
		set => mIsPinnable = value;
	}

	/// Whether the panel is pinned (auto-hide when unpinned).
	public bool IsPinned
	{
		get => mIsPinned;
		set
		{
			if (mIsPinned != value)
			{
				mIsPinned = value;
				mPinToggled.[Friend]Invoke(this);
			}
		}
	}

	/// Height of the title bar.
	public float TitleBarHeight
	{
		get => mTitleBarHeight;
		set
		{
			if (mTitleBarHeight != value)
			{
				mTitleBarHeight = value;
				InvalidateLayout();
			}
		}
	}

	/// Event fired when the close button is clicked.
	public EventAccessor<delegate void(DockablePanel)> CloseRequested => mCloseRequested;

	/// Event fired when the pin state is toggled.
	public EventAccessor<delegate void(DockablePanel)> PinToggled => mPinToggled;

	/// The title bar bounds (for drag detection).
	public RectangleF TitleBarBounds => mTitleBarBounds;

	// === Context ===

	public override void OnAttachedToContext(GUIContext context)
	{
		base.OnAttachedToContext(context);
		if (mContent != null)
			mContent.OnAttachedToContext(context);
	}

	public override void OnDetachedFromContext()
	{
		if (mContent != null)
			mContent.OnDetachedFromContext();
		base.OnDetachedFromContext();
	}

	// === Layout ===

	/// Returns true if the title bar should be shown.
	/// Title bar is hidden when the panel is in a tab group with multiple panels (tabs show the title instead).
	private bool ShouldShowTitleBar => ParentGroup == null || ParentGroup.IsSinglePanel;

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		float contentWidth = 0;
		float contentHeight = 0;

		if (mContent != null && mContent.Visibility != .Collapsed)
		{
			mContent.Measure(constraints);
			let contentSize = mContent.DesiredSize;
			contentWidth = contentSize.Width;
			contentHeight = contentSize.Height;
		}

		// Add title bar height only if showing title bar
		if (ShouldShowTitleBar)
			return .(contentWidth, contentHeight + mTitleBarHeight);
		else
			return .(contentWidth, contentHeight);
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		let showTitleBar = ShouldShowTitleBar;

		if (showTitleBar)
		{
			// Title bar at top
			mTitleBarBounds = .(contentBounds.X, contentBounds.Y, contentBounds.Width, mTitleBarHeight);

			// Button layout (right side of title bar)
			float buttonSize = mTitleBarHeight - 4;
			float buttonY = contentBounds.Y + 2;
			float buttonX = contentBounds.Right - buttonSize - 4;

			if (mIsCloseable)
			{
				mCloseBounds = .(buttonX, buttonY, buttonSize, buttonSize);
				buttonX -= buttonSize + 2;
			}
			else
			{
				mCloseBounds = .(0, 0, 0, 0);
			}

			if (mIsPinnable)
			{
				mPinBounds = .(buttonX, buttonY, buttonSize, buttonSize);
			}
			else
			{
				mPinBounds = .(0, 0, 0, 0);
			}

			// Content below title bar
			mContentBounds = .(
				contentBounds.X,
				contentBounds.Y + mTitleBarHeight,
				contentBounds.Width,
				contentBounds.Height - mTitleBarHeight
			);
		}
		else
		{
			// No title bar - full area for content
			mTitleBarBounds = .(0, 0, 0, 0);
			mCloseBounds = .(0, 0, 0, 0);
			mPinBounds = .(0, 0, 0, 0);
			mContentBounds = contentBounds;
		}

		if (mContent != null && mContent.Visibility != .Collapsed)
		{
			mContent.Arrange(mContentBounds);
		}
	}

	// === Rendering ===

	protected override void RenderOverride(DrawContext ctx)
	{
		// Only render title bar if it should be shown
		if (ShouldShowTitleBar)
		{
			// Title bar background
			let titleBarColor = Color(50, 50, 50, 255);
			ctx.FillRect(mTitleBarBounds, titleBarColor);

			// Title text - vertically centered
			let fontSize = 12.0f;
			let titleColor = Color(220, 220, 220, 255);
			let textX = mTitleBarBounds.X + 8;
			let textY = mTitleBarBounds.Y + (mTitleBarHeight - fontSize) / 2;
			ctx.DrawText(mTitle ?? "", fontSize, .(textX, textY), titleColor);

			// Close button
			if (mIsCloseable)
			{
				let closeColor = mIsCloseHovered ? Color(200, 60, 60, 255) : Color(120, 120, 120, 255);
				RenderCloseButton(ctx, mCloseBounds, closeColor);
			}

			// Pin button
			if (mIsPinnable)
			{
				let pinColor = mIsPinHovered ? Color(100, 150, 255, 255) : Color(120, 120, 120, 255);
				RenderPinButton(ctx, mPinBounds, pinColor, mIsPinned);
			}

			// Title bar bottom border
			ctx.DrawLine(
				.(mTitleBarBounds.X, mTitleBarBounds.Bottom),
				.(mTitleBarBounds.Right, mTitleBarBounds.Bottom),
				Color(80, 80, 80, 255), 1
			);
		}

		// Content background
		let contentBg = Background.A > 0 ? Background : Color(40, 40, 40, 255);
		ctx.FillRect(mContentBounds, contentBg);

		// Render content
		if (mContent != null && mContent.Visibility != .Collapsed)
		{
			mContent.Render(ctx);
		}
	}

	private void RenderCloseButton(DrawContext ctx, RectangleF bounds, Color color)
	{
		// Draw X
		let padding = 5.0f;
		let x1 = bounds.X + padding;
		let y1 = bounds.Y + padding;
		let x2 = bounds.Right - padding;
		let y2 = bounds.Bottom - padding;
		ctx.DrawLine(.(x1, y1), .(x2, y2), color, 1.5f);
		ctx.DrawLine(.(x2, y1), .(x1, y2), color, 1.5f);
	}

	private void RenderPinButton(DrawContext ctx, RectangleF bounds, Color color, bool isPinned)
	{
		// Draw pin icon (simplified)
		let cx = bounds.X + bounds.Width / 2;
		let cy = bounds.Y + bounds.Height / 2;
		let size = bounds.Width * 0.3f;

		if (isPinned)
		{
			// Vertical pin
			ctx.FillRect(.(cx - 2, cy - size, 4, size * 2), color);
			ctx.FillRect(.(cx - size, cy - size, size * 2, 3), color);
		}
		else
		{
			// Horizontal pin (rotated)
			ctx.FillRect(.(cx - size, cy - 2, size * 2, 4), color);
			ctx.FillRect(.(cx - size, cy - size, 3, size * 2), color);
		}
	}

	// === Input ===

	protected override void OnMouseMove(MouseEventArgs e)
	{
		base.OnMouseMove(e);

		let point = Vector2(e.ScreenX, e.ScreenY);
		mIsCloseHovered = mIsCloseable && mCloseBounds.Contains(point.X, point.Y);
		mIsPinHovered = mIsPinnable && mPinBounds.Contains(point.X, point.Y);
	}

	protected override void OnMouseLeave(MouseEventArgs e)
	{
		base.OnMouseLeave(e);
		mIsCloseHovered = false;
		mIsPinHovered = false;
	}

	protected override void OnMouseDown(MouseButtonEventArgs e)
	{
		base.OnMouseDown(e);

		if (e.Button == .Left)
		{
			let point = Vector2(e.ScreenX, e.ScreenY);

			// Check close button
			if (mIsCloseable && mCloseBounds.Contains(point.X, point.Y))
			{
				mCloseRequested.[Friend]Invoke(this);
				e.Handled = true;
				return;
			}

			// Check pin button
			if (mIsPinnable && mPinBounds.Contains(point.X, point.Y))
			{
				IsPinned = !IsPinned;
				e.Handled = true;
				return;
			}

			// Initiate drag from title bar (only when title bar is visible)
			if (ShouldShowTitleBar && mTitleBarBounds.Contains(point.X, point.Y))
			{
				mDragPending = true;
				mDragStartPos = point;

				if (Context != null && Context.DragDropManager != null && ParentGroup != null)
				{
					let tabIndex = ParentGroup.[Friend]mPanels.IndexOf(this);
					let dragData = new DockPanelDragData(this, ParentGroup, tabIndex);
					Context.DragDropManager.BeginPotentialDrag(this, dragData, .Move, point);
				}

				e.Handled = true;
			}
		}
	}

	protected override void OnMouseUp(MouseButtonEventArgs e)
	{
		base.OnMouseUp(e);

		if (e.Button == .Left)
		{
			mDragPending = false;
		}
	}

	// === IDragSource Implementation ===

	/// Returns whether a drag can be started from this panel.
	public bool CanStartDrag()
	{
		return mDragPending && ParentGroup != null;
	}

	/// Creates drag data for this panel.
	public DragData CreateDragData()
	{
		if (ParentGroup != null)
		{
			let tabIndex = ParentGroup.[Friend]mPanels.IndexOf(this);
			return new DockPanelDragData(this, ParentGroup, tabIndex);
		}
		return null;
	}

	/// Gets allowed drop effects for panel drag.
	public DragDropEffects GetAllowedEffects()
	{
		return .Move;
	}

	/// Creates the visual representation for the drag adorner.
	public void CreateDragVisual(DragAdorner adorner)
	{
		adorner.SetLabel(Title);
		adorner.Size = .(120, 30);
	}

	/// Called when drag actually starts.
	public void OnDragStarted(DragEventArgs args)
	{
		// Visual feedback could be added here
	}

	/// Called when drag completes.
	public void OnDragCompleted(DragEventArgs args)
	{
		mDragPending = false;
	}

	// === IDropTarget Implementation ===
	// Forward all drop operations to parent group to allow dropping panels onto other panels

	/// Returns whether this panel can accept dock panel drops.
	public bool CanAcceptDrop(DragData data)
	{
		// Don't accept drops of ourselves
		if (let panelData = data as DockPanelDragData)
		{
			if (panelData.Panel == this)
				return false;
		}
		return ParentGroup != null && data != null && data.Format == DockPanelDragDataFormat.DockPanel;
	}

	/// Called when a drag enters this panel.
	public void OnDragEnter(DragEventArgs args)
	{
		if (ParentGroup != null)
			ParentGroup.OnDragEnter(args);
	}

	/// Called while dragging over this panel.
	public void OnDragOver(DragEventArgs args)
	{
		if (ParentGroup != null)
			ParentGroup.OnDragOver(args);
	}

	/// Called when a drag leaves this panel.
	public void OnDragLeave(DragEventArgs args)
	{
		if (ParentGroup != null)
			ParentGroup.OnDragLeave(args);
	}

	/// Called when drop occurs on this panel.
	public void OnDrop(DragEventArgs args)
	{
		if (ParentGroup != null)
			ParentGroup.OnDrop(args);
	}

	// === Hit Testing ===

	public override UIElement HitTest(Vector2 point)
	{
		if (Visibility != .Visible)
			return null;

		if (!ArrangedBounds.Contains(point.X, point.Y))
			return null;

		// Check content first
		if (mContent != null && mContentBounds.Contains(point.X, point.Y))
		{
			let hit = mContent.HitTest(point);
			if (hit != null)
				return hit;
		}

		return this;
	}

	// === Visual Children ===

	public override int VisualChildCount => mContent != null ? 1 : 0;

	public override UIElement GetVisualChild(int index)
	{
		if (index == 0 && mContent != null)
			return mContent;
		return null;
	}
}

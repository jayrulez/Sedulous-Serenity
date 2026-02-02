using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.GUI;

/// A floating window containing a dockable panel.
/// Can be dragged to reposition and docked back into the layout.
public class FloatingWindow : Control
{
	private DockManager mManager;
	private DockablePanel mPanel ~ delete _;
	private Vector2 mPosition;
	private Vector2 mSize = .(300, 200);

	// Dragging state
	private bool mIsDragging = false;
	private Vector2 mDragOffset;

	// Resize state
	private bool mIsResizing = false;
	private ResizeEdge mResizeEdge = .None;
	private Vector2 mResizeStartPos;
	private RectangleF mResizeStartBounds;
	private const float ResizeBorderSize = 6;
	private const float MinWindowSize = 100;

	private enum ResizeEdge
	{
		None,
		Left,
		Right,
		Top,
		Bottom,
		TopLeft,
		TopRight,
		BottomLeft,
		BottomRight
	}

	/// Creates a floating window for a panel.
	public this(DockManager manager, DockablePanel panel)
	{
		mManager = manager;
		mPanel = panel;
		IsFocusable = false;
		IsTabStop = false;

		if (mPanel != null)
			mPanel.ParentGroup = null;
	}

	/// The panel in this floating window.
	public DockablePanel Panel
	{
		get => mPanel;
		set
		{
			if (mPanel != null && Context != null)
				mPanel.OnDetachedFromContext();
			mPanel = value;
			if (mPanel != null && Context != null)
				mPanel.OnAttachedToContext(Context);
		}
	}

	/// The position of the floating window.
	public Vector2 Position
	{
		get => mPosition;
		set
		{
			mPosition = value;
			InvalidateLayout();
		}
	}

	/// The size of the floating window.
	public Vector2 Size
	{
		get => mSize;
		set
		{
			mSize = .(Math.Max(MinWindowSize, value.X), Math.Max(MinWindowSize, value.Y));
			InvalidateLayout();
		}
	}

	/// The bounds of this floating window.
	public RectangleF WindowBounds => .(mPosition.X, mPosition.Y, mSize.X, mSize.Y);

	// === Context ===

	public override void OnAttachedToContext(GUIContext context)
	{
		base.OnAttachedToContext(context);
		if (mPanel != null)
			mPanel.OnAttachedToContext(context);
	}

	public override void OnDetachedFromContext()
	{
		if (mPanel != null)
			mPanel.OnDetachedFromContext();
		base.OnDetachedFromContext();
	}

	// === Layout ===

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		if (mPanel != null)
			mPanel.Measure(constraints);
		return .(mSize.X, mSize.Y);
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		if (mPanel != null)
		{
			mPanel.Arrange(WindowBounds);
		}
	}

	// === Rendering ===

	protected override void RenderOverride(DrawContext ctx)
	{
		let bounds = WindowBounds;

		// Window shadow
		let shadowOffset = 4.0f;
		ctx.FillRect(.(bounds.X + shadowOffset, bounds.Y + shadowOffset, bounds.Width, bounds.Height),
			Color(0, 0, 0, 60));

		// Window background
		ctx.FillRect(bounds, Color(45, 45, 45, 255));

		// Window border
		ctx.DrawRect(bounds, Color(80, 80, 80, 255), 1);

		// Render panel content
		if (mPanel != null)
		{
			mPanel.Render(ctx);
		}

		// Resize handles (subtle indicators at corners)
		if (mIsResizing || IsMouseOverResizeEdge(mLastMousePos))
		{
			let handleSize = 8.0f;
			let handleColor = Color(100, 150, 200, 150);

			// Bottom-right corner handle
			ctx.FillRect(.(bounds.Right - handleSize, bounds.Bottom - handleSize, handleSize, handleSize), handleColor);
		}
	}

	// === Input ===

	private Vector2 mLastMousePos;

	protected override void OnMouseMove(MouseEventArgs e)
	{
		base.OnMouseMove(e);
		mLastMousePos = .(e.ScreenX, e.ScreenY);

		if (mIsDragging)
		{
			mPosition = .(e.ScreenX - mDragOffset.X, e.ScreenY - mDragOffset.Y);
			InvalidateLayout();
			e.Handled = true;
		}
		else if (mIsResizing)
		{
			HandleResize(.(e.ScreenX, e.ScreenY));
			e.Handled = true;
		}
	}

	protected override void OnMouseDown(MouseButtonEventArgs e)
	{
		base.OnMouseDown(e);

		if (e.Button != .Left)
			return;

		let point = Vector2(e.ScreenX, e.ScreenY);
		let bounds = WindowBounds;

		// Check resize edges first
		let edge = GetResizeEdge(point);
		if (edge != .None)
		{
			mIsResizing = true;
			mResizeEdge = edge;
			mResizeStartPos = point;
			mResizeStartBounds = bounds;
			if (Context != null)
				Context.FocusManager?.SetCapture(this);
			e.Handled = true;
			return;
		}

		// Check title bar for dragging
		if (mPanel != null && mPanel.TitleBarBounds.Contains(point.X, point.Y))
		{
			mIsDragging = true;
			mDragOffset = .(point.X - mPosition.X, point.Y - mPosition.Y);
			if (Context != null)
				Context.FocusManager?.SetCapture(this);
			e.Handled = true;
		}
	}

	protected override void OnMouseUp(MouseButtonEventArgs e)
	{
		base.OnMouseUp(e);

		if (e.Button == .Left)
		{
			if (mIsDragging || mIsResizing)
			{
				mIsDragging = false;
				mIsResizing = false;
				if (Context != null)
					Context.FocusManager?.ReleaseCapture();
				e.Handled = true;
			}
		}
	}

	private ResizeEdge GetResizeEdge(Vector2 point)
	{
		let bounds = WindowBounds;

		bool onLeft = point.X >= bounds.X && point.X < bounds.X + ResizeBorderSize;
		bool onRight = point.X > bounds.Right - ResizeBorderSize && point.X <= bounds.Right;
		bool onTop = point.Y >= bounds.Y && point.Y < bounds.Y + ResizeBorderSize;
		bool onBottom = point.Y > bounds.Bottom - ResizeBorderSize && point.Y <= bounds.Bottom;

		if (onTop && onLeft) return .TopLeft;
		if (onTop && onRight) return .TopRight;
		if (onBottom && onLeft) return .BottomLeft;
		if (onBottom && onRight) return .BottomRight;
		if (onLeft) return .Left;
		if (onRight) return .Right;
		if (onTop) return .Top;
		if (onBottom) return .Bottom;

		return .None;
	}

	private bool IsMouseOverResizeEdge(Vector2 point)
	{
		return GetResizeEdge(point) != .None;
	}

	private void HandleResize(Vector2 currentPos)
	{
		let delta = currentPos - mResizeStartPos;
		var newBounds = mResizeStartBounds;

		switch (mResizeEdge)
		{
		case .Left:
			newBounds.X += delta.X;
			newBounds.Width -= delta.X;
		case .Right:
			newBounds.Width += delta.X;
		case .Top:
			newBounds.Y += delta.Y;
			newBounds.Height -= delta.Y;
		case .Bottom:
			newBounds.Height += delta.Y;
		case .TopLeft:
			newBounds.X += delta.X;
			newBounds.Width -= delta.X;
			newBounds.Y += delta.Y;
			newBounds.Height -= delta.Y;
		case .TopRight:
			newBounds.Width += delta.X;
			newBounds.Y += delta.Y;
			newBounds.Height -= delta.Y;
		case .BottomLeft:
			newBounds.X += delta.X;
			newBounds.Width -= delta.X;
			newBounds.Height += delta.Y;
		case .BottomRight:
			newBounds.Width += delta.X;
			newBounds.Height += delta.Y;
		case .None:
			return;
		}

		// Apply minimum size constraints
		if (newBounds.Width < MinWindowSize)
		{
			if (mResizeEdge == .Left || mResizeEdge == .TopLeft || mResizeEdge == .BottomLeft)
				newBounds.X = mResizeStartBounds.Right - MinWindowSize;
			newBounds.Width = MinWindowSize;
		}
		if (newBounds.Height < MinWindowSize)
		{
			if (mResizeEdge == .Top || mResizeEdge == .TopLeft || mResizeEdge == .TopRight)
				newBounds.Y = mResizeStartBounds.Bottom - MinWindowSize;
			newBounds.Height = MinWindowSize;
		}

		mPosition = .(newBounds.X, newBounds.Y);
		mSize = .(newBounds.Width, newBounds.Height);
		InvalidateLayout();
	}

	// === Hit Testing ===

	public override UIElement HitTest(Vector2 point)
	{
		let bounds = WindowBounds;
		if (!bounds.Contains(point.X, point.Y))
			return null;

		// Check panel content first
		if (mPanel != null)
		{
			let hit = mPanel.HitTest(point);
			if (hit != null)
				return hit;
		}

		return this;
	}

	// === Visual Children ===

	public override int VisualChildCount => mPanel != null ? 1 : 0;

	public override UIElement GetVisualChild(int index)
	{
		if (index == 0 && mPanel != null)
			return mPanel;
		return null;
	}
}

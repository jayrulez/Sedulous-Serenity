using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// Controls visibility of a scrollbar.
public enum ScrollBarVisibility
{
	/// Scrollbar is never shown, scrolling disabled in this direction.
	Disabled,
	/// Scrollbar is shown only when content exceeds viewport.
	Auto,
	/// Scrollbar is always hidden but scrolling is enabled.
	Hidden,
	/// Scrollbar is always visible.
	Visible
}

/// Provides a scrollable view of content larger than the viewport.
///
/// IMPORTANT: Use the `Content` property to set the scrollable content, not `AddChild()`.
/// The `Content` property ensures proper measurement, layout, and scrolling behavior.
///
/// Example:
/// ```
/// let scrollViewer = new ScrollViewer();
/// scrollViewer.Padding = Thickness(20);
///
/// let content = new StackPanel();
/// content.AddChild(new TextBlock("Item 1"));
/// content.AddChild(new TextBlock("Item 2"));
///
/// scrollViewer.Content = content;  // Correct
/// // scrollViewer.AddChild(content);  // Wrong - scrolling and layout will fail
/// ```
public class ScrollViewer : UIElement
{
	private UIElement mContent;
	private Vector2 mScrollOffset;
	private Vector2 mExtentSize;
	private Vector2 mViewportSize;

	private ScrollBarVisibility mHorizontalScrollBarVisibility = .Auto;
	private ScrollBarVisibility mVerticalScrollBarVisibility = .Auto;

	private float mScrollBarWidth = 12;

	// Scrollbar dragging state
	private enum DragMode { None, VerticalThumb, HorizontalThumb, VerticalTrack, HorizontalTrack }
	private DragMode mDragMode = .None;
	private float mDragStartOffset = 0;  // Scroll offset when drag started
	private float mDragStartMouse = 0;   // Mouse position when drag started

	/// The content element to scroll.
	public UIElement Content
	{
		get => mContent;
		set
		{
			if (mContent != null)
				RemoveChild(mContent);

			mContent = value;

			if (mContent != null)
				AddChild(mContent);

			InvalidateMeasure();
		}
	}

	/// Horizontal scroll offset in pixels.
	public float HorizontalOffset
	{
		get => mScrollOffset.X;
		set => ScrollTo(value, mScrollOffset.Y);
	}

	/// Vertical scroll offset in pixels.
	public float VerticalOffset
	{
		get => mScrollOffset.Y;
		set => ScrollTo(mScrollOffset.X, value);
	}

	/// Current scroll offset.
	public Vector2 ScrollOffset => mScrollOffset;

	/// Size of the scrollable content.
	public Vector2 ExtentSize => mExtentSize;

	/// Size of the visible viewport.
	public Vector2 ViewportSize => mViewportSize;

	/// Whether horizontal scrollbar is visible.
	public ScrollBarVisibility HorizontalScrollBarVisibility
	{
		get => mHorizontalScrollBarVisibility;
		set { mHorizontalScrollBarVisibility = value; InvalidateMeasure(); }
	}

	/// Whether vertical scrollbar is visible.
	public ScrollBarVisibility VerticalScrollBarVisibility
	{
		get => mVerticalScrollBarVisibility;
		set { mVerticalScrollBarVisibility = value; InvalidateMeasure(); }
	}

	/// Width of scrollbars in pixels.
	public float ScrollBarWidth
	{
		get => mScrollBarWidth;
		set { mScrollBarWidth = value; InvalidateMeasure(); }
	}

	/// Whether the content can scroll horizontally.
	public bool CanScrollHorizontally =>
		mHorizontalScrollBarVisibility != .Disabled && mExtentSize.X > mViewportSize.X;

	/// Whether the content can scroll vertically.
	public bool CanScrollVertically =>
		mVerticalScrollBarVisibility != .Disabled && mExtentSize.Y > mViewportSize.Y;

	/// Scrolls to the specified offset.
	public void ScrollTo(float x, float y)
	{
		let maxX = Math.Max(0, mExtentSize.X - mViewportSize.X);
		let maxY = Math.Max(0, mExtentSize.Y - mViewportSize.Y);

		let newX = Math.Clamp(x, 0, maxX);
		let newY = Math.Clamp(y, 0, maxY);

		if (newX != mScrollOffset.X || newY != mScrollOffset.Y)
		{
			mScrollOffset = .(newX, newY);
			InvalidateArrange();
		}
	}

	/// Scrolls by the specified delta.
	public void ScrollBy(float deltaX, float deltaY)
	{
		ScrollTo(mScrollOffset.X + deltaX, mScrollOffset.Y + deltaY);
	}

	/// Scrolls to make an element visible.
	public void ScrollIntoView(UIElement element)
	{
		if (element == null || mContent == null)
			return;

		// Convert element bounds from screen coordinates to content-relative coordinates
		// Content is arranged at (contentBounds - scrollOffset), so:
		// contentRelativePos = screenPos - (contentBounds - scrollOffset) = screenPos - contentBounds + scrollOffset
		let contentBounds = ContentBounds;
		let elementBounds = element.Bounds;
		let contentRelativeX = elementBounds.X - contentBounds.X + mScrollOffset.X;
		let contentRelativeY = elementBounds.Y - contentBounds.Y + mScrollOffset.Y;

		var targetX = mScrollOffset.X;
		var targetY = mScrollOffset.Y;

		// Adjust horizontal scroll (only if horizontal scrolling is enabled)
		if (mHorizontalScrollBarVisibility != .Disabled)
		{
			if (contentRelativeX < mScrollOffset.X)
				targetX = contentRelativeX;
			else if (contentRelativeX + elementBounds.Width > mScrollOffset.X + mViewportSize.X)
				targetX = contentRelativeX + elementBounds.Width - mViewportSize.X;
		}

		// Adjust vertical scroll (only if vertical scrolling is enabled)
		if (mVerticalScrollBarVisibility != .Disabled)
		{
			if (contentRelativeY < mScrollOffset.Y)
				targetY = contentRelativeY;
			else if (contentRelativeY + elementBounds.Height > mScrollOffset.Y + mViewportSize.Y)
				targetY = contentRelativeY + elementBounds.Height - mViewportSize.Y;
		}

		ScrollTo(targetX, targetY);
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		if (mContent == null)
			return .(0, 0);

		// Measure content with infinite space in scrollable directions
		var contentConstraints = constraints;
		if (mHorizontalScrollBarVisibility != .Disabled)
			contentConstraints.MaxWidth = SizeConstraints.Infinity;
		if (mVerticalScrollBarVisibility != .Disabled)
			contentConstraints.MaxHeight = SizeConstraints.Infinity;

		mContent.Measure(contentConstraints);
		mExtentSize = .(mContent.DesiredSize.Width, mContent.DesiredSize.Height);

		// Return viewport size (constrained)
		return .(
			constraints.ConstrainWidth(mContent.DesiredSize.Width),
			constraints.ConstrainHeight(mContent.DesiredSize.Height)
		);
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		if (mContent == null)
			return;

		// Calculate viewport size (accounting for scrollbars)
		var viewportWidth = contentBounds.Width;
		var viewportHeight = contentBounds.Height;

		let needsVScroll = mVerticalScrollBarVisibility == .Visible ||
			(mVerticalScrollBarVisibility == .Auto && mExtentSize.Y > viewportHeight);
		let needsHScroll = mHorizontalScrollBarVisibility == .Visible ||
			(mHorizontalScrollBarVisibility == .Auto && mExtentSize.X > viewportWidth);

		if (needsVScroll)
			viewportWidth -= mScrollBarWidth;
		if (needsHScroll)
			viewportHeight -= mScrollBarWidth;

		mViewportSize = .(Math.Max(0, viewportWidth), Math.Max(0, viewportHeight));

		// Clamp scroll offset
		ScrollTo(mScrollOffset.X, mScrollOffset.Y);

		// Arrange content at offset position
		let contentWidth = Math.Max(mExtentSize.X, mViewportSize.X);
		let contentHeight = Math.Max(mExtentSize.Y, mViewportSize.Y);

		mContent.Arrange(.(
			contentBounds.X - mScrollOffset.X,
			contentBounds.Y - mScrollOffset.Y,
			contentWidth,
			contentHeight
		));
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let contentBounds = ContentBounds;

		// Set up clipping for viewport (content area only)
		drawContext.PushClipRect(.(contentBounds.X, contentBounds.Y, mViewportSize.X, mViewportSize.Y));

		// Content is rendered via the normal child rendering in base class
	}

	public override void Render(DrawContext drawContext)
	{
		if (Visibility != .Visible || Opacity <= 0)
			return;

		// Render this element (sets up clip rect)
		OnRender(drawContext);

		// Render children (content) inside clip rect
		for (let child in Children)
		{
			child.Render(drawContext);
		}

		// Pop clip rect before rendering scrollbars
		drawContext.PopClip();

		// Render scrollbars outside the clip rect
		RenderScrollBars(drawContext);
	}

	private void RenderScrollBars(DrawContext drawContext)
	{
		let contentBounds = ContentBounds;
		let scrollBarColor = Color(128, 128, 128, 200);
		let thumbColor = Color(80, 80, 80, 255);

		// Vertical scrollbar
		if (CanScrollVertically && mVerticalScrollBarVisibility != .Hidden)
		{
			let barX = contentBounds.X + mViewportSize.X;
			let barY = contentBounds.Y;
			let barHeight = mViewportSize.Y;

			// Background track
			drawContext.FillRect(.(barX, barY, mScrollBarWidth, barHeight), scrollBarColor);

			// Thumb
			let thumbRatio = mViewportSize.Y / mExtentSize.Y;
			let thumbHeight = Math.Max(20, barHeight * thumbRatio);
			let thumbY = barY + (barHeight - thumbHeight) * (mScrollOffset.Y / (mExtentSize.Y - mViewportSize.Y));
			drawContext.FillRect(.(barX + 2, thumbY, mScrollBarWidth - 4, thumbHeight), thumbColor);
		}

		// Horizontal scrollbar
		if (CanScrollHorizontally && mHorizontalScrollBarVisibility != .Hidden)
		{
			let barX = contentBounds.X;
			let barY = contentBounds.Y + mViewportSize.Y;
			let barWidth = mViewportSize.X;

			// Background track
			drawContext.FillRect(.(barX, barY, barWidth, mScrollBarWidth), scrollBarColor);

			// Thumb
			let thumbRatio = mViewportSize.X / mExtentSize.X;
			let thumbWidth = Math.Max(20, barWidth * thumbRatio);
			let thumbX = barX + (barWidth - thumbWidth) * (mScrollOffset.X / (mExtentSize.X - mViewportSize.X));
			drawContext.FillRect(.(thumbX, barY + 2, thumbWidth, mScrollBarWidth - 4), thumbColor);
		}
	}

	protected override void OnMouseWheelRouted(MouseWheelEventArgs args)
	{
		// Scroll by wheel delta (typically 40 pixels per notch)
		let scrollAmount = 40.0f;
		bool scrolled = false;

		if (CanScrollVertically && args.DeltaY != 0)
		{
			ScrollBy(0, -args.DeltaY * scrollAmount);
			scrolled = true;
		}
		else if (CanScrollHorizontally && (args.DeltaX != 0 || args.DeltaY != 0))
		{
			// Use horizontal delta if available, otherwise use vertical for horizontal scroll
			let delta = args.DeltaX != 0 ? args.DeltaX : args.DeltaY;
			ScrollBy(-delta * scrollAmount, 0);
			scrolled = true;
		}

		if (scrolled)
			args.Handled = true;

		base.OnMouseWheelRouted(args);
	}

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		if (args.Button != .Left)
		{
			base.OnMouseDownRouted(args);
			return;
		}

		let contentBounds = ContentBounds;
		let localX = args.ScreenX - contentBounds.X;
		let localY = args.ScreenY - contentBounds.Y;

		// Check scrollbars FIRST (they're visually on top and should intercept clicks)

		// Check vertical scrollbar
		if (CanScrollVertically && mVerticalScrollBarVisibility != .Hidden)
		{
			let barX = mViewportSize.X;
			if (localX >= barX && localX < barX + mScrollBarWidth && localY >= 0 && localY < mViewportSize.Y)
			{
				// Hit vertical scrollbar
				let (thumbY, thumbHeight) = GetVerticalThumbBounds();
				let relativeThumbY = thumbY - contentBounds.Y;

				if (localY >= relativeThumbY && localY < relativeThumbY + thumbHeight)
				{
					// Hit thumb - start dragging
					mDragMode = .VerticalThumb;
					mDragStartOffset = mScrollOffset.Y;
					mDragStartMouse = args.ScreenY;
				}
				else
				{
					// Hit track - page scroll
					if (localY < relativeThumbY)
						ScrollBy(0, -mViewportSize.Y * 0.9f);
					else
						ScrollBy(0, mViewportSize.Y * 0.9f);
				}

				Context?.CaptureMouse(this);
				args.Handled = true;
				return;
			}
		}

		// Check horizontal scrollbar
		if (CanScrollHorizontally && mHorizontalScrollBarVisibility != .Hidden)
		{
			let barY = mViewportSize.Y;
			if (localY >= barY && localY < barY + mScrollBarWidth && localX >= 0 && localX < mViewportSize.X)
			{
				// Hit horizontal scrollbar
				let (thumbX, thumbWidth) = GetHorizontalThumbBounds();
				let relativeThumbX = thumbX - contentBounds.X;

				if (localX >= relativeThumbX && localX < relativeThumbX + thumbWidth)
				{
					// Hit thumb - start dragging
					mDragMode = .HorizontalThumb;
					mDragStartOffset = mScrollOffset.X;
					mDragStartMouse = args.ScreenX;
				}
				else
				{
					// Hit track - page scroll
					if (localX < relativeThumbX)
						ScrollBy(-mViewportSize.X * 0.9f, 0);
					else
						ScrollBy(mViewportSize.X * 0.9f, 0);
				}

				Context?.CaptureMouse(this);
				args.Handled = true;
				return;
			}
		}

		// Not in scrollbar area, let base handle it
		base.OnMouseDownRouted(args);
	}

	protected override void OnMouseMoveRouted(MouseEventArgs args)
	{
		base.OnMouseMoveRouted(args);

		if (mDragMode == .VerticalThumb)
		{
			// Calculate scroll from mouse delta
			let mouseDelta = args.ScreenY - mDragStartMouse;
			let trackHeight = mViewportSize.Y;
			let thumbRatio = mViewportSize.Y / mExtentSize.Y;
			let thumbHeight = Math.Max(20, trackHeight * thumbRatio);
			let scrollableTrack = trackHeight - thumbHeight;

			if (scrollableTrack > 0)
			{
				let scrollRange = mExtentSize.Y - mViewportSize.Y;
				let scrollDelta = (mouseDelta / scrollableTrack) * scrollRange;
				ScrollTo(mScrollOffset.X, mDragStartOffset + scrollDelta);
			}
			args.Handled = true;
		}
		else if (mDragMode == .HorizontalThumb)
		{
			// Calculate scroll from mouse delta
			let mouseDelta = args.ScreenX - mDragStartMouse;
			let trackWidth = mViewportSize.X;
			let thumbRatio = mViewportSize.X / mExtentSize.X;
			let thumbWidth = Math.Max(20, trackWidth * thumbRatio);
			let scrollableTrack = trackWidth - thumbWidth;

			if (scrollableTrack > 0)
			{
				let scrollRange = mExtentSize.X - mViewportSize.X;
				let scrollDelta = (mouseDelta / scrollableTrack) * scrollRange;
				ScrollTo(mDragStartOffset + scrollDelta, mScrollOffset.Y);
			}
			args.Handled = true;
		}
	}

	protected override void OnMouseUpRouted(MouseButtonEventArgs args)
	{
		base.OnMouseUpRouted(args);

		if (args.Button == .Left && mDragMode != .None)
		{
			mDragMode = .None;
			Context?.ReleaseMouseCapture();
			args.Handled = true;
		}
	}

	/// Gets the vertical thumb position and height in absolute coordinates.
	private (float thumbY, float thumbHeight) GetVerticalThumbBounds()
	{
		let contentBounds = ContentBounds;
		let barY = contentBounds.Y;
		let barHeight = mViewportSize.Y;

		let thumbRatio = mViewportSize.Y / mExtentSize.Y;
		let thumbHeight = Math.Max(20, barHeight * thumbRatio);
		let scrollRange = mExtentSize.Y - mViewportSize.Y;
		let thumbY = scrollRange > 0
			? barY + (barHeight - thumbHeight) * (mScrollOffset.Y / scrollRange)
			: barY;

		return (thumbY, thumbHeight);
	}

	/// Gets the horizontal thumb position and width in absolute coordinates.
	private (float thumbX, float thumbWidth) GetHorizontalThumbBounds()
	{
		let contentBounds = ContentBounds;
		let barX = contentBounds.X;
		let barWidth = mViewportSize.X;

		let thumbRatio = mViewportSize.X / mExtentSize.X;
		let thumbWidth = Math.Max(20, barWidth * thumbRatio);
		let scrollRange = mExtentSize.X - mViewportSize.X;
		let thumbX = scrollRange > 0
			? barX + (barWidth - thumbWidth) * (mScrollOffset.X / scrollRange)
			: barX;

		return (thumbX, thumbWidth);
	}
}

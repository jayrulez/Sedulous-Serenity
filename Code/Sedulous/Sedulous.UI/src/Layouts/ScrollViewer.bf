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
public class ScrollViewer : UIElement
{
	private UIElement mContent;
	private Vector2 mScrollOffset;
	private Vector2 mExtentSize;
	private Vector2 mViewportSize;

	private ScrollBarVisibility mHorizontalScrollBarVisibility = .Auto;
	private ScrollBarVisibility mVerticalScrollBarVisibility = .Auto;

	private float mScrollBarWidth = 12;

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

		// Calculate element's position relative to content
		let elementBounds = element.Bounds;
		var targetX = mScrollOffset.X;
		var targetY = mScrollOffset.Y;

		// Adjust horizontal scroll
		if (elementBounds.X < mScrollOffset.X)
			targetX = elementBounds.X;
		else if (elementBounds.X + elementBounds.Width > mScrollOffset.X + mViewportSize.X)
			targetX = elementBounds.X + elementBounds.Width - mViewportSize.X;

		// Adjust vertical scroll
		if (elementBounds.Y < mScrollOffset.Y)
			targetY = elementBounds.Y;
		else if (elementBounds.Y + elementBounds.Height > mScrollOffset.Y + mViewportSize.Y)
			targetY = elementBounds.Y + elementBounds.Height - mViewportSize.Y;

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
		let bounds = Bounds;

		// Set up clipping for viewport
		drawContext.PushClipRect(.(bounds.X, bounds.Y, mViewportSize.X, mViewportSize.Y));

		// Content is rendered via the normal child rendering

		// Render scrollbars
		RenderScrollBars(drawContext);

		drawContext.PopClip();
	}

	private void RenderScrollBars(DrawContext drawContext)
	{
		let bounds = Bounds;
		let scrollBarColor = Color(128, 128, 128, 200);
		let thumbColor = Color(80, 80, 80, 255);

		// Vertical scrollbar
		if (CanScrollVertically && mVerticalScrollBarVisibility != .Hidden)
		{
			let barX = bounds.X + mViewportSize.X;
			let barY = bounds.Y;
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
			let barX = bounds.X;
			let barY = bounds.Y + mViewportSize.Y;
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

	protected override void OnMouseWheel(float deltaX, float deltaY)
	{
		// Scroll by wheel delta (typically 40 pixels per notch)
		let scrollAmount = 40.0f;
		if (CanScrollVertically)
			ScrollBy(0, -deltaY * scrollAmount);
		else if (CanScrollHorizontally)
			ScrollBy(-deltaY * scrollAmount, 0);

		base.OnMouseWheel(deltaX, deltaY);
	}
}

using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Scrollable viewport container.
class ScrollViewer : Widget
{
	private Widget mContent;
	private Vector2 mScrollOffset;
	private Vector2 mExtent;
	private Vector2 mViewport;

	private ScrollBarVisibility mHorizontalScrollBarVisibility = .Auto;
	private ScrollBarVisibility mVerticalScrollBarVisibility = .Auto;

	private float mScrollBarWidth = 12;
	private float mScrollBarMinThumbSize = 20;

	private Color mScrollBarTrackColor = Color(40, 40, 40, 200);
	private Color mScrollBarThumbColor = Color(100, 100, 100, 255);
	private Color mScrollBarThumbHoverColor = Color(130, 130, 130, 255);
	private Color mScrollBarThumbPressedColor = Color(80, 80, 80, 255);

	private bool mIsVerticalThumbHovered;
	private bool mIsHorizontalThumbHovered;
	private bool mIsDraggingVertical;
	private bool mIsDraggingHorizontal;
	private float mDragStartOffset;
	private float mDragStartScroll;

	/// Event raised when scroll position changes.
	public Event<delegate void(Vector2)> OnScrollChanged ~ _.Dispose();

	/// Creates an empty scroll viewer.
	public this()
	{
		IsFocusable = true;
		ClipToBounds = true;
	}

	/// Gets or sets the content widget.
	public Widget Content
	{
		get => mContent;
		set
		{
			if (mContent != value)
			{
				if (mContent != null)
					Children.Remove(mContent);
				mContent = value;
				if (mContent != null)
					Children.Add(mContent);
				InvalidateMeasure();
			}
		}
	}

	/// Gets or sets the horizontal scroll offset.
	public float HorizontalOffset
	{
		get => mScrollOffset.X;
		set => ScrollTo(value, mScrollOffset.Y);
	}

	/// Gets or sets the vertical scroll offset.
	public float VerticalOffset
	{
		get => mScrollOffset.Y;
		set => ScrollTo(mScrollOffset.X, value);
	}

	/// Gets the total content extent.
	public Vector2 Extent => mExtent;

	/// Gets the viewport size.
	public Vector2 Viewport => mViewport;

	/// Gets or sets the horizontal scroll bar visibility.
	public ScrollBarVisibility HorizontalScrollBarVisibility
	{
		get => mHorizontalScrollBarVisibility;
		set { if (mHorizontalScrollBarVisibility != value) { mHorizontalScrollBarVisibility = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the vertical scroll bar visibility.
	public ScrollBarVisibility VerticalScrollBarVisibility
	{
		get => mVerticalScrollBarVisibility;
		set { if (mVerticalScrollBarVisibility != value) { mVerticalScrollBarVisibility = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the scroll bar width.
	public float ScrollBarWidth
	{
		get => mScrollBarWidth;
		set { if (mScrollBarWidth != value) { mScrollBarWidth = value; InvalidateMeasure(); } }
	}

	/// Gets whether horizontal scrolling is possible.
	public bool CanScrollHorizontally => mExtent.X > mViewport.X && mHorizontalScrollBarVisibility != .Disabled;

	/// Gets whether vertical scrolling is possible.
	public bool CanScrollVertically => mExtent.Y > mViewport.Y && mVerticalScrollBarVisibility != .Disabled;

	/// Gets whether the horizontal scroll bar should be shown.
	private bool ShowHorizontalScrollBar
	{
		get
		{
			switch (mHorizontalScrollBarVisibility)
			{
			case .Hidden, .Disabled: return false;
			case .Visible: return true;
			case .Auto: return mExtent.X > mViewport.X;
			}
		}
	}

	/// Gets whether the vertical scroll bar should be shown.
	private bool ShowVerticalScrollBar
	{
		get
		{
			switch (mVerticalScrollBarVisibility)
			{
			case .Hidden, .Disabled: return false;
			case .Visible: return true;
			case .Auto: return mExtent.Y > mViewport.Y;
			}
		}
	}

	/// Scrolls to the specified offset.
	public void ScrollTo(float x, float y)
	{
		let maxX = Math.Max(0, mExtent.X - mViewport.X);
		let maxY = Math.Max(0, mExtent.Y - mViewport.Y);

		let newX = Math.Clamp(x, 0, maxX);
		let newY = Math.Clamp(y, 0, maxY);

		if (mScrollOffset.X != newX || mScrollOffset.Y != newY)
		{
			mScrollOffset = Vector2(newX, newY);
			InvalidateArrange();
			OnScrollChanged(mScrollOffset);
		}
	}

	/// Scrolls by a delta amount.
	public void ScrollBy(float dx, float dy)
	{
		ScrollTo(mScrollOffset.X + dx, mScrollOffset.Y + dy);
	}

	/// Scrolls to make a rectangle visible.
	public void ScrollIntoView(RectangleF rect)
	{
		var newX = mScrollOffset.X;
		var newY = mScrollOffset.Y;

		// Horizontal
		if (rect.X < mScrollOffset.X)
			newX = rect.X;
		else if (rect.Right > mScrollOffset.X + mViewport.X)
			newX = rect.Right - mViewport.X;

		// Vertical
		if (rect.Y < mScrollOffset.Y)
			newY = rect.Y;
		else if (rect.Bottom > mScrollOffset.Y + mViewport.Y)
			newY = rect.Bottom - mViewport.Y;

		ScrollTo(newX, newY);
	}

	/// Measures the scroll viewer.
	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		if (mContent == null)
			return Vector2(Padding.HorizontalThickness, Padding.VerticalThickness);

		// Give content infinite space in scrollable directions
		var contentAvailable = availableSize;
		if (mHorizontalScrollBarVisibility != .Disabled)
			contentAvailable.X = float.MaxValue;
		if (mVerticalScrollBarVisibility != .Disabled)
			contentAvailable.Y = float.MaxValue;

		// Account for scrollbar space
		let showVBar = mVerticalScrollBarVisibility == .Visible;
		let showHBar = mHorizontalScrollBarVisibility == .Visible;
		if (showVBar && availableSize.X < float.MaxValue)
			contentAvailable.X = availableSize.X - mScrollBarWidth;
		if (showHBar && availableSize.Y < float.MaxValue)
			contentAvailable.Y = availableSize.Y - mScrollBarWidth;

		mContent.Measure(contentAvailable);
		mExtent = mContent.DesiredSize;

		// Return the smaller of available or content size
		var resultWidth = Math.Min(availableSize.X, mExtent.X);
		var resultHeight = Math.Min(availableSize.Y, mExtent.Y);

		if (showVBar)
			resultWidth += mScrollBarWidth;
		if (showHBar)
			resultHeight += mScrollBarWidth;

		return Vector2(
			resultWidth + Padding.HorizontalThickness,
			resultHeight + Padding.VerticalThickness
		);
	}

	/// Arranges the scroll viewer.
	protected override void ArrangeOverride(RectangleF finalRect)
	{
		let contentBounds = ContentBounds;

		// Calculate viewport size (minus scrollbars if shown)
		var viewportWidth = contentBounds.Width;
		var viewportHeight = contentBounds.Height;

		if (ShowVerticalScrollBar)
			viewportWidth -= mScrollBarWidth;
		if (ShowHorizontalScrollBar)
			viewportHeight -= mScrollBarWidth;

		mViewport = Vector2(viewportWidth, viewportHeight);

		// Clamp scroll position
		let maxX = Math.Max(0, mExtent.X - mViewport.X);
		let maxY = Math.Max(0, mExtent.Y - mViewport.Y);
		mScrollOffset.X = Math.Clamp(mScrollOffset.X, 0, maxX);
		mScrollOffset.Y = Math.Clamp(mScrollOffset.Y, 0, maxY);

		// Arrange content at scroll offset
		if (mContent != null)
		{
			let contentRect = RectangleF(
				contentBounds.X - mScrollOffset.X,
				contentBounds.Y - mScrollOffset.Y,
				Math.Max(mExtent.X, viewportWidth),
				Math.Max(mExtent.Y, viewportHeight)
			);
			mContent.Arrange(contentRect);
		}
	}

	/// Gets the vertical scrollbar track rectangle.
	private RectangleF GetVerticalTrackRect()
	{
		let bounds = ContentBounds;
		let height = ShowHorizontalScrollBar ? bounds.Height - mScrollBarWidth : bounds.Height;
		return RectangleF(bounds.Right - mScrollBarWidth, bounds.Y, mScrollBarWidth, height);
	}

	/// Gets the horizontal scrollbar track rectangle.
	private RectangleF GetHorizontalTrackRect()
	{
		let bounds = ContentBounds;
		let width = ShowVerticalScrollBar ? bounds.Width - mScrollBarWidth : bounds.Width;
		return RectangleF(bounds.X, bounds.Bottom - mScrollBarWidth, width, mScrollBarWidth);
	}

	/// Gets the vertical scrollbar thumb rectangle.
	private RectangleF GetVerticalThumbRect()
	{
		let track = GetVerticalTrackRect();
		if (mExtent.Y <= 0)
			return RectangleF(track.X, track.Y, track.Width, track.Height);

		let thumbRatio = Math.Clamp(mViewport.Y / mExtent.Y, 0, 1);
		let thumbHeight = Math.Max(mScrollBarMinThumbSize, track.Height * thumbRatio);
		let scrollRange = track.Height - thumbHeight;
		let maxScroll = mExtent.Y - mViewport.Y;
		let thumbY = (maxScroll > 0) ? track.Y + (mScrollOffset.Y / maxScroll) * scrollRange : track.Y;

		return RectangleF(track.X, thumbY, track.Width, thumbHeight);
	}

	/// Gets the horizontal scrollbar thumb rectangle.
	private RectangleF GetHorizontalThumbRect()
	{
		let track = GetHorizontalTrackRect();
		if (mExtent.X <= 0)
			return RectangleF(track.X, track.Y, track.Width, track.Height);

		let thumbRatio = Math.Clamp(mViewport.X / mExtent.X, 0, 1);
		let thumbWidth = Math.Max(mScrollBarMinThumbSize, track.Width * thumbRatio);
		let scrollRange = track.Width - thumbWidth;
		let maxScroll = mExtent.X - mViewport.X;
		let thumbX = (maxScroll > 0) ? track.X + (mScrollOffset.X / maxScroll) * scrollRange : track.X;

		return RectangleF(thumbX, track.Y, thumbWidth, track.Height);
	}

	/// Renders the scroll viewer.
	protected override void OnRender(DrawContext dc)
	{
		// Render scrollbars
		if (ShowVerticalScrollBar)
		{
			let track = GetVerticalTrackRect();
			let thumb = GetVerticalThumbRect();

			// Track
			dc.FillRect(track, mScrollBarTrackColor);

			// Thumb
			var thumbColor = mScrollBarThumbColor;
			if (mIsDraggingVertical)
				thumbColor = mScrollBarThumbPressedColor;
			else if (mIsVerticalThumbHovered)
				thumbColor = mScrollBarThumbHoverColor;
			dc.FillRoundedRect(thumb, .Uniform(3), thumbColor);
		}

		if (ShowHorizontalScrollBar)
		{
			let track = GetHorizontalTrackRect();
			let thumb = GetHorizontalThumbRect();

			// Track
			dc.FillRect(track, mScrollBarTrackColor);

			// Thumb
			var thumbColor = mScrollBarThumbColor;
			if (mIsDraggingHorizontal)
				thumbColor = mScrollBarThumbPressedColor;
			else if (mIsHorizontalThumbHovered)
				thumbColor = mScrollBarThumbHoverColor;
			dc.FillRoundedRect(thumb, .Uniform(3), thumbColor);
		}

		// Corner fill if both scrollbars visible
		if (ShowVerticalScrollBar && ShowHorizontalScrollBar)
		{
			let bounds = ContentBounds;
			let corner = RectangleF(
				bounds.Right - mScrollBarWidth,
				bounds.Bottom - mScrollBarWidth,
				mScrollBarWidth,
				mScrollBarWidth
			);
			dc.FillRect(corner, mScrollBarTrackColor);
		}
	}

	/// Handles mouse move.
	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		let pos = e.ScreenPosition;

		if (mIsDraggingVertical)
		{
			let track = GetVerticalTrackRect();
			let thumbHeight = GetVerticalThumbRect().Height;
			let scrollRange = track.Height - thumbHeight;
			let maxScroll = mExtent.Y - mViewport.Y;

			if (scrollRange > 0 && maxScroll > 0)
			{
				let delta = pos.Y - mDragStartOffset;
				let newScroll = mDragStartScroll + (delta / scrollRange) * maxScroll;
				ScrollTo(mScrollOffset.X, newScroll);
			}
			return true;
		}

		if (mIsDraggingHorizontal)
		{
			let track = GetHorizontalTrackRect();
			let thumbWidth = GetHorizontalThumbRect().Width;
			let scrollRange = track.Width - thumbWidth;
			let maxScroll = mExtent.X - mViewport.X;

			if (scrollRange > 0 && maxScroll > 0)
			{
				let delta = pos.X - mDragStartOffset;
				let newScroll = mDragStartScroll + (delta / scrollRange) * maxScroll;
				ScrollTo(newScroll, mScrollOffset.Y);
			}
			return true;
		}

		// Update hover states
		let wasVHovered = mIsVerticalThumbHovered;
		let wasHHovered = mIsHorizontalThumbHovered;

		mIsVerticalThumbHovered = ShowVerticalScrollBar && GetVerticalThumbRect().Contains(pos);
		mIsHorizontalThumbHovered = ShowHorizontalScrollBar && GetHorizontalThumbRect().Contains(pos);

		if (wasVHovered != mIsVerticalThumbHovered || wasHHovered != mIsHorizontalThumbHovered)
			InvalidateVisual();

		return false;
	}

	/// Handles mouse down.
	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return false;

		let pos = e.ScreenPosition;

		// Check vertical scrollbar
		if (ShowVerticalScrollBar)
		{
			let thumb = GetVerticalThumbRect();
			if (thumb.Contains(pos))
			{
				mIsDraggingVertical = true;
				mDragStartOffset = pos.Y;
				mDragStartScroll = mScrollOffset.Y;
				Context?.Input.CaptureMouse(this);
				return true;
			}

			// Click on track: page scroll
			let track = GetVerticalTrackRect();
			if (track.Contains(pos))
			{
				let pageSize = mViewport.Y * 0.9f;
				if (pos.Y < thumb.Y)
					ScrollBy(0, -pageSize);
				else
					ScrollBy(0, pageSize);
				return true;
			}
		}

		// Check horizontal scrollbar
		if (ShowHorizontalScrollBar)
		{
			let thumb = GetHorizontalThumbRect();
			if (thumb.Contains(pos))
			{
				mIsDraggingHorizontal = true;
				mDragStartOffset = pos.X;
				mDragStartScroll = mScrollOffset.X;
				Context?.Input.CaptureMouse(this);
				return true;
			}

			// Click on track: page scroll
			let track = GetHorizontalTrackRect();
			if (track.Contains(pos))
			{
				let pageSize = mViewport.X * 0.9f;
				if (pos.X < thumb.X)
					ScrollBy(-pageSize, 0);
				else
					ScrollBy(pageSize, 0);
				return true;
			}
		}

		return false;
	}

	/// Handles mouse up.
	protected override bool OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && (mIsDraggingVertical || mIsDraggingHorizontal))
		{
			mIsDraggingVertical = false;
			mIsDraggingHorizontal = false;
			Context?.Input.ReleaseMouse();
			InvalidateVisual();
			return true;
		}
		return false;
	}

	/// Handles mouse leave.
	protected override bool OnMouseLeave(MouseEventArgs e)
	{
		if (mIsVerticalThumbHovered || mIsHorizontalThumbHovered)
		{
			mIsVerticalThumbHovered = false;
			mIsHorizontalThumbHovered = false;
			InvalidateVisual();
		}
		return false;
	}

	/// Handles mouse wheel.
	protected override bool OnMouseWheel(MouseWheelEventArgs e)
	{
		let scrollAmount = 40.0f; // Pixels per wheel notch

		if (e.Modifiers.HasFlag(.Shift) && CanScrollHorizontally)
		{
			// Shift+Wheel = horizontal scroll
			ScrollBy(-e.DeltaY * scrollAmount, 0);
			return true;
		}
		else if (CanScrollVertically)
		{
			// Normal wheel = vertical scroll
			ScrollBy(0, -e.DeltaY * scrollAmount);
			return true;
		}
		else if (CanScrollHorizontally)
		{
			// Fall back to horizontal if no vertical scrolling
			ScrollBy(-e.DeltaY * scrollAmount, 0);
			return true;
		}

		return false;
	}

	/// Handles key down.
	protected override bool OnKeyDown(KeyEventArgs e)
	{
		let scrollAmount = 40.0f;
		let pageAmount = mViewport.Y * 0.9f;

		switch (e.Key)
		{
		case .Up:
			if (CanScrollVertically) { ScrollBy(0, -scrollAmount); return true; }
		case .Down:
			if (CanScrollVertically) { ScrollBy(0, scrollAmount); return true; }
		case .Left:
			if (CanScrollHorizontally) { ScrollBy(-scrollAmount, 0); return true; }
		case .Right:
			if (CanScrollHorizontally) { ScrollBy(scrollAmount, 0); return true; }
		case .PageUp:
			if (CanScrollVertically) { ScrollBy(0, -pageAmount); return true; }
		case .PageDown:
			if (CanScrollVertically) { ScrollBy(0, pageAmount); return true; }
		case .Home:
			ScrollTo(0, 0);
			return true;
		case .End:
			ScrollTo(mExtent.X - mViewport.X, mExtent.Y - mViewport.Y);
			return true;
		default:
		}

		return false;
	}
}

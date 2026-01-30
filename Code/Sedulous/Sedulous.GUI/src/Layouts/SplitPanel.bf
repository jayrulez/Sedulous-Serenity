using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.GUI;

/// A panel that splits its area into two resizable sections with a draggable splitter.
public class SplitPanel : Panel
{
	private Orientation mOrientation = .Horizontal;
	private float mSplitRatio = 0.5f;  // 0.0 to 1.0
	private float mSplitterSize = 6;
	private float mMinFirstSize = 50;
	private float mMinSecondSize = 50;
	private Color mSplitterColor = Color(80, 80, 80, 255);
	private Color mSplitterHoverColor = Color(100, 100, 100, 255);
	private Color mSplitterDragColor = Color(120, 120, 120, 255);

	// Interaction state
	private bool mIsDragging = false;
	private bool mIsHovered = false;
	private float mDragStartRatio;
	private float mDragStartPos;

	/// The orientation of the split.
	/// Horizontal: first child on left, second on right.
	/// Vertical: first child on top, second on bottom.
	public Orientation Orientation
	{
		get => mOrientation;
		set
		{
			if (mOrientation != value)
			{
				mOrientation = value;
				InvalidateLayout();
			}
		}
	}

	/// The split ratio (0.0 to 1.0). 0.5 means equal split.
	public float SplitRatio
	{
		get => mSplitRatio;
		set
		{
			let clamped = Math.Clamp(value, 0.0f, 1.0f);
			if (mSplitRatio != clamped)
			{
				mSplitRatio = clamped;
				InvalidateLayout();
			}
		}
	}

	/// The size of the splitter bar in pixels.
	public float SplitterSize
	{
		get => mSplitterSize;
		set
		{
			if (mSplitterSize != value)
			{
				mSplitterSize = Math.Max(1, value);
				InvalidateLayout();
			}
		}
	}

	/// Minimum size of the first section.
	public float MinFirstSize
	{
		get => mMinFirstSize;
		set => mMinFirstSize = Math.Max(0, value);
	}

	/// Minimum size of the second section.
	public float MinSecondSize
	{
		get => mMinSecondSize;
		set => mMinSecondSize = Math.Max(0, value);
	}

	/// Color of the splitter bar.
	public Color SplitterColor
	{
		get => mSplitterColor;
		set => mSplitterColor = value;
	}

	/// Color of the splitter bar when hovered.
	public Color SplitterHoverColor
	{
		get => mSplitterHoverColor;
		set => mSplitterHoverColor = value;
	}

	/// Color of the splitter bar when being dragged.
	public Color SplitterDragColor
	{
		get => mSplitterDragColor;
		set => mSplitterDragColor = value;
	}

	/// Gets the first child (left/top section).
	public UIElement FirstChild => ChildCount > 0 ? GetChild(0) : null;

	/// Gets the second child (right/bottom section).
	public UIElement SecondChild => ChildCount > 1 ? GetChild(1) : null;

	/// Gets the splitter rectangle in content bounds.
	private RectangleF GetSplitterRect(RectangleF contentBounds)
	{
		float availableSize = mOrientation == .Horizontal ?
			contentBounds.Width - mSplitterSize :
			contentBounds.Height - mSplitterSize;

		float firstSize = availableSize * mSplitRatio;

		if (mOrientation == .Horizontal)
		{
			return .(
				contentBounds.X + firstSize,
				contentBounds.Y,
				mSplitterSize,
				contentBounds.Height
			);
		}
		else
		{
			return .(
				contentBounds.X,
				contentBounds.Y + firstSize,
				contentBounds.Width,
				mSplitterSize
			);
		}
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		float firstWidth = 0, firstHeight = 0;
		float secondWidth = 0, secondHeight = 0;

		// Measure first child
		if (FirstChild != null && FirstChild.Visibility != .Collapsed)
		{
			let size = FirstChild.Measure(constraints);
			firstWidth = size.Width;
			firstHeight = size.Height;
		}

		// Measure second child
		if (SecondChild != null && SecondChild.Visibility != .Collapsed)
		{
			let size = SecondChild.Measure(constraints);
			secondWidth = size.Width;
			secondHeight = size.Height;
		}

		if (mOrientation == .Horizontal)
		{
			return .(
				firstWidth + mSplitterSize + secondWidth,
				Math.Max(firstHeight, secondHeight)
			);
		}
		else
		{
			return .(
				Math.Max(firstWidth, secondWidth),
				firstHeight + mSplitterSize + secondHeight
			);
		}
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		float availableSize = mOrientation == .Horizontal ?
			contentBounds.Width - mSplitterSize :
			contentBounds.Height - mSplitterSize;

		// Clamp ratio to respect minimum sizes
		float minRatio = mMinFirstSize / Math.Max(1, availableSize);
		float maxRatio = 1.0f - (mMinSecondSize / Math.Max(1, availableSize));
		float clampedRatio = Math.Clamp(mSplitRatio, minRatio, maxRatio);

		float firstSize = availableSize * clampedRatio;
		float secondSize = availableSize - firstSize;

		// Arrange first child
		if (FirstChild != null && FirstChild.Visibility != .Collapsed)
		{
			RectangleF firstRect;
			if (mOrientation == .Horizontal)
			{
				firstRect = .(contentBounds.X, contentBounds.Y, firstSize, contentBounds.Height);
			}
			else
			{
				firstRect = .(contentBounds.X, contentBounds.Y, contentBounds.Width, firstSize);
			}
			FirstChild.Arrange(firstRect);
		}

		// Arrange second child
		if (SecondChild != null && SecondChild.Visibility != .Collapsed)
		{
			RectangleF secondRect;
			if (mOrientation == .Horizontal)
			{
				secondRect = .(
					contentBounds.X + firstSize + mSplitterSize,
					contentBounds.Y,
					secondSize,
					contentBounds.Height
				);
			}
			else
			{
				secondRect = .(
					contentBounds.X,
					contentBounds.Y + firstSize + mSplitterSize,
					contentBounds.Width,
					secondSize
				);
			}
			SecondChild.Arrange(secondRect);
		}
	}

	protected override void RenderOverride(DrawContext ctx)
	{
		// Draw background
		base.RenderOverride(ctx);

		// Draw splitter
		let splitterRect = GetSplitterRect(ContentBounds);
		Color splitterColor = mIsDragging ? mSplitterDragColor :
			(mIsHovered ? mSplitterHoverColor : mSplitterColor);
		ctx.FillRect(splitterRect, splitterColor);

		// Render children (already done by base, but we need to ensure order)
	}

	public override UIElement HitTest(Vector2 point)
	{
		if (Visibility != .Visible)
			return null;

		if (!ArrangedBounds.Contains(point.X, point.Y))
			return null;

		// Check if hit is on splitter
		let splitterRect = GetSplitterRect(ContentBounds);
		if (splitterRect.Contains(point.X, point.Y))
			return this;  // Splitter is part of this panel

		// Check children
		for (int i = ChildCount - 1; i >= 0; i--)
		{
			let child = GetChild(i);
			if (child == null)
				continue;
			let hit = child.HitTest(point);
			if (hit != null)
				return hit;
		}

		return this;
	}

	protected override void OnMouseMove(MouseEventArgs e)
	{
		let splitterRect = GetSplitterRect(ContentBounds);
		mIsHovered = splitterRect.Contains(e.ScreenX, e.ScreenY);

		if (mIsDragging)
		{
			// Calculate new ratio based on mouse position
			float availableSize = mOrientation == .Horizontal ?
				ContentBounds.Width - mSplitterSize :
				ContentBounds.Height - mSplitterSize;

			float currentPos = mOrientation == .Horizontal ?
				e.ScreenX - ContentBounds.X :
				e.ScreenY - ContentBounds.Y;

			float newRatio = currentPos / Math.Max(1, availableSize);

			// Clamp to respect minimum sizes
			float minRatio = mMinFirstSize / Math.Max(1, availableSize);
			float maxRatio = 1.0f - (mMinSecondSize / Math.Max(1, availableSize));
			SplitRatio = Math.Clamp(newRatio, minRatio, maxRatio);
		}

		base.OnMouseMove(e);
	}

	protected override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button == .Left)
		{
			let splitterRect = GetSplitterRect(ContentBounds);
			if (splitterRect.Contains(e.ScreenX, e.ScreenY))
			{
				mIsDragging = true;
				mDragStartRatio = mSplitRatio;
				mDragStartPos = mOrientation == .Horizontal ? e.ScreenX : e.ScreenY;
				Context?.FocusManager?.SetCapture(this);
			}
		}

		base.OnMouseDown(e);
	}

	protected override void OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && mIsDragging)
		{
			mIsDragging = false;
			Context?.FocusManager?.ReleaseCapture();
		}

		base.OnMouseUp(e);
	}

	protected override void OnMouseLeave(MouseEventArgs e)
	{
		mIsHovered = false;
		base.OnMouseLeave(e);
	}
}

namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// Resizable split pane with two children separated by a draggable divider.
public class SplitView : ViewGroup
{
	private Orientation mOrientation = .Horizontal;
	private float mSplitRatio = 0.5f;
	private float mDividerSize = 6;
	private float mMinPaneSize = 50;
	private bool mIsDragging;
	private bool mIsDividerHovered;

	private EventAccessor<delegate void(SplitView, float)> mOnSplitChanged = new .() ~ delete _;

	public Orientation Orientation
	{
		get => mOrientation;
		set { mOrientation = value; InvalidateLayout(); }
	}

	/// Split ratio from 0.0 to 1.0. 0.5 = equal split.
	public float SplitRatio
	{
		get => mSplitRatio;
		set
		{
			float clamped = Math.Clamp(value, 0.0f, 1.0f);
			if (mSplitRatio != clamped)
			{
				mSplitRatio = clamped;
				InvalidateLayout();
				mOnSplitChanged.[Friend]Invoke(this, clamped);
			}
		}
	}

	public float DividerSize
	{
		get => mDividerSize;
		set { mDividerSize = Math.Max(2, value); InvalidateLayout(); }
	}

	public float MinPaneSize
	{
		get => mMinPaneSize;
		set { mMinPaneSize = Math.Max(0, value); }
	}

	/// Subscribe to split ratio change events.
	public EventAccessor<delegate void(SplitView, float)> OnSplitChanged => mOnSplitChanged;

	public this()
	{
	}

	public this(Orientation orientation) : this()
	{
		mOrientation = orientation;
	}

	/// Convenience: set both panes at once.
	public void SetPanes(View first, View second)
	{
		// Remove existing children
		while (ChildCount > 0)
			RemoveView(GetChildAt(0));

		if (first != null) AddView(first);
		if (second != null) AddView(second);
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(0, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(0, MinHeight, MaxHeight);

		// Measure both children with AtMost
		for (int i = 0; i < Math.Min(ChildCount, 2); i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;
			child.Measure(MeasureSpec.MakeAtMost(w), MeasureSpec.MakeAtMost(h));
		}

		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		if (ChildCount < 2) return;

		let first = GetChildAt(0);
		let second = GetChildAt(1);

		if (mOrientation == .Horizontal)
		{
			float available = width - mDividerSize;
			float firstW = available * mSplitRatio;

			// Enforce min pane sizes
			firstW = Math.Clamp(firstW, mMinPaneSize, available - mMinPaneSize);
			float secondW = available - firstW;

			if (first.Visibility != .Gone)
				first.Layout(0, 0, firstW, height);
			if (second.Visibility != .Gone)
				second.Layout(firstW + mDividerSize, 0, secondW, height);
		}
		else
		{
			float available = height - mDividerSize;
			float firstH = available * mSplitRatio;

			firstH = Math.Clamp(firstH, mMinPaneSize, available - mMinPaneSize);
			float secondH = available - firstH;

			if (first.Visibility != .Gone)
				first.Layout(0, 0, width, firstH);
			if (second.Visibility != .Gone)
				second.Layout(0, firstH + mDividerSize, width, secondH);
		}
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Draw children
		for (int i = 0; i < Math.Min(ChildCount, 2); i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility != .Gone)
				child.Draw(ctx);
		}

		// Draw divider
		let dividerRect = GetDividerRect();
		let dividerColor = (mIsDragging || mIsDividerHovered)
			? (theme?.GetColor("SplitView", "dividerHoverColor") ?? palette.Accent)
			: (theme?.GetColor("SplitView", "dividerColor") ?? palette.Border);

		ctx.FillRect(dividerRect, dividerColor);

		// Draw grip dots in center of divider
		let gripColor = Palette.WithAlpha(dividerColor, 153);
		if (mOrientation == .Horizontal)
		{
			float cx = dividerRect.X + dividerRect.Width * 0.5f;
			float cy = dividerRect.Y + dividerRect.Height * 0.5f;
			for (int i = -1; i <= 1; i++)
				ctx.FillCircle(.(cx, cy + i * 6), 1.5f, gripColor);
		}
		else
		{
			float cx = dividerRect.X + dividerRect.Width * 0.5f;
			float cy = dividerRect.Y + dividerRect.Height * 0.5f;
			for (int i = -1; i <= 1; i++)
				ctx.FillCircle(.(cx + i * 6, cy), 1.5f, gripColor);
		}
	}

	public override View HitTest(Vector2 point)
	{
		if (Visibility != .Visible || !IsHitTestVisible || IsPendingDeletion)
			return null;

		let localPoint = PointToLocal(point);

		// Bounds check — don't claim hits outside our area
		if (localPoint.X < 0 || localPoint.Y < 0 || localPoint.X > Width || localPoint.Y > Height)
			return null;

		// Check if point is in divider zone
		let dividerRect = GetDividerRect();
		if (localPoint.X >= dividerRect.X && localPoint.X < dividerRect.X + dividerRect.Width &&
			localPoint.Y >= dividerRect.Y && localPoint.Y < dividerRect.Y + dividerRect.Height)
		{
			return this; // Divider hit — we handle it
		}

		// Delegate to children
		for (int i = ChildCount - 1; i >= 0; i--)
		{
			let child = GetChildAt(i);
			let hit = child.HitTest(localPoint);
			if (hit != null) return hit;
		}

		return IsHitTestVisible ? this : null;
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left)
			return;

		let dividerRect = GetDividerRect();
		if (IsPointInRect(e.LocalX, e.LocalY, dividerRect))
		{
			mIsDragging = true;
			Context?.FocusManager.SetCapture(this);
			e.Handled = true;
		}
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		if (mIsDragging)
		{
			UpdateSplitFromMouse(e.LocalX, e.LocalY);
		}
		else
		{
			// Update hover state for cursor
			let dividerRect = GetDividerRect();
			bool wasHovered = mIsDividerHovered;
			mIsDividerHovered = IsPointInRect(e.LocalX, e.LocalY, dividerRect);
			if (mIsDividerHovered != wasHovered)
			{
				CursorType = mIsDividerHovered
					? (mOrientation == .Horizontal ? .ResizeEW : .ResizeNS)
					: .Default;
				Invalidate();
			}
		}
	}

	public override void OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button != .Left) return;

		if (mIsDragging)
		{
			mIsDragging = false;
			Context?.FocusManager.ReleaseCapture();
			e.Handled = true;
		}
	}

	public override void OnMouseLeave(MouseEventArgs e)
	{
		if (mIsDividerHovered)
		{
			mIsDividerHovered = false;
			CursorType = .Default;
			Invalidate();
		}
	}

	private RectangleF GetDividerRect()
	{
		if (ChildCount < 2)
			return .(0, 0, 0, 0);

		if (mOrientation == .Horizontal)
		{
			float available = Width - mDividerSize;
			float firstW = Math.Clamp(available * mSplitRatio, mMinPaneSize, available - mMinPaneSize);
			return .(firstW, 0, mDividerSize, Height);
		}
		else
		{
			float available = Height - mDividerSize;
			float firstH = Math.Clamp(available * mSplitRatio, mMinPaneSize, available - mMinPaneSize);
			return .(0, firstH, Width, mDividerSize);
		}
	}

	private void UpdateSplitFromMouse(float localX, float localY)
	{
		float ratio;
		if (mOrientation == .Horizontal)
		{
			float available = Width - mDividerSize;
			ratio = (available > 0) ? (localX - mDividerSize * 0.5f) / available : 0.5f;
		}
		else
		{
			float available = Height - mDividerSize;
			ratio = (available > 0) ? (localY - mDividerSize * 0.5f) / available : 0.5f;
		}

		SplitRatio = ratio; // Property clamps and fires event
	}

	private static bool IsPointInRect(float x, float y, RectangleF rect)
	{
		return x >= rect.X && x < rect.X + rect.Width &&
			   y >= rect.Y && y < rect.Y + rect.Height;
	}
}

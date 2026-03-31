namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Binary split node for the dock tree. Contains two children separated by a draggable divider.
public class DockSplit : ViewGroup
{
	private Orientation mOrientation = .Horizontal;
	private float mSplitRatio = 0.5f;
	private float mDividerSize = 4;
	private float mMinPaneSize = 50;
	private bool mIsDragging;
	private bool mIsDividerHovered;

	public Orientation Orientation
	{
		get => mOrientation;
		set { mOrientation = value; InvalidateLayout(); }
	}

	public float SplitRatio
	{
		get => mSplitRatio;
		set { mSplitRatio = Math.Clamp(value, 0.05f, 0.95f); InvalidateLayout(); }
	}

	public float DividerSize
	{
		get => mDividerSize;
		set { mDividerSize = Math.Max(2, value); InvalidateLayout(); }
	}

	public float MinPaneSize { get => mMinPaneSize; set { mMinPaneSize = Math.Max(10, value); } }

	/// First child (left or top).
	public View First => (ChildCount > 0) ? GetChildAt(0) : null;

	/// Second child (right or bottom).
	public View Second => (ChildCount > 1) ? GetChildAt(1) : null;

	public this(Orientation orientation = .Horizontal)
	{
		mOrientation = orientation;
	}

	/// Set both children. DockSplit takes ownership.
	public void SetChildren(View first, View second)
	{
		RemoveAllViews();
		if (first != null) AddView(first);
		if (second != null) AddView(second);
		InvalidateLayout();
	}

	private RectangleF GetDividerRect()
	{
		if (mOrientation == .Horizontal)
		{
			float available = Width - mDividerSize;
			float firstW = available * mSplitRatio;
			return .(firstW, 0, mDividerSize, Height);
		}
		else
		{
			float available = Height - mDividerSize;
			float firstH = available * mSplitRatio;
			return .(0, firstH, Width, mDividerSize);
		}
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(200, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(200, MinHeight, MaxHeight);

		if (mOrientation == .Horizontal)
		{
			float available = w - mDividerSize;
			float firstW = available * mSplitRatio;
			float secondW = available - firstW;

			if (First != null) First.Measure(MeasureSpec.MakeExactly(firstW), MeasureSpec.MakeExactly(h));
			if (Second != null) Second.Measure(MeasureSpec.MakeExactly(secondW), MeasureSpec.MakeExactly(h));
		}
		else
		{
			float available = h - mDividerSize;
			float firstH = available * mSplitRatio;
			float secondH = available - firstH;

			if (First != null) First.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(firstH));
			if (Second != null) Second.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(secondH));
		}

		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		if (mOrientation == .Horizontal)
		{
			float available = width - mDividerSize;
			float firstW = available * mSplitRatio;
			float secondW = available - firstW;

			if (First != null) First.Layout(0, 0, firstW, height);
			if (Second != null) Second.Layout(firstW + mDividerSize, 0, secondW, height);
		}
		else
		{
			float available = height - mDividerSize;
			float firstH = available * mSplitRatio;
			float secondH = available - firstH;

			if (First != null) First.Layout(0, 0, width, firstH);
			if (Second != null) Second.Layout(0, firstH + mDividerSize, width, secondH);
		}
	}

	protected override void OnDraw(DrawContext ctx)
	{
		// Draw children
		if (First != null && First.Visibility != .Gone) First.Draw(ctx);
		if (Second != null && Second.Visibility != .Gone) Second.Draw(ctx);

		// Draw divider
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		let dividerRect = GetDividerRect();
		let dividerColor = (mIsDragging || mIsDividerHovered)
			? (theme?.GetColor("DockSplit", "dividerHoverColor") ?? palette.Accent)
			: (theme?.GetColor("DockSplit", "dividerColor") ?? palette.Border);
		ctx.FillRect(dividerRect, dividerColor);
	}

	public override View HitTest(Vector2 point)
	{
		let local = PointToLocal(point);
		if (local.X < 0 || local.Y < 0 || local.X >= Width || local.Y >= Height)
			return null;

		let dividerRect = GetDividerRect();
		if (local.X >= dividerRect.X && local.X < dividerRect.X + dividerRect.Width &&
			local.Y >= dividerRect.Y && local.Y < dividerRect.Y + dividerRect.Height)
			return this;

		// Test children in reverse order
		if (Second != null)
		{
			let hit = Second.HitTest(local);
			if (hit != null) return hit;
		}
		if (First != null)
		{
			let hit = First.HitTest(local);
			if (hit != null) return hit;
		}

		return this;
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (!Enabled || e.Button != .Left) return;

		let dividerRect = GetDividerRect();
		if (e.LocalX >= dividerRect.X && e.LocalX < dividerRect.X + dividerRect.Width &&
			e.LocalY >= dividerRect.Y && e.LocalY < dividerRect.Y + dividerRect.Height)
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
			let dividerRect = GetDividerRect();
			bool overDivider = e.LocalX >= dividerRect.X && e.LocalX < dividerRect.X + dividerRect.Width &&
				e.LocalY >= dividerRect.Y && e.LocalY < dividerRect.Y + dividerRect.Height;

			if (overDivider != mIsDividerHovered)
			{
				mIsDividerHovered = overDivider;
				CursorType = overDivider
					? ((mOrientation == .Horizontal) ? .ResizeEW : .ResizeNS)
					: .Default;
				Invalidate();
			}
		}
	}

	public override void OnMouseUp(MouseButtonEventArgs e)
	{
		if (mIsDragging && e.Button == .Left)
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

	private void UpdateSplitFromMouse(float localX, float localY)
	{
		float ratio;
		if (mOrientation == .Horizontal)
		{
			float available = Width - mDividerSize;
			if (available <= 0) return;
			ratio = (localX - mDividerSize * 0.5f) / available;
		}
		else
		{
			float available = Height - mDividerSize;
			if (available <= 0) return;
			ratio = (localY - mDividerSize * 0.5f) / available;
		}

		SplitRatio = ratio;
	}
}

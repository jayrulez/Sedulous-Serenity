namespace Sedulous.UI;

using System;

/// A ViewGroup that positions children at explicit X,Y coordinates.
/// Children are measured without constraints (Unspecified) and placed at their specified positions.
public class AbsoluteLayout : ViewGroup
{
	/// LayoutParams for AbsoluteLayout children, specifying exact X,Y position.
	public class LayoutParams : Sedulous.UI.LayoutParams
	{
		/// X position relative to the layout's content area (after padding).
		public float X = 0;
		/// Y position relative to the layout's content area (after padding).
		public float Y = 0;

		public this() : base() { }
		public this(float x, float y, float width, float height) : base(width, height)
		{
			X = x;
			Y = y;
		}
	}

	protected override Sedulous.UI.LayoutParams CreateDefaultLayoutParams()
	{
		return new AbsoluteLayout.LayoutParams();
	}

	protected override bool CheckLayoutParams(Sedulous.UI.LayoutParams lp)
	{
		return lp != null;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float maxRight = 0;
		float maxBottom = 0;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			// Measure with no constraints
			let lp = child.LayoutParams;
			MeasureSpec childWidthSpec;
			MeasureSpec childHeightSpec;

			if (lp != null && lp.Width >= 0)
				childWidthSpec = .MakeExactly(lp.Width);
			else
				childWidthSpec = .MakeUnspecified();

			if (lp != null && lp.Height >= 0)
				childHeightSpec = .MakeExactly(lp.Height);
			else
				childHeightSpec = .MakeUnspecified();

			child.Measure(childWidthSpec, childHeightSpec);

			float x = 0, y = 0;
			if (let alp = lp as AbsoluteLayout.LayoutParams)
			{
				x = alp.X;
				y = alp.Y;
			}

			maxRight = Math.Max(maxRight, x + child.MeasuredWidth);
			maxBottom = Math.Max(maxBottom, y + child.MeasuredHeight);
		}

		SetMeasuredDimension(
			widthSpec.Resolve(maxRight + Padding.Horizontal, MinWidth, MaxWidth),
			heightSpec.Resolve(maxBottom + Padding.Vertical, MinHeight, MaxHeight)
		);
	}

	protected override void OnLayout(float width, float height)
	{
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			let lp = child.LayoutParams;
			float x = 0, y = 0;
			if (let alp = lp as AbsoluteLayout.LayoutParams)
			{
				x = alp.X;
				y = alp.Y;
			}

			child.Layout(Padding.Left + x, Padding.Top + y,
				child.MeasuredWidth, child.MeasuredHeight);
		}
	}
}

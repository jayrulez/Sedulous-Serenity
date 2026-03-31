namespace Sedulous.UI;

using System;
using Sedulous.Drawing;

/// A ViewGroup that stacks children on top of each other.
/// Each child can be positioned within the frame using Gravity via FrameLayout.LayoutParams.
/// Default gravity is None (top-left).
public class FrameLayout : ViewGroup
{
	/// LayoutParams for FrameLayout children, adding per-child Gravity.
	public class LayoutParams : Sedulous.UI.LayoutParams
	{
		public Gravity Gravity = .None;

		public this() : base() { }
		public this(float width, float height) : base(width, height) { }
		public this(float width, float height, Gravity gravity) : base(width, height)
		{
			Gravity = gravity;
		}
	}

	protected override Sedulous.UI.LayoutParams CreateDefaultLayoutParams()
	{
		return new FrameLayout.LayoutParams();
	}

	protected override bool CheckLayoutParams(Sedulous.UI.LayoutParams lp)
	{
		return lp != null;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float maxChildWidth = 0;
		float maxChildHeight = 0;
		bool hasMatchParentChild = false;

		// First pass: measure all children
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			MeasureChildWithMargins(child, widthSpec, 0, heightSpec, 0);

			let lp = child.LayoutParams;
			float childWidth = child.MeasuredWidth;
			float childHeight = child.MeasuredHeight;

			if (lp != null)
			{
				childWidth += lp.Margin.Horizontal;
				childHeight += lp.Margin.Vertical;

				if (lp.Width == Sedulous.UI.LayoutParams.MatchParent ||
					lp.Height == Sedulous.UI.LayoutParams.MatchParent)
					hasMatchParentChild = true;
			}

			maxChildWidth = Math.Max(maxChildWidth, childWidth);
			maxChildHeight = Math.Max(maxChildHeight, childHeight);
		}

		// Add padding and resolve own size
		maxChildWidth += Padding.Horizontal;
		maxChildHeight += Padding.Vertical;

		SetMeasuredDimension(
			widthSpec.Resolve(maxChildWidth, MinWidth, MaxWidth),
			heightSpec.Resolve(maxChildHeight, MinHeight, MaxHeight)
		);

		// Second pass: re-measure MatchParent children now that we know our size
		if (hasMatchParentChild)
		{
			for (int i = 0; i < ChildCount; i++)
			{
				let child = GetChildAt(i);
				if (child.Visibility == .Gone)
					continue;

				let lp = child.LayoutParams;
				if (lp == null)
					continue;

				bool remeasure = false;
				MeasureSpec childWidthSpec;
				MeasureSpec childHeightSpec;

				float marginH = lp.Margin.Horizontal;
				float marginV = lp.Margin.Vertical;

				if (lp.Width == Sedulous.UI.LayoutParams.MatchParent)
				{
					childWidthSpec = .MakeExactly(Math.Max(0, MeasuredWidth - Padding.Horizontal - marginH));
					remeasure = true;
				}
				else
				{
					childWidthSpec = ViewGroup.GetChildMeasureSpec(widthSpec, Padding.Horizontal + marginH, lp.Width);
				}

				if (lp.Height == Sedulous.UI.LayoutParams.MatchParent)
				{
					childHeightSpec = .MakeExactly(Math.Max(0, MeasuredHeight - Padding.Vertical - marginV));
					remeasure = true;
				}
				else
				{
					childHeightSpec = ViewGroup.GetChildMeasureSpec(heightSpec, Padding.Vertical + marginV, lp.Height);
				}

				if (remeasure)
					child.Measure(childWidthSpec, childHeightSpec);
			}
		}
	}

	protected override void OnLayout(float width, float height)
	{
		float contentW = width - Padding.Horizontal;
		float contentH = height - Padding.Vertical;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;
			Gravity gravity = .None;

			if (let flp = lp as FrameLayout.LayoutParams)
				gravity = flp.Gravity;

			float outX, outY, outW, outH;
			GravityHelper.Apply(gravity, contentW, contentH,
				child.MeasuredWidth, child.MeasuredHeight, margin,
				out outX, out outY, out outW, out outH);

			child.Layout(Padding.Left + outX, Padding.Top + outY, outW, outH);
		}
	}
}

namespace Sedulous.UI;

using System;

/// A ViewGroup that arranges children in a single row (Horizontal) or column (Vertical).
/// Supports weighted space distribution and cross-axis gravity.
public class LinearLayout : ViewGroup
{
	/// LayoutParams for LinearLayout children, adding Weight and per-child Gravity.
	public class LayoutParams : Sedulous.UI.LayoutParams
	{
		/// Proportional weight for space distribution. 0 = fixed size (measured normally).
		public float Weight = 0;

		/// Per-child gravity (cross-axis alignment). None = use parent's Gravity.
		public Gravity Gravity = .None;

		public this() : base() { }
		public this(float width, float height) : base(width, height) { }
		public this(float width, float height, float weight) : base(width, height)
		{
			Weight = weight;
		}
	}

	/// Main axis direction.
	public Orientation Orientation = .Vertical;

	/// Default cross-axis gravity for children that don't specify their own.
	public Gravity Gravity = .None;

	/// Spacing between consecutive visible children along the main axis.
	public float Spacing = 0;

	/// When true (default) and Orientation is Horizontal, children with baselines
	/// are vertically aligned so their text baselines match.
	public bool BaselineAligned = true;

	protected override Sedulous.UI.LayoutParams CreateDefaultLayoutParams()
	{
		return new LinearLayout.LayoutParams();
	}

	protected override bool CheckLayoutParams(Sedulous.UI.LayoutParams lp)
	{
		return lp != null;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		if (Orientation == .Vertical)
			MeasureVertical(widthSpec, heightSpec);
		else
			MeasureHorizontal(widthSpec, heightSpec);
	}

	private void MeasureVertical(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float totalMainSize = 0;
		float maxCrossSize = 0;
		float totalWeight = 0;
		int visibleCount = 0;

		// Pass 1: measure fixed children, accumulate weight
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;
			float weight = 0;
			if (let llp = lp as LinearLayout.LayoutParams)
				weight = llp.Weight;

			totalWeight += weight;
			visibleCount++;

			if (weight == 0)
			{
				// Fixed child: measure normally
				MeasureChildWithMargins(child, widthSpec, 0, heightSpec, totalMainSize);
				totalMainSize += child.MeasuredHeight + margin.Vertical;
				maxCrossSize = Math.Max(maxCrossSize, child.MeasuredWidth + margin.Horizontal);
			}
			else
			{
				// Weighted child: just count margin for now
				totalMainSize += margin.Vertical;
			}
		}

		// Add spacing
		float totalSpacing = Math.Max(0, visibleCount - 1) * Spacing;
		totalMainSize += totalSpacing;

		// Pass 2: distribute remaining space to weighted children
		if (totalWeight > 0)
		{
			float availableMain = 0;
			if (heightSpec.SpecMode != .Unspecified)
				availableMain = Math.Max(0, heightSpec.Size - Padding.Vertical - totalMainSize);

			for (int i = 0; i < ChildCount; i++)
			{
				let child = GetChildAt(i);
				if (child.Visibility == .Gone)
					continue;

				let lp = child.LayoutParams;
				float weight = 0;
				if (let llp = lp as LinearLayout.LayoutParams)
					weight = llp.Weight;

				if (weight > 0)
				{
					Thickness margin = (lp != null) ? lp.Margin : .Zero;
					float childMainSize = availableMain * (weight / totalWeight);
					let childHeightSpec = MeasureSpec.MakeExactly(Math.Max(0, childMainSize));
					let childWidthSpec = ViewGroup.GetChildMeasureSpec(widthSpec, Padding.Horizontal + margin.Horizontal, (lp != null) ? lp.Width : Sedulous.UI.LayoutParams.WrapContent);
					child.Measure(childWidthSpec, childHeightSpec);
					totalMainSize += child.MeasuredHeight;
					maxCrossSize = Math.Max(maxCrossSize, child.MeasuredWidth + margin.Horizontal);
				}
			}
		}

		float desiredWidth = maxCrossSize + Padding.Horizontal;
		float desiredHeight = totalMainSize + Padding.Vertical;

		SetMeasuredDimension(
			widthSpec.Resolve(desiredWidth, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredHeight, MinHeight, MaxHeight)
		);
	}

	private void MeasureHorizontal(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float totalMainSize = 0;
		float maxCrossSize = 0;
		float totalWeight = 0;
		int visibleCount = 0;

		// Baseline tracking
		float maxBaseline = 0;
		float maxDescentFromBaseline = 0;
		bool hasBaseline = false;

		// Pass 1: measure fixed children, accumulate weight
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;
			float weight = 0;
			if (let llp = lp as LinearLayout.LayoutParams)
				weight = llp.Weight;

			totalWeight += weight;
			visibleCount++;

			if (weight == 0)
			{
				MeasureChildWithMargins(child, widthSpec, totalMainSize, heightSpec, 0);
				totalMainSize += child.MeasuredWidth + margin.Horizontal;

				if (BaselineAligned)
				{
					float childBaseline = child.GetBaseline();
					if (childBaseline >= 0)
					{
						hasBaseline = true;
						maxBaseline = Math.Max(maxBaseline, margin.Top + childBaseline);
						maxDescentFromBaseline = Math.Max(maxDescentFromBaseline,
							child.MeasuredHeight + margin.Vertical - (margin.Top + childBaseline));
					}
					else
					{
						maxCrossSize = Math.Max(maxCrossSize, child.MeasuredHeight + margin.Vertical);
					}
				}
				else
				{
					maxCrossSize = Math.Max(maxCrossSize, child.MeasuredHeight + margin.Vertical);
				}
			}
			else
			{
				totalMainSize += margin.Horizontal;
			}
		}

		float totalSpacing = Math.Max(0, visibleCount - 1) * Spacing;
		totalMainSize += totalSpacing;

		// Pass 2: distribute remaining space to weighted children
		if (totalWeight > 0)
		{
			float availableMain = 0;
			if (widthSpec.SpecMode != .Unspecified)
				availableMain = Math.Max(0, widthSpec.Size - Padding.Horizontal - totalMainSize);

			for (int i = 0; i < ChildCount; i++)
			{
				let child = GetChildAt(i);
				if (child.Visibility == .Gone)
					continue;

				let lp = child.LayoutParams;
				float weight = 0;
				if (let llp = lp as LinearLayout.LayoutParams)
					weight = llp.Weight;

				if (weight > 0)
				{
					Thickness margin = (lp != null) ? lp.Margin : .Zero;
					float childMainSize = availableMain * (weight / totalWeight);
					let childWidthSpec = MeasureSpec.MakeExactly(Math.Max(0, childMainSize));
					let childHeightSpec = ViewGroup.GetChildMeasureSpec(heightSpec, Padding.Vertical + margin.Vertical, (lp != null) ? lp.Height : Sedulous.UI.LayoutParams.WrapContent);
					child.Measure(childWidthSpec, childHeightSpec);
					totalMainSize += child.MeasuredWidth;

					if (BaselineAligned)
					{
						float childBaseline = child.GetBaseline();
						if (childBaseline >= 0)
						{
							hasBaseline = true;
							maxBaseline = Math.Max(maxBaseline, margin.Top + childBaseline);
							maxDescentFromBaseline = Math.Max(maxDescentFromBaseline,
								child.MeasuredHeight + margin.Vertical - (margin.Top + childBaseline));
						}
						else
						{
							maxCrossSize = Math.Max(maxCrossSize, child.MeasuredHeight + margin.Vertical);
						}
					}
					else
					{
						maxCrossSize = Math.Max(maxCrossSize, child.MeasuredHeight + margin.Vertical);
					}
				}
			}
		}

		// If baseline aligned, cross size = max(baseline + descent, non-baseline children)
		if (hasBaseline)
			maxCrossSize = Math.Max(maxCrossSize, maxBaseline + maxDescentFromBaseline);

		float desiredWidth = totalMainSize + Padding.Horizontal;
		float desiredHeight = maxCrossSize + Padding.Vertical;

		SetMeasuredDimension(
			widthSpec.Resolve(desiredWidth, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredHeight, MinHeight, MaxHeight)
		);
	}

	protected override void OnLayout(float width, float height)
	{
		if (Orientation == .Vertical)
			LayoutVertical(width, height);
		else
			LayoutHorizontal(width, height);
	}

	private void LayoutVertical(float width, float height)
	{
		float contentW = width - Padding.Horizontal;
		float cursor = 0;
		bool first = true;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			if (!first)
				cursor += Spacing;
			first = false;

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;

			// Resolve cross-axis gravity (horizontal)
			Gravity childGravity = this.Gravity;
			if (let llp = lp as LinearLayout.LayoutParams)
			{
				if (llp.Gravity != .None)
					childGravity = llp.Gravity;
			}

			cursor += margin.Top;

			// Apply horizontal gravity for cross-axis positioning
			float outX, outY, outW, outH;
			GravityHelper.Apply(childGravity, contentW, child.MeasuredHeight,
				child.MeasuredWidth, child.MeasuredHeight, .(margin.Left, 0, margin.Right, 0),
				out outX, out outY, out outW, out outH);

			child.Layout(Padding.Left + outX, Padding.Top + cursor, outW, child.MeasuredHeight);
			cursor += child.MeasuredHeight + margin.Bottom;
		}
	}

	private void LayoutHorizontal(float width, float height)
	{
		float contentH = height - Padding.Vertical;
		float cursor = 0;
		bool first = true;

		// Compute max baseline for alignment
		float maxBaselinePos = 0;
		bool hasBaseline = false;

		if (BaselineAligned)
		{
			for (int i = 0; i < ChildCount; i++)
			{
				let child = GetChildAt(i);
				if (child.Visibility == .Gone)
					continue;

				let lp = child.LayoutParams;
				Thickness margin = (lp != null) ? lp.Margin : .Zero;

				float childBaseline = child.GetBaseline();
				if (childBaseline >= 0)
				{
					hasBaseline = true;
					maxBaselinePos = Math.Max(maxBaselinePos, margin.Top + childBaseline);
				}
			}
		}

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			if (!first)
				cursor += Spacing;
			first = false;

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;

			cursor += margin.Left;

			float childY;

			// Try baseline alignment first
			if (hasBaseline)
			{
				float childBaseline = child.GetBaseline();
				if (childBaseline >= 0)
				{
					// Align this child's baseline with maxBaselinePos
					childY = maxBaselinePos - childBaseline;
				}
				else
				{
					// No baseline — fall back to gravity
					Gravity childGravity = this.Gravity;
					if (let llp = lp as LinearLayout.LayoutParams)
					{
						if (llp.Gravity != .None)
							childGravity = llp.Gravity;
					}

					float outX, outY, outW, outH;
					GravityHelper.Apply(childGravity, child.MeasuredWidth, contentH,
						child.MeasuredWidth, child.MeasuredHeight, .(0, margin.Top, 0, margin.Bottom),
						out outX, out outY, out outW, out outH);
					childY = outY;
				}
			}
			else
			{
				// No baseline children — use gravity
				Gravity childGravity = this.Gravity;
				if (let llp = lp as LinearLayout.LayoutParams)
				{
					if (llp.Gravity != .None)
						childGravity = llp.Gravity;
				}

				float outX, outY, outW, outH;
				GravityHelper.Apply(childGravity, child.MeasuredWidth, contentH,
					child.MeasuredWidth, child.MeasuredHeight, .(0, margin.Top, 0, margin.Bottom),
					out outX, out outY, out outW, out outH);
				childY = outY;
			}

			child.Layout(Padding.Left + cursor, Padding.Top + childY, child.MeasuredWidth, child.MeasuredHeight);
			cursor += child.MeasuredWidth + margin.Right;
		}
	}
}

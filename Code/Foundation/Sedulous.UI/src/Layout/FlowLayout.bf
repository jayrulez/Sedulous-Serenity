namespace Sedulous.UI;

using System;

/// A ViewGroup that arranges children sequentially along the main axis,
/// wrapping to new lines when the available space is exceeded.
/// Similar to Android's FlexboxLayout with wrap enabled.
public class FlowLayout : ViewGroup
{
	/// Spacing between items along the main axis.
	public float HSpacing = 4;

	/// Spacing between lines along the cross axis.
	public float VSpacing = 4;

	/// Main axis direction. Horizontal wraps to new rows; Vertical wraps to new columns.
	public Orientation Orientation = .Horizontal;

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		if (Orientation == .Horizontal)
			MeasureHorizontal(widthSpec, heightSpec);
		else
			MeasureVertical(widthSpec, heightSpec);
	}

	private void MeasureHorizontal(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float availableW = (widthSpec.SpecMode != .Unspecified)
			? widthSpec.Size - Padding.Horizontal
			: float.MaxValue;

		float lineWidth = 0;
		float lineHeight = 0;
		float totalHeight = 0;
		float maxLineWidth = 0;
		bool firstInLine = true;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			MeasureChildWithMargins(child, widthSpec, 0, heightSpec, 0);

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;
			float childW = child.MeasuredWidth + margin.Horizontal;
			float childH = child.MeasuredHeight + margin.Vertical;

			float neededW = firstInLine ? childW : childW + HSpacing;

			if (!firstInLine && lineWidth + neededW > availableW)
			{
				// Wrap to next line
				maxLineWidth = Math.Max(maxLineWidth, lineWidth);
				totalHeight += lineHeight + VSpacing;
				lineWidth = childW;
				lineHeight = childH;
				firstInLine = false;
			}
			else
			{
				lineWidth += neededW;
				lineHeight = Math.Max(lineHeight, childH);
				firstInLine = false;
			}
		}

		// Account for last line
		maxLineWidth = Math.Max(maxLineWidth, lineWidth);
		totalHeight += lineHeight;

		float desiredW = maxLineWidth + Padding.Horizontal;
		float desiredH = totalHeight + Padding.Vertical;

		SetMeasuredDimension(
			widthSpec.Resolve(desiredW, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	private void MeasureVertical(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float availableH = (heightSpec.SpecMode != .Unspecified)
			? heightSpec.Size - Padding.Vertical
			: float.MaxValue;

		float colHeight = 0;
		float colWidth = 0;
		float totalWidth = 0;
		float maxColHeight = 0;
		bool firstInCol = true;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			MeasureChildWithMargins(child, widthSpec, 0, heightSpec, 0);

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;
			float childW = child.MeasuredWidth + margin.Horizontal;
			float childH = child.MeasuredHeight + margin.Vertical;

			float neededH = firstInCol ? childH : childH + VSpacing;

			if (!firstInCol && colHeight + neededH > availableH)
			{
				// Wrap to next column
				maxColHeight = Math.Max(maxColHeight, colHeight);
				totalWidth += colWidth + HSpacing;
				colHeight = childH;
				colWidth = childW;
				firstInCol = false;
			}
			else
			{
				colHeight += neededH;
				colWidth = Math.Max(colWidth, childW);
				firstInCol = false;
			}
		}

		// Account for last column
		maxColHeight = Math.Max(maxColHeight, colHeight);
		totalWidth += colWidth;

		float desiredW = totalWidth + Padding.Horizontal;
		float desiredH = maxColHeight + Padding.Vertical;

		SetMeasuredDimension(
			widthSpec.Resolve(desiredW, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnLayout(float width, float height)
	{
		if (Orientation == .Horizontal)
			LayoutHorizontal(width, height);
		else
			LayoutVertical(width, height);
	}

	private void LayoutHorizontal(float width, float height)
	{
		float availableW = width - Padding.Horizontal;
		float cursorX = 0;
		float cursorY = 0;
		float lineHeight = 0;
		bool firstInLine = true;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;
			float childW = child.MeasuredWidth + margin.Horizontal;
			float childH = child.MeasuredHeight + margin.Vertical;

			float neededW = firstInLine ? childW : childW + HSpacing;

			if (!firstInLine && cursorX + neededW > availableW)
			{
				// Wrap
				cursorX = 0;
				cursorY += lineHeight + VSpacing;
				lineHeight = 0;
				firstInLine = true;
			}

			if (!firstInLine)
				cursorX += HSpacing;

			child.Layout(
				Padding.Left + cursorX + margin.Left,
				Padding.Top + cursorY + margin.Top,
				child.MeasuredWidth,
				child.MeasuredHeight
			);

			cursorX += childW;
			lineHeight = Math.Max(lineHeight, childH);
			firstInLine = false;
		}
	}

	private void LayoutVertical(float width, float height)
	{
		float availableH = height - Padding.Vertical;
		float cursorX = 0;
		float cursorY = 0;
		float colWidth = 0;
		bool firstInCol = true;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone)
				continue;

			let lp = child.LayoutParams;
			Thickness margin = (lp != null) ? lp.Margin : .Zero;
			float childW = child.MeasuredWidth + margin.Horizontal;
			float childH = child.MeasuredHeight + margin.Vertical;

			float neededH = firstInCol ? childH : childH + VSpacing;

			if (!firstInCol && cursorY + neededH > availableH)
			{
				// Wrap to next column
				cursorY = 0;
				cursorX += colWidth + HSpacing;
				colWidth = 0;
				firstInCol = true;
			}

			if (!firstInCol)
				cursorY += VSpacing;

			child.Layout(
				Padding.Left + cursorX + margin.Left,
				Padding.Top + cursorY + margin.Top,
				child.MeasuredWidth,
				child.MeasuredHeight
			);

			cursorY += childH;
			colWidth = Math.Max(colWidth, childW);
			firstInCol = false;
		}
	}
}

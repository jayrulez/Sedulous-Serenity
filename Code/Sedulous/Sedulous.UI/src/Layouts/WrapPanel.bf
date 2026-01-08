using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Arranges children in sequential lines, wrapping to the next line when needed.
public class WrapPanel : Panel
{
	private Orientation mOrientation = .Horizontal;
	private float mItemWidth = 0;
	private float mItemHeight = 0;
	private float mHorizontalSpacing = 0;
	private float mVerticalSpacing = 0;

	/// The direction in which children are arranged before wrapping.
	public Orientation Orientation
	{
		get => mOrientation;
		set { mOrientation = value; InvalidateMeasure(); }
	}

	/// Fixed width for all items. 0 means use each item's desired width.
	public float ItemWidth
	{
		get => mItemWidth;
		set { mItemWidth = value; InvalidateMeasure(); }
	}

	/// Fixed height for all items. 0 means use each item's desired height.
	public float ItemHeight
	{
		get => mItemHeight;
		set { mItemHeight = value; InvalidateMeasure(); }
	}

	/// Horizontal spacing between items.
	public float HorizontalSpacing
	{
		get => mHorizontalSpacing;
		set { mHorizontalSpacing = value; InvalidateMeasure(); }
	}

	/// Vertical spacing between items/lines.
	public float VerticalSpacing
	{
		get => mVerticalSpacing;
		set { mVerticalSpacing = value; InvalidateMeasure(); }
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		var totalWidth = 0.0f;
		var totalHeight = 0.0f;
		var lineSize = 0.0f;
		var lineCross = 0.0f;
		var lineItemCount = 0;

		let maxMain = mOrientation == .Horizontal ? constraints.MaxWidth : constraints.MaxHeight;
		let spacing = mOrientation == .Horizontal ? mHorizontalSpacing : mVerticalSpacing;

		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			child.Measure(.Unconstrained);

			let itemWidth = mItemWidth > 0 ? mItemWidth : child.DesiredSize.Width;
			let itemHeight = mItemHeight > 0 ? mItemHeight : child.DesiredSize.Height;
			let itemMain = mOrientation == .Horizontal ? itemWidth : itemHeight;
			let itemCross = mOrientation == .Horizontal ? itemHeight : itemWidth;

			// Check if we need to wrap
			let spacingForItem = lineItemCount > 0 ? spacing : 0;
			if (lineSize + spacingForItem + itemMain > maxMain && lineItemCount > 0)
			{
				// Wrap to next line
				if (mOrientation == .Horizontal)
				{
					totalWidth = Math.Max(totalWidth, lineSize);
					totalHeight += lineCross;
					if (totalHeight > 0) totalHeight += mVerticalSpacing;
				}
				else
				{
					totalHeight = Math.Max(totalHeight, lineSize);
					totalWidth += lineCross;
					if (totalWidth > 0) totalWidth += mHorizontalSpacing;
				}
				lineSize = 0;
				lineCross = 0;
				lineItemCount = 0;
			}

			if (lineItemCount > 0)
				lineSize += spacing;
			lineSize += itemMain;
			lineCross = Math.Max(lineCross, itemCross);
			lineItemCount++;
		}

		// Add last line
		if (lineItemCount > 0)
		{
			if (mOrientation == .Horizontal)
			{
				totalWidth = Math.Max(totalWidth, lineSize);
				if (totalHeight > 0) totalHeight += mVerticalSpacing;
				totalHeight += lineCross;
			}
			else
			{
				totalHeight = Math.Max(totalHeight, lineSize);
				if (totalWidth > 0) totalWidth += mHorizontalSpacing;
				totalWidth += lineCross;
			}
		}

		return .(totalWidth, totalHeight);
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		var currentMain = 0.0f;
		var currentCross = 0.0f;
		var lineCross = 0.0f;
		var lineItemCount = 0;

		let maxMain = mOrientation == .Horizontal ? contentBounds.Width : contentBounds.Height;
		let spacing = mOrientation == .Horizontal ? mHorizontalSpacing : mVerticalSpacing;
		let crossSpacing = mOrientation == .Horizontal ? mVerticalSpacing : mHorizontalSpacing;

		// First pass: calculate line heights for proper cross positioning
		// Second pass: arrange items

		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			let itemWidth = mItemWidth > 0 ? mItemWidth : child.DesiredSize.Width;
			let itemHeight = mItemHeight > 0 ? mItemHeight : child.DesiredSize.Height;
			let itemMain = mOrientation == .Horizontal ? itemWidth : itemHeight;
			let itemCross = mOrientation == .Horizontal ? itemHeight : itemWidth;

			// Check if we need to wrap
			let spacingForItem = lineItemCount > 0 ? spacing : 0;
			if (currentMain + spacingForItem + itemMain > maxMain && lineItemCount > 0)
			{
				// Wrap to next line
				currentCross += lineCross + crossSpacing;
				currentMain = 0;
				lineCross = 0;
				lineItemCount = 0;
			}

			if (lineItemCount > 0)
				currentMain += spacing;

			// Position the child
			RectangleF childRect;
			if (mOrientation == .Horizontal)
			{
				childRect = .(
					contentBounds.X + currentMain,
					contentBounds.Y + currentCross,
					itemWidth,
					itemHeight
				);
			}
			else
			{
				childRect = .(
					contentBounds.X + currentCross,
					contentBounds.Y + currentMain,
					itemWidth,
					itemHeight
				);
			}

			child.Arrange(childRect);

			currentMain += itemMain;
			lineCross = Math.Max(lineCross, itemCross);
			lineItemCount++;
		}
	}
}

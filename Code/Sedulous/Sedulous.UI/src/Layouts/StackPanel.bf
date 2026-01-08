using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Arranges children in a single line, either horizontally or vertically.
public class StackPanel : Panel
{
	private Orientation mOrientation = .Vertical;
	private float mSpacing = 0;

	/// The direction in which children are stacked.
	public Orientation Orientation
	{
		get => mOrientation;
		set { mOrientation = value; InvalidateMeasure(); }
	}

	/// Space between children in pixels.
	public float Spacing
	{
		get => mSpacing;
		set { mSpacing = value; InvalidateMeasure(); }
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		var totalWidth = 0.0f;
		var totalHeight = 0.0f;
		var maxCrossAxis = 0.0f;
		var childCount = 0;

		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			// For the stacking direction, don't constrain
			// For the cross axis, use the available constraint
			SizeConstraints childConstraints;
			if (mOrientation == .Horizontal)
			{
				childConstraints = SizeConstraints(
					0, constraints.MinHeight,
					SizeConstraints.Infinity, constraints.MaxHeight
				);
			}
			else
			{
				childConstraints = SizeConstraints(
					constraints.MinWidth, 0,
					constraints.MaxWidth, SizeConstraints.Infinity
				);
			}

			child.Measure(childConstraints);

			if (mOrientation == .Horizontal)
			{
				totalWidth += child.DesiredSize.Width;
				maxCrossAxis = Math.Max(maxCrossAxis, child.DesiredSize.Height);
			}
			else
			{
				totalHeight += child.DesiredSize.Height;
				maxCrossAxis = Math.Max(maxCrossAxis, child.DesiredSize.Width);
			}

			childCount++;
		}

		// Add spacing between children
		let spacingTotal = childCount > 1 ? mSpacing * (childCount - 1) : 0;

		if (mOrientation == .Horizontal)
		{
			totalWidth += spacingTotal;
			totalHeight = maxCrossAxis;
		}
		else
		{
			totalHeight += spacingTotal;
			totalWidth = maxCrossAxis;
		}

		return .(totalWidth, totalHeight);
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		var offset = 0.0f;

		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			RectangleF childRect;
			if (mOrientation == .Horizontal)
			{
				childRect = .(
					contentBounds.X + offset,
					contentBounds.Y,
					child.DesiredSize.Width,
					contentBounds.Height
				);
				offset += child.DesiredSize.Width + mSpacing;
			}
			else
			{
				childRect = .(
					contentBounds.X,
					contentBounds.Y + offset,
					contentBounds.Width,
					child.DesiredSize.Height
				);
				offset += child.DesiredSize.Height + mSpacing;
			}

			child.Arrange(childRect);
		}
	}
}

using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Arranges children in a single line (horizontal or vertical).
class StackPanel : Widget
{
	private Orientation mOrientation = .Vertical;
	private float mSpacing = 0;

	/// Gets or sets the orientation (Horizontal or Vertical).
	public Orientation Orientation
	{
		get => mOrientation;
		set
		{
			if (mOrientation != value)
			{
				mOrientation = value;
				InvalidateMeasure();
			}
		}
	}

	/// Gets or sets the spacing between children.
	public float Spacing
	{
		get => mSpacing;
		set
		{
			if (mSpacing != value)
			{
				mSpacing = value;
				InvalidateMeasure();
			}
		}
	}

	/// Measures the stack panel and its children.
	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		var totalSize = Vector2.Zero;
		var maxCrossSize = 0f;
		var childCount = Children.Count;

		// Available size for children (subtract padding)
		var childAvailable = Vector2(
			Math.Max(0, availableSize.X - Padding.HorizontalThickness),
			Math.Max(0, availableSize.Y - Padding.VerticalThickness)
		);

		for (int i < childCount)
		{
			let child = Children[i];
			if (child.Visibility == .Collapsed)
				continue;

			// Give infinite size in stack direction
			var measureSize = childAvailable;
			if (mOrientation == .Vertical)
				measureSize.Y = float.MaxValue;
			else
				measureSize.X = float.MaxValue;

			child.Measure(measureSize);

			if (mOrientation == .Vertical)
			{
				totalSize.Y += child.DesiredSize.Y;
				maxCrossSize = Math.Max(maxCrossSize, child.DesiredSize.X);
			}
			else
			{
				totalSize.X += child.DesiredSize.X;
				maxCrossSize = Math.Max(maxCrossSize, child.DesiredSize.Y);
			}
		}

		// Add spacing between children
		int visibleCount = 0;
		for (let child in Children)
		{
			if (child.Visibility != .Collapsed)
				visibleCount++;
		}
		if (visibleCount > 1)
		{
			float totalSpacing = mSpacing * (visibleCount - 1);
			if (mOrientation == .Vertical)
				totalSize.Y += totalSpacing;
			else
				totalSize.X += totalSpacing;
		}

		// Set cross-axis size
		if (mOrientation == .Vertical)
			totalSize.X = maxCrossSize;
		else
			totalSize.Y = maxCrossSize;

		// Add padding
		totalSize.X += Padding.HorizontalThickness;
		totalSize.Y += Padding.VerticalThickness;

		return totalSize;
	}

	/// Arranges children in a stack.
	protected override void ArrangeOverride(RectangleF finalRect)
	{
		let contentBounds = ContentBounds;
		var offset = 0f;

		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			RectangleF childRect;

			if (mOrientation == .Vertical)
			{
				childRect = RectangleF(
					contentBounds.X,
					contentBounds.Y + offset,
					contentBounds.Width,
					child.DesiredSize.Y
				);
				offset += child.DesiredSize.Y + mSpacing;
			}
			else
			{
				childRect = RectangleF(
					contentBounds.X + offset,
					contentBounds.Y,
					child.DesiredSize.X,
					contentBounds.Height
				);
				offset += child.DesiredSize.X + mSpacing;
			}

			child.Arrange(childRect);
		}
	}
}

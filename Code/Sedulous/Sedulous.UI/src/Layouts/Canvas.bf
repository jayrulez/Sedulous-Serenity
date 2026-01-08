using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Canvas attached properties for positioning.
struct CanvasPosition
{
	public float? Left;
	public float? Top;
	public float? Right;
	public float? Bottom;
}

/// Arranges children at absolute positions.
/// Children are sized to their desired size unless Left+Right or Top+Bottom are both set.
public class Canvas : Panel
{
	private Dictionary<UIElement, CanvasPosition> mPositions = new .() ~ delete _;

	/// Gets the left offset for a child element.
	public float? GetLeft(UIElement element)
	{
		if (mPositions.TryGetValue(element, let pos))
			return pos.Left;
		return null;
	}

	/// Sets the left offset for a child element.
	public void SetLeft(UIElement element, float? left)
	{
		var pos = GetPosition(element);
		pos.Left = left;
		mPositions[element] = pos;
		InvalidateMeasure();
	}

	/// Gets the top offset for a child element.
	public float? GetTop(UIElement element)
	{
		if (mPositions.TryGetValue(element, let pos))
			return pos.Top;
		return null;
	}

	/// Sets the top offset for a child element.
	public void SetTop(UIElement element, float? top)
	{
		var pos = GetPosition(element);
		pos.Top = top;
		mPositions[element] = pos;
		InvalidateMeasure();
	}

	/// Gets the right offset for a child element.
	public float? GetRight(UIElement element)
	{
		if (mPositions.TryGetValue(element, let pos))
			return pos.Right;
		return null;
	}

	/// Sets the right offset for a child element.
	public void SetRight(UIElement element, float? right)
	{
		var pos = GetPosition(element);
		pos.Right = right;
		mPositions[element] = pos;
		InvalidateMeasure();
	}

	/// Gets the bottom offset for a child element.
	public float? GetBottom(UIElement element)
	{
		if (mPositions.TryGetValue(element, let pos))
			return pos.Bottom;
		return null;
	}

	/// Sets the bottom offset for a child element.
	public void SetBottom(UIElement element, float? bottom)
	{
		var pos = GetPosition(element);
		pos.Bottom = bottom;
		mPositions[element] = pos;
		InvalidateMeasure();
	}

	private CanvasPosition GetPosition(UIElement element)
	{
		if (mPositions.TryGetValue(element, let pos))
			return pos;
		return .();
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Canvas measures children but reports zero size by default
		// (unless Width/Height is explicitly set on the Canvas)
		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			child.Measure(.Unconstrained);
		}

		// Return zero - Canvas doesn't have intrinsic size
		return .(0, 0);
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			let pos = GetPosition(child);

			var x = contentBounds.X;
			var y = contentBounds.Y;
			var width = child.DesiredSize.Width;
			var height = child.DesiredSize.Height;

			// Handle horizontal positioning
			if (pos.Left.HasValue && pos.Right.HasValue)
			{
				// Both set - stretch between them
				x = contentBounds.X + pos.Left.Value;
				width = contentBounds.Width - pos.Left.Value - pos.Right.Value;
			}
			else if (pos.Left.HasValue)
			{
				x = contentBounds.X + pos.Left.Value;
			}
			else if (pos.Right.HasValue)
			{
				x = contentBounds.X + contentBounds.Width - pos.Right.Value - width;
			}

			// Handle vertical positioning
			if (pos.Top.HasValue && pos.Bottom.HasValue)
			{
				// Both set - stretch between them
				y = contentBounds.Y + pos.Top.Value;
				height = contentBounds.Height - pos.Top.Value - pos.Bottom.Value;
			}
			else if (pos.Top.HasValue)
			{
				y = contentBounds.Y + pos.Top.Value;
			}
			else if (pos.Bottom.HasValue)
			{
				y = contentBounds.Y + contentBounds.Height - pos.Bottom.Value - height;
			}

			child.Arrange(.(x, y, Math.Max(0, width), Math.Max(0, height)));
		}
	}
}

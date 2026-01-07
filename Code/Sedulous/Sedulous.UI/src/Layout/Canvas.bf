using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Provides absolute positioning of child elements.
class Canvas : Widget
{
	// Attached property storage
	private static Dictionary<Widget, CanvasProperties> sAttachedProps = new .() ~ delete _;

	/// Attached properties for canvas children.
	private struct CanvasProperties
	{
		public float Left;
		public float Top;
		public float Right;
		public float Bottom;
		public bool HasLeft;
		public bool HasTop;
		public bool HasRight;
		public bool HasBottom;
	}

	/// Gets the Left attached property.
	public static float GetLeft(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let props))
			return props.Left;
		return float.NaN;
	}

	/// Sets the Left attached property.
	public static void SetLeft(Widget widget, float left)
	{
		var props = GetOrCreateProps(widget);
		props.Left = left;
		props.HasLeft = left == left;  // NaN check
		sAttachedProps[widget] = props;
		widget.InvalidateArrange();
	}

	/// Gets the Top attached property.
	public static float GetTop(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let props))
			return props.Top;
		return float.NaN;
	}

	/// Sets the Top attached property.
	public static void SetTop(Widget widget, float top)
	{
		var props = GetOrCreateProps(widget);
		props.Top = top;
		props.HasTop = top == top;  // NaN check
		sAttachedProps[widget] = props;
		widget.InvalidateArrange();
	}

	/// Gets the Right attached property.
	public static float GetRight(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let props))
			return props.Right;
		return float.NaN;
	}

	/// Sets the Right attached property.
	public static void SetRight(Widget widget, float right)
	{
		var props = GetOrCreateProps(widget);
		props.Right = right;
		props.HasRight = right == right;  // NaN check
		sAttachedProps[widget] = props;
		widget.InvalidateArrange();
	}

	/// Gets the Bottom attached property.
	public static float GetBottom(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let props))
			return props.Bottom;
		return float.NaN;
	}

	/// Sets the Bottom attached property.
	public static void SetBottom(Widget widget, float bottom)
	{
		var props = GetOrCreateProps(widget);
		props.Bottom = bottom;
		props.HasBottom = bottom == bottom;  // NaN check
		sAttachedProps[widget] = props;
		widget.InvalidateArrange();
	}

	/// Helper to set both Left and Top.
	public static void SetPosition(Widget widget, float left, float top)
	{
		var props = GetOrCreateProps(widget);
		props.Left = left;
		props.Top = top;
		props.HasLeft = left == left;  // NaN check
		props.HasTop = top == top;  // NaN check
		sAttachedProps[widget] = props;
		widget.InvalidateArrange();
	}

	private static CanvasProperties GetOrCreateProps(Widget widget)
	{
		if (sAttachedProps.TryGetValue(widget, let props))
			return props;
		return CanvasProperties() { Left = float.NaN, Top = float.NaN, Right = float.NaN, Bottom = float.NaN };
	}

	/// Measures the canvas. Canvas reports zero size by default.
	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		// Measure all children with infinite space
		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			child.Measure(Vector2(float.MaxValue, float.MaxValue));
		}

		// Canvas doesn't have a natural size - it sizes to fill or explicit size
		return Vector2(Padding.HorizontalThickness, Padding.VerticalThickness);
	}

	/// Arranges children at absolute positions.
	protected override void ArrangeOverride(RectangleF finalRect)
	{
		let contentBounds = ContentBounds;

		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			var x = contentBounds.X;
			var y = contentBounds.Y;
			var width = child.DesiredSize.X - child.Margin.HorizontalThickness;
			var height = child.DesiredSize.Y - child.Margin.VerticalThickness;

			if (sAttachedProps.TryGetValue(child, let props))
			{
				// Position from left or right
				if (props.HasLeft && props.HasRight)
				{
					x = contentBounds.X + props.Left;
					width = contentBounds.Width - props.Left - props.Right;
				}
				else if (props.HasLeft)
				{
					x = contentBounds.X + props.Left;
				}
				else if (props.HasRight)
				{
					x = contentBounds.Right - width - props.Right;
				}

				// Position from top or bottom
				if (props.HasTop && props.HasBottom)
				{
					y = contentBounds.Y + props.Top;
					height = contentBounds.Height - props.Top - props.Bottom;
				}
				else if (props.HasTop)
				{
					y = contentBounds.Y + props.Top;
				}
				else if (props.HasBottom)
				{
					y = contentBounds.Bottom - height - props.Bottom;
				}
			}

			child.Arrange(RectangleF(x, y, Math.Max(0, width), Math.Max(0, height)));
		}
	}
}

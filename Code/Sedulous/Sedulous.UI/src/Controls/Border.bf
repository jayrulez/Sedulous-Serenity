using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// A control that draws a border and background around a single child.
///
/// IMPORTANT: Use the `Child` property to set the content, not `AddChild()`.
/// The `Child` property ensures proper measurement and layout of the content.
///
/// Example:
/// ```
/// let border = new Border();
/// border.Background = Color(45, 50, 60);
/// border.Padding = Thickness(10);
/// border.Child = new TextBlock("Hello");  // Correct
/// // border.AddChild(new TextBlock("Hello"));  // Wrong - layout will fail
/// ```
public class Border : Control
{
	private UIElement mChild;
	private float mCornerRadius;

	/// The single child element inside the border.
	public UIElement Child
	{
		get => mChild;
		set
		{
			if (mChild != value)
			{
				if (mChild != null)
					RemoveChild(mChild);

				mChild = value;

				if (mChild != null)
					AddChild(mChild);

				InvalidateMeasure();
			}
		}
	}

	/// The corner radius for rounded corners.
	public float CornerRadius
	{
		get => mCornerRadius;
		set { mCornerRadius = value; InvalidateVisual(); }
	}

	public this()
	{
		// Border is not focusable by default
		Focusable = false;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		if (mChild != null)
		{
			mChild.Measure(constraints);
			return mChild.DesiredSize;
		}
		return .(0, 0);
	}

	protected override void ArrangeContent(RectangleF contentBounds)
	{
		if (mChild != null)
		{
			mChild.Arrange(contentBounds);
		}
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let bounds = Bounds;

		// Draw background
		if (Background.HasValue)
		{
			if (mCornerRadius > 0)
			{
				drawContext.FillRoundedRect(bounds, mCornerRadius, Background.Value);
			}
			else
			{
				drawContext.FillRect(bounds, Background.Value);
			}
		}

		// Draw border
		if (BorderThickness.TotalHorizontal > 0 || BorderThickness.TotalVertical > 0)
		{
			if (BorderBrush.HasValue)
			{
				// Rectangular border - draw as four rectangles
				// For rounded corners, the border approximation is less precise
				let bt = BorderThickness;
				// Top border
				if (bt.Top > 0)
					drawContext.FillRect(.(bounds.X, bounds.Y, bounds.Width, bt.Top), BorderBrush.Value);
				// Bottom border
				if (bt.Bottom > 0)
					drawContext.FillRect(.(bounds.X, bounds.Bottom - bt.Bottom, bounds.Width, bt.Bottom), BorderBrush.Value);
				// Left border
				if (bt.Left > 0)
					drawContext.FillRect(.(bounds.X, bounds.Y + bt.Top, bt.Left, bounds.Height - bt.TotalVertical), BorderBrush.Value);
				// Right border
				if (bt.Right > 0)
					drawContext.FillRect(.(bounds.Right - bt.Right, bounds.Y + bt.Top, bt.Right, bounds.Height - bt.TotalVertical), BorderBrush.Value);
			}
		}

		// Child renders itself through the tree
	}
}

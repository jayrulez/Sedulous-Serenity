using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// A control that draws a border and background around a single child.
/// Use the `Child` property (inherited from Decorator) to set the content.
///
/// Example:
/// ```
/// let border = new Border();
/// border.Background = Color(45, 50, 60);
/// border.Padding = Thickness(10);
/// border.Child = new TextBlock("Hello");
/// ```
public class Border : Decorator
{
	private float mCornerRadius;

	/// The corner radius for rounded corners.
	public float CornerRadius
	{
		get => mCornerRadius;
		set { mCornerRadius = value; InvalidateVisual(); }
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

		// Render child (Decorator base class handles this)
		base.OnRender(drawContext);
	}
}

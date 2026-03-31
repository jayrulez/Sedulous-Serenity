namespace Sedulous.UI;

using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// A drawable that fills its bounds with a linear gradient.
public class GradientDrawable : Drawable
{
	public Color StartColor;
	public Color EndColor;
	public GradientDirection Direction = .TopToBottom;

	public enum GradientDirection
	{
		TopToBottom,
		LeftToRight,
		TopLeftToBottomRight,
		TopRightToBottomLeft
	}

	public this(Color startColor, Color endColor, GradientDirection direction = .TopToBottom)
	{
		StartColor = startColor;
		EndColor = endColor;
		Direction = direction;
	}

	public override void Draw(DrawContext ctx, RectangleF bounds)
	{
		Vector2 start, end;
		switch (Direction)
		{
		case .TopToBottom:
			start = .(bounds.X, bounds.Y);
			end = .(bounds.X, bounds.Y + bounds.Height);
		case .LeftToRight:
			start = .(bounds.X, bounds.Y);
			end = .(bounds.X + bounds.Width, bounds.Y);
		case .TopLeftToBottomRight:
			start = .(bounds.X, bounds.Y);
			end = .(bounds.X + bounds.Width, bounds.Y + bounds.Height);
		case .TopRightToBottomLeft:
			start = .(bounds.X + bounds.Width, bounds.Y);
			end = .(bounds.X, bounds.Y + bounds.Height);
		}

		let brush = scope LinearGradientBrush(start, end, StartColor, EndColor);
		ctx.FillRect(bounds, brush);
	}
}

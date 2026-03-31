namespace Sedulous.UI;

using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// A drawable that fills a rounded rectangle with optional border.
public class RoundedRectDrawable : Drawable
{
	public Color FillColor;
	public Color BorderColor;
	public float CornerRadius;
	public float BorderThickness;

	public this(Color fillColor, float cornerRadius, Color borderColor = default, float borderThickness = 0)
	{
		FillColor = fillColor;
		CornerRadius = cornerRadius;
		BorderColor = borderColor;
		BorderThickness = borderThickness;
	}

	public override void Draw(DrawContext ctx, RectangleF bounds)
	{
		ctx.FillRoundedRect(bounds, CornerRadius, FillColor);

		if (BorderThickness > 0 && BorderColor.A > 0)
			ctx.DrawBorderRoundedRect(bounds, CornerRadius, BorderColor, BorderThickness);
	}
}

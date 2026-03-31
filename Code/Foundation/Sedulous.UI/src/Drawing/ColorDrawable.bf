namespace Sedulous.UI;

using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// A drawable that fills its bounds with a solid color.
public class ColorDrawable : Drawable
{
	public Color Color;

	public this(Color color)
	{
		Color = color;
	}

	public override void Draw(DrawContext ctx, RectangleF bounds)
	{
		ctx.FillRect(bounds, Color);
	}
}

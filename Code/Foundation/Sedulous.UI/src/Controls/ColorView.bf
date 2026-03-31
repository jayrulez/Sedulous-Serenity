namespace Sedulous.UI;

using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Simple leaf View that fills its bounds with a solid color.
/// Useful for testing layout, prototyping, and placeholders.
public class ColorView : View
{
	private Color mColor;

	public Color Color
	{
		get => mColor;
		set { mColor = value; }
	}

	public this(Color color)
	{
		mColor = color;
	}

	protected override void OnDraw(DrawContext ctx)
	{
		ctx.FillRect(.(0, 0, Width, Height), mColor);
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		// ColorView has no intrinsic size — just uses what's given
		SetMeasuredDimension(
			widthSpec.Resolve(0, MinWidth, MaxWidth),
			heightSpec.Resolve(0, MinHeight, MaxHeight)
		);
	}
}

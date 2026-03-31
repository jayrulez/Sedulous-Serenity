namespace Sedulous.UI;

using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// A full-area semi-transparent view that blocks input below modal popups.
public class ModalBackdrop : View
{
	private Color mDimColor;

	public Color DimColor
	{
		get => mDimColor;
		set { mDimColor = value; Invalidate(); }
	}

	public this(Color dimColor = .(0, 0, 0, 102))
	{
		mDimColor = dimColor;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		SetMeasuredDimension(
			widthSpec.Resolve(0, MinWidth, MaxWidth),
			heightSpec.Resolve(0, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		// Use theme color if available, otherwise use the explicit dimColor
		Color color = Context?.Theme?.GetColor("ModalBackdrop", "dimColor") ?? mDimColor;
		if (color.A > 0)
			ctx.FillRect(.(0, 0, Width, Height), color);
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		// Block input — handled, does not propagate
		e.Handled = true;
	}

	public override void OnMouseUp(MouseButtonEventArgs e)
	{
		e.Handled = true;
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		e.Handled = true;
	}
}

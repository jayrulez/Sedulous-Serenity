namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Horizontal or vertical divider line.
public class Separator : View
{
	private Orientation mOrientation = .Horizontal;
	private Color mColor = default;
	private float mThickness = 0; // 0 = use theme dimension or default (1)

	public Orientation Orientation
	{
		get => mOrientation;
		set { mOrientation = value; InvalidateLayout(); }
	}

	public Color SeparatorColor
	{
		get => mColor;
		set { mColor = value; Invalidate(); }
	}

	public float Thickness
	{
		get => mThickness;
		set { mThickness = Math.Max(0, value); InvalidateLayout(); }
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float thickness = mThickness;
		if (thickness <= 0)
			thickness = Context?.Theme?.GetDimension("Separator", "thickness") ?? 1;

		float desiredW, desiredH;

		if (mOrientation == .Horizontal)
		{
			desiredW = 0; // fill available
			desiredH = thickness;
		}
		else
		{
			desiredW = thickness;
			desiredH = 0; // fill available
		}

		SetMeasuredDimension(
			widthSpec.Resolve(desiredW, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let drawable = Context?.Theme?.GetDrawable("Separator", "line");
		if (drawable != null)
		{
			drawable.Draw(ctx, .(0, 0, Width, Height));
		}
		else
		{
			let color = (mColor.A > 0) ? mColor : (Context?.Theme?.GetColor("Separator", "color") ?? GetStateBorderColor());
			ctx.FillRect(.(0, 0, Width, Height), color);
		}
	}
}

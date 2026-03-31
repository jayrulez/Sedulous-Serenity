namespace Sedulous.UI;

using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Visual overlay shown during a drag operation.
/// Wraps a user-provided visual or shows a default indicator.
/// Shown via PopupLayer with IsHitTestVisible = false.
public class DragAdorner : FrameLayout
{
	private float mOffsetX;
	private float mOffsetY;

	public this(View visual, float offsetX, float offsetY)
	{
		mOffsetX = offsetX;
		mOffsetY = offsetY;
		IsHitTestVisible = false;
		Alpha = 0.7f;

		if (visual != null)
			AddView(visual);
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		if (ChildCount > 0)
		{
			base.OnMeasure(widthSpec, heightSpec);
		}
		else
		{
			SetMeasuredDimension(
				widthSpec.Resolve(32, MinWidth, MaxWidth),
				heightSpec.Resolve(32, MinHeight, MaxHeight)
			);
		}
	}

	protected override void OnDraw(DrawContext ctx)
	{
		if (ChildCount > 0)
		{
			base.OnDraw(ctx);
		}
		else
		{
			ctx.FillRoundedRect(.(0, 0, Width, Height), 4, Color(128, 128, 128, 128));
		}
	}
}

namespace Sedulous.UI;

/// Fixed or expanding empty space.
/// Has no intrinsic size — uses whatever is given by LayoutParams and MeasureSpec.
/// Draws nothing (transparent).
public class Spacer : View
{
	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		SetMeasuredDimension(
			widthSpec.Resolve(0, MinWidth, MaxWidth),
			heightSpec.Resolve(0, MinHeight, MaxHeight)
		);
	}
}

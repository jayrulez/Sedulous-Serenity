namespace Sedulous.UI;

using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// A drawable that invokes a custom draw callback. Owns the delegate.
public class ShapeDrawable : Drawable
{
	private delegate void(DrawContext, RectangleF) mDrawFunc ~ delete _;

	public this(delegate void(DrawContext, RectangleF) drawFunc)
	{
		mDrawFunc = drawFunc;
	}

	public override void Draw(DrawContext ctx, RectangleF bounds)
	{
		mDrawFunc?.Invoke(ctx, bounds);
	}
}

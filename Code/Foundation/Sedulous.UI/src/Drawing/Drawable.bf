namespace Sedulous.UI;

using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// Abstract base for paintable objects that can serve as view backgrounds,
/// foregrounds, or compound visual elements.
public abstract class Drawable
{
	/// Draw this drawable into the given bounds.
	public abstract void Draw(DrawContext ctx, RectangleF bounds);

	/// Draw this drawable with state awareness. StateListDrawable overrides this
	/// to select the appropriate child. Default ignores state and calls Draw(ctx, bounds).
	public virtual void Draw(DrawContext ctx, RectangleF bounds, ControlState state)
	{
		Draw(ctx, bounds);
	}

	/// The natural size of this drawable, or (0,0) if it has no intrinsic size.
	public virtual Size2F IntrinsicSize => .(0, 0);

	/// Optional padding contributed by this drawable (e.g., nine-slice borders).
	public virtual Thickness DrawablePadding => .Zero;
}

namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// A drawable that wraps another drawable with fixed insets. Owns the inner drawable.
public class InsetDrawable : Drawable
{
	private Drawable mInner ~ delete _;
	private Thickness mInset;

	public this(Drawable inner, Thickness inset)
	{
		mInner = inner;
		mInset = inset;
	}

	public Thickness Inset
	{
		get => mInset;
		set => mInset = value;
	}

	public override void Draw(DrawContext ctx, RectangleF bounds)
	{
		let insetBounds = RectangleF(
			bounds.X + mInset.Left,
			bounds.Y + mInset.Top,
			Math.Max(0, bounds.Width - mInset.Horizontal),
			Math.Max(0, bounds.Height - mInset.Vertical)
		);
		mInner?.Draw(ctx, insetBounds);
	}

	public override Thickness DrawablePadding => mInset;
}

namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;
using Sedulous.ImageData;

/// A drawable that renders a 9-slice image. Does NOT own the IImageData.
/// Supports an optional Expand value that inflates the drawn area beyond
/// the logical bounds (used for shadows, glows, etc. in TurboBadger skins).
public class NineSliceDrawable : Drawable
{
	public IImageData Image;
	public NineSlice Slices;
	public Color Tint;

	/// How many pixels the visual extends beyond the logical bounds on each side.
	/// The nine-slice is drawn at (bounds - expand), making it larger than the element.
	public Thickness Expand;

	public this(IImageData image, NineSlice slices, Color tint = .(1.0f, 1.0f, 1.0f, 1.0f))
	{
		Image = image;
		Slices = slices;
		Tint = tint;
		Expand = .Zero;
	}

	public this(IImageData image, NineSlice slices, Thickness expand, Color tint = .(1.0f, 1.0f, 1.0f, 1.0f))
	{
		Image = image;
		Slices = slices;
		Tint = tint;
		Expand = expand;
	}

	public override void Draw(DrawContext ctx, RectangleF bounds)
	{
		if (Image == null)
			return;

		// Inflate bounds by expand amount (the visual extends beyond logical bounds)
		let drawBounds = RectangleF(
			bounds.X - Expand.Left,
			bounds.Y - Expand.Top,
			bounds.Width + Expand.Left + Expand.Right,
			bounds.Height + Expand.Top + Expand.Bottom
		);

		let srcRect = RectangleF(0, 0, Image.Width, Image.Height);
		ctx.DrawNineSlice(Image, drawBounds, srcRect, Slices, Tint);
	}

	/// Logical intrinsic size = image size minus expand (since expand extends beyond logical bounds).
	public override Size2F IntrinsicSize =>
		(Image != null) ? .(
			Math.Max(0, Image.Width - Expand.Left - Expand.Right),
			Math.Max(0, Image.Height - Expand.Top - Expand.Bottom)
		) : .(0, 0);

	/// Content padding = slice borders minus expand.
	/// With expand, part of the nine-slice border is outside logical bounds,
	/// so effective content inset is reduced.
	public override Thickness DrawablePadding
	{
		get
		{
			float left = Math.Max(0, Slices.Left - Expand.Left);
			float top = Math.Max(0, Slices.Top - Expand.Top);
			float right = Math.Max(0, Slices.Right - Expand.Right);
			float bottom = Math.Max(0, Slices.Bottom - Expand.Bottom);
			return .(left, top, right, bottom);
		}
	}
}

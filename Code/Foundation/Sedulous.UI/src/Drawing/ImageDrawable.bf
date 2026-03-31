namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// A drawable that stretches a single image to fill its bounds.
/// Does NOT own the IImageData.
/// Supports an optional Expand value that inflates the drawn area beyond
/// the logical bounds (matching TurboBadger's expand for Image-type elements).
public class ImageDrawable : Drawable
{
	public IImageData Image;
	public Color Tint;

	/// How many pixels the visual extends beyond the logical bounds on each side.
	public Thickness Expand;

	public this(IImageData image, Color tint = .(1.0f, 1.0f, 1.0f, 1.0f))
	{
		Image = image;
		Tint = tint;
		Expand = .Zero;
	}

	public this(IImageData image, Thickness expand, Color tint = .(1.0f, 1.0f, 1.0f, 1.0f))
	{
		Image = image;
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
		ctx.DrawImage(Image, drawBounds, srcRect, Tint);
	}

	/// Logical intrinsic size = image size minus expand.
	public override Size2F IntrinsicSize =>
		(Image != null) ? .(
			Math.Max(0, Image.Width - Expand.Left - Expand.Right),
			Math.Max(0, Image.Height - Expand.Top - Expand.Bottom)
		) : .(0, 0);
}

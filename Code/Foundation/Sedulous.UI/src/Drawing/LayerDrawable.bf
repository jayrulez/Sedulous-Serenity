namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// A drawable that stacks multiple drawables with per-layer insets.
/// Owns all child drawables.
public class LayerDrawable : Drawable
{
	private struct Layer
	{
		public Drawable Drawable;
		public Thickness Inset;
	}

	private List<Layer> mLayers = new .() ~ delete _;

	public ~this()
	{
		for (let layer in mLayers)
			delete layer.Drawable;
	}

	/// Add a layer with optional insets. Takes ownership of the drawable.
	public void AddLayer(Drawable drawable, Thickness inset = .Zero)
	{
		mLayers.Add(.() { Drawable = drawable, Inset = inset });
	}

	/// Number of layers.
	public int LayerCount => mLayers.Count;

	public override void Draw(DrawContext ctx, RectangleF bounds)
	{
		for (let layer in mLayers)
		{
			let insetBounds = RectangleF(
				bounds.X + layer.Inset.Left,
				bounds.Y + layer.Inset.Top,
				Math.Max(0, bounds.Width - layer.Inset.Horizontal),
				Math.Max(0, bounds.Height - layer.Inset.Vertical)
			);
			layer.Drawable.Draw(ctx, insetBounds);
		}
	}
}

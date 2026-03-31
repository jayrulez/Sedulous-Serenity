namespace Sedulous.UI;

using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Draws debug overlays for view layout bounds, margins, padding, and focus.
public static class DebugDrawOverlay
{
	// Debug colors
	private static readonly Color sBoundsColor = .(1.0f, 0.0f, 0.0f, 0.5f);       // Red
	private static readonly Color sMarginColor = .(1.0f, 0.6f, 0.0f, 0.3f);       // Orange
	private static readonly Color sPaddingColor = .(0.0f, 0.8f, 0.0f, 0.3f);      // Green
	private static readonly Color sFocusColor = .(0.0f, 0.4f, 1.0f, 0.8f);        // Blue

	/// Draw debug overlays for a view and all its children recursively.
	public static void DrawDebugOverlay(View view, DrawContext ctx)
	{
		if (view.Visibility != .Visible)
			return;

		ctx.PushState();
		ctx.Translate(view.Left, view.Top);

		// Apply render transform if present
		if (view.HasRenderTransform)
		{
			float originX = view.Width * view.RenderTransformOrigin.X;
			float originY = view.Height * view.RenderTransformOrigin.Y;
			ctx.Translate(originX, originY);
			ctx.SetTransform(view.RenderTransform * ctx.GetTransform());
			ctx.Translate(-originX, -originY);
		}

		// Draw padding (green fill inside bounds)
		let pad = view.Padding;
		if (pad.Left > 0 || pad.Top > 0 || pad.Right > 0 || pad.Bottom > 0)
		{
			// Top padding
			if (pad.Top > 0)
				ctx.FillRect(.(0, 0, view.Width, pad.Top), sPaddingColor);
			// Bottom padding
			if (pad.Bottom > 0)
				ctx.FillRect(.(0, view.Height - pad.Bottom, view.Width, pad.Bottom), sPaddingColor);
			// Left padding (between top and bottom)
			if (pad.Left > 0)
				ctx.FillRect(.(0, pad.Top, pad.Left, view.Height - pad.Top - pad.Bottom), sPaddingColor);
			// Right padding (between top and bottom)
			if (pad.Right > 0)
				ctx.FillRect(.(view.Width - pad.Right, pad.Top, pad.Right, view.Height - pad.Top - pad.Bottom), sPaddingColor);
		}

		// Draw layout bounds (red border)
		ctx.DrawRect(.(0, 0, view.Width, view.Height), sBoundsColor, 1.0f);

		// Draw margin (orange fill outside bounds)
		if (view.LayoutParams != null)
		{
			let margin = view.LayoutParams.Margin;
			if (margin.Left > 0 || margin.Top > 0 || margin.Right > 0 || margin.Bottom > 0)
			{
				// Top margin
				if (margin.Top > 0)
					ctx.FillRect(.(- margin.Left, -margin.Top, view.Width + margin.Horizontal, margin.Top), sMarginColor);
				// Bottom margin
				if (margin.Bottom > 0)
					ctx.FillRect(.(-margin.Left, view.Height, view.Width + margin.Horizontal, margin.Bottom), sMarginColor);
				// Left margin (between top and bottom)
				if (margin.Left > 0)
					ctx.FillRect(.(-margin.Left, 0, margin.Left, view.Height), sMarginColor);
				// Right margin (between top and bottom)
				if (margin.Right > 0)
					ctx.FillRect(.(view.Width, 0, margin.Right, view.Height), sMarginColor);
			}
		}

		// Draw focus ring (blue border)
		if (view.IsFocused)
			ctx.DrawRect(.(-2, -2, view.Width + 4, view.Height + 4), sFocusColor, 2.0f);

		// Recurse into children
		if (let group = view as ViewGroup)
		{
			for (int i = 0; i < group.ChildCount; i++)
			{
				let child = group.GetChildAt(i);
				DrawDebugOverlay(child, ctx);
			}
		}

		ctx.PopState();
	}
}

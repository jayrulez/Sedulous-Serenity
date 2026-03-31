namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// A FrameLayout with border and background drawing.
/// Children are laid out by FrameLayout rules; Panel adds visual decoration.
/// Panel manages its own fill color (with corner radius support) rather than
/// using the base View.Background drawable.
public class Panel : FrameLayout
{
	private float mCornerRadius = 0;
	private Color mBorderColor = default;
	private float mBorderWidth = 0;
	private Color mFillColor = default;

	public float CornerRadius
	{
		get => mCornerRadius;
		set { mCornerRadius = Math.Max(0, value); Invalidate(); }
	}

	public Color BorderColor
	{
		get => mBorderColor;
		set { mBorderColor = value; Invalidate(); }
	}

	public float BorderWidth
	{
		get => mBorderWidth;
		set { mBorderWidth = Math.Max(0, value); Invalidate(); }
	}

	/// The panel's fill color.
	public Color FillColor
	{
		get => mFillColor;
		set { mFillColor = value; Invalidate(); }
	}

	/// Returns the active background drawable, or null if using procedural rendering.
	private Drawable GetBackgroundDrawable()
	{
		if (mFillColor.A == 0 && mBorderColor.A == 0)
			return Context?.Theme?.GetDrawable("Panel", "background");
		return null;
	}

	/// Returns effective padding: max of user padding and drawable padding.
	/// When a theme drawable provides the panel background, its nine-slice
	/// insets define the minimum padding to avoid content overlapping borders.
	private Thickness GetEffectivePadding()
	{
		let bgDrawable = GetBackgroundDrawable();
		if (bgDrawable != null)
		{
			let dp = bgDrawable.DrawablePadding;
			return .(
				Math.Max(Padding.Left, dp.Left),
				Math.Max(Padding.Top, dp.Top),
				Math.Max(Padding.Right, dp.Right),
				Math.Max(Padding.Bottom, dp.Bottom)
			);
		}
		return Padding;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		let effective = GetEffectivePadding();
		if (effective != Padding)
		{
			var saved = this.[Friend]mPadding;
			this.[Friend]mPadding = effective;
			base.OnMeasure(widthSpec, heightSpec);
			this.[Friend]mPadding = saved;
		}
		else
		{
			base.OnMeasure(widthSpec, heightSpec);
		}
	}

	protected override void OnLayout(float width, float height)
	{
		let effective = GetEffectivePadding();
		if (effective != Padding)
		{
			var saved = this.[Friend]mPadding;
			this.[Friend]mPadding = effective;
			base.OnLayout(width, height);
			this.[Friend]mPadding = saved;
		}
		else
		{
			base.OnLayout(width, height);
		}
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;

		// If no explicit colors set, try theme drawable (e.g. TB container nine-slice)
		let bgDrawable = GetBackgroundDrawable();
		if (bgDrawable != null)
		{
			bgDrawable.Draw(ctx, .(0, 0, Width, Height));
			base.OnDraw(ctx);
			return;
		}

		// Draw fill: use explicit FillColor if set, otherwise query theme
		Color fillColor = mFillColor;
		if (fillColor.A == 0 && theme != null)
			fillColor = theme.GetColor("Panel", "background") ?? Color(0);
		if (fillColor.A > 0)
		{
			if (mCornerRadius > 0)
				ctx.FillRoundedRect(.(0, 0, Width, Height), mCornerRadius, fillColor);
			else
				ctx.FillRect(.(0, 0, Width, Height), fillColor);
		}

		// Draw border: use explicit BorderColor if set, otherwise query theme
		Color borderColor = mBorderColor;
		if (borderColor.A == 0)
			borderColor = (theme?.GetColor("Panel", "border") ?? GetStateBorderColor());
		if (mBorderWidth > 0)
		{
			if (mCornerRadius > 0)
				ctx.DrawBorderRoundedRect(.(0, 0, Width, Height), mCornerRadius, borderColor, mBorderWidth);
			else
				ctx.DrawBorderRect(.(0, 0, Width, Height), borderColor, mBorderWidth);
		}

		// Draw children
		base.OnDraw(ctx);
	}
}

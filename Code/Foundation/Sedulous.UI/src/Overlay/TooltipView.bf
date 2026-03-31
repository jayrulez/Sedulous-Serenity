namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// A simple tooltip label view. Reused by TooltipManager.
public class TooltipView : View
{
	private String mText = new .() ~ delete _;
	private float mFontSize = 12;
	private float mPaddingH = 8;
	private float mPaddingV = 4;

	public StringView Text => mText;

	public float FontSize
	{
		get => mFontSize;
		set { mFontSize = value; Invalidate(); }
	}

	public void SetText(StringView text)
	{
		mText.Set(text);
		Invalidate();
	}

	/// Get content inset from the drawable (if any).
	private Thickness GetDrawableInset()
	{
		let bgDrawable = Context?.Theme?.GetDrawable("Tooltip", "background");
		if (bgDrawable != null)
			return bgDrawable.DrawablePadding;
		return .Zero;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float textW = 0;
		float textH = mFontSize;

		let fontService = Context?.FontService;
		if (fontService != null && mText.Length > 0)
		{
			let font = fontService.GetFont(mFontSize);
			if (font != null)
			{
				textW = font.Font.MeasureString(mText);
				textH = font.Font.Metrics.LineHeight;
				fontService.ReleaseFont(font);
			}
		}
		else if (mText.Length > 0)
		{
			textW = mText.Length * (mFontSize * 0.6f);
		}

		let inset = GetDrawableInset();
		float w = textW + mPaddingH * 2 + inset.Horizontal;
		float h = textH + mPaddingV * 2 + inset.Vertical;

		SetMeasuredDimension(
			widthSpec.Resolve(w, MinWidth, MaxWidth),
			heightSpec.Resolve(h, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		Color textColor = theme?.GetColor("Tooltip", "text") ?? Color(255, 255, 255, 255);

		// Background — try drawable first, then color fallback
		let bgDrawable = theme?.GetDrawable("Tooltip", "background");
		if (bgDrawable != null)
		{
			bgDrawable.Draw(ctx, .(0, 0, Width, Height));
		}
		else
		{
			Color bgColor = theme?.GetColor("Tooltip", "background") ?? Color(50, 50, 50, 230);
			Color borderColor = theme?.GetColor("Tooltip", "border") ?? Color(100, 100, 100, 200);
			float cr = theme?.GetDimension("Tooltip", "cornerRadius") ?? 3;

			if (cr > 0)
			{
				ctx.FillRoundedRect(.(0, 0, Width, Height), cr, bgColor);
				ctx.DrawBorderRoundedRect(.(0, 0, Width, Height), cr, borderColor, 1);
			}
			else
			{
				ctx.FillRect(.(0, 0, Width, Height), bgColor);
				ctx.DrawBorderRect(.(0, 0, Width, Height), borderColor, 1);
			}
		}

		// Text — offset by drawable inset
		if (mText.Length > 0)
		{
			let inset = GetDrawableInset();
			ctx.DrawText(mText, mFontSize, .(inset.Left + mPaddingH, inset.Top + mPaddingV), textColor);
		}
	}
}

namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Fonts;

/// How text is handled when it overflows the available width.
public enum TextOverflow
{
	/// Text is clipped at the bounds (default).
	None,
	/// Text is truncated with "..." when it exceeds the available width.
	Ellipsis
}

/// Text display control.
/// Supports font size, text color, horizontal/vertical alignment, and word wrap.
public class Label : View
{
	private String mText = new .() ~ delete _;
	private float mFontSize = 16;
	private Color mTextColor = default;
	private TextAlignment mTextAlignment = .Left;
	private VerticalAlignment mVerticalAlignment = .Top;
	private bool mWordWrap = false;
	private TextOverflow mTextOverflow = .None;

	public StringView Text
	{
		get => mText;
		set
		{
			mText.Set(value);
			InvalidateLayout();
		}
	}

	public float FontSize
	{
		get => mFontSize;
		set
		{
			mFontSize = Math.Max(1, value);
			InvalidateLayout();
		}
	}

	public Color TextColor
	{
		get => mTextColor;
		set { mTextColor = value; Invalidate(); }
	}

	public TextAlignment TextAlignment
	{
		get => mTextAlignment;
		set { mTextAlignment = value; Invalidate(); }
	}

	public VerticalAlignment VerticalAlignment
	{
		get => mVerticalAlignment;
		set { mVerticalAlignment = value; Invalidate(); }
	}

	public bool WordWrap
	{
		get => mWordWrap;
		set
		{
			mWordWrap = value;
			InvalidateLayout();
		}
	}

	public TextOverflow TextOverflow
	{
		get => mTextOverflow;
		set
		{
			mTextOverflow = value;
			Invalidate();
		}
	}

	public this()
	{
	}

	public this(StringView text)
	{
		mText.Set(text);
	}

	public this(StringView text, float fontSize)
	{
		mText.Set(text);
		mFontSize = fontSize;
	}

	public override float GetBaseline()
	{
		if (Context == null || Context.FontService == null)
			return -1;

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null)
			return -1;

		float lineH = font.Font.Metrics.LineHeight;
		float ascent = font.Font.Metrics.Ascent;
		Context.FontService.ReleaseFont(font);

		// Account for vertical alignment within the measured height
		float contentH = MeasuredHeight - Padding.Vertical;
		float textTop = Padding.Top;
		if (mVerticalAlignment == .Middle && contentH > lineH)
			textTop += (contentH - lineH) * 0.5f;
		else if (mVerticalAlignment == .Bottom && contentH > lineH)
			textTop += contentH - lineH;

		return textTop + ascent;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float desiredW = Padding.Horizontal;
		float desiredH = Padding.Vertical;

		if (!mText.IsEmpty && Context != null && Context.FontService != null)
		{
			let font = Context.FontService.GetFont(mFontSize);
			if (font != null)
			{
				if (mWordWrap)
				{
					// For word wrap, use available width from spec
					float availableW = widthSpec.Size - Padding.Horizontal;
					if (availableW > 0 && font.Shaper != null)
					{
						let positions = scope System.Collections.List<GlyphPosition>();
						float totalHeight = 0;
						if (font.Shaper.ShapeTextWrapped(font.Font, mText, availableW, positions, out totalHeight) case .Ok)
							desiredH += totalHeight;
						else
							desiredH += font.Font.Metrics.LineHeight;
					}
					else
					{
						desiredH += font.Font.Metrics.LineHeight;
					}
					desiredW = widthSpec.Size; // fill available width when wrapping
				}
				else
				{
					float textW = font.Font.MeasureString(mText);
					if (mTextOverflow == .Ellipsis && (widthSpec.SpecMode == .AtMost || widthSpec.SpecMode == .Exactly))
					{
						float availW = widthSpec.Size - Padding.Horizontal;
						desiredW += Math.Min(textW, availW);
					}
					else
					{
						desiredW += textW;
					}
					desiredH += font.Font.Metrics.LineHeight;
				}

				Context.FontService.ReleaseFont(font);
			}
		}

		SetMeasuredDimension(
			widthSpec.Resolve(desiredW, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		if (mText.IsEmpty || Context == null || Context.FontService == null)
			return;

		let font = Context.FontService.GetFont(mFontSize);
		if (font == null)
			return;

		let atlasTexture = Context.FontService.GetAtlasTexture(font);
		if (atlasTexture == null)
		{
			Context.FontService.ReleaseFont(font);
			return;
		}

		let bounds = ContentBounds;
		let baseTextColor = (mTextColor.A > 0) ? mTextColor : GetStateForeground();
		let color = Enabled ? baseTextColor : Palette.ComputeDisabled(baseTextColor);

		if (mWordWrap && font.Shaper != null)
		{
			ctx.DrawTextWrapped(mText, font, atlasTexture, bounds, bounds.Width, color);
		}
		else if (!mWordWrap && mTextOverflow == .Ellipsis && !mText.IsEmpty)
		{
			float textW = font.Font.MeasureString(mText);
			if (textW <= bounds.Width)
			{
				ctx.DrawText(mText, font.Font, font.Atlas, atlasTexture, bounds, mTextAlignment, mVerticalAlignment, color);
			}
			else
			{
				// Truncate with ellipsis — binary search for max chars that fit
				let ellipsis = "...";
				float ellipsisW = font.Font.MeasureString(ellipsis);
				float availW = bounds.Width - ellipsisW;

				int lo = 0;
				int hi = mText.Length;
				while (lo < hi)
				{
					int mid = (lo + hi + 1) / 2;
					float w = font.Font.MeasureString(StringView(mText, 0, mid));
					if (w <= availW)
						lo = mid;
					else
						hi = mid - 1;
				}

				let truncated = scope String(lo + 3);
				truncated.Append(StringView(mText, 0, lo));
				truncated.Append(ellipsis);
				ctx.DrawText(truncated, font.Font, font.Atlas, atlasTexture, bounds, mTextAlignment, mVerticalAlignment, color);
			}
		}
		else
		{
			ctx.DrawText(mText, font.Font, font.Atlas, atlasTexture, bounds, mTextAlignment, mVerticalAlignment, color);
		}

		Context.FontService.ReleaseFont(font);
	}
}

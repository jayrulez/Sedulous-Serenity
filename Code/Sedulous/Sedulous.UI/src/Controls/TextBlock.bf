using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Fonts;

namespace Sedulous.UI;

/// Text wrapping options.
public enum TextWrapping
{
	/// No wrapping - text continues on single line.
	None,
	/// Wrap text at word boundaries.
	Wrap,
	/// Wrap text at character boundaries.
	WrapWholeWords
}

/// Displays text content.
public class TextBlock : Control
{
	private String mText ~ delete _;
	private Sedulous.Fonts.TextAlignment mTextAlignment = .Left;
	private TextWrapping mTextWrapping = .None;

	/// The text to display.
	public StringView Text
	{
		get => mText ?? "";
		set
		{
			if (mText == null)
				mText = new String();
			mText.Set(value);
			InvalidateMeasure();
		}
	}

	/// How to align text horizontally.
	public Sedulous.Fonts.TextAlignment TextAlignment
	{
		get => mTextAlignment;
		set { mTextAlignment = value; InvalidateVisual(); }
	}

	/// How to wrap text.
	public TextWrapping TextWrapping
	{
		get => mTextWrapping;
		set { mTextWrapping = value; InvalidateMeasure(); }
	}

	public this()
	{
		// TextBlock is not focusable by default
		Focusable = false;
	}

	public this(StringView text) : this()
	{
		Text = text;
	}

	/// Gets the font service from the context.
	private IFontService GetFontService()
	{
		let context = Context;
		if (context != null)
		{
			if (context.GetService<IFontService>() case .Ok(let service))
				return service;
		}
		return null;
	}

	/// Gets the cached font for this control's font settings.
	private CachedFont GetCachedFont()
	{
		let fontService = GetFontService();
		if (fontService == null)
			return null;

		return fontService.GetFont(FontFamily, FontSize);
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		if (mText == null || mText.Length == 0)
			return .(0, 0);

		// Try to measure with actual font
		let cachedFont = GetCachedFont();
		if (cachedFont != null)
		{
			let font = cachedFont.Font;
			let textWidth = font.MeasureString(mText);
			let lineHeight = font.Metrics.LineHeight;

			if (mTextWrapping == .None)
			{
				return .(textWidth, lineHeight);
			}
			else
			{
				// Wrapped text - calculate based on available width
				let maxWidth = constraints.MaxWidth;
				if (maxWidth == SizeConstraints.Infinity)
				{
					return .(textWidth, lineHeight);
				}

				// Calculate wrapped line count (simple approximation)
				let lineCount = Math.Max(1, (int)Math.Ceiling(textWidth / maxWidth));
				let width = Math.Min(textWidth, maxWidth);
				let height = lineCount * lineHeight;
				return .(width, height);
			}
		}

		// Fallback measurement when no font available
		let fontSize = FontSize;
		let charWidth = fontSize * 0.6f;
		let lineHeight = fontSize * 1.2f;

		if (mTextWrapping == .None)
		{
			let textWidth = mText.Length * charWidth;
			return .(textWidth, lineHeight);
		}
		else
		{
			let maxWidth = constraints.MaxWidth;
			if (maxWidth == SizeConstraints.Infinity)
			{
				let textWidth = mText.Length * charWidth;
				return .(textWidth, lineHeight);
			}

			let charsPerLine = Math.Max(1, (int)(maxWidth / charWidth));
			let lineCount = (mText.Length + charsPerLine - 1) / charsPerLine;
			let width = Math.Min(mText.Length * charWidth, maxWidth);
			let height = lineCount * lineHeight;
			return .(width, height);
		}
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		if (mText == null || mText.Length == 0)
			return;

		let foreground = Foreground ?? Color.Black;
		let bounds = ContentBounds;

		// Try to render with actual font
		let fontService = GetFontService();
		let cachedFont = GetCachedFont();

		if (fontService != null && cachedFont != null)
		{
			let font = cachedFont.Font;
			let atlas = cachedFont.Atlas;
			let atlasTexture = fontService.GetAtlasTexture(cachedFont);

			if (atlas != null && atlasTexture != null)
			{
				drawContext.DrawText(mText, font, atlas, atlasTexture, bounds, mTextAlignment, .Middle, foreground);
				return;
			}
		}

		// Debug fallback - draw a rectangle to show where text would be
		#if DEBUG
		if (Context?.DebugSettings.ShowLayoutBounds ?? false)
		{
			let fontSize = FontSize;
			let textWidth = mText.Length * fontSize * 0.6f;
			let textHeight = fontSize * 1.2f;
			var x = bounds.X;
			if (mTextAlignment == .Center)
				x = bounds.X + (bounds.Width - textWidth) / 2;
			else if (mTextAlignment == .Right)
				x = bounds.Right - textWidth;
			drawContext.FillRect(.(x, bounds.Y, textWidth, textHeight), Color(foreground.R, foreground.G, foreground.B, 40));
		}
		#endif
	}
}

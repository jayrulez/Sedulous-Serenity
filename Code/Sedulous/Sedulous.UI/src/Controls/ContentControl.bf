using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Fonts;

namespace Sedulous.UI;

/// Base class for controls that contain a single piece of content.
/// The content can be a UIElement or will be displayed as text.
public class ContentControl : Control
{
	private UIElement mContent;
	private String mContentText ~ delete _;

	/// The content of the control. Can be a UIElement or text.
	public UIElement Content
	{
		get => mContent;
		set
		{
			if (mContent != value)
			{
				if (mContent != null)
					RemoveChild(mContent);

				mContent = value;

				if (mContent != null)
					AddChild(mContent);

				InvalidateMeasure();
			}
		}
	}

	/// Sets text content directly.
	public StringView ContentText
	{
		get => mContentText ?? "";
		set
		{
			if (mContentText == null)
				mContentText = new String();
			mContentText.Set(value);
			InvalidateMeasure();
		}
	}

	/// Whether the content is a UIElement.
	public bool HasElementContent => mContent != null;

	/// Gets the font service from the context.
	protected IFontService GetFontService()
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
	protected CachedFont GetCachedFont()
	{
		let fontService = GetFontService();
		if (fontService == null)
			return null;

		return fontService.GetFont(FontFamily, FontSize);
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		if (mContent != null)
		{
			mContent.Measure(constraints);
			return mContent.DesiredSize;
		}

		// If we have text content but no element, measure the text
		if (mContentText != null && mContentText.Length > 0)
		{
			// Try to measure with actual font
			let cachedFont = GetCachedFont();
			if (cachedFont != null)
			{
				let font = cachedFont.Font;
				let textWidth = font.MeasureString(mContentText);
				let lineHeight = font.Metrics.LineHeight;
				return .(textWidth, lineHeight);
			}

			// Fallback: approximate text size based on font size
			let fontSize = FontSize;
			let textWidth = mContentText.Length * fontSize * 0.6f;
			let textHeight = fontSize * 1.2f;
			return .(textWidth, textHeight);
		}

		return .(0, 0);
	}

	protected override void ArrangeContent(RectangleF contentBounds)
	{
		if (mContent != null)
		{
			mContent.Arrange(contentBounds);
		}
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		if (mContent != null)
		{
			// Content renders itself via the tree
			return;
		}

		// Render text content if no element
		if (mContentText != null && mContentText.Length > 0)
		{
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
					drawContext.DrawText(mContentText, font, atlas, atlasTexture, bounds, .Center, .Middle, foreground);
					return;
				}
			}
		}
	}
}

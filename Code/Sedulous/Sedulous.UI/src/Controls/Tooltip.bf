using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// A popup that displays help text when hovering over an element.
public class Tooltip : Popup
{
	private String mText ~ delete _;

	/// The text displayed in the tooltip.
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

	/// Delay before showing the tooltip in seconds.
	public float ShowDelay { get; set; } = 0.5f;

	public this()
	{
		Behavior = .CloseOnClickOutside;
		Padding = Thickness(6, 4);
		Focusable = false;
	}

	public this(StringView text) : this()
	{
		Text = text;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		let fontSize = FontSize;
		var width = Padding.TotalHorizontal;
		var height = fontSize * 1.2f + Padding.TotalVertical;

		if (mText != null && mText.Length > 0)
			width += mText.Length * fontSize * 0.6f;
		else
			width += 20;

		return .(width, height);
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		// Shadow
		let shadowOffset = 2f;
		let shadowBounds = RectangleF(bounds.X + shadowOffset, bounds.Y + shadowOffset, bounds.Width, bounds.Height);
		drawContext.FillRect(shadowBounds, Color(0, 0, 0, 60));

		// Background - typically a light yellow or the surface color
		let bg = Background ?? theme?.GetColor("TooltipBackground") ?? Color(255, 255, 225);
		drawContext.FillRect(bounds, bg);

		// Border
		let border = BorderBrush ?? theme?.GetColor("TooltipBorder") ?? Color(100, 100, 100);
		drawContext.DrawRect(bounds, border, 1);

		// Text
		if (mText != null && mText.Length > 0)
		{
			let foreground = Foreground ?? theme?.GetColor("TooltipForeground") ?? theme?.GetColor("Foreground") ?? Color.Black;
			let contentBounds = ContentBounds;

			let fontService = GetFontService();
			let cachedFont = fontService?.GetFont(FontFamily, FontSize);

			if (fontService != null && cachedFont != null)
			{
				let font = cachedFont.Font;
				let atlas = cachedFont.Atlas;
				let atlasTexture = fontService.GetAtlasTexture(cachedFont);

				if (atlas != null && atlasTexture != null)
				{
					drawContext.DrawText(mText, font, atlas, atlasTexture, contentBounds, .Left, .Middle, foreground);
				}
			}
		}
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
}

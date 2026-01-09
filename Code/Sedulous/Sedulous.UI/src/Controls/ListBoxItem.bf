using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// An item in a ListBox.
public class ListBoxItem : Control
{
	private String mText ~ delete _;
	private bool mIsSelected;
	private Object mTag;

	/// The text displayed for this item.
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

	/// Whether this item is currently selected.
	public bool IsSelected
	{
		get => mIsSelected;
		set
		{
			if (mIsSelected != value)
			{
				mIsSelected = value;
				InvalidateVisual();
			}
		}
	}

	/// User-defined data associated with this item.
	public Object Tag
	{
		get => mTag;
		set => mTag = value;
	}

	public this()
	{
		Focusable = false;
		Height = .Fixed(24);
		Padding = Thickness(6, 2);
	}

	public this(StringView text) : this()
	{
		Text = text;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		let fontSize = FontSize;
		var width = 0f;

		if (mText != null && mText.Length > 0)
			width = mText.Length * fontSize * 0.6f;

		return .(width, fontSize * 1.4f);
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		// Background based on selection/hover state
		if (mIsSelected)
		{
			let selectedBg = theme?.GetColor("ListItemSelected") ?? theme?.GetColor("Selected") ?? Color(204, 228, 247);
			drawContext.FillRect(bounds, selectedBg);
		}
		else if (IsMouseOver)
		{
			let hoverBg = theme?.GetColor("ListItemHover") ?? theme?.GetColor("Hover") ?? Color(229, 241, 251);
			drawContext.FillRect(bounds, hoverBg);
		}

		// Text
		if (mText != null && mText.Length > 0)
		{
			let foreground = Foreground ?? theme?.GetColor("Foreground") ?? Color.Black;
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

	protected override void OnMouseEnter()
	{
		base.OnMouseEnter();
		InvalidateVisual();
	}

	protected override void OnMouseLeave()
	{
		base.OnMouseLeave();
		InvalidateVisual();
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

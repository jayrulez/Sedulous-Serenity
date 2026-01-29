using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.UI;

/// An item displayed in a TileView as an icon with label.
public class TileViewItem : Control
{
	private String mText ~ delete _;
	private bool mIsSelected;
	private Object mTag;
	private IImageData mIcon;

	/// The text displayed below the icon.
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

	/// Optional icon image.
	public IImageData Icon
	{
		get => mIcon;
		set
		{
			mIcon = value;
			InvalidateVisual();
		}
	}

	public this()
	{
		Focusable = false;
		Padding = Thickness(4);
	}

	public this(StringView text) : this()
	{
		Text = text;
	}

	public this(StringView text, IImageData icon) : this(text)
	{
		mIcon = icon;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		// Tiles have fixed size based on parent TileView settings
		// Default fallback if not in a TileView
		return .(80, 80);
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		// Background based on selection/hover state
		if (mIsSelected)
		{
			let selectedBg = theme?.GetColor("TileItemSelected") ?? theme?.GetColor("ListItemSelected") ?? theme?.GetColor("Selected") ?? Color(51, 51, 51);
			drawContext.FillRect(bounds, selectedBg);

			// Selection border
			let borderColor = theme?.GetColor("TileBorderSelected") ?? theme?.GetColor("BorderFocused") ?? Color(0, 120, 215);
			drawContext.DrawRect(bounds, borderColor, 2);
		}
		else if (IsMouseOver)
		{
			let hoverBg = theme?.GetColor("TileItemHover") ?? theme?.GetColor("ListItemHover") ?? theme?.GetColor("Hover") ?? Color(62, 62, 64);
			drawContext.FillRect(bounds, hoverBg);
		}

		let contentBounds = ContentBounds;
		let iconSize = Math.Min(contentBounds.Width - 8, contentBounds.Height - 20);
		let iconX = contentBounds.X + (contentBounds.Width - iconSize) / 2;
		let iconY = contentBounds.Y + 4;

		// Icon area
		if (mIcon != null)
		{
			let iconRect = RectangleF(iconX, iconY, iconSize, iconSize);
			drawContext.DrawImage(mIcon, iconRect);
		}
		else
		{
			// Default placeholder icon (folder/file shape)
			let iconRect = RectangleF(iconX + 4, iconY + 4, iconSize - 8, iconSize - 8);
			let iconColor = theme?.GetColor("TileIconPlaceholder") ?? Color(100, 100, 100);
			drawContext.FillRoundedRect(iconRect, 4, iconColor);
		}

		// Text below icon
		if (mText != null && mText.Length > 0)
		{
			let foreground = Foreground ?? theme?.GetColor("Foreground") ?? Color(220, 220, 220);
			let textY = iconY + iconSize + 4;
			let textBounds = RectangleF(contentBounds.X, textY, contentBounds.Width, contentBounds.Bottom - textY);

			let fontService = GetFontService();
			let cachedFont = fontService?.GetFont(FontFamily, FontSize);

			if (fontService != null && cachedFont != null)
			{
				let font = cachedFont.Font;
				let atlas = cachedFont.Atlas;
				let atlasTexture = fontService.GetAtlasTexture(cachedFont);

				if (atlas != null && atlasTexture != null)
				{
					// Truncate text if too long
					let maxWidth = contentBounds.Width - 4;
					let measuredWidth = font.MeasureString(mText);

					if (measuredWidth > maxWidth)
					{
						// Find how many characters fit with ellipsis
						let ellipsis = "...";
						let ellipsisWidth = font.MeasureString(ellipsis);
						let availableWidth = maxWidth - ellipsisWidth;

						let truncated = scope String();
						for (let c in mText.DecodedChars)
						{
							truncated.Append(c);
							if (font.MeasureString(truncated) > availableWidth)
							{
								truncated.RemoveFromEnd(1);
								break;
							}
						}
						truncated.Append(ellipsis);
						drawContext.DrawText(truncated, font, atlas, atlasTexture, textBounds, .Center, .Top, foreground);
					}
					else
					{
						drawContext.DrawText(mText, font, atlas, atlasTexture, textBounds, .Center, .Top, foreground);
					}
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

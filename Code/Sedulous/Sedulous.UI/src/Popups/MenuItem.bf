using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// Represents an item in a context menu or menu bar.
public class MenuItem : Control
{
	private String mText ~ delete _;
	private String mShortcutText ~ delete _;
	private bool mIsSubmenuOpen;
	private ContextMenu mSubmenu;
	private bool mIsSeparator;

	// Events
	private EventAccessor<delegate void(MenuItem)> mClickEvent = new .() ~ delete _;

	/// The text displayed for this menu item.
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

	/// The keyboard shortcut text displayed (e.g., "Ctrl+S").
	public StringView ShortcutText
	{
		get => mShortcutText ?? "";
		set
		{
			if (mShortcutText == null)
				mShortcutText = new String();
			mShortcutText.Set(value);
			InvalidateMeasure();
		}
	}

	/// Whether this menu item is a separator line.
	public bool IsSeparator
	{
		get => mIsSeparator;
		set { mIsSeparator = value; InvalidateMeasure(); }
	}

	/// Submenu that opens when this item is hovered/clicked.
	public ContextMenu Submenu
	{
		get => mSubmenu;
		set => mSubmenu = value;
	}

	/// Whether this item has a submenu.
	public bool HasSubmenu => mSubmenu != null;

	/// Fired when the menu item is clicked.
	public EventAccessor<delegate void(MenuItem)> Click => mClickEvent;

	public this()
	{
		Focusable = false;
		Height = 24;
		Padding = Thickness(8, 4);
	}

	public this(StringView text) : this()
	{
		Text = text;
	}

	/// Creates a separator menu item.
	public static MenuItem Separator()
	{
		let item = new MenuItem();
		item.IsSeparator = true;
		item.Height = 8;
		item.Padding = Thickness(4, 2);
		return item;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		if (mIsSeparator)
			return .(0, 1); // Separator stretches to fill width, doesn't request specific width

		// Measure text
		let fontSize = FontSize;
		var width = 0.0f;

		if (mText != null && mText.Length > 0)
			width += mText.Length * fontSize * 0.6f;

		// Add space for shortcut
		if (mShortcutText != null && mShortcutText.Length > 0)
			width += 40 + mShortcutText.Length * fontSize * 0.6f;

		// Add space for submenu arrow
		if (HasSubmenu)
			width += 20;

		return .(width, fontSize * 1.2f);
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		if (mIsSeparator)
		{
			// Draw separator line
			let separatorColor = theme?.GetColor("Border") ?? Color(80, 80, 90);
			let y = bounds.Y + bounds.Height / 2;
			drawContext.FillRect(.(bounds.X + 4, y, bounds.Width - 8, 1), separatorColor);
			return;
		}

		// Background on hover
		if (IsMouseOver && IsEnabled)
		{
			let hoverBg = theme?.GetColor("PrimaryHover") ?? Color(60, 60, 80);
			drawContext.FillRect(bounds, hoverBg);
		}

		// Text
		let foreground = IsEnabled
			? (Foreground ?? theme?.GetColor("Foreground") ?? Color.White)
			: (theme?.GetColor("ForegroundDisabled") ?? Color(128, 128, 128));

		let contentBounds = ContentBounds;
		var textX = contentBounds.X;
		let textY = contentBounds.Y;

		if (mText != null && mText.Length > 0)
		{
			// Draw with actual font if available
			let fontService = GetFontService();
			let cachedFont = fontService?.GetFont(FontFamily, FontSize);
			if (fontService != null && cachedFont != null)
			{
				let font = cachedFont.Font;
				let atlas = cachedFont.Atlas;
				let atlasTexture = fontService.GetAtlasTexture(cachedFont);
				if (atlas != null && atlasTexture != null)
				{
					let textBounds = RectangleF(textX, textY, contentBounds.Width, contentBounds.Height);
					drawContext.DrawText(mText, font, atlas, atlasTexture, textBounds, .Left, .Middle, foreground);
				}
			}
		}

		// Shortcut text (right-aligned)
		if (mShortcutText != null && mShortcutText.Length > 0)
		{
			let shortcutColor = Color(foreground.R, foreground.G, foreground.B, (uint8)(foreground.A * 0.7f));
			let fontService = GetFontService();
			let cachedFont = fontService?.GetFont(FontFamily, FontSize);
			if (fontService != null && cachedFont != null)
			{
				let font = cachedFont.Font;
				let atlas = cachedFont.Atlas;
				let atlasTexture = fontService.GetAtlasTexture(cachedFont);
				if (atlas != null && atlasTexture != null)
				{
					let textBounds = RectangleF(textX, textY, contentBounds.Width - 20, contentBounds.Height);
					drawContext.DrawText(mShortcutText, font, atlas, atlasTexture, textBounds, .Right, .Middle, shortcutColor);
				}
			}
		}

		// Submenu arrow
		if (HasSubmenu)
		{
			let arrowX = bounds.Right - 12;
			let arrowY = bounds.Y + bounds.Height / 2;
			// Draw simple arrow triangle
			drawContext.FillRect(.(arrowX, arrowY - 3, 6, 1), foreground);
			drawContext.FillRect(.(arrowX + 1, arrowY - 2, 4, 1), foreground);
			drawContext.FillRect(.(arrowX + 2, arrowY - 1, 2, 1), foreground);
			drawContext.FillRect(.(arrowX + 2, arrowY, 2, 1), foreground);
			drawContext.FillRect(.(arrowX + 1, arrowY + 1, 4, 1), foreground);
			drawContext.FillRect(.(arrowX, arrowY + 2, 6, 1), foreground);
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

	protected override void OnMouseEnter()
	{
		base.OnMouseEnter();

		// Open submenu on hover after a short delay
		if (HasSubmenu && !mIsSubmenuOpen)
		{
			OpenSubmenu();
		}

		InvalidateVisual();
	}

	protected override void OnMouseLeave()
	{
		base.OnMouseLeave();
		InvalidateVisual();
	}

	protected override void OnMouseUpRouted(MouseButtonEventArgs args)
	{
		base.OnMouseUpRouted(args);

		if (args.Button == .Left && !mIsSeparator && IsEnabled && !HasSubmenu)
		{
			// Fire click event
			mClickEvent.[Friend]Invoke(this);

			// Close parent menu
			if (Parent != null)
			{
				if (let menu = Parent.Parent as ContextMenu)
					menu.Close();
			}

			args.Handled = true;
		}
	}

	private void OpenSubmenu()
	{
		if (mSubmenu == null || mIsSubmenuOpen)
			return;

		mIsSubmenuOpen = true;
		mSubmenu.OpenAt(this, .Right);
	}

	private void CloseSubmenu()
	{
		if (mSubmenu == null || !mIsSubmenuOpen)
			return;

		mIsSubmenuOpen = false;
		mSubmenu.Close();
	}
}

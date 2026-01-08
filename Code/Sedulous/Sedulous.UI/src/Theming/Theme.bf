using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Complete UI theme with colors, floats, fonts, textures, and styles.
class Theme
{
	private String mName ~ delete _;
	private Dictionary<String, ThemeColor> mColors ~ DeleteDictionaryAndKeys!(_);
	private Dictionary<String, float> mFloats ~ DeleteDictionaryAndKeys!(_);
	private Dictionary<String, FontHandle> mFonts ~ DeleteDictionaryAndKeys!(_);
	private Dictionary<String, TextureHandle> mTextures ~ DeleteDictionaryAndKeys!(_);
	private Dictionary<String, Style> mStyles ~ DeleteDictionaryAndKeysAndValues!(_);

	/// Creates a new empty theme.
	public this()
	{
		mColors = new Dictionary<String, ThemeColor>();
		mFloats = new Dictionary<String, float>();
		mFonts = new Dictionary<String, FontHandle>();
		mTextures = new Dictionary<String, TextureHandle>();
		mStyles = new Dictionary<String, Style>();
	}

	/// Creates a theme with a name.
	public this(StringView name) : this()
	{
		mName = new String(name);
	}

	/// Gets or sets the theme name.
	public StringView Name
	{
		get => mName ?? "";
		set
		{
			delete mName;
			mName = value.IsEmpty ? null : new String(value);
		}
	}

	/// Gets the colors dictionary.
	public Dictionary<String, ThemeColor> Colors => mColors;

	/// Gets the floats dictionary.
	public Dictionary<String, float> Floats => mFloats;

	/// Gets the fonts dictionary.
	public Dictionary<String, FontHandle> Fonts => mFonts;

	/// Gets the textures dictionary.
	public Dictionary<String, TextureHandle> Textures => mTextures;

	/// Gets the styles dictionary.
	public Dictionary<String, Style> Styles => mStyles;

	// ============ Standard Color Keys ============

	public static readonly StringView BackgroundColor = "Background";
	public static readonly StringView ForegroundColor = "Foreground";
	public static readonly StringView PrimaryColor = "Primary";
	public static readonly StringView SecondaryColor = "Secondary";
	public static readonly StringView AccentColor = "Accent";
	public static readonly StringView BorderColor = "Border";
	public static readonly StringView DisabledColor = "Disabled";
	public static readonly StringView DisabledTextColor = "DisabledText";
	public static readonly StringView HoverColor = "Hover";
	public static readonly StringView PressedColor = "Pressed";
	public static readonly StringView SelectionColor = "Selection";
	public static readonly StringView ErrorColor = "Error";
	public static readonly StringView WarningColor = "Warning";
	public static readonly StringView SuccessColor = "Success";
	public static readonly StringView InfoColor = "Info";

	// Control-specific colors
	public static readonly StringView ButtonBackground = "ButtonBackground";
	public static readonly StringView ButtonHover = "ButtonHover";
	public static readonly StringView ButtonPressed = "ButtonPressed";
	public static readonly StringView ButtonBorder = "ButtonBorder";
	public static readonly StringView TextBoxBackground = "TextBoxBackground";
	public static readonly StringView TextBoxBorder = "TextBoxBorder";
	public static readonly StringView ScrollBarTrack = "ScrollBarTrack";
	public static readonly StringView ScrollBarThumb = "ScrollBarThumb";
	public static readonly StringView SliderTrack = "SliderTrack";
	public static readonly StringView SliderFill = "SliderFill";
	public static readonly StringView SliderThumb = "SliderThumb";
	public static readonly StringView CheckBoxBackground = "CheckBoxBackground";
	public static readonly StringView CheckBoxCheck = "CheckBoxCheck";
	public static readonly StringView ProgressBarBackground = "ProgressBarBackground";
	public static readonly StringView ProgressBarFill = "ProgressBarFill";

	// ============ Standard Float Keys ============

	public static readonly StringView BorderRadius = "BorderRadius";
	public static readonly StringView BorderWidth = "BorderWidth";
	public static readonly StringView FontSizeSmall = "FontSizeSmall";
	public static readonly StringView FontSizeNormal = "FontSizeNormal";
	public static readonly StringView FontSizeLarge = "FontSizeLarge";
	public static readonly StringView FontSizeHeader = "FontSizeHeader";
	public static readonly StringView Spacing = "Spacing";
	public static readonly StringView SpacingSmall = "SpacingSmall";
	public static readonly StringView SpacingLarge = "SpacingLarge";
	public static readonly StringView Padding = "Padding";
	public static readonly StringView PaddingSmall = "PaddingSmall";
	public static readonly StringView PaddingLarge = "PaddingLarge";
	public static readonly StringView ControlHeight = "ControlHeight";
	public static readonly StringView ScrollBarWidth = "ScrollBarWidth";

	// ============ Standard Font Keys ============

	public static readonly StringView DefaultFont = "Default";
	public static readonly StringView BoldFont = "Bold";
	public static readonly StringView ItalicFont = "Italic";
	public static readonly StringView MonospaceFont = "Monospace";
	public static readonly StringView HeaderFont = "Header";

	// ============ Setters ============

	/// Sets a color value.
	public void SetColor(StringView key, ThemeColor color)
	{
		let keyStr = new String(key);
		if (mColors.ContainsKey(keyStr))
		{
			mColors[keyStr] = color;
			delete keyStr;
		}
		else
		{
			mColors[keyStr] = color;
		}
	}

	/// Sets a color from a Color value.
	public void SetColor(StringView key, Color color)
	{
		SetColor(key, ThemeColor(color));
	}

	/// Sets a float value.
	public void SetFloat(StringView key, float value)
	{
		let keyStr = new String(key);
		if (mFloats.ContainsKey(keyStr))
		{
			mFloats[keyStr] = value;
			delete keyStr;
		}
		else
		{
			mFloats[keyStr] = value;
		}
	}

	/// Sets a font value.
	public void SetFont(StringView key, FontHandle font)
	{
		let keyStr = new String(key);
		if (mFonts.ContainsKey(keyStr))
		{
			mFonts[keyStr] = font;
			delete keyStr;
		}
		else
		{
			mFonts[keyStr] = font;
		}
	}

	/// Sets a texture value.
	public void SetTexture(StringView key, TextureHandle texture)
	{
		let keyStr = new String(key);
		if (mTextures.ContainsKey(keyStr))
		{
			mTextures[keyStr] = texture;
			delete keyStr;
		}
		else
		{
			mTextures[keyStr] = texture;
		}
	}

	/// Sets a style value.
	public void SetStyle(StringView key, Style style)
	{
		let keyStr = new String(key);
		if (mStyles.ContainsKey(keyStr))
		{
			let oldStyle = mStyles[keyStr];
			mStyles[keyStr] = style;
			delete oldStyle;
			delete keyStr;
		}
		else
		{
			mStyles[keyStr] = style;
		}
	}

	// ============ Getters ============

	/// Gets a color value with fallback.
	public ThemeColor GetColor(StringView key, ThemeColor fallback = default)
	{
		if (mColors.TryGetValue(scope String(key), let value))
			return value;
		return fallback;
	}

	/// Gets a color as Color type with fallback.
	public Color GetColorValue(StringView key, Color fallback = .White)
	{
		if (mColors.TryGetValue(scope String(key), let value))
			return value.Primary;
		return fallback;
	}

	/// Gets a float value with fallback.
	public float GetFloat(StringView key, float fallback = 0)
	{
		if (mFloats.TryGetValue(scope String(key), let value))
			return value;
		return fallback;
	}

	/// Gets a font value.
	public FontHandle GetFont(StringView key)
	{
		if (mFonts.TryGetValue(scope String(key), let value))
			return value;
		return default;
	}

	/// Gets a texture value.
	public TextureHandle GetTexture(StringView key)
	{
		if (mTextures.TryGetValue(scope String(key), let value))
			return value;
		return default;
	}

	/// Gets a style for a widget type.
	public Style GetStyle(StringView widgetType)
	{
		if (mStyles.TryGetValue(scope String(widgetType), let value))
			return value;
		return null;
	}

	// ============ Built-in Theme Factories ============

	/// Creates a dark theme.
	public static Theme CreateDark()
	{
		let theme = new Theme("Dark");

		// Background colors
		theme.SetColor(BackgroundColor, Color(30, 30, 30, 255));
		theme.SetColor(ForegroundColor, Color(220, 220, 220, 255));

		// Primary palette
		theme.SetColor(PrimaryColor, Color(60, 120, 200, 255));
		theme.SetColor(SecondaryColor, Color(80, 80, 80, 255));
		theme.SetColor(AccentColor, Color(100, 180, 255, 255));

		// State colors
		theme.SetColor(BorderColor, Color(80, 80, 80, 255));
		theme.SetColor(DisabledColor, Color(50, 50, 50, 255));
		theme.SetColor(DisabledTextColor, Color(120, 120, 120, 255));
		theme.SetColor(HoverColor, Color(70, 70, 70, 255));
		theme.SetColor(PressedColor, Color(40, 40, 40, 255));
		theme.SetColor(SelectionColor, Color(60, 120, 200, 180));

		// Semantic colors
		theme.SetColor(ErrorColor, Color(200, 60, 60, 255));
		theme.SetColor(WarningColor, Color(220, 180, 60, 255));
		theme.SetColor(SuccessColor, Color(60, 180, 80, 255));
		theme.SetColor(InfoColor, Color(60, 140, 200, 255));

		// Button
		theme.SetColor(ButtonBackground, Color(60, 60, 60, 255));
		theme.SetColor(ButtonHover, Color(80, 80, 80, 255));
		theme.SetColor(ButtonPressed, Color(40, 40, 40, 255));
		theme.SetColor(ButtonBorder, Color(100, 100, 100, 255));

		// TextBox
		theme.SetColor(TextBoxBackground, Color(45, 45, 45, 255));
		theme.SetColor(TextBoxBorder, Color(70, 70, 70, 255));

		// ScrollBar
		theme.SetColor(ScrollBarTrack, Color(40, 40, 40, 200));
		theme.SetColor(ScrollBarThumb, Color(100, 100, 100, 255));

		// Slider
		theme.SetColor(SliderTrack, Color(60, 60, 60, 255));
		theme.SetColor(SliderFill, Color(60, 120, 200, 255));
		theme.SetColor(SliderThumb, Color(200, 200, 200, 255));

		// CheckBox
		theme.SetColor(CheckBoxBackground, Color(60, 60, 60, 255));
		theme.SetColor(CheckBoxCheck, Color(60, 180, 60, 255));

		// ProgressBar
		theme.SetColor(ProgressBarBackground, Color(40, 40, 40, 255));
		theme.SetColor(ProgressBarFill, Color(60, 120, 200, 255));

		// Floats
		theme.SetFloat(BorderRadius, 4);
		theme.SetFloat(BorderWidth, 1);
		theme.SetFloat(FontSizeSmall, 11);
		theme.SetFloat(FontSizeNormal, 14);
		theme.SetFloat(FontSizeLarge, 18);
		theme.SetFloat(FontSizeHeader, 24);
		theme.SetFloat(Spacing, 8);
		theme.SetFloat(SpacingSmall, 4);
		theme.SetFloat(SpacingLarge, 16);
		theme.SetFloat(Padding, 8);
		theme.SetFloat(PaddingSmall, 4);
		theme.SetFloat(PaddingLarge, 12);
		theme.SetFloat(ControlHeight, 28);
		theme.SetFloat(ScrollBarWidth, 12);

		return theme;
	}

	/// Creates a light theme.
	public static Theme CreateLight()
	{
		let theme = new Theme("Light");

		// Background colors
		theme.SetColor(BackgroundColor, Color(245, 245, 245, 255));
		theme.SetColor(ForegroundColor, Color(30, 30, 30, 255));

		// Primary palette
		theme.SetColor(PrimaryColor, Color(0, 120, 212, 255));
		theme.SetColor(SecondaryColor, Color(200, 200, 200, 255));
		theme.SetColor(AccentColor, Color(0, 100, 200, 255));

		// State colors
		theme.SetColor(BorderColor, Color(180, 180, 180, 255));
		theme.SetColor(DisabledColor, Color(220, 220, 220, 255));
		theme.SetColor(DisabledTextColor, Color(160, 160, 160, 255));
		theme.SetColor(HoverColor, Color(230, 230, 230, 255));
		theme.SetColor(PressedColor, Color(200, 200, 200, 255));
		theme.SetColor(SelectionColor, Color(0, 120, 212, 100));

		// Semantic colors
		theme.SetColor(ErrorColor, Color(200, 50, 50, 255));
		theme.SetColor(WarningColor, Color(200, 150, 0, 255));
		theme.SetColor(SuccessColor, Color(50, 160, 70, 255));
		theme.SetColor(InfoColor, Color(0, 120, 200, 255));

		// Button
		theme.SetColor(ButtonBackground, Color(225, 225, 225, 255));
		theme.SetColor(ButtonHover, Color(210, 210, 210, 255));
		theme.SetColor(ButtonPressed, Color(190, 190, 190, 255));
		theme.SetColor(ButtonBorder, Color(170, 170, 170, 255));

		// TextBox
		theme.SetColor(TextBoxBackground, Color(255, 255, 255, 255));
		theme.SetColor(TextBoxBorder, Color(180, 180, 180, 255));

		// ScrollBar
		theme.SetColor(ScrollBarTrack, Color(230, 230, 230, 255));
		theme.SetColor(ScrollBarThumb, Color(180, 180, 180, 255));

		// Slider
		theme.SetColor(SliderTrack, Color(200, 200, 200, 255));
		theme.SetColor(SliderFill, Color(0, 120, 212, 255));
		theme.SetColor(SliderThumb, Color(100, 100, 100, 255));

		// CheckBox
		theme.SetColor(CheckBoxBackground, Color(255, 255, 255, 255));
		theme.SetColor(CheckBoxCheck, Color(0, 150, 50, 255));

		// ProgressBar
		theme.SetColor(ProgressBarBackground, Color(220, 220, 220, 255));
		theme.SetColor(ProgressBarFill, Color(0, 120, 212, 255));

		// Floats - same as dark theme
		theme.SetFloat(BorderRadius, 4);
		theme.SetFloat(BorderWidth, 1);
		theme.SetFloat(FontSizeSmall, 11);
		theme.SetFloat(FontSizeNormal, 14);
		theme.SetFloat(FontSizeLarge, 18);
		theme.SetFloat(FontSizeHeader, 24);
		theme.SetFloat(Spacing, 8);
		theme.SetFloat(SpacingSmall, 4);
		theme.SetFloat(SpacingLarge, 16);
		theme.SetFloat(Padding, 8);
		theme.SetFloat(PaddingSmall, 4);
		theme.SetFloat(PaddingLarge, 12);
		theme.SetFloat(ControlHeight, 28);
		theme.SetFloat(ScrollBarWidth, 12);

		return theme;
	}
}

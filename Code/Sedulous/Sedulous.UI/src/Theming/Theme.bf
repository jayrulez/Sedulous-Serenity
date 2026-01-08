using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// A theme that defines visual appearance for controls.
public class Theme : ITheme
{
	private Dictionary<Type, Style> mStyles = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<String, Color> mColors = new .() ~ DeleteDictionaryAndKeys!(_);
	private String mDefaultFontFamily = new .("Segoe UI") ~ delete _;
	private float mDefaultFontSize = 14.0f;

	/// Gets the default font family name.
	public StringView DefaultFontFamily => mDefaultFontFamily;

	/// Gets the default font size.
	public float DefaultFontSize => mDefaultFontSize;

	/// Sets the default font family.
	public void SetDefaultFontFamily(StringView fontFamily)
	{
		mDefaultFontFamily.Set(fontFamily);
	}

	/// Sets the default font size.
	public void SetDefaultFontSize(float size)
	{
		mDefaultFontSize = size;
	}

	/// Registers a style for a control type.
	public void RegisterStyle(Type controlType, Style style)
	{
		if (mStyles.ContainsKey(controlType))
		{
			delete mStyles[controlType];
		}
		mStyles[controlType] = style;
	}

	/// Gets the style for a control type.
	public Style GetStyle(Type controlType)
	{
		if (mStyles.TryGetValue(controlType, let style))
			return style;
		return null;
	}

	/// Sets a named color in the palette.
	public void SetColor(StringView colorName, Color color)
	{
		let key = new String(colorName);
		if (mColors.TryGetValueAlt(colorName, ?))
		{
			mColors[key] = color;
			delete key;
		}
		else
		{
			mColors[key] = color;
		}
	}

	/// Gets a color from the palette.
	public Color GetColor(StringView colorName)
	{
		if (mColors.TryGetValueAlt(colorName, let color))
			return color;
		return Color.Magenta; // Missing color indicator
	}

	/// Checks if a named color exists.
	public bool HasColor(StringView colorName)
	{
		return mColors.ContainsKeyAlt(colorName);
	}
}

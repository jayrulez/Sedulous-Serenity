using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Interface for theme providers that define the visual appearance of controls.
public interface ITheme
{
	/// Gets the style for a specific control type.
	Style GetStyle(Type controlType);

	/// Gets a color from the theme's palette.
	Color GetColor(StringView colorName);

	/// Gets the default font family name.
	StringView DefaultFontFamily { get; }

	/// Gets the default font size.
	float DefaultFontSize { get; }
}

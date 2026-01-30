using System;
using Sedulous.Mathematics;

namespace Sedulous.GUI;

/// Interface for theme providers.
/// Themes define the visual appearance of controls.
public interface ITheme
{
	/// The name of the theme.
	StringView Name { get; }

	/// The color palette for this theme.
	Palette Palette { get; }

	/// Gets the style for a specific control type.
	/// Returns a default style if no specific style is defined.
	ControlStyle GetControlStyle(StringView controlType);

	/// Gets the focus indicator color.
	Color FocusIndicatorColor { get; }

	/// Gets the focus indicator thickness.
	float FocusIndicatorThickness { get; }

	/// Gets the selection highlight color.
	Color SelectionColor { get; }

	/// Gets the default font size.
	float DefaultFontSize { get; }
}

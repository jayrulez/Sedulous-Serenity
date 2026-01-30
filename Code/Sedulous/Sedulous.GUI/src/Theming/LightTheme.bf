using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.GUI;

/// Light theme variant.
public class LightTheme : ITheme
{
	private Palette mPalette;
	private Dictionary<String, ControlStyle> mStyles = new .() ~ DeleteDictionaryAndKeys!(_);

	public this()
	{
		// Initialize palette
		mPalette = .()
		{
			Primary = Color(98, 0, 238, 255),      // Purple
			Secondary = Color(0, 150, 136, 255),   // Teal
			Accent = Color(33, 150, 243, 255),     // Blue
			Background = Color(250, 250, 250, 255), // Near white
			Surface = Color(255, 255, 255, 255),   // White
			Error = Color(211, 47, 47, 255),       // Red
			Text = Color(33, 33, 33, 255),         // Near black
			TextSecondary = Color(117, 117, 117, 255), // Gray
			Border = Color(200, 200, 200, 255)     // Light gray
		};

		// Define control styles
		InitializeStyles();
	}

	private void InitializeStyles()
	{
		// Default control style
		mStyles[new String("Control")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// Button style
		mStyles[new String("Button")] = .()
		{
			Background = Color(240, 240, 240, 255),
			Foreground = mPalette.Text,
			BorderColor = Color(200, 200, 200, 255),
			BorderThickness = 1,
			CornerRadius = 4,
			Hover = .() { Background = Color(230, 230, 230, 255) },
			Pressed = .() { Background = Color(210, 210, 210, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// Panel style
		mStyles[new String("Panel")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0
		};

		// TextBox style
		mStyles[new String("TextBox")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Hover = .() { BorderColor = Color(150, 150, 150, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// Label style
		mStyles[new String("Label")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.Text,
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0
		};
	}

	public StringView Name => "Light";

	public Palette Palette => mPalette;

	public ControlStyle GetControlStyle(StringView controlType)
	{
		for (let kv in mStyles)
		{
			if (StringView(kv.key) == controlType)
				return kv.value;
		}
		// Return default Control style
		for (let kv in mStyles)
		{
			if (StringView(kv.key) == "Control")
				return kv.value;
		}
		// Fallback
		return .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4
		};
	}

	public Color FocusIndicatorColor => mPalette.Accent;
	public float FocusIndicatorThickness => 2;
	public Color SelectionColor => Color(33, 150, 243, 80);
	public float DefaultFontSize => 14;
}

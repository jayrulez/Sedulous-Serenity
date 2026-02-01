using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.GUI;

/// Default dark theme with modern styling.
public class DarkTheme : ITheme
{
	private Palette mPalette;
	private Dictionary<String, ControlStyle> mStyles = new .() ~ DeleteDictionaryAndKeys!(_);

	public this()
	{
		// Initialize palette
		mPalette = .()
		{
			Primary = Color(98, 0, 238, 255),      // Purple
			Secondary = Color(3, 218, 198, 255),   // Teal
			Accent = Color(100, 149, 237, 255),    // Cornflower blue
			Background = Color(18, 18, 18, 255),   // Near black
			Surface = Color(30, 30, 30, 255),      // Dark gray
			Error = Color(207, 102, 121, 255),     // Soft red
			Text = Color(255, 255, 255, 255),      // White
			TextSecondary = Color(180, 180, 180, 255), // Light gray
			Border = Color(60, 60, 60, 255)        // Medium gray
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
			Background = Color(55, 55, 55, 255),
			Foreground = mPalette.Text,
			BorderColor = Color(70, 70, 70, 255),
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(10, 4, 10, 4),  // Horizontal 10px, vertical 4px
			Hover = .() { Background = Color(70, 70, 70, 255) },
			Pressed = .() { Background = Color(45, 45, 45, 255) },
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
			Background = Color(25, 25, 25, 255),
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(6, 4, 6, 4),
			Hover = .() { BorderColor = Color(80, 80, 80, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// PasswordBox style (same as TextBox)
		mStyles[new String("PasswordBox")] = .()
		{
			Background = Color(25, 25, 25, 255),
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(6, 4, 6, 4),
			Hover = .() { BorderColor = Color(80, 80, 80, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// NumericUpDown style
		mStyles[new String("NumericUpDown")] = .()
		{
			Background = Color(25, 25, 25, 255),
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(4, 2, 4, 2),
			Hover = .() { BorderColor = Color(80, 80, 80, 255) },
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

		// TextBlock style
		mStyles[new String("TextBlock")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.Text,
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0
		};

		// Border style
		mStyles[new String("Border")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 0
		};

		// Separator style
		mStyles[new String("Separator")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.Text,
			BorderColor = Color(50, 50, 50, 255),  // Subtle line color
			BorderThickness = 1,
			CornerRadius = 0
		};

		// ProgressBar style
		mStyles[new String("ProgressBar")] = .()
		{
			Background = Color(40, 40, 40, 255),  // Track color
			Foreground = mPalette.Accent,         // Fill color
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 4
		};

		// RepeatButton style (same as Button)
		mStyles[new String("RepeatButton")] = .()
		{
			Background = Color(55, 55, 55, 255),
			Foreground = mPalette.Text,
			BorderColor = Color(70, 70, 70, 255),
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(10, 4, 10, 4),
			Hover = .() { Background = Color(70, 70, 70, 255) },
			Pressed = .() { Background = Color(45, 45, 45, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// ToggleButton style
		mStyles[new String("ToggleButton")] = .()
		{
			Background = Color(55, 55, 55, 255),
			Foreground = mPalette.Text,
			BorderColor = Color(70, 70, 70, 255),
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(10, 4, 10, 4),
			Hover = .() { Background = Color(70, 70, 70, 255) },
			Pressed = .() { Background = Color(45, 45, 45, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// CheckBox style
		mStyles[new String("CheckBox")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 2,
			CornerRadius = 3,
			Hover = .() { BorderColor = Color(100, 100, 100, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// RadioButton style
		mStyles[new String("RadioButton")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 2,
			CornerRadius = 0, // Circles don't use corner radius
			Hover = .() { BorderColor = Color(100, 100, 100, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// ToggleSwitch style
		mStyles[new String("ToggleSwitch")] = .()
		{
			Background = Color(60, 60, 60, 255),  // Track off color
			Foreground = mPalette.Text,
			BorderColor = Color(80, 80, 80, 255),
			BorderThickness = 1,
			CornerRadius = 12,
			Hover = .() { BorderColor = Color(100, 100, 100, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// Hyperlink style
		mStyles[new String("Hyperlink")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.Accent,
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0,
			Padding = .(2, 2, 2, 2),  // Minimal padding for hyperlinks
			Hover = .() { Foreground = Color(130, 179, 255, 255) }  // Lighter accent
		};

		// Slider style
		mStyles[new String("Slider")] = .()
		{
			Background = Color(50, 50, 50, 255),  // Track color
			Foreground = mPalette.Accent,         // Thumb color
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0
		};

		// ScrollBar style
		mStyles[new String("ScrollBar")] = .()
		{
			Background = Color(30, 30, 30, 255),  // Track color
			Foreground = Color(80, 80, 80, 255),  // Thumb color
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0,
			Hover = .() { Foreground = Color(100, 100, 100, 255) }
		};

		// ScrollViewer style
		mStyles[new String("ScrollViewer")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 0
		};

		// Splitter style
		mStyles[new String("Splitter")] = .()
		{
			Background = Color(45, 45, 45, 255),
			Foreground = Color(100, 100, 100, 255),  // Grip color
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0,
			Hover = .() { Background = Color(55, 55, 55, 255) }
		};

		// ItemsControl style
		mStyles[new String("ItemsControl")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 0
		};

		// ListBox style
		mStyles[new String("ListBox")] = .()
		{
			Background = Color(25, 25, 25, 255),
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// ListBoxItem style
		mStyles[new String("ListBoxItem")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.Text,
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0,
			Padding = .(8, 4, 8, 4),
			Hover = .() { Background = Color(50, 50, 50, 255) }
		};

		// ComboBox style
		mStyles[new String("ComboBox")] = .()
		{
			Background = Color(25, 25, 25, 255),
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(8, 4, 8, 4),
			Hover = .() { BorderColor = Color(80, 80, 80, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};
	}

	public StringView Name => "Dark";

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
	public Color SelectionColor => Color(100, 149, 237, 100);
	public float DefaultFontSize => 14;
}

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
			Padding = .(10, 4, 10, 4),
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
			Padding = .(6, 4, 6, 4),
			Hover = .() { BorderColor = Color(150, 150, 150, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// PasswordBox style (same as TextBox)
		mStyles[new String("PasswordBox")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(6, 4, 6, 4),
			Hover = .() { BorderColor = Color(150, 150, 150, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// NumericUpDown style
		mStyles[new String("NumericUpDown")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(4, 2, 4, 2),
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
			BorderColor = Color(220, 220, 220, 255),  // Subtle line color
			BorderThickness = 1,
			CornerRadius = 0
		};

		// ProgressBar style
		mStyles[new String("ProgressBar")] = .()
		{
			Background = Color(230, 230, 230, 255),  // Track color
			Foreground = mPalette.Accent,            // Fill color
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 4
		};

		// RepeatButton style (same as Button)
		mStyles[new String("RepeatButton")] = .()
		{
			Background = Color(240, 240, 240, 255),
			Foreground = mPalette.Text,
			BorderColor = Color(200, 200, 200, 255),
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(10, 4, 10, 4),
			Hover = .() { Background = Color(230, 230, 230, 255) },
			Pressed = .() { Background = Color(210, 210, 210, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// ToggleButton style
		mStyles[new String("ToggleButton")] = .()
		{
			Background = Color(240, 240, 240, 255),
			Foreground = mPalette.Text,
			BorderColor = Color(200, 200, 200, 255),
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(10, 4, 10, 4),
			Hover = .() { Background = Color(230, 230, 230, 255) },
			Pressed = .() { Background = Color(210, 210, 210, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// CheckBox style
		mStyles[new String("CheckBox")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = Color(150, 150, 150, 255),
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
			BorderColor = Color(150, 150, 150, 255),
			BorderThickness = 2,
			CornerRadius = 0, // Circles don't use corner radius
			Hover = .() { BorderColor = Color(100, 100, 100, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// ToggleSwitch style
		mStyles[new String("ToggleSwitch")] = .()
		{
			Background = Color(200, 200, 200, 255),  // Track off color
			Foreground = mPalette.Text,
			BorderColor = Color(180, 180, 180, 255),
			BorderThickness = 1,
			CornerRadius = 12,
			Hover = .() { BorderColor = Color(150, 150, 150, 255) },
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
			Padding = .(2, 2, 2, 2),
			Hover = .() { Foreground = Color(0, 120, 215, 255) }  // Darker accent
		};

		// Slider style
		mStyles[new String("Slider")] = .()
		{
			Background = Color(200, 200, 200, 255),  // Track color
			Foreground = mPalette.Accent,            // Thumb color
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0
		};

		// ScrollBar style
		mStyles[new String("ScrollBar")] = .()
		{
			Background = Color(235, 235, 235, 255),  // Track color
			Foreground = Color(180, 180, 180, 255),  // Thumb color
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0,
			Hover = .() { Foreground = Color(160, 160, 160, 255) }
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
			Background = Color(220, 220, 220, 255),
			Foreground = Color(160, 160, 160, 255),  // Grip color
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0,
			Hover = .() { Background = Color(200, 200, 200, 255) }
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
			Background = mPalette.Surface,
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
			Hover = .() { Background = Color(230, 230, 230, 255) }
		};

		// ComboBox style
		mStyles[new String("ComboBox")] = .()
		{
			Background = mPalette.Surface,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Padding = .(8, 4, 8, 4),
			Hover = .() { BorderColor = Color(150, 150, 150, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// TabControl style
		mStyles[new String("TabControl")] = .()
		{
			Background = Color(245, 245, 245, 255),
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 0,
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// TabItem style
		mStyles[new String("TabItem")] = .()
		{
			Background = Color(230, 230, 230, 255),
			Foreground = mPalette.Text,
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0,
			Padding = .(12, 6, 12, 6),
			Hover = .() { Background = Color(220, 220, 220, 255) }
		};

		// Expander style
		mStyles[new String("Expander")] = .()
		{
			Background = Color(250, 250, 250, 255),
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Hover = .() { Background = Color(245, 245, 245, 255) },
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// GroupBox style
		mStyles[new String("GroupBox")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 0,
			Padding = .(8, 8, 8, 8)
		};

		// Breadcrumb style
		mStyles[new String("Breadcrumb")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.TextSecondary,
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0,
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// BreadcrumbItem style
		mStyles[new String("BreadcrumbItem")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.Accent,
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 2,
			Padding = .(4, 2, 4, 2),
			Hover = .() { Background = Color(230, 230, 230, 255) }
		};

		// TreeView style
		mStyles[new String("TreeView")] = .()
		{
			Background = Color(255, 255, 255, 255),
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// TreeViewItem style
		mStyles[new String("TreeViewItem")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.Text,
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 0,
			Padding = .(4, 2, 4, 2),
			Hover = .() { Background = Color(230, 230, 230, 255) }
		};

		// TileView style
		mStyles[new String("TileView")] = .()
		{
			Background = Color(255, 255, 255, 255),
			Foreground = mPalette.Text,
			BorderColor = mPalette.Border,
			BorderThickness = 1,
			CornerRadius = 4,
			Focused = .() { BorderColor = mPalette.Accent }
		};

		// TileViewItem style
		mStyles[new String("TileViewItem")] = .()
		{
			Background = Color.Transparent,
			Foreground = mPalette.Text,
			BorderColor = Color.Transparent,
			BorderThickness = 0,
			CornerRadius = 4,
			Padding = .(4, 4, 4, 4),
			Hover = .() { Background = Color(230, 230, 230, 255) }
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

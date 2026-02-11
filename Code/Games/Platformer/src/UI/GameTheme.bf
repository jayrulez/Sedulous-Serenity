namespace Platformer.UI;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Mathematics;

/// Platformer game theme - bright, colorful, high-contrast.
class GameTheme : ITheme
{
	private Palette mPalette;
	private Dictionary<String, ControlStyle> mStyles = new .() ~ {
		for (var kv in _)
			delete kv.key;
		delete _;
	};

	public this()
	{
		mPalette = .()
		{
			Primary = Color(60, 140, 220, 255),      // Sky blue
			Secondary = Color(40, 100, 180, 255),     // Darker blue
			Accent = Color(255, 200, 50, 255),        // Gold
			Background = Color(25, 30, 45, 255),      // Deep navy
			Surface = Color(35, 42, 60, 255),         // Surface
			Text = Color(255, 255, 255, 255),         // White
			TextSecondary = Color(180, 190, 210, 255),// Light blue-gray
			Error = Color(220, 60, 60, 255),          // Red
			Success = Color(60, 200, 80, 255),        // Green
			Warning = Color(255, 180, 40, 255)        // Orange
		};

		InitializeStyles();
	}

	private void InitializeStyles()
	{
		let buttonBase = Color(50, 120, 200, 255);
		let buttonHover = Color(70, 150, 230, 255);
		let buttonPressed = Color(40, 100, 180, 255);

		mStyles[new String("Button")] = .()
		{
			Background = buttonBase,
			Foreground = mPalette.Text,
			BorderColor = Color(80, 160, 240, 200),
			BorderThickness = 2,
			CornerRadius = 8,
			Padding = .(16, 8, 16, 8),
			Hover = .() { Background = buttonHover, BorderColor = mPalette.Accent },
			Pressed = .() { Background = buttonPressed }
		};

		mStyles[new String("TextBlock")] = .()
		{
			Foreground = mPalette.Text,
		};

		mStyles[new String("Border")] = .()
		{
			Background = mPalette.Surface,
			BorderColor = Color(60, 70, 90, 200),
			BorderThickness = 1,
			CornerRadius = 6,
		};
	}

	public StringView Name => "Platformer";
	public Palette Palette => mPalette;

	public ControlStyle GetControlStyle(StringView controlType)
	{
		let key = scope String(controlType);
		if (mStyles.TryGetValue(key, let style))
			return style;
		return .();
	}

	public Color FocusIndicatorColor => mPalette.Accent;
	public float FocusIndicatorThickness => 2;
	public Color SelectionColor => Color(60, 140, 220, 128);
	public float DefaultFontSize => 16;
	public float MenuItemHeight => 36;
	public float MenuCheckWidth => 24;
	public float MenuArrowWidth => 16;
	public float MenuShortcutGap => 24;
	public float TabStripHeight => 36;
	public float ScrollBarThickness => 12;
	public float SliderTrackThickness => 4;
	public float SliderThumbSize => 16;
	public float CheckBoxSize => 20;
	public float CheckBoxSpacing => 8;
	public float RadioButtonSize => 20;
	public float RadioButtonSpacing => 8;
	public float ToggleSwitchTrackWidth => 40;
	public float ToggleSwitchTrackHeight => 20;
	public float ToggleSwitchKnobSize => 16;
	public float SeparatorThickness => 1;
	public float DefaultCornerRadius => 6;
	public float ComboBoxDropDownButtonWidth => 28;
	public float ComboBoxDropDownMaxHeight => 300;
	public float MessageBoxIconSize => 48;
	public float DockPanelTitleBarHeight => 28;
	public float DockTabHeight => 28;
	public float DockFontSize => 13;
	public float DockTabPadding => 8;
}

using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// A dark theme for the UI framework.
public class DarkTheme : Theme
{
	public this()
	{
		InitializeColors();
		InitializeStyles();
	}

	private void InitializeColors()
	{
		// Primary colors (blue accent)
		SetColor("Primary", .(0, 120, 215));
		SetColor("PrimaryLight", .(51, 153, 255));
		SetColor("PrimaryDark", .(0, 84, 153));

		// Secondary colors
		SetColor("Secondary", .(90, 100, 115));
		SetColor("SecondaryLight", .(120, 130, 145));
		SetColor("SecondaryDark", .(60, 70, 85));

		// Background colors (dark)
		SetColor("Background", .(30, 30, 30));
		SetColor("BackgroundAlt", .(45, 45, 45));
		SetColor("BackgroundDark", .(20, 20, 20));
		SetColor("Surface", .(45, 45, 50)); // Popup/menu surface

		// Foreground colors (light text on dark)
		SetColor("Foreground", .(240, 240, 240));
		SetColor("ForegroundSecondary", .(180, 180, 180));
		SetColor("ForegroundDisabled", .(100, 100, 100));

		// Border colors
		SetColor("Border", .(70, 70, 70));
		SetColor("BorderLight", .(90, 90, 90));
		SetColor("BorderDark", .(50, 50, 50));
		SetColor("BorderFocused", .(0, 120, 215));

		// State colors
		SetColor("Hover", .(55, 55, 55));
		SetColor("PrimaryHover", .(60, 80, 120)); // Menu item hover
		SetColor("Pressed", .(65, 65, 65));
		SetColor("Selected", .(0, 90, 158));
		SetColor("Disabled", .(40, 40, 40));

		// Accent colors
		SetColor("Success", .(46, 160, 67));
		SetColor("Warning", .(255, 185, 0));
		SetColor("Error", .(248, 81, 73));
		SetColor("Info", .(88, 166, 255));
	}

	private void InitializeStyles()
	{
		// Styles for specific controls can be added here
	}
}

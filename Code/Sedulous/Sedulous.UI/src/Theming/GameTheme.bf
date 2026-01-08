using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// A game-styled theme with bold colors and high contrast.
/// Features a dark base with cyan/orange accent colors.
public class GameTheme : Theme
{
	public this()
	{
		InitializeColors();
		InitializeStyles();
	}

	private void InitializeColors()
	{
		// Primary colors (cyan accent)
		SetColor("Primary", .(0, 200, 220));
		SetColor("PrimaryLight", .(80, 230, 245));
		SetColor("PrimaryDark", .(0, 150, 170));

		// Secondary colors (orange accent)
		SetColor("Secondary", .(255, 140, 0));
		SetColor("SecondaryLight", .(255, 180, 80));
		SetColor("SecondaryDark", .(200, 100, 0));

		// Background colors (very dark with slight blue tint)
		SetColor("Background", .(15, 18, 25));
		SetColor("BackgroundAlt", .(25, 30, 40));
		SetColor("BackgroundDark", .(8, 10, 15));

		// Foreground colors
		SetColor("Foreground", .(220, 230, 240));
		SetColor("ForegroundSecondary", .(140, 160, 180));
		SetColor("ForegroundDisabled", .(80, 90, 100));

		// Border colors (cyan tinted)
		SetColor("Border", .(40, 60, 80));
		SetColor("BorderLight", .(60, 90, 110));
		SetColor("BorderDark", .(25, 35, 50));
		SetColor("BorderFocused", .(0, 200, 220));

		// State colors
		SetColor("Hover", .(35, 45, 60));
		SetColor("Pressed", .(45, 60, 80));
		SetColor("Selected", .(0, 120, 140));
		SetColor("Disabled", .(20, 25, 35));

		// Accent colors (vivid game-style)
		SetColor("Success", .(0, 255, 128));
		SetColor("Warning", .(255, 200, 0));
		SetColor("Error", .(255, 60, 80));
		SetColor("Info", .(0, 200, 220));
	}

	private void InitializeStyles()
	{
		// Styles for specific controls can be added here
	}
}

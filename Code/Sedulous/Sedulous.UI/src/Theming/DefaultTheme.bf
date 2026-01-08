using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// The default light theme for the UI framework.
public class DefaultTheme : Theme
{
	public this()
	{
		InitializeColors();
		InitializeStyles();
	}

	private void InitializeColors()
	{
		// Primary colors
		SetColor("Primary", .(0, 120, 215));
		SetColor("PrimaryLight", .(51, 153, 255));
		SetColor("PrimaryDark", .(0, 84, 153));

		// Secondary colors
		SetColor("Secondary", .(104, 118, 138));
		SetColor("SecondaryLight", .(147, 157, 170));
		SetColor("SecondaryDark", .(73, 83, 97));

		// Background colors
		SetColor("Background", Color.White);
		SetColor("BackgroundAlt", .(243, 243, 243));
		SetColor("BackgroundDark", .(230, 230, 230));

		// Foreground colors
		SetColor("Foreground", Color.Black);
		SetColor("ForegroundSecondary", .(102, 102, 102));
		SetColor("ForegroundDisabled", .(160, 160, 160));

		// Border colors
		SetColor("Border", .(204, 204, 204));
		SetColor("BorderLight", .(229, 229, 229));
		SetColor("BorderDark", .(171, 171, 171));
		SetColor("BorderFocused", .(0, 120, 215));

		// State colors
		SetColor("Hover", .(229, 241, 251));
		SetColor("Pressed", .(204, 228, 247));
		SetColor("Selected", .(204, 228, 247));
		SetColor("Disabled", .(243, 243, 243));

		// Accent colors
		SetColor("Success", .(16, 124, 16));
		SetColor("Warning", .(255, 185, 0));
		SetColor("Error", .(232, 17, 35));
		SetColor("Info", .(0, 120, 215));
	}

	private void InitializeStyles()
	{
		// Styles for specific controls will be added as controls are implemented
		// in Stage 5. For now, we just set up the infrastructure.
	}
}

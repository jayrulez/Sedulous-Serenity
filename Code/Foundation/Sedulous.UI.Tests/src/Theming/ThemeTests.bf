using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class ThemeTests
{
	//==========================================================================
	// Color get/set
	//==========================================================================

	[Test]
	public static void SetColor_GetColor_ReturnsSet()
	{
		let theme = scope Theme();
		let c = Color(255, 0, 0, 255);
		theme.SetColor("Button", "background", c);

		let result = theme.GetColor("Button", "background");
		Test.Assert(result.HasValue);
		Test.Assert(result.Value.R == 255);
		Test.Assert(result.Value.G == 0);
	}

	[Test]
	public static void GetColor_Unset_ReturnsNull()
	{
		let theme = scope Theme();
		let result = theme.GetColor("Button", "background");
		Test.Assert(!result.HasValue);
	}

	[Test]
	public static void SetColor_Overwrite_ReturnsNew()
	{
		let theme = scope Theme();
		theme.SetColor("Button", "background", .(255, 0, 0, 255));
		theme.SetColor("Button", "background", .(0, 255, 0, 255));

		let result = theme.GetColor("Button", "background");
		Test.Assert(result.HasValue);
		Test.Assert(result.Value.G == 255);
		Test.Assert(result.Value.R == 0);
	}

	//==========================================================================
	// Dimension get/set
	//==========================================================================

	[Test]
	public static void SetDimension_GetDimension_ReturnsSet()
	{
		let theme = scope Theme();
		theme.SetDimension("Button", "cornerRadius", 8);

		let result = theme.GetDimension("Button", "cornerRadius");
		Test.Assert(result.HasValue);
		Test.Assert(result.Value == 8);
	}

	[Test]
	public static void GetDimension_Unset_ReturnsNull()
	{
		let theme = scope Theme();
		let result = theme.GetDimension("Button", "cornerRadius");
		Test.Assert(!result.HasValue);
	}

	//==========================================================================
	// Named colors
	//==========================================================================

	[Test]
	public static void SetNamedColor_GetNamedColor_ReturnsSet()
	{
		let theme = scope Theme();
		theme.SetNamedColor("danger", .(255, 0, 0, 255));

		let result = theme.GetNamedColor("danger");
		Test.Assert(result.HasValue);
		Test.Assert(result.Value.R == 255);
	}

	[Test]
	public static void GetNamedColor_Unset_ReturnsNull()
	{
		let theme = scope Theme();
		Test.Assert(!theme.GetNamedColor("danger").HasValue);
	}

	//==========================================================================
	// Named dimensions
	//==========================================================================

	[Test]
	public static void SetNamedDimension_GetNamedDimension_ReturnsSet()
	{
		let theme = scope Theme();
		theme.SetNamedDimension("spacing", 16);

		let result = theme.GetNamedDimension("spacing");
		Test.Assert(result.HasValue);
		Test.Assert(result.Value == 16);
	}

	//==========================================================================
	// DarkTheme / LightTheme factories
	//==========================================================================

	[Test]
	public static void DarkTheme_Create_HasName()
	{
		let theme = DarkTheme.Create();
		defer delete theme;
		Test.Assert(theme.Name != null);
		Test.Assert(StringView(theme.Name) == "Dark");
	}

	[Test]
	public static void LightTheme_Create_HasName()
	{
		let theme = LightTheme.Create();
		defer delete theme;
		Test.Assert(theme.Name != null);
		Test.Assert(StringView(theme.Name) == "Light");
	}

	[Test]
	public static void DarkTheme_HasButtonBackground()
	{
		let theme = DarkTheme.Create();
		defer delete theme;
		let bg = theme.GetColor("Button", "background");
		Test.Assert(bg.HasValue);
		Test.Assert(bg.Value.A == 255);
	}

	[Test]
	public static void LightTheme_HasButtonBackground()
	{
		let theme = LightTheme.Create();
		defer delete theme;
		let bg = theme.GetColor("Button", "background");
		Test.Assert(bg.HasValue);
		Test.Assert(bg.Value.A == 255);
	}

	[Test]
	public static void DarkTheme_HasFocusBorderColor()
	{
		let theme = DarkTheme.Create();
		defer delete theme;
		let fc = theme.GetColor("Focus", "borderColor");
		Test.Assert(fc.HasValue);
	}

	[Test]
	public static void DarkTheme_Palette_IsDark()
	{
		let theme = DarkTheme.Create();
		defer delete theme;
		// Dark theme text should be light
		Test.Assert(theme.Palette.Text.R > 200);
	}

	[Test]
	public static void LightTheme_Palette_IsLight()
	{
		let theme = LightTheme.Create();
		defer delete theme;
		// Light theme text should be dark
		Test.Assert(theme.Palette.Text.R < 50);
	}

	//==========================================================================
	// Default palette
	//==========================================================================

	[Test]
	public static void Theme_DefaultPalette_IsDark()
	{
		let theme = scope Theme();
		Test.Assert(theme.Palette.Text.R > 200);
	}
}

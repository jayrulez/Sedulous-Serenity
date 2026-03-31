using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class PaletteTests
{
	//==========================================================================
	// Lighten
	//==========================================================================

	[Test]
	public static void Lighten_Zero_ReturnsOriginal()
	{
		let c = Color(100, 50, 25, 255);
		let result = Palette.Lighten(c, 0);
		Test.Assert(result.R == c.R);
		Test.Assert(result.G == c.G);
		Test.Assert(result.B == c.B);
	}

	[Test]
	public static void Lighten_One_ReturnsWhite()
	{
		let c = Color(100, 50, 25, 255);
		let result = Palette.Lighten(c, 1.0f);
		Test.Assert(result.R == 255);
		Test.Assert(result.G == 255);
		Test.Assert(result.B == 255);
	}

	[Test]
	public static void Lighten_Half_Midpoint()
	{
		let c = Color(100, 0, 0, 255);
		let result = Palette.Lighten(c, 0.5f);
		// Midpoint between 100 and 255 ≈ 177-178
		Test.Assert(result.R > 170 && result.R < 185);
		Test.Assert(result.G > 120 && result.G < 135);
	}

	[Test]
	public static void Lighten_PreservesAlpha()
	{
		let c = Color(100, 50, 25, 128);
		let result = Palette.Lighten(c, 0.5f);
		Test.Assert(result.A == 128);
	}

	//==========================================================================
	// Darken
	//==========================================================================

	[Test]
	public static void Darken_Zero_ReturnsOriginal()
	{
		let c = Color(100, 50, 25, 255);
		let result = Palette.Darken(c, 0);
		Test.Assert(result.R == c.R);
		Test.Assert(result.G == c.G);
		Test.Assert(result.B == c.B);
	}

	[Test]
	public static void Darken_One_ReturnsBlack()
	{
		let c = Color(100, 50, 25, 255);
		let result = Palette.Darken(c, 1.0f);
		Test.Assert(result.R == 0);
		Test.Assert(result.G == 0);
		Test.Assert(result.B == 0);
	}

	[Test]
	public static void Darken_PreservesAlpha()
	{
		let c = Color(100, 50, 25, 200);
		let result = Palette.Darken(c, 0.5f);
		Test.Assert(result.A == 200);
	}

	//==========================================================================
	// Desaturate
	//==========================================================================

	[Test]
	public static void Desaturate_Zero_ReturnsOriginal()
	{
		let c = Color(200, 100, 50, 255);
		let result = Palette.Desaturate(c, 0);
		Test.Assert(result.R == c.R);
		Test.Assert(result.G == c.G);
		Test.Assert(result.B == c.B);
	}

	[Test]
	public static void Desaturate_One_ReturnsGray()
	{
		let c = Color(200, 100, 50, 255);
		let result = Palette.Desaturate(c, 1.0f);
		// All channels should be equal (grayscale)
		let diff = Math.Abs((int32)result.R - (int32)result.G);
		Test.Assert(diff <= 1); // Allow rounding error
	}

	//==========================================================================
	// WithAlpha
	//==========================================================================

	[Test]
	public static void WithAlpha_ChangesAlpha()
	{
		let c = Color(100, 50, 25, 255);
		let result = Palette.WithAlpha(c, 128);
		Test.Assert(result.R == 100);
		Test.Assert(result.G == 50);
		Test.Assert(result.B == 25);
		Test.Assert(result.A == 128);
	}

	//==========================================================================
	// State derivation
	//==========================================================================

	[Test]
	public static void ComputeHover_Lightens()
	{
		let c = Color(100, 100, 100, 255);
		let result = Palette.ComputeHover(c);
		Test.Assert(result.R > c.R);
		Test.Assert(result.G > c.G);
		Test.Assert(result.B > c.B);
	}

	[Test]
	public static void ComputePressed_Darkens()
	{
		let c = Color(100, 100, 100, 255);
		let result = Palette.ComputePressed(c);
		Test.Assert(result.R < c.R);
		Test.Assert(result.G < c.G);
		Test.Assert(result.B < c.B);
	}

	[Test]
	public static void ComputeDisabled_HalvesAlpha()
	{
		let c = Color(100, 100, 100, 200);
		let result = Palette.ComputeDisabled(c);
		Test.Assert(result.A == 100);
	}

	[Test]
	public static void ComputeFocused_BlendsTowardAccent()
	{
		let c = Color(100, 100, 100, 255);
		let accent = Color(0, 0, 255, 255);
		let result = Palette.ComputeFocused(c, accent);
		// Blue should increase, since accent is pure blue
		Test.Assert(result.B > c.B);
	}

	//==========================================================================
	// ResolveState
	//==========================================================================

	[Test]
	public static void ResolveState_Normal_ReturnsBase()
	{
		let c = Color(100, 100, 100, 255);
		let accent = Color(0, 0, 255, 255);
		let result = Palette.ResolveState(c, .Normal, accent);
		Test.Assert(result.R == c.R);
		Test.Assert(result.G == c.G);
		Test.Assert(result.B == c.B);
	}

	[Test]
	public static void ResolveState_Hover_Lightens()
	{
		let c = Color(100, 100, 100, 255);
		let accent = Color(0, 0, 255, 255);
		let result = Palette.ResolveState(c, .Hover, accent);
		Test.Assert(result.R > c.R);
	}

	[Test]
	public static void ResolveState_Pressed_Darkens()
	{
		let c = Color(100, 100, 100, 255);
		let accent = Color(0, 0, 255, 255);
		let result = Palette.ResolveState(c, .Pressed, accent);
		Test.Assert(result.R < c.R);
	}

	[Test]
	public static void ResolveState_Disabled_HalvesAlpha()
	{
		let c = Color(100, 100, 100, 200);
		let accent = Color(0, 0, 255, 255);
		let result = Palette.ResolveState(c, .Disabled, accent);
		Test.Assert(result.A == 100);
	}

	//==========================================================================
	// Predefined palettes
	//==========================================================================

	[Test]
	public static void DarkPalette_HasNonZeroColors()
	{
		let p = Palette.Dark;
		Test.Assert(p.Primary.A == 255);
		Test.Assert(p.Accent.A == 255);
		Test.Assert(p.Text.A == 255);
		Test.Assert(p.Background.A == 255);
	}

	[Test]
	public static void LightPalette_HasNonZeroColors()
	{
		let p = Palette.Light;
		Test.Assert(p.Primary.A == 255);
		Test.Assert(p.Accent.A == 255);
		Test.Assert(p.Text.A == 255);
		Test.Assert(p.Background.A == 255);
	}

	[Test]
	public static void DarkPalette_TextIsLight()
	{
		let p = Palette.Dark;
		Test.Assert(p.Text.R > 200);
	}

	[Test]
	public static void LightPalette_TextIsDark()
	{
		let p = Palette.Light;
		Test.Assert(p.Text.R < 50);
	}
}

using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class PaletteWarningSuccessTests
{
	[Test]
	public static void DarkPalette_WarningHasFullAlpha()
	{
		let p = Palette.Dark;
		Test.Assert(p.Warning.A == 255);
	}

	[Test]
	public static void DarkPalette_SuccessHasFullAlpha()
	{
		let p = Palette.Dark;
		Test.Assert(p.Success.A == 255);
	}

	[Test]
	public static void LightPalette_WarningHasFullAlpha()
	{
		let p = Palette.Light;
		Test.Assert(p.Warning.A == 255);
	}

	[Test]
	public static void LightPalette_SuccessHasFullAlpha()
	{
		let p = Palette.Light;
		Test.Assert(p.Success.A == 255);
	}

	[Test]
	public static void DarkPalette_WarningIsAmberish()
	{
		let p = Palette.Dark;
		// Warning should be warm (R high, G medium, B low)
		Test.Assert(p.Warning.R > 200);
		Test.Assert(p.Warning.G > 100);
		Test.Assert(p.Warning.B < 50);
	}

	[Test]
	public static void DarkPalette_SuccessIsGreenish()
	{
		let p = Palette.Dark;
		// Success should have G > R and G > B
		Test.Assert(p.Success.G > p.Success.R);
		Test.Assert(p.Success.G > p.Success.B);
	}

	[Test]
	public static void WarningDiffersFromError()
	{
		let p = Palette.Dark;
		// Warning and Error should not be the same
		Test.Assert(p.Warning.R != p.Error.R || p.Warning.G != p.Error.G || p.Warning.B != p.Error.B);
	}

	[Test]
	public static void SuccessDiffersFromAccent()
	{
		let p = Palette.Dark;
		Test.Assert(p.Success.R != p.Accent.R || p.Success.G != p.Accent.G || p.Success.B != p.Accent.B);
	}
}

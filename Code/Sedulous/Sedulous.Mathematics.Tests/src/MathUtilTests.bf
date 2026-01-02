using System;

namespace Sedulous.Mathematics.Tests;

class MathUtilTests
{
	[Test]
	public static void TestConstants()
	{
		Test.Assert(MathUtil.Approximately(MathUtil.Pi, 3.14159265f, 1e-5f));
		Test.Assert(MathUtil.Approximately(MathUtil.TwoPi, MathUtil.Pi * 2.0f));
		Test.Assert(MathUtil.Approximately(MathUtil.PiOver2, MathUtil.Pi / 2.0f));
		Test.Assert(MathUtil.Approximately(MathUtil.PiOver4, MathUtil.Pi / 4.0f));
	}

	[Test]
	public static void TestToRadians()
	{
		Test.Assert(MathUtil.Approximately(MathUtil.ToRadians(0.0f), 0.0f));
		Test.Assert(MathUtil.Approximately(MathUtil.ToRadians(90.0f), MathUtil.PiOver2));
		Test.Assert(MathUtil.Approximately(MathUtil.ToRadians(180.0f), MathUtil.Pi));
		Test.Assert(MathUtil.Approximately(MathUtil.ToRadians(360.0f), MathUtil.TwoPi));
	}

	[Test]
	public static void TestToDegrees()
	{
		Test.Assert(MathUtil.Approximately(MathUtil.ToDegrees(0.0f), 0.0f));
		Test.Assert(MathUtil.Approximately(MathUtil.ToDegrees(MathUtil.PiOver2), 90.0f));
		Test.Assert(MathUtil.Approximately(MathUtil.ToDegrees(MathUtil.Pi), 180.0f));
		Test.Assert(MathUtil.Approximately(MathUtil.ToDegrees(MathUtil.TwoPi), 360.0f));
	}

	[Test]
	public static void TestClamp()
	{
		Test.Assert(MathUtil.Clamp(5.0f, 0.0f, 10.0f) == 5.0f);
		Test.Assert(MathUtil.Clamp(-5.0f, 0.0f, 10.0f) == 0.0f);
		Test.Assert(MathUtil.Clamp(15.0f, 0.0f, 10.0f) == 10.0f);
	}

	[Test]
	public static void TestClamp01()
	{
		Test.Assert(MathUtil.Clamp01(0.5f) == 0.5f);
		Test.Assert(MathUtil.Clamp01(-0.5f) == 0.0f);
		Test.Assert(MathUtil.Clamp01(1.5f) == 1.0f);
	}

	[Test]
	public static void TestLerp()
	{
		Test.Assert(MathUtil.Lerp(0.0f, 10.0f, 0.0f) == 0.0f);
		Test.Assert(MathUtil.Lerp(0.0f, 10.0f, 1.0f) == 10.0f);
		Test.Assert(MathUtil.Lerp(0.0f, 10.0f, 0.5f) == 5.0f);
		Test.Assert(MathUtil.Lerp(10.0f, 20.0f, 0.25f) == 12.5f);
	}

	[Test]
	public static void TestApproximately()
	{
		Test.Assert(MathUtil.Approximately(1.0f, 1.0f));
		Test.Assert(MathUtil.Approximately(1.0f, 1.0000001f));
		Test.Assert(!MathUtil.Approximately(1.0f, 1.001f));
		Test.Assert(MathUtil.Approximately(1.0f, 1.1f, 0.2f));
	}

	[Test]
	public static void TestMinMax()
	{
		Test.Assert(MathUtil.Min(3.0f, 5.0f) == 3.0f);
		Test.Assert(MathUtil.Min(5.0f, 3.0f) == 3.0f);
		Test.Assert(MathUtil.Max(3.0f, 5.0f) == 5.0f);
		Test.Assert(MathUtil.Max(5.0f, 3.0f) == 5.0f);
	}

	[Test]
	public static void TestSign()
	{
		Test.Assert(MathUtil.Sign(5.0f) == 1.0f);
		Test.Assert(MathUtil.Sign(-5.0f) == -1.0f);
		Test.Assert(MathUtil.Sign(0.0f) == 0.0f);
	}

	[Test]
	public static void TestWrapAngle()
	{
		// Already in range
		Test.Assert(MathUtil.Approximately(MathUtil.WrapAngle(0.0f), 0.0f));
		Test.Assert(MathUtil.Approximately(MathUtil.WrapAngle(MathUtil.PiOver2), MathUtil.PiOver2));

		// Wrap from positive
		Test.Assert(MathUtil.Approximately(MathUtil.WrapAngle(MathUtil.TwoPi), 0.0f));
		Test.Assert(MathUtil.Approximately(MathUtil.WrapAngle(MathUtil.Pi + MathUtil.TwoPi), MathUtil.Pi));

		// Wrap from negative
		Test.Assert(MathUtil.Approximately(MathUtil.WrapAngle(-MathUtil.TwoPi), 0.0f));
	}

	[Test]
	public static void TestDegreesRadiansRoundTrip()
	{
		float[] testDegrees = scope float[] (0, 45, 90, 180, 270, 360);
		for (let deg in testDegrees)
		{
			let rad = MathUtil.ToRadians(deg);
			let backToDeg = MathUtil.ToDegrees(rad);
			Test.Assert(MathUtil.Approximately(deg, backToDeg));
		}
	}
}

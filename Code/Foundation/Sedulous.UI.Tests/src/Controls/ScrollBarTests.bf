using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class ScrollBarTests
{
	[Test]
	public static void ScrollBar_DefaultValues()
	{
		let sb = scope ScrollBar();
		Test.Assert(sb.Min == 0);
		Test.Assert(sb.Max == 100);
		Test.Assert(sb.Value == 0);
		Test.Assert(sb.ViewportSize == 0);
		Test.Assert(sb.Orientation == .Vertical);
	}

	[Test]
	public static void ScrollBar_ValueClamped()
	{
		let sb = scope ScrollBar();
		sb.Max = 200;
		sb.ViewportSize = 50;
		// MaxScrollValue = 200 - 50 = 150
		sb.Value = 999;
		Test.Assert(sb.Value == 150);

		sb.Value = -10;
		Test.Assert(sb.Value == 0);
	}

	[Test]
	public static void ScrollBar_IsNeeded()
	{
		let sb = scope ScrollBar();
		sb.Max = 100;
		sb.ViewportSize = 50;
		Test.Assert(sb.IsNeeded); // 100 > 50

		sb.ViewportSize = 150;
		Test.Assert(!sb.IsNeeded); // 100 < 150
	}

	[Test]
	public static void ScrollBar_ThumbProportionalSize()
	{
		let sb = scope ScrollBar();
		sb.Max = 100;
		sb.ViewportSize = 50;
		sb.Measure(MeasureSpec.MakeExactly(12), MeasureSpec.MakeExactly(200));
		sb.Layout(0, 0, 12, 200);

		let (_, thumbLen) = sb.GetThumbGeometry();
		// Thumb should be ~50% of 200 = 100
		Test.Assert(thumbLen >= 95 && thumbLen <= 105);
	}

	[Test]
	public static void ScrollBar_ThumbMinimumSize()
	{
		let sb = scope ScrollBar();
		sb.Max = 10000;
		sb.ViewportSize = 10;
		sb.Measure(MeasureSpec.MakeExactly(12), MeasureSpec.MakeExactly(200));
		sb.Layout(0, 0, 12, 200);

		let (_, thumbLen) = sb.GetThumbGeometry();
		// Should be minimum size (20)
		Test.Assert(thumbLen == 20);
	}

	[Test]
	public static void ScrollBar_Range()
	{
		let sb = scope ScrollBar();
		sb.Min = 10;
		sb.Max = 100;
		Test.Assert(sb.Range == 90);
	}

	[Test]
	public static void ScrollBar_MaxScrollValue()
	{
		let sb = scope ScrollBar();
		sb.Max = 100;
		sb.ViewportSize = 30;
		Test.Assert(sb.MaxScrollValue == 70);
	}

	[Test]
	public static void ScrollBar_EffectiveLargeChange()
	{
		let sb = scope ScrollBar();
		sb.ViewportSize = 100;
		// LargeChange = 0 (auto) → 90% of viewport
		Test.Assert(sb.EffectiveLargeChange == 90);

		sb.LargeChange = 50;
		Test.Assert(sb.EffectiveLargeChange == 50);
	}

	[Test]
	public static void ScrollBar_HorizontalOrientation()
	{
		let sb = scope ScrollBar(.Horizontal);
		Test.Assert(sb.Orientation == .Horizontal);
	}
}

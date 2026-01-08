using System;

namespace Sedulous.UI.Tests;

class ThicknessTests
{
	[Test]
	public static void UniformThickness()
	{
		let t = Thickness(10);
		Test.Assert(t.Left == 10);
		Test.Assert(t.Top == 10);
		Test.Assert(t.Right == 10);
		Test.Assert(t.Bottom == 10);
		Test.Assert(t.IsUniform);
	}

	[Test]
	public static void HorizontalVerticalThickness()
	{
		let t = Thickness(20, 10);
		Test.Assert(t.Left == 20);
		Test.Assert(t.Right == 20);
		Test.Assert(t.Top == 10);
		Test.Assert(t.Bottom == 10);
	}

	[Test]
	public static void IndividualThickness()
	{
		let t = Thickness(1, 2, 3, 4);
		Test.Assert(t.Left == 1);
		Test.Assert(t.Top == 2);
		Test.Assert(t.Right == 3);
		Test.Assert(t.Bottom == 4);
		Test.Assert(!t.IsUniform);
	}

	[Test]
	public static void ZeroThickness()
	{
		let t = Thickness.Zero;
		Test.Assert(t.IsZero);
		Test.Assert(t.TotalHorizontal == 0);
		Test.Assert(t.TotalVertical == 0);
	}

	[Test]
	public static void TotalHorizontalAndVertical()
	{
		let t = Thickness(10, 20, 30, 40);
		Test.Assert(t.TotalHorizontal == 40); // 10 + 30
		Test.Assert(t.TotalVertical == 60);   // 20 + 40
	}

	[Test]
	public static void ThicknessAddition()
	{
		let a = Thickness(1, 2, 3, 4);
		let b = Thickness(10, 20, 30, 40);
		let c = a + b;
		Test.Assert(c.Left == 11);
		Test.Assert(c.Top == 22);
		Test.Assert(c.Right == 33);
		Test.Assert(c.Bottom == 44);
	}

	[Test]
	public static void ThicknessSubtraction()
	{
		let a = Thickness(10, 20, 30, 40);
		let b = Thickness(1, 2, 3, 4);
		let c = a - b;
		Test.Assert(c.Left == 9);
		Test.Assert(c.Top == 18);
		Test.Assert(c.Right == 27);
		Test.Assert(c.Bottom == 36);
	}

	[Test]
	public static void ThicknessMultiplication()
	{
		let t = Thickness(2, 4, 6, 8) * 0.5f;
		Test.Assert(t.Left == 1);
		Test.Assert(t.Top == 2);
		Test.Assert(t.Right == 3);
		Test.Assert(t.Bottom == 4);
	}

	[Test]
	public static void ThicknessEquality()
	{
		let a = Thickness(1, 2, 3, 4);
		let b = Thickness(1, 2, 3, 4);
		let c = Thickness(1, 2, 3, 5);
		Test.Assert(a == b);
		Test.Assert(a != c);
	}
}

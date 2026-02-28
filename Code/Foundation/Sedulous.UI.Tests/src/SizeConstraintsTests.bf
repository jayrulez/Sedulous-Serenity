using System;

namespace Sedulous.UI.Tests;

class SizeConstraintsTests
{
	[Test]
	public static void DefaultConstraintsAreUnconstrained()
	{
		let c = SizeConstraints();
		Test.Assert(c.MinWidth == 0);
		Test.Assert(c.MinHeight == 0);
		Test.Assert(c.HasUnboundedWidth);
		Test.Assert(c.HasUnboundedHeight);
	}

	[Test]
	public static void ExactConstraints()
	{
		let c = SizeConstraints.Exact(100, 50);
		Test.Assert(c.MinWidth == 100);
		Test.Assert(c.MinHeight == 50);
		Test.Assert(c.MaxWidth == 100);
		Test.Assert(c.MaxHeight == 50);
	}

	[Test]
	public static void ConstrainWidthClampsToRange()
	{
		let c = SizeConstraints(50, 0, 150, 1000);

		Test.Assert(c.ConstrainWidth(30) == 50);   // Below min
		Test.Assert(c.ConstrainWidth(100) == 100); // Within range
		Test.Assert(c.ConstrainWidth(200) == 150); // Above max
	}

	[Test]
	public static void ConstrainHeightClampsToRange()
	{
		let c = SizeConstraints(0, 25, 1000, 75);

		Test.Assert(c.ConstrainHeight(10) == 25);  // Below min
		Test.Assert(c.ConstrainHeight(50) == 50);  // Within range
		Test.Assert(c.ConstrainHeight(100) == 75); // Above max
	}

	[Test]
	public static void ConstrainDesiredSize()
	{
		let c = SizeConstraints(50, 25, 150, 75);
		let size = DesiredSize(200, 10);
		let constrained = c.Constrain(size);

		Test.Assert(constrained.Width == 150);  // Clamped to max
		Test.Assert(constrained.Height == 25);  // Clamped to min
	}

	[Test]
	public static void DeflateReducesByThickness()
	{
		let c = SizeConstraints(100, 80, 200, 160);
		let t = Thickness(10, 20, 10, 20); // Total: 20 horizontal, 40 vertical
		let deflated = c.Deflate(t);

		Test.Assert(deflated.MinWidth == 80);   // 100 - 20
		Test.Assert(deflated.MinHeight == 40);  // 80 - 40
		Test.Assert(deflated.MaxWidth == 180);  // 200 - 20
		Test.Assert(deflated.MaxHeight == 120); // 160 - 40
	}

	[Test]
	public static void DeflateDoesNotGoBelowZero()
	{
		let c = SizeConstraints(10, 10, 50, 50);
		let t = Thickness(30); // Total: 60 horizontal, 60 vertical
		let deflated = c.Deflate(t);

		Test.Assert(deflated.MinWidth == 0);
		Test.Assert(deflated.MinHeight == 0);
		Test.Assert(deflated.MaxWidth == 0);
		Test.Assert(deflated.MaxHeight == 0);
	}

	[Test]
	public static void FromMaximum()
	{
		let c = SizeConstraints.FromMaximum(800, 600);
		Test.Assert(c.MinWidth == 0);
		Test.Assert(c.MinHeight == 0);
		Test.Assert(c.MaxWidth == 800);
		Test.Assert(c.MaxHeight == 600);
	}
}

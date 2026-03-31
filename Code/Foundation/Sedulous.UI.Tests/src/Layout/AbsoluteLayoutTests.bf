using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class AbsoluteLayoutTests
{
	[Test]
	public static void Layout_PositionsAtXY()
	{
		let layout = scope AbsoluteLayout();
		let child = new TestView(80, 40);
		let lp = new AbsoluteLayout.LayoutParams(50, 30, 80, 40);
		layout.AddView(child, lp);

		layout.Measure(.MakeAtMost(400), .MakeAtMost(400));
		layout.Layout(0, 0, 400, 400);

		Test.Assert(child.Left == 50);
		Test.Assert(child.Top == 30);
		Test.Assert(child.Width == 80);
		Test.Assert(child.Height == 40);
	}

	[Test]
	public static void Measure_BoundingBox()
	{
		let layout = scope AbsoluteLayout();

		let a = new TestView(100, 50);
		let lpA = new AbsoluteLayout.LayoutParams(10, 10, 100, 50);
		layout.AddView(a, lpA);

		let b = new TestView(80, 80);
		let lpB = new AbsoluteLayout.LayoutParams(200, 100, 80, 80);
		layout.AddView(b, lpB);

		layout.Measure(.MakeAtMost(500), .MakeAtMost(500));

		// Bounding box: max(10+100, 200+80) = 280, max(10+50, 100+80) = 180
		Test.Assert(layout.MeasuredWidth == 280);
		Test.Assert(layout.MeasuredHeight == 180);
	}

	[Test]
	public static void Layout_DefaultXY_IsZero()
	{
		let layout = scope AbsoluteLayout();
		let child = new TestView(50, 50);
		// Plain LayoutParams, not AbsoluteLayout.LayoutParams
		let lp = new LayoutParams(50, 50);
		layout.AddView(child, lp);

		layout.Measure(.MakeAtMost(400), .MakeAtMost(400));
		layout.Layout(0, 0, 400, 400);

		Test.Assert(child.Left == 0);
		Test.Assert(child.Top == 0);
	}

	[Test]
	public static void Layout_WithPadding()
	{
		let layout = scope AbsoluteLayout();
		layout.Padding = .(10, 20, 10, 20);
		let child = new TestView(50, 50);
		let lp = new AbsoluteLayout.LayoutParams(30, 40, 50, 50);
		layout.AddView(child, lp);

		layout.Measure(.MakeAtMost(400), .MakeAtMost(400));
		layout.Layout(0, 0, 400, 400);

		// Position = padding + X/Y
		Test.Assert(child.Left == 40);  // 10 + 30
		Test.Assert(child.Top == 60);   // 20 + 40
	}

	[Test]
	public static void Layout_GoneChild_Skipped()
	{
		let layout = scope AbsoluteLayout();
		let child = new TestView(100, 100);
		child.Visibility = .Gone;
		let lp = new AbsoluteLayout.LayoutParams(0, 0, 100, 100);
		layout.AddView(child, lp);

		layout.Measure(.MakeAtMost(400), .MakeAtMost(400));

		// Gone child shouldn't contribute to bounding box
		Test.Assert(layout.MeasuredWidth == 0);
		Test.Assert(layout.MeasuredHeight == 0);
	}
}

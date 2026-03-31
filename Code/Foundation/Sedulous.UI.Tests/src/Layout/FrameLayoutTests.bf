using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class FrameLayoutTests
{
	[Test]
	public static void Measure_SingleChild_WrapContent()
	{
		let frame = scope FrameLayout();
		let child = new TestView(80, 40);
		frame.AddView(child);

		frame.Measure(.MakeAtMost(400), .MakeAtMost(400));
		Test.Assert(frame.MeasuredWidth == 80);
		Test.Assert(frame.MeasuredHeight == 40);
	}

	[Test]
	public static void Measure_MultipleChildren_TakesMax()
	{
		let frame = scope FrameLayout();
		frame.AddView(new TestView(80, 40));
		frame.AddView(new TestView(120, 30));
		frame.AddView(new TestView(60, 70));

		frame.Measure(.MakeAtMost(400), .MakeAtMost(400));
		Test.Assert(frame.MeasuredWidth == 120);
		Test.Assert(frame.MeasuredHeight == 70);
	}

	[Test]
	public static void Measure_WithPadding()
	{
		let frame = scope FrameLayout();
		frame.Padding = .(10, 20, 10, 20);
		frame.AddView(new TestView(80, 40));

		frame.Measure(.MakeAtMost(400), .MakeAtMost(400));
		Test.Assert(frame.MeasuredWidth == 100); // 80 + 10 + 10
		Test.Assert(frame.MeasuredHeight == 80); // 40 + 20 + 20
	}

	[Test]
	public static void Layout_DefaultGravity_TopLeft()
	{
		let frame = scope FrameLayout();
		frame.Padding = .(5, 5, 5, 5);
		let child = new TestView(50, 30);
		frame.AddView(child);

		frame.Measure(.MakeExactly(200), .MakeExactly(200));
		frame.Layout(0, 0, 200, 200);

		Test.Assert(child.Left == 5);
		Test.Assert(child.Top == 5);
		Test.Assert(child.Width == 50);
		Test.Assert(child.Height == 30);
	}

	[Test]
	public static void Layout_Center_CentersChild()
	{
		let frame = scope FrameLayout();
		let child = new TestView(50, 50);
		let lp = new FrameLayout.LayoutParams(50, 50, .Center);
		frame.AddView(child, lp);

		frame.Measure(.MakeExactly(200), .MakeExactly(200));
		frame.Layout(0, 0, 200, 200);

		Test.Assert(child.Left == 75);
		Test.Assert(child.Top == 75);
	}

	[Test]
	public static void Layout_BottomRight_PositionsCorrectly()
	{
		let frame = scope FrameLayout();
		let child = new TestView(50, 50);
		let lp = new FrameLayout.LayoutParams(50, 50, .BottomRight);
		frame.AddView(child, lp);

		frame.Measure(.MakeExactly(200), .MakeExactly(200));
		frame.Layout(0, 0, 200, 200);

		Test.Assert(child.Left == 150);
		Test.Assert(child.Top == 150);
	}

	[Test]
	public static void Layout_FillH_ExpandsChildWidth()
	{
		let frame = scope FrameLayout();
		frame.Padding = .(10, 10, 10, 10);
		let child = new TestView(50, 50);
		let lp = new FrameLayout.LayoutParams(50, 50, .FillH);
		frame.AddView(child, lp);

		frame.Measure(.MakeExactly(200), .MakeExactly(200));
		frame.Layout(0, 0, 200, 200);

		// Content area = 200 - 20 = 180, FillH => width = 180
		Test.Assert(child.Width == 180);
		Test.Assert(child.Left == 10);
		Test.Assert(child.Height == 50); // Vertical unchanged
	}

	[Test]
	public static void Layout_BackwardCompatible_PlainLayoutParams()
	{
		let frame = scope FrameLayout();
		let child = new TestView(50, 50);
		let lp = new LayoutParams(50, 50);
		lp.Margin = .(10, 20, 0, 0);
		frame.AddView(child, lp);

		frame.Measure(.MakeExactly(200), .MakeExactly(200));
		frame.Layout(0, 0, 200, 200);

		// Plain LayoutParams → gravity None → TopLeft with margin
		Test.Assert(child.Left == 10);
		Test.Assert(child.Top == 20);
	}

	[Test]
	public static void Layout_GoneChild_Skipped()
	{
		let frame = scope FrameLayout();
		let child = new TestView(50, 50);
		child.Visibility = .Gone;
		frame.AddView(child);
		let visible = new TestView(30, 30);
		frame.AddView(visible);

		frame.Measure(.MakeAtMost(400), .MakeAtMost(400));
		// Gone child should not contribute to measured size
		Test.Assert(frame.MeasuredWidth == 30);
		Test.Assert(frame.MeasuredHeight == 30);
	}
}

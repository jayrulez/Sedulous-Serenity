using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class FlowLayoutTests
{
	//==========================================================================
	// Horizontal — single line
	//==========================================================================

	[Test]
	public static void Measure_Horizontal_SingleLine_SumsWidths()
	{
		let layout = scope FlowLayout();
		layout.HSpacing = 0;
		layout.VSpacing = 0;
		layout.AddView(new TestView(30, 20));
		layout.AddView(new TestView(40, 20));
		layout.AddView(new TestView(50, 20));

		layout.Measure(.MakeAtMost(200), .MakeAtMost(200));
		Test.Assert(layout.MeasuredWidth == 120); // 30+40+50
		Test.Assert(layout.MeasuredHeight == 20);
	}

	[Test]
	public static void Measure_Horizontal_SingleLine_WithSpacing()
	{
		let layout = scope FlowLayout();
		layout.HSpacing = 5;
		layout.VSpacing = 0;
		layout.AddView(new TestView(30, 20));
		layout.AddView(new TestView(40, 20));

		layout.Measure(.MakeAtMost(200), .MakeAtMost(200));
		Test.Assert(layout.MeasuredWidth == 75); // 30+5+40
		Test.Assert(layout.MeasuredHeight == 20);
	}

	//==========================================================================
	// Horizontal — wrapping
	//==========================================================================

	[Test]
	public static void Measure_Horizontal_Wraps_WhenExceedsWidth()
	{
		let layout = scope FlowLayout();
		layout.HSpacing = 0;
		layout.VSpacing = 0;
		// Each child 60 wide, available 100 → first line gets 60, second line 60+60 wraps
		layout.AddView(new TestView(60, 20));
		layout.AddView(new TestView(60, 20));
		layout.AddView(new TestView(60, 20));

		layout.Measure(.MakeAtMost(100), .MakeAtMost(300));
		// Line 1: 60, Line 2: 60, Line 3: 60
		Test.Assert(layout.MeasuredWidth == 60);
		Test.Assert(layout.MeasuredHeight == 60); // 3 lines * 20
	}

	[Test]
	public static void Measure_Horizontal_Wraps_WithVSpacing()
	{
		let layout = scope FlowLayout();
		layout.HSpacing = 0;
		layout.VSpacing = 10;
		layout.AddView(new TestView(60, 20));
		layout.AddView(new TestView(60, 20));
		layout.AddView(new TestView(60, 20));

		layout.Measure(.MakeAtMost(100), .MakeAtMost(300));
		// 3 lines of 20 with 2 gaps of 10: 20+10+20+10+20 = 80
		Test.Assert(layout.MeasuredHeight == 80);
	}

	[Test]
	public static void Layout_Horizontal_WrappedChildren_Positioned()
	{
		let layout = scope FlowLayout();
		layout.HSpacing = 0;
		layout.VSpacing = 0;
		layout.AddView(new TestView(60, 20));
		layout.AddView(new TestView(60, 20));

		layout.Measure(.MakeAtMost(80), .MakeAtMost(300));
		layout.Layout(0, 0, 80, layout.MeasuredHeight);

		let c0 = layout.GetChildAt(0);
		let c1 = layout.GetChildAt(1);
		// First child at (0,0), second wraps to (0,20)
		Test.Assert(c0.Left == 0 && c0.Top == 0);
		Test.Assert(c1.Left == 0 && c1.Top == 20);
	}

	//==========================================================================
	// Horizontal — with padding
	//==========================================================================

	[Test]
	public static void Measure_Horizontal_WithPadding()
	{
		let layout = scope FlowLayout();
		layout.HSpacing = 0;
		layout.VSpacing = 0;
		layout.Padding = .(10, 5, 10, 5);
		layout.AddView(new TestView(50, 20));

		layout.Measure(.MakeAtMost(200), .MakeAtMost(200));
		Test.Assert(layout.MeasuredWidth == 70); // 50 + 10 + 10
		Test.Assert(layout.MeasuredHeight == 30); // 20 + 5 + 5
	}

	//==========================================================================
	// Empty and single child
	//==========================================================================

	[Test]
	public static void Measure_Empty_ZeroSize()
	{
		let layout = scope FlowLayout();
		layout.Measure(.MakeAtMost(200), .MakeAtMost(200));
		Test.Assert(layout.MeasuredWidth == 0);
		Test.Assert(layout.MeasuredHeight == 0);
	}

	[Test]
	public static void Measure_SingleChild()
	{
		let layout = scope FlowLayout();
		layout.HSpacing = 10;
		layout.VSpacing = 10;
		layout.AddView(new TestView(80, 30));

		layout.Measure(.MakeAtMost(200), .MakeAtMost(200));
		Test.Assert(layout.MeasuredWidth == 80);
		Test.Assert(layout.MeasuredHeight == 30);
	}

	//==========================================================================
	// Visibility.Gone
	//==========================================================================

	[Test]
	public static void Measure_SkipsGoneChildren()
	{
		let layout = scope FlowLayout();
		layout.HSpacing = 0;
		layout.VSpacing = 0;
		let hidden = new TestView(100, 100);
		hidden.Visibility = .Gone;
		layout.AddView(hidden);
		layout.AddView(new TestView(50, 20));

		layout.Measure(.MakeAtMost(200), .MakeAtMost(200));
		Test.Assert(layout.MeasuredWidth == 50);
		Test.Assert(layout.MeasuredHeight == 20);
	}

	//==========================================================================
	// Vertical orientation
	//==========================================================================

	[Test]
	public static void Measure_Vertical_SingleColumn()
	{
		let layout = scope FlowLayout();
		layout.Orientation = .Vertical;
		layout.HSpacing = 0;
		layout.VSpacing = 0;
		layout.AddView(new TestView(30, 40));
		layout.AddView(new TestView(30, 40));
		layout.AddView(new TestView(30, 40));

		layout.Measure(.MakeAtMost(200), .MakeAtMost(200));
		Test.Assert(layout.MeasuredWidth == 30);
		Test.Assert(layout.MeasuredHeight == 120); // 3*40
	}

	[Test]
	public static void Measure_Vertical_Wraps_WhenExceedsHeight()
	{
		let layout = scope FlowLayout();
		layout.Orientation = .Vertical;
		layout.HSpacing = 0;
		layout.VSpacing = 0;
		layout.AddView(new TestView(30, 60));
		layout.AddView(new TestView(30, 60));
		layout.AddView(new TestView(30, 60));

		layout.Measure(.MakeAtMost(200), .MakeAtMost(100));
		// Col 1: 60, Col 2: 60, Col 3: 60 → 3 columns of width 30
		Test.Assert(layout.MeasuredWidth == 90); // 3*30
		Test.Assert(layout.MeasuredHeight == 60);
	}
}

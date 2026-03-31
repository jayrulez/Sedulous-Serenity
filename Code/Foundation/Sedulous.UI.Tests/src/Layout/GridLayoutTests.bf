using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class GridLayoutTests
{
	[Test]
	public static void AutoAssign_2Columns_Sequential()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 2;

		let a = new TestView(50, 50);
		let b = new TestView(50, 50);
		let c = new TestView(50, 50);
		let d = new TestView(50, 50);
		grid.AddView(a);
		grid.AddView(b);
		grid.AddView(c);
		grid.AddView(d);

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));
		grid.Layout(0, 0, 400, 400);

		// Row 0: a(0,0), b(0,1)
		// Row 1: c(1,0), d(1,1)
		Test.Assert(a.Left == 0);
		Test.Assert(a.Top == 0);
		Test.Assert(b.Left == 50);
		Test.Assert(b.Top == 0);
		Test.Assert(c.Left == 0);
		Test.Assert(c.Top == 50);
		Test.Assert(d.Left == 50);
		Test.Assert(d.Top == 50);
	}

	[Test]
	public static void Layout_WithSpacing()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 2;
		grid.ColumnSpacing = 10;
		grid.RowSpacing = 5;

		let a = new TestView(50, 30);
		let b = new TestView(50, 30);
		let c = new TestView(50, 30);
		grid.AddView(a);
		grid.AddView(b);
		grid.AddView(c);

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));
		grid.Layout(0, 0, 400, 400);

		// Row 0: a at (0,0), b at (50+10=60, 0)
		// Row 1: c at (0, 30+5=35)
		Test.Assert(a.Left == 0);
		Test.Assert(a.Top == 0);
		Test.Assert(b.Left == 60);
		Test.Assert(b.Top == 0);
		Test.Assert(c.Left == 0);
		Test.Assert(c.Top == 35);
	}

	[Test]
	public static void Measure_EqualColumns_CorrectSize()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 2;
		grid.ColumnSpacing = 10;

		grid.AddView(new TestView(100, 40));
		grid.AddView(new TestView(80, 60));

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));

		// Column 0: width 100, Column 1: width 80
		// Total width: 100 + 10 + 80 = 190
		// Max row height: max(40, 60) = 60
		Test.Assert(grid.MeasuredWidth == 190);
		Test.Assert(grid.MeasuredHeight == 60);
	}

	[Test]
	public static void Layout_ColumnSpan()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 3;
		grid.ColumnSpacing = 10;

		// First child spans 2 columns
		let wide = new TestView(50, 30);
		let lpWide = new GridLayout.LayoutParams(50, 30);
		lpWide.ColumnSpan = 2;
		grid.AddView(wide, lpWide);

		let normal = new TestView(50, 30);
		grid.AddView(normal);

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));
		grid.Layout(0, 0, 400, 400);

		// wide spans col 0+1, normal at col 2
		// wide gets width of col0 + spacing + col1
		Test.Assert(wide.Left == 0);
		Test.Assert(wide.Width >= 50); // At least its measured width
	}

	[Test]
	public static void Layout_RowSpan()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 2;
		grid.RowSpacing = 5;

		// First child spans 2 rows
		let tall = new TestView(50, 30);
		let lpTall = new GridLayout.LayoutParams(50, 30);
		lpTall.RowSpan = 2;
		grid.AddView(tall, lpTall);

		let b = new TestView(50, 30);
		grid.AddView(b);
		let c = new TestView(50, 30);
		grid.AddView(c);

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));
		grid.Layout(0, 0, 400, 400);

		// tall at (0,0) spanning rows 0-1
		// b at (col 1, row 0)
		// c at (col 1, row 1) — since col 0 is occupied by tall's row span
		Test.Assert(tall.Left == 0);
		Test.Assert(tall.Top == 0);
		Test.Assert(b.Left == 50);
		Test.Assert(b.Top == 0);
	}

	[Test]
	public static void Layout_ExplicitPosition()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 3;

		let a = new TestView(50, 50);
		let lpA = new GridLayout.LayoutParams(50, 50);
		lpA.Row = 2;
		lpA.Column = 1;
		grid.AddView(a, lpA);

		let b = new TestView(50, 50);
		grid.AddView(b);

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));
		grid.Layout(0, 0, 400, 400);

		// a is explicitly at row 2, col 1
		// b auto-assigned to row 0, col 0
		Test.Assert(a.Top > b.Top); // a is in a later row
	}

	[Test]
	public static void Layout_GravityInCell()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 1;

		// Large cell, small child centered
		let big = new TestView(100, 100);
		grid.AddView(big);
		let small = new TestView(30, 30);
		let lpSmall = new GridLayout.LayoutParams(30, 30);
		lpSmall.Gravity = .Center;
		grid.AddView(small, lpSmall);

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));
		grid.Layout(0, 0, 400, 400);

		// small is in row 1, cell height = 30, cell width = 100 (max col width)
		// With .Center gravity, horizontally centered in 100-wide cell: (100-30)/2 = 35
		Test.Assert(small.Left == 35);
	}

	[Test]
	public static void Measure_Empty()
	{
		let grid = scope GridLayout();
		grid.Padding = .(5, 10, 5, 10);

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));
		Test.Assert(grid.MeasuredWidth == 10);  // padding only
		Test.Assert(grid.MeasuredHeight == 20);
	}

	[Test]
	public static void Layout_WithPadding()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 1;
		grid.Padding = .(10, 20, 10, 20);

		let child = new TestView(50, 30);
		grid.AddView(child);

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));
		grid.Layout(0, 0, 400, 400);

		Test.Assert(child.Left == 10);
		Test.Assert(child.Top == 20);
	}

	[Test]
	public static void AutoAssign_WithColumnSpan_SkipsCells()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 3;

		// Child 0 spans 2 columns
		let a = new TestView(50, 30);
		let lpA = new GridLayout.LayoutParams(50, 30);
		lpA.ColumnSpan = 2;
		grid.AddView(a, lpA);

		// Child 1 should go to col 2 (since 0-1 are taken)
		let b = new TestView(50, 30);
		grid.AddView(b);

		// Child 2 should go to next row
		let c = new TestView(50, 30);
		grid.AddView(c);

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));
		grid.Layout(0, 0, 400, 400);

		// a at row 0, col 0 (span 2)
		// b at row 0, col 2
		// c at row 1, col 0
		Test.Assert(a.Top == 0);
		Test.Assert(b.Top == 0);
		Test.Assert(c.Top > 0); // Next row
		Test.Assert(b.Left > a.Left); // b is to the right
	}
}

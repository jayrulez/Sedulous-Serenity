using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class GridLayoutStarTests
{
	//==========================================================================
	// Backward compatibility — no specs
	//==========================================================================

	[Test]
	public static void NoSpecs_BehavesLikeOriginal()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 2;
		grid.AddView(new TestView(60, 30));
		grid.AddView(new TestView(40, 30));

		grid.Measure(.MakeAtMost(400), .MakeAtMost(400));
		// Without specs, columns sized to content: max(60,40)=60 per col? No — col0=60, col1=40
		Test.Assert(grid.MeasuredWidth == 100); // 60 + 40
		Test.Assert(grid.MeasuredHeight == 30);
	}

	//==========================================================================
	// Fixed columns
	//==========================================================================

	[Test]
	public static void FixedColumns_UsesSpecifiedWidth()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 2;
		grid.SetColumnSpecs(.Pixels(80), .Pixels(120));
		grid.AddView(new TestView(30, 30));
		grid.AddView(new TestView(30, 30));

		grid.Measure(.MakeExactly(200), .MakeAtMost(400));
		Test.Assert(grid.MeasuredWidth == 200);

		grid.Layout(0, 0, 200, grid.MeasuredHeight);
		let c0 = grid.GetChildAt(0);
		let c1 = grid.GetChildAt(1);
		// First child in 80px column, second in 120px column
		Test.Assert(c0.Left == 0);
		Test.Assert(c1.Left == 80);
	}

	//==========================================================================
	// Proportional columns
	//==========================================================================

	[Test]
	public static void ProportionalColumns_DistributeSpace()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 2;
		grid.SetColumnSpecs(.Star(1), .Star(1));
		grid.AddView(new TestView(10, 30));
		grid.AddView(new TestView(10, 30));

		grid.Measure(.MakeExactly(200), .MakeAtMost(400));
		grid.Layout(0, 0, 200, grid.MeasuredHeight);

		let c0 = grid.GetChildAt(0);
		let c1 = grid.GetChildAt(1);
		// Each gets 100px
		Test.Assert(c0.Left == 0);
		Test.Assert(c1.Left == 100);
	}

	[Test]
	public static void ProportionalColumns_WeightedDistribution()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 2;
		grid.SetColumnSpecs(.Star(1), .Star(3));
		grid.AddView(new TestView(10, 30));
		grid.AddView(new TestView(10, 30));

		grid.Measure(.MakeExactly(200), .MakeAtMost(400));
		grid.Layout(0, 0, 200, grid.MeasuredHeight);

		let c0 = grid.GetChildAt(0);
		let c1 = grid.GetChildAt(1);
		// 1:3 ratio of 200 → 50 and 150
		Test.Assert(c0.Left == 0);
		Test.Assert(c1.Left == 50);
	}

	//==========================================================================
	// Mixed: Fixed + Proportional
	//==========================================================================

	[Test]
	public static void MixedColumns_FixedAndStar()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 3;
		grid.SetColumnSpecs(.Pixels(50), .Star(1), .Star(1));
		grid.AddView(new TestView(10, 30));
		grid.AddView(new TestView(10, 30));
		grid.AddView(new TestView(10, 30));

		grid.Measure(.MakeExactly(200), .MakeAtMost(400));
		grid.Layout(0, 0, 200, grid.MeasuredHeight);

		let c0 = grid.GetChildAt(0);
		let c1 = grid.GetChildAt(1);
		let c2 = grid.GetChildAt(2);
		// Fixed 50, then 150 split 1:1 → 75 each
		Test.Assert(c0.Left == 0);
		Test.Assert(c1.Left == 50);
		Test.Assert(c2.Left == 125);
	}

	//==========================================================================
	// Auto columns
	//==========================================================================

	[Test]
	public static void AutoColumn_SizesToContent()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 2;
		grid.SetColumnSpecs(.Auto, .Star(1));
		grid.AddView(new TestView(60, 30));
		grid.AddView(new TestView(10, 30));

		grid.Measure(.MakeExactly(200), .MakeAtMost(400));
		grid.Layout(0, 0, 200, grid.MeasuredHeight);

		let c0 = grid.GetChildAt(0);
		let c1 = grid.GetChildAt(1);
		// Auto column = 60 (content), star gets 200-60 = 140
		Test.Assert(c0.Left == 0);
		Test.Assert(c1.Left == 60);
	}

	//==========================================================================
	// Row specs
	//==========================================================================

	[Test]
	public static void ProportionalRows_DistributeSpace()
	{
		let grid = scope GridLayout();
		grid.ColumnCount = 1;
		grid.SetRowSpecs(.Star(1), .Star(1));
		grid.AddView(new TestView(50, 10));
		grid.AddView(new TestView(50, 10));

		grid.Measure(.MakeAtMost(400), .MakeExactly(200));
		grid.Layout(0, 0, grid.MeasuredWidth, 200);

		let c0 = grid.GetChildAt(0);
		let c1 = grid.GetChildAt(1);
		// Each row gets 100px
		Test.Assert(c0.Top == 0);
		Test.Assert(c1.Top == 100);
	}
}

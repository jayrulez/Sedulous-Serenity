using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class LinearLayoutTests
{
	//==========================================================================
	// Vertical orientation — measurement
	//==========================================================================

	[Test]
	public static void Measure_Vertical_FixedChildren_SumsHeights()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;
		layout.AddView(new TestView(60, 40));
		layout.AddView(new TestView(80, 30));
		layout.AddView(new TestView(50, 50));

		layout.Measure(.MakeAtMost(400), .MakeAtMost(400));
		Test.Assert(layout.MeasuredWidth == 80);  // max cross
		Test.Assert(layout.MeasuredHeight == 120); // 40+30+50
	}

	[Test]
	public static void Measure_Vertical_WithSpacing()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;
		layout.Spacing = 10;
		layout.AddView(new TestView(60, 40));
		layout.AddView(new TestView(60, 40));
		layout.AddView(new TestView(60, 40));

		layout.Measure(.MakeAtMost(400), .MakeAtMost(400));
		// 3*40 + 2*10 = 140
		Test.Assert(layout.MeasuredHeight == 140);
	}

	[Test]
	public static void Measure_Vertical_WithPadding()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;
		layout.Padding = .(10, 20, 10, 20);
		layout.AddView(new TestView(60, 40));

		layout.Measure(.MakeAtMost(400), .MakeAtMost(400));
		Test.Assert(layout.MeasuredWidth == 80);  // 60 + 10 + 10
		Test.Assert(layout.MeasuredHeight == 80); // 40 + 20 + 20
	}

	//==========================================================================
	// Vertical orientation — layout positioning
	//==========================================================================

	[Test]
	public static void Layout_Vertical_PositionsSequentially()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;
		let a = new TestView(60, 40);
		let b = new TestView(60, 30);
		layout.AddView(a);
		layout.AddView(b);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		Test.Assert(a.Top == 0);
		Test.Assert(a.Height == 40);
		Test.Assert(b.Top == 40);
		Test.Assert(b.Height == 30);
	}

	[Test]
	public static void Layout_Vertical_WithSpacing()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;
		layout.Spacing = 10;
		let a = new TestView(60, 40);
		let b = new TestView(60, 30);
		layout.AddView(a);
		layout.AddView(b);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		Test.Assert(a.Top == 0);
		Test.Assert(b.Top == 50); // 40 + 10 spacing
	}

	[Test]
	public static void Layout_Vertical_WithMargins()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;
		let a = new TestView(60, 40);
		let lpA = new LinearLayout.LayoutParams(60, 40);
		lpA.Margin = .(0, 5, 0, 5);
		let b = new TestView(60, 30);
		layout.AddView(a, lpA);
		layout.AddView(b);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		Test.Assert(a.Top == 5);  // margin top
		Test.Assert(b.Top == 50); // 5 + 40 + 5 = 50
	}

	//==========================================================================
	// Horizontal orientation
	//==========================================================================

	[Test]
	public static void Measure_Horizontal_FixedChildren_SumsWidths()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Horizontal;
		layout.AddView(new TestView(60, 40));
		layout.AddView(new TestView(80, 30));

		layout.Measure(.MakeAtMost(400), .MakeAtMost(400));
		Test.Assert(layout.MeasuredWidth == 140); // 60+80
		Test.Assert(layout.MeasuredHeight == 40); // max cross
	}

	[Test]
	public static void Layout_Horizontal_PositionsSequentially()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Horizontal;
		layout.Spacing = 10;
		let a = new TestView(60, 40);
		let b = new TestView(80, 30);
		layout.AddView(a);
		layout.AddView(b);

		layout.Measure(.MakeExactly(300), .MakeExactly(200));
		layout.Layout(0, 0, 300, 200);

		Test.Assert(a.Left == 0);
		Test.Assert(a.Width == 60);
		Test.Assert(b.Left == 70); // 60 + 10
		Test.Assert(b.Width == 80);
	}

	//==========================================================================
	// Weight system
	//==========================================================================

	[Test]
	public static void Measure_Vertical_WeightedChildren_EqualDistribution()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;

		let a = new TestView(60, 0);
		let lpA = new LinearLayout.LayoutParams(60, 0, 1);
		let b = new TestView(60, 0);
		let lpB = new LinearLayout.LayoutParams(60, 0, 1);
		layout.AddView(a, lpA);
		layout.AddView(b, lpB);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		// 200 space, 2 children weight 1 each => 100 each
		Test.Assert(a.Height == 100);
		Test.Assert(b.Height == 100);
		Test.Assert(a.Top == 0);
		Test.Assert(b.Top == 100);
	}

	[Test]
	public static void Measure_Vertical_MixedFixedAndWeighted()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;

		let fixedChild = new TestView(60, 60);
		let weightedChild = new TestView(60, 0);
		let lpW = new LinearLayout.LayoutParams(60, 0, 1);
		layout.AddView(fixedChild);
		layout.AddView(weightedChild, lpW);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		// Fixed takes 60, remaining 140 goes to weighted
		Test.Assert(fixedChild.Height == 60);
		Test.Assert(weightedChild.Height == 140);
		Test.Assert(fixedChild.Top == 0);
		Test.Assert(weightedChild.Top == 60);
	}

	[Test]
	public static void Layout_Vertical_Weight_2_1_Distribution()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;

		let a = new TestView(60, 0);
		let lpA = new LinearLayout.LayoutParams(60, 0, 2);
		let b = new TestView(60, 0);
		let lpB = new LinearLayout.LayoutParams(60, 0, 1);
		layout.AddView(a, lpA);
		layout.AddView(b, lpB);

		layout.Measure(.MakeExactly(60), .MakeExactly(300));
		layout.Layout(0, 0, 60, 300);

		// 300 total, weight 2:1 => 200:100
		Test.Assert(a.Height == 200);
		Test.Assert(b.Height == 100);
	}

	//==========================================================================
	// Cross-axis gravity
	//==========================================================================

	[Test]
	public static void Layout_Vertical_CrossAxisCenterH()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;
		layout.Gravity = .CenterH;

		let child = new TestView(60, 40);
		layout.AddView(child);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		// Centered horizontally: (200 - 60) / 2 = 70
		Test.Assert(child.Left == 70);
	}

	[Test]
	public static void Layout_Vertical_PerChildGravity_Overrides()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;
		layout.Gravity = .CenterH;

		let a = new TestView(60, 40);
		let b = new TestView(60, 40);
		let lpB = new LinearLayout.LayoutParams(60, 40);
		lpB.Gravity = .Right;
		layout.AddView(a);
		layout.AddView(b, lpB);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		// a uses parent gravity (CenterH): (200-60)/2 = 70
		Test.Assert(a.Left == 70);
		// b overrides with Right: 200 - 60 = 140
		Test.Assert(b.Left == 140);
	}

	[Test]
	public static void Layout_Vertical_CrossAxisFillH()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;
		layout.Gravity = .FillH;

		let child = new TestView(60, 40);
		layout.AddView(child);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		// FillH => child width expands to container width
		Test.Assert(child.Width == 200);
		Test.Assert(child.Left == 0);
	}

	//==========================================================================
	// Edge cases
	//==========================================================================

	[Test]
	public static void Measure_Empty_JustPadding()
	{
		let layout = scope LinearLayout();
		layout.Padding = .(10, 20, 10, 20);

		layout.Measure(.MakeAtMost(400), .MakeAtMost(400));
		Test.Assert(layout.MeasuredWidth == 20);  // padding only
		Test.Assert(layout.MeasuredHeight == 40);
	}

	[Test]
	public static void Layout_GoneChild_SkippedInCursor()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Vertical;
		layout.Spacing = 10;

		let a = new TestView(60, 40);
		let gone = new TestView(60, 40);
		gone.Visibility = .Gone;
		let b = new TestView(60, 30);
		layout.AddView(a);
		layout.AddView(gone);
		layout.AddView(b);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		// Gone child skipped entirely: a at 0, b at 40+10=50
		Test.Assert(a.Top == 0);
		Test.Assert(b.Top == 50); // Only one spacing between a and b
	}

	//==========================================================================
	// Baseline alignment (horizontal)
	//==========================================================================

	[Test]
	public static void Layout_Horizontal_BaselineAligned_AlignsBaselines()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Horizontal;
		layout.BaselineAligned = true;

		// Small text: height=20, baseline at 15 (ascent)
		let small = new BaselineTestView(40, 20, 15);
		// Large text: height=40, baseline at 30 (ascent)
		let large = new BaselineTestView(60, 40, 30);
		layout.AddView(small);
		layout.AddView(large);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		// Both baselines should align at y=30 (the max baseline)
		// small: top + baseline = top + 15 = 30, so top = 15
		// large: top + baseline = top + 30 = 30, so top = 0
		Test.Assert(small.Top == 15);
		Test.Assert(large.Top == 0);
	}

	[Test]
	public static void Layout_Horizontal_BaselineAligned_MixedWithNoBaseline()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Horizontal;
		layout.BaselineAligned = true;

		// View with baseline
		let text = new BaselineTestView(60, 30, 20);
		// View without baseline (returns -1)
		let icon = new TestView(30, 30);
		layout.AddView(text);
		layout.AddView(icon);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		// text has baseline=20, maxBaseline=20, so text.Top = 0
		Test.Assert(text.Top == 0);
		// icon has no baseline, falls back to gravity (None → top by default)
		Test.Assert(icon.Top == 0);
	}

	[Test]
	public static void Layout_Horizontal_BaselineDisabled_UsesGravity()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Horizontal;
		layout.BaselineAligned = false;
		layout.Gravity = .CenterV;

		let small = new BaselineTestView(40, 20, 15);
		let large = new BaselineTestView(60, 40, 30);
		layout.AddView(small);
		layout.AddView(large);

		layout.Measure(.MakeExactly(200), .MakeExactly(200));
		layout.Layout(0, 0, 200, 200);

		// With BaselineAligned=false, gravity applies instead
		// CenterV: small centered in 200px → (200-20)/2 = 90
		Test.Assert(small.Top == 90);
		// CenterV: large centered in 200px → (200-40)/2 = 80
		Test.Assert(large.Top == 80);
	}

	[Test]
	public static void Measure_Horizontal_BaselineAligned_CrossSizeAccountsForBaseline()
	{
		let layout = scope LinearLayout();
		layout.Orientation = .Horizontal;
		layout.BaselineAligned = true;

		// Small: height=20, baseline=15 → descent from baseline = 5
		let small = new BaselineTestView(40, 20, 15);
		// Large: height=40, baseline=30 → descent from baseline = 10
		let large = new BaselineTestView(60, 40, 30);
		layout.AddView(small);
		layout.AddView(large);

		layout.Measure(.MakeAtMost(400), .MakeAtMost(400));

		// maxBaseline = 30, maxDescent = 10
		// crossSize = 30 + 10 = 40
		Test.Assert(layout.MeasuredHeight == 40);
	}
}

/// Test view that reports a fixed baseline for testing baseline alignment.
class BaselineTestView : View
{
	public float DesiredWidth;
	public float DesiredHeight;
	public float BaselineValue;

	public this(float desiredWidth, float desiredHeight, float baseline)
	{
		DesiredWidth = desiredWidth;
		DesiredHeight = desiredHeight;
		BaselineValue = baseline;
	}

	public override float GetBaseline()
	{
		return BaselineValue;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		SetMeasuredDimension(
			widthSpec.Resolve(DesiredWidth, MinWidth, MaxWidth),
			heightSpec.Resolve(DesiredHeight, MinHeight, MaxHeight)
		);
	}
}

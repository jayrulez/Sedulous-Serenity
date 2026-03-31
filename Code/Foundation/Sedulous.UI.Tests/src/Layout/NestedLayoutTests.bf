using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class NestedLayoutTests
{
	[Test]
	public static void LinearLayout_InsideFrameLayout()
	{
		let frame = scope FrameLayout();
		let linear = new LinearLayout();
		linear.Orientation = .Vertical;
		let a = new TestView(60, 30);
		let b = new TestView(60, 40);
		linear.AddView(a);
		linear.AddView(b);
		frame.AddView(linear);

		frame.Measure(.MakeExactly(200), .MakeExactly(200));
		frame.Layout(0, 0, 200, 200);

		// LinearLayout measures to 60 x 70 (30+40)
		Test.Assert(linear.MeasuredWidth == 60);
		Test.Assert(linear.MeasuredHeight == 70);
		// Children laid out sequentially
		Test.Assert(a.Top == 0);
		Test.Assert(b.Top == 30);
	}

	[Test]
	public static void FrameLayout_InsideLinearLayout()
	{
		let linear = scope LinearLayout();
		linear.Orientation = .Vertical;

		let frame = new FrameLayout();
		let child = new TestView(40, 40);
		let lp = new FrameLayout.LayoutParams(40, 40, .Center);
		frame.AddView(child, lp);

		let lpFrame = new LinearLayout.LayoutParams(100, 100);
		linear.AddView(frame, lpFrame);

		linear.Measure(.MakeExactly(200), .MakeExactly(200));
		linear.Layout(0, 0, 200, 200);

		// Frame is 100x100 (from LayoutParams), child centered inside
		Test.Assert(frame.Width == 100);
		Test.Assert(frame.Height == 100);
		Test.Assert(child.Left == 30); // (100-40)/2
		Test.Assert(child.Top == 30);
	}

	[Test]
	public static void DeepNesting_ThreeLevels()
	{
		let root = scope FrameLayout();
		let middle = new LinearLayout();
		middle.Orientation = .Horizontal;
		middle.Spacing = 10;
		let inner = new FrameLayout();
		let leaf = new TestView(30, 20);
		inner.AddView(leaf);
		middle.AddView(inner);
		middle.AddView(new TestView(50, 40));
		root.AddView(middle);

		root.Measure(.MakeExactly(300), .MakeExactly(300));
		root.Layout(0, 0, 300, 300);

		// middle: horizontal, inner(30x20) + spacing(10) + testview(50x40) = 90 wide, 40 tall
		Test.Assert(middle.MeasuredWidth == 90);
		Test.Assert(middle.MeasuredHeight == 40);
		// leaf inside inner
		Test.Assert(leaf.Width == 30);
		Test.Assert(leaf.Height == 20);
	}
}

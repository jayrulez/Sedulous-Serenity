using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

/// Test element with fixed content size.
class FixedSizeElement : UIElement
{
	public float FixedWidth;
	public float FixedHeight;

	public this(float width, float height)
	{
		FixedWidth = width;
		FixedHeight = height;
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		return .(
			constraints.ConstrainWidth(FixedWidth),
			constraints.ConstrainHeight(FixedHeight)
		);
	}
}

class StackPanelTests
{
	[Test]
	public static void VerticalStackMeasure()
	{
		let stack = scope StackPanel();
		stack.Orientation = .Vertical;
		stack.AddChild(new FixedSizeElement(100, 30));
		stack.AddChild(new FixedSizeElement(80, 40));
		stack.AddChild(new FixedSizeElement(120, 50));

		stack.Measure(.Unconstrained);

		// Width is max of children, height is sum
		Test.Assert(stack.DesiredSize.Width == 120);
		Test.Assert(stack.DesiredSize.Height == 120); // 30+40+50
	}

	[Test]
	public static void VerticalStackWithSpacing()
	{
		let stack = scope StackPanel();
		stack.Orientation = .Vertical;
		stack.Spacing = 10;
		stack.AddChild(new FixedSizeElement(100, 30));
		stack.AddChild(new FixedSizeElement(100, 40));
		stack.AddChild(new FixedSizeElement(100, 50));

		stack.Measure(.Unconstrained);

		// Height includes spacing between children
		Test.Assert(stack.DesiredSize.Height == 140); // 30+10+40+10+50
	}

	[Test]
	public static void HorizontalStackMeasure()
	{
		let stack = scope StackPanel();
		stack.Orientation = .Horizontal;
		stack.AddChild(new FixedSizeElement(30, 100));
		stack.AddChild(new FixedSizeElement(40, 80));
		stack.AddChild(new FixedSizeElement(50, 120));

		stack.Measure(.Unconstrained);

		// Width is sum, height is max
		Test.Assert(stack.DesiredSize.Width == 120); // 30+40+50
		Test.Assert(stack.DesiredSize.Height == 120);
	}

	[Test]
	public static void VerticalStackArrange()
	{
		let stack = scope StackPanel();
		stack.Orientation = .Vertical;
		let child1 = new FixedSizeElement(100, 30);
		let child2 = new FixedSizeElement(100, 40);
		stack.AddChild(child1);
		stack.AddChild(child2);

		stack.Measure(.Unconstrained);
		stack.Arrange(.(0, 0, 200, 200));

		Test.Assert(child1.Bounds.Y == 0);
		Test.Assert(child1.Bounds.Height == 30);
		Test.Assert(child2.Bounds.Y == 30);
		Test.Assert(child2.Bounds.Height == 40);
	}

	[Test]
	public static void CollapsedChildSkipped()
	{
		let stack = scope StackPanel();
		stack.Orientation = .Vertical;
		let child1 = new FixedSizeElement(100, 30);
		let child2 = new FixedSizeElement(100, 40);
		child2.Visibility = .Collapsed;
		let child3 = new FixedSizeElement(100, 50);
		stack.AddChild(child1);
		stack.AddChild(child2);
		stack.AddChild(child3);

		stack.Measure(.Unconstrained);

		// Collapsed child not counted
		Test.Assert(stack.DesiredSize.Height == 80); // 30+50, not 120
	}
}

class DockPanelTests
{
	[Test]
	public static void DockLeft()
	{
		let dock = scope DockPanel();
		let left = new FixedSizeElement(50, 100);
		let fill = new FixedSizeElement(100, 100);
		dock.SetDock(left, .Left);
		dock.AddChild(left);
		dock.AddChild(fill);

		dock.Measure(.Unconstrained);
		dock.Arrange(.(0, 0, 200, 100));

		Test.Assert(left.Bounds.X == 0);
		Test.Assert(left.Bounds.Width == 50);
		Test.Assert(fill.Bounds.X == 50);
		Test.Assert(fill.Bounds.Width == 150); // Fills remaining
	}

	[Test]
	public static void DockTop()
	{
		let dock = scope DockPanel();
		let top = new FixedSizeElement(100, 30);
		let fill = new FixedSizeElement(100, 100);
		dock.SetDock(top, .Top);
		dock.AddChild(top);
		dock.AddChild(fill);

		dock.Measure(.Unconstrained);
		dock.Arrange(.(0, 0, 200, 150));

		Test.Assert(top.Bounds.Y == 0);
		Test.Assert(top.Bounds.Height == 30);
		Test.Assert(fill.Bounds.Y == 30);
		Test.Assert(fill.Bounds.Height == 120);
	}

	[Test]
	public static void DockAllSides()
	{
		let dock = scope DockPanel();
		let left = new FixedSizeElement(20, 50);
		let top = new FixedSizeElement(50, 20);
		let right = new FixedSizeElement(20, 50);
		let bottom = new FixedSizeElement(50, 20);
		let fill = new FixedSizeElement(50, 50);

		dock.SetDock(left, .Left);
		dock.SetDock(top, .Top);
		dock.SetDock(right, .Right);
		dock.SetDock(bottom, .Bottom);

		dock.AddChild(left);
		dock.AddChild(top);
		dock.AddChild(right);
		dock.AddChild(bottom);
		dock.AddChild(fill);

		dock.Measure(.Unconstrained);
		dock.Arrange(.(0, 0, 200, 150));

		// Left gets full height initially
		Test.Assert(left.Bounds.X == 0);
		Test.Assert(left.Bounds.Width == 20);

		// Top gets remaining width after left
		Test.Assert(top.Bounds.X == 20);
		Test.Assert(top.Bounds.Y == 0);

		// Right gets remaining after left and top
		Test.Assert(right.Bounds.X == 180);

		// Bottom gets remaining after left, top, right
		Test.Assert(bottom.Bounds.Y == 130);
	}

	[Test]
	public static void LastChildFillDisabled()
	{
		let dock = scope DockPanel();
		dock.LastChildFill = false;
		let left = new FixedSizeElement(50, 100);
		let center = new FixedSizeElement(30, 30);
		dock.SetDock(left, .Left);
		dock.AddChild(left);
		dock.AddChild(center);

		dock.Measure(.Unconstrained);
		dock.Arrange(.(0, 0, 200, 100));

		// Center should keep its size, not fill
		Test.Assert(center.Bounds.Width == 30);
	}
}

class GridTests
{
	[Test]
	public static void SingleCellGrid()
	{
		let grid = scope Grid();
		let child = new FixedSizeElement(100, 50);
		grid.AddChild(child);

		grid.Measure(.Unconstrained);
		grid.Arrange(.(0, 0, 200, 100));

		// Child fills the grid
		Test.Assert(child.Bounds.Width == 200);
		Test.Assert(child.Bounds.Height == 100);
	}

	[Test]
	public static void FixedRowsAndColumns()
	{
		let grid = scope Grid();
		grid.RowDefinitions.Add(new .() { Height = .Pixel(50) });
		grid.RowDefinitions.Add(new .() { Height = .Pixel(30) });
		grid.ColumnDefinitions.Add(new .() { Width = .Pixel(100) });
		grid.ColumnDefinitions.Add(new .() { Width = .Pixel(80) });

		let child = new FixedSizeElement(50, 30);
		grid.SetRow(child, 0);
		grid.SetColumn(child, 1);
		grid.AddChild(child);

		grid.Measure(.Unconstrained);
		grid.Arrange(.(0, 0, 200, 100));

		// Child should be in second column, first row
		Test.Assert(child.Bounds.X == 100);
		Test.Assert(child.Bounds.Y == 0);
		Test.Assert(child.Bounds.Width == 80);
		Test.Assert(child.Bounds.Height == 50);
	}

	[Test]
	public static void StarSizing()
	{
		let grid = scope Grid();
		grid.ColumnDefinitions.Add(new .() { Width = .StarWeight(1) });
		grid.ColumnDefinitions.Add(new .() { Width = .StarWeight(2) });

		let child1 = new FixedSizeElement(50, 50);
		let child2 = new FixedSizeElement(50, 50);
		grid.SetColumn(child1, 0);
		grid.SetColumn(child2, 1);
		grid.AddChild(child1);
		grid.AddChild(child2);

		grid.Measure(.Unconstrained);
		grid.Arrange(.(0, 0, 300, 100));

		// Column 1 gets 1/3, column 2 gets 2/3
		Test.Assert(child1.Bounds.Width == 100);
		Test.Assert(child2.Bounds.Width == 200);
	}

	[Test]
	public static void RowSpan()
	{
		let grid = scope Grid();
		grid.RowDefinitions.Add(new .() { Height = .Pixel(50) });
		grid.RowDefinitions.Add(new .() { Height = .Pixel(50) });

		let child = new FixedSizeElement(100, 80);
		grid.SetRowSpan(child, 2);
		grid.AddChild(child);

		grid.Measure(.Unconstrained);
		grid.Arrange(.(0, 0, 200, 100));

		// Child spans both rows
		Test.Assert(child.Bounds.Height == 100);
	}
}

class CanvasTests
{
	[Test]
	public static void PositionWithLeftTop()
	{
		let canvas = scope Canvas();
		let child = new FixedSizeElement(50, 30);
		canvas.SetLeft(child, 20);
		canvas.SetTop(child, 10);
		canvas.AddChild(child);

		canvas.Measure(.Unconstrained);
		canvas.Arrange(.(0, 0, 200, 150));

		Test.Assert(child.Bounds.X == 20);
		Test.Assert(child.Bounds.Y == 10);
		Test.Assert(child.Bounds.Width == 50);
		Test.Assert(child.Bounds.Height == 30);
	}

	[Test]
	public static void PositionWithRightBottom()
	{
		let canvas = scope Canvas();
		let child = new FixedSizeElement(50, 30);
		canvas.SetRight(child, 20);
		canvas.SetBottom(child, 10);
		canvas.AddChild(child);

		canvas.Measure(.Unconstrained);
		canvas.Arrange(.(0, 0, 200, 150));

		Test.Assert(child.Bounds.X == 130); // 200 - 20 - 50
		Test.Assert(child.Bounds.Y == 110); // 150 - 10 - 30
	}

	[Test]
	public static void StretchWithLeftRight()
	{
		let canvas = scope Canvas();
		let child = new FixedSizeElement(50, 30);
		canvas.SetLeft(child, 20);
		canvas.SetRight(child, 30);
		canvas.AddChild(child);

		canvas.Measure(.Unconstrained);
		canvas.Arrange(.(0, 0, 200, 150));

		// Should stretch between left and right
		Test.Assert(child.Bounds.X == 20);
		Test.Assert(child.Bounds.Width == 150); // 200 - 20 - 30
	}

	[Test]
	public static void CanvasHasZeroDesiredSize()
	{
		let canvas = scope Canvas();
		canvas.AddChild(new FixedSizeElement(100, 50));

		canvas.Measure(.Unconstrained);

		// Canvas doesn't report child size
		Test.Assert(canvas.DesiredSize.Width == 0);
		Test.Assert(canvas.DesiredSize.Height == 0);
	}
}

class WrapPanelTests
{
	[Test]
	public static void HorizontalWrap()
	{
		let wrap = scope WrapPanel();
		wrap.Orientation = .Horizontal;
		for (int i = 0; i < 5; i++)
			wrap.AddChild(new FixedSizeElement(40, 30));

		wrap.Measure(SizeConstraints.FromMaximum(100, 500));

		// 5 items * 40 = 200, but max width is 100
		// So 2 items per row, 3 rows needed
		// Height = 3 * 30 = 90
		Test.Assert(wrap.DesiredSize.Height == 90);
	}

	[Test]
	public static void WrapWithSpacing()
	{
		let wrap = scope WrapPanel();
		wrap.Orientation = .Horizontal;
		wrap.HorizontalSpacing = 10;
		wrap.VerticalSpacing = 5;
		wrap.AddChild(new FixedSizeElement(40, 30));
		wrap.AddChild(new FixedSizeElement(40, 30));
		wrap.AddChild(new FixedSizeElement(40, 30));

		wrap.Measure(SizeConstraints.FromMaximum(100, 500));
		wrap.Arrange(.(0, 0, 100, 100));

		// First 2 fit on line 1: 40 + 10 + 40 = 90
		// Third goes to line 2
		let child3 = wrap.Children[2];
		Test.Assert(child3.Bounds.Y == 35); // 30 + 5 spacing
	}

	[Test]
	public static void UniformItemSize()
	{
		let wrap = scope WrapPanel();
		wrap.ItemWidth = 50;
		wrap.ItemHeight = 40;
		let child = new FixedSizeElement(30, 20);
		wrap.AddChild(child);

		wrap.Measure(.Unconstrained);
		wrap.Arrange(.(0, 0, 200, 200));

		// Child should be sized to uniform item size
		Test.Assert(child.Bounds.Width == 50);
		Test.Assert(child.Bounds.Height == 40);
	}
}

class ScrollViewerTests
{
	[Test]
	public static void ScrollViewerWithLargeContent()
	{
		let scroll = scope ScrollViewer();
		let content = new FixedSizeElement(500, 400);
		scroll.Content = content;

		scroll.Measure(SizeConstraints.FromMaximum(200, 150));
		scroll.Arrange(.(0, 0, 200, 150));

		Test.Assert(scroll.ExtentSize.X == 500);
		Test.Assert(scroll.ExtentSize.Y == 400);
		Test.Assert(scroll.CanScrollHorizontally);
		Test.Assert(scroll.CanScrollVertically);
	}

	[Test]
	public static void ScrollOffset()
	{
		let scroll = scope ScrollViewer();
		let content = new FixedSizeElement(500, 400);
		scroll.Content = content;

		scroll.Measure(SizeConstraints.FromMaximum(200, 150));
		scroll.Arrange(.(0, 0, 200, 150));

		scroll.ScrollTo(100, 50);

		Test.Assert(scroll.HorizontalOffset == 100);
		Test.Assert(scroll.VerticalOffset == 50);
	}

	[Test]
	public static void ScrollOffsetClamped()
	{
		let scroll = scope ScrollViewer();
		let content = new FixedSizeElement(500, 400);
		scroll.Content = content;

		scroll.Measure(SizeConstraints.FromMaximum(200, 150));
		scroll.Arrange(.(0, 0, 200, 150));

		scroll.ScrollTo(1000, 1000);

		// Should be clamped to max scroll
		let expectedMaxX = 500 - scroll.ViewportSize.X;
		let expectedMaxY = 400 - scroll.ViewportSize.Y;
		Test.Assert(scroll.HorizontalOffset <= expectedMaxX);
		Test.Assert(scroll.VerticalOffset <= expectedMaxY);
	}

	[Test]
	public static void NoScrollWhenContentFits()
	{
		let scroll = scope ScrollViewer();
		let content = new FixedSizeElement(100, 80);
		scroll.Content = content;

		scroll.Measure(SizeConstraints.FromMaximum(200, 150));
		scroll.Arrange(.(0, 0, 200, 150));

		Test.Assert(!scroll.CanScrollHorizontally);
		Test.Assert(!scroll.CanScrollVertically);
	}
}

class PanelTests
{
	class TestPanel : Panel
	{
	}

	[Test]
	public static void PanelBackground()
	{
		let panel = scope TestPanel();
		Test.Assert(panel.Background == null);

		panel.Background = Color.Red;
		Test.Assert(panel.Background.HasValue);
		Test.Assert(panel.Background.Value == Color.Red);
	}
}

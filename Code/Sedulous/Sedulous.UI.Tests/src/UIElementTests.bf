using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

/// Simple concrete element for testing.
/// Extends CompositeControl to support children for hierarchy tests.
class SimpleElement : CompositeControl
{
	public float ContentWidth = 50;
	public float ContentHeight = 30;

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// First measure children (important for containers)
		var childSize = base.MeasureOverride(constraints);

		// Return max of content size and child size, constrained
		return .(
			constraints.ConstrainWidth(Math.Max(ContentWidth, childSize.Width)),
			constraints.ConstrainHeight(Math.Max(ContentHeight, childSize.Height))
		);
	}
}

class UIElementTests
{
	[Test]
	public static void DefaultProperties()
	{
		let element = scope SimpleElement();
		Test.Assert(element.Parent == null);
		Test.Assert(element.Children.Count == 0);
		Test.Assert(element.Visibility == .Visible);
		Test.Assert(element.Opacity == 1.0f);
		Test.Assert(element.IsEnabled);
		Test.Assert(!element.IsFocused);
		Test.Assert(!element.IsMouseOver);
	}

	[Test]
	public static void SetId()
	{
		let element = scope SimpleElement();
		element.Id = "myButton";
		Test.Assert(element.Id == UIElementId("myButton"));
	}

	[Test]
	public static void AddChild()
	{
		let parent = scope SimpleElement();
		let child = new SimpleElement();
		parent.AddChild(child);

		Test.Assert(parent.Children.Count == 1);
		Test.Assert(parent.Children[0] == child);
		Test.Assert(child.Parent == parent);
	}

	[Test]
	public static void AddMultipleChildren()
	{
		let parent = scope SimpleElement();
		let child1 = new SimpleElement();
		let child2 = new SimpleElement();
		let child3 = new SimpleElement();

		parent.AddChild(child1);
		parent.AddChild(child2);
		parent.AddChild(child3);

		Test.Assert(parent.Children.Count == 3);
		Test.Assert(child1.Parent == parent);
		Test.Assert(child2.Parent == parent);
		Test.Assert(child3.Parent == parent);
	}

	[Test]
	public static void InsertChild()
	{
		let parent = scope SimpleElement();
		let child1 = new SimpleElement();
		let child2 = new SimpleElement();
		let child3 = new SimpleElement();

		parent.AddChild(child1);
		parent.AddChild(child3);
		parent.InsertChild(1, child2);

		Test.Assert(parent.Children[0] == child1);
		Test.Assert(parent.Children[1] == child2);
		Test.Assert(parent.Children[2] == child3);
	}

	[Test]
	public static void RemoveChild()
	{
		let parent = scope SimpleElement();
		let child = new SimpleElement();
		parent.AddChild(child);
		Test.Assert(parent.Children.Count == 1);

		let removed = parent.RemoveChild(child);
		Test.Assert(removed);
		Test.Assert(parent.Children.Count == 0);
		Test.Assert(child.Parent == null);

		delete child;
	}

	[Test]
	public static void ReparentChild()
	{
		let parent1 = scope SimpleElement();
		let parent2 = scope SimpleElement();
		let child = new SimpleElement();

		parent1.AddChild(child);
		Test.Assert(parent1.Children.Count == 1);
		Test.Assert(parent2.Children.Count == 0);

		parent2.AddChild(child);
		Test.Assert(parent1.Children.Count == 0);
		Test.Assert(parent2.Children.Count == 1);
		Test.Assert(child.Parent == parent2);
	}

	[Test]
	public static void ClearChildren()
	{
		let parent = scope SimpleElement();
		parent.AddChild(new SimpleElement());
		parent.AddChild(new SimpleElement());
		parent.AddChild(new SimpleElement());

		Test.Assert(parent.Children.Count == 3);
		parent.ClearChildren();
		Test.Assert(parent.Children.Count == 0);
	}

	[Test]
	public static void FindElementById()
	{
		let root = scope SimpleElement();
		root.Id = "root";
		let child1 = new SimpleElement();
		child1.Id = "child1";
		let child2 = new SimpleElement();
		child2.Id = "child2";
		let grandchild = new SimpleElement();
		grandchild.Id = "grandchild";

		root.AddChild(child1);
		root.AddChild(child2);
		child1.AddChild(grandchild);

		Test.Assert(root.FindElementById("root") == root);
		Test.Assert(root.FindElementById("child1") == child1);
		Test.Assert(root.FindElementById("child2") == child2);
		Test.Assert(root.FindElementById("grandchild") == grandchild);
		Test.Assert(root.FindElementById("notFound") == null);
	}

	[Test]
	public static void MeasureWithFixedSize()
	{
		let element = scope SimpleElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(80);

		element.Measure(.Unconstrained);

		Test.Assert(element.DesiredSize.Width == 100);
		Test.Assert(element.DesiredSize.Height == 80);
	}

	[Test]
	public static void MeasureWithAutoSize()
	{
		let element = scope SimpleElement();
		element.ContentWidth = 75;
		element.ContentHeight = 45;
		// Default is Auto sizing

		element.Measure(.Unconstrained);

		Test.Assert(element.DesiredSize.Width == 75);
		Test.Assert(element.DesiredSize.Height == 45);
	}

	[Test]
	public static void MeasureWithMargin()
	{
		let element = scope SimpleElement();
		element.ContentWidth = 50;
		element.ContentHeight = 30;
		element.Margin = .(10);

		element.Measure(.Unconstrained);

		// Desired size should include margin
		Test.Assert(element.DesiredSize.Width == 70); // 50 + 10 + 10
		Test.Assert(element.DesiredSize.Height == 50); // 30 + 10 + 10
	}

	[Test]
	public static void MeasureWithPadding()
	{
		let element = scope SimpleElement();
		element.ContentWidth = 50;
		element.ContentHeight = 30;
		element.Padding = .(5);

		element.Measure(.Unconstrained);

		// Desired size should include padding
		Test.Assert(element.DesiredSize.Width == 60); // 50 + 5 + 5
		Test.Assert(element.DesiredSize.Height == 40); // 30 + 5 + 5
	}

	[Test]
	public static void ArrangeWithStretchAlignment()
	{
		let element = scope SimpleElement();
		element.Width = .Auto;
		element.Height = .Auto;
		element.HorizontalAlignment = .Stretch;
		element.VerticalAlignment = .Stretch;
		element.ContentWidth = 50;
		element.ContentHeight = 30;

		element.Measure(.Unconstrained);
		element.Arrange(.(0, 0, 200, 150));

		// Should stretch to fill available space
		Test.Assert(element.Bounds.Width == 200);
		Test.Assert(element.Bounds.Height == 150);
	}

	[Test]
	public static void ArrangeWithCenterAlignment()
	{
		let element = scope SimpleElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(50);
		element.HorizontalAlignment = .Center;
		element.VerticalAlignment = .Center;

		element.Measure(.Unconstrained);
		element.Arrange(.(0, 0, 200, 100));

		Test.Assert(element.Bounds.X == 50);  // (200-100)/2
		Test.Assert(element.Bounds.Y == 25);  // (100-50)/2
		Test.Assert(element.Bounds.Width == 100);
		Test.Assert(element.Bounds.Height == 50);
	}

	[Test]
	public static void ArrangeWithLeftTopAlignment()
	{
		let element = scope SimpleElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(50);
		element.HorizontalAlignment = .Left;
		element.VerticalAlignment = .Top;

		element.Measure(.Unconstrained);
		element.Arrange(.(10, 20, 200, 100));

		Test.Assert(element.Bounds.X == 10);
		Test.Assert(element.Bounds.Y == 20);
	}

	[Test]
	public static void ArrangeWithRightBottomAlignment()
	{
		let element = scope SimpleElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(50);
		element.HorizontalAlignment = .Right;
		element.VerticalAlignment = .Bottom;

		element.Measure(.Unconstrained);
		element.Arrange(.(0, 0, 200, 100));

		Test.Assert(element.Bounds.X == 100);  // 200-100
		Test.Assert(element.Bounds.Y == 50);   // 100-50
	}

	[Test]
	public static void ContentBoundsExcludesPadding()
	{
		let element = scope SimpleElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(80);
		element.Padding = .(10, 5, 15, 20);

		element.Measure(.Unconstrained);
		element.Arrange(.(0, 0, 100, 80));

		let content = element.ContentBounds;
		Test.Assert(content.X == 10);
		Test.Assert(content.Y == 5);
		Test.Assert(content.Width == 75);  // 100 - 10 - 15
		Test.Assert(content.Height == 55); // 80 - 5 - 20
	}

	[Test]
	public static void CollapsedElementHasZeroSize()
	{
		let element = scope SimpleElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(80);
		element.Visibility = .Collapsed;

		element.Measure(.Unconstrained);

		Test.Assert(element.DesiredSize.Width == 0);
		Test.Assert(element.DesiredSize.Height == 0);
	}

	[Test]
	public static void HiddenElementStillMeasures()
	{
		let element = scope SimpleElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(80);
		element.Visibility = .Hidden;

		element.Measure(.Unconstrained);

		Test.Assert(element.DesiredSize.Width == 100);
		Test.Assert(element.DesiredSize.Height == 80);
	}

	[Test]
	public static void HitTestWithinBounds()
	{
		let element = scope SimpleElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		element.Measure(.Unconstrained);
		element.Arrange(.(50, 50, 100, 100));

		Test.Assert(element.HitTest(75, 75) == element);
		Test.Assert(element.HitTest(50, 50) == element);
		Test.Assert(element.HitTest(149, 149) == element);
	}

	[Test]
	public static void HitTestOutsideBounds()
	{
		let element = scope SimpleElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		element.Measure(.Unconstrained);
		element.Arrange(.(50, 50, 100, 100));

		Test.Assert(element.HitTest(0, 0) == null);
		Test.Assert(element.HitTest(49, 50) == null);
		Test.Assert(element.HitTest(150, 50) == null);
	}

	[Test]
	public static void HitTestReturnsDeepestChild()
	{
		let parent = scope SimpleElement();
		parent.Width = .Fixed(200);
		parent.Height = .Fixed(200);

		let child = new SimpleElement();
		child.Width = .Fixed(50);
		child.Height = .Fixed(50);
		child.HorizontalAlignment = .Left;
		child.VerticalAlignment = .Top;
		parent.AddChild(child);

		parent.Measure(.Unconstrained);
		parent.Arrange(.(0, 0, 200, 200));

		// Hit within child bounds
		let hitChild = parent.HitTest(25, 25);
		Test.Assert(hitChild == child);

		// Hit outside child but within parent
		let hitParent = parent.HitTest(100, 100);
		Test.Assert(hitParent == parent);
	}

	[Test]
	public static void OpacityClamps()
	{
		let element = scope SimpleElement();

		element.Opacity = 1.5f;
		Test.Assert(element.Opacity == 1.0f);

		element.Opacity = -0.5f;
		Test.Assert(element.Opacity == 0.0f);

		element.Opacity = 0.5f;
		Test.Assert(element.Opacity == 0.5f);
	}

	[Test]
	public static void IsEnabledInheritsFromParent()
	{
		let parent = scope SimpleElement();
		let child = new SimpleElement();
		parent.AddChild(child);

		Test.Assert(child.IsEnabled);

		parent.IsEnabled = false;
		Test.Assert(!parent.IsEnabled);
		Test.Assert(!child.IsEnabled);
	}
}

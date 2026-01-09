using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

class SplitterTests
{
	[Test]
	public static void SplitterDefaultProperties()
	{
		let splitter = scope Splitter();
		Test.Assert(splitter.Orientation == .Horizontal);
		Test.Assert(splitter.SplitterThickness == 6);
	}

	[Test]
	public static void SplitterOrientationProperty()
	{
		let splitter = scope Splitter();
		splitter.Orientation = .Vertical;
		Test.Assert(splitter.Orientation == .Vertical);

		splitter.Orientation = .Horizontal;
		Test.Assert(splitter.Orientation == .Horizontal);
	}

	[Test]
	public static void SplitterThicknessProperty()
	{
		let splitter = scope Splitter();
		splitter.SplitterThickness = 8;
		Test.Assert(splitter.SplitterThickness == 8);

		// Should clamp to minimum
		splitter.SplitterThickness = 1;
		Test.Assert(splitter.SplitterThickness >= 2);
	}

	[Test]
	public static void SplitterMeasureHorizontal()
	{
		let splitter = scope Splitter();
		splitter.Orientation = .Horizontal;
		splitter.SplitterThickness = 6;

		splitter.Measure(SizeConstraints.FromMaximum(200, 100));

		Test.Assert(splitter.DesiredSize.Width == 6);
		Test.Assert(splitter.DesiredSize.Height == 100);
	}

	[Test]
	public static void SplitterMeasureVertical()
	{
		let splitter = scope Splitter();
		splitter.Orientation = .Vertical;
		splitter.SplitterThickness = 6;

		splitter.Measure(SizeConstraints.FromMaximum(200, 100));

		Test.Assert(splitter.DesiredSize.Width == 200);
		Test.Assert(splitter.DesiredSize.Height == 6);
	}

	[Test]
	public static void SplitterCursorHorizontal()
	{
		let splitter = scope Splitter();
		splitter.Orientation = .Horizontal;
		Test.Assert(splitter.Cursor == .ResizeEW);
	}

	[Test]
	public static void SplitterCursorVertical()
	{
		let splitter = scope Splitter();
		splitter.Orientation = .Vertical;
		Test.Assert(splitter.Cursor == .ResizeNS);
	}
}

class SplitPanelTests
{
	[Test]
	public static void SplitPanelCanBeCreated()
	{
		let splitPanel = scope SplitPanel();
		Test.Assert(splitPanel != null);
	}

	[Test]
	public static void SplitPanelDefaultOrientation()
	{
		let splitPanel = scope SplitPanel();
		Test.Assert(splitPanel.Orientation == .Horizontal);
	}

	[Test]
	public static void SplitPanelDefaultPanelsNull()
	{
		let splitPanel = scope SplitPanel();
		Test.Assert(splitPanel.Panel1 == null);
		Test.Assert(splitPanel.Panel2 == null);
	}

	[Test]
	public static void SplitPanelDefaultMinSizes()
	{
		let splitPanel = scope SplitPanel();
		Test.Assert(splitPanel.Panel1MinSize == 50);
		Test.Assert(splitPanel.Panel2MinSize == 50);
	}

	[Test]
	public static void SplitPanelSetOrientation()
	{
		let splitPanel = scope SplitPanel();
		splitPanel.Orientation = .Vertical;
		Test.Assert(splitPanel.Orientation == .Vertical);
	}

	[Test]
	public static void SplitPanelSetMinSizes()
	{
		let splitPanel = scope SplitPanel();
		splitPanel.Panel1MinSize = 100;
		splitPanel.Panel2MinSize = 80;
		Test.Assert(splitPanel.Panel1MinSize == 100);
		Test.Assert(splitPanel.Panel2MinSize == 80);
	}
}

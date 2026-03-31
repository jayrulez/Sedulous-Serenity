using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.UI.Toolkit;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class DockManagerTests
{
	//==========================================================================
	// DockManager — Creation & Basic State
	//==========================================================================

	[Test]
	public static void New_HasNoRootNode()
	{
		let dm = scope DockManager();
		Test.Assert(dm.RootNode == null);
	}

	[Test]
	public static void AddPanel_ReturnsPanelWithTitle()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let panel = dm.AddPanel("Props", null);
		Test.Assert(panel != null);
		Test.Assert(panel.Title == "Props");
		dm.DockPanel(panel, .Center); // Dock so DockManager's tree owns it
	}

	[Test]
	public static void AddPanel_ReturnsPanelWithContent()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let content = new FrameLayout();
		let panel = dm.AddPanel("Scene", content);
		Test.Assert(panel.ContentView == content);
		dm.DockPanel(panel, .Center); // Dock so DockManager's tree owns it
	}

	//==========================================================================
	// DockManager — DockPanel (Center)
	//==========================================================================

	[Test]
	public static void DockPanel_Center_CreatesTabGroup()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let panel = dm.AddPanel("Panel1", null);
		dm.DockPanel(panel, .Center);

		Test.Assert(dm.RootNode != null);
		Test.Assert(dm.RootNode is DockTabGroup);

		let tabGroup = dm.RootNode as DockTabGroup;
		Test.Assert(tabGroup.PanelCount == 1);
		Test.Assert(tabGroup.SelectedPanel == panel);
	}

	[Test]
	public static void DockPanel_TwoCenter_SameTabGroup()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let p1 = dm.AddPanel("P1", null);
		let p2 = dm.AddPanel("P2", null);
		dm.DockPanel(p1, .Center);
		dm.DockPanel(p2, .Center);

		Test.Assert(dm.RootNode is DockTabGroup);
		let tabGroup = dm.RootNode as DockTabGroup;
		Test.Assert(tabGroup.PanelCount == 2);
	}

	//==========================================================================
	// DockManager — DockPanel (Split positions)
	//==========================================================================

	[Test]
	public static void DockPanel_Left_CreatesSplit()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let p1 = dm.AddPanel("Center", null);
		let p2 = dm.AddPanel("Left", null);
		dm.DockPanel(p1, .Center);
		dm.DockPanel(p2, .Left);

		// Root should now be a DockSplit with Horizontal orientation
		Test.Assert(dm.RootNode is DockSplit);
		let split = dm.RootNode as DockSplit;
		Test.Assert(split.Orientation == .Horizontal);

		// Left panel is First, center is Second
		Test.Assert(split.First is DockTabGroup);
		Test.Assert(split.Second is DockTabGroup);
		let firstGroup = split.First as DockTabGroup;
		let secondGroup = split.Second as DockTabGroup;
		Test.Assert(firstGroup.SelectedPanel == p2);
		Test.Assert(secondGroup.SelectedPanel == p1);
	}

	[Test]
	public static void DockPanel_Right_PanelIsSecond()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let p1 = dm.AddPanel("Center", null);
		let p2 = dm.AddPanel("Right", null);
		dm.DockPanel(p1, .Center);
		dm.DockPanel(p2, .Right);

		let split = dm.RootNode as DockSplit;
		Test.Assert(split != null);
		Test.Assert(split.Orientation == .Horizontal);
		let secondGroup = split.Second as DockTabGroup;
		Test.Assert(secondGroup != null);
		Test.Assert(secondGroup.SelectedPanel == p2);
	}

	[Test]
	public static void DockPanel_Top_VerticalSplit()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let p1 = dm.AddPanel("Center", null);
		let p2 = dm.AddPanel("Top", null);
		dm.DockPanel(p1, .Center);
		dm.DockPanel(p2, .Top);

		let split = dm.RootNode as DockSplit;
		Test.Assert(split != null);
		Test.Assert(split.Orientation == .Vertical);
		let firstGroup = split.First as DockTabGroup;
		Test.Assert(firstGroup != null);
		Test.Assert(firstGroup.SelectedPanel == p2);
	}

	[Test]
	public static void DockPanel_Bottom_VerticalSplit()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let p1 = dm.AddPanel("Center", null);
		let p2 = dm.AddPanel("Bottom", null);
		dm.DockPanel(p1, .Center);
		dm.DockPanel(p2, .Bottom);

		let split = dm.RootNode as DockSplit;
		Test.Assert(split != null);
		Test.Assert(split.Orientation == .Vertical);
		let secondGroup = split.Second as DockTabGroup;
		Test.Assert(secondGroup != null);
		Test.Assert(secondGroup.SelectedPanel == p2);
	}

	//==========================================================================
	// DockManager — Complex tree (3+ panels)
	//==========================================================================

	[Test]
	public static void DockPanel_ThreePanels_NestedSplits()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let center = dm.AddPanel("Center", null);
		let left = dm.AddPanel("Left", null);
		let bottom = dm.AddPanel("Bottom", null);
		dm.DockPanel(center, .Center);
		dm.DockPanel(left, .Left);
		dm.DockPanel(bottom, .Bottom);

		// Root is a vertical split (Bottom was added last to the root)
		// The structure should be a split containing the left/center split and the bottom
		Test.Assert(dm.RootNode is DockSplit);
	}

	//==========================================================================
	// DockManager — UndockPanel
	//==========================================================================

	[Test]
	public static void UndockPanel_LastPanel_RootBecomesNull()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let panel = dm.AddPanel("Solo", null);
		dm.DockPanel(panel, .Center);
		Test.Assert(dm.RootNode != null);

		dm.UndockPanel(panel);
		TestHelper.UpdateFrame(ctx, rootView); // Process deferred deletions

		// After undocking the only panel, root should be cleaned up
		Test.Assert(dm.RootNode == null);

		// Panel itself should still exist (undock doesn't delete)
		Test.Assert(panel.Title == "Solo");
		delete panel;
	}

	[Test]
	public static void UndockPanel_FromSplit_CollapsesToTabGroup()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let p1 = dm.AddPanel("Center", null);
		let p2 = dm.AddPanel("Left", null);
		dm.DockPanel(p1, .Center);
		dm.DockPanel(p2, .Left);
		Test.Assert(dm.RootNode is DockSplit);

		dm.UndockPanel(p2);
		TestHelper.UpdateFrame(ctx, rootView);

		// After removing one panel from a split, should collapse to single tab group
		Test.Assert(dm.RootNode is DockTabGroup);
		let tabGroup = dm.RootNode as DockTabGroup;
		Test.Assert(tabGroup.PanelCount == 1);
		Test.Assert(tabGroup.SelectedPanel == p1);
		delete p2;
	}

	//==========================================================================
	// DockManager — DockPanelRelativeTo
	//==========================================================================

	[Test]
	public static void DockPanelRelativeTo_SplitsTargetNode()
	{
		let ctx = scope UIContext();
		let dm = new DockManager();
		let rootView = TestHelper.SetupContext(ctx, dm, 800, 600);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let p1 = dm.AddPanel("P1", null);
		let p2 = dm.AddPanel("P2", null);
		let p3 = dm.AddPanel("P3", null);
		dm.DockPanel(p1, .Center);
		dm.DockPanel(p2, .Left);

		// Now dock P3 to the right of P1's tab group
		let centerGroup = (dm.RootNode as DockSplit).Second;
		dm.DockPanelRelativeTo(p3, .Right, centerGroup);

		// Root should still be a split; the second child should now be a split itself
		Test.Assert(dm.RootNode is DockSplit);
	}

	//==========================================================================
	// DockManager — IDropTarget
	//==========================================================================

	[Test]
	public static void CanAcceptDrop_DockPanelFormat_ReturnsMove()
	{
		let dm = scope DockManager();
		let data = scope DockPanelDragData(null);
		Test.Assert(dm.CanAcceptDrop(data, 0, 0) == .Move);
	}

	[Test]
	public static void CanAcceptDrop_UnknownFormat_ReturnsNone()
	{
		let dm = scope DockManager();
		let data = scope DragData("text/plain");
		Test.Assert(dm.CanAcceptDrop(data, 0, 0) == .None);
	}
}

//==========================================================================
// DockSplit Tests
//==========================================================================

class DockSplitTests
{
	[Test]
	public static void New_DefaultsHorizontal()
	{
		let split = scope DockSplit();
		Test.Assert(split.Orientation == .Horizontal);
	}

	[Test]
	public static void New_Vertical()
	{
		let split = scope DockSplit(.Vertical);
		Test.Assert(split.Orientation == .Vertical);
	}

	[Test]
	public static void SplitRatio_DefaultHalf()
	{
		let split = scope DockSplit();
		Test.Assert(split.SplitRatio == 0.5f);
	}

	[Test]
	public static void SplitRatio_ClampsToRange()
	{
		let split = scope DockSplit();
		split.SplitRatio = 0.01f;
		Test.Assert(split.SplitRatio == 0.05f);

		split.SplitRatio = 0.99f;
		Test.Assert(split.SplitRatio == 0.95f);
	}

	[Test]
	public static void SplitRatio_AcceptsValidValues()
	{
		let split = scope DockSplit();
		split.SplitRatio = 0.3f;
		Test.Assert(split.SplitRatio == 0.3f);

		split.SplitRatio = 0.7f;
		Test.Assert(split.SplitRatio == 0.7f);
	}

	[Test]
	public static void DividerSize_MinTwo()
	{
		let split = scope DockSplit();
		split.DividerSize = 1;
		Test.Assert(split.DividerSize == 2);
	}

	[Test]
	public static void MinPaneSize_MinTen()
	{
		let split = scope DockSplit();
		split.MinPaneSize = 5;
		Test.Assert(split.MinPaneSize == 10);
	}

	[Test]
	public static void SetChildren_SetsFirstAndSecond()
	{
		let split = scope DockSplit();
		let a = new ColorView(.Red);
		let b = new ColorView(.Blue);
		split.SetChildren(a, b);

		Test.Assert(split.First == a);
		Test.Assert(split.Second == b);
		Test.Assert(split.ChildCount == 2);
	}

	[Test]
	public static void SetChildren_NullSecond()
	{
		let split = scope DockSplit();
		let a = new ColorView(.Red);
		split.SetChildren(a, null);

		Test.Assert(split.First == a);
		Test.Assert(split.Second == null);
		Test.Assert(split.ChildCount == 1);
	}

	[Test]
	public static void First_NoChildren_ReturnsNull()
	{
		let split = scope DockSplit();
		Test.Assert(split.First == null);
		Test.Assert(split.Second == null);
	}

	[Test]
	public static void SetChildren_ReplacesExisting()
	{
		let split = scope DockSplit();
		let a = new ColorView(.Red);
		let b = new ColorView(.Blue);
		split.SetChildren(a, b);

		let c = new ColorView(.Green);
		let d = new ColorView(.White);
		split.SetChildren(c, d);

		Test.Assert(split.First == c);
		Test.Assert(split.Second == d);
		Test.Assert(split.ChildCount == 2);
	}

	[Test]
	public static void Layout_HorizontalSplit_DividesWidth()
	{
		let split = scope DockSplit(.Horizontal);
		let a = new ColorView(.Red);
		let b = new ColorView(.Blue);
		split.SetChildren(a, b);
		split.SplitRatio = 0.5f;

		split.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(100));
		split.Layout(0, 0, 200, 100);

		// Each side gets (200 - dividerSize) * 0.5
		float available = 200 - split.DividerSize;
		float expected = available * 0.5f;
		Test.Assert(Math.Abs(a.Width - expected) < 1.0f);
		Test.Assert(Math.Abs(b.Width - expected) < 1.0f);
	}

	[Test]
	public static void Layout_VerticalSplit_DividesHeight()
	{
		let split = scope DockSplit(.Vertical);
		let a = new ColorView(.Red);
		let b = new ColorView(.Blue);
		split.SetChildren(a, b);
		split.SplitRatio = 0.5f;

		split.Measure(MeasureSpec.MakeExactly(200), MeasureSpec.MakeExactly(100));
		split.Layout(0, 0, 200, 100);

		float available = 100 - split.DividerSize;
		float expected = available * 0.5f;
		Test.Assert(Math.Abs(a.Height - expected) < 1.0f);
		Test.Assert(Math.Abs(b.Height - expected) < 1.0f);
	}
}

//==========================================================================
// DockTabGroup Tests
//==========================================================================

class DockTabGroupTests
{
	[Test]
	public static void New_EmptyGroup()
	{
		let group = scope DockTabGroup();
		Test.Assert(group.PanelCount == 0);
		Test.Assert(group.SelectedIndex == -1);
		Test.Assert(group.SelectedPanel == null);
	}

	[Test]
	public static void AddPanel_IncreasesCount()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		group.AddPanel(p1);

		Test.Assert(group.PanelCount == 1);
	}

	[Test]
	public static void AddPanel_FirstAutoSelects()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		group.AddPanel(p1);

		Test.Assert(group.SelectedIndex == 0);
		Test.Assert(group.SelectedPanel == p1);
	}

	[Test]
	public static void AddPanel_SecondDoesNotChangeSelection()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		let p2 = new DockablePanel("P2");
		group.AddPanel(p1);
		group.AddPanel(p2);

		Test.Assert(group.SelectedIndex == 0);
		Test.Assert(group.SelectedPanel == p1);
		Test.Assert(group.PanelCount == 2);
	}

	[Test]
	public static void SelectedIndex_SwitchesVisibility()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		let p2 = new DockablePanel("P2");
		group.AddPanel(p1);
		group.AddPanel(p2);

		// First panel visible, second gone
		Test.Assert(p1.Visibility == .Visible);
		Test.Assert(p2.Visibility == .Gone);

		group.SelectedIndex = 1;
		Test.Assert(p1.Visibility == .Gone);
		Test.Assert(p2.Visibility == .Visible);
		Test.Assert(group.SelectedPanel == p2);
	}

	[Test]
	public static void SelectedIndex_RejectsOutOfRange()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		group.AddPanel(p1);

		group.SelectedIndex = 5; // Out of range
		Test.Assert(group.SelectedIndex == 0); // Unchanged
	}

	[Test]
	public static void RemovePanel_ReturnsPanel()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		group.AddPanel(p1);

		let removed = group.RemovePanel(p1);
		Test.Assert(removed == p1);
		Test.Assert(group.PanelCount == 0);
		Test.Assert(group.SelectedIndex == -1);
		delete p1;
	}

	[Test]
	public static void RemovePanel_NotFound_ReturnsNull()
	{
		let group = scope DockTabGroup();
		let p1 = scope DockablePanel("P1");

		let removed = group.RemovePanel(p1);
		Test.Assert(removed == null);
	}

	[Test]
	public static void RemovePanel_AdjustsSelection()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		let p2 = new DockablePanel("P2");
		let p3 = new DockablePanel("P3");
		group.AddPanel(p1);
		group.AddPanel(p2);
		group.AddPanel(p3);

		group.SelectedIndex = 2; // Select P3

		// Remove P1 (before selected) — selection should shift down
		let removed = group.RemovePanel(p1);
		Test.Assert(group.SelectedIndex == 1); // Shifted from 2 to 1
		Test.Assert(group.SelectedPanel == p3); // Still P3
		delete removed;
	}

	[Test]
	public static void RemovePanelAt_ValidIndex()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		let p2 = new DockablePanel("P2");
		group.AddPanel(p1);
		group.AddPanel(p2);

		let removed = group.RemovePanelAt(0);
		Test.Assert(removed == p1);
		Test.Assert(group.PanelCount == 1);
		Test.Assert(group.SelectedPanel == p2);
		delete removed;
	}

	[Test]
	public static void RemovePanelAt_InvalidIndex_ReturnsNull()
	{
		let group = scope DockTabGroup();
		Test.Assert(group.RemovePanelAt(-1) == null);
		Test.Assert(group.RemovePanelAt(0) == null);
	}

	[Test]
	public static void GetPanel_ValidIndex()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		let p2 = new DockablePanel("P2");
		group.AddPanel(p1);
		group.AddPanel(p2);

		Test.Assert(group.GetPanel(0) == p1);
		Test.Assert(group.GetPanel(1) == p2);
	}

	[Test]
	public static void GetPanel_InvalidIndex_ReturnsNull()
	{
		let group = scope DockTabGroup();
		Test.Assert(group.GetPanel(-1) == null);
		Test.Assert(group.GetPanel(0) == null);
	}

	[Test]
	public static void InsertPanel_AtBeginning()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		let p2 = new DockablePanel("P2");
		group.AddPanel(p1);
		group.InsertPanel(0, p2);

		Test.Assert(group.GetPanel(0) == p2);
		Test.Assert(group.GetPanel(1) == p1);
		Test.Assert(group.PanelCount == 2);
	}

	[Test]
	public static void InsertPanel_BeforeSelected_ShiftsSelection()
	{
		let group = scope DockTabGroup();
		let p1 = new DockablePanel("P1");
		let p2 = new DockablePanel("P2");
		group.AddPanel(p1); // auto-selects index 0

		group.InsertPanel(0, p2);

		// Selection should shift from 0 to 1 (still pointing at P1)
		Test.Assert(group.SelectedIndex == 1);
		Test.Assert(group.SelectedPanel == p1);
	}

	[Test]
	public static void TabHeight_MinSixteen()
	{
		let group = scope DockTabGroup();
		group.TabHeight = 10;
		Test.Assert(group.TabHeight == 16);
	}
}

//==========================================================================
// DockablePanel Tests
//==========================================================================

class DockablePanelTests
{
	[Test]
	public static void New_DefaultTitle()
	{
		let panel = scope DockablePanel();
		Test.Assert(panel.Title == "Panel");
	}

	[Test]
	public static void New_WithTitle()
	{
		let panel = scope DockablePanel("Inspector");
		Test.Assert(panel.Title == "Inspector");
	}

	[Test]
	public static void New_WithTitleAndContent()
	{
		let content = new FrameLayout();
		let panel = scope DockablePanel("Scene", content);
		Test.Assert(panel.Title == "Scene");
		Test.Assert(panel.ContentView == content);
	}

	[Test]
	public static void Title_SetGet()
	{
		let panel = scope DockablePanel();
		panel.Title = "NewTitle";
		Test.Assert(panel.Title == "NewTitle");
	}

	[Test]
	public static void Closable_DefaultTrue()
	{
		let panel = scope DockablePanel();
		Test.Assert(panel.Closable == true);
	}

	[Test]
	public static void Closable_SetFalse()
	{
		let panel = scope DockablePanel();
		panel.Closable = false;
		Test.Assert(panel.Closable == false);
	}

	[Test]
	public static void HeaderHeight_MinSixteen()
	{
		let panel = scope DockablePanel();
		panel.HeaderHeight = 10;
		Test.Assert(panel.HeaderHeight == 16);
	}

	[Test]
	public static void SetContent_ReplacesExisting()
	{
		let panel = scope DockablePanel();
		let c1 = new FrameLayout();
		let c2 = new FrameLayout();

		panel.SetContent(c1);
		Test.Assert(panel.ContentView == c1);

		panel.SetContent(c2);
		Test.Assert(panel.ContentView == c2);
	}

	[Test]
	public static void SetContent_Null()
	{
		let panel = scope DockablePanel();
		let c1 = new FrameLayout();
		panel.SetContent(c1);
		panel.SetContent(null);
		Test.Assert(panel.ContentView == null);
	}

	[Test]
	public static void SaveDockPosition_StoresValues()
	{
		let panel = scope DockablePanel();
		let relativeTo = scope ColorView(.Red);

		panel.SaveDockPosition(.Left, relativeTo);
		Test.Assert(panel.mLastDockPosition == .Left);
		Test.Assert(panel.mLastRelativeToId == relativeTo.Id);
	}

	[Test]
	public static void SaveDockPosition_NullRelativeTo()
	{
		let panel = scope DockablePanel();
		panel.SaveDockPosition(.Right, null);
		Test.Assert(panel.mLastDockPosition == .Right);
		Test.Assert(panel.mLastRelativeToId == .Invalid);
	}

	[Test]
	public static void CreateDragData_NullWithoutHeaderClick()
	{
		let panel = scope DockablePanel();
		// No mouse down on header → CreateDragData should return null
		let data = panel.CreateDragData();
		Test.Assert(data == null);
	}
}

//==========================================================================
// FloatingWindow Tests
//==========================================================================

class FloatingWindowTests
{
	[Test]
	public static void New_ContainsPanel()
	{
		let panel = new DockablePanel("Float");
		let fw = scope FloatingWindow(panel);

		Test.Assert(fw.Panel == panel);
		Test.Assert(fw.IsOSWindow == false); // Default
	}

	[Test]
	public static void DetachPanel_ReturnsPanel()
	{
		let panel = new DockablePanel("Float");
		let fw = scope FloatingWindow(panel);

		let detached = fw.DetachPanel();
		Test.Assert(detached == panel);
		Test.Assert(fw.Panel == null);
		delete panel;
	}

	[Test]
	public static void DetachPanel_CalledTwice_ReturnsNull()
	{
		let panel = new DockablePanel("Float");
		let fw = scope FloatingWindow(panel);

		let first = fw.DetachPanel();
		let second = fw.DetachPanel();
		Test.Assert(first == panel);
		Test.Assert(second == null);
		delete panel;
	}

	[Test]
	public static void MinDimensions()
	{
		let panel = new DockablePanel("Float");
		let fw = scope FloatingWindow(panel);
		Test.Assert(fw.MinWidth == 120);
		Test.Assert(fw.MinHeight == 80);
	}
}

//==========================================================================
// DockZoneIndicator Tests
//==========================================================================

class DockZoneIndicatorTests
{
	[Test]
	public static void New_IsNotHitTestVisible()
	{
		let indicator = scope DockZoneIndicator();
		Test.Assert(indicator.IsHitTestVisible == false);
	}

	[Test]
	public static void GetHoveredTarget_NoTargets_ReturnsNull()
	{
		let indicator = scope DockZoneIndicator();
		let result = indicator.GetHoveredTarget(50, 50);
		Test.Assert(!result.HasValue);
	}

	[Test]
	public static void GetHoveredTarget_HitsTarget()
	{
		let indicator = scope DockZoneIndicator();
		let targets = scope List<DockTarget>();
		targets.Add(.(DockPosition.Left, null, .(10, 10, 40, 40)));
		targets.Add(.(DockPosition.Right, null, .(60, 10, 40, 40)));
		indicator.SetTargets(targets);

		let result = indicator.GetHoveredTarget(25, 25);
		Test.Assert(result.HasValue);
		Test.Assert(result.Value.Position == .Left);
	}

	[Test]
	public static void GetHoveredTarget_HitsSecondTarget()
	{
		let indicator = scope DockZoneIndicator();
		let targets = scope List<DockTarget>();
		targets.Add(.(DockPosition.Left, null, .(10, 10, 40, 40)));
		targets.Add(.(DockPosition.Right, null, .(60, 10, 40, 40)));
		indicator.SetTargets(targets);

		let result = indicator.GetHoveredTarget(75, 25);
		Test.Assert(result.HasValue);
		Test.Assert(result.Value.Position == .Right);
	}

	[Test]
	public static void GetHoveredTarget_MissesAll()
	{
		let indicator = scope DockZoneIndicator();
		let targets = scope List<DockTarget>();
		targets.Add(.(DockPosition.Left, null, .(10, 10, 40, 40)));
		indicator.SetTargets(targets);

		let result = indicator.GetHoveredTarget(200, 200);
		Test.Assert(!result.HasValue);
	}

	[Test]
	public static void ClearTargets_ResetsState()
	{
		let indicator = scope DockZoneIndicator();
		let targets = scope List<DockTarget>();
		targets.Add(.(DockPosition.Center, null, .(10, 10, 40, 40)));
		indicator.SetTargets(targets);

		// Hover to set state
		indicator.GetHoveredTarget(25, 25);

		indicator.ClearTargets();
		let result = indicator.GetHoveredTarget(25, 25);
		Test.Assert(!result.HasValue);
	}
}

//==========================================================================
// DockPanelDragData Tests
//==========================================================================

class DockPanelDragDataTests
{
	[Test]
	public static void Format_IsDockPanel()
	{
		let panel = scope DockablePanel("Test");
		let data = scope DockPanelDragData(panel);
		Test.Assert(data.Format == "dock/panel");
	}

	[Test]
	public static void Panel_ReferencesSource()
	{
		let panel = scope DockablePanel("Test");
		let data = scope DockPanelDragData(panel);
		Test.Assert(data.Panel == panel);
	}
}

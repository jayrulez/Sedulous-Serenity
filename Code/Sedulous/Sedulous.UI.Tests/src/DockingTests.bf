using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

class DockZoneTests
{
	[Test]
	public static void DockZoneValues()
	{
		// Verify all enum values are distinct
		Test.Assert(DockZone.None != DockZone.Left);
		Test.Assert(DockZone.Left != DockZone.Right);
		Test.Assert(DockZone.Right != DockZone.Top);
		Test.Assert(DockZone.Top != DockZone.Bottom);
		Test.Assert(DockZone.Bottom != DockZone.Center);
		Test.Assert(DockZone.Center != DockZone.Float);
	}
}

class DockablePanelTests
{
	[Test]
	public static void DockablePanelDefaultProperties()
	{
		let panel = scope DockablePanel();
		Test.Assert(panel.Title == "");
		Test.Assert(panel.PanelContent == null);
		Test.Assert(panel.DockZone == .None);
		Test.Assert(panel.CanClose == true);
		Test.Assert(panel.CanFloat == true);
		Test.Assert(!panel.IsDocked);
		Test.Assert(!panel.IsFloating);
		Test.Assert(panel.TitleBarHeight == 24);
	}

	[Test]
	public static void DockablePanelTitle()
	{
		let panel = scope DockablePanel();
		panel.Title = "Properties";
		Test.Assert(panel.Title == "Properties");
	}

	[Test]
	public static void DockablePanelTitleConstructor()
	{
		let panel = scope DockablePanel("Explorer");
		Test.Assert(panel.Title == "Explorer");
	}

	[Test]
	public static void DockablePanelContent()
	{
		let panel = scope DockablePanel();
		let content = new Border();
		panel.PanelContent = content;

		Test.Assert(panel.PanelContent == content);
		Test.Assert(content.Parent == panel);
	}

	[Test]
	public static void DockablePanelReplaceContent()
	{
		let panel = scope DockablePanel();
		let content1 = new Border();
		let content2 = new Border();

		panel.PanelContent = content1;
		Test.Assert(panel.PanelContent == content1);

		panel.PanelContent = content2;
		Test.Assert(panel.PanelContent == content2);
		Test.Assert(content1.Parent == null);

		delete content1;
	}

	[Test]
	public static void DockablePanelDockZone()
	{
		let panel = scope DockablePanel();

		panel.DockZone = .Left;
		Test.Assert(panel.DockZone == .Left);
		Test.Assert(panel.IsDocked);
		Test.Assert(!panel.IsFloating);

		panel.DockZone = .Float;
		Test.Assert(panel.DockZone == .Float);
		Test.Assert(!panel.IsDocked);
		Test.Assert(panel.IsFloating);

		panel.DockZone = .None;
		Test.Assert(panel.DockZone == .None);
		Test.Assert(!panel.IsDocked);
		Test.Assert(!panel.IsFloating);
	}

	[Test]
	public static void DockablePanelCanClose()
	{
		let panel = scope DockablePanel();
		Test.Assert(panel.CanClose);

		panel.CanClose = false;
		Test.Assert(!panel.CanClose);
	}

	[Test]
	public static void DockablePanelCanFloat()
	{
		let panel = scope DockablePanel();
		Test.Assert(panel.CanFloat);

		panel.CanFloat = false;
		Test.Assert(!panel.CanFloat);
	}

	[Test]
	public static void DockablePanelTitleBarHeight()
	{
		let panel = scope DockablePanel();
		panel.TitleBarHeight = 32;
		Test.Assert(panel.TitleBarHeight == 32);

		// Should clamp to minimum
		panel.TitleBarHeight = 10;
		Test.Assert(panel.TitleBarHeight >= 16);
	}

	[Test]
	public static void DockablePanelFloat()
	{
		let panel = scope DockablePanel();
		panel.DockZone = .Left;
		Test.Assert(panel.IsDocked);

		panel.Float();
		Test.Assert(panel.IsFloating);
		Test.Assert(panel.DockZone == .Float);
	}

	[Test]
	public static void DockablePanelFloatWhenDisabled()
	{
		let panel = scope DockablePanel();
		panel.CanFloat = false;
		panel.DockZone = .Left;

		panel.Float();

		// Should not float when CanFloat is false
		Test.Assert(panel.DockZone == .Left);
		Test.Assert(!panel.IsFloating);
	}

	[Test]
	public static void DockablePanelGetTitleBarBounds()
	{
		let panel = scope DockablePanel();
		panel.TitleBarHeight = 24;
		panel.Measure(SizeConstraints.FromMaximum(200, 300));
		panel.Arrange(.(10, 20, 200, 300));

		let titleBarBounds = panel.GetTitleBarBounds();
		Test.Assert(titleBarBounds.X == 0);
		Test.Assert(titleBarBounds.Y == 0);
		Test.Assert(titleBarBounds.Width == 200);
		Test.Assert(titleBarBounds.Height == 24);
	}

	[Test]
	public static void DockablePanelGetCloseButtonBounds()
	{
		let panel = scope DockablePanel();
		panel.TitleBarHeight = 24;
		panel.CanClose = true;
		panel.Measure(SizeConstraints.FromMaximum(200, 300));
		panel.Arrange(.(10, 20, 200, 300));

		let closeBounds = panel.GetCloseButtonBounds();
		Test.Assert(closeBounds.Width > 0);
		Test.Assert(closeBounds.Height > 0);
	}

	[Test]
	public static void DockablePanelGetCloseButtonBoundsWhenDisabled()
	{
		let panel = scope DockablePanel();
		panel.CanClose = false;

		let closeBounds = panel.GetCloseButtonBounds();
		Test.Assert(closeBounds == RectangleF.Empty);
	}

	[Test]
	public static void DockablePanelMeasure()
	{
		let panel = scope DockablePanel();
		panel.Title = "Test Panel";
		panel.TitleBarHeight = 24;

		let content = new Border();
		content.Width = 150;
		content.Height = 200;
		panel.PanelContent = content;

		panel.Measure(SizeConstraints.FromMaximum(300, 400));

		Test.Assert(panel.DesiredSize.Width > 0);
		Test.Assert(panel.DesiredSize.Height > panel.TitleBarHeight);
	}

	[Test]
	public static void DockablePanelDockedEvent()
	{
		let panel = scope DockablePanel();

		var eventFired = false;
		var zoneReceived = DockZone.None;

		delegate void(DockablePanel, DockZone) handler = new [&](p, z) =>
		{
			eventFired = true;
			zoneReceived = z;
		};
		panel.Docked.Subscribe(handler);

		panel.DockZone = .Left;

		Test.Assert(eventFired);
		Test.Assert(zoneReceived == .Left);

		// Don't delete handler - EventAccessor owns it after Subscribe
	}

	[Test]
	public static void DockablePanelFloatedEvent()
	{
		let panel = scope DockablePanel();
		panel.DockZone = .Left;

		var eventFired = false;

		delegate void(DockablePanel) handler = new [&](p) =>
		{
			eventFired = true;
		};
		panel.Floated.Subscribe(handler);

		panel.Float();

		Test.Assert(eventFired);

		// Don't delete handler - EventAccessor owns it after Subscribe
	}
}

class DockManagerTests
{
	[Test]
	public static void DockManagerDefaultProperties()
	{
		let manager = scope DockManager();
		Test.Assert(manager.CenterContent == null);
		Test.Assert(manager.LeftPanel == null);
		Test.Assert(manager.RightPanel == null);
		Test.Assert(manager.TopPanel == null);
		Test.Assert(manager.BottomPanel == null);
		Test.Assert(manager.LeftWidth == 100);
		Test.Assert(manager.RightWidth == 100);
		Test.Assert(manager.TopHeight == 80);
		Test.Assert(manager.BottomHeight == 80);
	}

	[Test]
	public static void DockManagerSetCenterContent()
	{
		let manager = scope DockManager();
		let content = new Border();

		manager.CenterContent = content;
		Test.Assert(manager.CenterContent == content);
		Test.Assert(content.Parent == manager);
	}

	[Test]
	public static void DockManagerDockLeft()
	{
		let manager = scope DockManager();
		let panel = new DockablePanel("Left Panel");

		manager.Dock(panel, .Left);

		Test.Assert(manager.LeftPanel == panel);
		Test.Assert(panel.DockZone == .Left);
		Test.Assert(panel.IsDocked);
	}

	[Test]
	public static void DockManagerDockRight()
	{
		let manager = scope DockManager();
		let panel = new DockablePanel("Right Panel");

		manager.Dock(panel, .Right);

		Test.Assert(manager.RightPanel == panel);
		Test.Assert(panel.DockZone == .Right);
	}

	[Test]
	public static void DockManagerDockTop()
	{
		let manager = scope DockManager();
		let panel = new DockablePanel("Top Panel");

		manager.Dock(panel, .Top);

		Test.Assert(manager.TopPanel == panel);
		Test.Assert(panel.DockZone == .Top);
	}

	[Test]
	public static void DockManagerDockBottom()
	{
		let manager = scope DockManager();
		let panel = new DockablePanel("Bottom Panel");

		manager.Dock(panel, .Bottom);

		Test.Assert(manager.BottomPanel == panel);
		Test.Assert(panel.DockZone == .Bottom);
	}

	[Test]
	public static void DockManagerFloatPanel()
	{
		let manager = scope DockManager();
		let panel = new DockablePanel("Panel");
		manager.Dock(panel, .Left);

		manager.Float(panel, 100, 100);

		Test.Assert(manager.LeftPanel == null);
		Test.Assert(panel.IsFloating);
		Test.Assert(manager.FloatingPanels.Contains(panel));
	}

	[Test]
	public static void DockManagerClosePanelFromDocked()
	{
		let manager = scope DockManager();
		let panel = scope DockablePanel("Panel");
		manager.Dock(panel, .Left);

		manager.ClosePanel(panel);

		Test.Assert(manager.LeftPanel == null);
		// Panel should be removed
	}

	[Test]
	public static void DockManagerClosePanelFromFloating()
	{
		let manager = scope DockManager();
		let panel = scope DockablePanel("Panel");
		manager.Float(panel, 100, 100);

		Test.Assert(manager.FloatingPanels.Contains(panel));

		manager.ClosePanel(panel);

		Test.Assert(!manager.FloatingPanels.Contains(panel));
	}

	[Test]
	public static void DockManagerPanelSizes()
	{
		let manager = scope DockManager();

		manager.LeftWidth = 250;
		manager.RightWidth = 300;
		manager.TopHeight = 100;
		manager.BottomHeight = 120;

		Test.Assert(manager.LeftWidth == 250);
		Test.Assert(manager.RightWidth == 300);
		Test.Assert(manager.TopHeight == 100);
		Test.Assert(manager.BottomHeight == 120);
	}

	[Test]
	public static void DockManagerMeasure()
	{
		let manager = scope DockManager();

		let content = new Border();
		content.Width = 400;
		content.Height = 300;
		manager.CenterContent = content;

		manager.Measure(SizeConstraints.FromMaximum(800, 600));

		Test.Assert(manager.DesiredSize.Width > 0);
		Test.Assert(manager.DesiredSize.Height > 0);
	}

	[Test]
	public static void DockManagerArrangeWithDockedPanels()
	{
		let manager = scope DockManager();

		let leftPanel = new DockablePanel("Left");
		let rightPanel = new DockablePanel("Right");
		let content = new Border();

		manager.Dock(leftPanel, .Left);
		manager.Dock(rightPanel, .Right);
		manager.CenterContent = content;
		manager.LeftWidth = 100;
		manager.RightWidth = 100;

		manager.Measure(SizeConstraints.FromMaximum(600, 400));
		manager.Arrange(.(0, 0, 600, 400));

		// Left panel should be on the left
		Test.Assert(leftPanel.Bounds.X == 0);

		// Right panel should be on the right
		Test.Assert(rightPanel.Bounds.Right <= 600);
	}

	[Test]
	public static void DockManagerReplaceDockPanel()
	{
		let manager = scope DockManager();
		let panel1 = new DockablePanel("Panel 1");
		let panel2 = new DockablePanel("Panel 2");

		manager.Dock(panel1, .Left);
		Test.Assert(manager.LeftPanel == panel1);

		manager.Dock(panel2, .Left);
		Test.Assert(manager.LeftPanel == panel2);

		delete panel1;
	}

	[Test]
	public static void DockManagerDockZoneNoneUndocks()
	{
		let manager = scope DockManager();
		let panel = new DockablePanel("Panel");

		manager.Dock(panel, .Left);
		Test.Assert(manager.LeftPanel == panel);

		manager.Dock(panel, .None);
		Test.Assert(manager.LeftPanel == null);

		delete panel;
	}
}

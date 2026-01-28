using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

class PopupTests
{
	[Test]
	public static void PopupDefaultProperties()
	{
		let popup = scope Popup();
		Test.Assert(popup.Anchor == null);
		Test.Assert(popup.Placement == .Bottom);
		Test.Assert(popup.Behavior == .Default);
		Test.Assert(popup.HorizontalOffset == 0);
		Test.Assert(popup.VerticalOffset == 0);
		Test.Assert(!popup.IsOpen);
		Test.Assert(popup.Content == null);
	}

	[Test]
	public static void PopupSetContent()
	{
		let popup = scope Popup();
		let content = new Border();
		popup.Content = content;
		Test.Assert(popup.Content == content);
		Test.Assert(content.Parent == popup);
	}

	[Test]
	public static void PopupReplaceContent()
	{
		let popup = scope Popup();
		let content1 = new Border();
		let content2 = new Border();

		popup.Content = content1;
		Test.Assert(popup.Content == content1);

		popup.Content = content2;
		Test.Assert(popup.Content == content2);
		Test.Assert(content1.Parent == null);
		Test.Assert(content2.Parent == popup);

		delete content1;
	}

	[Test]
	public static void PopupPlacementProperty()
	{
		let popup = scope Popup();
		popup.Placement = .TopCenter;
		Test.Assert(popup.Placement == .TopCenter);

		popup.Placement = .Right;
		Test.Assert(popup.Placement == .Right);
	}

	[Test]
	public static void PopupBehaviorFlags()
	{
		let popup = scope Popup();

		popup.Behavior = .Modal;
		Test.Assert(popup.Behavior.HasFlag(.Modal));
		Test.Assert(popup.IsModal);

		popup.Behavior = .CloseOnClickOutside | .CloseOnEscape;
		Test.Assert(popup.Behavior.HasFlag(.CloseOnClickOutside));
		Test.Assert(popup.Behavior.HasFlag(.CloseOnEscape));
		Test.Assert(!popup.IsModal);
	}

	[Test]
	public static void PopupOffsets()
	{
		let popup = scope Popup();
		popup.HorizontalOffset = 10;
		popup.VerticalOffset = 20;
		Test.Assert(popup.HorizontalOffset == 10);
		Test.Assert(popup.VerticalOffset == 20);
	}

	[Test]
	public static void PopupCalculatePositionAbsolute()
	{
		let popup = scope Popup();
		popup.Placement = .Absolute;
		popup.HorizontalOffset = 100;
		popup.VerticalOffset = 50;

		// Need to measure first
		popup.Measure(.Unconstrained);

		let pos = popup.CalculatePosition(800, 600);
		Test.Assert(pos.X == 100);
		Test.Assert(pos.Y == 50);
	}

	[Test]
	public static void PopupCalculatePositionCenter()
	{
		let popup = scope Popup();
		popup.Placement = .Center;

		let content = new Border();
		content.Width = 200;
		content.Height = 100;
		popup.Content = content;

		popup.Measure(.Unconstrained);

		let pos = popup.CalculatePosition(800, 600);
		let expectedX = (800.0f - popup.DesiredSize.Width) / 2;
		let expectedY = (600.0f - popup.DesiredSize.Height) / 2;
		Test.Assert(pos.X == expectedX);
		Test.Assert(pos.Y == expectedY);
	}

	[Test]
	public static void PopupCalculatePositionBottomOfAnchor()
	{
		let context = scope UIContext();
		let anchor = scope Border();
		anchor.Width = 100;
		anchor.Height = 30;
		context.RootElement = anchor;
		context.SetViewportSize(800, 600);
		context.Update(0.016f, 0.016);

		let popup = scope Popup();
		popup.Anchor = anchor;
		popup.Placement = .Bottom;

		let content = new Border();
		content.Width = 150;
		content.Height = 80;
		popup.Content = content;
		popup.Measure(.Unconstrained);

		let pos = popup.CalculatePosition(800, 600);
		Test.Assert(pos.X == 0); // Same X as anchor
		Test.Assert(pos.Y == 30); // Below anchor (anchor height)
	}

	[Test]
	public static void PopupShouldCloseOnClickOutside()
	{
		let popup = scope Popup();
		popup.Behavior = .CloseOnClickOutside;
		popup.Width = .Fixed(100);
		popup.Height = .Fixed(100);
		popup.Visibility = .Visible; // Popup starts collapsed, need to make visible for bounds

		let content = new Border();
		popup.Content = content;
		popup.Measure(.Unconstrained);
		popup.Arrange(.(50, 50, 100, 100));

		// Verify bounds are set correctly
		let bounds = popup.Bounds;
		Test.Assert(bounds.Width > 0);
		Test.Assert(bounds.Height > 0);

		// Click outside - should close
		Test.Assert(popup.ShouldCloseOnClickOutside(bounds.Right + 50, bounds.Bottom + 50));

		// Click inside - should not close
		let centerX = bounds.X + bounds.Width / 2;
		let centerY = bounds.Y + bounds.Height / 2;
		Test.Assert(!popup.ShouldCloseOnClickOutside(centerX, centerY));
	}

	[Test]
	public static void PopupShouldNotCloseWhenBehaviorNotSet()
	{
		let popup = scope Popup();
		popup.Behavior = (PopupBehavior)0;

		let content = new Border();
		content.Width = 100;
		content.Height = 100;
		popup.Content = content;
		popup.Measure(.Unconstrained);
		popup.Arrange(.(50, 50, 100, 100));

		// Even clicking outside shouldn't trigger close when behavior not set
		Test.Assert(!popup.ShouldCloseOnClickOutside(200, 200));
	}
}

class ContextMenuTests
{
	[Test]
	public static void ContextMenuDefaultProperties()
	{
		let menu = scope ContextMenu();
		Test.Assert(menu != null);
		Test.Assert(menu.Items != null);
		Test.Assert(menu.Items.Count == 0);
		Test.Assert(menu.SelectedIndex == -1);
	}

	[Test]
	public static void ContextMenuAddItem()
	{
		let menu = scope ContextMenu();
		let item = new MenuItem("Test Item");
		menu.AddItem(item);

		Test.Assert(menu.Items.Count == 1);
		Test.Assert(menu.Items[0] == item);
	}

	[Test]
	public static void ContextMenuAddItemWithText()
	{
		let menu = scope ContextMenu();
		let item = menu.AddItem("Click Me", null);

		Test.Assert(menu.Items.Count == 1);
		Test.Assert(item.Text == "Click Me");
	}

	[Test]
	public static void ContextMenuAddSeparator()
	{
		let menu = scope ContextMenu();
		menu.AddItem("Item 1", null);
		menu.AddSeparator();
		menu.AddItem("Item 2", null);

		Test.Assert(menu.Items.Count == 3);
		if (let sepItem = menu.Items[1] as MenuItem)
			Test.Assert(sepItem.IsSeparator);
	}

	[Test]
	public static void ContextMenuClearItems()
	{
		let menu = scope ContextMenu();
		menu.AddItem("Item 1", null);
		menu.AddItem("Item 2", null);
		menu.AddItem("Item 3", null);

		Test.Assert(menu.Items.Count == 3);
		menu.ClearItems();
		Test.Assert(menu.Items.Count == 0);
		Test.Assert(menu.SelectedIndex == -1);
	}

	[Test]
	public static void ContextMenuSelectedIndex()
	{
		let menu = scope ContextMenu();
		menu.AddItem("Item 1", null);
		menu.AddItem("Item 2", null);
		menu.AddItem("Item 3", null);

		menu.SelectedIndex = 1;
		Test.Assert(menu.SelectedIndex == 1);

		// Clamp to valid range
		menu.SelectedIndex = 10;
		Test.Assert(menu.SelectedIndex == 2);

		menu.SelectedIndex = -5;
		Test.Assert(menu.SelectedIndex == -1);
	}
}

class MenuItemTests
{
	[Test]
	public static void MenuItemDefaultProperties()
	{
		let item = scope MenuItem();
		Test.Assert(item.Text == "");
		Test.Assert(item.ShortcutText == "");
		Test.Assert(!item.IsSeparator);
		Test.Assert(!item.HasSubmenu);
		Test.Assert(item.Submenu == null);
	}

	[Test]
	public static void MenuItemWithText()
	{
		let item = scope MenuItem("File");
		Test.Assert(item.Text == "File");
	}

	[Test]
	public static void MenuItemSetText()
	{
		let item = scope MenuItem();
		item.Text = "Edit";
		Test.Assert(item.Text == "Edit");
	}

	[Test]
	public static void MenuItemShortcutText()
	{
		let item = scope MenuItem("Save");
		item.ShortcutText = "Ctrl+S";
		Test.Assert(item.ShortcutText == "Ctrl+S");
	}

	[Test]
	public static void MenuItemSeparator()
	{
		let item = MenuItem.Separator();
		Test.Assert(item.IsSeparator);
		delete item;
	}

	[Test]
	public static void MenuItemSubmenu()
	{
		let item = scope MenuItem("Options");
		let submenu = scope ContextMenu();

		Test.Assert(!item.HasSubmenu);

		item.Submenu = submenu;
		Test.Assert(item.HasSubmenu);
		Test.Assert(item.Submenu == submenu);
	}
}

class UIContextPopupTests
{
	[Test]
	public static void OpenPopupRegistersWithContext()
	{
		let context = scope UIContext();
		let root = scope Border();
		context.RootElement = root;
		context.SetViewportSize(800, 600);

		let popup = new Popup();
		let content = new Border();
		content.Width = 100;
		content.Height = 100;
		popup.Content = content;

		// Set context by adding as child temporarily
		root.Child = popup;

		popup.Open();
		Test.Assert(popup.IsOpen);
	}

	[Test]
	public static void ClosePopupUnregistersFromContext()
	{
		let context = scope UIContext();
		let root = scope Border();
		context.RootElement = root;
		context.SetViewportSize(800, 600);

		let popup = new Popup();
		let content = new Border();
		content.Width = 100;
		content.Height = 100;
		popup.Content = content;

		root.Child = popup;
		popup.Open();
		Test.Assert(popup.IsOpen);

		popup.Close();
		Test.Assert(!popup.IsOpen);
	}
}

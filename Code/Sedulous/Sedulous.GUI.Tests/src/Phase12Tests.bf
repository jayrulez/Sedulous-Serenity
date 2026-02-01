using System;
using Sedulous.GUI;
using Sedulous.Mathematics;

namespace Sedulous.GUI.Tests;

/// Tests for Phase 12: Popup & Dialog System
class Phase12Tests
{
	// === Tooltip Tests ===

	[Test]
	public static void TooltipDefaultProperties()
	{
		let tooltip = scope Tooltip();
		Test.Assert(tooltip.Text == "");
		Test.Assert(tooltip.CornerRadius == 4);
		Test.Assert(tooltip.BorderThickness == 1);
	}

	[Test]
	public static void TooltipWithText()
	{
		let tooltip = scope Tooltip("Hello World");
		Test.Assert(tooltip.Text == "Hello World");
		Test.Assert(tooltip.Content != null);  // Should create a TextBlock
	}

	[Test]
	public static void TooltipSetText()
	{
		let tooltip = scope Tooltip();
		tooltip.Text = "Test Tooltip";
		Test.Assert(tooltip.Text == "Test Tooltip");
	}

	// === MenuItem Tests ===

	[Test]
	public static void MenuItemDefaultProperties()
	{
		let item = scope MenuItem();
		Test.Assert(item.Text == "");
		Test.Assert(item.ShortcutText == "");
		Test.Assert(item.IsCheckable == false);
		Test.Assert(item.IsChecked == false);
		Test.Assert(item.HasSubItems == false);
	}

	[Test]
	public static void MenuItemWithText()
	{
		let item = scope MenuItem("Cut");
		Test.Assert(item.Text == "Cut");
	}

	[Test]
	public static void MenuItemWithShortcut()
	{
		let item = scope MenuItem("Copy");
		item.ShortcutText = "Ctrl+C";
		Test.Assert(item.ShortcutText == "Ctrl+C");
	}

	[Test]
	public static void MenuItemCheckable()
	{
		let item = scope MenuItem("Show Grid");
		item.IsCheckable = true;
		Test.Assert(item.IsCheckable == true);
		Test.Assert(item.IsChecked == false);

		item.IsChecked = true;
		Test.Assert(item.IsChecked == true);
	}

	[Test]
	public static void MenuItemAddSubItem()
	{
		let item = scope MenuItem("File");
		let subItem = item.AddItem("Open");

		Test.Assert(item.HasSubItems == true);
		Test.Assert(item.SubItemCount == 1);
		Test.Assert(subItem.Text == "Open");
	}

	[Test]
	public static void MenuItemAddSeparator()
	{
		let item = scope MenuItem("Edit");
		item.AddItem("Cut");
		item.AddSeparator();
		item.AddItem("Paste");

		Test.Assert(item.SubItemCount == 3);
		Test.Assert(item.GetSubItem(1) is MenuSeparator);
	}

	[Test]
	public static void MenuItemHighlightState()
	{
		let item = scope MenuItem("Item");
		Test.Assert(item.IsHighlighted == false);

		item.SetHighlighted(true);
		Test.Assert(item.IsHighlighted == true);

		item.SetHighlighted(false);
		Test.Assert(item.IsHighlighted == false);
	}

	// === MenuSeparator Tests ===

	[Test]
	public static void MenuSeparatorDefaultProperties()
	{
		let separator = scope MenuSeparator();
		Test.Assert(separator.LineThickness == 1);
	}

	// === ContextMenu Tests ===

	[Test]
	public static void ContextMenuDefaultProperties()
	{
		let menu = scope ContextMenu();
		Test.Assert(menu.ItemCount == 0);
	}

	[Test]
	public static void ContextMenuAddItem()
	{
		let menu = scope ContextMenu();
		let item = menu.AddItem("Cut");

		Test.Assert(menu.ItemCount == 1);
		Test.Assert(item.Text == "Cut");
	}

	[Test]
	public static void ContextMenuAddMultipleItems()
	{
		let menu = scope ContextMenu();
		menu.AddItem("Cut");
		menu.AddItem("Copy");
		menu.AddItem("Paste");

		Test.Assert(menu.ItemCount == 3);
	}

	[Test]
	public static void ContextMenuAddSeparator()
	{
		let menu = scope ContextMenu();
		menu.AddItem("Cut");
		menu.AddSeparator();
		menu.AddItem("Paste");

		Test.Assert(menu.ItemCount == 3);
		Test.Assert(menu.GetItem(1) is MenuSeparator);
	}

	[Test]
	public static void ContextMenuClearItems()
	{
		let menu = scope ContextMenu();
		menu.AddItem("Cut");
		menu.AddItem("Copy");
		menu.AddItem("Paste");

		Test.Assert(menu.ItemCount == 3);

		menu.ClearItems();
		Test.Assert(menu.ItemCount == 0);
	}

	// === DialogResult Tests ===

	[Test]
	public static void DialogResultEnumValues()
	{
		Test.Assert(DialogResult.None != DialogResult.OK);
		Test.Assert(DialogResult.OK != DialogResult.Cancel);
		Test.Assert(DialogResult.Yes != DialogResult.No);
	}

	// === Dialog Tests ===

	[Test]
	public static void DialogDefaultProperties()
	{
		let dialog = scope Dialog();
		Test.Assert(dialog.Title == "");
		Test.Assert(dialog.Content == null);
		Test.Assert(dialog.Result == .None);
	}

	[Test]
	public static void DialogWithTitle()
	{
		let dialog = scope Dialog("Test Dialog");
		Test.Assert(dialog.Title == "Test Dialog");
	}

	[Test]
	public static void DialogSetTitle()
	{
		let dialog = scope Dialog();
		dialog.Title = "My Dialog";
		Test.Assert(dialog.Title == "My Dialog");
	}

	[Test]
	public static void DialogSetContent()
	{
		let dialog = scope Dialog("Dialog");
		let content = new TextBlock("Content");
		dialog.Content = content;
		Test.Assert(dialog.Content == content);
	}

	[Test]
	public static void DialogAddButtons()
	{
		let dialog = scope Dialog("Dialog");
		let okBtn = dialog.AddButton("OK", .OK);
		let cancelBtn = dialog.AddButton("Cancel", .Cancel);

		Test.Assert(okBtn != null);
		Test.Assert(cancelBtn != null);
	}

	[Test]
	public static void DialogMinSize()
	{
		let dialog = scope Dialog("Dialog");
		dialog.DialogMinWidth = 400;
		dialog.DialogMinHeight = 200;

		Test.Assert(dialog.DialogMinWidth == 400);
		Test.Assert(dialog.DialogMinHeight == 200);
	}

	// === Flyout Tests ===

	[Test]
	public static void FlyoutDefaultProperties()
	{
		let flyout = scope Flyout();
		Test.Assert(flyout.Placement == .Bottom);
		Test.Assert(flyout.CornerRadius == 4);
	}

	[Test]
	public static void FlyoutSetPlacement()
	{
		let flyout = scope Flyout();
		flyout.Placement = .Top;
		Test.Assert(flyout.Placement == .Top);

		flyout.Placement = .Left;
		Test.Assert(flyout.Placement == .Left);

		flyout.Placement = .Right;
		Test.Assert(flyout.Placement == .Right);

		flyout.Placement = .Auto;
		Test.Assert(flyout.Placement == .Auto);
	}

	[Test]
	public static void FlyoutSetContent()
	{
		let flyout = scope Flyout();
		let content = new TextBlock("Flyout content");
		flyout.Content = content;
		Test.Assert(flyout.Content == content);
	}

	// === TooltipService Tests ===

	[Test]
	public static void TooltipServiceDefaultProperties()
	{
		let context = scope GUIContext();
		let service = context.TooltipService;

		Test.Assert(service != null);
		Test.Assert(service.ShowDelay == 0.5f);
		Test.Assert(service.HideDelay == 0.0f);
	}

	[Test]
	public static void TooltipServiceSetDelay()
	{
		let context = scope GUIContext();
		let service = context.TooltipService;

		service.ShowDelay = 1.0f;
		Test.Assert(service.ShowDelay == 1.0f);

		service.HideDelay = 0.2f;
		Test.Assert(service.HideDelay == 0.2f);
	}

	// === ModalManager Tests ===

	[Test]
	public static void ModalManagerDefaultProperties()
	{
		let context = scope GUIContext();
		let manager = context.ModalManager;

		Test.Assert(manager != null);
		Test.Assert(manager.HasModal == false);
		Test.Assert(manager.ModalCount == 0);
	}

	[Test]
	public static void ModalManagerBackdropOpacity()
	{
		let context = scope GUIContext();
		let manager = context.ModalManager;

		manager.BackdropOpacity = 0.8f;
		Test.Assert(Math.Abs(manager.BackdropOpacity - 0.8f) < 0.01f);
	}

	// === Control TooltipText Tests ===

	[Test]
	public static void ControlTooltipText()
	{
		let button = scope Button("Test");
		Test.Assert(button.TooltipText == "");

		button.TooltipText = "Button tooltip";
		Test.Assert(button.TooltipText == "Button tooltip");
	}

	// === Control ContextMenu Tests ===

	[Test]
	public static void ControlContextMenu()
	{
		let button = scope Button("Test");
		Test.Assert(button.ContextMenu == null);

		let menu = new ContextMenu();
		menu.AddItem("Action");
		button.ContextMenu = menu;

		Test.Assert(button.ContextMenu != null);
		Test.Assert(button.ContextMenu.ItemCount == 1);
	}
}

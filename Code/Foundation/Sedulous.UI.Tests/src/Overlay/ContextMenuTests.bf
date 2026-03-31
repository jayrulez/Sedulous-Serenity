using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class ContextMenuTests
{
	[Test]
	public static void ContextMenu_AddItems()
	{
		let menu = scope ContextMenu();
		menu.AddItem("Cut", new () => {});
		menu.AddItem("Copy", new () => {});
		menu.AddItem("Paste", new () => {});
		Test.Assert(menu.ItemCount == 3);
	}

	[Test]
	public static void ContextMenu_WithSeparator()
	{
		let menu = scope ContextMenu();
		menu.AddItem("Undo", new () => {});
		menu.AddSeparator();
		menu.AddItem("Cut", new () => {});
		Test.Assert(menu.ItemCount == 3); // 2 items + 1 separator
	}

	[Test]
	public static void ContextMenu_ShowAsPopup()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let menu = new ContextMenu();
		menu.AddItem("Action 1", new () => {});
		menu.AddItem("Action 2", new () => {});

		ContextMenu.Show(ctx, 100, 100, menu);
		Test.Assert(rootView.PopupLayer.HasPopups);
		Test.Assert(rootView.PopupLayer.PopupCount == 1);

		rootView.PopupLayer.CloseAllPopups();
	}

	[Test]
	public static void ContextMenu_DisabledItem()
	{
		let menu = scope ContextMenu();
		menu.AddItem("Enabled", new () => {}, true);
		menu.AddItem("Disabled", new () => {}, false);
		Test.Assert(menu.ItemCount == 2);
	}

	[Test]
	public static void ContextMenu_ClickOutsideCloses()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let menu = new ContextMenu();
		menu.AddItem("Test", new () => {});
		ContextMenu.Show(ctx, 100, 100, menu);
		TestHelper.UpdateFrame(ctx, rootView);

		Test.Assert(rootView.PopupLayer.HasPopups);

		// Click outside
		rootView.PopupLayer.HandleClickOutside(300, 300);
		Test.Assert(!rootView.PopupLayer.HasPopups);
	}
}

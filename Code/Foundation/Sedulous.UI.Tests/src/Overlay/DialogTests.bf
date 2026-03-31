using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class DialogTests
{
	[Test]
	public static void Dialog_AlertCreation()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let dialog = Dialog.Alert("Test Title", "Test message body");
		ctx.ShowModalPopup(dialog);
		TestHelper.UpdateFrame(ctx, rootView);

		Test.Assert(rootView.PopupLayer.HasModalPopup);
		Test.Assert(rootView.PopupLayer.TopModalPopup == dialog);

		rootView.PopupLayer.CloseAllPopups();
	}

	[Test]
	public static void Dialog_ConfirmCreation()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let dialog = Dialog.Confirm("Confirm?", "Are you sure?");
		ctx.ShowModalPopup(dialog);
		TestHelper.UpdateFrame(ctx, rootView);

		Test.Assert(rootView.PopupLayer.HasModalPopup);

		rootView.PopupLayer.CloseAllPopups();
	}

	[Test]
	public static void Dialog_CloseFiresResult()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let dialog = Dialog.Alert("Title", "Message");
		Dialog.DialogResult gotResult = .None;
		dialog.OnResult.Subscribe(new [&] (d, r) => { gotResult = r; });

		ctx.ShowModalPopup(dialog);
		TestHelper.UpdateFrame(ctx, rootView);

		dialog.Close(.OK);
		Test.Assert(gotResult == .OK);
		TestHelper.UpdateFrame(ctx, rootView); // Process deferred close
		Test.Assert(!rootView.PopupLayer.HasPopups);
	}

	[Test]
	public static void Dialog_ConfirmResult()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let dialog = Dialog.Confirm("Delete?", "Really delete?");
		Dialog.DialogResult gotResult = .None;
		dialog.OnResult.Subscribe(new [&] (d, r) => { gotResult = r; });

		ctx.ShowModalPopup(dialog);
		TestHelper.UpdateFrame(ctx, rootView);

		dialog.Close(.Yes);
		Test.Assert(gotResult == .Yes);
		TestHelper.UpdateFrame(ctx, rootView); // Process deferred close
	}

	[Test]
	public static void Dialog_CustomContent()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let dialog = new Dialog();
		dialog.Title = "Custom";
		let content = new Label();
		content.Text = "Custom content";
		dialog.SetContent(content);
		dialog.AddButton("Done", .Custom);

		ctx.ShowModalPopup(dialog);
		TestHelper.UpdateFrame(ctx, rootView);

		Test.Assert(rootView.PopupLayer.HasModalPopup);

		rootView.PopupLayer.CloseAllPopups();
	}
}

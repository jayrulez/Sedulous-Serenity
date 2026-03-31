using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class PopupLayerTests
{
	[Test]
	public static void PopupLayer_InitiallyEmpty()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		Test.Assert(!rootView.PopupLayer.HasPopups);
		Test.Assert(rootView.PopupLayer.PopupCount == 0);
		Test.Assert(!rootView.PopupLayer.HasModalPopup);
	}

	[Test]
	public static void PopupLayer_ShowPopup()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let popup = new Label();
		popup.Text = "Test Popup";
		ctx.ShowPopup(popup, null, 100, 50);

		Test.Assert(rootView.PopupLayer.HasPopups);
		Test.Assert(rootView.PopupLayer.PopupCount == 1);
	}

	[Test]
	public static void PopupLayer_ClosePopup()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let popup = new Label();
		popup.Text = "Test";
		ctx.ShowPopup(popup, null, 100, 50);
		Test.Assert(rootView.PopupLayer.PopupCount == 1);

		ctx.ClosePopup(popup);
		Test.Assert(rootView.PopupLayer.PopupCount == 0);
		Test.Assert(!rootView.PopupLayer.HasPopups);
	}

	[Test]
	public static void PopupLayer_ModalPopup()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let dialog = new Label();
		dialog.Text = "Modal";
		ctx.ShowModalPopup(dialog);

		Test.Assert(rootView.PopupLayer.HasPopups);
		Test.Assert(rootView.PopupLayer.HasModalPopup);
		Test.Assert(rootView.PopupLayer.TopModalPopup == dialog);
	}

	[Test]
	public static void PopupLayer_CloseAllPopups()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ShowPopup(new Label(), null, 10, 10);
		ctx.ShowPopup(new Label(), null, 20, 20);
		ctx.ShowPopup(new Label(), null, 30, 30);
		Test.Assert(rootView.PopupLayer.PopupCount == 3);

		rootView.PopupLayer.CloseAllPopups();
		Test.Assert(rootView.PopupLayer.PopupCount == 0);
	}

	[Test]
	public static void PopupLayer_HitTestPassesThroughWhenEmpty()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let hit = rootView.PopupLayer.HitTest(.(100, 100));
		Test.Assert(hit == null);
	}

	[Test]
	public static void PopupLayer_ClickOutsideCloses()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let popup = new Label();
		popup.Text = "Popup";
		popup.MinWidth = 100;
		popup.MinHeight = 30;
		ctx.ShowPopup(popup, null, 50, 50, true);
		TestHelper.UpdateFrame(ctx, rootView); // Measure and layout

		Test.Assert(rootView.PopupLayer.PopupCount == 1);

		// Click outside the popup
		rootView.PopupLayer.HandleClickOutside(300, 300);
		Test.Assert(rootView.PopupLayer.PopupCount == 0);
	}

	[Test]
	public static void PopupLayer_OwnerNotified()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		PopupOwnerTracker tracker = scope .();
		let popup = new Label();
		ctx.ShowPopup(popup, tracker, 10, 10);

		ctx.ClosePopup(popup);
		Test.Assert(tracker.CloseCount == 1);
	}

	private class PopupOwnerTracker : IPopupOwner
	{
		public int CloseCount = 0;

		public void OnPopupClosed(View popup)
		{
			CloseCount++;
		}
	}
}

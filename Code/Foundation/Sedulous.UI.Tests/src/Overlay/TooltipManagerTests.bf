using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class TooltipManagerTests
{
	[Test]
	public static void TooltipManager_InitialState()
	{
		let ctx = scope UIContext();
		let rootView = TestHelper.SetupContext(ctx, null);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		Test.Assert(!ctx.Tooltips.IsShowing);
		Test.Assert(ctx.Tooltips.CurrentTarget == null);
	}

	[Test]
	public static void TooltipManager_ShowsAfterDelay()
	{
		let ctx = scope UIContext();
		let content = new FrameLayout();
		let btn = new Button();
		btn.Text = "Hover me";
		btn.TooltipText = new .("Tooltip text");
		btn.MinWidth = 100;
		btn.MinHeight = 30;
		content.AddView(btn, new LayoutParams(100, 30));
		let rootView = TestHelper.SetupContext(ctx, content);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Simulate hover
		ctx.Tooltips.OnMouseMoved(50, 15);
		ctx.Tooltips.OnHoverChanged(btn);

		Test.Assert(ctx.Tooltips.CurrentTarget == btn);
		Test.Assert(!ctx.Tooltips.IsShowing);

		// Tick tooltip directly past show delay
		ctx.Tooltips.Update(0.6f);

		Test.Assert(ctx.Tooltips.IsShowing);

		// Cleanup: hide before scope exit
		ctx.Tooltips.Hide();
	}

	[Test]
	public static void TooltipManager_HidesOnMouseDown()
	{
		let ctx = scope UIContext();
		let content = new FrameLayout();
		let btn = new Button();
		btn.Text = "Click";
		btn.TooltipText = new .("Tip");
		btn.MinWidth = 100;
		btn.MinHeight = 30;
		content.AddView(btn, new LayoutParams(100, 30));
		let rootView = TestHelper.SetupContext(ctx, content);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.Tooltips.OnMouseMoved(50, 15);
		ctx.Tooltips.OnHoverChanged(btn);
		ctx.Tooltips.Update(0.6f);
		Test.Assert(ctx.Tooltips.IsShowing);

		ctx.Tooltips.OnMouseDown();
		Test.Assert(!ctx.Tooltips.IsShowing);
	}

	[Test]
	public static void TooltipManager_NoTooltipWithoutText()
	{
		let ctx = scope UIContext();
		let content = new FrameLayout();
		let btn = new Button();
		btn.Text = "No tooltip";
		btn.MinWidth = 100;
		btn.MinHeight = 30;
		content.AddView(btn, new LayoutParams(100, 30));
		let rootView = TestHelper.SetupContext(ctx, content);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.Tooltips.OnHoverChanged(btn);
		Test.Assert(ctx.Tooltips.CurrentTarget == null); // No tooltip text = no target

		ctx.Tooltips.Update(0.6f);
		Test.Assert(!ctx.Tooltips.IsShowing);
	}

	[Test]
	public static void TooltipManager_HidesOnHoverLeave()
	{
		let ctx = scope UIContext();
		let content = new FrameLayout();
		let btn = new Button();
		btn.Text = "Hover";
		btn.TooltipText = new .("Tip");
		btn.MinWidth = 100;
		btn.MinHeight = 30;
		content.AddView(btn, new LayoutParams(100, 30));
		let rootView = TestHelper.SetupContext(ctx, content);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.Tooltips.OnMouseMoved(50, 15);
		ctx.Tooltips.OnHoverChanged(btn);
		ctx.Tooltips.Update(0.6f);
		Test.Assert(ctx.Tooltips.IsShowing);

		// Hover away
		ctx.Tooltips.OnHoverChanged(null);
		Test.Assert(!ctx.Tooltips.IsShowing);
	}
}

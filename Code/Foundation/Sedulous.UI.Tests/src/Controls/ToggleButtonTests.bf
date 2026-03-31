using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class ToggleButtonTests
{
	private static RootView SetupContext(UIContext ctx, View root, float w, float h)
	{
		return TestHelper.SetupContext(ctx, root, w, h);
	}

	[Test]
	public static void ToggleButton_DefaultUnchecked()
	{
		let tb = scope ToggleButton();
		Test.Assert(!tb.IsChecked);
	}

	[Test]
	public static void ToggleButton_Click_TogglesState()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let tb = new ToggleButton("Toggle");
		root.AddView(tb, new LayoutParams(200, 40));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Click to check
		ctx.ProcessMouseDown(100, 20, .Left);
		ctx.ProcessMouseUp(100, 20, .Left);
		Test.Assert(tb.IsChecked);

		// Click again to uncheck
		ctx.ProcessMouseDown(100, 20, .Left);
		ctx.ProcessMouseUp(100, 20, .Left);
		Test.Assert(!tb.IsChecked);
	}

	[Test]
	public static void ToggleButton_FiresOnCheckedChanged()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let tb = new ToggleButton("Toggle");
		root.AddView(tb, new LayoutParams(200, 40));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		bool eventFired = false;
		bool lastState = false;
		tb.OnCheckedChanged.Subscribe(new [&eventFired, &lastState] (t, c) => { eventFired = true; lastState = c; });

		ctx.ProcessMouseDown(100, 20, .Left);
		ctx.ProcessMouseUp(100, 20, .Left);

		Test.Assert(eventFired);
		Test.Assert(lastState == true);
	}

	[Test]
	public static void ToggleButton_SetIsChecked_Programmatic()
	{
		let tb = scope ToggleButton();
		bool eventFired = false;
		tb.OnCheckedChanged.Subscribe(new [&eventFired] (t, c) => { eventFired = true; });

		tb.IsChecked = true;
		Test.Assert(tb.IsChecked);
		Test.Assert(eventFired);
	}

	[Test]
	public static void ToggleButton_Disabled_DoesNotToggle()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let tb = new ToggleButton("Toggle");
		tb.Enabled = false;
		root.AddView(tb, new LayoutParams(200, 40));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseDown(100, 20, .Left);
		ctx.ProcessMouseUp(100, 20, .Left);

		Test.Assert(!tb.IsChecked);
	}
}

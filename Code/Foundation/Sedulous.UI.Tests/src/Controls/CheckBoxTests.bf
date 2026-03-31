using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class CheckBoxTests
{
	private static RootView SetupContext(UIContext ctx, View root, float w, float h)
	{
		return TestHelper.SetupContext(ctx, root, w, h);
	}

	[Test]
	public static void CheckBox_DefaultUnchecked()
	{
		let cb = scope CheckBox();
		Test.Assert(!cb.IsChecked);
	}

	[Test]
	public static void CheckBox_Click_TogglesState()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let cb = new CheckBox("Check");
		root.AddView(cb, new LayoutParams(200, 30));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseDown(10, 15, .Left);
		Test.Assert(cb.IsChecked);

		ctx.ProcessMouseDown(10, 15, .Left);
		Test.Assert(!cb.IsChecked);
	}

	[Test]
	public static void CheckBox_FiresOnCheckedChanged()
	{
		let cb = scope CheckBox("Test");
		bool eventFired = false;
		bool lastState = false;
		cb.OnCheckedChanged.Subscribe(new [&eventFired, &lastState] (c, s) => { eventFired = true; lastState = s; });

		cb.IsChecked = true;
		Test.Assert(eventFired);
		Test.Assert(lastState == true);
	}

	[Test]
	public static void CheckBox_ConstructorWithText()
	{
		let cb = scope CheckBox("Hello");
		Test.Assert(cb.Text == "Hello");
	}

	[Test]
	public static void CheckBox_SetSameValue_NoEvent()
	{
		let cb = scope CheckBox();
		cb.IsChecked = false; // already false

		bool eventFired = false;
		cb.OnCheckedChanged.Subscribe(new [&eventFired] (c, s) => { eventFired = true; });

		cb.IsChecked = false; // same value
		Test.Assert(!eventFired);
	}

	[Test]
	public static void CheckBox_IsFocusable()
	{
		let cb = scope CheckBox();
		Test.Assert(cb.Focusable);
	}

	[Test]
	public static void CheckBox_Disabled_DoesNotToggle()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let cb = new CheckBox("Disabled");
		cb.Enabled = false;
		root.AddView(cb, new LayoutParams(200, 30));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseDown(10, 15, .Left);
		Test.Assert(!cb.IsChecked);
	}
}

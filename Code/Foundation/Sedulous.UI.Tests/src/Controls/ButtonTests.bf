using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class ButtonTests
{
	private static RootView SetupContext(UIContext ctx, View root, float w, float h)
	{
		return TestHelper.SetupContext(ctx, root, w, h);
	}

	[Test]
	public static void Button_IsFocusableByDefault()
	{
		let btn = scope Button();
		Test.Assert(btn.Focusable);
	}

	[Test]
	public static void Button_HasPointerCursor()
	{
		let btn = scope Button();
		Test.Assert(btn.CursorType == .Pointer);
	}

	[Test]
	public static void Button_Click_FiresOnClick()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let btn = new Button("Click Me");
		root.AddView(btn, new LayoutParams(200, 40));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		bool clicked = false;
		btn.OnClick.Subscribe(new [&clicked] (b) => { clicked = true; });

		// Press and release within bounds
		ctx.ProcessMouseDown(100, 20, .Left);
		ctx.ProcessMouseUp(100, 20, .Left);

		Test.Assert(clicked);
	}

	[Test]
	public static void Button_Disabled_DoesNotFireOnClick()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let btn = new Button("Disabled");
		btn.Enabled = false;
		root.AddView(btn, new LayoutParams(200, 40));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		bool clicked = false;
		btn.OnClick.Subscribe(new [&clicked] (b) => { clicked = true; });

		ctx.ProcessMouseDown(100, 20, .Left);
		ctx.ProcessMouseUp(100, 20, .Left);

		Test.Assert(!clicked);
	}

	[Test]
	public static void Button_ReleaseOutsideBounds_DoesNotFireOnClick()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let btn = new Button("Press");
		root.AddView(btn, new LayoutParams(100, 40));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		bool clicked = false;
		btn.OnClick.Subscribe(new [&clicked] (b) => { clicked = true; });

		// Press inside, release outside
		ctx.ProcessMouseDown(50, 20, .Left);
		ctx.ProcessMouseUp(150, 150, .Left);

		Test.Assert(!clicked);
	}

	[Test]
	public static void Button_SetText_UpdatesText()
	{
		let btn = scope Button();
		btn.Text = "Hello";
		Test.Assert(btn.Text == "Hello");
	}

	[Test]
	public static void Button_KeyboardActivation_Space()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let btn = new Button("KB");
		root.AddView(btn, new LayoutParams(200, 40));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		bool clicked = false;
		btn.OnClick.Subscribe(new [&clicked] (b) => { clicked = true; });

		ctx.FocusManager.SetFocus(btn);
		ctx.ProcessKeyDown(.Space);

		Test.Assert(clicked);
	}

	[Test]
	public static void Button_KeyboardActivation_Enter()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let btn = new Button("KB");
		root.AddView(btn, new LayoutParams(200, 40));
		let rootView = SetupContext(ctx, root, 200, 200); defer { ctx.RemoveRootView(rootView); delete rootView; }

		bool clicked = false;
		btn.OnClick.Subscribe(new [&clicked] (b) => { clicked = true; });

		ctx.FocusManager.SetFocus(btn);
		ctx.ProcessKeyDown(.Return);

		Test.Assert(clicked);
	}
}

using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class InputManagerTests
{
	/// Helper: create a UIContext with a RootView wrapping the given content,
	/// with children laid out so hit-testing works.
	private static RootView SetupContext(UIContext ctx, View content, float w, float h)
	{
		return TestHelper.SetupContext(ctx, content, w, h);
	}

	//==========================================================================
	// Mouse Move / Hover
	//==========================================================================

	[Test]
	public static void MouseMove_UpdatesHover()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(100, 100);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Move mouse over child (child is at 0,0 sized 100x100 inside 200x200 root)
		ctx.ProcessMouseMove(50, 50);

		Test.Assert(child.MouseEnterCalled);
		Test.Assert(child.IsHovered);
		Test.Assert(ctx.InputManager.HoveredView == child);
	}

	[Test]
	public static void MouseMove_EnterLeave_OnHoverChange()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();

		let childA = new InputTestView(100, 100);
		childA.LayoutParams = new LayoutParams(100, 100);
		root.AddView(childA);

		let childB = new InputTestView(100, 100);
		childB.LayoutParams = new LayoutParams(100, 100);
		root.AddView(childB);

		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// childA and childB are stacked (FrameLayout). childB is on top at same position.
		// Move over them — childB (last added) should be hit
		ctx.ProcessMouseMove(50, 50);
		Test.Assert(childB.MouseEnterCalled);

		childA.ClearFlags();
		childB.ClearFlags();

		// Move outside both children (beyond their bounds)
		ctx.ProcessMouseMove(150, 150);
		Test.Assert(childB.MouseLeaveCalled);
	}

	[Test]
	public static void MouseMove_FiresMouseMoveHandler()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseMove(50, 50);
		child.ClearFlags();

		// Second move — same hover target, should fire OnMouseMove
		ctx.ProcessMouseMove(60, 60);
		Test.Assert(child.MouseMoveCalled);
	}

	//==========================================================================
	// Mouse Down / Up
	//==========================================================================

	[Test]
	public static void MouseDown_SetsPressedState()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseDown(50, 50, .Left);

		Test.Assert(child.MouseDownCalled);
		Test.Assert(child.IsPressed);
		Test.Assert(child.LastButton == .Left);
		Test.Assert(ctx.InputManager.PressedView == child);
	}

	[Test]
	public static void MouseUp_ClearsPressedState()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseDown(50, 50, .Left);
		Test.Assert(child.IsPressed);

		ctx.ProcessMouseUp(50, 50, .Left);
		Test.Assert(child.MouseUpCalled);
		Test.Assert(!child.IsPressed);
		Test.Assert(ctx.InputManager.PressedView == null);
	}

	[Test]
	public static void MouseDown_FocusOnClick()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		child.Focusable = true;
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseDown(50, 50, .Left);

		Test.Assert(child.IsFocused);
		Test.Assert(child.FocusGainedCalled);
		Test.Assert(ctx.FocusManager.FocusedView == child);
	}

	[Test]
	public static void MouseDown_DisabledView_DoesNotFocus()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		child.Focusable = true;
		child.Enabled = false;
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseDown(50, 50, .Left);

		Test.Assert(!child.IsFocused);
		Test.Assert(ctx.FocusManager.FocusedView == null);
	}

	[Test]
	public static void MouseDown_EmptySpace_ClearsFocus()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(50, 50);
		child.Focusable = true;
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Focus the child via click
		ctx.ProcessMouseDown(25, 25, .Left);
		ctx.ProcessMouseUp(25, 25, .Left);
		Test.Assert(child.IsFocused);

		child.ClearFlags();

		// Click far outside child (root will be hit, not focusable, no focusable ancestor)
		ctx.ProcessMouseDown(150, 150, .Left);
		// Focus should be cleared since root isn't focusable
		Test.Assert(!child.IsFocused);
	}

	//==========================================================================
	// Double-Click Detection
	//==========================================================================

	[Test]
	public static void DoubleClick_Detected()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// First click
		ctx.ProcessMouseDown(50, 50, .Left);
		ctx.ProcessMouseUp(50, 50, .Left);
		Test.Assert(child.LastClickCount == 1);

		child.ClearFlags();

		// Second click within time window (advance a tiny bit of time)
		TestHelper.UpdateFrame(ctx, rootView, 0.1f);
		ctx.ProcessMouseDown(50, 50, .Left);
		Test.Assert(child.LastClickCount == 2);
	}

	[Test]
	public static void DoubleClick_TooSlow_ResetToSingle()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// First click
		ctx.ProcessMouseDown(50, 50, .Left);
		ctx.ProcessMouseUp(50, 50, .Left);

		child.ClearFlags();

		// Wait too long (double-click time is 0.3s)
		TestHelper.UpdateFrame(ctx, rootView, 0.5f);
		ctx.ProcessMouseDown(50, 50, .Left);
		Test.Assert(child.LastClickCount == 1);
	}

	//==========================================================================
	// Mouse Wheel
	//==========================================================================

	[Test]
	public static void MouseWheel_RoutesToTarget()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseWheel(50, 50, 0, 120);
		Test.Assert(child.MouseWheelCalled);
	}

	//==========================================================================
	// Keyboard Events
	//==========================================================================

	[Test]
	public static void KeyDown_RoutesToFocused()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		child.Focusable = true;
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.FocusManager.SetFocus(child);
		child.ClearFlags();

		ctx.ProcessKeyDown(.A);
		Test.Assert(child.KeyDownCalled);
		Test.Assert(child.LastKey == .A);
	}

	[Test]
	public static void KeyUp_RoutesToFocused()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		child.Focusable = true;
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.FocusManager.SetFocus(child);
		child.ClearFlags();

		ctx.ProcessKeyUp(.A);
		Test.Assert(child.KeyUpCalled);
	}

	[Test]
	public static void KeyDown_NoFocus_NoEvent()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// No focus set
		ctx.ProcessKeyDown(.A);
		Test.Assert(!child.KeyDownCalled);
	}

	[Test]
	public static void Tab_AdvancesFocus()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let a = new InputTestView(200, 200); a.Focusable = true;
		let b = new InputTestView(200, 200); b.Focusable = true;
		root.AddView(a);
		root.AddView(b);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.FocusManager.SetFocus(a);

		ctx.ProcessKeyDown(.Tab);
		Test.Assert(ctx.FocusManager.FocusedView == b);
	}

	[Test]
	public static void ShiftTab_GoesBackward()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let a = new InputTestView(200, 200); a.Focusable = true;
		let b = new InputTestView(200, 200); b.Focusable = true;
		root.AddView(a);
		root.AddView(b);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.FocusManager.SetFocus(b);

		ctx.ProcessKeyDown(.Tab, .Shift);
		Test.Assert(ctx.FocusManager.FocusedView == a);
	}

	//==========================================================================
	// Text Input
	//==========================================================================

	[Test]
	public static void TextInput_RoutesToFocused()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		child.Focusable = true;
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.FocusManager.SetFocus(child);
		child.ClearFlags();

		ctx.ProcessTextInput('A');
		Test.Assert(child.TextInputCalled);
		Test.Assert(child.LastChar == 'A');
	}

	//==========================================================================
	// Event Bubbling
	//==========================================================================

	[Test]
	public static void MouseDown_Bubbles_WhenNotHandled()
	{
		let ctx = scope UIContext();
		let parent = new FrameLayout();
		// We'll make a custom InputTestView that acts as a ViewGroup via FrameLayout
		let container = new InputTestFrameLayout(200, 200);
		parent.AddView(container);

		let child = new InputTestView(100, 100);
		container.AddView(child);

		let rootView = SetupContext(ctx, parent, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// child does NOT handle events, so it should bubble to container
		ctx.ProcessMouseDown(50, 50, .Left);
		Test.Assert(child.MouseDownCalled);
		Test.Assert(container.MouseDownCalled);
	}

	[Test]
	public static void MouseDown_StopsBubbling_WhenHandled()
	{
		let ctx = scope UIContext();
		let parent = new FrameLayout();
		let container = new InputTestFrameLayout(200, 200);
		parent.AddView(container);

		let child = new InputTestView(100, 100);
		child.HandlesEvents = true; // Will set Handled = true
		container.AddView(child);

		let rootView = SetupContext(ctx, parent, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseDown(50, 50, .Left);
		Test.Assert(child.MouseDownCalled);
		Test.Assert(!container.MouseDownCalled); // Should NOT bubble
	}

	[Test]
	public static void MouseWheel_Bubbles_WhenNotHandled()
	{
		let ctx = scope UIContext();
		let parent = new FrameLayout();
		let container = new InputTestFrameLayout(200, 200);
		parent.AddView(container);

		let child = new InputTestView(100, 100);
		container.AddView(child);

		let rootView = SetupContext(ctx, parent, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.ProcessMouseWheel(50, 50, 0, 120);
		Test.Assert(child.MouseWheelCalled);
		Test.Assert(container.MouseWheelCalled);
	}

	[Test]
	public static void KeyDown_Bubbles_WhenNotHandled()
	{
		let ctx = scope UIContext();
		let parent = new FrameLayout();
		let container = new InputTestFrameLayout(200, 200);
		parent.AddView(container);

		let child = new InputTestView(100, 100);
		child.Focusable = true;
		container.AddView(child);

		let rootView = SetupContext(ctx, parent, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.FocusManager.SetFocus(child);
		child.ClearFlags();
		container.ClearFlags();

		ctx.ProcessKeyDown(.A);
		Test.Assert(child.KeyDownCalled);
		Test.Assert(container.KeyDownCalled);
	}

	//==========================================================================
	// OnElementDeleted
	//==========================================================================

	[Test]
	public static void OnElementDeleted_ClearsHoveredAndPressed()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(200, 200);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Set up hover + pressed state
		ctx.ProcessMouseMove(50, 50);
		ctx.ProcessMouseDown(50, 50, .Left);
		Test.Assert(ctx.InputManager.HoveredView == child);
		Test.Assert(ctx.InputManager.PressedView == child);

		ctx.InputManager.OnElementDeleted(child);
		Test.Assert(ctx.InputManager.HoveredView == null);
		Test.Assert(ctx.InputManager.PressedView == null);
	}
}

/// A FrameLayout subclass that tracks input handler calls (for bubbling tests).
class InputTestFrameLayout : FrameLayout
{
	public float DesiredWidth;
	public float DesiredHeight;

	public bool MouseDownCalled;
	public bool MouseUpCalled;
	public bool MouseMoveCalled;
	public bool MouseWheelCalled;
	public bool MouseEnterCalled;
	public bool MouseLeaveCalled;
	public bool KeyDownCalled;
	public bool KeyUpCalled;

	public bool HandlesEvents;

	public this(float desiredWidth = 200, float desiredHeight = 200)
	{
		DesiredWidth = desiredWidth;
		DesiredHeight = desiredHeight;
	}

	public void ClearFlags()
	{
		MouseDownCalled = false;
		MouseUpCalled = false;
		MouseMoveCalled = false;
		MouseWheelCalled = false;
		MouseEnterCalled = false;
		MouseLeaveCalled = false;
		KeyDownCalled = false;
		KeyUpCalled = false;
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		MouseDownCalled = true;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnMouseUp(MouseButtonEventArgs e)
	{
		MouseUpCalled = true;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		MouseMoveCalled = true;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnMouseWheel(MouseWheelEventArgs e)
	{
		MouseWheelCalled = true;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnMouseEnter(MouseEventArgs e) { MouseEnterCalled = true; }
	public override void OnMouseLeave(MouseEventArgs e) { MouseLeaveCalled = true; }

	public override void OnKeyDown(KeyEventArgs e)
	{
		KeyDownCalled = true;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnKeyUp(KeyEventArgs e)
	{
		KeyUpCalled = true;
		if (HandlesEvents) e.Handled = true;
	}
}

using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class MouseCaptureTests
{
	private static RootView SetupContext(UIContext ctx, View content, float w, float h)
	{
		return TestHelper.SetupContext(ctx, content, w, h);
	}

	//==========================================================================
	// SetCapture / ReleaseCapture
	//==========================================================================

	[Test]
	public static void SetCapture_RoutesMouseMoveToCapture()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();

		// Two children side by side conceptually, but in FrameLayout they stack.
		// We'll use layout params to position them differently isn't possible in FrameLayout.
		// Instead: one small child and capture it, then move mouse outside.
		let child = new InputTestView(50, 50);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Move over child first to establish hover
		ctx.ProcessMouseMove(25, 25);
		Test.Assert(ctx.InputManager.HoveredView == child);

		// Set capture on child
		ctx.FocusManager.SetCapture(child);
		Test.Assert(ctx.FocusManager.CapturedView == child);

		child.ClearFlags();

		// Move mouse far outside child bounds — should still route to captured view
		ctx.ProcessMouseMove(150, 150);
		Test.Assert(child.MouseMoveCalled);
	}

	[Test]
	public static void SetCapture_RoutesMouseDownToCapture()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(50, 50);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.FocusManager.SetCapture(child);
		child.ClearFlags();

		// Click outside child bounds — should route to captured view
		ctx.ProcessMouseDown(150, 150, .Left);
		Test.Assert(child.MouseDownCalled);
	}

	[Test]
	public static void ReleaseCapture_RestoresNormalRouting()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(50, 50);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Capture
		ctx.FocusManager.SetCapture(child);
		Test.Assert(ctx.FocusManager.CapturedView == child);

		// Release
		ctx.FocusManager.ReleaseCapture();
		Test.Assert(ctx.FocusManager.CapturedView == null);

		child.ClearFlags();

		// Move far from child — should NOT route to child anymore
		// (root will be hit instead since mouse is within root bounds but outside child)
		ctx.ProcessMouseMove(150, 150);
		Test.Assert(!child.MouseMoveCalled);
	}

	[Test]
	public static void OnElementDeleted_ClearsCapture()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(50, 50);
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.FocusManager.SetCapture(child);
		Test.Assert(ctx.FocusManager.CapturedView == child);

		ctx.FocusManager.OnElementDeleted(child);
		Test.Assert(ctx.FocusManager.CapturedView == null);
	}

	[Test]
	public static void Capture_DragScenario()
	{
		// Simulate a drag: mousedown → capture → move outside → mouseup → release
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let child = new InputTestView(50, 50);
		child.Focusable = true;
		root.AddView(child);
		let rootView = SetupContext(ctx, root, 200, 200);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Mouse down on child
		ctx.ProcessMouseDown(25, 25, .Left);
		Test.Assert(child.MouseDownCalled);
		Test.Assert(child.IsPressed);

		// Capture the view (as a real control would do in its OnMouseDown)
		ctx.FocusManager.SetCapture(child);

		child.ClearFlags();

		// Drag outside child bounds
		ctx.ProcessMouseMove(150, 150);
		Test.Assert(child.MouseMoveCalled);

		child.ClearFlags();

		// Mouse up (still captured)
		ctx.ProcessMouseUp(150, 150, .Left);
		Test.Assert(child.MouseUpCalled);

		// Release capture
		ctx.FocusManager.ReleaseCapture();
		Test.Assert(ctx.FocusManager.CapturedView == null);
	}
}

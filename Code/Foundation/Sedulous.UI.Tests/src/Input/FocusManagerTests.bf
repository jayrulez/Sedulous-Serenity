using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class FocusManagerTests
{
	//==========================================================================
	// SetFocus / ClearFocus
	//==========================================================================

	[Test]
	public static void SetFocus_FiresGainedEvent()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let view = new InputTestView();
		view.Focusable = true;
		root.AddView(view);

		ctx.FocusManager.SetFocus(view);

		Test.Assert(view.FocusGainedCalled);
		Test.Assert(!view.FocusLostCalled);
		Test.Assert(view.IsFocused);
		Test.Assert(ctx.FocusManager.FocusedView == view);
	}

	[Test]
	public static void SetFocus_ChangeFocus_FiresLostThenGained()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let viewA = new InputTestView();
		viewA.Focusable = true;
		root.AddView(viewA);

		let viewB = new InputTestView();
		viewB.Focusable = true;
		root.AddView(viewB);

		ctx.FocusManager.SetFocus(viewA);
		Test.Assert(viewA.IsFocused);

		// Clear flags to check new events
		viewA.ClearFlags();
		viewB.ClearFlags();

		ctx.FocusManager.SetFocus(viewB);

		Test.Assert(viewA.FocusLostCalled);
		Test.Assert(!viewA.IsFocused);
		Test.Assert(viewB.FocusGainedCalled);
		Test.Assert(viewB.IsFocused);
		Test.Assert(ctx.FocusManager.FocusedView == viewB);
	}

	[Test]
	public static void SetFocus_SameView_NoEvent()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let view = new InputTestView();
		view.Focusable = true;
		root.AddView(view);

		ctx.FocusManager.SetFocus(view);
		view.ClearFlags();

		// Setting same focus again should not fire events
		ctx.FocusManager.SetFocus(view);
		Test.Assert(!view.FocusGainedCalled);
		Test.Assert(!view.FocusLostCalled);
	}

	[Test]
	public static void ClearFocus_FiresLostEvent()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let view = new InputTestView();
		view.Focusable = true;
		root.AddView(view);

		ctx.FocusManager.SetFocus(view);
		view.ClearFlags();

		ctx.FocusManager.ClearFocus();

		Test.Assert(view.FocusLostCalled);
		Test.Assert(!view.IsFocused);
		Test.Assert(ctx.FocusManager.FocusedView == null);
	}

	//==========================================================================
	// Tab Navigation
	//==========================================================================

	[Test]
	public static void FocusNext_CyclesForward_TreeOrder()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// All TabIndex=0 (default) — should follow tree order
		let a = new InputTestView(); a.Focusable = true;
		let b = new InputTestView(); b.Focusable = true;
		let c = new InputTestView(); c.Focusable = true;
		root.AddView(a);
		root.AddView(b);
		root.AddView(c);

		// No focus yet — FocusNext should focus first in tree
		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == a);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == b);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == c);

		// Wrap around
		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == a);
	}

	[Test]
	public static void FocusPrevious_CyclesBackward_TreeOrder()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let a = new InputTestView(); a.Focusable = true;
		let b = new InputTestView(); b.Focusable = true;
		let c = new InputTestView(); c.Focusable = true;
		root.AddView(a);
		root.AddView(b);
		root.AddView(c);

		// No focus — FocusPrevious should focus last in tree
		ctx.FocusManager.FocusPrevious();
		Test.Assert(ctx.FocusManager.FocusedView == c);

		ctx.FocusManager.FocusPrevious();
		Test.Assert(ctx.FocusManager.FocusedView == b);

		ctx.FocusManager.FocusPrevious();
		Test.Assert(ctx.FocusManager.FocusedView == a);

		// Wrap around
		ctx.FocusManager.FocusPrevious();
		Test.Assert(ctx.FocusManager.FocusedView == c);
	}

	[Test]
	public static void FocusNext_PositiveTabIndex_ComesBeforeZero()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Tree order: natural, explicit1, natural2 — but positive TabIndex comes first
		let natural1 = new InputTestView(); natural1.Focusable = true; // TabIndex=0
		let explicit1 = new InputTestView(); explicit1.Focusable = true; explicit1.TabIndex = 1;
		let natural2 = new InputTestView(); natural2.Focusable = true; // TabIndex=0
		root.AddView(natural1);
		root.AddView(explicit1);
		root.AddView(natural2);

		// HTML model: explicit1 (TabIndex=1) first, then natural1, natural2 in tree order
		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == explicit1);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == natural1);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == natural2);
	}

	[Test]
	public static void FocusNext_PositiveTabIndex_SortedByValue()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Added in reverse order, but should sort by TabIndex
		let high = new InputTestView(); high.Focusable = true; high.TabIndex = 10;
		let low = new InputTestView(); low.Focusable = true; low.TabIndex = 1;
		let mid = new InputTestView(); mid.Focusable = true; mid.TabIndex = 5;
		root.AddView(high);
		root.AddView(low);
		root.AddView(mid);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == low);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == mid);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == high);
	}

	[Test]
	public static void FocusNext_SkipsNonFocusable()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let a = new InputTestView(); a.Focusable = true;
		let skip = new InputTestView(); skip.Focusable = false;
		let b = new InputTestView(); b.Focusable = true;
		root.AddView(a);
		root.AddView(skip);
		root.AddView(b);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == a);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == b);
	}

	[Test]
	public static void FocusNext_SkipsNotTabStop()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let a = new InputTestView(); a.Focusable = true;
		let skip = new InputTestView(); skip.Focusable = true; skip.IsTabStop = false;
		let b = new InputTestView(); b.Focusable = true;
		root.AddView(a);
		root.AddView(skip);
		root.AddView(b);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == a);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == b);
	}

	[Test]
	public static void FocusNext_SkipsInvisible()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let a = new InputTestView(); a.Focusable = true;
		let hidden = new InputTestView(); hidden.Focusable = true; hidden.Visibility = .Gone;
		let b = new InputTestView(); b.Focusable = true;
		root.AddView(a);
		root.AddView(hidden);
		root.AddView(b);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == a);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == b);
	}

	[Test]
	public static void FocusNext_SkipsDisabled()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let a = new InputTestView(); a.Focusable = true;
		let disabled = new InputTestView(); disabled.Focusable = true; disabled.Enabled = false;
		let b = new InputTestView(); b.Focusable = true;
		root.AddView(a);
		root.AddView(disabled);
		root.AddView(b);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == a);

		ctx.FocusManager.FocusNext();
		Test.Assert(ctx.FocusManager.FocusedView == b);
	}

	//==========================================================================
	// OnElementDeleted
	//==========================================================================

	[Test]
	public static void OnElementDeleted_ClearsFocus()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let view = new InputTestView();
		view.Focusable = true;
		root.AddView(view);

		ctx.FocusManager.SetFocus(view);
		Test.Assert(ctx.FocusManager.FocusedView == view);

		ctx.FocusManager.OnElementDeleted(view);
		Test.Assert(ctx.FocusManager.FocusedView == null);
	}

	[Test]
	public static void OnElementDeleted_ClearsCapture()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let rootView = TestHelper.SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		let view = new InputTestView();
		root.AddView(view);

		ctx.FocusManager.SetCapture(view);
		Test.Assert(ctx.FocusManager.CapturedView == view);

		ctx.FocusManager.OnElementDeleted(view);
		Test.Assert(ctx.FocusManager.CapturedView == null);
	}
}

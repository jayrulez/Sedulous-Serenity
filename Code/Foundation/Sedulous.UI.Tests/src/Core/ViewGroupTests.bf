using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

/// A concrete ViewGroup for testing (simple stacking like FrameLayout).
class TestViewGroup : ViewGroup
{
	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float maxW = 0, maxH = 0;
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;
			MeasureChild(child, widthSpec, heightSpec);
			maxW = Math.Max(maxW, child.MeasuredWidth);
			maxH = Math.Max(maxH, child.MeasuredHeight);
		}
		SetMeasuredDimension(
			widthSpec.Resolve(maxW + Padding.Horizontal, MinWidth, MaxWidth),
			heightSpec.Resolve(maxH + Padding.Vertical, MinHeight, MaxHeight)
		);
	}

	protected override void OnLayout(float width, float height)
	{
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;
			let lp = child.LayoutParams;
			float ml = (lp != null) ? lp.Margin.Left : 0;
			float mt = (lp != null) ? lp.Margin.Top : 0;
			child.Layout(Padding.Left + ml, Padding.Top + mt, child.MeasuredWidth, child.MeasuredHeight);
		}
	}
}

class ViewGroupTests
{
	[Test]
	public static void AddView_IncreasesChildCount()
	{
		let group = scope TestViewGroup();
		Test.Assert(group.ChildCount == 0);

		let child = new TestView(50, 50);
		group.AddView(child);
		Test.Assert(group.ChildCount == 1);
	}

	[Test]
	public static void AddView_SetsParent()
	{
		let group = scope TestViewGroup();
		let child = new TestView();
		group.AddView(child);
		Test.Assert(child.Parent == group);
	}

	[Test]
	public static void AddView_NullChild_Ignored()
	{
		let group = scope TestViewGroup();
		group.AddView(null);
		Test.Assert(group.ChildCount == 0);
	}

	[Test]
	public static void AddView_AlreadyParented_Ignored()
	{
		let group1 = scope TestViewGroup();
		let group2 = scope TestViewGroup();
		let child = new TestView();
		group1.AddView(child);
		group2.AddView(child); // Should be ignored — already has parent
		Test.Assert(group1.ChildCount == 1);
		Test.Assert(group2.ChildCount == 0);
		Test.Assert(child.Parent == group1);
	}

	[Test]
	public static void GetChildAt_ReturnsCorrectChild()
	{
		let group = scope TestViewGroup();
		let a = new TestView();
		let b = new TestView();
		group.AddView(a);
		group.AddView(b);
		Test.Assert(group.GetChildAt(0) == a);
		Test.Assert(group.GetChildAt(1) == b);
	}

	[Test]
	public static void GetChildAt_OutOfRange_ReturnsNull()
	{
		let group = scope TestViewGroup();
		Test.Assert(group.GetChildAt(-1) == null);
		Test.Assert(group.GetChildAt(0) == null);
		Test.Assert(group.GetChildAt(100) == null);
	}

	[Test]
	public static void RemoveView_RemovesAndDeletesChild()
	{
		let group = scope TestViewGroup();
		let child = new TestView();
		group.AddView(child);
		Test.Assert(group.ChildCount == 1);

		group.RemoveView(child);
		Test.Assert(group.ChildCount == 0);
		// child is now deleted — we can't access it, but count verifies removal
	}

	[Test]
	public static void RemoveViewAt_RemovesCorrectChild()
	{
		let group = scope TestViewGroup();
		let a = new TestView();
		let b = new TestView();
		let bId = b.Id;
		group.AddView(a);
		group.AddView(b);

		group.RemoveViewAt(0); // removes 'a'
		Test.Assert(group.ChildCount == 1);
		Test.Assert(group.GetChildAt(0).Id == bId);
	}

	[Test]
	public static void RemoveAllViews_ClearsAll()
	{
		let group = scope TestViewGroup();
		group.AddView(new TestView());
		group.AddView(new TestView());
		group.AddView(new TestView());
		Test.Assert(group.ChildCount == 3);

		group.RemoveAllViews();
		Test.Assert(group.ChildCount == 0);
	}

	[Test]
	public static void DetachView_RemovesWithoutDelete()
	{
		let group = scope TestViewGroup();
		let child = new TestView();
		let childId = child.Id;
		group.AddView(child);

		let detached = group.DetachView(child);
		Test.Assert(group.ChildCount == 0);
		Test.Assert(detached != null);
		Test.Assert(detached.Id == childId);
		Test.Assert(detached.Parent == null);

		// Caller must delete
		delete detached;
	}

	[Test]
	public static void DetachView_WrongParent_ReturnsNull()
	{
		let group1 = scope TestViewGroup();
		let group2 = scope TestViewGroup();
		let child = new TestView();
		group1.AddView(child);

		let result = group2.DetachView(child);
		Test.Assert(result == null);
		Test.Assert(group1.ChildCount == 1);
	}

	[Test]
	public static void InsertView_AtIndex()
	{
		let group = scope TestViewGroup();
		let a = new TestView();
		let b = new TestView();
		let c = new TestView();
		let cId = c.Id;

		group.AddView(a);
		group.AddView(b);
		group.InsertView(c, 1); // Insert between a and b

		Test.Assert(group.ChildCount == 3);
		Test.Assert(group.GetChildAt(0) == a);
		Test.Assert(group.GetChildAt(1).Id == cId);
		Test.Assert(group.GetChildAt(2) == b);
	}

	[Test]
	public static void HitTest_ReturnsDeepestChild()
	{
		let group = scope TestViewGroup();
		let child = new TestView(50, 50);
		group.AddView(child);

		group.Measure(.MakeExactly(200), .MakeExactly(200));
		group.Layout(0, 0, 200, 200);

		// Hit inside child
		let hit = group.HitTest(.(25, 25));
		Test.Assert(hit == child);
	}

	[Test]
	public static void HitTest_ReversOrder_TopmostFirst()
	{
		let group = scope TestViewGroup();
		let a = new TestView(100, 100);
		let b = new TestView(100, 100);
		group.AddView(a);
		group.AddView(b);

		group.Measure(.MakeExactly(200), .MakeExactly(200));
		group.Layout(0, 0, 200, 200);

		// Both overlap at (25, 25). 'b' is last added (topmost), should be hit
		let hit = group.HitTest(.(25, 25));
		Test.Assert(hit == b);
	}

	[Test]
	public static void HitTest_MissChildren_ReturnsSelf()
	{
		let group = scope TestViewGroup();
		let child = new TestView(50, 50);
		let lp = new LayoutParams(50, 50);
		child.LayoutParams = lp;
		group.AddView(child);

		group.Measure(.MakeExactly(200), .MakeExactly(200));
		group.Layout(0, 0, 200, 200);

		// Point outside child but inside group
		let hit = group.HitTest(.(150, 150));
		Test.Assert(hit == group);
	}

	[Test]
	public static void FindViewByTag_FindsChild()
	{
		let group = scope TestViewGroup();
		let child = new TestView();
		child.Tag = new String("my-tag");
		group.AddView(child);

		let found = group.FindViewByTag("my-tag");
		Test.Assert(found == child);
	}

	[Test]
	public static void FindViewByTag_NotFound_ReturnsNull()
	{
		let group = scope TestViewGroup();
		let child = new TestView();
		group.AddView(child);

		Test.Assert(group.FindViewByTag("nonexistent") == null);
	}

	[Test]
	public static void Destructor_DeletesChildren()
	{
		// Create a group on heap, add children, delete it
		// If children are properly deleted, no leak occurs.
		// We can't directly verify deletion, but this tests no crash.
		let group = new TestViewGroup();
		group.AddView(new TestView());
		group.AddView(new TestView());
		delete group;
	}

	[Test]
	public static void LifecycleCallbacks_PropagateToChildren()
	{
		let ctx = scope UIContext();
		let group = scope TestViewGroup();
		let child = new TestView();
		group.AddView(child);

		// Attach to context
		group.OnAttachedToContext(ctx);
		Test.Assert(child.Context == ctx);
		Test.Assert(ctx.GetElementById(child.Id) == child);

		// Detach from context
		group.OnDetachedFromContext(ctx);
		Test.Assert(child.Context == null);
		Test.Assert(ctx.GetElementById(child.Id) == null);
	}

	[Test]
	public static void AddView_WithLayoutParams()
	{
		let group = scope TestViewGroup();
		let child = new TestView();
		let lp = new LayoutParams(100, 50);
		group.AddView(child, lp);

		Test.Assert(child.LayoutParams != null);
		Test.Assert(child.LayoutParams.Width == 100);
		Test.Assert(child.LayoutParams.Height == 50);
	}
}

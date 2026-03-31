using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class MutationQueueTests
{
	[Test]
	public static void New_NoPending()
	{
		let queue = scope MutationQueue();
		Test.Assert(!queue.HasPending);
	}

	[Test]
	public static void QueueAddChild_AddsPending()
	{
		let queue = scope MutationQueue();
		let parent = scope TestViewGroup();
		let child = scope TestView();
		queue.QueueAddChild(parent, child);
		Test.Assert(queue.HasPending);
	}

	[Test]
	public static void Process_AddChild_AddsToParent()
	{
		let ctx = scope UIContext();
		let queue = scope MutationQueue();
		let parent = scope TestViewGroup();
		let child = new TestView();
		parent.OnAttachedToContext(ctx);

		queue.QueueAddChild(parent, child);
		queue.Process(ctx);

		Test.Assert(parent.ChildCount == 1);
		Test.Assert(parent.GetChildAt(0) == child);
		Test.Assert(!queue.HasPending);
	}

	[Test]
	public static void Process_RemoveChild_RemovesFromParent()
	{
		let ctx = scope UIContext();
		let queue = scope MutationQueue();
		let parent = scope TestViewGroup();
		let child = new TestView();
		parent.OnAttachedToContext(ctx);
		parent.[Friend]AddViewInternal(child);
		Test.Assert(parent.ChildCount == 1);

		queue.QueueRemoveChild(parent, child, deleteAfterRemove: true);
		queue.Process(ctx);

		Test.Assert(parent.ChildCount == 0);
	}

	[Test]
	public static void QueueDelete_MarksIsPendingDeletion()
	{
		let queue = scope MutationQueue();
		let view = new TestView();
		Test.Assert(!view.IsPendingDeletion);

		queue.QueueDelete(view);
		Test.Assert(view.IsPendingDeletion);

		// Process to actually delete
		let ctx = scope UIContext();
		queue.Process(ctx);
	}

	[Test]
	public static void Process_Delete_RemovesFromParentAndDeletes()
	{
		let ctx = scope UIContext();
		let queue = scope MutationQueue();
		let parent = scope TestViewGroup();
		let child = new TestView();
		parent.OnAttachedToContext(ctx);
		parent.[Friend]AddViewInternal(child);

		queue.QueueDelete(child);
		Test.Assert(parent.ChildCount == 1); // Still there before processing
		Test.Assert(child.IsPendingDeletion);

		queue.Process(ctx);
		Test.Assert(parent.ChildCount == 0); // Removed and deleted
	}

	[Test]
	public static void QueueDelete_AlreadyPending_Ignored()
	{
		let queue = scope MutationQueue();
		let view = new TestView();
		queue.QueueDelete(view);
		queue.QueueDelete(view); // Should not double-queue

		let ctx = scope UIContext();
		queue.Process(ctx);
		// If it double-deleted, we'd crash. No crash = pass.
	}

	[Test]
	public static void QueueAction_ExecutesOnProcess()
	{
		let queue = scope MutationQueue();
		var executed = false;
		queue.QueueAction(new [&executed]() => { executed = true; });
		Test.Assert(!executed);

		let ctx = scope UIContext();
		queue.Process(ctx);
		Test.Assert(executed);
	}

	[Test]
	public static void Process_ClearsPending()
	{
		let ctx = scope UIContext();
		let queue = scope MutationQueue();
		queue.QueueAction(new () => { });
		Test.Assert(queue.HasPending);

		queue.Process(ctx);
		Test.Assert(!queue.HasPending);
	}

	[Test]
	public static void QueueNull_Ignored()
	{
		let queue = scope MutationQueue();
		queue.QueueAddChild(null, null);
		queue.QueueRemoveChild(null, null);
		queue.QueueDelete(null);
		queue.QueueAction(null);
		Test.Assert(!queue.HasPending);
	}
}

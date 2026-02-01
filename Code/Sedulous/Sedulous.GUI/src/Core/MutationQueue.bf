using System;
using System.Collections;

namespace Sedulous.GUI;

/// Type of tree mutation.
public enum MutationType
{
	/// Add a child to a container.
	AddChild,
	/// Remove a child from a container (optionally delete).
	RemoveChild,
	/// Delete an element.
	DeleteElement
}

/// Represents a pending tree mutation.
public struct Mutation
{
	public MutationType Type;
	public UIElement Target;
	public UIElement Child;
	public bool DeleteAfterRemove;
}

/// Queue for deferred tree mutations.
/// All tree modifications (add/remove/delete) are queued during event processing
/// and applied at the end of the frame to prevent crashes from modifications
/// during iteration or event handling.
public class MutationQueue
{
	private List<Mutation> mPending = new .() ~ delete _;
	private List<delegate void()> mQueuedActions = new .() ~ DeleteContainerAndItems!(_);
	private bool mProcessing = false;

	/// Whether mutations are currently being processed.
	public bool IsProcessing => mProcessing;

	/// Number of pending mutations.
	public int Count => mPending.Count;

	/// Queue adding a child to a container.
	/// The child will be added when Process() is called.
	public void QueueAddChild(UIElement parent, UIElement child)
	{
		mPending.Add(.()
		{
			Type = .AddChild,
			Target = parent,
			Child = child,
			DeleteAfterRemove = false
		});
	}

	/// Queue removing a child from a container.
	/// If deleteAfterRemove is true, the child will be deleted after removal.
	public void QueueRemoveChild(UIElement parent, UIElement child, bool deleteAfterRemove = true)
	{
		mPending.Add(.()
		{
			Type = .RemoveChild,
			Target = parent,
			Child = child,
			DeleteAfterRemove = deleteAfterRemove
		});
	}

	/// Queue deleting an element.
	/// The element will be removed from its parent and deleted when Process() is called.
	public void QueueDelete(UIElement element)
	{
		if (element == null)
			return;

		// Mark as pending deletion immediately
		element.[Friend]mIsPendingDeletion = true;

		mPending.Add(.()
		{
			Type = .DeleteElement,
			Target = element,
			Child = null,
			DeleteAfterRemove = true
		});
	}

	/// Queue an action to be executed at the end of the frame.
	/// Useful for deferring operations that would cause use-after-free if executed immediately.
	public void QueueAction(delegate void() action)
	{
		if (action != null)
			mQueuedActions.Add(action);
	}

	/// Process all pending mutations.
	/// Called at the end of each frame by GUIContext.
	public void Process(GUIContext context)
	{
		if (mPending.Count == 0)
			return;

		mProcessing = true;

		for (let mutation in mPending)
		{
			// Skip if target is already pending deletion (except for DeleteElement)
			if (mutation.Type != .DeleteElement && mutation.Target.IsPendingDeletion)
				continue;

			switch (mutation.Type)
			{
			case .AddChild:
				// Skip if child is already pending deletion
				if (mutation.Child != null && !mutation.Child.IsPendingDeletion)
				{
					mutation.Target.TryAddChild(mutation.Child);
				}

			case .RemoveChild:
				if (mutation.Child != null)
				{
					// Detach the child from its parent
					let detached = mutation.Target.TryDetachChild(mutation.Child);

					// If deletion requested and detachment succeeded
					if (mutation.DeleteAfterRemove && detached != null)
					{
						context.OnElementDeleted(detached);
						context.UnregisterElement(detached);
						delete detached;
					}
				}

			case .DeleteElement:
				if (mutation.Target != null)
				{
					// Notify context so input/focus managers can clear references
					context.OnElementDeleted(mutation.Target);

					// Clear root element reference if this is the root
					if (context.[Friend]mRootElement == mutation.Target)
					{
						context.[Friend]mRootElement = null;
					}

					// Remove from parent if any
					if (mutation.Target.Parent != null)
					{
						mutation.Target.DetachFromParent();
					}

					context.UnregisterElement(mutation.Target);
					delete mutation.Target;
				}
			}
		}

		mPending.Clear();

		// Execute queued actions after mutations are processed
		for (let action in mQueuedActions)
		{
			action();
			delete action;
		}
		mQueuedActions.Clear();

		mProcessing = false;
	}

	/// Clear all pending mutations without processing them.
	public void Clear()
	{
		mPending.Clear();
		DeleteContainerAndItems!(mQueuedActions);
		mQueuedActions = new .();
	}
}

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
				// TODO: Implement when Container class is added
				break;

			case .RemoveChild:
				// TODO: Implement when Container class is added
				if (mutation.DeleteAfterRemove && mutation.Child != null)
				{
					context.UnregisterElement(mutation.Child);
					delete mutation.Child;
				}

			case .DeleteElement:
				if (mutation.Target != null)
				{
					// Clear root element reference if this is the root
					if (context.[Friend]mRootElement == mutation.Target)
					{
						context.[Friend]mRootElement = null;
					}

					// Remove from parent if any
					if (mutation.Target.Parent != null)
					{
						// TODO: Implement parent removal when Container class is added
					}

					context.UnregisterElement(mutation.Target);
					delete mutation.Target;
				}
			}
		}

		mPending.Clear();
		mProcessing = false;
	}

	/// Clear all pending mutations without processing them.
	public void Clear()
	{
		mPending.Clear();
	}
}

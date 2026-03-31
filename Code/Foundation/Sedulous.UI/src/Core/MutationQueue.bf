namespace Sedulous.UI;

using System;
using System.Collections;

/// Type of deferred tree mutation.
public enum MutationType
{
	AddChild,
	RemoveChild,
	DeleteElement
}

/// A deferred tree mutation.
public struct Mutation
{
	public MutationType Type;
	public ViewId TargetId;
	public ViewId ChildId;
	public ViewGroup Target;
	public View Child;
	public bool DeleteAfterRemove;
}

/// Defers tree mutations (add/remove/delete) to the end of a frame.
/// This prevents use-after-free when events trigger tree modifications
/// while the tree is being iterated (e.g., during input routing).
public class MutationQueue
{
	private List<Mutation> mPending = new .() ~ delete _;
	private List<delegate void()> mDeferredActions = new .() ~ delete _;
	private HashSet<ViewId> mDeletedThisFrame = new .() ~ delete _;

	/// Queue adding a child to a parent.
	public void QueueAddChild(ViewGroup parent, View child)
	{
		if (parent == null || child == null)
			return;

		Mutation m = .();
		m.Type = .AddChild;
		m.TargetId = parent.Id;
		m.ChildId = child.Id;
		m.Target = parent;
		m.Child = child;
		mPending.Add(m);
	}

	/// Queue removing a child from a parent.
	/// If deleteAfterRemove is true, the child will be deleted after removal.
	public void QueueRemoveChild(ViewGroup parent, View child, bool deleteAfterRemove = false)
	{
		if (parent == null || child == null)
			return;

		Mutation m = .();
		m.Type = .RemoveChild;
		m.TargetId = parent.Id;
		m.ChildId = child.Id;
		m.Target = parent;
		m.Child = child;
		m.DeleteAfterRemove = deleteAfterRemove;
		mPending.Add(m);
	}

	/// Queue deletion of an element.
	/// Marks IsPendingDeletion immediately so handles and input skip it.
	public void QueueDelete(View element)
	{
		if (element == null || element.IsPendingDeletion)
			return;

		element.[Friend]mIsPendingDeletion = true;

		Mutation m = .();
		m.Type = .DeleteElement;
		m.TargetId = (element.Parent != null) ? element.Parent.Id : .Invalid;
		m.ChildId = element.Id;
		m.Target = element.Parent as ViewGroup;
		m.Child = element;
		mPending.Add(m);
	}

	/// Queue an arbitrary deferred action to run at end of frame.
	public void QueueAction(delegate void() action)
	{
		if (action != null)
			mDeferredActions.Add(action);
	}

	/// Process all pending mutations. Call at the end of each frame.
	public void Process(UIContext context)
	{
		mDeletedThisFrame.Clear();

		// Process structural mutations
		for (let m in mPending)
		{
			// Skip if the element was already deleted this frame
			if (mDeletedThisFrame.Contains(m.ChildId))
				continue;

			switch (m.Type)
			{
			case .AddChild:
				if (m.Target != null && m.Child != null && !m.Child.IsPendingDeletion)
				{
					m.Target.[Friend]AddViewInternal(m.Child);
				}

			case .RemoveChild:
				if (m.Target != null && m.Child != null)
				{
					m.Target.[Friend]RemoveViewInternal(m.Child);
					if (m.DeleteAfterRemove)
					{
						mDeletedThisFrame.Add(m.ChildId);
						context?.NotifyElementDeleted(m.Child);
						context?.UnregisterElement(m.Child);
						delete m.Child;
					}
				}

			case .DeleteElement:
				if (m.Child != null)
				{
					mDeletedThisFrame.Add(m.ChildId);
					// Remove from parent if it has one
					if (m.Target != null)
						m.Target.[Friend]RemoveViewInternal(m.Child);
					context?.NotifyElementDeleted(m.Child);
					context?.UnregisterElement(m.Child);
					delete m.Child;
				}
			}
		}
		mPending.Clear();

		// Process deferred actions
		for (let action in mDeferredActions)
		{
			action();
			delete action;
		}
		mDeferredActions.Clear();
	}

	/// Whether there are pending mutations.
	public bool HasPending => mPending.Count > 0 || mDeferredActions.Count > 0;
}

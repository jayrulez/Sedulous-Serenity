namespace Sedulous.UI;

/// Safe weak reference to a View.
/// Stores the ViewId and resolves through the UIContext's element registry.
/// If the referenced View has been deleted, TryResolve returns null.
public struct ElementHandle<T> where T : View
{
	private ViewId mId;

	public this(T view)
	{
		mId = (view != null) ? view.Id : .Invalid;
	}

	public this(ViewId id)
	{
		mId = id;
	}

	/// The stored ViewId.
	public ViewId Id => mId;

	/// Whether this handle was assigned (does not guarantee the view still exists).
	public bool IsValid => mId.IsValid;

	/// Attempt to resolve the handle to a live View.
	/// Returns null if the view has been deleted or is pending deletion.
	public T TryResolve(UIContext context)
	{
		if (!mId.IsValid || context == null)
			return null;

		let view = context.GetElementById(mId);
		if (view == null || view.IsPendingDeletion)
			return null;

		return view as T;
	}

	/// Clear this handle.
	public void Clear() mut
	{
		mId = .Invalid;
	}

	/// Create a handle from a View (implicit conversion).
	public static implicit operator ElementHandle<T>(T view)
	{
		return .(view);
	}

	public static readonly ElementHandle<T> Empty = .(.Invalid);
}

/// Non-generic ElementHandle for general use.
public typealias ViewHandle = ElementHandle<View>;

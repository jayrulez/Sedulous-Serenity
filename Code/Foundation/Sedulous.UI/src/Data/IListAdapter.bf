namespace Sedulous.UI;

using System;
using System.Collections;

/// Callback interface for adapter data change notifications.
public interface IAdapterObserver
{
	void OnDataChanged();
}

/// Adapter that provides data items to a ListView.
public interface IListAdapter
{
	/// Total number of items in the data set.
	int ItemCount { get; }

	/// Return a view type identifier for the item at position.
	int32 GetItemViewType(int position);

	/// Create a new View for the given view type.
	/// The caller takes ownership of the returned view.
	View CreateView(int32 viewType);

	/// Bind data at position to an existing view (possibly recycled).
	void BindView(View view, int position);

	/// Register an observer to be notified on data changes.
	void RegisterObserver(IAdapterObserver observer);

	/// Unregister a previously registered observer.
	void UnregisterObserver(IAdapterObserver observer);
}

/// Convenience base class with default GetItemViewType and observer management.
public abstract class ListAdapter : IListAdapter
{
	private List<IAdapterObserver> mObservers = new .() ~ delete _;

	public abstract int ItemCount { get; }

	public virtual int32 GetItemViewType(int position) => 0;

	public abstract View CreateView(int32 viewType);

	public abstract void BindView(View view, int position);

	public void RegisterObserver(IAdapterObserver observer)
	{
		if (!mObservers.Contains(observer))
			mObservers.Add(observer);
	}

	public void UnregisterObserver(IAdapterObserver observer)
	{
		mObservers.Remove(observer);
	}

	/// Call this when data changes to notify all observers.
	public void NotifyDataChanged()
	{
		for (let obs in mObservers)
			obs.OnDataChanged();
	}
}

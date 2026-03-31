namespace Sedulous.UI;

using System;

/// Adapter for hierarchical (tree) data.
/// Manages its own flattened list of visible nodes.
/// When ToggleExpand is called, the adapter updates its internal flat list
/// and calls NotifyDataChanged() to inform observers.
public interface ITreeAdapter
{
	/// Total number of visible nodes (expanded tree flattened).
	int ItemCount { get; }

	/// Depth of the node at flat position (0 = root level).
	int GetDepth(int position);

	/// Whether the node at position has children.
	bool HasChildren(int position);

	/// Whether the node at position is currently expanded.
	bool IsExpanded(int position);

	/// Toggle the expand/collapse state at position.
	/// After this call, ItemCount and positions may change.
	void ToggleExpand(int position);

	/// Get the view type for position (for recycling purposes).
	int32 GetItemViewType(int position);

	/// Create a view for the given type.
	View CreateView(int32 viewType);

	/// Bind data at position to a view.
	void BindView(View view, int position);

	/// Register data change observer.
	void RegisterObserver(IAdapterObserver observer);

	/// Unregister observer.
	void UnregisterObserver(IAdapterObserver observer);
}

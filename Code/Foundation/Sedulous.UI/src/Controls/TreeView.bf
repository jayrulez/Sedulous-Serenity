namespace Sedulous.UI;

using System;
using Sedulous.Core;

/// A tree view that displays hierarchical data with expand/collapse.
/// Internally uses a ListView with a FlattenedTreeAdapter.
public class TreeView : ViewGroup
{
	private ListView mListView; // Owned by ViewGroup (added as child)
	private FlattenedTreeAdapter mFlatAdapter ~ delete _;
	private ITreeAdapter mTreeAdapter;

	private EventAccessor<delegate void(TreeView, int)> mOnItemClick = new .() ~ delete _;
	private EventAccessor<delegate void(TreeView, int)> mOnNodeToggled = new .() ~ delete _;

	/// Subscribe to item click events (flat position).
	public EventAccessor<delegate void(TreeView, int)> OnItemClick => mOnItemClick;

	/// Subscribe to node expand/collapse events (flat position).
	public EventAccessor<delegate void(TreeView, int)> OnNodeToggled => mOnNodeToggled;

	/// Access the selection model from the internal ListView.
	public SelectionModel SelectionModel => mListView?.SelectionModel;

	/// Indent per depth level in pixels.
	public float IndentPerDepth = 20;

	/// Fixed item height (passed through to ListView).
	public float FixedItemHeight
	{
		get => mListView.FixedItemHeight;
		set { mListView.FixedItemHeight = value; }
	}

	/// Access the underlying tree adapter.
	public ITreeAdapter TreeAdapter => mTreeAdapter;

	public this()
	{
		mListView = new ListView();
		AddView(mListView, new LayoutParams(Sedulous.UI.LayoutParams.MatchParent, Sedulous.UI.LayoutParams.MatchParent));
		mListView.OnItemClick.Subscribe(new => OnListItemClick);
	}

	/// Set the tree adapter. The TreeView does not take ownership.
	/// Pass null to detach.
	public void SetAdapter(ITreeAdapter adapter)
	{
		mTreeAdapter = adapter;

		mListView.SetAdapter(null); // Detach before deleting old adapter
		delete mFlatAdapter;

		if (adapter != null)
		{
			mFlatAdapter = new FlattenedTreeAdapter(adapter, IndentPerDepth);
			ApplyThemeToAdapter();
			mListView.SetAdapter(mFlatAdapter);
		}
		else
		{
			mFlatAdapter = null;
		}
	}

	/// Apply theme icons or text symbols to the flat adapter.
	private void ApplyThemeToAdapter()
	{
		if (mFlatAdapter == null) return;

		let theme = Context?.Theme;
		if (theme != null)
		{
			let expandedIcon = theme.GetDrawable("TreeView", "expandedIcon");
			let collapsedIcon = theme.GetDrawable("TreeView", "collapsedIcon");
			if (expandedIcon != null && collapsedIcon != null)
			{
				mFlatAdapter.SetIcons(expandedIcon, collapsedIcon);
				return;
			}

			let expanded = theme.GetString("TreeView", "expandedSymbol");
			let collapsed = theme.GetString("TreeView", "collapsedSymbol");
			let leaf = theme.GetString("TreeView", "leafPrefix");
			if (expanded != null && collapsed != null)
			{
				mFlatAdapter.SetSymbols(expanded, collapsed, leaf ?? "  ");
				return;
			}
		}

		// No theme or no tree settings: clear icons, use defaults
		mFlatAdapter.SetIcons(null, null);
	}

	public override void OnThemeChanged()
	{
		base.OnThemeChanged();

		// Rebuild the flat adapter since icon vs text mode may change the view structure
		if (mTreeAdapter != null)
		{
			mListView.SetAdapter(null); // Detach before deleting old adapter
			delete mFlatAdapter;
			mFlatAdapter = new FlattenedTreeAdapter(mTreeAdapter, IndentPerDepth);
			ApplyThemeToAdapter();
			mListView.SetAdapter(mFlatAdapter);
		}
	}

	private void OnListItemClick(ListView lv, int position)
	{
		if (mTreeAdapter == null) return;

		if (mTreeAdapter.HasChildren(position))
		{
			mTreeAdapter.ToggleExpand(position);
			mOnNodeToggled.[Friend]Invoke(this, position);
		}

		mOnItemClick.[Friend]Invoke(this, position);
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (mTreeAdapter == null || mListView == null) return;

		let sel = mListView.SelectionModel;
		if (sel == null || sel.Mode == .None) return;

		int pos = sel.SelectedPosition;
		if (pos < 0 || pos >= mTreeAdapter.ItemCount) return;

		switch (e.Key)
		{
		case .Right:
			if (mTreeAdapter.HasChildren(pos))
			{
				if (!mTreeAdapter.IsExpanded(pos))
				{
					// Expand the node
					mTreeAdapter.ToggleExpand(pos);
					mOnNodeToggled.[Friend]Invoke(this, pos);
				}
				else if (pos + 1 < mTreeAdapter.ItemCount)
				{
					// Already expanded: move to first child
					sel.Select(pos + 1);
					mListView.ScrollToPosition(pos + 1);
					mListView.Invalidate();
				}
			}
			e.Handled = true;
		case .Left:
			if (mTreeAdapter.HasChildren(pos) && mTreeAdapter.IsExpanded(pos))
			{
				// Collapse the node
				mTreeAdapter.ToggleExpand(pos);
				mOnNodeToggled.[Friend]Invoke(this, pos);
			}
			else
			{
				// Move to parent: scan backward for first item with lower depth
				int depth = mTreeAdapter.GetDepth(pos);
				if (depth > 0)
				{
					for (int i = pos - 1; i >= 0; i--)
					{
						if (mTreeAdapter.GetDepth(i) < depth)
						{
							sel.Select(i);
							mListView.ScrollToPosition(i);
							mListView.Invalidate();
							break;
						}
					}
				}
			}
			e.Handled = true;
		default:
		}
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(0, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(0, MinHeight, MaxHeight);

		if (mListView != null)
			mListView.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(h));

		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		if (mListView != null)
			mListView.Layout(0, 0, width, height);
	}
}

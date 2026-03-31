namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// Adapter interface that supports reordering items for DraggableTreeView.
public interface IReorderableTreeAdapter : ITreeAdapter
{
	/// Move an item from one position to another.
	bool MoveItem(int fromPosition, int toPosition);

	/// Check if an item can be moved from one position to another.
	bool CanMove(int fromPosition, int toPosition);
}

/// Drag data carrying a tree item position.
public class TreeDragData : DragData
{
	public int SourcePosition;

	public this(int sourcePosition) : base("tree/reorder")
	{
		SourcePosition = sourcePosition;
	}
}

/// A tree view that supports drag-to-reorder of items.
/// Wraps the core TreeView and adds drag-and-drop via IDragSource/IDropTarget.
public class DraggableTreeView : ViewGroup, IDragSource, IDropTarget
{
	private TreeView mTreeView;
	private bool mDragEnabled = true;
	private int mDropIndicatorPosition = -1;
	private int mDragSourcePosition = -1;

	private EventAccessor<delegate void(DraggableTreeView, int, int)> mOnItemReordered = new .() ~ delete _;

	/// Fired when an item is successfully reordered (from, to).
	public EventAccessor<delegate void(DraggableTreeView, int, int)> OnItemReordered => mOnItemReordered;

	/// Whether drag-to-reorder is enabled.
	public bool DragEnabled { get => mDragEnabled; set { mDragEnabled = value; } }

	/// The internal TreeView.
	public TreeView InternalTreeView => mTreeView;

	public this()
	{
		mTreeView = new TreeView();
		AddView(mTreeView);
	}

	/// Set the tree adapter. Must implement IReorderableTreeAdapter for drag support.
	public void SetAdapter(ITreeAdapter adapter)
	{
		mTreeView.SetAdapter(adapter);
	}

	/// Access the selection model.
	public SelectionModel SelectionModel => mTreeView.SelectionModel;

	/// Item height for the internal list.
	public float FixedItemHeight
	{
		get => mTreeView.FixedItemHeight;
		set { mTreeView.FixedItemHeight = value; }
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float w = widthSpec.Resolve(200, MinWidth, MaxWidth);
		float h = heightSpec.Resolve(150, MinHeight, MaxHeight);
		mTreeView.Measure(MeasureSpec.MakeExactly(w), MeasureSpec.MakeExactly(h));
		SetMeasuredDimension(w, h);
	}

	protected override void OnLayout(float width, float height)
	{
		mTreeView.Layout(0, 0, width, height);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		mTreeView.Draw(ctx);

		// Draw drop indicator line
		if (mDropIndicatorPosition >= 0)
		{
			let theme = Context?.Theme;
			let palette = theme?.Palette ?? Palette.Dark;
			let indicatorColor = theme?.GetColor("DraggableTreeView", "dropIndicator") ?? palette.Accent;

			float itemH = mTreeView.FixedItemHeight;
			float y = mDropIndicatorPosition * itemH;
			ctx.FillRect(.(0, y - 1, Width, 3), indicatorColor);
		}
	}

	// ===== IDragSource =====

	public DragData CreateDragData()
	{
		if (!mDragEnabled) return null;

		let selection = mTreeView.SelectionModel;
		if (selection == null) return null;
		int selected = selection.SelectedPosition;
		if (selected < 0) return null;

		mDragSourcePosition = selected;
		return new TreeDragData(selected);
	}

	public View CreateDragVisual(DragData data)
	{
		let label = new Label("Moving item");
		label.FontSize = 12;
		label.Padding = .(8, 4, 8, 4);
		label.MinWidth = 80;
		label.MinHeight = 24;
		return label;
	}

	public void OnDragStarted(DragData data)
	{
		Alpha = 0.8f;
	}

	public void OnDragCompleted(DragData data, DragDropEffects effect, bool cancelled)
	{
		Alpha = 1.0f;
		mDragSourcePosition = -1;
		mDropIndicatorPosition = -1;
		Invalidate();
	}

	// ===== IDropTarget =====

	public DragDropEffects CanAcceptDrop(DragData data, float localX, float localY)
	{
		if (data.Format == "tree/reorder")
			return .Move;
		return .None;
	}

	public void OnDragEnter(DragData data, float localX, float localY)
	{
		UpdateDropIndicator(localY);
	}

	public void OnDragOver(DragData data, float localX, float localY)
	{
		UpdateDropIndicator(localY);
	}

	public void OnDragLeave(DragData data)
	{
		mDropIndicatorPosition = -1;
		Invalidate();
	}

	public DragDropEffects OnDrop(DragData data, float localX, float localY)
	{
		if (let treeData = data as TreeDragData)
		{
			int from = treeData.SourcePosition;
			int to = mDropIndicatorPosition;
			mDropIndicatorPosition = -1;

			if (from >= 0 && to >= 0 && from != to)
			{
				if (let adapter = mTreeView.TreeAdapter as IReorderableTreeAdapter)
				{
					if (adapter.CanMove(from, to) && adapter.MoveItem(from, to))
					{
						mOnItemReordered.[Friend]Invoke(this, from, to);
						return .Move;
					}
				}
			}
		}

		mDropIndicatorPosition = -1;
		Invalidate();
		return .None;
	}

	private void UpdateDropIndicator(float localY)
	{
		float itemH = mTreeView.FixedItemHeight;
		if (itemH <= 0) itemH = 22;
		int pos = (int)(localY / itemH);
		if (pos != mDropIndicatorPosition)
		{
			mDropIndicatorPosition = pos;
			Invalidate();
		}
	}
}

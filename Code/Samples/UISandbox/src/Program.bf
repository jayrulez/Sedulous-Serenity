namespace UISandbox;

using System;
using Sedulous.RHI;
using Sedulous.Runtime.Client;

class Program
{
	public static int Main(String[] args)
	{
		let app = scope UISandboxApp();
		return app.Run(.() { Title = "Sedulous.UI Sandbox", Width = 1280, Height = 720, ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f), EnableDepth = false, SwapChainFormat = .BGRA8Unorm });
	}
}

// ===== Beef tuple literal parser bug repro =====
// Returning a tuple with inline multiply expressions fails to parse.
// The compiler misinterprets "VelocityY * dt" as a variable declaration.
// Workaround: compute into locals first, then return the tuple.
struct TupleBugRepro
{
	float VelocityX;
	float VelocityY;

	 /*//BUG: This fails to compile — parser sees "VelocityY * dt" as a var decl
	 public (float dx, float dy) Broken(float dt) mut
	 {
	     return (VelocityX * dt, VelocityY * dt);
	 }*/

	// WORKAROUND: Use locals
	public (float dx, float dy) Working(float dt) mut
	{
		float dx = VelocityX * dt;
		float dy = VelocityY * dt;
		return (dx, dy);
	}
}

using System.Collections;
using Sedulous.UI;
using Sedulous.UI.Toolkit;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Adapter for the ListView demo: 10,000 simple Label items.
class DemoListAdapter : ListAdapter
{
	private int mCount;

	public this(int count) { mCount = count; }

	public override int ItemCount => mCount;

	public override View CreateView(int32 viewType)
	{
		let label = new Label();
		label.Padding = .(8, 2, 8, 2);
		return label;
	}

	public override void BindView(View view, int position)
	{
		if (let label = view as Label)
			label.Text = scope:: $"Item {position + 1} - Recycled list entry";
	}
}

/// Adapter for the TreeView demo: hierarchical categories.
class DemoTreeAdapter : ITreeAdapter
{
	public struct Node
	{
		public String Label;
		public int Depth;
		public bool HasKids;
		public bool Expanded;
		public int ChildCount;
	}

	private List<Node> mVisible = new .() ~ {
		for (var n in _) delete n.Label;
		delete _;
	};
	private List<IAdapterObserver> mObservers = new .() ~ delete _;

	public this()
	{
		for (int i = 0; i < 5; i++)
		{
			Node node;
			node.Label = new $"Category {i + 1}";
			node.Depth = 0;
			node.HasKids = true;
			node.Expanded = false;
			node.ChildCount = 4;
			mVisible.Add(node);
		}
	}

	public int ItemCount => mVisible.Count;
	public int GetDepth(int position) => mVisible[position].Depth;
	public bool HasChildren(int position) => mVisible[position].HasKids;
	public bool IsExpanded(int position) => mVisible[position].Expanded;
	public int32 GetItemViewType(int position) => 0;

	public View CreateView(int32 viewType)
	{
		let label = new Label();
		label.Padding = .(4, 2, 4, 2);
		return label;
	}

	public void BindView(View view, int position)
	{
		if (let label = view as Label)
		{
			let node = mVisible[position];
			label.Text = scope:: $"{node.Label}";
		}
	}

	public void ToggleExpand(int position)
	{
		var node = mVisible[position];
		if (!node.HasKids) return;

		if (node.Expanded)
		{
			node.Expanded = false;
			mVisible[position] = node;

			int removeCount = 0;
			int idx = position + 1;
			while (idx < mVisible.Count && mVisible[idx].Depth > node.Depth)
			{
				delete mVisible[idx].Label;
				removeCount++;
				idx++;
			}
			mVisible.RemoveRange(position + 1, removeCount);
		}
		else
		{
			node.Expanded = true;
			mVisible[position] = node;

			for (int i = 0; i < node.ChildCount; i++)
			{
				bool hasGrandkids = (node.Depth == 0 && i < 2);
				Node child;
				child.Label = new $"{node.Label}.{i + 1}";
				child.Depth = node.Depth + 1;
				child.HasKids = hasGrandkids;
				child.Expanded = false;
				child.ChildCount = hasGrandkids ? 3 : 0;
				mVisible.Insert(position + 1 + i, child);
			}
		}

		for (let obs in mObservers)
			obs.OnDataChanged();
	}

	public void RegisterObserver(IAdapterObserver observer)
	{
		if (!mObservers.Contains(observer))
			mObservers.Add(observer);
	}

	public void UnregisterObserver(IAdapterObserver observer)
	{
		mObservers.Remove(observer);
	}
}

/// Flat reorderable adapter for DraggableTreeView demo.
class ReorderableListAdapter : IReorderableTreeAdapter
{
	private List<String> mItems = new .() ~ { for (var s in _) delete s; delete _; };
	private List<IAdapterObserver> mObservers = new .() ~ delete _;

	public this()
	{
		mItems.Add(new String("Scene"));
		mItems.Add(new String("Player"));
		mItems.Add(new String("Enemy"));
		mItems.Add(new String("Terrain"));
		mItems.Add(new String("Lighting"));
		mItems.Add(new String("Audio"));
	}

	public int ItemCount => mItems.Count;
	public int GetDepth(int position) => 0;
	public bool HasChildren(int position) => false;
	public bool IsExpanded(int position) => false;
	public int32 GetItemViewType(int position) => 0;
	public void ToggleExpand(int position) { }

	public View CreateView(int32 viewType)
	{
		let label = new Label();
		label.Padding = .(6, 2, 6, 2);
		return label;
	}

	public void BindView(View view, int position)
	{
		if (let label = view as Label)
			label.Text = mItems[position];
	}

	public bool CanMove(int from, int to) => from >= 0 && to >= 0 && from < mItems.Count && to < mItems.Count;

	public bool MoveItem(int from, int to)
	{
		if (!CanMove(from, to) || from == to) return false;
		let item = mItems[from];
		mItems.RemoveAt(from);
		int insertAt = (to > from) ? to - 1 : to;
		if (insertAt < 0) insertAt = 0;
		if (insertAt > mItems.Count) insertAt = mItems.Count;
		mItems.Insert(insertAt, item);
		for (let obs in mObservers) obs.OnDataChanged();
		return true;
	}

	public void RegisterObserver(IAdapterObserver observer)
	{
		if (!mObservers.Contains(observer))
			mObservers.Add(observer);
	}

	public void UnregisterObserver(IAdapterObserver observer)
	{
		mObservers.Remove(observer);
	}
}

/// DragData carrying a reference to the dragged view.
class ViewDragData : DragData
{
	public View SourceView;

	public this(StringView format, View sourceView) : base(format)
	{
		SourceView = sourceView;
	}
}

/// A colored panel that can be dragged.
class DraggablePanel : Panel, IDragSource
{
	private Color mColor;
	private String mName ~ delete _;

	public this(StringView name, Color color)
	{
		mName = new String(name);
		mColor = color;
		FillColor = color;
		CornerRadius = 6;
		BorderWidth = 1;
		BorderColor = Color(0.0f, 0.0f, 0.0f, 0.3f);

		let label = new Label(name);
		label.TextAlignment = .Center;
		label.VerticalAlignment = .Middle;
		AddView(label, new FrameLayout.LayoutParams(-1, -1) { Gravity = .Center });
	}

	public DragData CreateDragData()
	{
		return new ViewDragData("view/reorder", this);
	}

	public View CreateDragVisual(DragData data)
	{
		let visual = new Panel();
		visual.FillColor = mColor;
		visual.CornerRadius = 6;
		visual.MinWidth = 60;
		visual.MinHeight = 40;
		let label = new Label(mName);
		label.TextAlignment = .Center;
		visual.AddView(label, new FrameLayout.LayoutParams(-1, -1) { Gravity = .Center });
		return visual;
	}

	public void OnDragStarted(DragData data)
	{
		Alpha = 0.4f;
		let dd = Context.DragDrop;
		dd.AdornerOffsetX = 0;
		dd.AdornerOffsetY = 0;
		dd.AcceptCursor = .Pointer;
	}

	public void OnDragCompleted(DragData data, DragDropEffects effect, bool cancelled)
	{
		Alpha = 1.0f;
	}
}

/// A horizontal layout that accepts drag-and-drop reordering of its children.
class ReorderContainer : LinearLayout, IDropTarget
{
	public this()
	{
		Orientation = .Horizontal;
		Spacing = 6;
	}

	public DragDropEffects CanAcceptDrop(DragData data, float localX, float localY)
	{
		if (data.Format == "view/reorder")
			return .Move;
		return .None;
	}

	public void OnDragEnter(DragData data, float localX, float localY)
	{
	}

	public void OnDragOver(DragData data, float localX, float localY)
	{
	}

	public void OnDragLeave(DragData data)
	{
	}

	public DragDropEffects OnDrop(DragData data, float localX, float localY)
	{
		if (let viewData = data as ViewDragData)
		{
			let sourceView = viewData.SourceView;
			if (sourceView.Parent != this)
				return .None;

			int targetIndex = -1;
			for (int i = 0; i < ChildCount; i++)
			{
				let child = GetChildAt(i);
				if (child == sourceView) continue;
				if (localX >= child.Left && localX < child.Left + child.Width)
				{
					targetIndex = i;
					break;
				}
			}

			if (targetIndex < 0)
				return .Move;

			DetachView(sourceView);
			if (targetIndex > ChildCount) targetIndex = ChildCount;
			InsertView(sourceView, targetIndex);

			return .Move;
		}
		return .None;
	}
}

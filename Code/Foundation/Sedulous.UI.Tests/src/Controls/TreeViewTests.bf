namespace Sedulous.UI.Tests;

using System;
using System.Collections;
using Sedulous.UI;

class TreeViewTests
{
	/// Same test tree adapter as FlattenedTreeAdapterTests.
	private class TestTreeAdapter : ITreeAdapter
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
			for (int i = 0; i < 3; i++)
			{
				Node node;
				node.Label = new $"Root {i}";
				node.Depth = 0;
				node.HasKids = true;
				node.Expanded = false;
				node.ChildCount = 2;
				mVisible.Add(node);
			}
		}

		public int ItemCount => mVisible.Count;
		public int GetDepth(int position) => mVisible[position].Depth;
		public bool HasChildren(int position) => mVisible[position].HasKids;
		public bool IsExpanded(int position) => mVisible[position].Expanded;
		public int32 GetItemViewType(int position) => 0;

		public View CreateView(int32 viewType) => new Label();

		public void BindView(View view, int position)
		{
			if (let label = view as Label)
			{
				let node = mVisible[position];
				label.Text = scope $"{node.Label}";
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
					Node child;
					child.Label = new $"{node.Label} child {i}";
					child.Depth = node.Depth + 1;
					child.HasKids = false;
					child.Expanded = false;
					child.ChildCount = 0;
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

	private static RootView SetupContext(UIContext ctx, View root, float w = 400, float h = 300)
	{
		return TestHelper.SetupContext(ctx, root, w, h);
	}

	[Test]
	static void InitialCount_OnlyRootNodes()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let treeView = new TreeView();
		treeView.FixedItemHeight = 24;
		root.AddView(treeView, new LayoutParams(400, 300));

		let adapter = new TestTreeAdapter();
		treeView.SetAdapter(adapter);
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Only 3 root nodes visible initially
		Test.Assert(adapter.ItemCount == 3);

		treeView.SetAdapter(null); // Detach before deleting
		delete adapter;
	}

	[Test]
	static void ExpandNode_ShowsChildren()
	{
		let adapter = scope TestTreeAdapter();
		Test.Assert(adapter.ItemCount == 3);

		adapter.ToggleExpand(0); // expand Root 0
		Test.Assert(adapter.ItemCount == 5); // 3 roots + 2 children
		Test.Assert(adapter.GetDepth(1) == 1); // first child
		Test.Assert(adapter.GetDepth(2) == 1); // second child
		Test.Assert(adapter.GetDepth(3) == 0); // Root 1
	}

	[Test]
	static void CollapseNode_HidesChildren()
	{
		let adapter = scope TestTreeAdapter();

		adapter.ToggleExpand(0); // expand
		Test.Assert(adapter.ItemCount == 5);

		adapter.ToggleExpand(0); // collapse
		Test.Assert(adapter.ItemCount == 3);
	}

	[Test]
	static void OnNodeToggled_Fires()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let treeView = new TreeView();
		treeView.FixedItemHeight = 24;
		root.AddView(treeView, new LayoutParams(400, 300));

		let adapter = new TestTreeAdapter();
		treeView.SetAdapter(adapter);
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		int toggleCount = 0;
		treeView.OnNodeToggled.Subscribe(new [&toggleCount] (tv, pos) => { toggleCount++; });

		// Simulate click on Root 0 (which has children, so should toggle)
		ctx.ProcessMouseDown(200, 12, .Left); // y=12 is within first item (h=24)
		Test.Assert(toggleCount == 1);

		treeView.SetAdapter(null); // Detach before deleting
		delete adapter;
	}
}

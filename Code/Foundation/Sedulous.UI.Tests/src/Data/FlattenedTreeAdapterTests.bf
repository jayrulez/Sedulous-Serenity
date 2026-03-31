namespace Sedulous.UI.Tests;

using System;
using System.Collections;
using Sedulous.UI;

class FlattenedTreeAdapterTests
{
	/// A simple test tree adapter with known structure.
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

		// Build: 3 root nodes, each with 2 children
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

		public View CreateView(int32 viewType)
		{
			return new Label();
		}

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
				// Collapse: remove children after this position
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
				// Expand: insert children
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

	[Test]
	static void ItemCount_MatchesTree()
	{
		let tree = scope TestTreeAdapter();
		let flat = scope FlattenedTreeAdapter(tree);
		Test.Assert(flat.ItemCount == 3); // 3 root nodes, none expanded
	}

	[Test]
	static void BindView_SetsIndentation()
	{
		let tree = scope TestTreeAdapter();
		let flat = scope FlattenedTreeAdapter(tree, 20);

		let view = flat.CreateView(0);
		flat.BindView(view, 0);

		// Root node: depth 0, indent = 0 * 20 + 4 = 4
		Test.Assert(view.Padding.Left == 4);

		// Expand root 0 to get children at depth 1
		tree.ToggleExpand(0);
		flat.BindView(view, 1); // first child

		// Child: depth 1, indent = 1 * 20 + 4 = 24
		Test.Assert(view.Padding.Left == 24);

		delete view;
	}

	[Test]
	static void DataChange_Propagates()
	{
		let tree = scope TestTreeAdapter();
		let flat = scope FlattenedTreeAdapter(tree);

		int changeCount = 0;

		let observer = new TestObserver(&changeCount);
		flat.RegisterObserver(observer);

		tree.ToggleExpand(0); // expand root 0
		Test.Assert(changeCount == 1);
		Test.Assert(flat.ItemCount == 5); // 3 roots + 2 children

		tree.ToggleExpand(0); // collapse root 0
		Test.Assert(changeCount == 2);
		Test.Assert(flat.ItemCount == 3);

		flat.UnregisterObserver(observer);
		delete observer;
	}

	private class TestObserver : IAdapterObserver
	{
		private int* mCount;

		public this(int* count)
		{
			mCount = count;
		}

		public void OnDataChanged()
		{
			(*mCount)++;
		}
	}
}

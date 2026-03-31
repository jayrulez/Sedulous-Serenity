namespace Sedulous.UI.Tests;

using System;
using System.Collections;
using Sedulous.UI;

class ListViewTests
{
	/// Simple adapter that creates Labels with fixed text.
	private class TestAdapter : ListAdapter
	{
		public int mCount;
		public int CreateCount;
		public int BindCount;

		public this(int count)
		{
			mCount = count;
		}

		public override int ItemCount => mCount;

		public override View CreateView(int32 viewType)
		{
			CreateCount++;
			let label = new Label();
			return label;
		}

		public override void BindView(View view, int position)
		{
			BindCount++;
			if (let label = view as Label)
				label.Text = scope $"Item {position}";
		}
	}

	private static RootView SetupContext(UIContext ctx, View root, float w = 400, float h = 300)
	{
		return TestHelper.SetupContext(ctx, root, w, h);
	}

	[Test]
	static void NoAdapter_HandlesGracefully()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let listView = new ListView();
		root.AddView(listView, new LayoutParams(400, 300));
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }
		// Should not crash
		Test.Assert(listView.Width == 400);
	}

	[Test]
	static void FixedHeight_VisibleRangeCorrect()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let listView = new ListView();
		listView.FixedItemHeight = 40;
		root.AddView(listView, new LayoutParams(400, 200));

		let adapter = new TestAdapter(100);
		listView.SetAdapter(adapter);

		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// 200px viewport / 40px items = 5 visible items (0-4)
		// Adapter should only have created ~5-6 views (not 100)
		Test.Assert(adapter.CreateCount <= 7);
		Test.Assert(adapter.CreateCount >= 5);

		delete adapter;
	}

	[Test]
	static void Recycling_ReusesViews()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let listView = new ListView();
		listView.FixedItemHeight = 40;
		root.AddView(listView, new LayoutParams(400, 200));

		let adapter = new TestAdapter(100);
		listView.SetAdapter(adapter);
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Scroll down by several items
		listView.ScrollY = 200; // 5 items down
		TestHelper.UpdateFrame(ctx, rootView);

		// Should have reused recycled views, not created many new ones
		Test.Assert(listView.Recycler.ReusedCount > 0);

		delete adapter;
	}

	[Test]
	static void Recycling_CreatedCountBounded()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let listView = new ListView();
		listView.FixedItemHeight = 20;
		root.AddView(listView, new LayoutParams(400, 200));

		let adapter = new TestAdapter(10000);
		listView.SetAdapter(adapter);
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Scroll through many positions
		for (int i = 0; i < 20; i++)
		{
			listView.ScrollY = (float)(i * 200);
			TestHelper.UpdateFrame(ctx, rootView);
		}

		// With 200px viewport and 20px items, ~10-12 views should suffice
		// Total creates should be bounded, not 10000
		Test.Assert(adapter.CreateCount < 30);

		delete adapter;
	}

	[Test]
	static void ScrollY_Clamped()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let listView = new ListView();
		listView.FixedItemHeight = 40;
		root.AddView(listView, new LayoutParams(400, 200));

		let adapter = new TestAdapter(10);
		listView.SetAdapter(adapter);
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Max scroll = 10 * 40 - 200 = 200
		listView.ScrollY = 999;
		TestHelper.UpdateFrame(ctx, rootView);
		Test.Assert(listView.ScrollY <= 200);

		listView.ScrollY = -100;
		TestHelper.UpdateFrame(ctx, rootView);
		Test.Assert(listView.ScrollY >= 0);

		delete adapter;
	}

	[Test]
	static void OnDataChanged_RefreshesViews()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let listView = new ListView();
		listView.FixedItemHeight = 40;
		root.AddView(listView, new LayoutParams(400, 200));

		let adapter = new TestAdapter(10);
		listView.SetAdapter(adapter);
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		int bindsBefore = adapter.BindCount;

		// Change data and notify
		adapter.mCount = 20;
		adapter.NotifyDataChanged();
		TestHelper.UpdateFrame(ctx, rootView);

		// Should have rebound visible items
		Test.Assert(adapter.BindCount > bindsBefore);

		delete adapter;
	}

	[Test]
	static void Selection_SingleMode()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let listView = new ListView();
		listView.FixedItemHeight = 40;
		root.AddView(listView, new LayoutParams(400, 200));

		let adapter = new TestAdapter(10);
		listView.SetAdapter(adapter);
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		listView.SelectionModel.Select(3);
		Test.Assert(listView.SelectionModel.IsSelected(3));
		Test.Assert(listView.SelectionModel.Count == 1);

		listView.SelectionModel.Select(5);
		Test.Assert(!listView.SelectionModel.IsSelected(3));
		Test.Assert(listView.SelectionModel.IsSelected(5));

		delete adapter;
	}

	[Test]
	static void OnItemClick_FiresWithCorrectPosition()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let listView = new ListView();
		listView.FixedItemHeight = 40;
		root.AddView(listView, new LayoutParams(400, 200));

		let adapter = new TestAdapter(10);
		listView.SetAdapter(adapter);
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		int clickedPos = -1;
		listView.OnItemClick.Subscribe(new [&clickedPos] (lv, pos) => { clickedPos = pos; });

		// Click in the third item (y = 80-120, use center at y=100)
		ctx.ProcessMouseDown(200, 100, .Left);
		Test.Assert(clickedPos == 2); // 100 / 40 = item 2

		delete adapter;
	}

	[Test]
	static void KeyNav_DownMovesSelection()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let listView = new ListView();
		listView.FixedItemHeight = 40;
		root.AddView(listView, new LayoutParams(400, 200));

		let adapter = new TestAdapter(10);
		listView.SetAdapter(adapter);
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		ctx.FocusManager.SetFocus(listView);
		ctx.ProcessKeyDown(.Down);
		Test.Assert(listView.SelectionModel.SelectedPosition == 0);

		ctx.ProcessKeyDown(.Down);
		Test.Assert(listView.SelectionModel.SelectedPosition == 1);

		ctx.ProcessKeyDown(.Down);
		Test.Assert(listView.SelectionModel.SelectedPosition == 2);

		delete adapter;
	}

	[Test]
	static void ScrollToPosition_BringsIntoView()
	{
		let ctx = scope UIContext();
		let root = new FrameLayout();
		let listView = new ListView();
		listView.FixedItemHeight = 40;
		root.AddView(listView, new LayoutParams(400, 200));

		let adapter = new TestAdapter(100);
		listView.SetAdapter(adapter);
		let rootView = SetupContext(ctx, root);
		defer { ctx.RemoveRootView(rootView); delete rootView; }

		// Item 50 is at y=2000, well below viewport
		listView.ScrollToPosition(50);
		TestHelper.UpdateFrame(ctx, rootView);

		// Should have scrolled so item 50 is visible
		float itemTop = 50 * 40;
		Test.Assert(listView.ScrollY <= itemTop);
		Test.Assert(listView.ScrollY + listView.ViewportHeight >= itemTop + 40);

		delete adapter;
	}

	[Test]
	static void DefaultConfiguration()
	{
		let listView = scope ListView();
		Test.Assert(listView.SelectionModel != null);
		Test.Assert(listView.SelectionModel.Mode == .Single);
		Test.Assert(listView.FixedItemHeight == 0);
	}
}

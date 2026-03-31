namespace Sedulous.UI.Tests;

using System;
using Sedulous.UI;

class ViewRecyclerTests
{
	private class DummyView : View
	{
		public int32 ViewType;

		public this(int32 viewType)
		{
			ViewType = viewType;
		}

		protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
		{
			SetMeasuredDimension(widthSpec.Resolve(50, MinWidth, MaxWidth),
				heightSpec.Resolve(20, MinHeight, MaxHeight));
		}
	}

	[Test]
	static void ObtainView_ReturnsNullWhenEmpty()
	{
		let recycler = scope ViewRecycler();
		Test.Assert(recycler.ObtainView(0) == null);
		Test.Assert(recycler.ObtainView(1) == null);
	}

	[Test]
	static void RecycleAndObtain_ReturnsSameView()
	{
		let recycler = scope ViewRecycler();
		let view = new DummyView(0);

		recycler.RecycleView(view, 0);
		let obtained = recycler.ObtainView(0);
		Test.Assert(obtained === view);

		// After obtaining, pool should be empty
		Test.Assert(recycler.ObtainView(0) == null);

		// Clean up the obtained view (we own it now)
		delete obtained;
	}

	[Test]
	static void DifferentViewTypes_SeparatePools()
	{
		let recycler = scope ViewRecycler();
		let viewA = new DummyView(0);
		let viewB = new DummyView(1);

		recycler.RecycleView(viewA, 0);
		recycler.RecycleView(viewB, 1);

		// Should not cross-recycle
		let obtainedB = recycler.ObtainView(1);
		Test.Assert(obtainedB === viewB);

		let obtainedA = recycler.ObtainView(0);
		Test.Assert(obtainedA === viewA);

		delete obtainedA;
		delete obtainedB;
	}

	[Test]
	static void Counters_TrackCorrectly()
	{
		let recycler = scope ViewRecycler();
		Test.Assert(recycler.CreatedCount == 0);
		Test.Assert(recycler.RecycledCount == 0);
		Test.Assert(recycler.ReusedCount == 0);

		recycler.RecordCreation();
		recycler.RecordCreation();
		Test.Assert(recycler.CreatedCount == 2);

		let view = new DummyView(0);
		recycler.RecycleView(view, 0);
		Test.Assert(recycler.RecycledCount == 1);

		let obtained = recycler.ObtainView(0);
		Test.Assert(recycler.ReusedCount == 1);

		delete obtained;
	}

	[Test]
	static void Clear_DeletesPooledViews()
	{
		let recycler = scope ViewRecycler();
		recycler.RecycleView(new DummyView(0), 0);
		recycler.RecycleView(new DummyView(0), 0);
		recycler.RecycleView(new DummyView(1), 1);

		recycler.Clear();

		// All pools should be empty
		Test.Assert(recycler.ObtainView(0) == null);
		Test.Assert(recycler.ObtainView(1) == null);
	}
}

namespace Sedulous.UI;

using System;
using System.Collections;

/// Pool of recycled views, keyed by view type.
/// When a view scrolls out of the visible range, it is scrapped into the pool.
/// When a new view is needed, the pool is checked first before creating one.
public class ViewRecycler
{
	private Dictionary<int32, List<View>> mScrapHeap = new .() ~ {
		for (let (key, list) in _)
		{
			for (let view in list)
				delete view;
			delete list;
		}
		delete _;
	};

	private int mCreatedCount;
	private int mRecycledCount;
	private int mReusedCount;

	public int CreatedCount => mCreatedCount;
	public int RecycledCount => mRecycledCount;
	public int ReusedCount => mReusedCount;

	/// Try to obtain a recycled view of the given type.
	/// Returns null if none available. Transfers ownership to caller.
	public View ObtainView(int32 viewType)
	{
		if (mScrapHeap.TryGetValue(viewType, let list))
		{
			if (list.Count > 0)
			{
				let view = list.PopBack();
				mReusedCount++;
				return view;
			}
		}
		return null;
	}

	/// Return a view to the recycle pool. Takes ownership.
	public void RecycleView(View view, int32 viewType)
	{
		List<View> list;
		if (!mScrapHeap.TryGetValue(viewType, out list))
		{
			list = new List<View>();
			mScrapHeap[viewType] = list;
		}
		list.Add(view);
		mRecycledCount++;
	}

	/// Record that a new view was created (for diagnostics).
	public void RecordCreation()
	{
		mCreatedCount++;
	}

	/// Delete all pooled views and clear the pool.
	public void Clear()
	{
		for (let (_, list) in mScrapHeap)
		{
			for (let view in list)
				delete view;
			list.Clear();
		}
	}

	/// Reset diagnostic counters.
	public void ResetCounters()
	{
		mCreatedCount = 0;
		mRecycledCount = 0;
		mReusedCount = 0;
	}
}

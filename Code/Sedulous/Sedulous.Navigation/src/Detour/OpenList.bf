using System;
using System.Collections;

namespace Sedulous.Navigation.Detour;

/// Priority queue (min-heap) for the A* open list.
class OpenList
{
	private List<NavNode> mHeap ~ delete _;

	public int32 Count => (int32)mHeap.Count;
	public bool IsEmpty => mHeap.Count == 0;

	public this()
	{
		mHeap = new List<NavNode>();
	}

	/// Clears the open list.
	public void Clear()
	{
		mHeap.Clear();
	}

	/// Pushes a node onto the heap.
	public void Push(NavNode node)
	{
		mHeap.Add(node);
		BubbleUp((int32)(mHeap.Count - 1));
	}

	/// Pops the node with the lowest total cost.
	public NavNode Pop()
	{
		if (mHeap.Count == 0) return null;

		let result = mHeap[0];
		int32 last = (int32)(mHeap.Count - 1);

		if (last > 0)
		{
			mHeap[0] = mHeap[last];
			mHeap.RemoveAt(last);
			BubbleDown(0);
		}
		else
		{
			mHeap.RemoveAt(0);
		}

		return result;
	}

	/// Updates the position of a node after its cost has decreased.
	public void Update(NavNode node)
	{
		// Find the node in the heap and bubble up
		for (int32 i = 0; i < mHeap.Count; i++)
		{
			if (mHeap[i] === node)
			{
				BubbleUp(i);
				return;
			}
		}
	}

	private void BubbleUp(int32 index)
	{
		var index;
		while (index > 0)
		{
			int32 parent = (index - 1) / 2;
			if (mHeap[index].TotalCost < mHeap[parent].TotalCost)
			{
				let tmp = mHeap[index];
				mHeap[index] = mHeap[parent];
				mHeap[parent] = tmp;
				index = parent;
			}
			else
			{
				break;
			}
		}
	}

	private void BubbleDown(int32 index)
	{
		var index;
		int32 count = (int32)mHeap.Count;
		while (true)
		{
			int32 smallest = index;
			int32 left = 2 * index + 1;
			int32 right = 2 * index + 2;

			if (left < count && mHeap[left].TotalCost < mHeap[smallest].TotalCost)
				smallest = left;
			if (right < count && mHeap[right].TotalCost < mHeap[smallest].TotalCost)
				smallest = right;

			if (smallest != index)
			{
				let tmp = mHeap[index];
				mHeap[index] = mHeap[smallest];
				mHeap[smallest] = tmp;
				index = smallest;
			}
			else
			{
				break;
			}
		}
	}
}

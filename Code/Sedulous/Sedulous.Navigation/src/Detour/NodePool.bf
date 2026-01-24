using System;
using System.Collections;

namespace Sedulous.Navigation.Detour;

/// Pool of NavNodes indexed by PolyRef for the A* search.
class NodePool
{
	private NavNode[] mNodes ~ { for (var n in _) delete n; delete _; };
	private Dictionary<uint64, int32> mNodeMap ~ delete _;
	private int32 mNodeCount;
	private int32 mMaxNodes;

	public int32 NodeCount => mNodeCount;

	public this(int32 maxNodes)
	{
		mMaxNodes = maxNodes;
		mNodes = new NavNode[maxNodes];
		mNodeMap = new Dictionary<uint64, int32>();
		mNodeCount = 0;
	}

	/// Resets the pool for a new query.
	public void Clear()
	{
		for (int32 i = 0; i < mNodeCount; i++)
		{
			if (mNodes[i] != null)
			{
				delete mNodes[i];
				mNodes[i] = null;
			}
		}
		mNodeCount = 0;
		mNodeMap.Clear();
	}

	/// Gets or creates a node for the given polygon reference.
	public NavNode GetNode(PolyRef polyRef)
	{
		if (mNodeMap.TryGetValue(polyRef.Value, let idx))
			return mNodes[idx];

		if (mNodeCount >= mMaxNodes)
			return null;

		let node = new NavNode();
		node.Index = mNodeCount;
		node.PolyRef = polyRef;
		node.CostFromStart = 0;
		node.TotalCost = 0;
		node.ParentIndex = -1;
		node.Flags = .None;

		mNodes[mNodeCount] = node;
		mNodeMap[polyRef.Value] = mNodeCount;
		mNodeCount++;

		return node;
	}

	/// Finds an existing node for the given polygon reference.
	public NavNode FindNode(PolyRef polyRef)
	{
		if (mNodeMap.TryGetValue(polyRef.Value, let idx))
			return mNodes[idx];
		return null;
	}

	/// Gets a node by its pool index.
	public NavNode GetNodeAtIndex(int32 index)
	{
		if (index >= 0 && index < mNodeCount)
			return mNodes[index];
		return null;
	}
}

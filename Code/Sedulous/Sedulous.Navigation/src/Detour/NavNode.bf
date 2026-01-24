using System;

namespace Sedulous.Navigation.Detour;

/// Node flags for the A* search.
enum NavNodeFlags : uint8
{
	None = 0,
	Open = 1,
	Closed = 2
}

/// A node in the A* search graph.
class NavNode
{
	/// Position on the polygon (entry point).
	public float[3] Position;
	/// Cost from start to this node.
	public float CostFromStart;
	/// Total estimated cost (g + h).
	public float TotalCost;
	/// Parent node index for path reconstruction.
	public int32 ParentIndex;
	/// Reference to the polygon this node represents.
	public PolyRef PolyRef;
	/// Node state flags.
	public NavNodeFlags Flags;
	/// Index in the node pool.
	public int32 Index;
}

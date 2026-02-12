namespace StormTactics.Battle;

using System;
using System.Collections;
using StormTactics.Core;

/// A* pathfinder on a hex grid.
class HexPathfinder
{
	private HexGrid mGrid;

	public this(HexGrid grid)
	{
		mGrid = grid;
	}

	/// Find shortest path from `start` to `goal`.
	/// Returns true if a path was found, false if unreachable.
	/// `flying` = true ignores occupied cells (can fly over units).
	public bool FindPath(HexCoord start, HexCoord goal, bool flying, List<HexCoord> outPath)
	{
		outPath.Clear();

		if (!mGrid.InBounds(start) || !mGrid.InBounds(goal))
			return false;

		if (start == goal)
		{
			outPath.Add(start);
			return true;
		}

		// Goal must be unoccupied to land on (flying only helps traverse, not land)
		if (!mGrid.IsPassable(goal))
			return false;

		let openSet = scope PriorityQueue();
		let cameFrom = scope Dictionary<HexCoord, HexCoord>();
		let gScore = scope Dictionary<HexCoord, int32>();

		gScore[start] = 0;
		openSet.Enqueue(start, HexCoord.Distance(start, goal));

		while (!openSet.IsEmpty)
		{
			let current = openSet.Dequeue();

			if (current == goal)
			{
				// Reconstruct path
				ReconstructPath(cameFrom, current, outPath);
				return true;
			}

			let currentG = gScore.GetValueOrDefault(current);

			for (int dir = 0; dir < 6; dir++)
			{
				let neighbor = current.Neighbor(dir);

				if (!mGrid.InBounds(neighbor))
					continue;

				// Can only pass through if passable (or goal)
				if (neighbor != goal && !IsPassable(neighbor, flying))
					continue;

				let tentativeG = currentG + 1;

				if (!gScore.ContainsKey(neighbor) || tentativeG < gScore[neighbor])
				{
					cameFrom[neighbor] = current;
					gScore[neighbor] = tentativeG;
					let fScore = tentativeG + HexCoord.Distance(neighbor, goal);
					openSet.Enqueue(neighbor, fScore);
				}
			}
		}

		return false; // No path found
	}

	/// Get all cells reachable within `maxSteps` movement.
	/// `flying` = true ignores occupied cells for movement.
	/// Does NOT include the start cell.
	public void GetReachableCells(HexCoord start, int32 maxSteps, bool flying, List<HexCoord> outList)
	{
		outList.Clear();

		let visited = scope Dictionary<HexCoord, int32>();
		let queue = scope Queue<(HexCoord coord, int32 cost)>();

		visited[start] = 0;
		queue.Add((start, 0));

		while (queue.Count > 0)
		{
			let (current, cost) = queue.PopFront();

			for (int dir = 0; dir < 6; dir++)
			{
				let neighbor = current.Neighbor(dir);
				let nextCost = cost + 1;

				if (nextCost > maxSteps)
					continue;

				if (!mGrid.InBounds(neighbor))
					continue;

				// Flying units can traverse occupied cells but can't stop on them
				if (flying)
				{
					if (!mGrid.IsPassableFlying(neighbor))
						continue; // Blocked terrain stops even flyers
				}
				else
				{
					if (!mGrid.IsPassable(neighbor))
						continue;
				}

				if (visited.ContainsKey(neighbor) && visited[neighbor] <= nextCost)
					continue;

				visited[neighbor] = nextCost;
				queue.Add((neighbor, nextCost));

				// Only add to reachable destinations if actually unoccupied (can land)
				if (mGrid.IsPassable(neighbor) && !outList.Contains(neighbor))
					outList.Add(neighbor);
			}
		}
	}

	private bool IsPassable(HexCoord hex, bool flying)
	{
		return flying ? mGrid.IsPassableFlying(hex) : mGrid.IsPassable(hex);
	}

	private void ReconstructPath(Dictionary<HexCoord, HexCoord> cameFrom, HexCoord current, List<HexCoord> outPath)
	{
		let temp = scope List<HexCoord>();
		temp.Add(current);
		var cur = current;
		while (cameFrom.ContainsKey(cur))
		{
			cur = cameFrom[cur];
			temp.Add(cur);
		}
		for (let hex in temp.Reversed)
			outPath.Add(hex);
	}

	/// Simple min-priority queue for A*.
	private class PriorityQueue
	{
		private List<(HexCoord coord, int32 priority)> mHeap = new .() ~ delete _;

		public bool IsEmpty => mHeap.Count == 0;

		public void Enqueue(HexCoord coord, int32 priority)
		{
			mHeap.Add((coord, priority));
			BubbleUp(mHeap.Count - 1);
		}

		public HexCoord Dequeue()
		{
			let result = mHeap[0].coord;
			let last = mHeap.Count - 1;
			mHeap[0] = mHeap[last];
			mHeap.RemoveAt(last);
			if (mHeap.Count > 0)
				BubbleDown(0);
			return result;
		}

		private void BubbleUp(int index)
		{
			var idx = index;
			while (idx > 0)
			{
				let parent = (idx - 1) / 2;
				if (mHeap[idx].priority < mHeap[parent].priority)
				{
					let tmp = mHeap[idx];
					mHeap[idx] = mHeap[parent];
					mHeap[parent] = tmp;
					idx = parent;
				}
				else break;
			}
		}

		private void BubbleDown(int index)
		{
			var idx = index;
			let count = mHeap.Count;
			while (true)
			{
				var smallest = idx;
				let left = 2 * idx + 1;
				let right = 2 * idx + 2;

				if (left < count && mHeap[left].priority < mHeap[smallest].priority)
					smallest = left;
				if (right < count && mHeap[right].priority < mHeap[smallest].priority)
					smallest = right;

				if (smallest != idx)
				{
					let tmp = mHeap[idx];
					mHeap[idx] = mHeap[smallest];
					mHeap[smallest] = tmp;
					idx = smallest;
				}
				else break;
			}
		}
	}
}

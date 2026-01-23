using System;
using System.Collections;

namespace Sedulous.Navigation.Detour;

/// Straight path vertex flags.
enum StraightPathFlags : uint8
{
	None = 0,
	/// The vertex is the start of the path.
	Start = 1,
	/// The vertex is the end of the path.
	End = 2,
	/// The vertex is at an off-mesh connection.
	OffMeshConnection = 4
}

/// Status of a sliced pathfinding query.
enum SlicedQueryStatus
{
	/// No sliced query is in progress.
	None,
	/// A sliced query is in progress.
	InProgress,
	/// The sliced query completed successfully (reached goal).
	Complete,
	/// The sliced query completed with a partial result (ran out of nodes).
	Partial
}

/// Provides pathfinding and spatial queries on a navigation mesh.
class NavMeshQuery
{
	private NavMesh mNavMesh;
	private NodePool mNodePool ~ delete _;
	private OpenList mOpenList ~ delete _;
	private int32 mMaxNodes;

	// Sliced pathfinding state
	private SlicedQueryStatus mSlicedStatus;
	private PolyRef mSlicedStartRef;
	private PolyRef mSlicedEndRef;
	private float[3] mSlicedStartPos;
	private float[3] mSlicedEndPos;
	private INavMeshQueryFilter mSlicedFilter;
	private NavNode mSlicedLastBestNode;
	private float mSlicedLastBestCost;
	private int32 mSlicedMaxPath;

	/// Initializes the query object for use with the given navmesh.
	public NavStatus Init(NavMesh navMesh, int32 maxNodes = 2048)
	{
		mNavMesh = navMesh;
		mMaxNodes = maxNodes;
		mNodePool = new NodePool(maxNodes);
		mOpenList = new OpenList();
		return .Success;
	}

	/// Finds the nearest polygon to the given position within the search extents.
	public NavStatus FindNearestPoly(float[3] center, float[3] halfExtents, INavMeshQueryFilter filter,
		out PolyRef nearestRef, out float[3] nearestPoint)
	{
		nearestRef = .Null;
		nearestPoint = center;

		float nearestDistSq = float.MaxValue;

		// Search all tiles that overlap the query box
		float[3] queryMin = .(center[0] - halfExtents[0], center[1] - halfExtents[1], center[2] - halfExtents[2]);
		float[3] queryMax = .(center[0] + halfExtents[0], center[1] + halfExtents[1], center[2] + halfExtents[2]);

		for (int32 ti = 0; ti < mNavMesh.MaxTiles; ti++)
		{
			let tile = mNavMesh.GetTile(ti);
			if (tile == null) continue;

			// Check if tile overlaps query bounds
			if (tile.BMax[0] < queryMin[0] || tile.BMin[0] > queryMax[0]) continue;
			if (tile.BMax[2] < queryMin[2] || tile.BMin[2] > queryMax[2]) continue;

			for (int32 pi = 0; pi < tile.PolyCount; pi++)
			{
				ref NavPoly poly = ref tile.Polygons[pi];
				if (poly.Type == .OffMeshConnection) continue;

				PolyRef polyRef = mNavMesh.EncodePolyRef(tile, pi);
				if (!filter.PassFilter(polyRef, poly)) continue;

				// Find closest point on this polygon
				float[3] closestPt;
				mNavMesh.ClosestPointOnPoly(polyRef, center, out closestPt);

				float dx = center[0] - closestPt[0];
				float dy = center[1] - closestPt[1];
				float dz = center[2] - closestPt[2];
				float distSq = dx * dx + dy * dy + dz * dz;

				if (distSq < nearestDistSq)
				{
					// Check if within extents
					if (closestPt[0] >= queryMin[0] && closestPt[0] <= queryMax[0] &&
						closestPt[1] >= queryMin[1] && closestPt[1] <= queryMax[1] &&
						closestPt[2] >= queryMin[2] && closestPt[2] <= queryMax[2])
					{
						nearestDistSq = distSq;
						nearestRef = polyRef;
						nearestPoint = closestPt;
					}
				}
			}
		}

		if (nearestRef.IsValid)
			return .Success;
		return .PathNotFound;
	}

	/// Finds a polygon path from start to end using A*.
	/// Returns the polygon corridor (sequence of polygon references).
	public NavStatus FindPath(PolyRef startRef, PolyRef endRef,
		float[3] startPos, float[3] endPos,
		INavMeshQueryFilter filter,
		List<PolyRef> path, int32 maxPath = 256)
	{
		path.Clear();

		if (!startRef.IsValid || !endRef.IsValid)
			return .InvalidParam;

		if (startRef == endRef)
		{
			path.Add(startRef);
			return .Success;
		}

		// Initialize A*
		mNodePool.Clear();
		mOpenList.Clear();

		let startNode = mNodePool.GetNode(startRef);
		if (startNode == null) return .OutOfNodes;

		startNode.Position = startPos;
		startNode.CostFromStart = 0;
		startNode.TotalCost = Heuristic(startPos, endPos);
		startNode.ParentIndex = -1;
		startNode.Flags = .Open;
		mOpenList.Push(startNode);

		NavNode lastBestNode = startNode;
		float lastBestCost = startNode.TotalCost;

		while (!mOpenList.IsEmpty)
		{
			let bestNode = mOpenList.Pop();
			bestNode.Flags = .Closed;

			// Check if we reached the goal
			if (bestNode.PolyRef == endRef)
			{
				lastBestNode = bestNode;
				break;
			}

			// Expand neighbors
			NavPoly bestPoly;
			NavMeshTile bestTile;
			if (!mNavMesh.GetPolyAndTile(bestNode.PolyRef, out bestPoly, out bestTile))
				continue;

			// Iterate through polygon links
			int32 linkIdx = bestPoly.FirstLink;
			while (linkIdx >= 0 && linkIdx < bestTile.LinkCount)
			{
				ref NavMeshLink link = ref bestTile.Links[linkIdx];
				PolyRef neighborRef = link.Reference;
				linkIdx = link.Next;

				if (!neighborRef.IsValid) continue;

				NavPoly neighborPoly;
				NavMeshTile neighborTile;
				if (!mNavMesh.GetPolyAndTile(neighborRef, out neighborPoly, out neighborTile))
					continue;

				if (!filter.PassFilter(neighborRef, neighborPoly))
					continue;

				// Get the portal edge between the two polygons
				float[3] portalMid;
				GetPortalMidpoint(bestNode.PolyRef, bestPoly, bestTile, neighborRef, neighborPoly, neighborTile, out portalMid);

				// Calculate costs
				float curCost = filter.GetCost(bestNode.Position, portalMid, bestNode.PolyRef, bestPoly);
				float newCost = bestNode.CostFromStart + curCost;
				float heuristic = Heuristic(portalMid, endPos);
				float totalCost = newCost + heuristic;

				let neighborNode = mNodePool.GetNode(neighborRef);
				if (neighborNode == null) continue;

				if (neighborNode.Flags == .None)
				{
					// New node
					neighborNode.Position = portalMid;
					neighborNode.CostFromStart = newCost;
					neighborNode.TotalCost = totalCost;
					neighborNode.ParentIndex = bestNode.Index;
					neighborNode.Flags = .Open;
					mOpenList.Push(neighborNode);

					if (heuristic < lastBestCost)
					{
						lastBestCost = heuristic;
						lastBestNode = neighborNode;
					}
				}
				else if (newCost < neighborNode.CostFromStart)
				{
					// Found a better path to this node
					neighborNode.Position = portalMid;
					neighborNode.CostFromStart = newCost;
					neighborNode.TotalCost = totalCost;
					neighborNode.ParentIndex = bestNode.Index;

					if (neighborNode.Flags == .Closed)
					{
						neighborNode.Flags = .Open;
						mOpenList.Push(neighborNode);
					}
					else
					{
						mOpenList.Update(neighborNode);
					}

					if (heuristic < lastBestCost)
					{
						lastBestCost = heuristic;
						lastBestNode = neighborNode;
					}
				}
			}

			// Also check neighbor polygons via adjacency (for tiles without explicit links)
			for (int32 e = 0; e < bestPoly.VertexCount; e++)
			{
				uint16 neighbor = bestPoly.Neighbors[e];
				if (neighbor == 0 || neighbor > NavMeshConstants.ExternalLink)
					continue;

				PolyRef neighborRef2 = mNavMesh.EncodePolyRef(bestTile, (int32)(neighbor - 1));
				if (mNodePool.FindNode(neighborRef2) != null)
				{
					let existingNode = mNodePool.FindNode(neighborRef2);
					if (existingNode.Flags == .Closed) continue;
				}

				NavPoly neighborPoly2;
				NavMeshTile neighborTile2;
				if (!mNavMesh.GetPolyAndTile(neighborRef2, out neighborPoly2, out neighborTile2))
					continue;

				if (!filter.PassFilter(neighborRef2, neighborPoly2))
					continue;

				float[3] edgeMid;
				GetEdgeMidpoint(bestTile, bestPoly, e, out edgeMid);

				float curCost2 = filter.GetCost(bestNode.Position, edgeMid, bestNode.PolyRef, bestPoly);
				float newCost2 = bestNode.CostFromStart + curCost2;
				float heuristic2 = Heuristic(edgeMid, endPos);
				float totalCost2 = newCost2 + heuristic2;

				let neighborNode2 = mNodePool.GetNode(neighborRef2);
				if (neighborNode2 == null) continue;

				if (neighborNode2.Flags == .None)
				{
					neighborNode2.Position = edgeMid;
					neighborNode2.CostFromStart = newCost2;
					neighborNode2.TotalCost = totalCost2;
					neighborNode2.ParentIndex = bestNode.Index;
					neighborNode2.Flags = .Open;
					mOpenList.Push(neighborNode2);

					if (heuristic2 < lastBestCost)
					{
						lastBestCost = heuristic2;
						lastBestNode = neighborNode2;
					}
				}
				else if (newCost2 < neighborNode2.CostFromStart)
				{
					neighborNode2.Position = edgeMid;
					neighborNode2.CostFromStart = newCost2;
					neighborNode2.TotalCost = totalCost2;
					neighborNode2.ParentIndex = bestNode.Index;

					if (neighborNode2.Flags == .Closed)
					{
						neighborNode2.Flags = .Open;
						mOpenList.Push(neighborNode2);
					}
					else
					{
						mOpenList.Update(neighborNode2);
					}

					if (heuristic2 < lastBestCost)
					{
						lastBestCost = heuristic2;
						lastBestNode = neighborNode2;
					}
				}
			}
		}

		// Reconstruct path from lastBestNode
		NavNode node = lastBestNode;
		int32 pathLen = 0;
		while (node != null && pathLen < maxPath)
		{
			pathLen++;
			if (node.ParentIndex < 0) break;
			node = mNodePool.GetNodeAtIndex(node.ParentIndex);
		}

		// Build path in correct order
		node = lastBestNode;
		let tempPath = scope PolyRef[pathLen];
		int32 idx = pathLen - 1;
		while (node != null && idx >= 0)
		{
			tempPath[idx] = node.PolyRef;
			idx--;
			if (node.ParentIndex < 0) break;
			node = mNodePool.GetNodeAtIndex(node.ParentIndex);
		}

		for (int32 i = 0; i < pathLen; i++)
			path.Add(tempPath[i]);

		if (lastBestNode.PolyRef == endRef)
			return .Success;
		return .PartialResult;
	}

	/// Gets the current status of the sliced pathfinding query.
	public SlicedQueryStatus SlicedStatus => mSlicedStatus;

	/// Initializes a sliced pathfinding query.
	/// After calling this, call UpdateSlicedFindPath() repeatedly until it returns
	/// Complete or Partial, then call FinalizeSlicedFindPath() to get the result.
	public NavStatus InitSlicedFindPath(PolyRef startRef, PolyRef endRef,
		float[3] startPos, float[3] endPos,
		INavMeshQueryFilter filter, int32 maxPath = 256)
	{
		mSlicedStatus = .None;

		if (!startRef.IsValid || !endRef.IsValid)
			return .InvalidParam;

		mSlicedStartRef = startRef;
		mSlicedEndRef = endRef;
		mSlicedStartPos = startPos;
		mSlicedEndPos = endPos;
		mSlicedFilter = filter;
		mSlicedMaxPath = maxPath;

		// Initialize A*
		mNodePool.Clear();
		mOpenList.Clear();

		let startNode = mNodePool.GetNode(startRef);
		if (startNode == null) return .OutOfNodes;

		startNode.Position = startPos;
		startNode.CostFromStart = 0;
		startNode.TotalCost = Heuristic(startPos, endPos);
		startNode.ParentIndex = -1;
		startNode.Flags = .Open;
		mOpenList.Push(startNode);

		mSlicedLastBestNode = startNode;
		mSlicedLastBestCost = startNode.TotalCost;

		if (startRef == endRef)
		{
			mSlicedStatus = .Complete;
			return .Success;
		}

		mSlicedStatus = .InProgress;
		return .Success;
	}

	/// Performs up to maxIterations of the sliced A* search.
	/// Returns the number of iterations actually performed.
	/// Check SlicedStatus after calling to see if the query is complete.
	public int32 UpdateSlicedFindPath(int32 maxIterations)
	{
		if (mSlicedStatus != .InProgress)
			return 0;

		int32 iter = 0;
		while (iter < maxIterations && !mOpenList.IsEmpty)
		{
			iter++;

			let bestNode = mOpenList.Pop();
			bestNode.Flags = .Closed;

			// Check if we reached the goal
			if (bestNode.PolyRef == mSlicedEndRef)
			{
				mSlicedLastBestNode = bestNode;
				mSlicedStatus = .Complete;
				return iter;
			}

			// Expand neighbors
			NavPoly bestPoly;
			NavMeshTile bestTile;
			if (!mNavMesh.GetPolyAndTile(bestNode.PolyRef, out bestPoly, out bestTile))
				continue;

			// Iterate through polygon links
			int32 linkIdx = bestPoly.FirstLink;
			while (linkIdx >= 0 && linkIdx < bestTile.LinkCount)
			{
				ref NavMeshLink link = ref bestTile.Links[linkIdx];
				PolyRef neighborRef = link.Reference;
				linkIdx = link.Next;

				if (!neighborRef.IsValid) continue;

				NavPoly neighborPoly;
				NavMeshTile neighborTile;
				if (!mNavMesh.GetPolyAndTile(neighborRef, out neighborPoly, out neighborTile))
					continue;

				if (!mSlicedFilter.PassFilter(neighborRef, neighborPoly))
					continue;

				float[3] portalMid;
				GetPortalMidpoint(bestNode.PolyRef, bestPoly, bestTile, neighborRef, neighborPoly, neighborTile, out portalMid);

				float curCost = mSlicedFilter.GetCost(bestNode.Position, portalMid, bestNode.PolyRef, bestPoly);
				float newCost = bestNode.CostFromStart + curCost;
				float heuristic = Heuristic(portalMid, mSlicedEndPos);
				float totalCost = newCost + heuristic;

				let neighborNode = mNodePool.GetNode(neighborRef);
				if (neighborNode == null) continue;

				if (neighborNode.Flags == .None)
				{
					neighborNode.Position = portalMid;
					neighborNode.CostFromStart = newCost;
					neighborNode.TotalCost = totalCost;
					neighborNode.ParentIndex = bestNode.Index;
					neighborNode.Flags = .Open;
					mOpenList.Push(neighborNode);

					if (heuristic < mSlicedLastBestCost)
					{
						mSlicedLastBestCost = heuristic;
						mSlicedLastBestNode = neighborNode;
					}
				}
				else if (newCost < neighborNode.CostFromStart)
				{
					neighborNode.Position = portalMid;
					neighborNode.CostFromStart = newCost;
					neighborNode.TotalCost = totalCost;
					neighborNode.ParentIndex = bestNode.Index;

					if (neighborNode.Flags == .Closed)
					{
						neighborNode.Flags = .Open;
						mOpenList.Push(neighborNode);
					}
					else
					{
						mOpenList.Update(neighborNode);
					}

					if (heuristic < mSlicedLastBestCost)
					{
						mSlicedLastBestCost = heuristic;
						mSlicedLastBestNode = neighborNode;
					}
				}
			}

			// Also check neighbor polygons via adjacency
			for (int32 e = 0; e < bestPoly.VertexCount; e++)
			{
				uint16 neighbor = bestPoly.Neighbors[e];
				if (neighbor == 0 || neighbor > NavMeshConstants.ExternalLink)
					continue;

				PolyRef neighborRef2 = mNavMesh.EncodePolyRef(bestTile, (int32)(neighbor - 1));
				if (mNodePool.FindNode(neighborRef2) != null)
				{
					let existingNode = mNodePool.FindNode(neighborRef2);
					if (existingNode.Flags == .Closed) continue;
				}

				NavPoly neighborPoly2;
				NavMeshTile neighborTile2;
				if (!mNavMesh.GetPolyAndTile(neighborRef2, out neighborPoly2, out neighborTile2))
					continue;

				if (!mSlicedFilter.PassFilter(neighborRef2, neighborPoly2))
					continue;

				float[3] edgeMid;
				GetEdgeMidpoint(bestTile, bestPoly, e, out edgeMid);

				float curCost2 = mSlicedFilter.GetCost(bestNode.Position, edgeMid, bestNode.PolyRef, bestPoly);
				float newCost2 = bestNode.CostFromStart + curCost2;
				float heuristic2 = Heuristic(edgeMid, mSlicedEndPos);
				float totalCost2 = newCost2 + heuristic2;

				let neighborNode2 = mNodePool.GetNode(neighborRef2);
				if (neighborNode2 == null) continue;

				if (neighborNode2.Flags == .None)
				{
					neighborNode2.Position = edgeMid;
					neighborNode2.CostFromStart = newCost2;
					neighborNode2.TotalCost = totalCost2;
					neighborNode2.ParentIndex = bestNode.Index;
					neighborNode2.Flags = .Open;
					mOpenList.Push(neighborNode2);

					if (heuristic2 < mSlicedLastBestCost)
					{
						mSlicedLastBestCost = heuristic2;
						mSlicedLastBestNode = neighborNode2;
					}
				}
				else if (newCost2 < neighborNode2.CostFromStart)
				{
					neighborNode2.Position = edgeMid;
					neighborNode2.CostFromStart = newCost2;
					neighborNode2.TotalCost = totalCost2;
					neighborNode2.ParentIndex = bestNode.Index;

					if (neighborNode2.Flags == .Closed)
					{
						neighborNode2.Flags = .Open;
						mOpenList.Push(neighborNode2);
					}
					else
					{
						mOpenList.Update(neighborNode2);
					}

					if (heuristic2 < mSlicedLastBestCost)
					{
						mSlicedLastBestCost = heuristic2;
						mSlicedLastBestNode = neighborNode2;
					}
				}
			}
		}

		// If open list is empty, we've exhausted all reachable nodes
		if (mOpenList.IsEmpty)
			mSlicedStatus = .Partial;

		return iter;
	}

	/// Finalizes the sliced pathfinding query and returns the result path.
	/// Must be called after UpdateSlicedFindPath returns Complete or Partial.
	public NavStatus FinalizeSlicedFindPath(List<PolyRef> path)
	{
		path.Clear();

		if (mSlicedStatus == .None || mSlicedStatus == .InProgress)
			return .InvalidParam;

		if (mSlicedLastBestNode == null)
			return .PathNotFound;

		// Handle trivial case
		if (mSlicedStartRef == mSlicedEndRef)
		{
			path.Add(mSlicedStartRef);
			mSlicedStatus = .None;
			return .Success;
		}

		// Reconstruct path from lastBestNode
		NavNode node = mSlicedLastBestNode;
		int32 pathLen = 0;
		while (node != null && pathLen < mSlicedMaxPath)
		{
			pathLen++;
			if (node.ParentIndex < 0) break;
			node = mNodePool.GetNodeAtIndex(node.ParentIndex);
		}

		// Build path in correct order
		node = mSlicedLastBestNode;
		let tempPath = scope PolyRef[pathLen];
		int32 idx = pathLen - 1;
		while (node != null && idx >= 0)
		{
			tempPath[idx] = node.PolyRef;
			idx--;
			if (node.ParentIndex < 0) break;
			node = mNodePool.GetNodeAtIndex(node.ParentIndex);
		}

		for (int32 i = 0; i < pathLen; i++)
			path.Add(tempPath[i]);

		let result = (mSlicedStatus == .Complete) ? NavStatus.Success : NavStatus.PartialResult;
		mSlicedStatus = .None;
		return result;
	}

	/// Converts a polygon path corridor to a straight path (waypoints) using the funnel algorithm.
	public NavStatus FindStraightPath(float[3] startPos, float[3] endPos,
		List<PolyRef> path,
		List<float> straightPath, List<StraightPathFlags> straightPathFlags, List<PolyRef> straightPathRefs,
		int32 maxStraightPath = 256)
	{
		straightPath.Clear();
		straightPathFlags.Clear();
		straightPathRefs.Clear();

		if (path.Count == 0)
			return .InvalidParam;

		// Add start point
		AddStraightPathPoint(startPos, .Start, path[0], straightPath, straightPathFlags, straightPathRefs);

		if (path.Count == 1)
		{
			AddStraightPathPoint(endPos, .End, path[0], straightPath, straightPathFlags, straightPathRefs);
			return .Success;
		}

		// Funnel algorithm
		float[3] portalApex = startPos;
		float[3] portalLeft = startPos;
		float[3] portalRight = startPos;
		int32 apexIndex = 0;
		int32 leftIndex = 0;
		int32 rightIndex = 0;

		for (int32 i = 1; i <= path.Count && straightPath.Count / 3 < maxStraightPath; i++)
		{
			float[3] left, right;

			if (i < path.Count)
			{
				// Get portal between path[i-1] and path[i]
				GetPortalPoints(path[i - 1], path[i], out left, out right);
			}
			else
			{
				// Last segment - use end position
				left = endPos;
				right = endPos;
			}

			// Right side
			if (TriArea2D(portalApex, portalRight, right) <= 0.0f)
			{
				if (VEqual(portalApex, portalRight) || TriArea2D(portalApex, portalLeft, right) > 0.0f)
				{
					// Tighten the funnel
					portalRight = right;
					rightIndex = i;
				}
				else
				{
					// Right over left, insert left to path
					if (!VEqual(portalLeft, portalApex))
					{
						AddStraightPathPoint(portalLeft, .None, path[Math.Min(leftIndex, (int32)path.Count - 1)],
							straightPath, straightPathFlags, straightPathRefs);

						if (straightPath.Count / 3 >= maxStraightPath)
							break;
					}

					portalApex = portalLeft;
					apexIndex = leftIndex;
					portalLeft = portalApex;
					portalRight = portalApex;
					leftIndex = apexIndex;
					rightIndex = apexIndex;
					i = apexIndex;
					continue;
				}
			}

			// Left side
			if (TriArea2D(portalApex, portalLeft, left) >= 0.0f)
			{
				if (VEqual(portalApex, portalLeft) || TriArea2D(portalApex, portalRight, left) < 0.0f)
				{
					// Tighten the funnel
					portalLeft = left;
					leftIndex = i;
				}
				else
				{
					// Left over right, insert right to path
					if (!VEqual(portalRight, portalApex))
					{
						AddStraightPathPoint(portalRight, .None, path[Math.Min(rightIndex, (int32)path.Count - 1)],
							straightPath, straightPathFlags, straightPathRefs);

						if (straightPath.Count / 3 >= maxStraightPath)
							break;
					}

					portalApex = portalRight;
					apexIndex = rightIndex;
					portalLeft = portalApex;
					portalRight = portalApex;
					leftIndex = apexIndex;
					rightIndex = apexIndex;
					i = apexIndex;
					continue;
				}
			}
		}

		// Add end point
		if (straightPath.Count / 3 < maxStraightPath)
		{
			AddStraightPathPoint(endPos, .End, path[path.Count - 1], straightPath, straightPathFlags, straightPathRefs);
		}

		return .Success;
	}

	/// Helper to add a point to the straight path output.
	private void AddStraightPathPoint(float[3] pos, StraightPathFlags flags, PolyRef polyRef,
		List<float> path, List<StraightPathFlags> pathFlags, List<PolyRef> pathRefs)
	{
		path.Add(pos[0]);
		path.Add(pos[1]);
		path.Add(pos[2]);
		pathFlags.Add(flags);
		pathRefs.Add(polyRef);
	}

	/// Gets the portal points (left and right edge vertices) between two adjacent polygons.
	private void GetPortalPoints(PolyRef fromRef, PolyRef toRef, out float[3] left, out float[3] right)
	{
		left = .(0, 0, 0);
		right = .(0, 0, 0);

		NavPoly fromPoly;
		NavMeshTile fromTile;
		if (!mNavMesh.GetPolyAndTile(fromRef, out fromPoly, out fromTile)) return;

		NavPoly toPoly;
		NavMeshTile toTile;
		if (!mNavMesh.GetPolyAndTile(toRef, out toPoly, out toTile)) return;

		// Find the shared edge
		for (int32 i = 0; i < fromPoly.VertexCount; i++)
		{
			int32 iNext = (i + 1) % (int32)fromPoly.VertexCount;
			uint16 va = fromPoly.VertexIndices[i];
			uint16 vb = fromPoly.VertexIndices[iNext];

			// Check if this edge connects to the target polygon
			// Via neighbor index
			uint16 neighbor = fromPoly.Neighbors[i];
			if (neighbor != 0 && neighbor <= NavMeshConstants.ExternalLink)
			{
				PolyRef neighborRef = mNavMesh.EncodePolyRef(fromTile, (int32)(neighbor - 1));
				if (neighborRef == toRef)
				{
					int32 viA = (int32)va * 3;
					int32 viB = (int32)vb * 3;
					left[0] = fromTile.Vertices[viA];
					left[1] = fromTile.Vertices[viA + 1];
					left[2] = fromTile.Vertices[viA + 2];
					right[0] = fromTile.Vertices[viB];
					right[1] = fromTile.Vertices[viB + 1];
					right[2] = fromTile.Vertices[viB + 2];
					return;
				}
			}

			// Also check via links
			int32 linkIdx = fromPoly.FirstLink;
			while (linkIdx >= 0 && linkIdx < fromTile.LinkCount)
			{
				ref NavMeshLink link = ref fromTile.Links[linkIdx];
				if (link.Reference == toRef && link.Edge == i)
				{
					int32 viA = (int32)va * 3;
					int32 viB = (int32)vb * 3;
					left[0] = fromTile.Vertices[viA];
					left[1] = fromTile.Vertices[viA + 1];
					left[2] = fromTile.Vertices[viA + 2];
					right[0] = fromTile.Vertices[viB];
					right[1] = fromTile.Vertices[viB + 1];
					right[2] = fromTile.Vertices[viB + 2];
					return;
				}
				linkIdx = link.Next;
			}
		}

		// Fallback: if no shared edge found via links, try matching vertex positions
		for (int32 i = 0; i < fromPoly.VertexCount; i++)
		{
			int32 iNext = (i + 1) % (int32)fromPoly.VertexCount;
			float[3] edgeA, edgeB;
			edgeA[0] = fromTile.Vertices[(int32)fromPoly.VertexIndices[i] * 3];
			edgeA[1] = fromTile.Vertices[(int32)fromPoly.VertexIndices[i] * 3 + 1];
			edgeA[2] = fromTile.Vertices[(int32)fromPoly.VertexIndices[i] * 3 + 2];
			edgeB[0] = fromTile.Vertices[(int32)fromPoly.VertexIndices[iNext] * 3];
			edgeB[1] = fromTile.Vertices[(int32)fromPoly.VertexIndices[iNext] * 3 + 1];
			edgeB[2] = fromTile.Vertices[(int32)fromPoly.VertexIndices[iNext] * 3 + 2];

			for (int32 j = 0; j < toPoly.VertexCount; j++)
			{
				int32 jNext = (j + 1) % (int32)toPoly.VertexCount;
				float[3] toEdgeA, toEdgeB;
				toEdgeA[0] = toTile.Vertices[(int32)toPoly.VertexIndices[j] * 3];
				toEdgeA[1] = toTile.Vertices[(int32)toPoly.VertexIndices[j] * 3 + 1];
				toEdgeA[2] = toTile.Vertices[(int32)toPoly.VertexIndices[j] * 3 + 2];
				toEdgeB[0] = toTile.Vertices[(int32)toPoly.VertexIndices[jNext] * 3];
				toEdgeB[1] = toTile.Vertices[(int32)toPoly.VertexIndices[jNext] * 3 + 1];
				toEdgeB[2] = toTile.Vertices[(int32)toPoly.VertexIndices[jNext] * 3 + 2];

				// Shared edge has reversed winding
				if (VNear(edgeA, toEdgeB) && VNear(edgeB, toEdgeA))
				{
					left = edgeA;
					right = edgeB;
					return;
				}
			}
		}
	}

	/// Gets the midpoint of a portal between two adjacent polygons.
	private void GetPortalMidpoint(PolyRef fromRef, in NavPoly fromPoly, NavMeshTile fromTile,
		PolyRef toRef, in NavPoly toPoly, NavMeshTile toTile, out float[3] mid)
	{
		float[3] left, right;
		GetPortalPoints(fromRef, toRef, out left, out right);
		mid[0] = (left[0] + right[0]) * 0.5f;
		mid[1] = (left[1] + right[1]) * 0.5f;
		mid[2] = (left[2] + right[2]) * 0.5f;
	}

	/// Gets the midpoint of an edge on a polygon.
	private void GetEdgeMidpoint(NavMeshTile tile, in NavPoly poly, int32 edge, out float[3] mid)
	{
		int32 iNext = (edge + 1) % (int32)poly.VertexCount;
		int32 va = (int32)poly.VertexIndices[edge] * 3;
		int32 vb = (int32)poly.VertexIndices[iNext] * 3;
		mid[0] = (tile.Vertices[va] + tile.Vertices[vb]) * 0.5f;
		mid[1] = (tile.Vertices[va + 1] + tile.Vertices[vb + 1]) * 0.5f;
		mid[2] = (tile.Vertices[va + 2] + tile.Vertices[vb + 2]) * 0.5f;
	}

	/// Euclidean distance heuristic for A*.
	private static float Heuristic(float[3] a, float[3] b)
	{
		float dx = b[0] - a[0];
		float dy = b[1] - a[1];
		float dz = b[2] - a[2];
		return Math.Sqrt(dx * dx + dy * dy + dz * dz);
	}

	/// Signed triangle area in 2D (XZ plane).
	private static float TriArea2D(float[3] a, float[3] b, float[3] c)
	{
		float abx = b[0] - a[0];
		float abz = b[2] - a[2];
		float acx = c[0] - a[0];
		float acz = c[2] - a[2];
		return acx * abz - abx * acz;
	}

	/// Checks if two 3D points are approximately equal.
	private static bool VEqual(float[3] a, float[3] b)
	{
		const float eps = 0.001f;
		float dx = a[0] - b[0];
		float dy = a[1] - b[1];
		float dz = a[2] - b[2];
		return (dx * dx + dy * dy + dz * dz) < eps * eps;
	}

	/// Checks if two 3D points are near each other (for vertex matching).
	private static bool VNear(float[3] a, float[3] b)
	{
		const float eps = 0.01f;
		float dx = a[0] - b[0];
		float dy = a[1] - b[1];
		float dz = a[2] - b[2];
		return (dx * dx + dy * dy + dz * dz) < eps * eps;
	}

	/// Finds the closest point on the navmesh to the given position.
	public NavStatus ClosestPointOnPoly(PolyRef polyRef, float[3] pos, out float[3] closest)
	{
		closest = pos;
		if (!mNavMesh.IsValidPolyRef(polyRef))
			return .InvalidParam;

		mNavMesh.ClosestPointOnPoly(polyRef, pos, out closest);
		return .Success;
	}

	/// Gets the height at the specified position on the given polygon.
	/// Uses the detail mesh for accurate height interpolation when available.
	public NavStatus GetPolyHeight(PolyRef polyRef, float[3] pos, out float height)
	{
		height = 0;

		NavPoly poly;
		NavMeshTile tile;
		if (!mNavMesh.GetPolyAndTile(polyRef, out poly, out tile))
			return .InvalidParam;

		int32 polyIdx = mNavMesh.DecodePolyIndex(polyRef);

		// Try detail mesh first for accurate height
		if (tile.DetailMeshes != null && polyIdx < tile.DetailMeshCount)
		{
			ref NavPolyDetail detail = ref tile.DetailMeshes[polyIdx];

			// Check each detail triangle
			for (int32 ti = 0; ti < detail.TriCount; ti++)
			{
				int32 triBase = (detail.TriBase + ti) * 4;
				float[3][3] triVerts = .();

				for (int32 vi = 0; vi < 3; vi++)
				{
					int32 vertIdx = (int32)tile.DetailTriangles[triBase + vi];
					if (vertIdx < poly.VertexCount)
					{
						// Polygon vertex
						int32 pvIdx = (int32)poly.VertexIndices[vertIdx] * 3;
						triVerts[vi] = .(tile.Vertices[pvIdx], tile.Vertices[pvIdx + 1], tile.Vertices[pvIdx + 2]);
					}
					else
					{
						// Detail vertex
						int32 dvIdx = (detail.VertBase + vertIdx - (int32)poly.VertexCount) * 3;
						triVerts[vi] = .(tile.DetailVertices[dvIdx], tile.DetailVertices[dvIdx + 1], tile.DetailVertices[dvIdx + 2]);
					}
				}

					// Check if pos projects inside this triangle (XZ plane)
				float h;
				if (ClosestHeightPointTriangle(pos, triVerts[0], triVerts[1], triVerts[2], out h))
				{
					height = h;
					return .Success;
				}
			}
		}

		// Fallback: interpolate height from polygon vertices
		float[3] closest;
		mNavMesh.ClosestPointOnPoly(polyRef, pos, out closest);
		height = closest[1];
		return .Success;
	}

	/// Casts a ray along the navmesh surface from start to end position.
	/// Returns the parameter t along the ray where it hits a boundary (0..1, 1 = reached end).
	public NavStatus Raycast(PolyRef startRef, float[3] startPos, float[3] endPos,
		INavMeshQueryFilter filter, out float hitT, out float[3] hitNormal, List<PolyRef> path)
	{
		hitT = 1.0f;
		hitNormal = .(0, 0, 0);

		if (!startRef.IsValid)
			return .InvalidParam;

		path?.Clear();

		PolyRef curRef = startRef;

		for (int32 iter = 0; iter < 256; iter++)
		{
			path?.Add(curRef);

			NavPoly poly;
			NavMeshTile tile;
			if (!mNavMesh.GetPolyAndTile(curRef, out poly, out tile))
				break;

			// Find the edge that the ray crosses
			float tMin = float.MaxValue;
			int32 crossEdge = -1;
			float[3] crossNormal = .(0, 0, 0);

			for (int32 e = 0; e < poly.VertexCount; e++)
			{
				int32 eNext = (e + 1) % (int32)poly.VertexCount;
				int32 va = (int32)poly.VertexIndices[e] * 3;
				int32 vb = (int32)poly.VertexIndices[eNext] * 3;

				float[3] edgeA = .(tile.Vertices[va], tile.Vertices[va + 1], tile.Vertices[va + 2]);
				float[3] edgeB = .(tile.Vertices[vb], tile.Vertices[vb + 1], tile.Vertices[vb + 2]);

				float segT, rayT;
				if (IntersectSegmentSegment2D(startPos, endPos, edgeA, edgeB, out rayT, out segT))
				{
					if (rayT >= 0 && segT >= 0 && segT <= 1.0f && rayT < tMin)
					{
						tMin = rayT;
						crossEdge = e;

						// Compute edge normal (perpendicular in XZ)
						float edx = edgeB[0] - edgeA[0];
						float edz = edgeB[2] - edgeA[2];
						float len = Math.Sqrt(edx * edx + edz * edz);
						if (len > 0)
						{
							crossNormal[0] = edz / len;
							crossNormal[1] = 0;
							crossNormal[2] = -edx / len;
						}
					}
				}
			}

			if (crossEdge < 0 || tMin > 1.0f)
			{
				// Ray stays within this polygon or reaches end
				hitT = 1.0f;
				return .Success;
			}

			// Check if there's a neighbor on this edge
			uint16 neighbor = poly.Neighbors[crossEdge];
			if (neighbor != 0 && neighbor < NavMeshConstants.ExternalLink)
			{
				PolyRef neighborRef = mNavMesh.EncodePolyRef(tile, (int32)(neighbor - 1));
				NavPoly neighborPoly;
				NavMeshTile neighborTile;
				if (mNavMesh.GetPolyAndTile(neighborRef, out neighborPoly, out neighborTile))
				{
					if (filter.PassFilter(neighborRef, neighborPoly))
					{
						curRef = neighborRef;
						continue;
					}
				}
			}

			// Hit a wall (no passable neighbor)
			hitT = Math.Clamp(tMin, 0.0f, 1.0f);
			hitNormal = crossNormal;
			return .Success;
		}

		return .Success;
	}

	/// Moves along the navmesh surface from startPos toward endPos, constrained to the mesh.
	/// Returns the resulting position and visited polygon list.
	public NavStatus MoveAlongSurface(PolyRef startRef, float[3] startPos, float[3] endPos,
		INavMeshQueryFilter filter, out float[3] resultPos, List<PolyRef> visited)
	{
		resultPos = startPos;
		visited?.Clear();

		if (!startRef.IsValid)
			return .InvalidParam;

		// Use a simple iterative approach: try to move toward endPos,
		// stopping at polygon boundaries and crossing to neighbors.
		PolyRef curRef = startRef;
		float[3] curPos = startPos;
		float[3] targetPos = endPos;

		for (int32 iter = 0; iter < 64; iter++)
		{
			visited?.Add(curRef);

			NavPoly poly;
			NavMeshTile tile;
			if (!mNavMesh.GetPolyAndTile(curRef, out poly, out tile))
				break;

			// Check if targetPos is inside the current polygon
			if (PointInPoly2D(targetPos, tile, poly))
			{
				resultPos = targetPos;
				// Snap Y to polygon height
				float h;
				if (GetPolyHeight(curRef, targetPos, out h) == .Success)
					resultPos[1] = h;
				return .Success;
			}

			// Find the closest edge intersection
			float bestDist = float.MaxValue;
			int32 bestEdge = -1;
			float[3] bestPoint = curPos;

			for (int32 e = 0; e < poly.VertexCount; e++)
			{
				int32 eNext = (e + 1) % (int32)poly.VertexCount;
				int32 va = (int32)poly.VertexIndices[e] * 3;
				int32 vb = (int32)poly.VertexIndices[eNext] * 3;

				float[3] edgeA = .(tile.Vertices[va], tile.Vertices[va + 1], tile.Vertices[va + 2]);
				float[3] edgeB = .(tile.Vertices[vb], tile.Vertices[vb + 1], tile.Vertices[vb + 2]);

				// Project targetPos onto this edge
				float[3] edgePoint;
				ClosestPointOnSegment(targetPos, edgeA, edgeB, out edgePoint);

				float dx = edgePoint[0] - targetPos[0];
				float dz = edgePoint[2] - targetPos[2];
				float dist = dx * dx + dz * dz;

				if (dist < bestDist)
				{
					bestDist = dist;
					bestEdge = e;
					bestPoint = edgePoint;
				}
			}

			if (bestEdge < 0)
				break;

			// Try to cross to neighbor
			uint16 neighbor = poly.Neighbors[bestEdge];
			if (neighbor != 0 && neighbor < NavMeshConstants.ExternalLink)
			{
				PolyRef neighborRef = mNavMesh.EncodePolyRef(tile, (int32)(neighbor - 1));
				NavPoly neighborPoly;
				NavMeshTile neighborTile;
				if (mNavMesh.GetPolyAndTile(neighborRef, out neighborPoly, out neighborTile))
				{
					if (filter.PassFilter(neighborRef, neighborPoly))
					{
						curRef = neighborRef;
						curPos = bestPoint;
						continue;
					}
				}
			}

			// Can't cross - clamp to edge
			resultPos = bestPoint;
			float h2;
			if (GetPolyHeight(curRef, bestPoint, out h2) == .Success)
				resultPos[1] = h2;
			return .Success;
		}

		resultPos = curPos;
		return .Success;
	}

	/// Finds all polygons within a circle centered at the given position.
	public NavStatus FindPolysAroundCircle(PolyRef startRef, float[3] centerPos, float radius,
		INavMeshQueryFilter filter, List<PolyRef> resultRefs, List<PolyRef> resultParents,
		List<float> resultCosts, int32 maxResult = 128)
	{
		resultRefs?.Clear();
		resultParents?.Clear();
		resultCosts?.Clear();

		if (!startRef.IsValid)
			return .InvalidParam;

		float radiusSq = radius * radius;

		// BFS from start polygon
		let openList = scope List<PolyRef>();
		let visited = scope List<PolyRef>();

		openList.Add(startRef);
		visited.Add(startRef);
		resultRefs?.Add(startRef);
		resultParents?.Add(.Null);
		resultCosts?.Add(0);

		while (openList.Count > 0 && (resultRefs == null || resultRefs.Count < maxResult))
		{
			PolyRef curRef = openList[0];
			openList.RemoveAt(0);

			NavPoly poly;
			NavMeshTile tile;
			if (!mNavMesh.GetPolyAndTile(curRef, out poly, out tile))
				continue;

			// Check all neighbor edges
			for (int32 e = 0; e < poly.VertexCount; e++)
			{
				uint16 neighbor = poly.Neighbors[e];
				if (neighbor == 0 || neighbor >= NavMeshConstants.ExternalLink)
					continue;

				PolyRef neighborRef = mNavMesh.EncodePolyRef(tile, (int32)(neighbor - 1));

				// Skip if already visited
				bool alreadyVisited = false;
				for (let v in visited)
				{
					if (v == neighborRef)
					{
						alreadyVisited = true;
						break;
					}
				}
				if (alreadyVisited) continue;

				NavPoly neighborPoly;
				NavMeshTile neighborTile;
				if (!mNavMesh.GetPolyAndTile(neighborRef, out neighborPoly, out neighborTile))
					continue;

				if (!filter.PassFilter(neighborRef, neighborPoly))
					continue;

				// Check if polygon is within radius
				float[3] closestPoint;
				mNavMesh.ClosestPointOnPoly(neighborRef, centerPos, out closestPoint);

				float dx = closestPoint[0] - centerPos[0];
				float dz = closestPoint[2] - centerPos[2];
				float distSq = dx * dx + dz * dz;

				if (distSq > radiusSq)
				{
					visited.Add(neighborRef);
					continue;
				}

				// Add to results
				visited.Add(neighborRef);
				openList.Add(neighborRef);
				resultRefs?.Add(neighborRef);
				resultParents?.Add(curRef);
				resultCosts?.Add(Math.Sqrt(distSq));
			}
		}

		return .Success;
	}

	/// Tests if a point (in XZ) is inside a polygon.
	private bool PointInPoly2D(float[3] pos, NavMeshTile tile, in NavPoly poly)
	{
		bool inside = false;
		int32 n = (int32)poly.VertexCount;

		int32 j = n - 1;
		for (int32 i = 0; i < n; j = i, i++)
		{
			int32 vi = (int32)poly.VertexIndices[i] * 3;
			int32 vj = (int32)poly.VertexIndices[j] * 3;
			float xi = tile.Vertices[vi], zi = tile.Vertices[vi + 2];
			float xj = tile.Vertices[vj], zj = tile.Vertices[vj + 2];

			if (((zi > pos[2]) != (zj > pos[2])) &&
				(pos[0] < (xj - xi) * (pos[2] - zi) / (zj - zi) + xi))
			{
				inside = !inside;
			}
		}
		return inside;
	}

	/// Finds the closest point on a line segment to a given point.
	private static void ClosestPointOnSegment(float[3] pt, float[3] segA, float[3] segB, out float[3] closest)
	{
		float dx = segB[0] - segA[0];
		float dz = segB[2] - segA[2];
		float lenSq = dx * dx + dz * dz;

		if (lenSq < 1e-8f)
		{
			closest = segA;
			return;
		}

		float t = ((pt[0] - segA[0]) * dx + (pt[2] - segA[2]) * dz) / lenSq;
		t = Math.Clamp(t, 0.0f, 1.0f);

		closest[0] = segA[0] + t * dx;
		closest[1] = segA[1] + t * (segB[1] - segA[1]);
		closest[2] = segA[2] + t * dz;
	}

	/// Intersects two 2D line segments (in XZ plane). Returns true if they intersect.
	private static bool IntersectSegmentSegment2D(float[3] p0, float[3] p1, float[3] q0, float[3] q1,
		out float tP, out float tQ)
	{
		tP = 0;
		tQ = 0;

		float d0x = p1[0] - p0[0];
		float d0z = p1[2] - p0[2];
		float d1x = q1[0] - q0[0];
		float d1z = q1[2] - q0[2];

		float denom = d0x * d1z - d0z * d1x;
		if (Math.Abs(denom) < 1e-8f)
			return false;

		float dx = q0[0] - p0[0];
		float dz = q0[2] - p0[2];

		tP = (dx * d1z - dz * d1x) / denom;
		tQ = (dx * d0z - dz * d0x) / denom;

		return true;
	}

	/// Checks if point P projects inside triangle ABC in XZ, and returns interpolated height.
	private static bool ClosestHeightPointTriangle(float[3] p, float[3] a, float[3] b, float[3] c, out float h)
	{
		h = 0;

		float[2] v0 = .(c[0] - a[0], c[2] - a[2]);
		float[2] v1 = .(b[0] - a[0], b[2] - a[2]);
		float[2] v2 = .(p[0] - a[0], p[2] - a[2]);

		float dot00 = v0[0] * v0[0] + v0[1] * v0[1];
		float dot01 = v0[0] * v1[0] + v0[1] * v1[1];
		float dot02 = v0[0] * v2[0] + v0[1] * v2[1];
		float dot11 = v1[0] * v1[0] + v1[1] * v1[1];
		float dot12 = v1[0] * v2[0] + v1[1] * v2[1];

		float invDenom = 1.0f / (dot00 * dot11 - dot01 * dot01);
		float u = (dot11 * dot02 - dot01 * dot12) * invDenom;
		float v = (dot00 * dot12 - dot01 * dot02) * invDenom;

		const float eps = -1e-4f;
		if (u >= eps && v >= eps && (u + v) <= 1.0f + 1e-4f)
		{
			h = a[1] * (1.0f - u - v) + c[1] * u + b[1] * v;
			return true;
		}

		return false;
	}

	/// Decodes the polygon index from a PolyRef (delegates to NavMesh).
	private int32 DecodePolyIndex(PolyRef polyRef)
	{
		return mNavMesh.DecodePolyIndex(polyRef);
	}
}

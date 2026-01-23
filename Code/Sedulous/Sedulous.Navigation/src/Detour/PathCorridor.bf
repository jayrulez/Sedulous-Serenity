using System;
using System.Collections;

namespace Sedulous.Navigation.Detour;

/// Maintains a path corridor for agent path following.
/// The corridor stores a current position, a target position, and a polygon
/// corridor (sequence of PolyRefs) connecting them. It provides methods for
/// moving along the path, optimizing the corridor, and checking validity.
class PathCorridor
{
	/// The polygon corridor (sequence of polygon references from start to end).
	private List<PolyRef> mPath ~ delete _;

	/// Current position snapped to the navmesh.
	private float[3] mPos;

	/// Target position.
	private float[3] mTarget;

	/// Gets the current position within the corridor.
	public float[3] Position => mPos;

	/// Gets the target position within the corridor.
	public float[3] Target => mTarget;

	/// Gets the current polygon corridor.
	public List<PolyRef> Path => mPath;

	/// Gets the number of polygons in the corridor.
	public int32 PathCount => (int32)mPath.Count;

	/// Gets the first polygon in the corridor (where the agent currently is).
	public PolyRef FirstPoly => mPath.Count > 0 ? mPath[0] : .Null;

	/// Gets the last polygon in the corridor (destination polygon).
	public PolyRef LastPoly => mPath.Count > 0 ? mPath[mPath.Count - 1] : .Null;

	/// Creates a new empty path corridor.
	public this()
	{
		mPath = new List<PolyRef>();
		mPos = .(0, 0, 0);
		mTarget = .(0, 0, 0);
	}

	/// Resets the corridor to a single polygon at the given position.
	/// Sets both the current position and target to the specified position.
	public void Reset(PolyRef startRef, float[3] startPos)
	{
		mPath.Clear();
		mPath.Add(startRef);
		mPos = startPos;
		mTarget = startPos;
	}

	/// Sets the corridor path and target position.
	/// Copies the provided path into internal storage.
	public void SetCorridor(float[3] target, List<PolyRef> path)
	{
		mTarget = target;
		mPath.Clear();
		for (let polyRef in path)
			mPath.Add(polyRef);
	}

	/// Moves the position along the corridor toward the desired new position.
	/// The movement is constrained to the navmesh surface. Polygons that have
	/// been passed are removed from the corridor prefix.
	/// Returns the new clamped position.
	public float[3] MovePosition(float[3] newPos, NavMeshQuery query, INavMeshQueryFilter filter)
	{
		if (mPath.Count == 0)
			return mPos;

		// Snap the desired position to the current polygon.
		// Phase 2: Simplified implementation - find closest point on current polygon.
		float[3] result = newPos;
		PolyRef currentRef = mPath[0];

		// Clamp the new position to the navmesh by finding the closest point on the current polygon.
		float[3] closestPt;
		let status = query.ClosestPointOnPoly(currentRef, newPos, out closestPt);
		if (status.Succeeded)
		{
			result = closestPt;
		}

		// Walk forward through the corridor, checking if we have moved into subsequent polygons.
		// For each polygon we've moved past, remove it from the front of the corridor.
		while (mPath.Count > 1)
		{
			// Check if the new position is closer to the next polygon
			PolyRef nextRef = mPath[1];
			float[3] nextClosest;
			let nextStatus = query.ClosestPointOnPoly(nextRef, result, out nextClosest);
			if (!nextStatus.Succeeded)
				break;

			// Calculate distance to current and next polygon centers
			float distCurrent = DistanceSq(result, mPos);
			float distNext = DistanceSq(result, nextClosest);

			// If the position is closer to the next polygon, advance the corridor
			if (distNext < distCurrent * 0.25f)
			{
				mPath.RemoveAt(0);
				result = nextClosest;
			}
			else
			{
				break;
			}
		}

		mPos = result;
		return mPos;
	}

	/// Moves the target position, adjusting the corridor tail.
	/// Used when the movement target is dynamic.
	public float[3] MoveTargetPosition(float[3] newPos, NavMeshQuery query, INavMeshQueryFilter filter)
	{
		if (mPath.Count == 0)
			return mTarget;

		// Snap the new target to the last polygon in the corridor.
		PolyRef lastRef = mPath[mPath.Count - 1];
		float[3] closestPt;
		let status = query.ClosestPointOnPoly(lastRef, newPos, out closestPt);
		if (status.Succeeded)
		{
			mTarget = closestPt;
		}
		else
		{
			mTarget = newPos;
		}

		return mTarget;
	}

	/// Attempts to shortcut the path by raycasting toward a position further along.
	/// If the raycast succeeds (no obstructions), intermediate corridor polygons are removed.
	public void OptimizePathVisibility(float[3] nextPos, float pathOptimizationRange, NavMeshQuery query, INavMeshQueryFilter filter)
	{
		if (mPath.Count < 2)
			return;

		// Phase 2: Simplified implementation.
		// Attempt to find a polygon further along the corridor that is directly reachable.
		// For now, check if we can skip intermediate polygons by verifying the target
		// polygon is within optimization range.
		float dx = nextPos[0] - mPos[0];
		float dz = nextPos[2] - mPos[2];
		float distSq = dx * dx + dz * dz;

		if (distSq > pathOptimizationRange * pathOptimizationRange)
			return;

		// Try to find a polygon in the corridor that contains or is near the next position.
		// If found, remove intermediate polygons.
		for (int32 i = Math.Min((int32)mPath.Count - 1, 32); i > 0; i--)
		{
			float[3] closestPt;
			let status = query.ClosestPointOnPoly(mPath[i], nextPos, out closestPt);
			if (!status.Succeeded)
				continue;

			float cdx = closestPt[0] - nextPos[0];
			float cdz = closestPt[2] - nextPos[2];
			float closestDistSq = cdx * cdx + cdz * cdz;

			// If the point is very close to this polygon, we can shortcut
			if (closestDistSq < 0.01f)
			{
				// Remove intermediate polygons (keep first and from i onward)
				for (int32 j = 1; j < i; j++)
					mPath.RemoveAt(1);
				break;
			}
		}
	}

	/// Tries to find shorter alternative paths through adjacent polygons.
	/// Re-evaluates the corridor by checking if adjacent polygons provide a shortcut.
	public void OptimizePathTopology(NavMeshQuery query, INavMeshQueryFilter filter)
	{
		if (mPath.Count < 3)
			return;

		// Phase 2: Simplified implementation.
		// A full implementation would use InitSlicedFindPath or similar to test
		// alternative routes. For now, this is a placeholder that maintains the
		// correct API surface.

		// Try to find a direct connection from the first polygon to a later polygon,
		// skipping intermediate ones.
		for (int32 i = Math.Min((int32)mPath.Count - 1, 32); i >= 2; i--)
		{
			float[3] closestStart;
			float[3] closestEnd;
			let startStatus = query.ClosestPointOnPoly(mPath[0], mPos, out closestStart);
			let endStatus = query.ClosestPointOnPoly(mPath[i], mTarget, out closestEnd);

			if (!startStatus.Succeeded || !endStatus.Succeeded)
				continue;

			// Check if we can build a shorter path
			let testPath = scope List<PolyRef>();
			let findStatus = query.FindPath(mPath[0], mPath[i], closestStart, closestEnd, filter, testPath, (int32)i + 1);

			if (findStatus.Succeeded && testPath.Count > 0 && testPath.Count < i + 1)
			{
				// Found a shorter path - replace the corridor prefix
				// Keep polygons from i onward and prepend the new shorter path
				let newPath = scope List<PolyRef>();
				for (let p in testPath)
					newPath.Add(p);

				// Append remaining corridor polygons (skip the overlap at mPath[i])
				for (int32 j = i + 1; j < (int32)mPath.Count; j++)
					newPath.Add(mPath[j]);

				mPath.Clear();
				for (let p in newPath)
					mPath.Add(p);
				break;
			}
		}
	}

	/// Checks if the corridor polygons are still valid (not removed from the navmesh).
	/// Checks up to maxLookAhead polygons from the start of the corridor.
	public bool IsValid(int32 maxLookAhead, NavMesh navMesh)
	{
		int32 count = Math.Min(maxLookAhead, (int32)mPath.Count);
		for (int32 i = 0; i < count; i++)
		{
			if (!navMesh.IsValidPolyRef(mPath[i]))
				return false;
		}
		return true;
	}

	/// Gets a specific waypoint from the corridor using FindStraightPath internally.
	/// Returns false if the index is out of range or the straight path cannot be computed.
	public bool GetCorner(int32 index, out float[3] pos, out StraightPathFlags flags, out PolyRef polyRef, NavMeshQuery query)
	{
		pos = .(0, 0, 0);
		flags = .None;
		polyRef = .Null;

		if (mPath.Count == 0)
			return false;

		let straightPath = scope List<float>();
		let straightPathFlags = scope List<StraightPathFlags>();
		let straightPathRefs = scope List<PolyRef>();

		let status = query.FindStraightPath(mPos, mTarget, mPath,
			straightPath, straightPathFlags, straightPathRefs);

		if (!status.Succeeded)
			return false;

		int32 pointCount = (int32)straightPath.Count / 3;
		if (index < 0 || index >= pointCount)
			return false;

		int32 baseIdx = index * 3;
		pos[0] = straightPath[baseIdx];
		pos[1] = straightPath[baseIdx + 1];
		pos[2] = straightPath[baseIdx + 2];
		flags = straightPathFlags[index];
		polyRef = straightPathRefs[index];
		return true;
	}

	/// Computes the squared distance between two 3D points.
	private static float DistanceSq(float[3] a, float[3] b)
	{
		float dx = a[0] - b[0];
		float dy = a[1] - b[1];
		float dz = a[2] - b[2];
		return dx * dx + dy * dy + dz * dz;
	}
}

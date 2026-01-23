using System;
using System.Collections;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation;

/// High-level convenience API for navigation queries.
class NavigationQuery
{
	private NavMesh mNavMesh;
	private NavMeshQuery mQuery ~ delete _;
	private NavMeshQueryFilter mFilter ~ delete _;

	/// Initializes the query for use with the given navmesh.
	public NavStatus Init(NavMesh navMesh, int32 maxNodes = 2048)
	{
		mNavMesh = navMesh;
		mQuery = new NavMeshQuery();
		mFilter = new NavMeshQueryFilter();
		return mQuery.Init(navMesh, maxNodes);
	}

	/// Gets the underlying filter for customization.
	public NavMeshQueryFilter Filter => mFilter;

	/// Finds a path from start to end, returning world-space waypoints.
	public NavStatus FindPath(float[3] start, float[3] end, List<float> waypoints, float[3] searchExtents = .(5, 5, 5))
	{
		waypoints.Clear();

		// Find nearest polygons to start and end
		PolyRef startRef, endRef;
		float[3] startPos, endPos;

		var status = mQuery.FindNearestPoly(start, searchExtents, mFilter, out startRef, out startPos);
		if (status.Failed) return status;

		status = mQuery.FindNearestPoly(end, searchExtents, mFilter, out endRef, out endPos);
		if (status.Failed) return status;

		// Find polygon corridor
		let path = scope List<PolyRef>();
		status = mQuery.FindPath(startRef, endRef, startPos, endPos, mFilter, path);
		if (status.Failed) return status;

		// Convert to straight path
		let straightPath = scope List<float>();
		let straightFlags = scope List<StraightPathFlags>();
		let straightRefs = scope List<PolyRef>();

		status = mQuery.FindStraightPath(startPos, endPos, path, straightPath, straightFlags, straightRefs);
		if (status.Failed) return status;

		// Copy to output
		for (let v in straightPath)
			waypoints.Add(v);

		return .Success;
	}

	/// Finds the nearest point on the navmesh to the given position.
	public NavStatus FindNearestPoint(float[3] pos, out float[3] nearestPoint, float[3] searchExtents = .(5, 5, 5))
	{
		PolyRef nearestRef;
		return mQuery.FindNearestPoly(pos, searchExtents, mFilter, out nearestRef, out nearestPoint);
	}

	/// Checks if a position is on the navmesh within the given tolerance.
	public bool IsOnNavMesh(float[3] pos, float tolerance = 0.5f)
	{
		float[3] extents = .(tolerance, tolerance, tolerance);
		PolyRef nearestRef;
		float[3] nearestPoint;

		var status = mQuery.FindNearestPoly(pos, extents, mFilter, out nearestRef, out nearestPoint);
		if (status.Failed) return false;

		float dx = pos[0] - nearestPoint[0];
		float dy = pos[1] - nearestPoint[1];
		float dz = pos[2] - nearestPoint[2];
		return (dx * dx + dy * dy + dz * dz) < tolerance * tolerance;
	}
}

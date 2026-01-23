using System;

namespace Sedulous.Navigation.Detour;

/// Interface for filtering polygons during navigation queries.
interface INavMeshQueryFilter
{
	/// Returns true if the polygon can be visited/traversed.
	bool PassFilter(PolyRef polyRef, in NavPoly poly);

	/// Returns the traversal cost for moving through the polygon.
	float GetCost(float[3] a, float[3] b, PolyRef polyRef, in NavPoly poly);
}

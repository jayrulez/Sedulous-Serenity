using System;

namespace Sedulous.Navigation.Crowd;

/// Information about a neighboring agent within collision query range.
[CRepr]
struct CrowdNeighbor
{
	/// Index of the neighboring agent in the CrowdManager.
	public int32 AgentIndex;
	/// Squared distance to this neighbor.
	public float DistanceSq;
}

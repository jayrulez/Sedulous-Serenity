using System;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation.Recast;

/// Result of a navmesh build operation.
class NavMeshBuildResult
{
	/// Whether the build succeeded.
	public bool Success;
	/// Error message if the build failed.
	public String ErrorMessage ~ delete _;
	/// The built navmesh (owned by the caller).
	public NavMesh NavMesh;
	/// The intermediate polygon mesh (for debugging).
	public PolyMesh PolyMesh /*~ delete _*/;
	/// Build statistics.
	public NavMeshBuildStats Stats;

	public this()
	{
		Success = false;
		ErrorMessage = null;
		NavMesh = null;
		PolyMesh = null;
		Stats = .();
	}
}

/// Statistics from a navmesh build.
[CRepr]
struct NavMeshBuildStats
{
	public int32 VertexCount;
	public int32 PolyCount;
	public int32 SpanCount;
	public int32 RegionCount;
	public int32 ContourCount;
}

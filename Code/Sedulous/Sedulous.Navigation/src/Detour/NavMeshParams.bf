using System;

namespace Sedulous.Navigation.Detour;

/// Initialization parameters for NavMesh.
[CRepr]
struct NavMeshParams
{
	/// World-space origin of the navmesh.
	public float[3] Origin;
	/// Width of a tile in world units.
	public float TileWidth;
	/// Height (depth) of a tile in world units.
	public float TileHeight;
	/// Maximum number of tiles.
	public int32 MaxTiles;
	/// Maximum number of polygons per tile.
	public int32 MaxPolys;
}

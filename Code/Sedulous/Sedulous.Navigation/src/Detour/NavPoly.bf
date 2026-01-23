using System;

namespace Sedulous.Navigation.Detour;

/// Maximum number of vertices per navigation polygon.
static class NavMeshConstants
{
	public const int32 MaxVertsPerPoly = 6;
	public const int32 MaxAreas = 64;
	public const uint16 ExternalLink = 0x8000;
	public const int32 MaxTiles = 1 << 22;
}

/// A navigation polygon within a tile.
[CRepr]
struct NavPoly
{
	/// Indices into the tile's vertex array. Unused slots are 0xFFFF.
	public uint16[NavMeshConstants.MaxVertsPerPoly] VertexIndices;
	/// Neighbor polygon references. For each edge:
	/// - Internal neighbor: index+1 into tile's poly array
	/// - External (cross-tile): NavMeshConstants.ExternalLink | direction
	/// - No neighbor: 0
	public uint16[NavMeshConstants.MaxVertsPerPoly] Neighbors;
	/// Number of valid vertices in this polygon.
	public uint8 VertexCount;
	/// Area ID for filtering.
	public uint8 Area;
	/// User-defined flags for path filtering.
	public uint16 Flags;
	/// Type of polygon.
	public PolyType Type;
	/// Index to the first link in the tile's link array.
	public int32 FirstLink;

	public this()
	{
		VertexIndices = .();
		Neighbors = .();
		VertexCount = 0;
		Area = 0;
		Flags = 0;
		Type = .Ground;
		FirstLink = -1;
	}
}

/// Detail information for sub-triangle mesh of a polygon.
[CRepr]
struct NavPolyDetail
{
	/// Index into the tile's detail vertex array.
	public int32 VertBase;
	/// Number of detail vertices for this polygon.
	public int32 VertCount;
	/// Index into the tile's detail triangle array.
	public int32 TriBase;
	/// Number of detail triangles.
	public int32 TriCount;
}

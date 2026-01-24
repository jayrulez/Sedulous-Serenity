using System;

namespace Sedulous.Navigation.Detour;

/// A tile in the navigation mesh containing polygons and connectivity.
class NavMeshTile
{
	/// Salt for PolyRef validity checking.
	public int32 Salt;
	/// Tile grid X coordinate.
	public int32 X;
	/// Tile grid Z coordinate (Y in 2D grid terms).
	public int32 Z;
	/// Tile layer (for multi-layer tiles).
	public int32 Layer;

	/// Tile bounding box minimum.
	public float[3] BMin;
	/// Tile bounding box maximum.
	public float[3] BMax;

	/// Polygon vertices as float[3] triples.
	public float[] Vertices ~ delete _;
	/// Navigation polygons.
	public NavPoly[] Polygons ~ delete _;
	/// Links for polygon connectivity.
	public NavMeshLink[] Links ~ delete _;
	/// Detail sub-mesh information per polygon.
	public NavPolyDetail[] DetailMeshes ~ delete _;
	/// Detail mesh vertices.
	public float[] DetailVertices ~ delete _;
	/// Detail mesh triangles (indices * 4: v0, v1, v2, flags).
	public uint8[] DetailTriangles ~ delete _;

	/// Number of vertices.
	public int32 VertexCount;
	/// Number of polygons.
	public int32 PolyCount;
	/// Number of links.
	public int32 LinkCount;
	/// Maximum number of links (capacity).
	public int32 MaxLinkCount;
	/// Number of detail meshes.
	public int32 DetailMeshCount;
	/// Number of detail vertices.
	public int32 DetailVertexCount;
	/// Number of detail triangles.
	public int32 DetailTriangleCount;

	/// Index of this tile in the NavMesh tile array.
	public int32 TileIndex;

	/// Allocates a new link slot and returns its index.
	public int32 AllocLink()
	{
		if (LinkCount >= MaxLinkCount)
			return -1;
		return LinkCount++;
	}
}

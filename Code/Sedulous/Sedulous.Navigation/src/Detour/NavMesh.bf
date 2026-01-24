using System;
using System.Collections;

namespace Sedulous.Navigation.Detour;

/// The runtime navigation mesh data structure.
/// Manages tiles and provides polygon references for queries.
class NavMesh
{
	private NavMeshParams mParams;
	private NavMeshTile[] mTiles ~ { if (_ != null) { for (var t in _) delete t; delete _; } };
	private int32 mTileCount;
	private int32 mMaxTiles;
	private int32 mMaxPolys;
	private int32 mNextSalt;

	public NavMeshParams Params => mParams;
	public int32 TileCount => mTileCount;
	public int32 MaxTiles => mMaxTiles;

	/// Initializes the navmesh with the given parameters.
	public NavStatus Init(in NavMeshParams @params)
	{
		mParams = @params;
		mMaxTiles = @params.MaxTiles;
		mMaxPolys = @params.MaxPolys;
		mTiles = new NavMeshTile[mMaxTiles];
		mTileCount = 0;
		mNextSalt = 1;
		return .Success;
	}

	/// Adds a tile to the navmesh at the specified grid location.
	/// Returns the base PolyRef for polygons in this tile.
	public NavStatus AddTile(NavMeshTile tile, out PolyRef baseRef)
	{
		baseRef = .Null;

		if (mTileCount >= mMaxTiles)
			return .InvalidParam;

		// Find a free slot
		int32 tileIndex = -1;
		for (int32 i = 0; i < mMaxTiles; i++)
		{
			if (mTiles[i] == null)
			{
				tileIndex = i;
				break;
			}
		}

		if (tileIndex < 0)
			return .InvalidParam;

		tile.Salt = mNextSalt++;
		tile.TileIndex = tileIndex;
		mTiles[tileIndex] = tile;
		mTileCount++;

		// Build internal links
		BuildInternalLinks(tile);

		baseRef = PolyRef.Encode(tile.Salt, tileIndex, 0);
		return .Success;
	}

	/// Removes a tile from the navmesh.
	public NavStatus RemoveTile(int32 tileIndex)
	{
		if (tileIndex < 0 || tileIndex >= mMaxTiles)
			return .InvalidParam;

		if (mTiles[tileIndex] == null)
			return .InvalidParam;

		delete mTiles[tileIndex];
		mTiles[tileIndex] = null;
		mTileCount--;
		return .Success;
	}

	/// Gets a tile by index.
	public NavMeshTile GetTile(int32 index)
	{
		if (index < 0 || index >= mMaxTiles)
			return null;
		return mTiles[index];
	}

	/// Gets the tile containing the specified polygon reference.
	public NavMeshTile GetTileByRef(PolyRef polyRef)
	{
		if (!polyRef.IsValid) return null;
		int32 tileIdx = polyRef.TileIndex;
		if (tileIdx < 0 || tileIdx >= mMaxTiles) return null;
		let tile = mTiles[tileIdx];
		if (tile == null) return null;
		if (tile.Salt != polyRef.Salt) return null;
		return tile;
	}

	/// Gets the polygon at the specified reference.
	public bool GetPolyAndTile(PolyRef polyRef, out NavPoly poly, out NavMeshTile tile)
	{
		poly = .();
		tile = null;

		if (!polyRef.IsValid) return false;

		int32 tileIdx = polyRef.TileIndex;
		if (tileIdx < 0 || tileIdx >= mMaxTiles) return false;

		tile = mTiles[tileIdx];
		if (tile == null) return false;
		if (tile.Salt != polyRef.Salt) return false;

		int32 polyIdx = polyRef.PolyIndex;
		if (polyIdx < 0 || polyIdx >= tile.PolyCount) return false;

		poly = tile.Polygons[polyIdx];
		return true;
	}

	/// Creates a PolyRef for a polygon in the given tile.
	public PolyRef GetPolyRefBase(NavMeshTile tile)
	{
		return PolyRef.Encode(tile.Salt, tile.TileIndex, 0);
	}

	/// Encodes a reference to a specific polygon in a tile.
	public PolyRef EncodePolyRef(NavMeshTile tile, int32 polyIndex)
	{
		return PolyRef.Encode(tile.Salt, tile.TileIndex, polyIndex);
	}

	/// Decodes and returns the polygon index from a PolyRef.
	public int32 DecodePolyIndex(PolyRef polyRef)
	{
		return polyRef.PolyIndex;
	}

	/// Checks if a polygon reference is valid.
	public bool IsValidPolyRef(PolyRef polyRef)
	{
		if (!polyRef.IsValid) return false;
		int32 tileIdx = polyRef.TileIndex;
		if (tileIdx < 0 || tileIdx >= mMaxTiles) return false;
		let tile = mTiles[tileIdx];
		if (tile == null) return false;
		if (tile.Salt != polyRef.Salt) return false;
		int32 polyIdx = polyRef.PolyIndex;
		return polyIdx >= 0 && polyIdx < tile.PolyCount;
	}

	/// Gets a polygon's vertex positions.
	public void GetPolyVertices(PolyRef polyRef, float[] outVerts, out int32 vertCount)
	{
		vertCount = 0;
		NavPoly poly;
		NavMeshTile tile;
		if (!GetPolyAndTile(polyRef, out poly, out tile)) return;

		vertCount = (int32)poly.VertexCount;
		for (int32 i = 0; i < poly.VertexCount; i++)
		{
			int32 vi = (int32)poly.VertexIndices[i] * 3;
			outVerts[i * 3] = tile.Vertices[vi];
			outVerts[i * 3 + 1] = tile.Vertices[vi + 1];
			outVerts[i * 3 + 2] = tile.Vertices[vi + 2];
		}
	}

	/// Finds the closest point on a polygon to a given position.
	public void ClosestPointOnPoly(PolyRef polyRef, float[3] pos, out float[3] closest)
	{
		closest = pos;

		NavPoly poly;
		NavMeshTile tile;
		if (!GetPolyAndTile(polyRef, out poly, out tile)) return;

		int32 nv = (int32)poly.VertexCount;
		float[NavMeshConstants.MaxVertsPerPoly * 3] verts = .();

		for (int32 i = 0; i < nv; i++)
		{
			int32 vi = (int32)poly.VertexIndices[i] * 3;
			verts[i * 3] = tile.Vertices[vi];
			verts[i * 3 + 1] = tile.Vertices[vi + 1];
			verts[i * 3 + 2] = tile.Vertices[vi + 2];
		}

		ClosestPointOnConvexPoly(pos, &verts, nv, out closest);
	}

	/// Finds the closest point on a convex polygon to a position.
	private static void ClosestPointOnConvexPoly(float[3] pos, float* verts, int32 nverts, out float[3] closest)
	{
		closest = pos;

		// Check if point is inside the polygon (in xz plane)
		bool inside = true;
		for (int32 i = 0, j = nverts - 1; i < nverts; j = i++)
		{
			float ex = verts[i * 3] - verts[j * 3];
			float ez = verts[i * 3 + 2] - verts[j * 3 + 2];
			float px2 = pos[0] - verts[j * 3];
			float pz2 = pos[2] - verts[j * 3 + 2];
			if (ex * pz2 - ez * px2 < 0)
			{
				inside = false;
				break;
			}
		}

		if (inside)
		{
			// Point is inside polygon - project onto polygon plane
			// For simplicity, use the average Y of the polygon vertices
			float avgY = 0;
			for (int32 i = 0; i < nverts; i++)
				avgY += verts[i * 3 + 1];
			avgY /= (float)nverts;
			closest[1] = avgY;
			return;
		}

		// Point is outside - find closest point on edges
		float minDistSq = float.MaxValue;
		for (int32 i = 0, j = nverts - 1; i < nverts; j = i++)
		{
			float[3] edgeClosest;
			ClosestPointOnSegment(pos,
				.(verts[j * 3], verts[j * 3 + 1], verts[j * 3 + 2]),
				.(verts[i * 3], verts[i * 3 + 1], verts[i * 3 + 2]),
				out edgeClosest);

			float dx = pos[0] - edgeClosest[0];
			float dy = pos[1] - edgeClosest[1];
			float dz = pos[2] - edgeClosest[2];
			float distSq = dx * dx + dy * dy + dz * dz;

			if (distSq < minDistSq)
			{
				minDistSq = distSq;
				closest = edgeClosest;
			}
		}
	}

	/// Finds the closest point on a line segment to a point.
	private static void ClosestPointOnSegment(float[3] pos, float[3] a, float[3] b, out float[3] closest)
	{
		float dx = b[0] - a[0];
		float dy = b[1] - a[1];
		float dz = b[2] - a[2];
		float lenSq = dx * dx + dy * dy + dz * dz;

		if (lenSq < 1e-8f)
		{
			closest = a;
			return;
		}

		float t = ((pos[0] - a[0]) * dx + (pos[1] - a[1]) * dy + (pos[2] - a[2]) * dz) / lenSq;
		t = Math.Clamp(t, 0.0f, 1.0f);

		closest[0] = a[0] + t * dx;
		closest[1] = a[1] + t * dy;
		closest[2] = a[2] + t * dz;
	}

	/// Builds internal polygon links within a tile.
	private void BuildInternalLinks(NavMeshTile tile)
	{
		// Allocate links for internal edges
		int32 maxLinks = 0;
		for (int32 i = 0; i < tile.PolyCount; i++)
		{
			for (int32 j = 0; j < tile.Polygons[i].VertexCount; j++)
			{
				if (tile.Polygons[i].Neighbors[j] != 0)
					maxLinks++;
			}
		}

		if (maxLinks == 0) return;

		tile.MaxLinkCount = maxLinks;
		tile.Links = new NavMeshLink[maxLinks];
		tile.LinkCount = 0;

		for (int32 i = 0; i < tile.PolyCount; i++)
		{
			ref NavPoly poly = ref tile.Polygons[i];
			poly.FirstLink = -1;

			for (int32 j = (int32)poly.VertexCount - 1; j >= 0; j--)
			{
				uint16 neighbor = poly.Neighbors[j];
				if (neighbor == 0 || neighbor > NavMeshConstants.ExternalLink)
					continue;

				int32 linkIdx = tile.AllocLink();
				if (linkIdx < 0) break;

				ref NavMeshLink link = ref tile.Links[linkIdx];
				link.Reference = EncodePolyRef(tile, (int32)(neighbor - 1));
				link.Edge = (uint8)j;
				link.Side = 0xFF;
				link.BMin = 0;
				link.BMax = 0;
				link.Next = poly.FirstLink;
				poly.FirstLink = linkIdx;
			}
		}
	}

	/// Gets the tile at the given grid coordinates.
	public NavMeshTile GetTileAt(int32 x, int32 z)
	{
		for (int32 i = 0; i < mMaxTiles; i++)
		{
			let tile = mTiles[i];
			if (tile != null && tile.X == x && tile.Z == z)
				return tile;
		}
		return null;
	}

	/// Connects all adjacent tiles by building cross-tile links.
	/// Call this after all tiles have been added.
	public void ConnectAllTiles()
	{
		for (int32 i = 0; i < mMaxTiles; i++)
		{
			let tile = mTiles[i];
			if (tile == null) continue;

			// Connect to right neighbor (+X)
			let rightNeighbor = GetTileAt(tile.X + 1, tile.Z);
			if (rightNeighbor != null)
				ConnectTilesOnSide(tile, rightNeighbor, 0);

			// Connect to forward neighbor (+Z)
			let forwardNeighbor = GetTileAt(tile.X, tile.Z + 1);
			if (forwardNeighbor != null)
				ConnectTilesOnSide(tile, forwardNeighbor, 1);
		}
	}

	/// Connects two adjacent tiles by creating bidirectional cross-tile links.
	/// Side: 0 = tileA is left of tileB (+X boundary), 1 = tileA is below tileB (+Z boundary).
	public void ConnectTilesOnSide(NavMeshTile tileA, NavMeshTile tileB, int32 side)
	{
		const float tolerance = 0.01f;

		// Determine the boundary line
		float boundaryVal;
		int32 axisIdx; // 0 for X boundary, 2 for Z boundary
		int32 perpIdx; // perpendicular axis for overlap checking

		if (side == 0)
		{
			// +X boundary: tileA's max X = tileB's min X
			boundaryVal = tileA.BMax[0];
			axisIdx = 0;
			perpIdx = 2;
		}
		else
		{
			// +Z boundary: tileA's max Z = tileB's min Z
			boundaryVal = tileA.BMax[2];
			axisIdx = 2;
			perpIdx = 0;
		}

		// Find boundary edges on tile A (edges on max side) and create links to tile B
		CreateCrossTileLinks(tileA, tileB, boundaryVal, axisIdx, perpIdx, tolerance);
		// Find boundary edges on tile B (edges on min side) and create links to tile A
		CreateCrossTileLinks(tileB, tileA, boundaryVal, axisIdx, perpIdx, tolerance);
	}

	/// Creates one-directional cross-tile links from srcTile's boundary edges to dstTile's boundary polygons.
	private void CreateCrossTileLinks(NavMeshTile srcTile, NavMeshTile dstTile,
		float boundaryVal, int32 axisIdx, int32 perpIdx, float tolerance)
	{
		// Count how many links we need
		int32 linkCount = 0;
		for (int32 pi = 0; pi < srcTile.PolyCount; pi++)
		{
			ref NavPoly poly = ref srcTile.Polygons[pi];
			for (int32 e = 0; e < poly.VertexCount; e++)
			{
				// Skip edges with internal neighbors
				if (poly.Neighbors[e] != 0)
					continue;

				int32 eNext = (e + 1) % (int32)poly.VertexCount;
				int32 va = (int32)poly.VertexIndices[e] * 3;
				int32 vb = (int32)poly.VertexIndices[eNext] * 3;

				// Check if both vertices are on the boundary
				if (Math.Abs(srcTile.Vertices[va + axisIdx] - boundaryVal) < tolerance &&
					Math.Abs(srcTile.Vertices[vb + axisIdx] - boundaryVal) < tolerance)
				{
					linkCount++;
				}
			}
		}

		if (linkCount == 0) return;

		// Grow the links array if needed
		GrowLinks(srcTile, linkCount);

		// Create links
		for (int32 pi = 0; pi < srcTile.PolyCount; pi++)
		{
			ref NavPoly poly = ref srcTile.Polygons[pi];
			for (int32 e = 0; e < poly.VertexCount; e++)
			{
				if (poly.Neighbors[e] != 0)
					continue;

				int32 eNext = (e + 1) % (int32)poly.VertexCount;
				int32 va = (int32)poly.VertexIndices[e] * 3;
				int32 vb = (int32)poly.VertexIndices[eNext] * 3;

				if (Math.Abs(srcTile.Vertices[va + axisIdx] - boundaryVal) < tolerance &&
					Math.Abs(srcTile.Vertices[vb + axisIdx] - boundaryVal) < tolerance)
				{
					// This edge is on the boundary - find matching polygon in dstTile
					float edgeMin = Math.Min(srcTile.Vertices[va + perpIdx], srcTile.Vertices[vb + perpIdx]);
					float edgeMax = Math.Max(srcTile.Vertices[va + perpIdx], srcTile.Vertices[vb + perpIdx]);

					int32 bestPoly = FindOverlappingBoundaryPoly(dstTile, boundaryVal, axisIdx, perpIdx, edgeMin, edgeMax, tolerance);
					if (bestPoly >= 0)
					{
						int32 linkIdx = srcTile.AllocLink();
						if (linkIdx < 0) break;

						ref NavMeshLink link = ref srcTile.Links[linkIdx];
						link.Reference = EncodePolyRef(dstTile, bestPoly);
						link.Edge = (uint8)e;
						// Determine link side: 0=+X, 1=-X, 2=+Z, 3=-Z
						bool isMaxSide = Math.Abs(boundaryVal - srcTile.BMax[axisIdx]) < tolerance;
						link.Side = isMaxSide ?
							(uint8)(axisIdx == 0 ? 0 : 2) :  // +X or +Z
							(uint8)(axisIdx == 0 ? 1 : 3);   // -X or -Z
						link.BMin = 0;
						link.BMax = 255;
						link.Next = poly.FirstLink;
						poly.FirstLink = linkIdx;
					}
				}
			}
		}
	}

	/// Finds the polygon in dstTile that has a boundary edge overlapping the given range on the perpendicular axis.
	private int32 FindOverlappingBoundaryPoly(NavMeshTile tile, float boundaryVal, int32 axisIdx, int32 perpIdx,
		float srcMin, float srcMax, float tolerance)
	{
		int32 bestPoly = -1;
		float bestOverlap = 0;

		for (int32 pi = 0; pi < tile.PolyCount; pi++)
		{
			ref NavPoly poly = ref tile.Polygons[pi];
			for (int32 e = 0; e < poly.VertexCount; e++)
			{
				int32 eNext = (e + 1) % (int32)poly.VertexCount;
				int32 va = (int32)poly.VertexIndices[e] * 3;
				int32 vb = (int32)poly.VertexIndices[eNext] * 3;

				// Check if this edge is on the same boundary
				if (Math.Abs(tile.Vertices[va + axisIdx] - boundaryVal) < tolerance &&
					Math.Abs(tile.Vertices[vb + axisIdx] - boundaryVal) < tolerance)
				{
					// Check overlap on perpendicular axis
					float dstMin = Math.Min(tile.Vertices[va + perpIdx], tile.Vertices[vb + perpIdx]);
					float dstMax = Math.Max(tile.Vertices[va + perpIdx], tile.Vertices[vb + perpIdx]);

					float overlapMin = Math.Max(srcMin, dstMin);
					float overlapMax = Math.Min(srcMax, dstMax);
					float overlap = overlapMax - overlapMin;

					if (overlap > tolerance && overlap > bestOverlap)
					{
						bestOverlap = overlap;
						bestPoly = pi;
					}
				}
			}
		}

		return bestPoly;
	}

	/// Grows the link array of a tile to accommodate additional links.
	private void GrowLinks(NavMeshTile tile, int32 additionalCount)
	{
		int32 newMax = tile.MaxLinkCount + additionalCount;
		let newLinks = new NavMeshLink[newMax];

		if (tile.Links != null)
		{
			Internal.MemCpy(newLinks.Ptr, tile.Links.Ptr, tile.LinkCount * sizeof(NavMeshLink));
			delete tile.Links;
		}

		tile.Links = newLinks;
		tile.MaxLinkCount = newMax;
	}
}

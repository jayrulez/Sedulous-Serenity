using System;
using System.Collections;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation.Dynamic;

/// Integrates off-mesh connections into a NavMesh by creating special polygons and links.
static class OffMeshConnectionBuilder
{
	/// Adds off-mesh connections to an existing NavMesh.
	/// Each connection creates a 2-vertex polygon (Type=OffMeshConnection) and
	/// links it to the nearest ground polygon at each endpoint.
	public static int32 AddConnections(NavMesh navMesh, Span<OffMeshConnection> connections)
	{
		int32 added = 0;

		for (let connection in connections)
		{
			if (AddConnection(navMesh, connection))
				added++;
		}

		return added;
	}

	/// Adds a single off-mesh connection to the NavMesh.
	/// Returns true if the connection was successfully added.
	public static bool AddConnection(NavMesh navMesh, in OffMeshConnection connection)
	{
		// Find the tile containing the start point
		NavMeshTile startTile = FindTileForPoint(navMesh, connection.Start);
		if (startTile == null) return false;

		// Find the nearest ground polygon to the start point
		int32 startPolyIdx = FindNearestGroundPoly(startTile, connection.Start, connection.Radius);
		if (startPolyIdx < 0) return false;

		// Find the tile containing the end point
		NavMeshTile endTile = FindTileForPoint(navMesh, connection.End);
		if (endTile == null) return false;

		// Find the nearest ground polygon to the end point
		int32 endPolyIdx = FindNearestGroundPoly(endTile, connection.End, connection.Radius);
		if (endPolyIdx < 0) return false;

		// Add the off-mesh connection polygon to the start tile
		int32 connPolyIdx = AddOffMeshPoly(startTile, connection);
		if (connPolyIdx < 0) return false;

		// Create link from start ground poly to off-mesh poly
		CreateOffMeshLink(startTile, startPolyIdx, connPolyIdx, 0);

		// Create link from off-mesh poly to end ground poly
		PolyRef endRef = navMesh.EncodePolyRef(endTile, endPolyIdx);
		CreateOffMeshLinkToRef(startTile, connPolyIdx, endRef, 1);

		// If bidirectional, create reverse links
		if (connection.Bidirectional)
		{
			PolyRef connRef = navMesh.EncodePolyRef(startTile, connPolyIdx);
			CreateOffMeshLinkToRef(endTile, endPolyIdx, connRef, 0);
		}

		return true;
	}

	/// Finds the tile that contains the given world point.
	private static NavMeshTile FindTileForPoint(NavMesh navMesh, float[3] point)
	{
		for (int32 i = 0; i < navMesh.MaxTiles; i++)
		{
			let tile = navMesh.GetTile(i);
			if (tile == null) continue;

			if (point[0] >= tile.BMin[0] && point[0] <= tile.BMax[0] &&
				point[2] >= tile.BMin[2] && point[2] <= tile.BMax[2])
				return tile;
		}
		return null;
	}

	/// Finds the nearest ground polygon to the given point.
	private static int32 FindNearestGroundPoly(NavMeshTile tile, float[3] point, float radius)
	{
		int32 bestIdx = -1;
		float bestDistSq = float.MaxValue;

		for (int32 i = 0; i < tile.PolyCount; i++)
		{
			ref NavPoly poly = ref tile.Polygons[i];
			if (poly.Type != .Ground) continue;

			// Calculate distance from point to polygon centroid
			float[3] centroid = default;
			for (int32 j = 0; j < poly.VertexCount; j++)
			{
				int32 vi = (int32)poly.VertexIndices[j] * 3;
				centroid[0] += tile.Vertices[vi];
				centroid[1] += tile.Vertices[vi + 1];
				centroid[2] += tile.Vertices[vi + 2];
			}
			float invCount = 1.0f / (float)poly.VertexCount;
			centroid[0] *= invCount;
			centroid[1] *= invCount;
			centroid[2] *= invCount;

			float dx = point[0] - centroid[0];
			float dy = point[1] - centroid[1];
			float dz = point[2] - centroid[2];
			float distSq = dx * dx + dy * dy + dz * dz;

			if (distSq < bestDistSq)
			{
				bestDistSq = distSq;
				bestIdx = i;
			}
		}

		return bestIdx;
	}

	/// Adds a 2-vertex off-mesh connection polygon to the tile.
	/// Returns the new polygon index, or -1 if the tile can't accommodate it.
	private static int32 AddOffMeshPoly(NavMeshTile tile, in OffMeshConnection connection)
	{
		// Expand the vertex and polygon arrays
		int32 newVertIdx = tile.VertexCount;
		int32 newPolyIdx = tile.PolyCount;

		// Add start and end vertices
		let newVerts = new float[(tile.VertexCount + 2) * 3];
		if (tile.Vertices != null)
		{
			Internal.MemCpy(newVerts.Ptr, tile.Vertices.Ptr, tile.VertexCount * 3 * sizeof(float));
			delete tile.Vertices;
		}
		newVerts[(tile.VertexCount) * 3] = connection.Start[0];
		newVerts[(tile.VertexCount) * 3 + 1] = connection.Start[1];
		newVerts[(tile.VertexCount) * 3 + 2] = connection.Start[2];
		newVerts[(tile.VertexCount + 1) * 3] = connection.End[0];
		newVerts[(tile.VertexCount + 1) * 3 + 1] = connection.End[1];
		newVerts[(tile.VertexCount + 1) * 3 + 2] = connection.End[2];
		tile.Vertices = newVerts;
		tile.VertexCount += 2;

		// Add new polygon
		let newPolys = new NavPoly[tile.PolyCount + 1];
		if (tile.Polygons != null)
		{
			Internal.MemCpy(newPolys.Ptr, tile.Polygons.Ptr, tile.PolyCount * sizeof(NavPoly));
			delete tile.Polygons;
		}
		ref NavPoly newPoly = ref newPolys[newPolyIdx];
		newPoly = .();
		newPoly.VertexIndices[0] = (uint16)newVertIdx;
		newPoly.VertexIndices[1] = (uint16)(newVertIdx + 1);
		newPoly.VertexCount = 2;
		newPoly.Type = .OffMeshConnection;
		newPoly.Area = connection.Area;
		newPoly.Flags = connection.Flags;
		newPoly.FirstLink = -1;
		tile.Polygons = newPolys;
		tile.PolyCount++;

		return newPolyIdx;
	}

	/// Creates a link from sourcePoly to targetPoly within the same tile.
	private static void CreateOffMeshLink(NavMeshTile tile, int32 sourcePolyIdx, int32 targetPolyIdx, uint8 edge)
	{
		// Grow links if needed
		if (tile.LinkCount >= tile.MaxLinkCount)
		{
			int32 newMax = Math.Max(tile.MaxLinkCount * 2, tile.MaxLinkCount + 4);
			let newLinks = new NavMeshLink[newMax];
			if (tile.Links != null)
			{
				Internal.MemCpy(newLinks.Ptr, tile.Links.Ptr, tile.LinkCount * sizeof(NavMeshLink));
				delete tile.Links;
			}
			tile.Links = newLinks;
			tile.MaxLinkCount = newMax;
		}

		int32 linkIdx = tile.LinkCount++;
		ref NavMeshLink link = ref tile.Links[linkIdx];
		link.Reference = PolyRef.Encode(tile.Salt, tile.TileIndex, targetPolyIdx);
		link.Edge = edge;
		link.Side = 0xFF; // Off-mesh
		link.BMin = 0;
		link.BMax = 0;
		link.Next = tile.Polygons[sourcePolyIdx].FirstLink;
		tile.Polygons[sourcePolyIdx].FirstLink = linkIdx;
	}

	/// Creates a link from sourcePoly to a PolyRef (possibly in another tile).
	private static void CreateOffMeshLinkToRef(NavMeshTile tile, int32 sourcePolyIdx, PolyRef targetRef, uint8 edge)
	{
		if (tile.LinkCount >= tile.MaxLinkCount)
		{
			int32 newMax = Math.Max(tile.MaxLinkCount * 2, tile.MaxLinkCount + 4);
			let newLinks = new NavMeshLink[newMax];
			if (tile.Links != null)
			{
				Internal.MemCpy(newLinks.Ptr, tile.Links.Ptr, tile.LinkCount * sizeof(NavMeshLink));
				delete tile.Links;
			}
			tile.Links = newLinks;
			tile.MaxLinkCount = newMax;
		}

		int32 linkIdx = tile.LinkCount++;
		ref NavMeshLink link = ref tile.Links[linkIdx];
		link.Reference = targetRef;
		link.Edge = edge;
		link.Side = 0xFF; // Off-mesh
		link.BMin = 0;
		link.BMax = 0;
		link.Next = tile.Polygons[sourcePolyIdx].FirstLink;
		tile.Polygons[sourcePolyIdx].FirstLink = linkIdx;
	}
}

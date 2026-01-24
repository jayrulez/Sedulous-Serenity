using System;
using System.Collections;
using Sedulous.Navigation.Detour;
using Sedulous.Navigation.Crowd;

namespace Sedulous.Navigation;

/// Debug vertex with position and color for visualization.
[CRepr]
struct DebugDrawVertex
{
	public float X, Y, Z;
	public uint32 Color; // RGBA packed

	public this(float x, float y, float z, uint32 color)
	{
		X = x; Y = y; Z = z;
		Color = color;
	}
}

/// Generates debug visualization data for navigation meshes.
/// Outputs vertex/color data that can be rendered by any graphics system.
static class NavMeshDebugDraw
{
	public const uint32 ColorNavMeshPoly = 0x6040C0A0;    // Semi-transparent teal
	public const uint32 ColorNavMeshEdge = 0xFF203050;    // Dark blue edge
	public const uint32 ColorNavMeshBoundary = 0xFF4080C0; // Bright boundary edge
	public const uint32 ColorPath = 0xFF00FF00;            // Green path
	public const uint32 ColorStart = 0xFF00FF00;           // Green start
	public const uint32 ColorEnd = 0xFFFF0000;             // Red end

	/// Generates triangle list vertices for the navmesh polygons.
	public static void DrawNavMesh(NavMesh navMesh, List<DebugDrawVertex> outVertices)
	{
		for (int32 ti = 0; ti < navMesh.MaxTiles; ti++)
		{
			let tile = navMesh.GetTile(ti);
			if (tile == null) continue;

			for (int32 pi = 0; pi < tile.PolyCount; pi++)
			{
				ref NavPoly poly = ref tile.Polygons[pi];
				if (poly.Type == .OffMeshConnection) continue;

				uint32 color = GetAreaColor(poly.Area);

				// Triangulate the polygon for rendering
				if (poly.VertexCount >= 3)
				{
					int32 v0 = (int32)poly.VertexIndices[0] * 3;
					for (int32 j = 1; j < poly.VertexCount - 1; j++)
					{
						int32 v1 = (int32)poly.VertexIndices[j] * 3;
						int32 v2 = (int32)poly.VertexIndices[j + 1] * 3;
						outVertices.Add(DebugDrawVertex(tile.Vertices[v0], tile.Vertices[v0 + 1], tile.Vertices[v0 + 2], color));
						outVertices.Add(DebugDrawVertex(tile.Vertices[v1], tile.Vertices[v1 + 1], tile.Vertices[v1 + 2], color));
						outVertices.Add(DebugDrawVertex(tile.Vertices[v2], tile.Vertices[v2 + 1], tile.Vertices[v2 + 2], color));
					}
				}
			}
		}
	}

	/// Generates line list vertices for navmesh edges.
	public static void DrawNavMeshEdges(NavMesh navMesh, List<DebugDrawVertex> outVertices)
	{
		for (int32 ti = 0; ti < navMesh.MaxTiles; ti++)
		{
			let tile = navMesh.GetTile(ti);
			if (tile == null) continue;

			for (int32 pi = 0; pi < tile.PolyCount; pi++)
			{
				ref NavPoly poly = ref tile.Polygons[pi];
				if (poly.Type == .OffMeshConnection) continue;

				for (int32 j = 0; j < poly.VertexCount; j++)
				{
					int32 jNext = (j + 1) % (int32)poly.VertexCount;
					int32 v0 = (int32)poly.VertexIndices[j] * 3;
					int32 v1 = (int32)poly.VertexIndices[jNext] * 3;

					uint32 color = (poly.Neighbors[j] == 0) ? ColorNavMeshBoundary : ColorNavMeshEdge;

					outVertices.Add(DebugDrawVertex(tile.Vertices[v0], tile.Vertices[v0 + 1], tile.Vertices[v0 + 2], color));
					outVertices.Add(DebugDrawVertex(tile.Vertices[v1], tile.Vertices[v1 + 1], tile.Vertices[v1 + 2], color));
				}
			}
		}
	}

	/// Generates line list vertices for a path.
	public static void DrawPath(List<float> waypoints, List<DebugDrawVertex> outVertices)
	{
		int32 pointCount = (int32)(waypoints.Count / 3);
		for (int32 i = 0; i < pointCount - 1; i++)
		{
			outVertices.Add(DebugDrawVertex(waypoints[i * 3], waypoints[i * 3 + 1], waypoints[i * 3 + 2], ColorPath));
			outVertices.Add(DebugDrawVertex(waypoints[(i + 1) * 3], waypoints[(i + 1) * 3 + 1], waypoints[(i + 1) * 3 + 2], ColorPath));
		}
	}

	/// Generates line list vertices for a polygon corridor (path as polygon centroids).
	public static void DrawPolygonCorridor(NavMesh navMesh, List<PolyRef> path, List<DebugDrawVertex> outVertices,
		uint32 color = 0xFFFFFF00)
	{
		if (path.Count < 2) return;

		for (int32 i = 0; i < path.Count - 1; i++)
		{
			float[3] centerA = default;
			float[3] centerB = default;

			NavPoly polyA;
			NavMeshTile tileA;
			if (!navMesh.GetPolyAndTile(path[i], out polyA, out tileA)) continue;

			NavPoly polyB;
			NavMeshTile tileB;
			if (!navMesh.GetPolyAndTile(path[i + 1], out polyB, out tileB)) continue;

			for (int32 vi = 0; vi < polyA.VertexCount; vi++)
			{
				int32 vIdx = (int32)polyA.VertexIndices[vi] * 3;
				centerA[0] += tileA.Vertices[vIdx];
				centerA[1] += tileA.Vertices[vIdx + 1];
				centerA[2] += tileA.Vertices[vIdx + 2];
			}
			float invA = 1.0f / (float)polyA.VertexCount;
			centerA[0] *= invA; centerA[1] *= invA; centerA[2] *= invA;

			for (int32 vi = 0; vi < polyB.VertexCount; vi++)
			{
				int32 vIdx = (int32)polyB.VertexIndices[vi] * 3;
				centerB[0] += tileB.Vertices[vIdx];
				centerB[1] += tileB.Vertices[vIdx + 1];
				centerB[2] += tileB.Vertices[vIdx + 2];
			}
			float invB = 1.0f / (float)polyB.VertexCount;
			centerB[0] *= invB; centerB[1] *= invB; centerB[2] *= invB;

			outVertices.Add(DebugDrawVertex(centerA[0], centerA[1], centerA[2], color));
			outVertices.Add(DebugDrawVertex(centerB[0], centerB[1], centerB[2], color));
		}
	}

	/// Generates line list vertices for crowd agent positions and velocities.
	public static void DrawAgents(CrowdManager crowd, List<DebugDrawVertex> outVertices,
		uint32 posColor = 0xFF00FF00, uint32 velColor = 0xFFFF8000, uint32 targetColor = 0xFFFF0000)
	{
		for (int32 i = 0; i < crowd.MaxAgents; i++)
		{
			let agent = crowd.GetAgent(i);
			if (agent == null) continue;

			float r = agent.Params.Radius;

			// Cross at agent position
			outVertices.Add(DebugDrawVertex(agent.Position[0] - r, agent.Position[1], agent.Position[2], posColor));
			outVertices.Add(DebugDrawVertex(agent.Position[0] + r, agent.Position[1], agent.Position[2], posColor));
			outVertices.Add(DebugDrawVertex(agent.Position[0], agent.Position[1], agent.Position[2] - r, posColor));
			outVertices.Add(DebugDrawVertex(agent.Position[0], agent.Position[1], agent.Position[2] + r, posColor));

			// Velocity vector
			float speed = Math.Sqrt(agent.Velocity[0] * agent.Velocity[0] + agent.Velocity[2] * agent.Velocity[2]);
			if (speed > 0.01f)
			{
				outVertices.Add(DebugDrawVertex(agent.Position[0], agent.Position[1], agent.Position[2], velColor));
				outVertices.Add(DebugDrawVertex(
					agent.Position[0] + agent.Velocity[0],
					agent.Position[1],
					agent.Position[2] + agent.Velocity[2], velColor));
			}

			// Line to target
			if (agent.TargetRef.IsValid)
			{
				outVertices.Add(DebugDrawVertex(agent.Position[0], agent.Position[1], agent.Position[2], targetColor));
				outVertices.Add(DebugDrawVertex(agent.TargetPosition[0], agent.TargetPosition[1], agent.TargetPosition[2], targetColor));
			}
		}
	}

	/// Generates line list vertices for off-mesh connections.
	public static void DrawOffMeshConnections(NavMesh navMesh, List<DebugDrawVertex> outVertices,
		uint32 color = 0xFFFF8000)
	{
		for (int32 ti = 0; ti < navMesh.MaxTiles; ti++)
		{
			let tile = navMesh.GetTile(ti);
			if (tile == null) continue;

			for (int32 pi = 0; pi < tile.PolyCount; pi++)
			{
				ref NavPoly poly = ref tile.Polygons[pi];
				if (poly.Type != .OffMeshConnection) continue;
				if (poly.VertexCount < 2) continue;

				int32 va = (int32)poly.VertexIndices[0] * 3;
				int32 vb = (int32)poly.VertexIndices[1] * 3;

				outVertices.Add(DebugDrawVertex(tile.Vertices[va], tile.Vertices[va + 1], tile.Vertices[va + 2], color));
				outVertices.Add(DebugDrawVertex(tile.Vertices[vb], tile.Vertices[vb + 1], tile.Vertices[vb + 2], color));
			}
		}
	}

	/// Returns a color for a given area type.
	private static uint32 GetAreaColor(uint8 area)
	{
		switch (area)
		{
		case 0: return 0x40404040;   // Null area (shouldn't render)
		case 1: return 0x6040C060;   // Ground - green
		case 2: return 0x604060C0;   // Water - blue
		case 3: return 0x60C0C040;   // Road - yellow
		default: return ColorNavMeshPoly;
		}
	}
}

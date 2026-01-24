using System;
using System.Collections;

namespace Sedulous.Navigation.Recast;

/// A polygon mesh built from contours. Each polygon is convex with up to MaxVertsPerPoly vertices.
class PolyMesh
{
	/// Mesh vertices [VertexCount * 3] as (x, y, z) in voxel coordinates.
	public int32[] Vertices ~ delete _;
	/// Polygon data [PolyCount * MaxVertsPerPoly * 2].
	/// First half: vertex indices (0xFFFF = unused).
	/// Second half: neighbor polygon indices (0xFFFF = no neighbor or boundary).
	public int32[] Polygons ~ delete _;
	/// Region ID per polygon.
	public uint16[] RegionIds ~ delete _;
	/// Area flags per polygon.
	public uint8[] Areas ~ delete _;
	/// Flags per polygon (user-defined, e.g., for path filtering).
	public uint16[] Flags ~ delete _;

	public int32 VertexCount;
	public int32 PolyCount;
	public int32 MaxVertsPerPoly;
	public float[3] BMin;
	public float[3] BMax;
	public float CellSize;
	public float CellHeight;
	public int32 BorderSize;
	public float MaxEdgeError;

	public const int32 NullIndex = -1;

	/// Builds a polygon mesh from a contour set.
	public static PolyMesh Build(ContourSet contourSet, int32 maxVertsPerPoly)
	{
		let mesh = new PolyMesh();
		mesh.BMin = contourSet.BMin;
		mesh.BMax = contourSet.BMax;
		mesh.CellSize = contourSet.CellSize;
		mesh.CellHeight = contourSet.CellHeight;
		mesh.BorderSize = contourSet.BorderSize;
		mesh.MaxVertsPerPoly = maxVertsPerPoly;
		mesh.MaxEdgeError = contourSet.MaxError;

		// Collect all vertices and triangulate contours
		let allVerts = scope List<int32>();       // x, y, z triples
		let allPolys = scope List<int32>();       // polygon vertex indices
		let allRegions = scope List<uint16>();
		let allAreas = scope List<uint8>();

		for (let contour in contourSet.Contours)
		{
			if (contour.Vertices.Count < 3) continue;

			// Add contour vertices to the global vertex list
			int32 vertBase = (int32)(allVerts.Count / 3);
			for (let v in contour.Vertices)
			{
				allVerts.Add(v.X);
				allVerts.Add(v.Y);
				allVerts.Add(v.Z);
			}

			// Triangulate the contour using ear clipping
			let triIndices = scope List<int32>();
			Triangulate(contour.Vertices, triIndices);

			// Convert triangles to polygons (initially each triangle is a polygon)
			for (int32 t = 0; t < triIndices.Count / 3; t++)
			{
				int32[6] poly = .(-1, -1, -1, -1, -1, -1);
				poly[0] = vertBase + triIndices[t * 3];
				poly[1] = vertBase + triIndices[t * 3 + 1];
				poly[2] = vertBase + triIndices[t * 3 + 2];

				for (int i = 0; i < maxVertsPerPoly; i++)
					allPolys.Add(poly[i]);

				allRegions.Add(contour.RegionId);
				allAreas.Add(contour.Area);
			}
		}

		if (allPolys.Count == 0)
		{
			mesh.VertexCount = 0;
			mesh.PolyCount = 0;
			mesh.Vertices = new int32[0];
			mesh.Polygons = new int32[0];
			mesh.RegionIds = new uint16[0];
			mesh.Areas = new uint8[0];
			mesh.Flags = new uint16[0];
			return mesh;
		}

		// Merge triangles into convex polygons
		int32 polyCount = (int32)(allPolys.Count / maxVertsPerPoly);
		MergePolygons(allVerts, allPolys, allRegions, allAreas, maxVertsPerPoly, ref polyCount);

		// Remove degenerate polygons and compact
		let finalVerts = scope List<int32>();
		let finalPolys = scope List<int32>();
		let finalRegions = scope List<uint16>();
		let finalAreas = scope List<uint8>();
		let vertRemap = scope List<int32>();

		// Build vertex remap (remove unused vertices)
		int32 totalVerts = (int32)(allVerts.Count / 3);
		let vertUsed = scope bool[totalVerts];
		for (int32 i = 0; i < polyCount; i++)
		{
			for (int32 j = 0; j < maxVertsPerPoly; j++)
			{
				int32 vi = allPolys[i * maxVertsPerPoly + j];
				if (vi != -1 && vi < totalVerts)
					vertUsed[vi] = true;
			}
		}

		// Remap vertices
		vertRemap.Resize(totalVerts);
		int32 newVertCount = 0;
		for (int32 i = 0; i < totalVerts; i++)
		{
			if (vertUsed[i])
			{
				vertRemap[i] = newVertCount;
				finalVerts.Add(allVerts[i * 3]);
				finalVerts.Add(allVerts[i * 3 + 1]);
				finalVerts.Add(allVerts[i * 3 + 2]);
				newVertCount++;
			}
			else
			{
				vertRemap[i] = -1;
			}
		}

		// Remap polygon vertex indices
		for (int32 i = 0; i < polyCount; i++)
		{
			bool valid = false;
			for (int32 j = 0; j < maxVertsPerPoly; j++)
			{
				int32 vi = allPolys[i * maxVertsPerPoly + j];
				if (vi != -1 && vi < totalVerts)
				{
					allPolys[i * maxVertsPerPoly + j] = vertRemap[vi];
					valid = true;
				}
			}

			if (valid)
			{
				for (int32 j = 0; j < maxVertsPerPoly; j++)
					finalPolys.Add(allPolys[i * maxVertsPerPoly + j]);
				// Add neighbor slots (initialized to -1)
				for (int32 j = 0; j < maxVertsPerPoly; j++)
					finalPolys.Add(NullIndex);
				finalRegions.Add(allRegions[i]);
				finalAreas.Add(allAreas[i]);
			}
		}

		// Store results
		mesh.VertexCount = newVertCount;
		mesh.PolyCount = (int32)(finalRegions.Count);

		mesh.Vertices = new int32[finalVerts.Count];
		Internal.MemCpy(mesh.Vertices.Ptr, finalVerts.Ptr, finalVerts.Count * sizeof(int32));

		mesh.Polygons = new int32[finalPolys.Count];
		Internal.MemCpy(mesh.Polygons.Ptr, finalPolys.Ptr, finalPolys.Count * sizeof(int32));

		mesh.RegionIds = new uint16[finalRegions.Count];
		Internal.MemCpy(mesh.RegionIds.Ptr, finalRegions.Ptr, finalRegions.Count * sizeof(uint16));

		mesh.Areas = new uint8[finalAreas.Count];
		Internal.MemCpy(mesh.Areas.Ptr, finalAreas.Ptr, finalAreas.Count * sizeof(uint8));

		mesh.Flags = new uint16[mesh.PolyCount];
		for (int32 i = 0; i < mesh.PolyCount; i++)
			mesh.Flags[i] = 1; // Default flag: walkable

		// Build adjacency
		BuildAdjacency(mesh);

		return mesh;
	}

	/// Triangulates a contour using ear-clipping.
	private static void Triangulate(List<ContourVertex> verts, List<int32> outIndices)
	{
		int32 n = (int32)verts.Count;
		if (n < 3) return;

		if (n == 3)
		{
			outIndices.Add(0);
			outIndices.Add(1);
			outIndices.Add(2);
			return;
		}

		// Build index list
		let indices = scope int32[n];
		for (int32 i = 0; i < n; i++)
			indices[i] = i;

		int32 remaining = n;
		int32 ear = 0;
		int32 attempts = 0;

		while (remaining > 2 && attempts < remaining * 3)
		{
			int32 prev = (ear - 1 + remaining) % remaining;
			int32 next = (ear + 1) % remaining;

			int32 pi = indices[prev];
			int32 ci = indices[ear];
			int32 ni = indices[next];

			if (IsEar(verts, indices, remaining, prev, ear, next))
			{
				outIndices.Add(pi);
				outIndices.Add(ci);
				outIndices.Add(ni);

				// Remove ear vertex
				for (int32 i = ear; i < remaining - 1; i++)
					indices[i] = indices[i + 1];
				remaining--;

				if (ear >= remaining)
					ear = 0;
				attempts = 0;
			}
			else
			{
				ear = (ear + 1) % remaining;
				attempts++;
			}
		}

		// If we couldn't triangulate properly, create a fan from the remaining vertices
		if (remaining > 2)
		{
			for (int32 i = 1; i < remaining - 1; i++)
			{
				outIndices.Add(indices[0]);
				outIndices.Add(indices[i]);
				outIndices.Add(indices[i + 1]);
			}
		}
	}

	/// Checks if vertex at 'ear' forms a valid ear (convex and no other vertices inside).
	private static bool IsEar(List<ContourVertex> verts, int32[] indices, int32 count, int32 prev, int32 ear, int32 next)
	{
		int32 pi = indices[prev];
		int32 ci = indices[ear];
		int32 ni = indices[next];

		// Check convexity (cross product > 0 for CCW winding)
		int32 ax = verts[ci].X - verts[pi].X;
		int32 az = verts[ci].Z - verts[pi].Z;
		int32 bx = verts[ni].X - verts[ci].X;
		int32 bz = verts[ni].Z - verts[ci].Z;
		int32 cross = ax * bz - az * bx;

		if (cross <= 0) return false;

		// Check if any other vertex is inside the triangle
		for (int32 i = 0; i < count; i++)
		{
			if (i == prev || i == ear || i == next) continue;
			if (PointInTriangle(verts[indices[i]].X, verts[indices[i]].Z,
				verts[pi].X, verts[pi].Z,
				verts[ci].X, verts[ci].Z,
				verts[ni].X, verts[ni].Z))
				return false;
		}

		return true;
	}

	/// Point-in-triangle test using barycentric coordinates (2D, xz plane).
	private static bool PointInTriangle(int32 px, int32 pz, int32 ax, int32 az, int32 bx, int32 bz, int32 cx, int32 cz)
	{
		int32 d1 = (bx - ax) * (pz - az) - (bz - az) * (px - ax);
		int32 d2 = (cx - bx) * (pz - bz) - (cz - bz) * (px - bx);
		int32 d3 = (ax - cx) * (pz - cz) - (az - cz) * (px - cx);

		bool hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
		bool hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);

		return !(hasNeg && hasPos);
	}

	/// Merges adjacent triangles into larger convex polygons.
	private static void MergePolygons(List<int32> verts, List<int32> polys, List<uint16> regions, List<uint8> areas, int32 maxVerts, ref int32 polyCount)
	{
		bool merged = true;
		while (merged)
		{
			merged = false;

			for (int32 i = 0; i < polyCount; i++)
			{
				if (polys[i * maxVerts] == -1) continue; // Deleted polygon

				for (int32 j = i + 1; j < polyCount; j++)
				{
					if (polys[j * maxVerts] == -1) continue;
					if (regions[i] != regions[j]) continue; // Different regions

					// Find shared edge
					int32 sharedA = -1, sharedB = -1;
					int32 vertCountI = CountPolyVerts(polys, i, maxVerts);
					int32 vertCountJ = CountPolyVerts(polys, j, maxVerts);

					if (vertCountI + vertCountJ - 2 > maxVerts) continue; // Merged would exceed max

					for (int32 vi = 0; vi < vertCountI; vi++)
					{
						int32 viNext = (vi + 1) % vertCountI;
						for (int32 vj = 0; vj < vertCountJ; vj++)
						{
							int32 vjNext = (vj + 1) % vertCountJ;
							// Shared edge: i[vi]-i[viNext] matches j[vj]-j[vjNext] (reversed)
							if (polys[i * maxVerts + vi] == polys[j * maxVerts + vjNext] &&
								polys[i * maxVerts + viNext] == polys[j * maxVerts + vj])
							{
								sharedA = vi;
								sharedB = vj;
								break;
							}
						}
						if (sharedA >= 0) break;
					}

					if (sharedA < 0) continue; // No shared edge

					// Check if merged polygon would be convex
					if (!CanMerge(verts, polys, i, j, sharedA, sharedB, maxVerts))
						continue;

					// Merge j into i
					DoMerge(polys, i, j, sharedA, sharedB, maxVerts, vertCountI, vertCountJ);
					merged = true;

					// Mark j as deleted
					for (int32 k = 0; k < maxVerts; k++)
						polys[j * maxVerts + k] = -1;
				}
			}
		}

		// Compact: remove deleted polygons
		int32 writeIdx = 0;
		for (int32 i = 0; i < polyCount; i++)
		{
			if (polys[i * maxVerts] == -1) continue;
			if (writeIdx != i)
			{
				for (int32 k = 0; k < maxVerts; k++)
					polys[writeIdx * maxVerts + k] = polys[i * maxVerts + k];
				regions[writeIdx] = regions[i];
				areas[writeIdx] = areas[i];
			}
			writeIdx++;
		}
		polyCount = writeIdx;
	}

	/// Counts non-null vertices in a polygon.
	private static int32 CountPolyVerts(List<int32> polys, int32 polyIdx, int32 maxVerts)
	{
		int32 count = 0;
		for (int32 i = 0; i < maxVerts; i++)
		{
			if (polys[polyIdx * maxVerts + i] == -1) break;
			count++;
		}
		return count;
	}

	/// Checks if merging two polygons at the shared edge produces a convex result.
	private static bool CanMerge(List<int32> verts, List<int32> polys, int32 pi, int32 pj, int32 sharedA, int32 sharedB, int32 maxVerts)
	{
		int32 vertCountI = CountPolyVerts(polys, pi, maxVerts);
		int32 vertCountJ = CountPolyVerts(polys, pj, maxVerts);

		// Check convexity at the two merge points
		// At sharedA in polygon i: check prev-sharedA-next_from_j
		int32 prevA = (sharedA - 1 + vertCountI) % vertCountI;
		int32 nextB = (sharedB + 2) % vertCountJ; // First vertex of j after the shared edge

		int32 vPrev = polys[pi * maxVerts + prevA];
		int32 vCurr = polys[pi * maxVerts + sharedA];
		int32 vNext = polys[pj * maxVerts + nextB];

		if (!IsConvex(verts, vPrev, vCurr, vNext)) return false;

		// At sharedA+1 in polygon i: check last_from_j-sharedA+1-next
		int32 nextA = (sharedA + 2) % vertCountI;
		int32 prevB = (sharedB - 1 + vertCountJ) % vertCountJ;

		vPrev = polys[pj * maxVerts + prevB];
		vCurr = polys[pi * maxVerts + (sharedA + 1) % vertCountI];
		vNext = polys[pi * maxVerts + nextA];

		if (!IsConvex(verts, vPrev, vCurr, vNext)) return false;

		return true;
	}

	/// Checks if the angle at vertex b is convex (in XZ plane).
	private static bool IsConvex(List<int32> verts, int32 a, int32 b, int32 c)
	{
		int32 ax = verts[a * 3] - verts[b * 3];
		int32 az = verts[a * 3 + 2] - verts[b * 3 + 2];
		int32 bx = verts[c * 3] - verts[b * 3];
		int32 bz = verts[c * 3 + 2] - verts[b * 3 + 2];
		return (ax * bz - az * bx) > 0;
	}

	/// Performs the actual merge of polygon j into polygon i at the shared edge.
	private static void DoMerge(List<int32> polys, int32 pi, int32 pj, int32 sharedA, int32 sharedB, int32 maxVerts, int32 vertCountI, int32 vertCountJ)
	{
		let merged = scope int32[maxVerts];
		for (int32 k = 0; k < maxVerts; k++)
			merged[k] = -1;

		int32 idx = 0;

		// Add vertices from polygon i, skipping the shared edge end
		for (int32 k = 0; k < vertCountI - 1; k++)
		{
			int32 vi = (sharedA + 1 + k) % vertCountI;
			if (idx < maxVerts)
				merged[idx++] = polys[pi * maxVerts + vi];
		}

		// Add vertices from polygon j, skipping the shared edge
		for (int32 k = 0; k < vertCountJ - 1; k++)
		{
			int32 vj = (sharedB + 1 + k) % vertCountJ;
			// Skip the second shared vertex
			if (polys[pj * maxVerts + vj] == polys[pi * maxVerts + sharedA])
				continue;
			if (idx < maxVerts)
				merged[idx++] = polys[pj * maxVerts + vj];
		}

		// Write back
		for (int32 k = 0; k < maxVerts; k++)
			polys[pi * maxVerts + k] = merged[k];
	}

	/// Builds polygon adjacency information (neighbor indices).
	private static void BuildAdjacency(PolyMesh mesh)
	{
		int32 nvp = mesh.MaxVertsPerPoly;
		int32 stride = nvp * 2; // First half: verts, second half: neighbors

		for (int32 i = 0; i < mesh.PolyCount; i++)
		{
			int32 pi = i * stride;
			int32 vertCountI = 0;
			for (int32 k = 0; k < nvp; k++)
			{
				if (mesh.Polygons[pi + k] == NullIndex) break;
				vertCountI++;
			}

			for (int32 j = i + 1; j < mesh.PolyCount; j++)
			{
				int32 pj = j * stride;
				int32 vertCountJ = 0;
				for (int32 k = 0; k < nvp; k++)
				{
					if (mesh.Polygons[pj + k] == NullIndex) break;
					vertCountJ++;
				}

				// Find shared edge
				for (int32 ei = 0; ei < vertCountI; ei++)
				{
					int32 eiNext = (ei + 1) % vertCountI;
					int32 va = mesh.Polygons[pi + ei];
					int32 vb = mesh.Polygons[pi + eiNext];

					for (int32 ej = 0; ej < vertCountJ; ej++)
					{
						int32 ejNext = (ej + 1) % vertCountJ;
						int32 vc = mesh.Polygons[pj + ej];
						int32 vd = mesh.Polygons[pj + ejNext];

						// Shared edge is reversed between neighbors
						if (va == vd && vb == vc)
						{
							mesh.Polygons[pi + nvp + ei] = j;
							mesh.Polygons[pj + nvp + ej] = i;
						}
					}
				}
			}
		}
	}

	/// Gets the number of vertices for a given polygon.
	public int32 GetPolyVertCount(int32 polyIndex)
	{
		int32 nvp = MaxVertsPerPoly;
		int32 pi = polyIndex * nvp * 2;
		int32 count = 0;
		for (int32 i = 0; i < nvp; i++)
		{
			if (Polygons[pi + i] == NullIndex) break;
			count++;
		}
		return count;
	}

	/// Gets a vertex position in world coordinates for a given vertex index.
	public void GetVertex(int32 vertIndex, out float x, out float y, out float z)
	{
		x = BMin[0] + (float)Vertices[vertIndex * 3] * CellSize;
		y = BMin[1] + (float)Vertices[vertIndex * 3 + 1] * CellHeight;
		z = BMin[2] + (float)Vertices[vertIndex * 3 + 2] * CellSize;
	}
}

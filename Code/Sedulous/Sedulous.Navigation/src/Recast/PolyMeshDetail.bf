using System;
using System.Collections;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation.Recast;

/// A detail mesh that captures height variation within each polygon of a PolyMesh.
/// The detail mesh subdivides polygons with additional vertices and triangles where
/// the heightfield surface deviates from the polygon plane beyond a threshold.
class PolyMeshDetail
{
	/// Sub-mesh information for each polygon (one per polygon in the source PolyMesh).
	public NavPolyDetail[] DetailMeshes ~ delete _;
	/// Detail mesh vertices in world space [DetailVertexCount * 3].
	public float[] DetailVertices ~ delete _;
	/// Detail mesh triangles [DetailTriangleCount * 4]: (v0, v1, v2, edgeFlags).
	/// Vertex indices reference polygon vertices first (0..nverts-1),
	/// then detail vertices (nverts..nverts+ndetail-1).
	/// Edge flags: bit i set means edge i is a polygon boundary edge.
	public uint8[] DetailTriangles ~ delete _;

	/// Number of sub-meshes (equal to source PolyMesh polygon count).
	public int32 MeshCount;
	/// Total number of detail vertices across all sub-meshes.
	public int32 DetailVertexCount;
	/// Total number of detail triangles across all sub-meshes.
	public int32 DetailTriangleCount;

	/// Builds a detail mesh from a polygon mesh and compact heightfield.
	/// The detail mesh adds height information by sampling the heightfield at
	/// regular intervals and inserting vertices where the surface deviates.
	///
	/// @param polyMesh       Source polygon mesh.
	/// @param chf            Compact heightfield for height sampling.
	/// @param sampleDist     Sampling distance in world units (0 = no detail sampling).
	/// @param sampleMaxError Maximum allowed height error before adding detail vertices.
	/// @returns              A new PolyMeshDetail, or null if input is invalid.
	public static PolyMeshDetail Build(PolyMesh polyMesh, CompactHeightfield chf, float sampleDist, float sampleMaxError)
	{
		if (polyMesh == null || polyMesh.PolyCount == 0)
			return null;

		let detail = new PolyMeshDetail();
		int32 polyCount = polyMesh.PolyCount;
		int32 nvp = polyMesh.MaxVertsPerPoly;

		detail.MeshCount = polyCount;
		detail.DetailMeshes = new NavPolyDetail[polyCount];

		// Temporary storage for building vertices and triangles
		let allDetailVerts = scope List<float>();
		let allDetailTris = scope List<uint8>();

		// Temporary per-polygon working buffers
		let polyVerts = scope float[nvp * 3];
		let detailVerts = scope List<float>();
		let detailTris = scope List<uint8>();

		for (int32 i = 0; i < polyCount; i++)
		{
			int32 polyBase = i * nvp * 2;

			// Count vertices in this polygon
			int32 polyVertCount = 0;
			for (int32 j = 0; j < nvp; j++)
			{
				if (polyMesh.Polygons[polyBase + j] == PolyMesh.NullIndex) break;
				polyVertCount++;
			}

			if (polyVertCount < 3)
			{
				// Degenerate polygon, store empty sub-mesh
				detail.DetailMeshes[i] = .() { VertBase = (int32)(allDetailVerts.Count / 3), VertCount = 0, TriBase = (int32)(allDetailTris.Count / 4), TriCount = 0 };
				continue;
			}

			// Convert polygon vertices from voxel to world coordinates
			for (int32 j = 0; j < polyVertCount; j++)
			{
				int32 vi = polyMesh.Polygons[polyBase + j];
				polyVerts[j * 3]     = polyMesh.BMin[0] + (float)polyMesh.Vertices[vi * 3]     * polyMesh.CellSize;
				polyVerts[j * 3 + 1] = polyMesh.BMin[1] + (float)polyMesh.Vertices[vi * 3 + 1] * polyMesh.CellHeight;
				polyVerts[j * 3 + 2] = polyMesh.BMin[2] + (float)polyMesh.Vertices[vi * 3 + 2] * polyMesh.CellSize;
			}

			// Build detail mesh for this polygon
			detailVerts.Clear();
			detailTris.Clear();

			BuildPolyDetail(polyVerts, polyVertCount, chf, sampleDist, sampleMaxError, detailVerts, detailTris);

			// Record sub-mesh info
			int32 vertBase = (int32)(allDetailVerts.Count / 3);
			int32 triBase = (int32)(allDetailTris.Count / 4);
			int32 vertCount = (int32)(detailVerts.Count / 3);
			int32 triCount = (int32)(detailTris.Count / 4);

			detail.DetailMeshes[i] = .()
			{
				VertBase = vertBase,
				VertCount = vertCount,
				TriBase = triBase,
				TriCount = triCount
			};

			// Append detail vertices and triangles to global lists
			for (int32 j = 0; j < detailVerts.Count; j++)
				allDetailVerts.Add(detailVerts[j]);

			for (int32 j = 0; j < detailTris.Count; j++)
				allDetailTris.Add(detailTris[j]);
		}

		// Store final arrays
		detail.DetailVertexCount = (int32)(allDetailVerts.Count / 3);
		detail.DetailTriangleCount = (int32)(allDetailTris.Count / 4);

		detail.DetailVertices = new float[allDetailVerts.Count];
		for (int32 j = 0; j < allDetailVerts.Count; j++)
			detail.DetailVertices[j] = allDetailVerts[j];

		detail.DetailTriangles = new uint8[allDetailTris.Count];
		for (int32 j = 0; j < allDetailTris.Count; j++)
			detail.DetailTriangles[j] = allDetailTris[j];

		return detail;
	}

	/// Builds detail vertices and triangles for a single polygon.
	/// Uses fan triangulation for flat polygons and Delaunay-like insertion
	/// when detail vertices are added due to height deviation.
	private static void BuildPolyDetail(
		float[] polyVerts, int32 polyVertCount,
		CompactHeightfield chf,
		float sampleDist, float sampleMaxError,
		List<float> outVerts, List<uint8> outTris)
	{
		// Collect detail sample vertices from the heightfield
		let sampleVerts = scope List<float>();

		if (sampleDist > 0)
		{
			SampleHeightfield(polyVerts, polyVertCount, chf, sampleDist, sampleMaxError, sampleVerts);
		}

		if (sampleVerts.Count == 0)
		{
			// No detail vertices needed: use simple fan triangulation
			TriangulateFan(polyVertCount, outTris);
		}
		else
		{
			// Copy detail sample vertices to output
			for (int32 i = 0; i < sampleVerts.Count; i++)
				outVerts.Add(sampleVerts[i]);

			// Triangulate with detail vertices using Delaunay-like insertion
			TriangulateWithDetail(polyVerts, polyVertCount, outVerts, outTris);
		}
	}

	/// Samples the heightfield at regular grid points within the polygon
	/// and adds vertices where height deviation exceeds sampleMaxError.
	private static void SampleHeightfield(
		float[] polyVerts, int32 polyVertCount,
		CompactHeightfield chf,
		float sampleDist, float sampleMaxError,
		List<float> outSampleVerts)
	{
		// Compute polygon bounds in world space (XZ plane)
		float bminX = polyVerts[0], bmaxX = polyVerts[0];
		float bminZ = polyVerts[2], bmaxZ = polyVerts[2];
		float bminY = polyVerts[1], bmaxY = polyVerts[1];

		for (int32 i = 1; i < polyVertCount; i++)
		{
			float px = polyVerts[i * 3];
			float py = polyVerts[i * 3 + 1];
			float pz = polyVerts[i * 3 + 2];
			if (px < bminX) bminX = px;
			if (px > bmaxX) bmaxX = px;
			if (py < bminY) bminY = py;
			if (py > bmaxY) bmaxY = py;
			if (pz < bminZ) bminZ = pz;
			if (pz > bmaxZ) bmaxZ = pz;
		}

		// Sample on a grid within the polygon bounds
		int32 xSamples = (int32)((bmaxX - bminX) / sampleDist) + 1;
		int32 zSamples = (int32)((bmaxZ - bminZ) / sampleDist) + 1;

		for (int32 sz = 0; sz <= zSamples; sz++)
		{
			float sampleZ = bminZ + (float)sz * sampleDist;
			for (int32 sx = 0; sx <= xSamples; sx++)
			{
				float sampleX = bminX + (float)sx * sampleDist;

				// Check if the sample point is inside the polygon (XZ plane)
				if (!PointInPoly2D(sampleX, sampleZ, polyVerts, polyVertCount))
					continue;

				// Compute interpolated height on the polygon plane at this XZ position
				float polyHeight = GetPolyHeight(sampleX, sampleZ, polyVerts, polyVertCount);

				// Sample height from the compact heightfield
				float hfHeight = GetHeightfieldHeight(sampleX, sampleZ, chf);

				// If heightfield height is valid and deviates from polygon plane
				if (hfHeight != float.MinValue)
				{
					float heightError = Math.Abs(hfHeight - polyHeight);
					if (heightError > sampleMaxError)
					{
						// Add detail vertex at the heightfield surface
						outSampleVerts.Add(sampleX);
						outSampleVerts.Add(hfHeight);
						outSampleVerts.Add(sampleZ);
					}
				}
			}
		}
	}

	/// Gets the height from the compact heightfield at the given world XZ position.
	/// Returns float.MinValue if no valid span is found.
	private static float GetHeightfieldHeight(float worldX, float worldZ, CompactHeightfield chf)
	{
		// Convert world position to cell coordinates
		int32 cellX = (int32)((worldX - chf.BMin[0]) / chf.CellSize);
		int32 cellZ = (int32)((worldZ - chf.BMin[2]) / chf.CellSize);

		// Bounds check
		if (cellX < 0 || cellX >= chf.Width || cellZ < 0 || cellZ >= chf.Height)
			return float.MinValue;

		// Find the highest walkable span in this cell
		ref CompactCell cell = ref chf.Cells[cellX + cellZ * chf.Width];
		float bestY = float.MinValue;

		for (int32 i = cell.FirstSpan; i < cell.FirstSpan + cell.SpanCount; i++)
		{
			if (chf.Areas[i] == NavArea.Null) continue;

			float spanY = chf.BMin[1] + (float)chf.Spans[i].Y * chf.CellHeight;
			if (spanY > bestY)
				bestY = spanY;
		}

		return bestY;
	}

	/// Computes the interpolated height on the polygon plane at the given XZ position.
	/// Uses barycentric interpolation on the first triangle fan from vertex 0.
	private static float GetPolyHeight(float x, float z, float[] polyVerts, int32 polyVertCount)
	{
		// Try each triangle in a fan from vertex 0
		for (int32 i = 1; i < polyVertCount - 1; i++)
		{
			float ax = polyVerts[0], ay = polyVerts[1], az = polyVerts[2];
			float bx = polyVerts[i * 3], by = polyVerts[i * 3 + 1], bz = polyVerts[i * 3 + 2];
			float cx = polyVerts[(i + 1) * 3], cy = polyVerts[(i + 1) * 3 + 1], cz = polyVerts[(i + 1) * 3 + 2];

			float u, v, w;
			if (BarycentricCoords(x, z, ax, az, bx, bz, cx, cz, out u, out v, out w))
			{
				if (u >= 0 && v >= 0 && w >= 0)
					return u * ay + v * by + w * cy;
			}
		}

		// Fallback: return average height
		float sum = 0;
		for (int32 i = 0; i < polyVertCount; i++)
			sum += polyVerts[i * 3 + 1];
		return sum / (float)polyVertCount;
	}

	/// Computes barycentric coordinates (u, v, w) for point (px, pz) in triangle (ax,az)-(bx,bz)-(cx,cz).
	/// Returns false if the triangle is degenerate.
	private static bool BarycentricCoords(
		float px, float pz,
		float ax, float az, float bx, float bz, float cx, float cz,
		out float u, out float v, out float w)
	{
		float v0x = bx - ax, v0z = bz - az;
		float v1x = cx - ax, v1z = cz - az;
		float v2x = px - ax, v2z = pz - az;

		float dot00 = v0x * v0x + v0z * v0z;
		float dot01 = v0x * v1x + v0z * v1z;
		float dot02 = v0x * v2x + v0z * v2z;
		float dot11 = v1x * v1x + v1z * v1z;
		float dot12 = v1x * v2x + v1z * v2z;

		float invDenom = dot00 * dot11 - dot01 * dot01;
		if (Math.Abs(invDenom) < 1e-8f)
		{
			u = 0; v = 0; w = 0;
			return false;
		}

		invDenom = 1.0f / invDenom;
		v = (dot11 * dot02 - dot01 * dot12) * invDenom;
		w = (dot00 * dot12 - dot01 * dot02) * invDenom;
		u = 1.0f - v - w;
		return true;
	}

	/// Tests if a 2D point (px, pz) is inside a convex polygon (XZ plane).
	private static bool PointInPoly2D(float px, float pz, float[] polyVerts, int32 polyVertCount)
	{
		bool inside = false;
		int32 j = polyVertCount - 1;

		for (int32 i = 0; i < polyVertCount; i++)
		{
			float ix = polyVerts[i * 3], iz = polyVerts[i * 3 + 2];
			float jx = polyVerts[j * 3], jz = polyVerts[j * 3 + 2];

			if (((iz > pz) != (jz > pz)) &&
				(px < (jx - ix) * (pz - iz) / (jz - iz) + ix))
			{
				inside = !inside;
			}
			j = i;
		}

		return inside;
	}

	/// Creates a simple fan triangulation from vertex 0 (no detail vertices).
	/// Sets edge flags for polygon boundary edges.
	private static void TriangulateFan(int32 polyVertCount, List<uint8> outTris)
	{
		for (int32 i = 1; i < polyVertCount - 1; i++)
		{
			uint8 v0 = 0;
			uint8 v1 = (uint8)i;
			uint8 v2 = (uint8)(i + 1);

			// Compute edge flags: each bit indicates a polygon boundary edge.
			// Edge 0: v0-v1, Edge 1: v1-v2, Edge 2: v2-v0
			uint8 flags = 0;

			// For a fan from vertex 0:
			// - Edge v0-v1: boundary if v0=0 and v1=1 (first triangle only)
			// - Edge v1-v2: always a polygon boundary edge
			// - Edge v2-v0: boundary if v2=polyVertCount-1 (last triangle only)
			if (i == 1)
				flags |= (1 << 0); // First edge (0-1) is polygon boundary
			flags |= (1 << 1);     // Middle edge (i to i+1) is always polygon boundary
			if (i == polyVertCount - 2)
				flags |= (1 << 2); // Last edge (last vert back to 0) is polygon boundary

			outTris.Add(v0);
			outTris.Add(v1);
			outTris.Add(v2);
			outTris.Add(flags);
		}
	}

	/// Triangulates a polygon with detail vertices using Delaunay-like point insertion.
	/// Polygon vertices come first (indices 0..polyVertCount-1), then detail vertices
	/// are appended (polyVertCount..polyVertCount+detailCount-1).
	private static void TriangulateWithDetail(
		float[] polyVerts, int32 polyVertCount,
		List<float> detailVerts, List<uint8> outTris)
	{
		int32 detailVertCount = (int32)(detailVerts.Count / 3);
		int32 totalVerts = polyVertCount + detailVertCount;

		// Build a unified vertex array for triangulation
		let verts = scope float[totalVerts * 3];
		for (int32 i = 0; i < polyVertCount; i++)
		{
			verts[i * 3]     = polyVerts[i * 3];
			verts[i * 3 + 1] = polyVerts[i * 3 + 1];
			verts[i * 3 + 2] = polyVerts[i * 3 + 2];
		}
		for (int32 i = 0; i < detailVertCount; i++)
		{
			verts[(polyVertCount + i) * 3]     = detailVerts[i * 3];
			verts[(polyVertCount + i) * 3 + 1] = detailVerts[i * 3 + 1];
			verts[(polyVertCount + i) * 3 + 2] = detailVerts[i * 3 + 2];
		}

		// Start with a fan triangulation of the polygon boundary,
		// then insert each detail vertex by splitting triangles.
		let tris = scope List<int32>(); // Stores triangles as (v0, v1, v2) index triples

		// Initial fan triangulation
		for (int32 i = 1; i < polyVertCount - 1; i++)
		{
			tris.Add(0);
			tris.Add(i);
			tris.Add(i + 1);
		}

		// Insert each detail vertex into the triangulation
		for (int32 di = 0; di < detailVertCount; di++)
		{
			int32 vi = polyVertCount + di;
			float px = verts[vi * 3];
			float pz = verts[vi * 3 + 2];

			// Find which triangle contains this point
			int32 containingTri = -1;
			for (int32 t = 0; t < tris.Count / 3; t++)
			{
				int32 a = tris[t * 3];
				int32 b = tris[t * 3 + 1];
				int32 c = tris[t * 3 + 2];

				if (PointInTriangle2D(px, pz,
					verts[a * 3], verts[a * 3 + 2],
					verts[b * 3], verts[b * 3 + 2],
					verts[c * 3], verts[c * 3 + 2]))
				{
					containingTri = t;
					break;
				}
			}

			if (containingTri < 0)
				continue; // Point outside polygon, skip

			// Split the containing triangle into 3 sub-triangles
			int32 a = tris[containingTri * 3];
			int32 b = tris[containingTri * 3 + 1];
			int32 c = tris[containingTri * 3 + 2];

			// Remove old triangle (replace with last and pop)
			int32 lastTri = (int32)(tris.Count / 3) - 1;
			if (containingTri != lastTri)
			{
				tris[containingTri * 3]     = tris[lastTri * 3];
				tris[containingTri * 3 + 1] = tris[lastTri * 3 + 1];
				tris[containingTri * 3 + 2] = tris[lastTri * 3 + 2];
			}
			tris.RemoveRange(lastTri * 3, 3);

			// Add 3 new triangles
			tris.Add(a); tris.Add(b); tris.Add(vi);
			tris.Add(b); tris.Add(c); tris.Add(vi);
			tris.Add(c); tris.Add(a); tris.Add(vi);

			// Perform edge flips to maintain Delaunay property
			FlipEdges(verts, tris, vi);
		}

		// Convert triangles to output format with edge flags
		for (int32 t = 0; t < tris.Count / 3; t++)
		{
			int32 a = tris[t * 3];
			int32 b = tris[t * 3 + 1];
			int32 c = tris[t * 3 + 2];

			uint8 flags = ComputeEdgeFlags(a, b, c, polyVertCount);

			outTris.Add((uint8)a);
			outTris.Add((uint8)b);
			outTris.Add((uint8)c);
			outTris.Add(flags);
		}
	}

	/// Performs Delaunay edge flips around the newly inserted vertex.
	/// Iterates until no more flips are needed.
	private static void FlipEdges(float[] verts, List<int32> tris, int32 insertedVert)
	{
		// Simple iterative flip: check all edges opposite to the inserted vertex
		bool flipped = true;
		int32 maxIter = (int32)(tris.Count / 3) * 4; // Safety limit
		int32 iter = 0;

		while (flipped && iter < maxIter)
		{
			flipped = false;
			iter++;

			int32 triCount = (int32)(tris.Count / 3);
			for (int32 t = 0; t < triCount; t++)
			{
				int32 a = tris[t * 3];
				int32 b = tris[t * 3 + 1];
				int32 c = tris[t * 3 + 2];

				// Find which vertex in this triangle is the inserted one
				int32 localIdx = -1;
				if (a == insertedVert) localIdx = 0;
				else if (b == insertedVert) localIdx = 1;
				else if (c == insertedVert) localIdx = 2;

				if (localIdx < 0) continue;

				// The edge opposite to the inserted vertex
				int32 edgeV0, edgeV1;
				switch (localIdx)
				{
				case 0: edgeV0 = b; edgeV1 = c;
				case 1: edgeV0 = c; edgeV1 = a;
				default: edgeV0 = a; edgeV1 = b;
				}

				// Find the adjacent triangle sharing this edge
				int32 adjTri = -1;
				int32 adjOpposite = -1;
				for (int32 t2 = 0; t2 < triCount; t2++)
				{
					if (t2 == t) continue;
					int32 ta = tris[t2 * 3];
					int32 tb = tris[t2 * 3 + 1];
					int32 tc = tris[t2 * 3 + 2];

					// Check if t2 shares edge (edgeV0, edgeV1) in reverse
					if ((ta == edgeV1 && tb == edgeV0) || (tb == edgeV1 && tc == edgeV0) || (tc == edgeV1 && ta == edgeV0))
					{
						adjTri = t2;
						// Find the vertex opposite to the shared edge
						if (ta != edgeV0 && ta != edgeV1) adjOpposite = ta;
						else if (tb != edgeV0 && tb != edgeV1) adjOpposite = tb;
						else adjOpposite = tc;
						break;
					}
				}

				if (adjTri < 0 || adjOpposite < 0) continue;

				// Check if flip improves Delaunay condition (in-circle test)
				if (InCircle(verts, insertedVert, edgeV0, edgeV1, adjOpposite))
				{
					// Flip: replace the two triangles
					// Old: (insertedVert, edgeV0, edgeV1) and (adjOpposite, edgeV1, edgeV0)
					// New: (insertedVert, edgeV0, adjOpposite) and (insertedVert, adjOpposite, edgeV1)
					tris[t * 3]     = insertedVert;
					tris[t * 3 + 1] = edgeV0;
					tris[t * 3 + 2] = adjOpposite;

					tris[adjTri * 3]     = insertedVert;
					tris[adjTri * 3 + 1] = adjOpposite;
					tris[adjTri * 3 + 2] = edgeV1;

					flipped = true;
				}
			}
		}
	}

	/// In-circle test: returns true if vertex d lies inside the circumcircle of triangle (a, b, c).
	/// Uses the 2D XZ plane for the test.
	private static bool InCircle(float[] verts, int32 a, int32 b, int32 c, int32 d)
	{
		float ax = verts[a * 3] - verts[d * 3];
		float az = verts[a * 3 + 2] - verts[d * 3 + 2];
		float bx = verts[b * 3] - verts[d * 3];
		float bz = verts[b * 3 + 2] - verts[d * 3 + 2];
		float cx = verts[c * 3] - verts[d * 3];
		float cz = verts[c * 3 + 2] - verts[d * 3 + 2];

		float det = (ax * ax + az * az) * (bx * cz - cx * bz)
				  - (bx * bx + bz * bz) * (ax * cz - cx * az)
				  + (cx * cx + cz * cz) * (ax * bz - bx * az);

		return det > 0;
	}

	/// Point-in-triangle test in 2D (XZ plane).
	private static bool PointInTriangle2D(float px, float pz, float ax, float az, float bx, float bz, float cx, float cz)
	{
		float d1 = (bx - ax) * (pz - az) - (bz - az) * (px - ax);
		float d2 = (cx - bx) * (pz - bz) - (cz - bz) * (px - bx);
		float d3 = (ax - cx) * (pz - cz) - (az - cz) * (px - cx);

		bool hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
		bool hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);

		return !(hasNeg && hasPos);
	}

	/// Computes edge flags for a detail triangle.
	/// A bit is set for each edge that lies on the polygon boundary.
	/// Bit 0: edge v0-v1, Bit 1: edge v1-v2, Bit 2: edge v2-v0.
	/// An edge is a boundary edge if both its vertices are polygon vertices
	/// and they are adjacent in the polygon ring.
	private static uint8 ComputeEdgeFlags(int32 a, int32 b, int32 c, int32 polyVertCount)
	{
		uint8 flags = 0;

		if (IsPolyBoundaryEdge(a, b, polyVertCount))
			flags |= (1 << 0);
		if (IsPolyBoundaryEdge(b, c, polyVertCount))
			flags |= (1 << 1);
		if (IsPolyBoundaryEdge(c, a, polyVertCount))
			flags |= (1 << 2);

		return flags;
	}

	/// Checks if edge (v0, v1) is a polygon boundary edge.
	/// Both vertices must be polygon vertices (index < polyVertCount) and adjacent
	/// in the polygon ring.
	private static bool IsPolyBoundaryEdge(int32 v0, int32 v1, int32 polyVertCount)
	{
		// Both must be polygon vertices
		if (v0 >= polyVertCount || v1 >= polyVertCount)
			return false;

		// Check if they are adjacent in the polygon ring
		int32 diff = Math.Abs(v0 - v1);
		return (diff == 1) || (diff == polyVertCount - 1);
	}
}

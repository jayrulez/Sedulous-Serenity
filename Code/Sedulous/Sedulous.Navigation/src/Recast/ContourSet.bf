using System;
using System.Collections;

namespace Sedulous.Navigation.Recast;

/// A set of contours representing the boundaries of all regions in a compact heightfield.
class ContourSet
{
	public List<Contour> Contours ~ DeleteContainerAndItems!(_);
	public float[3] BMin;
	public float[3] BMax;
	public float CellSize;
	public float CellHeight;
	public int32 Width;
	public int32 Height;
	public int32 BorderSize;
	public float MaxError;

	public this()
	{
		Contours = new List<Contour>();
	}

	/// Builds contours from a compact heightfield with regions assigned.
	public static ContourSet Build(CompactHeightfield chf, float maxError, int32 maxEdgeLen)
	{
		let cs = new ContourSet();
		cs.BMin = chf.BMin;
		cs.BMax = chf.BMax;
		cs.CellSize = chf.CellSize;
		cs.CellHeight = chf.CellHeight;
		cs.Width = chf.Width;
		cs.Height = chf.Height;
		cs.BorderSize = chf.BorderSize;
		cs.MaxError = maxError;

		// Flags to track which edges have been traced
		let flags = new uint8[chf.SpanCount];
		defer delete flags;

		// Mark edges between different regions
		for (int32 z = 0; z < chf.Height; z++)
		{
			for (int32 x = 0; x < chf.Width; x++)
			{
				ref CompactCell cell = ref chf.Cells[x + z * chf.Width];
				for (int32 si = cell.FirstSpan; si < cell.FirstSpan + cell.SpanCount; si++)
				{
					if (chf.Areas[si] == NavArea.Null)
					{
						flags[si] = 0;
						continue;
					}

					ref CompactSpan span = ref chf.Spans[si];
					uint8 f = 0;

					for (int32 dir = 0; dir < 4; dir++)
					{
						uint16 neighborRegion = 0;
						int32 conn = span.GetConnection(dir);
						if (conn != CompactSpan.NotConnected)
						{
							int32 nx = x + CompactHeightfield.DirOffsetX[dir];
							int32 nz = z + CompactHeightfield.DirOffsetZ[dir];
							ref CompactCell nc = ref chf.Cells[nx + nz * chf.Width];
							int32 ni = nc.FirstSpan + conn;
							neighborRegion = chf.Spans[ni].RegionId;
						}

						if (neighborRegion != span.RegionId)
							f |= (uint8)(1 << dir);
					}

					// Invert: flags mark edges that are NOT region boundaries
					flags[si] = (uint8)(f ^ 0xF);
				}
			}
		}

		// Trace contours
		for (int32 z = 0; z < chf.Height; z++)
		{
			for (int32 x = 0; x < chf.Width; x++)
			{
				ref CompactCell cell = ref chf.Cells[x + z * chf.Width];
				for (int32 si = cell.FirstSpan; si < cell.FirstSpan + cell.SpanCount; si++)
				{
					if (flags[si] == 0xF || flags[si] == 0) continue;
					if (chf.Areas[si] == NavArea.Null) continue;
					if (chf.Spans[si].RegionId == 0) continue;

					// Find an untraced boundary edge
					for (int32 dir = 0; dir < 4; dir++)
					{
						if ((flags[si] & (1 << dir)) != 0) continue; // Not a boundary or already traced

						// Actually check if this direction IS a boundary (flag bit = 0 means boundary in our inverted scheme)
						// Wait - we inverted above. Let me re-check.
						// f marks edges that are NOT boundaries (XOR with 0xF).
						// So flags[si] bit=1 means NOT a boundary edge.
						// We want to trace where bit=0 (boundary edges).
						// But we also use flags to track traced edges.
						// Let me reconsider...
					}

					// Trace the contour starting from this span
					let rawVerts = scope List<ContourVertex>();
					TraceContour(chf, x, z, si, flags, rawVerts);

					if (rawVerts.Count >= 3)
					{
						let contour = new Contour();
						contour.RegionId = chf.Spans[si].RegionId;
						contour.Area = chf.Areas[si];

						// Copy raw vertices
						for (var v in rawVerts)
							contour.RawVertices.Add(v);

						// Simplify
						SimplifyContour(rawVerts, contour.Vertices, maxError, maxEdgeLen);

						if (contour.Vertices.Count >= 3)
							cs.Contours.Add(contour);
						else
							delete contour;
					}

					// Mark this span as fully traced
					flags[si] = 0xF;
				}
			}
		}

		return cs;
	}

	/// Traces a contour around a region boundary.
	private static void TraceContour(CompactHeightfield chf, int32 startX, int32 startZ, int32 startSpan, uint8[] flags, List<ContourVertex> verts)
	{
		int32 x = startX;
		int32 z = startZ;
		int32 si = startSpan;
		int32 dir = 0;

		// Find the first boundary direction
		while (dir < 4)
		{
			// In our flag scheme (inverted), bit=0 means boundary
			if ((flags[si] & (1 << dir)) == 0)
				break;
			dir++;
		}
		if (dir >= 4) return; // No boundary edge found

		int32 startDir = dir;
		int32 iter = 0;
		int32 maxIter = chf.SpanCount * 4;

		while (iter < maxIter)
		{
			iter++;

			// Check if current direction is a boundary
			if ((flags[si] & (1 << dir)) == 0)
			{
				// This is a boundary edge - record the vertex
				int32 vx = x;
				int32 vy = (int32)chf.Spans[si].Y;
				int32 vz = z;

				// Adjust vertex position based on direction
				switch (dir)
				{
				case 0: vx++; // East edge
				case 1: vx++; vz++; // North edge
				case 2: vz++; // West edge
				case 3: // South edge - at corner (x, z)
				}

				// Get neighbor region for this edge
				int32 neighborRegion = 0;
				int32 conn = chf.Spans[si].GetConnection(dir);
				if (conn != CompactSpan.NotConnected)
				{
					int32 nx = x + CompactHeightfield.DirOffsetX[dir];
					int32 nz = z + CompactHeightfield.DirOffsetZ[dir];
					ref CompactCell nc = ref chf.Cells[nx + nz * chf.Width];
					int32 ni = nc.FirstSpan + conn;
					neighborRegion = (int32)chf.Spans[ni].RegionId;
				}

				verts.Add(ContourVertex(vx, vy, vz, neighborRegion));

				// Mark this edge as traced
				flags[si] |= (uint8)(1 << dir);

				// Rotate clockwise
				dir = (dir + 1) & 0x3;
			}
			else
			{
				// Not a boundary - step to the neighbor in this direction
				int32 conn = chf.Spans[si].GetConnection(dir);
				if (conn != CompactSpan.NotConnected)
				{
					int32 nx = x + CompactHeightfield.DirOffsetX[dir];
					int32 nz = z + CompactHeightfield.DirOffsetZ[dir];
					ref CompactCell nc = ref chf.Cells[nx + nz * chf.Width];
					si = nc.FirstSpan + conn;
					x = nx;
					z = nz;
				}

				// Rotate counter-clockwise
				dir = (dir + 3) & 0x3;
			}

			// Check if we've returned to the start
			if (si == startSpan && dir == startDir)
				break;
		}
	}

	/// Simplifies a contour using Douglas-Peucker algorithm with edge length subdivision.
	private static void SimplifyContour(List<ContourVertex> rawVerts, List<ContourVertex> simplified, float maxError, int32 maxEdgeLen)
	{
		if (rawVerts.Count < 3) return;

		// Start with corners (vertices where region changes)
		bool hasConnections = false;
		for (int32 i = 0; i < rawVerts.Count; i++)
		{
			int32 j = (i + 1) % (int32)rawVerts.Count;
			if (rawVerts[i].RegionFlag != rawVerts[j].RegionFlag)
			{
				simplified.Add(rawVerts[i]);
				hasConnections = true;
			}
		}

		if (!hasConnections)
		{
			// No region changes - use bounding box corners as initial simplification
			int32 minX = rawVerts[0].X, maxX = rawVerts[0].X;
			int32 minZ = rawVerts[0].Z, maxZ = rawVerts[0].Z;
			int32 minXi = 0, maxXi = 0, minZi = 0, maxZi = 0;

			for (int32 i = 1; i < rawVerts.Count; i++)
			{
				if (rawVerts[i].X < minX) { minX = rawVerts[i].X; minXi = i; }
				if (rawVerts[i].X > maxX) { maxX = rawVerts[i].X; maxXi = i; }
				if (rawVerts[i].Z < minZ) { minZ = rawVerts[i].Z; minZi = i; }
				if (rawVerts[i].Z > maxZ) { maxZ = rawVerts[i].Z; maxZi = i; }
			}

			simplified.Add(rawVerts[minXi]);
			simplified.Add(rawVerts[maxXi]);
			if (minZi != minXi && minZi != maxXi) simplified.Add(rawVerts[minZi]);
			if (maxZi != minXi && maxZi != maxXi && maxZi != minZi) simplified.Add(rawVerts[maxZi]);
		}

		if (simplified.Count < 3)
		{
			// Fallback: use first 3 raw vertices
			simplified.Clear();
			for (int32 i = 0; i < Math.Min(rawVerts.Count, 3); i++)
				simplified.Add(rawVerts[i]);
			return;
		}

		// Douglas-Peucker simplification
		float maxErrorSq = maxError * maxError;
		int32 pass = 0;
		int32 maxPasses = 50;

		while (pass < maxPasses)
		{
			pass++;
			bool changed = false;

			for (int32 i = 0; i < simplified.Count; )
			{
				int32 j = (i + 1) % (int32)simplified.Count;

				// Find the raw vertex range between simplified[i] and simplified[j]
				int32 rawStart = FindRawIndex(rawVerts, simplified[i]);
				int32 rawEnd = FindRawIndex(rawVerts, simplified[j]);

				if (rawStart < 0 || rawEnd < 0)
				{
					i++;
					continue;
				}

				// Find the point with maximum deviation
				float maxDevSq = 0;
				int32 maxIdx = -1;
				int32 count = (int32)rawVerts.Count;

				int32 ci = (rawStart + 1) % count;
				while (ci != rawEnd)
				{
					float dev = PointToSegmentDistSq(
						rawVerts[ci].X, rawVerts[ci].Z,
						simplified[i].X, simplified[i].Z,
						simplified[j].X, simplified[j].Z);

					if (dev > maxDevSq)
					{
						maxDevSq = dev;
						maxIdx = ci;
					}
					ci = (ci + 1) % count;
				}

				if (maxDevSq > maxErrorSq && maxIdx >= 0)
				{
					simplified.Insert(j, rawVerts[maxIdx]);
					changed = true;
				}
				else
				{
					i++;
				}
			}

			if (!changed) break;
		}

		// Subdivide long edges
		if (maxEdgeLen > 0)
		{
			for (int32 i = 0; i < simplified.Count; )
			{
				int32 j = (i + 1) % (int32)simplified.Count;
				int32 dx = simplified[j].X - simplified[i].X;
				int32 dz = simplified[j].Z - simplified[i].Z;
				int32 edgeLenSq = dx * dx + dz * dz;

				if (edgeLenSq > maxEdgeLen * maxEdgeLen)
				{
					// Find midpoint in raw vertices
					int32 rawStart = FindRawIndex(rawVerts, simplified[i]);
					int32 rawEnd = FindRawIndex(rawVerts, simplified[j]);

					if (rawStart >= 0 && rawEnd >= 0)
					{
						int32 midRaw = (rawStart + ((rawEnd - rawStart + (int32)rawVerts.Count) % (int32)rawVerts.Count) / 2) % (int32)rawVerts.Count;
						simplified.Insert(j, rawVerts[midRaw]);
					}
					else
					{
						i++;
					}
				}
				else
				{
					i++;
				}
			}
		}
	}

	/// Finds the index in rawVerts matching the given simplified vertex.
	private static int32 FindRawIndex(List<ContourVertex> rawVerts, ContourVertex v)
	{
		for (int32 i = 0; i < rawVerts.Count; i++)
		{
			if (rawVerts[i].X == v.X && rawVerts[i].Z == v.Z && rawVerts[i].Y == v.Y)
				return i;
		}
		return -1;
	}

	/// Computes squared distance from point (px, pz) to segment (ax, az)-(bx, bz).
	private static float PointToSegmentDistSq(int32 px, int32 pz, int32 ax, int32 az, int32 bx, int32 bz)
	{
		float dx = (float)(bx - ax);
		float dz = (float)(bz - az);
		float lenSq = dx * dx + dz * dz;

		if (lenSq < 1e-6f)
		{
			float ex = (float)(px - ax);
			float ez = (float)(pz - az);
			return ex * ex + ez * ez;
		}

		float t = ((float)(px - ax) * dx + (float)(pz - az) * dz) / lenSq;
		t = Math.Clamp(t, 0.0f, 1.0f);

		float closestX = (float)ax + t * dx;
		float closestZ = (float)az + t * dz;
		float ex2 = (float)px - closestX;
		float ez2 = (float)pz - closestZ;
		return ex2 * ex2 + ez2 * ez2;
	}
}

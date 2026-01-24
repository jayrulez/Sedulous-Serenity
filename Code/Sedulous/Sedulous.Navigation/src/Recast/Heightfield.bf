using System;
using System.Collections;

namespace Sedulous.Navigation.Recast;

/// A voxel heightfield representing rasterized geometry.
/// Each cell column contains a linked list of solid spans.
class Heightfield
{
	/// Grid width in cells (x-axis).
	public int32 Width;
	/// Grid height in cells (z-axis).
	public int32 Height;
	/// World-space minimum bounds.
	public float[3] BMin;
	/// World-space maximum bounds.
	public float[3] BMax;
	/// Cell size in xz plane.
	public float CellSize;
	/// Cell height in y axis.
	public float CellHeight;
	/// Array of span linked-list heads, one per column [Width * Height].
	public HeightfieldSpan[] Spans;

	public this(int32 width, int32 height, float[3] bmin, float[3] bmax, float cellSize, float cellHeight)
	{
		Width = width;
		Height = height;
		BMin = bmin;
		BMax = bmax;
		CellSize = cellSize;
		CellHeight = cellHeight;
		Spans = new HeightfieldSpan[width * height];
	}

	public ~this()
	{
		for (int i = 0; i < Spans.Count; i++)
		{
			var span = Spans[i];
			while (span != null)
			{
				var next = span.Next;
				delete span;
				span = next;
			}
		}
		delete Spans;
	}

	/// Adds a span to the specified column, merging with overlapping spans.
	public void AddSpan(int32 x, int32 z, int32 minY, int32 maxY, uint8 area, int32 flagMergeThreshold)
	{
		int32 idx = x + z * Width;

		HeightfieldSpan newSpan = new HeightfieldSpan(minY, maxY, area);

		// Find insertion point in sorted linked list
		HeightfieldSpan prev = null;
		HeightfieldSpan cur = Spans[idx];

		while (cur != null && cur.MinY <= newSpan.MaxY)
		{
			// Check for overlap/merge
			if (cur.MaxY < newSpan.MinY)
			{
				// Current span is below new span, advance
				prev = cur;
				cur = cur.Next;
				continue;
			}

			// Overlapping spans - merge
			if (cur.MinY < newSpan.MinY)
				newSpan.MinY = cur.MinY;
			if (cur.MaxY > newSpan.MaxY)
				newSpan.MaxY = cur.MaxY;

			// Merge area: keep the one with higher priority (lower non-null value)
			if (Math.Abs(newSpan.MaxY - cur.MaxY) <= flagMergeThreshold)
			{
				newSpan.Area = Math.Max(newSpan.Area, cur.Area);
			}

			// Remove current span from list
			var next = cur.Next;
			if (prev != null)
				prev.Next = next;
			else
				Spans[idx] = next;

			delete cur;
			cur = next;
		}

		// Insert the new span
		if (prev != null)
		{
			newSpan.Next = prev.Next;
			prev.Next = newSpan;
		}
		else
		{
			newSpan.Next = Spans[idx];
			Spans[idx] = newSpan;
		}
	}

	/// Rasterizes a single triangle into the heightfield.
	public void RasterizeTriangle(float* v0, float* v1, float* v2, uint8 area, int32 flagMergeThreshold)
	{
		float ics = 1.0f / CellSize;
		float ich = 1.0f / CellHeight;

		// Calculate triangle bounding box in cell coordinates
		float[3] tmin, tmax;
		tmin[0] = v0[0]; tmin[1] = v0[1]; tmin[2] = v0[2];
		tmax[0] = v0[0]; tmax[1] = v0[1]; tmax[2] = v0[2];

		for (int i = 0; i < 3; i++)
		{
			if (v1[i] < tmin[i]) tmin[i] = v1[i];
			if (v2[i] < tmin[i]) tmin[i] = v2[i];
			if (v1[i] > tmax[i]) tmax[i] = v1[i];
			if (v2[i] > tmax[i]) tmax[i] = v2[i];
		}

		// Skip triangles outside the heightfield bounds
		if (tmax[0] < BMin[0] || tmin[0] > BMax[0]) return;
		if (tmax[2] < BMin[2] || tmin[2] > BMax[2]) return;

		// Clamp to heightfield bounds
		int32 z0 = (int32)((tmin[2] - BMin[2]) * ics);
		int32 z1 = (int32)((tmax[2] - BMin[2]) * ics);
		z0 = Math.Clamp(z0, 0, Height - 1);
		z1 = Math.Clamp(z1, 0, Height - 1);

		// Buffers for polygon clipping
		float[7 * 3] inBuf = .();
		float[7 * 3] outBuf1 = .();
		float[7 * 3] outBuf2 = .();

		for (int32 z = z0; z <= z1; z++)
		{
			// Clip polygon to z slab
			float cz = BMin[2] + (float)z * CellSize;

			// Copy triangle into input buffer
			Internal.MemCpy(&inBuf[0], v0, 3 * sizeof(float));
			Internal.MemCpy(&inBuf[3], v1, 3 * sizeof(float));
			Internal.MemCpy(&inBuf[6], v2, 3 * sizeof(float));

			int32 nIn = 3;
			int32 nOut1 = ClipPolyByPlane(&inBuf, nIn, &outBuf1, 1.0f, 0.0f, -(cz));
			if (nOut1 < 3) continue;

			int32 nOut2 = ClipPolyByPlane(&outBuf1, nOut1, &outBuf2, -1.0f, 0.0f, cz + CellSize);
			if (nOut2 < 3) continue;

			// Find x range
			float pminX = outBuf2[0], pmaxX = outBuf2[0];
			for (int32 i = 1; i < nOut2; i++)
			{
				float px = outBuf2[i * 3];
				if (px < pminX) pminX = px;
				if (px > pmaxX) pmaxX = px;
			}

			int32 x0 = (int32)((pminX - BMin[0]) * ics);
			int32 x1 = (int32)((pmaxX - BMin[0]) * ics);
			x0 = Math.Clamp(x0, 0, Width - 1);
			x1 = Math.Clamp(x1, 0, Width - 1);

			for (int32 x = x0; x <= x1; x++)
			{
				float cx = BMin[0] + (float)x * CellSize;

				// Clip to x slab
				int32 nClip1 = ClipPolyByPlane(&outBuf2, nOut2, &outBuf1, 0.0f, 1.0f, -(cx));
				if (nClip1 < 3) continue;

				int32 nClip2 = ClipPolyByPlane(&outBuf1, nClip1, &inBuf, 0.0f, -1.0f, cx + CellSize);
				if (nClip2 < 3) continue;

				// Find y range of the clipped polygon
				float spanMinY = inBuf[1], spanMaxY = inBuf[1];
				for (int32 i = 1; i < nClip2; i++)
				{
					float py = inBuf[i * 3 + 1];
					if (py < spanMinY) spanMinY = py;
					if (py > spanMaxY) spanMaxY = py;
				}

				int32 yMin = Math.Clamp((int32)((spanMinY - BMin[1]) * ich), 0, 0x7FFF);
				int32 yMax = Math.Clamp((int32)((spanMaxY - BMin[1]) * ich), 0, 0x7FFF);

				if (yMin <= yMax)
				{
					AddSpan(x, z, yMin, yMax, area, flagMergeThreshold);
				}
			}
		}
	}

	/// Rasterizes all triangles from the input geometry.
	public void RasterizeTriangles(IInputGeometryProvider geometry, int32 flagMergeThreshold = 1)
	{
		float* verts = geometry.Vertices;
		int32* tris = geometry.Triangles;
		uint8* areas = geometry.TriangleAreaFlags;

		for (int32 i = 0; i < geometry.TriangleCount; i++)
		{
			int32 i0 = tris[i * 3] * 3;
			int32 i1 = tris[i * 3 + 1] * 3;
			int32 i2 = tris[i * 3 + 2] * 3;

			uint8 area = (areas != null) ? areas[i] : NavArea.Walkable;

			RasterizeTriangle(&verts[i0], &verts[i1], &verts[i2], area, flagMergeThreshold);
		}
	}

	/// Marks non-walkable spans based on slope angle.
	public void FilterWalkableLowHeightSpans(int32 walkableHeight)
	{
		for (int32 i = 0; i < Width * Height; i++)
		{
			var span = Spans[i];
			while (span != null)
			{
				// Check if there's enough clearance above this span
				int32 ceiling = (span.Next != null) ? span.Next.MinY : 0x7FFF;
				int32 clearance = ceiling - span.MaxY;

				if (clearance < walkableHeight)
					span.Area = NavArea.Null;

				span = span.Next;
			}
		}
	}

	/// Filters ledges that are too high to step onto.
	public void FilterLedgeSpans(int32 walkableHeight, int32 walkableClimb)
	{
		for (int32 z = 0; z < Height; z++)
		{
			for (int32 x = 0; x < Width; x++)
			{
				var span = Spans[x + z * Width];
				while (span != null)
				{
					if (span.Area == NavArea.Null)
					{
						span = span.Next;
						continue;
					}

					int32 bot = span.MaxY;
					int32 top = (span.Next != null) ? span.Next.MinY : 0x7FFF;

					// Check all four neighbors
					int32 minh = 0x7FFF;
					int32 asmin = span.MaxY;
					int32 asmax = span.MaxY;

					int32[4] dx = .(0, 1, 0, -1);
					int32[4] dz = .(-1, 0, 1, 0);

					for (int dir = 0; dir < 4; dir++)
					{
						int32 nx = x + dx[dir];
						int32 nz = z + dz[dir];

						if (nx < 0 || nz < 0 || nx >= Width || nz >= Height)
						{
							// Out of bounds = drop-off
							minh = Math.Min(minh, -(walkableClimb) - bot);
							continue;
						}

						var nSpan = Spans[nx + nz * Width];
						int32 nbot = -walkableClimb;
						int32 ntop = (nSpan != null) ? nSpan.MinY : 0x7FFF;

						if (Math.Min(top, ntop) - Math.Max(bot, nbot) > walkableHeight)
							minh = Math.Min(minh, nbot - bot);

						while (nSpan != null)
						{
							nbot = nSpan.MaxY;
							ntop = (nSpan.Next != null) ? nSpan.Next.MinY : 0x7FFF;

							if (Math.Min(top, ntop) - Math.Max(bot, nbot) > walkableHeight)
							{
								minh = Math.Min(minh, nbot - bot);

								if (Math.Abs(nbot - bot) <= walkableClimb)
								{
									if (nbot < asmin) asmin = nbot;
									if (nbot > asmax) asmax = nbot;
								}
							}
							nSpan = nSpan.Next;
						}
					}

					if (minh < -(walkableClimb))
						span.Area = NavArea.Null;

					if ((asmax - asmin) > walkableClimb)
						span.Area = NavArea.Null;

					span = span.Next;
				}
			}
		}
	}

	/// Clips a polygon by a 2D plane defined by (nx*z + nz*x + d >= 0) where
	/// the polygon vertices are 3D with [x, y, z] layout.
	private static int32 ClipPolyByPlane(float* inVerts, int32 numInVerts, float* outVerts, float nx, float nz, float d)
	{
		float[7] dist = .();
		for (int32 i = 0; i < numInVerts; i++)
		{
			// Distance along plane normal: nx * vert.z + nz * vert.x + d
			dist[i] = nx * inVerts[i * 3 + 2] + nz * inVerts[i * 3] + d;
		}

		int32 numOut = 0;
		int32 j = numInVerts - 1;
		for (int32 i = 0; i < numInVerts; j = i, i++)
		{
			bool inj = dist[j] >= 0;
			bool ini = dist[i] >= 0;

			if (inj != ini)
			{
				// Edge crosses the plane - compute intersection
				float t = dist[j] / (dist[j] - dist[i]);
				outVerts[numOut * 3 + 0] = inVerts[j * 3 + 0] + (inVerts[i * 3 + 0] - inVerts[j * 3 + 0]) * t;
				outVerts[numOut * 3 + 1] = inVerts[j * 3 + 1] + (inVerts[i * 3 + 1] - inVerts[j * 3 + 1]) * t;
				outVerts[numOut * 3 + 2] = inVerts[j * 3 + 2] + (inVerts[i * 3 + 2] - inVerts[j * 3 + 2]) * t;
				numOut++;
			}
			if (ini)
			{
				outVerts[numOut * 3 + 0] = inVerts[i * 3 + 0];
				outVerts[numOut * 3 + 1] = inVerts[i * 3 + 1];
				outVerts[numOut * 3 + 2] = inVerts[i * 3 + 2];
				numOut++;
			}
		}

		return numOut;
	}

	/// Marks triangles with slope above walkable angle as non-walkable.
	public static void MarkWalkableTriangles(float walkableSlopeAngle, float* verts, int32* tris, int32 triCount, uint8* areas)
	{
		float walkableThreshold = Math.Cos(walkableSlopeAngle * Math.PI_f / 180.0f);

		for (int32 i = 0; i < triCount; i++)
		{
			int32 i0 = tris[i * 3] * 3;
			int32 i1 = tris[i * 3 + 1] * 3;
			int32 i2 = tris[i * 3 + 2] * 3;

			// Compute triangle normal
			float e0x = verts[i1] - verts[i0];
			float e0y = verts[i1 + 1] - verts[i0 + 1];
			float e0z = verts[i1 + 2] - verts[i0 + 2];
			float e1x = verts[i2] - verts[i0];
			float e1y = verts[i2 + 1] - verts[i0 + 1];
			float e1z = verts[i2 + 2] - verts[i0 + 2];

			float nx = e0y * e1z - e0z * e1y;
			float ny = e0z * e1x - e0x * e1z;
			float nz = e0x * e1y - e0y * e1x;

			// Normalize
			float len = Math.Sqrt(nx * nx + ny * ny + nz * nz);
			if (len > 0)
				ny /= len;

			// Check if slope is within walkable angle.
			// Use abs(ny) to handle both winding orders (up-facing or down-facing normals).
			if (Math.Abs(ny) >= walkableThreshold)
				areas[i] = NavArea.Walkable;
			else
				areas[i] = NavArea.Null;
		}
	}
}

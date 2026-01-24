using System;
using System.Collections;

namespace Sedulous.Navigation.Recast;

/// A compact representation of the walkable space extracted from a Heightfield.
/// Used for region building, distance field computation, and contour generation.
class CompactHeightfield
{
	public int32 Width;
	public int32 Height;
	public int32 SpanCount;
	public int32 WalkableHeight;
	public int32 WalkableClimb;
	public int32 BorderSize;
	public float CellSize;
	public float CellHeight;
	public float[3] BMin;
	public float[3] BMax;
	public int32 MaxRegions;

	public CompactCell[] Cells ~ delete _;
	public CompactSpan[] Spans ~ delete _;
	public uint16[] DistanceField ~ delete _;
	public uint8[] Areas ~ delete _;

	/// Direction offsets for neighbor lookups (E, N, W, S).
	public static int32[4] DirOffsetX = .(1, 0, -1, 0);
	public static int32[4] DirOffsetZ = .(0, 1, 0, -1);

	/// Builds a CompactHeightfield from a solid Heightfield.
	public static CompactHeightfield Build(Heightfield hf, int32 walkableHeight, int32 walkableClimb)
	{
		let chf = new CompactHeightfield();
		chf.Width = hf.Width;
		chf.Height = hf.Height;
		chf.WalkableHeight = walkableHeight;
		chf.WalkableClimb = walkableClimb;
		chf.CellSize = hf.CellSize;
		chf.CellHeight = hf.CellHeight;
		chf.BMin = hf.BMin;
		chf.BMax = hf.BMax;
		chf.BMax[1] += (float)walkableHeight * hf.CellHeight;
		chf.MaxRegions = 0;

		// Count spans
		int32 spanCount = 0;
		for (int32 i = 0; i < hf.Width * hf.Height; i++)
		{
			var s = hf.Spans[i];
			while (s != null)
			{
				if (s.Area != NavArea.Null)
					spanCount++;
				s = s.Next;
			}
		}

		chf.SpanCount = spanCount;
		chf.Cells = new CompactCell[hf.Width * hf.Height];
		chf.Spans = new CompactSpan[spanCount];
		chf.Areas = new uint8[spanCount];

		// Fill in cells and spans
		int32 idx = 0;
		for (int32 z = 0; z < hf.Height; z++)
		{
			for (int32 x = 0; x < hf.Width; x++)
			{
				int32 ci = x + z * hf.Width;
				chf.Cells[ci].FirstSpan = idx;
				int32 count = 0;

				var s = hf.Spans[ci];
				while (s != null)
				{
					if (s.Area != NavArea.Null)
					{
						int32 bot = s.MaxY;
						int32 top = (s.Next != null) ? s.Next.MinY : 0x7FFF;

						chf.Spans[idx].Y = (uint16)Math.Clamp(bot, 0, 0xFFFF);
						chf.Spans[idx].Height = (uint16)Math.Clamp(top - bot, 0, 0xFFFF);
						chf.Spans[idx].Connections = 0;
						chf.Spans[idx].RegionId = 0;
						chf.Areas[idx] = s.Area;

						// Set all connections to not connected initially
						for (int32 dir = 0; dir < 4; dir++)
							chf.Spans[idx].SetConnection(dir, CompactSpan.NotConnected);

						idx++;
						count++;
					}
					s = s.Next;
				}
				chf.Cells[ci].SpanCount = count;
			}
		}

		// Build neighbor connections
		for (int32 z = 0; z < hf.Height; z++)
		{
			for (int32 x = 0; x < hf.Width; x++)
			{
				ref CompactCell cell = ref chf.Cells[x + z * hf.Width];
				for (int32 i = cell.FirstSpan; i < cell.FirstSpan + cell.SpanCount; i++)
				{
					ref CompactSpan span = ref chf.Spans[i];
					for (int32 dir = 0; dir < 4; dir++)
					{
						int32 nx = x + DirOffsetX[dir];
						int32 nz = z + DirOffsetZ[dir];

						if (nx < 0 || nz < 0 || nx >= hf.Width || nz >= hf.Height)
							continue;

						ref CompactCell nCell = ref chf.Cells[nx + nz * hf.Width];
						for (int32 j = nCell.FirstSpan; j < nCell.FirstSpan + nCell.SpanCount; j++)
						{
							ref CompactSpan nSpan = ref chf.Spans[j];
							int32 bot = Math.Max((int32)span.Y, (int32)nSpan.Y);
							int32 top = Math.Min((int32)span.Y + (int32)span.Height, (int32)nSpan.Y + (int32)nSpan.Height);

							if ((top - bot) >= walkableHeight && Math.Abs((int32)nSpan.Y - (int32)span.Y) <= walkableClimb)
							{
								int32 connIdx = j - nCell.FirstSpan;
								if (connIdx < CompactSpan.NotConnected)
								{
									span.SetConnection(dir, connIdx);
									break;
								}
							}
						}
					}
				}
			}
		}

		return chf;
	}

	/// Erodes the walkable area by the specified radius.
	public void ErodeWalkableArea(int32 radius)
	{
		let dist = new uint16[SpanCount];
		defer delete dist;

		// Initialize distances
		for (int32 i = 0; i < SpanCount; i++)
		{
			if (Areas[i] == NavArea.Null)
			{
				dist[i] = 0;
				continue;
			}

			// Check if any neighbor is not connected or non-walkable
			bool border = false;
			for (int32 dir = 0; dir < 4; dir++)
			{
				if (Spans[i].GetConnection(dir) == CompactSpan.NotConnected)
				{
					border = true;
					break;
				}
			}
			dist[i] = border ? (uint16)0 : (uint16)0xFFFF;
		}

		// Forward pass (2-pass distance transform)
		for (int32 z = 0; z < Height; z++)
		{
			for (int32 x = 0; x < Width; x++)
			{
				ref CompactCell cell = ref Cells[x + z * Width];
				for (int32 si = cell.FirstSpan; si < cell.FirstSpan + cell.SpanCount; si++)
				{
					ref CompactSpan span = ref Spans[si];

					// Check (-1, 0) and (0, -1)
					if (span.GetConnection(2) != CompactSpan.NotConnected) // West
					{
						int32 nx = x + DirOffsetX[2];
						int32 nz = z + DirOffsetZ[2];
						ref CompactCell nc = ref Cells[nx + nz * Width];
						int32 ni = nc.FirstSpan + span.GetConnection(2);
						if (dist[ni] + 2 < dist[si])
							dist[si] = (uint16)(dist[ni] + 2);
					}
					if (span.GetConnection(3) != CompactSpan.NotConnected) // South
					{
						int32 nx = x + DirOffsetX[3];
						int32 nz = z + DirOffsetZ[3];
						ref CompactCell nc = ref Cells[nx + nz * Width];
						int32 ni = nc.FirstSpan + span.GetConnection(3);
						if (dist[ni] + 2 < dist[si])
							dist[si] = (uint16)(dist[ni] + 2);
					}
				}
			}
		}

		// Backward pass
		for (int32 z = Height - 1; z >= 0; z--)
		{
			for (int32 x = Width - 1; x >= 0; x--)
			{
				ref CompactCell cell = ref Cells[x + z * Width];
				for (int32 si = cell.FirstSpan; si < cell.FirstSpan + cell.SpanCount; si++)
				{
					ref CompactSpan span = ref Spans[si];

					if (span.GetConnection(0) != CompactSpan.NotConnected) // East
					{
						int32 nx = x + DirOffsetX[0];
						int32 nz = z + DirOffsetZ[0];
						ref CompactCell nc = ref Cells[nx + nz * Width];
						int32 ni = nc.FirstSpan + span.GetConnection(0);
						if (dist[ni] + 2 < dist[si])
							dist[si] = (uint16)(dist[ni] + 2);
					}
					if (span.GetConnection(1) != CompactSpan.NotConnected) // North
					{
						int32 nx = x + DirOffsetX[1];
						int32 nz = z + DirOffsetZ[1];
						ref CompactCell nc = ref Cells[nx + nz * Width];
						int32 ni = nc.FirstSpan + span.GetConnection(1);
						if (dist[ni] + 2 < dist[si])
							dist[si] = (uint16)(dist[ni] + 2);
					}
				}
			}
		}

		// Apply erosion: mark spans with distance < radius*2 as non-walkable
		uint16 threshold = (uint16)(radius * 2);
		for (int32 i = 0; i < SpanCount; i++)
		{
			if (dist[i] < threshold)
				Areas[i] = NavArea.Null;
		}
	}

	/// Builds the distance field used for watershed region building.
	public void BuildDistanceField()
	{
		DistanceField = new uint16[SpanCount];

		// Initialize: border spans get 0, others get max
		for (int32 i = 0; i < SpanCount; i++)
		{
			if (Areas[i] == NavArea.Null)
			{
				DistanceField[i] = 0;
				continue;
			}

			bool isBorder = false;
			for (int32 dir = 0; dir < 4; dir++)
			{
				if (Spans[i].GetConnection(dir) == CompactSpan.NotConnected)
				{
					isBorder = true;
					break;
				}
			}
			DistanceField[i] = isBorder ? (uint16)0 : (uint16)0xFFFF;
		}

		// Forward pass
		for (int32 z = 0; z < Height; z++)
		{
			for (int32 x = 0; x < Width; x++)
			{
				ref CompactCell cell = ref Cells[x + z * Width];
				for (int32 si = cell.FirstSpan; si < cell.FirstSpan + cell.SpanCount; si++)
				{
					ref CompactSpan span = ref Spans[si];

					// West neighbor
					if (span.GetConnection(2) != CompactSpan.NotConnected)
					{
						int32 nx = x - 1;
						int32 nz = z;
						ref CompactCell nc = ref Cells[nx + nz * Width];
						int32 ni = nc.FirstSpan + span.GetConnection(2);
						if (DistanceField[ni] + 2 < DistanceField[si])
							DistanceField[si] = (uint16)(DistanceField[ni] + 2);

						// Diagonal: SW
						ref CompactSpan ns = ref Spans[ni];
						if (ns.GetConnection(3) != CompactSpan.NotConnected)
						{
							int32 nnx = nx + DirOffsetX[3];
							int32 nnz = nz + DirOffsetZ[3];
							ref CompactCell nnc = ref Cells[nnx + nnz * Width];
							int32 nni = nnc.FirstSpan + ns.GetConnection(3);
							if (DistanceField[nni] + 3 < DistanceField[si])
								DistanceField[si] = (uint16)(DistanceField[nni] + 3);
						}
					}

					// South neighbor
					if (span.GetConnection(3) != CompactSpan.NotConnected)
					{
						int32 nx = x;
						int32 nz = z - 1;
						ref CompactCell nc = ref Cells[nx + nz * Width];
						int32 ni = nc.FirstSpan + span.GetConnection(3);
						if (DistanceField[ni] + 2 < DistanceField[si])
							DistanceField[si] = (uint16)(DistanceField[ni] + 2);

						// Diagonal: SE
						ref CompactSpan ns = ref Spans[ni];
						if (ns.GetConnection(0) != CompactSpan.NotConnected)
						{
							int32 nnx = nx + DirOffsetX[0];
							int32 nnz = nz + DirOffsetZ[0];
							ref CompactCell nnc = ref Cells[nnx + nnz * Width];
							int32 nni = nnc.FirstSpan + ns.GetConnection(0);
							if (DistanceField[nni] + 3 < DistanceField[si])
								DistanceField[si] = (uint16)(DistanceField[nni] + 3);
						}
					}
				}
			}
		}

		// Backward pass
		for (int32 z = Height - 1; z >= 0; z--)
		{
			for (int32 x = Width - 1; x >= 0; x--)
			{
				ref CompactCell cell = ref Cells[x + z * Width];
				for (int32 si = cell.FirstSpan; si < cell.FirstSpan + cell.SpanCount; si++)
				{
					ref CompactSpan span = ref Spans[si];

					// East neighbor
					if (span.GetConnection(0) != CompactSpan.NotConnected)
					{
						int32 nx = x + 1;
						int32 nz = z;
						ref CompactCell nc = ref Cells[nx + nz * Width];
						int32 ni = nc.FirstSpan + span.GetConnection(0);
						if (DistanceField[ni] + 2 < DistanceField[si])
							DistanceField[si] = (uint16)(DistanceField[ni] + 2);

						// Diagonal: NE
						ref CompactSpan ns = ref Spans[ni];
						if (ns.GetConnection(1) != CompactSpan.NotConnected)
						{
							int32 nnx = nx + DirOffsetX[1];
							int32 nnz = nz + DirOffsetZ[1];
							ref CompactCell nnc = ref Cells[nnx + nnz * Width];
							int32 nni = nnc.FirstSpan + ns.GetConnection(1);
							if (DistanceField[nni] + 3 < DistanceField[si])
								DistanceField[si] = (uint16)(DistanceField[nni] + 3);
						}
					}

					// North neighbor
					if (span.GetConnection(1) != CompactSpan.NotConnected)
					{
						int32 nx = x;
						int32 nz = z + 1;
						ref CompactCell nc = ref Cells[nx + nz * Width];
						int32 ni = nc.FirstSpan + span.GetConnection(1);
						if (DistanceField[ni] + 2 < DistanceField[si])
							DistanceField[si] = (uint16)(DistanceField[ni] + 2);

						// Diagonal: NW
						ref CompactSpan ns = ref Spans[ni];
						if (ns.GetConnection(2) != CompactSpan.NotConnected)
						{
							int32 nnx = nx + DirOffsetX[2];
							int32 nnz = nz + DirOffsetZ[2];
							ref CompactCell nnc = ref Cells[nnx + nnz * Width];
							int32 nni = nnc.FirstSpan + ns.GetConnection(2);
							if (DistanceField[nni] + 3 < DistanceField[si])
								DistanceField[si] = (uint16)(DistanceField[nni] + 3);
						}
					}
				}
			}
		}
	}

	/// Builds regions using flood fill from distance field maxima.
	public void BuildRegionsWatershed(int32 minRegionArea, int32 mergeRegionArea)
	{
		if (DistanceField == null)
			BuildDistanceField();

		uint16 regionId = 1;
		let stack = scope List<int32>();

		// Connected-component flood fill.
		// Each connected group of walkable spans becomes a region.
		for (int32 z = 0; z < Height; z++)
		{
			for (int32 x = 0; x < Width; x++)
			{
				ref CompactCell cell = ref Cells[x + z * Width];
				for (int32 si = cell.FirstSpan; si < cell.FirstSpan + cell.SpanCount; si++)
				{
					if (Areas[si] == NavArea.Null) continue;
					if (Spans[si].RegionId != 0) continue;

					// Flood fill from this seed
					stack.Clear();
					stack.Add(si);
					Spans[si].RegionId = regionId;

					int32 regionSize = 0;

					while (stack.Count > 0)
					{
						int32 ci = stack.PopBack();
						regionSize++;

						int32 cx, cz;
						FindSpanLocation(ci, out cx, out cz);

						for (int32 dir = 0; dir < 4; dir++)
						{
							int32 conn = Spans[ci].GetConnection(dir);
							if (conn == CompactSpan.NotConnected) continue;

							int32 nx = cx + DirOffsetX[dir];
							int32 nz = cz + DirOffsetZ[dir];
							if (nx < 0 || nz < 0 || nx >= Width || nz >= Height) continue;

							ref CompactCell nc = ref Cells[nx + nz * Width];
							int32 ni = nc.FirstSpan + conn;

							if (ni < 0 || ni >= SpanCount) continue;
							if (Areas[ni] == NavArea.Null) continue;
							if (Spans[ni].RegionId != 0) continue;

							Spans[ni].RegionId = regionId;
							stack.Add(ni);
						}
					}

					if (regionSize >= minRegionArea)
						regionId++;
					else
					{
						// Region too small, reset
						for (int32 i2 = 0; i2 < SpanCount; i2++)
						{
							if (Spans[i2].RegionId == regionId)
								Spans[i2].RegionId = 0;
						}
					}
				}
			}
		}

		// Merge small regions
		if (mergeRegionArea > 0 && regionId > 1)
		{
			MergeSmallRegions(regionId, mergeRegionArea);
		}

		MaxRegions = (int32)regionId;
	}

	/// Builds regions using monotone partitioning (faster, more polygons).
	public void BuildRegionsMonotone(int32 minRegionArea, int32 mergeRegionArea)
	{
		uint16 regionId = 1;

		for (int32 z = 0; z < Height; z++)
		{
			for (int32 x = 0; x < Width; x++)
			{
				ref CompactCell cell = ref Cells[x + z * Width];
				for (int32 si = cell.FirstSpan; si < cell.FirstSpan + cell.SpanCount; si++)
				{
					if (Areas[si] == NavArea.Null)
					{
						Spans[si].RegionId = 0;
						continue;
					}

					// Check south neighbor
					uint16 prevReg = 0;
					if (Spans[si].GetConnection(3) != CompactSpan.NotConnected)
					{
						int32 nx = x;
						int32 nz = z - 1;
						if (nz >= 0)
						{
							ref CompactCell nc = ref Cells[nx + nz * Width];
							int32 ni = nc.FirstSpan + Spans[si].GetConnection(3);
							prevReg = Spans[ni].RegionId;
						}
					}

					if (prevReg == 0)
					{
						// New region
						Spans[si].RegionId = regionId++;
					}
					else
					{
						Spans[si].RegionId = prevReg;
					}
				}
			}
		}

		MaxRegions = (int32)regionId;
	}

	/// Merges regions smaller than the threshold into their largest neighbor.
	private void MergeSmallRegions(uint16 maxRegionId, int32 mergeRegionArea)
	{
		// Count region sizes
		let regionSizes = scope int32[maxRegionId];
		for (int32 i = 0; i < SpanCount; i++)
		{
			uint16 r = Spans[i].RegionId;
			if (r > 0 && r < maxRegionId)
				regionSizes[r]++;
		}

		// For each small region, find the largest neighboring region and merge
		for (uint16 r = 1; r < maxRegionId; r++)
		{
			if (regionSizes[r] == 0 || regionSizes[r] >= mergeRegionArea)
				continue;

			// Find best neighbor region
			uint16 bestNeighbor = 0;
			int32 bestNeighborSize = 0;

			for (int32 i = 0; i < SpanCount; i++)
			{
				if (Spans[i].RegionId != r) continue;

				int32 cx, cz;
				FindSpanLocation(i, out cx, out cz);

				for (int32 dir = 0; dir < 4; dir++)
				{
					int32 conn = Spans[i].GetConnection(dir);
					if (conn == CompactSpan.NotConnected) continue;

					int32 nx = cx + DirOffsetX[dir];
					int32 nz = cz + DirOffsetZ[dir];
					ref CompactCell nc = ref Cells[nx + nz * Width];
					int32 ni = nc.FirstSpan + conn;
					uint16 nr = Spans[ni].RegionId;

					if (nr != 0 && nr != r && regionSizes[nr] > bestNeighborSize)
					{
						bestNeighbor = nr;
						bestNeighborSize = regionSizes[nr];
					}
				}
			}

			if (bestNeighbor != 0)
			{
				// Merge: reassign all spans from region r to bestNeighbor
				for (int32 i = 0; i < SpanCount; i++)
				{
					if (Spans[i].RegionId == r)
						Spans[i].RegionId = bestNeighbor;
				}
				regionSizes[bestNeighbor] += regionSizes[r];
				regionSizes[r] = 0;
			}
		}
	}

	/// Finds the grid cell coordinates (x, z) for a given span index.
	public void FindSpanLocation(int32 spanIndex, out int32 x, out int32 z)
	{
		x = 0;
		z = 0;
		for (int32 cz = 0; cz < Height; cz++)
		{
			for (int32 cx = 0; cx < Width; cx++)
			{
				ref CompactCell cell = ref Cells[cx + cz * Width];
				if (spanIndex >= cell.FirstSpan && spanIndex < cell.FirstSpan + cell.SpanCount)
				{
					x = cx;
					z = cz;
					return;
				}
			}
		}
	}

	/// Gets the grid x-coordinate for a span (helper for internal use).
	private int32 FindCellX(int32 spanIndex)
	{
		for (int32 cz = 0; cz < Height; cz++)
		{
			for (int32 cx = 0; cx < Width; cx++)
			{
				ref CompactCell cell = ref Cells[cx + cz * Width];
				if (spanIndex >= cell.FirstSpan && spanIndex < cell.FirstSpan + cell.SpanCount)
					return cx;
			}
		}
		return 0;
	}
}

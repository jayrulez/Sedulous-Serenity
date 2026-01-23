using System;
using System.Collections;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation.Recast;

/// Builds a navigation mesh from input geometry through the full Recast pipeline.
static class NavMeshBuilder
{
	/// Builds a single-tile navigation mesh from the given geometry.
	public static NavMeshBuildResult BuildSingle(IInputGeometryProvider geometry, in NavMeshBuildConfig config)
	{
		let result = new NavMeshBuildResult();

		if (geometry == null || geometry.VertexCount == 0 || geometry.TriangleCount == 0)
		{
			result.ErrorMessage = new String("No input geometry provided.");
			return result;
		}

		// Step 1: Calculate grid size
		var cfg = config;
		let bounds = geometry.Bounds;
		cfg.BMin = .(bounds.Min.X, bounds.Min.Y, bounds.Min.Z);
		cfg.BMax = .(bounds.Max.X, bounds.Max.Y, bounds.Max.Z);

		int32 gridWidth = (int32)((cfg.BMax[0] - cfg.BMin[0]) / cfg.CellSize + 0.5f);
		int32 gridHeight = (int32)((cfg.BMax[2] - cfg.BMin[2]) / cfg.CellSize + 0.5f);

		if (gridWidth <= 0 || gridHeight <= 0)
		{
			result.ErrorMessage = new String("Grid dimensions are zero. Check bounds and cell size.");
			return result;
		}

		// Step 2: Mark walkable triangles
		let areas = new uint8[geometry.TriangleCount];
		defer delete areas;

		if (geometry.TriangleAreaFlags != null)
		{
			Internal.MemCpy(areas.Ptr, geometry.TriangleAreaFlags, geometry.TriangleCount * sizeof(uint8));
		}
		else
		{
			Heightfield.MarkWalkableTriangles(cfg.WalkableSlopeAngle, geometry.Vertices, geometry.Triangles, geometry.TriangleCount, areas.Ptr);
		}

		// Step 3: Create and rasterize heightfield
		let hf = new Heightfield(gridWidth, gridHeight, cfg.BMin, cfg.BMax, cfg.CellSize, cfg.CellHeight);
		defer delete hf;

		// Rasterize triangles with area flags
		float* verts = geometry.Vertices;
		int32* tris = geometry.Triangles;

		for (int32 i = 0; i < geometry.TriangleCount; i++)
		{
			if (areas[i] == NavArea.Null) continue;

			int32 i0 = tris[i * 3] * 3;
			int32 i1 = tris[i * 3 + 1] * 3;
			int32 i2 = tris[i * 3 + 2] * 3;

			hf.RasterizeTriangle(&verts[i0], &verts[i1], &verts[i2], areas[i], cfg.WalkableClimb);
		}

		// Step 4: Filter heightfield
		hf.FilterWalkableLowHeightSpans(cfg.WalkableHeight);
		hf.FilterLedgeSpans(cfg.WalkableHeight, cfg.WalkableClimb);

		// Step 5: Build compact heightfield
		let chf = CompactHeightfield.Build(hf, cfg.WalkableHeight, cfg.WalkableClimb);
		defer delete chf;

		if (chf.SpanCount == 0)
		{
			result.ErrorMessage = new String("No walkable spans found after filtering.");
			return result;
		}

		result.Stats.SpanCount = chf.SpanCount;

		// Step 6: Erode walkable area
		if (cfg.WalkableRadius > 0)
			chf.ErodeWalkableArea(cfg.WalkableRadius);

		// Step 7: Build distance field and regions
		chf.BuildDistanceField();

		switch (cfg.RegionStrategy)
		{
		case .Watershed:
			chf.BuildRegionsWatershed(cfg.MinRegionArea, cfg.MergeRegionArea);
		case .Monotone:
			chf.BuildRegionsMonotone(cfg.MinRegionArea, cfg.MergeRegionArea);
		case .Layer:
			chf.BuildRegionsMonotone(cfg.MinRegionArea, cfg.MergeRegionArea); // Fallback for Phase 1
		}

		result.Stats.RegionCount = chf.MaxRegions;

		if (chf.MaxRegions <= 1)
		{
			result.ErrorMessage = new String("No regions were built. Geometry may be too small or config too restrictive.");
			return result;
		}

		// Step 8: Build contours
		let contourSet = ContourSet.Build(chf, cfg.MaxSimplificationError, cfg.MaxEdgeLength);
		defer delete contourSet;

		if (contourSet.Contours.Count == 0)
		{
			result.ErrorMessage = new String("No contours were generated from regions.");
			return result;
		}

		result.Stats.ContourCount = (int32)contourSet.Contours.Count;

		// Step 9: Build polygon mesh
		let polyMesh = PolyMesh.Build(contourSet, cfg.MaxVertsPerPoly);

		if (polyMesh.PolyCount == 0)
		{
			delete polyMesh;
			result.ErrorMessage = new String("No polygons were generated from contours.");
			return result;
		}

		result.Stats.VertexCount = polyMesh.VertexCount;
		result.Stats.PolyCount = polyMesh.PolyCount;
		result.PolyMesh = polyMesh;

		// Step 10: Build detail mesh for height accuracy
		let detailMesh = PolyMeshDetail.Build(polyMesh, chf, cfg.DetailSampleDist, cfg.DetailSampleMaxError);
		defer { if (detailMesh != null) delete detailMesh; }

		// Step 11: Create NavMesh from PolyMesh
		let navMesh = CreateNavMeshFromPolyMesh(polyMesh, detailMesh, cfg);
		if (navMesh == null)
		{
			result.ErrorMessage = new String("Failed to create NavMesh from polygon mesh.");
			return result;
		}

		result.NavMesh = navMesh;
		result.Success = true;
		return result;
	}

	/// Builds a single tile from geometry within the specified bounds.
	/// Returns a NavMeshTile ready to be added to a NavMesh, or null on failure.
	/// The tile coordinates (tileX, tileZ) are stored in the returned tile.
	public static NavMeshTile BuildTile(IInputGeometryProvider geometry, in NavMeshBuildConfig config,
		float[3] tileBMin, float[3] tileBMax, int32 tileX, int32 tileZ)
	{
		if (geometry == null || geometry.VertexCount == 0 || geometry.TriangleCount == 0)
			return null;

		var cfg = config;
		cfg.BMin = tileBMin;
		cfg.BMax = tileBMax;

		// Expand bounds by border for stitching
		float borderExpand = (float)cfg.BorderSize * cfg.CellSize;
		float[3] expandedMin = .(cfg.BMin[0] - borderExpand, cfg.BMin[1], cfg.BMin[2] - borderExpand);
		float[3] expandedMax = .(cfg.BMax[0] + borderExpand, cfg.BMax[1], cfg.BMax[2] + borderExpand);

		int32 gridWidth = (int32)((expandedMax[0] - expandedMin[0]) / cfg.CellSize + 0.5f);
		int32 gridHeight = (int32)((expandedMax[2] - expandedMin[2]) / cfg.CellSize + 0.5f);
		if (gridWidth <= 0 || gridHeight <= 0)
			return null;

		// Mark walkable triangles
		let areas = new uint8[geometry.TriangleCount];
		defer delete areas;

		if (geometry.TriangleAreaFlags != null)
			Internal.MemCpy(areas.Ptr, geometry.TriangleAreaFlags, geometry.TriangleCount * sizeof(uint8));
		else
			Heightfield.MarkWalkableTriangles(cfg.WalkableSlopeAngle, geometry.Vertices, geometry.Triangles, geometry.TriangleCount, areas.Ptr);

		// Create heightfield with expanded bounds
		let hf = new Heightfield(gridWidth, gridHeight, expandedMin, expandedMax, cfg.CellSize, cfg.CellHeight);
		defer delete hf;

		float* verts = geometry.Vertices;
		int32* tris = geometry.Triangles;
		for (int32 i = 0; i < geometry.TriangleCount; i++)
		{
			if (areas[i] == NavArea.Null) continue;
			int32 i0 = tris[i * 3] * 3;
			int32 i1 = tris[i * 3 + 1] * 3;
			int32 i2 = tris[i * 3 + 2] * 3;
			hf.RasterizeTriangle(&verts[i0], &verts[i1], &verts[i2], areas[i], cfg.WalkableClimb);
		}

		hf.FilterWalkableLowHeightSpans(cfg.WalkableHeight);
		hf.FilterLedgeSpans(cfg.WalkableHeight, cfg.WalkableClimb);

		let chf = CompactHeightfield.Build(hf, cfg.WalkableHeight, cfg.WalkableClimb);
		defer delete chf;
		if (chf.SpanCount == 0) return null;

		if (cfg.WalkableRadius > 0)
			chf.ErodeWalkableArea(cfg.WalkableRadius);

		chf.BuildDistanceField();
		chf.BuildRegionsWatershed(cfg.MinRegionArea, cfg.MergeRegionArea);
		if (chf.MaxRegions <= 1) return null;

		let contourSet = ContourSet.Build(chf, cfg.MaxSimplificationError, cfg.MaxEdgeLength);
		defer delete contourSet;
		if (contourSet.Contours.Count == 0) return null;

		let polyMesh = PolyMesh.Build(contourSet, cfg.MaxVertsPerPoly);
		defer delete polyMesh;
		if (polyMesh.PolyCount == 0) return null;

		let detailMesh = PolyMeshDetail.Build(polyMesh, chf, cfg.DetailSampleDist, cfg.DetailSampleMaxError);
		defer { if (detailMesh != null) delete detailMesh; }

		// Clip the poly mesh to the original tile bounds (not expanded)
		// This ensures polygon edges align with tile boundaries for stitching.
		// For now, we build with expanded bounds and trust that polygons near borders
		// will have vertices on the tile boundary line.

		let tile = CreateTileFromPolyMesh(polyMesh, detailMesh, tileX, tileZ, tileBMin, tileBMax);
		return tile;
	}

	/// Converts a PolyMesh into a runtime NavMesh data structure.
	private static NavMesh CreateNavMeshFromPolyMesh(PolyMesh polyMesh, PolyMeshDetail detailMesh, NavMeshBuildConfig config)
	{
		let navMesh = new NavMesh();

		NavMeshParams @params = .();
		@params.Origin = polyMesh.BMin;
		@params.TileWidth = (polyMesh.BMax[0] - polyMesh.BMin[0]);
		@params.TileHeight = (polyMesh.BMax[2] - polyMesh.BMin[2]);
		@params.MaxTiles = 1;
		@params.MaxPolys = polyMesh.PolyCount;

		if (navMesh.Init(@params) != .Success)
		{
			delete navMesh;
			return null;
		}

		let tile = CreateTileFromPolyMesh(polyMesh, detailMesh, 0, 0, polyMesh.BMin, polyMesh.BMax);
		if (tile == null)
		{
			delete navMesh;
			return null;
		}

		PolyRef baseRef;
		navMesh.AddTile(tile, out baseRef);
		return navMesh;
	}

	/// Creates a NavMeshTile from a PolyMesh and optional detail mesh.
	private static NavMeshTile CreateTileFromPolyMesh(PolyMesh polyMesh, PolyMeshDetail detailMesh,
		int32 tileX, int32 tileZ, float[3] tileBMin, float[3] tileBMax)
	{
		let tile = new NavMeshTile();
		tile.X = tileX;
		tile.Z = tileZ;
		tile.Layer = 0;
		tile.BMin = tileBMin;
		tile.BMax = tileBMax;
		tile.PolyCount = polyMesh.PolyCount;
		tile.VertexCount = polyMesh.VertexCount;

		// Convert vertices from voxel to world coordinates
		tile.Vertices = new float[polyMesh.VertexCount * 3];
		for (int32 i = 0; i < polyMesh.VertexCount; i++)
		{
			tile.Vertices[i * 3] = polyMesh.BMin[0] + (float)polyMesh.Vertices[i * 3] * polyMesh.CellSize;
			tile.Vertices[i * 3 + 1] = polyMesh.BMin[1] + (float)polyMesh.Vertices[i * 3 + 1] * polyMesh.CellHeight;
			tile.Vertices[i * 3 + 2] = polyMesh.BMin[2] + (float)polyMesh.Vertices[i * 3 + 2] * polyMesh.CellSize;
		}

		// Convert polygons
		int32 nvp = polyMesh.MaxVertsPerPoly;
		tile.Polygons = new NavPoly[polyMesh.PolyCount];

		for (int32 i = 0; i < polyMesh.PolyCount; i++)
		{
			ref NavPoly poly = ref tile.Polygons[i];
			poly = .();
			poly.Area = polyMesh.Areas[i];
			poly.Flags = polyMesh.Flags[i];
			poly.Type = .Ground;
			poly.FirstLink = -1;

			int32 polyBase = i * nvp * 2;
			int32 vertCount = 0;

			for (int32 j = 0; j < nvp; j++)
			{
				int32 vi = polyMesh.Polygons[polyBase + j];
				if (vi == PolyMesh.NullIndex) break;
				poly.VertexIndices[j] = (uint16)vi;
				vertCount++;

				// Neighbor info is in the second half
				int32 ni = polyMesh.Polygons[polyBase + nvp + j];
				if (ni != PolyMesh.NullIndex)
					poly.Neighbors[j] = (uint16)(ni + 1); // +1 because 0 means no neighbor
				else
					poly.Neighbors[j] = 0;
			}

			poly.VertexCount = (uint8)vertCount;
		}

		// Copy detail mesh data to tile
		if (detailMesh != null)
		{
			tile.DetailMeshCount = detailMesh.MeshCount;
			tile.DetailMeshes = new NavPolyDetail[detailMesh.MeshCount];
			for (int32 i = 0; i < detailMesh.MeshCount; i++)
				tile.DetailMeshes[i] = detailMesh.DetailMeshes[i];

			tile.DetailVertexCount = detailMesh.DetailVertexCount;
			if (detailMesh.DetailVertexCount > 0)
			{
				tile.DetailVertices = new float[detailMesh.DetailVertexCount * 3];
				Internal.MemCpy(tile.DetailVertices.Ptr, detailMesh.DetailVertices.Ptr, detailMesh.DetailVertexCount * 3 * sizeof(float));
			}

			tile.DetailTriangleCount = detailMesh.DetailTriangleCount;
			if (detailMesh.DetailTriangleCount > 0)
			{
				tile.DetailTriangles = new uint8[detailMesh.DetailTriangleCount * 4];
				Internal.MemCpy(tile.DetailTriangles.Ptr, detailMesh.DetailTriangles.Ptr, detailMesh.DetailTriangleCount * 4 * sizeof(uint8));
			}
		}

		return tile;
	}
}

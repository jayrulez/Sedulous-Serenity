namespace Sedulous.Framework.Navigation;

using System;
using recastnavigation_Beef;

/// Build result from NavMeshBuilder.
class NavMeshBuildResult
{
	public bool Success;
	public NavMesh NavMesh ~ delete _;
	public String ErrorMessage ~ delete _;
	public NavMeshBuildStats Stats;
}

/// Statistics from navmesh building.
struct NavMeshBuildStats
{
	public int32 VertexCount;
	public int32 PolyCount;
	public int32 TileCount;
}

/// Static class for building navigation meshes.
static class NavMeshBuilder
{
	/// Builds a single-tile navigation mesh from geometry.
	public static NavMeshBuildResult BuildSingle(IInputGeometryProvider geometry, in NavMeshBuildConfig config)
	{
		let result = new NavMeshBuildResult();
		result.Success = false;

		if (geometry == null || geometry.VertexCount == 0 || geometry.TriangleCount == 0)
		{
			result.ErrorMessage = new String("Invalid input geometry");
			return result;
		}

		// Get bounds
		let bounds = geometry.Bounds;
		float[3] bmin = .(bounds.Min.X, bounds.Min.Y, bounds.Min.Z);
		float[3] bmax = .(bounds.Max.X, bounds.Max.Y, bounds.Max.Z);

		// Create context
		let ctx = rcCreateContext(1, 1);
		defer { rcDestroyContext(ctx); }

		// Calculate grid size
		int32 gw = 0, gh = 0;
		rcCalcGridSize(&bmin[0], &bmax[0], config.CellSize, &gw, &gh);

		// Create heightfield
		let hf = rcAllocHeightfield();
		defer { rcFreeHeightField(hf); }

		if (rcCreateHeightfield(ctx, hf, gw, gh, &bmin[0], &bmax[0], config.CellSize, config.CellHeight) == 0)
		{
			result.ErrorMessage = new String("Could not create heightfield");
			return result;
		}

		// Mark walkable triangles
		int32 ntris = geometry.TriangleCount;
		uint8* triareas = new uint8[ntris]*;
		defer { delete triareas; }

		Internal.MemSet(triareas, 0, ntris);
		rcMarkWalkableTriangles(ctx, config.AgentMaxSlope, geometry.Vertices, geometry.VertexCount,
			geometry.Triangles, ntris, triareas);

		// Rasterize triangles
		if (rcRasterizeTriangles(ctx, geometry.Vertices, geometry.VertexCount,
			geometry.Triangles, triareas, ntris, hf, (int32)(config.AgentMaxClimb / config.CellHeight)) == 0)
		{
			result.ErrorMessage = new String("Could not rasterize triangles");
			return result;
		}

		// Filter walkables
		int32 walkableHeight = (int32)Math.Ceiling(config.AgentHeight / config.CellHeight);
		int32 walkableClimb = (int32)Math.Floor(config.AgentMaxClimb / config.CellHeight);

		rcFilterLowHangingWalkableObstacles(ctx, walkableClimb, hf);
		rcFilterLedgeSpans(ctx, walkableHeight, walkableClimb, hf);
		rcFilterWalkableLowHeightSpans(ctx, walkableHeight, hf);

		// Create compact heightfield
		let chf = rcAllocCompactHeightfield();
		defer { rcFreeCompactHeightfield(chf); }

		if (rcBuildCompactHeightfield(ctx, walkableHeight, walkableClimb, hf, chf) == 0)
		{
			result.ErrorMessage = new String("Could not build compact heightfield");
			return result;
		}

		// Erode walkable area
		int32 walkableRadius = (int32)Math.Ceiling(config.AgentRadius / config.CellSize);
		if (rcErodeWalkableArea(ctx, walkableRadius, chf) == 0)
		{
			result.ErrorMessage = new String("Could not erode walkable area");
			return result;
		}

		// Build distance field and regions
		if (rcBuildDistanceField(ctx, chf) == 0)
		{
			result.ErrorMessage = new String("Could not build distance field");
			return result;
		}

		if (rcBuildRegions(ctx, chf, 0, config.RegionMinSize * config.RegionMinSize,
			config.RegionMergeSize * config.RegionMergeSize) == 0)
		{
			result.ErrorMessage = new String("Could not build regions");
			return result;
		}

		// Build contours
		let cset = rcAllocContourSet();
		defer { rcFreeContourSet(cset); }

		int32 maxEdgeLen = (int32)(config.EdgeMaxLen / config.CellSize);
		if (rcBuildContours(ctx, chf, config.EdgeMaxError, maxEdgeLen, cset, (.)rcBuildContoursFlags.RC_CONTOUR_TESS_WALL_EDGES) == 0)
		{
			result.ErrorMessage = new String("Could not build contours");
			return result;
		}

		// Build poly mesh
		let pmesh = rcAllocPolyMesh();
		defer { rcFreePolyMesh(pmesh); }

		if (rcBuildPolyMesh(ctx, cset, config.VertsPerPoly, pmesh) == 0)
		{
			result.ErrorMessage = new String("Could not build poly mesh");
			return result;
		}

		// Build detail mesh
		let dmesh = rcAllocPolyMeshDetail();
		defer { rcFreePolyMeshDetail(dmesh); }

		if (rcBuildPolyMeshDetail(ctx, pmesh, chf, config.DetailSampleDist, config.DetailSampleMaxError, dmesh) == 0)
		{
			result.ErrorMessage = new String("Could not build detail mesh");
			return result;
		}

		// Get poly mesh data
		int32 nverts = rcPolyMeshGetNVerts(pmesh);
		int32 npolys = rcPolyMeshGetNPolys(pmesh);
		int32 nvp = rcPolyMeshGetNvp(pmesh);

		if (npolys == 0)
		{
			result.ErrorMessage = new String("No polygons generated");
			return result;
		}

		// Build navmesh create params
		dtNavMeshCreateParams navParams = .();
		navParams.verts = rcPolyMeshGetVerts(pmesh);
		navParams.vertCount = nverts;
		navParams.polys = rcPolyMeshGetPolys(pmesh);
		navParams.polyFlags = rcPolyMeshGetFlags(pmesh);
		navParams.polyAreas = rcPolyMeshGetAreas(pmesh);
		navParams.polyCount = npolys;
		navParams.nvp = nvp;

		navParams.detailMeshes = rcPolyMeshDetailGetMeshes(dmesh);
		navParams.detailVerts = rcPolyMeshDetailGetVerts(dmesh);
		navParams.detailVertsCount = rcPolyMeshDetailGetNVerts(dmesh);
		navParams.detailTris = rcPolyMeshDetailGetTris(dmesh);
		navParams.detailTriCount = rcPolyMeshDetailGetNTris(dmesh);

		rcPolyMeshGetBMin(pmesh, &navParams.bmin[0]);
		rcPolyMeshGetBMax(pmesh, &navParams.bmax[0]);

		navParams.walkableHeight = config.AgentHeight;
		navParams.walkableRadius = config.AgentRadius;
		navParams.walkableClimb = config.AgentMaxClimb;
		navParams.cs = config.CellSize;
		navParams.ch = config.CellHeight;
		navParams.buildBvTree = 1;

		// Set all poly flags to 1 (walkable)
		for (int32 i = 0; i < npolys; i++)
			navParams.polyFlags[i] = 1;

		// Create navmesh data
		uint8* navData = null;
		int32 navDataSize = 0;
		if (dtCreateNavMeshData(&navParams, &navData, &navDataSize) == 0)
		{
			result.ErrorMessage = new String("Could not create navmesh data");
			return result;
		}

		// Create navmesh
		let navMesh = new NavMesh();
		let initStatus = navMesh.InitSingle(navData, navDataSize, (.)dtTileFlags.DT_TILE_FREE_DATA);
		if (initStatus != .Success)
		{
			dtFree(navData);
			delete navMesh;
			result.ErrorMessage = new String("Could not initialize navmesh");
			return result;
		}

		result.Success = true;
		result.NavMesh = navMesh;
		result.Stats = .() {
			VertexCount = nverts,
			PolyCount = npolys,
			TileCount = 1
		};

		return result;
	}
}

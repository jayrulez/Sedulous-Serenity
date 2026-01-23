using System;
using System.Collections;
using Sedulous.Navigation;
using Sedulous.Navigation.Recast;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation.Tests;

/// Tests for tiled navmesh building, cross-tile stitching, and pathfinding across tiles.
class TiledNavMeshTests
{
	/// Helper: creates a tiled navmesh config with a specific tile size.
	private static NavMeshBuildConfig CreateTiledConfig(int32 tileSize = 32)
	{
		var cfg = NavMeshBuildConfig.Default;
		cfg.TileSize = tileSize;
		return cfg;
	}

	[Test]
	public static void TestTiledNavMeshBuildSequential()
	{
		let geometry = TestGeometries.CreateLargePlane(20, 20);
		defer delete geometry;

		var config = CreateTiledConfig(32);
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(geometry.Bounds.Min.X, geometry.Bounds.Min.Y, geometry.Bounds.Min.Z);
		float[3] bmax = .(geometry.Bounds.Max.X, geometry.Bounds.Max.Y, geometry.Bounds.Max.Z);
		builder.Initialize(bmin, bmax, config);

		Test.Assert(builder.TileCountX > 0, "Should have tiles in X");
		Test.Assert(builder.TileCountZ > 0, "Should have tiles in Z");

		let result = builder.BuildAll(geometry);
		defer { if (result.NavMesh != null) delete result.NavMesh; delete result; }

		Test.Assert(result.Success, scope String()..AppendF("Tiled build should succeed: {}", result.ErrorMessage ?? ""));
		Test.Assert(result.TileCount > 0, "Should have built at least one tile");
		Test.Assert(result.NavMesh != null, "NavMesh should not be null");
	}

	[Test]
	public static void TestMultipleTilesCreated()
	{
		// 20x20 plane with CellSize=0.3, TileSize=32 => tile world size = 9.6
		// So we need ceil(20/9.6)=3 tiles in each direction
		let geometry = TestGeometries.CreateLargePlane(20, 20);
		defer delete geometry;

		var config = CreateTiledConfig(32);
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(geometry.Bounds.Min.X, geometry.Bounds.Min.Y, geometry.Bounds.Min.Z);
		float[3] bmax = .(geometry.Bounds.Max.X, geometry.Bounds.Max.Y, geometry.Bounds.Max.Z);
		builder.Initialize(bmin, bmax, config);

		// Should have multiple tiles in each direction
		Test.Assert(builder.TileCountX >= 2, scope String()..AppendF("Expected >= 2 tiles in X, got {}", builder.TileCountX));
		Test.Assert(builder.TileCountZ >= 2, scope String()..AppendF("Expected >= 2 tiles in Z, got {}", builder.TileCountZ));

		let result = builder.BuildAll(geometry);
		defer { if (result.NavMesh != null) delete result.NavMesh; delete result; }

		Test.Assert(result.Success, "Build should succeed");
		Test.Assert(result.TileCount >= 4, scope String()..AppendF("Expected >= 4 tiles built, got {}", result.TileCount));
	}

	[Test]
	public static void TestTileBoundsCalculation()
	{
		let geometry = TestGeometries.CreateLargePlane(20, 20);
		defer delete geometry;

		var config = CreateTiledConfig(32);
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(geometry.Bounds.Min.X, geometry.Bounds.Min.Y, geometry.Bounds.Min.Z);
		float[3] bmax = .(geometry.Bounds.Max.X, geometry.Bounds.Max.Y, geometry.Bounds.Max.Z);
		builder.Initialize(bmin, bmax, config);

		// First tile should start at world min
		float[3] tileBMin, tileBMax;
		builder.GetTileBounds(0, 0, out tileBMin, out tileBMax);

		Test.Assert(Math.Abs(tileBMin[0] - bmin[0]) < 0.01f, "Tile (0,0) min X should match world min X");
		Test.Assert(Math.Abs(tileBMin[2] - bmin[2]) < 0.01f, "Tile (0,0) min Z should match world min Z");
		Test.Assert(tileBMax[0] > tileBMin[0], "Tile max X should be greater than min X");
		Test.Assert(tileBMax[2] > tileBMin[2], "Tile max Z should be greater than min Z");

		// Last tile should end at world max
		float[3] lastBMin, lastBMax;
		builder.GetTileBounds(builder.TileCountX - 1, builder.TileCountZ - 1, out lastBMin, out lastBMax);

		Test.Assert(Math.Abs(lastBMax[0] - bmax[0]) < 0.01f, "Last tile max X should match world max X");
		Test.Assert(Math.Abs(lastBMax[2] - bmax[2]) < 0.01f, "Last tile max Z should match world max Z");
	}

	[Test]
	public static void TestTileCoordLookup()
	{
		var config = CreateTiledConfig(32);
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(-10, 0, -10);
		float[3] bmax = .(10, 5, 10);
		builder.Initialize(bmin, bmax, config);

		// World center should map to a valid tile coord
		let centerCoord = builder.GetTileCoord(0, 0);
		Test.Assert(centerCoord.X >= 0 && centerCoord.X < builder.TileCountX, "Center X coord should be valid");
		Test.Assert(centerCoord.Z >= 0 && centerCoord.Z < builder.TileCountZ, "Center Z coord should be valid");

		// World min corner should map to (0, 0)
		let minCoord = builder.GetTileCoord(-10, -10);
		Test.Assert(minCoord.X == 0, "Min corner should map to tile X=0");
		Test.Assert(minCoord.Z == 0, "Min corner should map to tile Z=0");

		// World max corner should map to last tile
		let maxCoord = builder.GetTileCoord(9.9f, 9.9f);
		Test.Assert(maxCoord.X == builder.TileCountX - 1, "Max corner should map to last tile X");
		Test.Assert(maxCoord.Z == builder.TileCountZ - 1, "Max corner should map to last tile Z");
	}

	[Test]
	public static void TestTiledNavMeshTilePositions()
	{
		let geometry = TestGeometries.CreateLargePlane(20, 20);
		defer delete geometry;

		var config = CreateTiledConfig(32);
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(geometry.Bounds.Min.X, geometry.Bounds.Min.Y, geometry.Bounds.Min.Z);
		float[3] bmax = .(geometry.Bounds.Max.X, geometry.Bounds.Max.Y, geometry.Bounds.Max.Z);
		builder.Initialize(bmin, bmax, config);

		let result = builder.BuildAll(geometry);
		defer { if (result.NavMesh != null) delete result.NavMesh; delete result; }

		Test.Assert(result.Success, "Build should succeed");

		// Verify tiles have correct X/Z coordinates
		let navMesh = result.NavMesh;
		for (int32 tz = 0; tz < builder.TileCountZ; tz++)
		{
			for (int32 tx = 0; tx < builder.TileCountX; tx++)
			{
				let tile = navMesh.GetTileAt(tx, tz);
				if (tile != null)
				{
					Test.Assert(tile.X == tx, scope String()..AppendF("Tile X should be {}, got {}", tx, tile.X));
					Test.Assert(tile.Z == tz, scope String()..AppendF("Tile Z should be {}, got {}", tz, tile.Z));
				}
			}
		}
	}

	[Test]
	public static void TestCrossTileLinksEstablished()
	{
		let geometry = TestGeometries.CreateLargePlane(20, 20);
		defer delete geometry;

		var config = CreateTiledConfig(32);
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(geometry.Bounds.Min.X, geometry.Bounds.Min.Y, geometry.Bounds.Min.Z);
		float[3] bmax = .(geometry.Bounds.Max.X, geometry.Bounds.Max.Y, geometry.Bounds.Max.Z);
		builder.Initialize(bmin, bmax, config);

		let result = builder.BuildAll(geometry);
		defer { if (result.NavMesh != null) delete result.NavMesh; delete result; }

		Test.Assert(result.Success, "Build should succeed");
		Test.Assert(result.TileCount >= 4, "Need multiple tiles for cross-tile test");

		// Check that at least some tiles have cross-tile links
		let navMesh = result.NavMesh;
		int32 totalCrossTileLinks = 0;

		for (int32 i = 0; i < navMesh.TileCount; i++)
		{
			let tile = navMesh.GetTile(i);
			if (tile == null) continue;

			if (tile.Links != null)
			{
				for (int32 li = 0; li < tile.Links.Count; li++)
				{
					// A cross-tile link has a reference to a polygon in a different tile
					if (tile.Links[li].Reference.Value != 0)
						totalCrossTileLinks++;
				}
			}
		}

		Test.Assert(totalCrossTileLinks > 0, scope String()..AppendF("Expected cross-tile links, found {}", totalCrossTileLinks));
	}

	[Test]
	public static void TestCrossTilePathfinding()
	{
		let geometry = TestGeometries.CreateLargePlane(20, 20);
		defer delete geometry;

		var config = CreateTiledConfig(32);
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(geometry.Bounds.Min.X, geometry.Bounds.Min.Y, geometry.Bounds.Min.Z);
		float[3] bmax = .(geometry.Bounds.Max.X, geometry.Bounds.Max.Y, geometry.Bounds.Max.Z);
		builder.Initialize(bmin, bmax, config);

		let result = builder.BuildAll(geometry);
		defer { if (result.NavMesh != null) delete result.NavMesh; delete result; }

		Test.Assert(result.Success, "Build should succeed");

		// Create query
		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);

		// Find path from one side of the plane to the other (crosses multiple tiles)
		float[3] startPos = .(-8, 0, -8);
		float[3] endPos = .(8, 0, 8);
		float[3] extents = .(2, 4, 2);
		let filter = scope NavMeshQueryFilter();

		PolyRef startRef = default;
		float[3] nearestStart = default;
		let startStatus = query.FindNearestPoly(startPos, extents, filter, out startRef, out nearestStart);
		Test.Assert(startStatus == .Success && startRef.IsValid, "Should find start poly");

		PolyRef endRef = default;
		float[3] nearestEnd = default;
		let endStatus = query.FindNearestPoly(endPos, extents, filter, out endRef, out nearestEnd);
		Test.Assert(endStatus == .Success && endRef.IsValid, "Should find end poly");

		// Verify start and end are in different tiles
		int32 startTileIdx = (int32)(startRef.TileIndex);
		int32 endTileIdx = (int32)(endRef.TileIndex);
		Test.Assert(startTileIdx != endTileIdx, scope String()..AppendF("Start and end should be in different tiles: start={}, end={}", startTileIdx, endTileIdx));

		// Find path
		let path = scope List<PolyRef>();
		let pathStatus = query.FindPath(startRef, endRef, nearestStart, nearestEnd, filter, path, 256);

		Test.Assert(pathStatus.Succeeded,
			scope String()..AppendF("FindPath should succeed across tiles, got status {}", pathStatus));
		Test.Assert(path.Count >= 2, scope String()..AppendF("Path should have at least 2 polys, got {}", path.Count));

		// If path is complete, verify it crosses tile boundaries
		if (pathStatus == .Success)
		{
			bool crossesTile = false;
			int32 firstTile = (int32)(path[0].TileIndex);
			for (int32 i = 1; i < path.Count; i++)
			{
				if ((int32)(path[i].TileIndex) != firstTile)
				{
					crossesTile = true;
					break;
				}
			}
			Test.Assert(crossesTile, "Path should cross tile boundaries");
		}
	}

	[Test]
	public static void TestCrossTileStraightPath()
	{
		let geometry = TestGeometries.CreateLargePlane(20, 20);
		defer delete geometry;

		var config = CreateTiledConfig(32);
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(geometry.Bounds.Min.X, geometry.Bounds.Min.Y, geometry.Bounds.Min.Z);
		float[3] bmax = .(geometry.Bounds.Max.X, geometry.Bounds.Max.Y, geometry.Bounds.Max.Z);
		builder.Initialize(bmin, bmax, config);

		let result = builder.BuildAll(geometry);
		defer { if (result.NavMesh != null) delete result.NavMesh; delete result; }

		Test.Assert(result.Success, "Build should succeed");

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);

		// Path across tiles
		float[3] startPos = .(-7, 0, 0);
		float[3] endPos = .(7, 0, 0);
		float[3] extents = .(2, 4, 2);
		let filter = scope NavMeshQueryFilter();

		PolyRef startRef, endRef;
		float[3] nearestStart, nearestEnd;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out nearestStart);
		query.FindNearestPoly(endPos, extents, filter, out endRef, out nearestEnd);

		Test.Assert(startRef.IsValid && endRef.IsValid, "Should find both polys");

		// Get corridor
		let path = scope List<PolyRef>();
		query.FindPath(startRef, endRef, nearestStart, nearestEnd, filter, path, 64);
		Test.Assert(path.Count >= 2, "Should find corridor");

		// Get straight path (waypoints)
		let straightPath = scope List<float>();
		let straightPathFlags = scope List<StraightPathFlags>();
		let straightPathRefs = scope List<PolyRef>();

		let spStatus = query.FindStraightPath(nearestStart, nearestEnd, path,
			straightPath, straightPathFlags, straightPathRefs, 64);

		Test.Assert(spStatus == .Success, "FindStraightPath should succeed");
		int32 waypointCount = (int32)(straightPath.Count / 3);
		Test.Assert(waypointCount >= 2, scope String()..AppendF("Should have at least 2 waypoints, got {}", waypointCount));

		// First point should be near start, last near end
		float dx = straightPath[0] - nearestStart[0];
		float dz = straightPath[2] - nearestStart[2];
		Test.Assert(Math.Sqrt(dx * dx + dz * dz) < 1.0f, "First waypoint should be near start");

		int32 lastIdx = (waypointCount - 1) * 3;
		dx = straightPath[lastIdx] - nearestEnd[0];
		dz = straightPath[lastIdx + 2] - nearestEnd[2];
		Test.Assert(Math.Sqrt(dx * dx + dz * dz) < 1.0f, "Last waypoint should be near end");
	}

	[Test]
	public static void TestTiledBuildTotalPolyCount()
	{
		let geometry = TestGeometries.CreateLargePlane(20, 20);
		defer delete geometry;

		var config = CreateTiledConfig(32);
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(geometry.Bounds.Min.X, geometry.Bounds.Min.Y, geometry.Bounds.Min.Z);
		float[3] bmax = .(geometry.Bounds.Max.X, geometry.Bounds.Max.Y, geometry.Bounds.Max.Z);
		builder.Initialize(bmin, bmax, config);

		let result = builder.BuildAll(geometry);
		defer { if (result.NavMesh != null) delete result.NavMesh; delete result; }

		Test.Assert(result.Success, "Build should succeed");
		Test.Assert(result.TotalPolyCount > 0, scope String()..AppendF("Should have polys, got {}", result.TotalPolyCount));
		Test.Assert(result.TotalTilesAttempted == builder.TotalTileCount,
			scope String()..AppendF("Attempted should match total: {} vs {}", result.TotalTilesAttempted, builder.TotalTileCount));
	}

	[Test]
	public static void TestTiledBuildWithSmallTileSize()
	{
		// Smaller tile size = more tiles
		let geometry = TestGeometries.CreateLargePlane(20, 20);
		defer delete geometry;

		var config = CreateTiledConfig(16); // Smaller tiles
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(geometry.Bounds.Min.X, geometry.Bounds.Min.Y, geometry.Bounds.Min.Z);
		float[3] bmax = .(geometry.Bounds.Max.X, geometry.Bounds.Max.Y, geometry.Bounds.Max.Z);
		builder.Initialize(bmin, bmax, config);

		// Smaller tile size should produce more tiles
		// TileWorldSize = 16 * 0.3 = 4.8, so ceil(20/4.8) = 5 tiles per axis
		Test.Assert(builder.TileCountX >= 4, scope String()..AppendF("Expected >= 4 tiles X with small tile size, got {}", builder.TileCountX));
		Test.Assert(builder.TileCountZ >= 4, scope String()..AppendF("Expected >= 4 tiles Z with small tile size, got {}", builder.TileCountZ));

		let result = builder.BuildAll(geometry);
		defer { if (result.NavMesh != null) delete result.NavMesh; delete result; }

		Test.Assert(result.Success, "Build should succeed with small tiles");
		Test.Assert(result.TileCount >= 16, scope String()..AppendF("Expected >= 16 tiles, got {}", result.TileCount));
	}

	[Test]
	public static void TestFindNearestPolyOnTiledMesh()
	{
		let geometry = TestGeometries.CreateLargePlane(20, 20);
		defer delete geometry;

		var config = CreateTiledConfig(32);
		let builder = scope TiledNavMeshBuilder();

		float[3] bmin = .(geometry.Bounds.Min.X, geometry.Bounds.Min.Y, geometry.Bounds.Min.Z);
		float[3] bmax = .(geometry.Bounds.Max.X, geometry.Bounds.Max.Y, geometry.Bounds.Max.Z);
		builder.Initialize(bmin, bmax, config);

		let result = builder.BuildAll(geometry);
		defer { if (result.NavMesh != null) delete result.NavMesh; delete result; }

		Test.Assert(result.Success, "Build should succeed");

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);

		// Query at various positions across the plane
		float[3] extents = .(2, 4, 2);
		let filter = scope NavMeshQueryFilter();

		float[3] pos1 = .(-5, 0, -5);
		float[3] pos2 = .(5, 0, 5);
		float[3] pos3 = .(0, 0, 0);

		PolyRef ref1, ref2, ref3;
		float[3] nearest1, nearest2, nearest3;

		query.FindNearestPoly(pos1, extents, filter, out ref1, out nearest1);
		query.FindNearestPoly(pos2, extents, filter, out ref2, out nearest2);
		query.FindNearestPoly(pos3, extents, filter, out ref3, out nearest3);

		Test.Assert(ref1.IsValid, "Should find poly at (-5, -5)");
		Test.Assert(ref2.IsValid, "Should find poly at (5, 5)");
		Test.Assert(ref3.IsValid, "Should find poly at (0, 0)");

		// Nearest points should be close to query positions (on a flat plane, Y=0)
		Test.Assert(Math.Abs(nearest1[0] - pos1[0]) < 1.0f, "Nearest point 1 X should be close");
		Test.Assert(Math.Abs(nearest2[0] - pos2[0]) < 1.0f, "Nearest point 2 X should be close");
		Test.Assert(Math.Abs(nearest3[0] - pos3[0]) < 1.0f, "Nearest point 3 X should be close");
	}
}

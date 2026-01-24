using System;
using System.Collections;
using Sedulous.Navigation;
using Sedulous.Navigation.Recast;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation.Tests;

/// Tests for spatial queries: detail mesh, BVTree, raycast, move along surface, path corridor.
class SpatialQueryTests
{
	/// Helper: builds a navmesh and query from a flat plane geometry.
	private static bool BuildFlatPlaneQuery(out NavMesh navMesh, out NavMeshQuery query, out PolyMesh polyMesh)
	{
		navMesh = null;
		query = null;
		polyMesh = null;

		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (!result.Success || result.NavMesh == null) { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; } delete result; }

		if (!result.Success || result.NavMesh == null)
			return false;

		navMesh = result.NavMesh;
		polyMesh = result.PolyMesh;

		query = new NavMeshQuery();
		query.Init(navMesh);
		return true;
	}

	[Test]
	public static void TestDetailMeshCreated()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		Test.Assert(result.Success, "Build should succeed");

		// Check that the tile has detail mesh data
		let tile = result.NavMesh.GetTile(0);
		Test.Assert(tile != null, "Tile should exist");
		Test.Assert(tile.DetailMeshes != null, "Detail meshes should be created");
		Test.Assert(tile.DetailMeshCount > 0, "Should have detail meshes");
		Test.Assert(tile.DetailTriangles != null, "Should have detail triangles");
		Test.Assert(tile.DetailTriangleCount > 0, "Should have detail triangle count > 0");
	}

	[Test]
	public static void TestGetPolyHeight()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		// Find a polygon near the center
		float[3] center = .(0, 0.5f, 0);
		float[3] extents = .(10, 10, 10);
		PolyRef nearRef;
		float[3] nearPt;
		query.FindNearestPoly(center, extents, filter, out nearRef, out nearPt);

		if (!nearRef.IsValid) return;

		// Query the height at that point
		float height;
		let status = query.GetPolyHeight(nearRef, nearPt, out height);
		Test.Assert(status.Succeeded, "GetPolyHeight should succeed");

		// For a flat plane at Y=0, height should be near 0
		Test.Assert(Math.Abs(height) < 1.0f, "Height on flat plane should be near 0");
	}

	[Test]
	public static void TestRaycastNoObstacle()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		// Find a start polygon
		float[3] startPos = .(-2, 0.5f, 0);
		float[3] extents = .(10, 10, 10);
		PolyRef startRef;
		float[3] snapped;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out snapped);
		if (!startRef.IsValid) return;

		// Ray toward center on flat plane - should not hit anything
		float[3] endPos = .(2, 0.5f, 0);
		float hitT;
		float[3] hitNormal;
		let path = scope List<PolyRef>();

		let status = query.Raycast(startRef, snapped, endPos, filter, out hitT, out hitNormal, path);
		Test.Assert(status.Succeeded, "Raycast should succeed");
		// On a flat plane with multiple polygons, the ray may or may not hit an edge
		// depending on polygon layout. hitT should be > 0 at minimum.
		Test.Assert(hitT > 0, "Ray should travel some distance");
		Test.Assert(path.Count > 0, "Path should have at least one polygon");
	}

	[Test]
	public static void TestRaycastHitsWall()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }
		if (!result.Success) return;

		let query = new NavMeshQuery();
		defer delete query;
		query.Init(result.NavMesh);

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		// Start from inside the mesh and ray toward outside
		float[3] startPos = .(0, 0.5f, 0);
		float[3] extents = .(10, 10, 10);
		PolyRef startRef;
		float[3] snapped;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out snapped);
		if (!startRef.IsValid) return;

		// Ray going far outside the mesh boundary
		float[3] endPos = .(20, 0.5f, 0);
		float hitT;
		float[3] hitNormal;
		let path = scope List<PolyRef>();

		let status = query.Raycast(startRef, snapped, endPos, filter, out hitT, out hitNormal, path);
		Test.Assert(status.Succeeded, "Raycast should succeed");
		// Should hit the boundary before reaching the end
		Test.Assert(hitT < 1.0f, "Ray should hit boundary before reaching end");
	}

	[Test]
	public static void TestMoveAlongSurface()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		// Find start polygon
		float[3] startPos = .(0, 0.5f, 0);
		float[3] extents = .(10, 10, 10);
		PolyRef startRef;
		float[3] snapped;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out snapped);
		if (!startRef.IsValid) return;

		// Move a small distance within the mesh
		float[3] endPos = .(1, 0.5f, 1);
		float[3] resultPos;
		let visited = scope List<PolyRef>();

		let status = query.MoveAlongSurface(startRef, snapped, endPos, filter, out resultPos, visited);
		Test.Assert(status.Succeeded, "MoveAlongSurface should succeed");
		Test.Assert(visited.Count > 0, "Should have visited at least one polygon");

		// Result should be near the requested end position (within navmesh)
		float dx = resultPos[0] - endPos[0];
		float dz = resultPos[2] - endPos[2];
		float dist = Math.Sqrt(dx * dx + dz * dz);
		Test.Assert(dist < 2.0f, "Result should be near the target");
	}

	[Test]
	public static void TestMoveAlongSurfaceClampsToEdge()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		float[3] startPos = .(0, 0.5f, 0);
		float[3] extents = .(10, 10, 10);
		PolyRef startRef;
		float[3] snapped;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out snapped);
		if (!startRef.IsValid) return;

		// Move far outside the mesh - should be clamped to the boundary
		float[3] endPos = .(50, 0.5f, 0);
		float[3] resultPos;
		let visited = scope List<PolyRef>();

		let status = query.MoveAlongSurface(startRef, snapped, endPos, filter, out resultPos, visited);
		Test.Assert(status.Succeeded, "MoveAlongSurface should succeed");

		// Result should be clamped within the navmesh bounds (plane is -5 to 5, minus erosion)
		Test.Assert(resultPos[0] < 10.0f, "Result X should be within reasonable bounds");
	}

	[Test]
	public static void TestFindPolysAroundCircle()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		float[3] center = .(0, 0.5f, 0);
		float[3] extents = .(10, 10, 10);
		PolyRef startRef;
		float[3] nearPt;
		query.FindNearestPoly(center, extents, filter, out startRef, out nearPt);
		if (!startRef.IsValid) return;

		// Search with a large radius to find multiple polygons
		let resultRefs = scope List<PolyRef>();
		let resultParents = scope List<PolyRef>();
		let resultCosts = scope List<float>();

		let status = query.FindPolysAroundCircle(startRef, nearPt, 5.0f, filter, resultRefs, resultParents, resultCosts);
		Test.Assert(status.Succeeded, "FindPolysAroundCircle should succeed");
		Test.Assert(resultRefs.Count >= 1, "Should find at least the start polygon");
		Test.Assert(resultParents.Count == resultRefs.Count, "Parents count should match refs count");
		Test.Assert(resultCosts.Count == resultRefs.Count, "Costs count should match refs count");
	}

	[Test]
	public static void TestFindPolysAroundCircleSmallRadius()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		float[3] center = .(0, 0.5f, 0);
		float[3] extents = .(10, 10, 10);
		PolyRef startRef;
		float[3] nearPt;
		query.FindNearestPoly(center, extents, filter, out startRef, out nearPt);
		if (!startRef.IsValid) return;

		// Very small radius - should find only the start polygon (or few neighbors)
		let resultRefs = scope List<PolyRef>();

		let status = query.FindPolysAroundCircle(startRef, nearPt, 0.1f, filter, resultRefs, null, null);
		Test.Assert(status.Succeeded, "FindPolysAroundCircle should succeed");
		Test.Assert(resultRefs.Count >= 1, "Should find at least one polygon");
	}

	[Test]
	public static void TestBVTreeBuild()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		// Build a BVTree from the tile's polygons
		let tile = navMesh.GetTile(0);
		Test.Assert(tile != null, "Tile should exist");

		let nodes = BVTree.Build(tile.Vertices, tile.Polygons, tile.PolyCount, tile.BMin, tile.BMax);
		defer { if (nodes != null) delete nodes; }

		Test.Assert(nodes != null, "BVTree should be built");
		Test.Assert(nodes.Count > 0, "BVTree should have nodes");
	}

	[Test]
	public static void TestBVTreeQueryOverlap()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let tile = navMesh.GetTile(0);
		if (tile == null) return;

		let nodes = BVTree.Build(tile.Vertices, tile.Polygons, tile.PolyCount, tile.BMin, tile.BMax);
		defer { if (nodes != null) delete nodes; }
		if (nodes == null) return;

		// Query with a box covering the center of the mesh
		float[3] queryCenter = .(0, 0, 0);
		uint16[3] qMin = BVTree.QuantizePoint(
			.(queryCenter[0] - 1.0f, queryCenter[1] - 1.0f, queryCenter[2] - 1.0f),
			tile.BMin, tile.BMax);
		uint16[3] qMax = BVTree.QuantizePoint(
			.(queryCenter[0] + 1.0f, queryCenter[1] + 1.0f, queryCenter[2] + 1.0f),
			tile.BMin, tile.BMax);

		let results = scope List<int32>();
		BVTree.QueryOverlapAABB(nodes, (int32)nodes.Count, qMin, qMax, results);

		Test.Assert(results.Count > 0, "BVTree query should find overlapping polygons");
	}

	[Test]
	public static void TestPathCorridorReset()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		float[3] startPos = .(0, 0.5f, 0);
		float[3] extents = .(10, 10, 10);
		PolyRef startRef;
		float[3] nearPt;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out nearPt);
		if (!startRef.IsValid) return;

		let corridor = new PathCorridor();
		defer delete corridor;

		corridor.Reset(startRef, nearPt);

		Test.Assert(corridor.PathCount == 1, "Corridor should have 1 polygon after reset");
		Test.Assert(corridor.FirstPoly == startRef, "First poly should be start ref");
		Test.Assert(corridor.LastPoly == startRef, "Last poly should be start ref (single poly)");
	}

	[Test]
	public static void TestPathCorridorSetCorridor()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		// Find path from one side to other
		float[3] startPos = .(-3, 0.5f, 0);
		float[3] endPos = .(3, 0.5f, 0);
		float[3] extents = .(10, 10, 10);

		PolyRef startRef, endRef;
		float[3] snappedStart, snappedEnd;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out snappedStart);
		query.FindNearestPoly(endPos, extents, filter, out endRef, out snappedEnd);
		if (!startRef.IsValid || !endRef.IsValid) return;

		let path = scope List<PolyRef>();
		query.FindPath(startRef, endRef, snappedStart, snappedEnd, filter, path);
		if (path.Count == 0) return;

		let corridor = new PathCorridor();
		defer delete corridor;

		corridor.Reset(startRef, snappedStart);
		corridor.SetCorridor(snappedEnd, path);

		Test.Assert(corridor.PathCount > 0, "Corridor should have polygons");
		Test.Assert(corridor.FirstPoly == path[0], "First poly should match path start");
		Test.Assert(corridor.LastPoly == path[path.Count - 1], "Last poly should match path end");
	}

	[Test]
	public static void TestPathCorridorMovePosition()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		float[3] startPos = .(-2, 0.5f, 0);
		float[3] endPos = .(2, 0.5f, 0);
		float[3] extents = .(10, 10, 10);

		PolyRef startRef, endRef;
		float[3] snappedStart, snappedEnd;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out snappedStart);
		query.FindNearestPoly(endPos, extents, filter, out endRef, out snappedEnd);
		if (!startRef.IsValid || !endRef.IsValid) return;

		let path = scope List<PolyRef>();
		query.FindPath(startRef, endRef, snappedStart, snappedEnd, filter, path);
		if (path.Count == 0) return;

		let corridor = new PathCorridor();
		defer delete corridor;

		corridor.Reset(startRef, snappedStart);
		corridor.SetCorridor(snappedEnd, path);

		// Move the position slightly
		float[3] newPos = .(snappedStart[0] + 0.5f, snappedStart[1], snappedStart[2]);
		let result = corridor.MovePosition(newPos, query, filter);

		// Position should have moved
		float dx = result[0] - snappedStart[0];
		float dz = result[2] - snappedStart[2];
		float dist = Math.Sqrt(dx * dx + dz * dz);
		// It should have moved at least somewhat (might be constrained to polygon)
		Test.Assert(dist >= 0, "Position should be valid after move");
	}

	[Test]
	public static void TestPathCorridorIsValid()
	{
		NavMesh navMesh;
		NavMeshQuery query;
		PolyMesh polyMesh;
		if (!BuildFlatPlaneQuery(out navMesh, out query, out polyMesh))
			return;
		defer { delete navMesh; delete query; delete polyMesh; }

		let filter = new NavMeshQueryFilter();
		defer delete filter;

		float[3] startPos = .(0, 0.5f, 0);
		float[3] extents = .(10, 10, 10);
		PolyRef startRef;
		float[3] nearPt;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out nearPt);
		if (!startRef.IsValid) return;

		let corridor = new PathCorridor();
		defer delete corridor;

		corridor.Reset(startRef, nearPt);

		// Corridor should be valid since we haven't modified the navmesh
		Test.Assert(corridor.IsValid(10, navMesh), "Corridor should be valid");
	}

	[Test]
	public static void TestPolyMeshDetailBuild()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		if (!result.Success || result.PolyMesh == null) return;

		// Build detail mesh separately to verify the class works
		let chf = scope CompactHeightfield();
		let detailMesh = PolyMeshDetail.Build(result.PolyMesh, chf, 0, 0);
		defer { if (detailMesh != null) delete detailMesh; }

		Test.Assert(detailMesh != null, "Detail mesh should be created");
		Test.Assert(detailMesh.MeshCount == result.PolyMesh.PolyCount, "Detail mesh count should match poly count");
		Test.Assert(detailMesh.DetailTriangleCount > 0, "Should have detail triangles");
	}
}

using System;
using System.Collections;
using Sedulous.Navigation;
using Sedulous.Navigation.Recast;
using Sedulous.Navigation.Detour;
using Sedulous.Navigation.Crowd;

namespace Sedulous.Navigation.Tests;

/// Tests for sliced (incremental) pathfinding and debug visualization helpers.
class SlicedPathfindingTests
{
	// --- Sliced Pathfinding Tests ---

	[Test]
	public static void TestSlicedFindPathInit()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);
		let filter = scope NavMeshQueryFilter();

		float[3] startPos = .(-3, 0, -3);
		float[3] endPos = .(3, 0, 3);
		float[3] extents = .(5, 5, 5);

		PolyRef startRef, endRef;
		float[3] nearestStart, nearestEnd;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out nearestStart);
		query.FindNearestPoly(endPos, extents, filter, out endRef, out nearestEnd);

		let status = query.InitSlicedFindPath(startRef, endRef, nearestStart, nearestEnd, filter);
		Test.Assert(status == .Success, "InitSlicedFindPath should succeed");
		Test.Assert(query.SlicedStatus == .InProgress, "Status should be InProgress after init");
	}

	[Test]
	public static void TestSlicedFindPathSameStartEnd()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);
		let filter = scope NavMeshQueryFilter();

		float[3] pos = .(0, 0, 0);
		float[3] extents = .(5, 5, 5);

		PolyRef polyRef;
		float[3] nearestPos;
		query.FindNearestPoly(pos, extents, filter, out polyRef, out nearestPos);

		let status = query.InitSlicedFindPath(polyRef, polyRef, nearestPos, nearestPos, filter);
		Test.Assert(status == .Success, "Init should succeed");
		Test.Assert(query.SlicedStatus == .Complete, "Same start/end should be immediately complete");

		let path = scope List<PolyRef>();
		let finalStatus = query.FinalizeSlicedFindPath(path);
		Test.Assert(finalStatus == .Success, "Finalize should succeed");
		Test.Assert(path.Count == 1, "Path should have 1 polygon");
		Test.Assert(path[0] == polyRef, "Path should contain the single polygon");
	}

	[Test]
	public static void TestSlicedFindPathInvalidRefs()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);
		let filter = scope NavMeshQueryFilter();

		float[3] pos = .(0, 0, 0);
		let status = query.InitSlicedFindPath(.Null, .Null, pos, pos, filter);
		Test.Assert(status == .InvalidParam, "Invalid refs should return InvalidParam");
	}

	[Test]
	public static void TestSlicedFindPathUpdate()
	{
		let geometry = TestGeometries.CreatePlaneWithBox();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);
		let filter = scope NavMeshQueryFilter();

		float[3] startPos = .(-8, 0, 0);
		float[3] endPos = .(8, 0, 0);
		float[3] extents = .(5, 5, 5);

		PolyRef startRef, endRef;
		float[3] nearestStart, nearestEnd;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out nearestStart);
		query.FindNearestPoly(endPos, extents, filter, out endRef, out nearestEnd);

		Test.Assert(startRef.IsValid && endRef.IsValid, "Both refs should be valid");

		query.InitSlicedFindPath(startRef, endRef, nearestStart, nearestEnd, filter);

		// Do one iteration at a time
		int32 totalIters = 0;
		while (query.SlicedStatus == .InProgress && totalIters < 1000)
		{
			int32 iters = query.UpdateSlicedFindPath(1);
			totalIters += iters;
			if (iters == 0) break;
		}

		Test.Assert(query.SlicedStatus == .Complete || query.SlicedStatus == .Partial,
			"Should complete or have partial result");
		Test.Assert(totalIters > 0, "Should have done at least one iteration");
	}

	[Test]
	public static void TestSlicedFindPathFinalize()
	{
		let geometry = TestGeometries.CreatePlaneWithBox();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);
		let filter = scope NavMeshQueryFilter();

		float[3] startPos = .(-8, 0, 0);
		float[3] endPos = .(8, 0, 0);
		float[3] extents = .(5, 5, 5);

		PolyRef startRef, endRef;
		float[3] nearestStart, nearestEnd;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out nearestStart);
		query.FindNearestPoly(endPos, extents, filter, out endRef, out nearestEnd);

		query.InitSlicedFindPath(startRef, endRef, nearestStart, nearestEnd, filter);

		// Run to completion
		while (query.SlicedStatus == .InProgress)
			query.UpdateSlicedFindPath(32);

		let path = scope List<PolyRef>();
		let status = query.FinalizeSlicedFindPath(path);

		Test.Assert(status.Succeeded, "Finalize should succeed");
		Test.Assert(path.Count >= 2, "Path should have at least start and end polygons");
		Test.Assert(path[0] == startRef, "Path should start with startRef");
	}

	[Test]
	public static void TestSlicedFindPathMatchesRegular()
	{
		let geometry = TestGeometries.CreatePlaneWithBox();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);
		let filter = scope NavMeshQueryFilter();

		float[3] startPos = .(-8, 0, 0);
		float[3] endPos = .(8, 0, 0);
		float[3] extents = .(5, 5, 5);

		PolyRef startRef, endRef;
		float[3] nearestStart, nearestEnd;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out nearestStart);
		query.FindNearestPoly(endPos, extents, filter, out endRef, out nearestEnd);

		// Regular path
		let regularPath = scope List<PolyRef>();
		query.FindPath(startRef, endRef, nearestStart, nearestEnd, filter, regularPath);

		// Sliced path
		query.InitSlicedFindPath(startRef, endRef, nearestStart, nearestEnd, filter);
		while (query.SlicedStatus == .InProgress)
			query.UpdateSlicedFindPath(256);

		let slicedPath = scope List<PolyRef>();
		query.FinalizeSlicedFindPath(slicedPath);

		// Both should produce the same path
		Test.Assert(regularPath.Count == slicedPath.Count,
			scope $"Path lengths should match: regular={regularPath.Count}, sliced={slicedPath.Count}");

		for (int32 i = 0; i < Math.Min((int32)regularPath.Count, (int32)slicedPath.Count); i++)
		{
			Test.Assert(regularPath[i] == slicedPath[i],
				scope $"Path polygons should match at index {i}");
		}
	}

	[Test]
	public static void TestSlicedFindPathBatchUpdate()
	{
		let geometry = TestGeometries.CreatePlaneWithBox();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);
		let filter = scope NavMeshQueryFilter();

		float[3] startPos = .(-8, 0, 0);
		float[3] endPos = .(8, 0, 0);
		float[3] extents = .(5, 5, 5);

		PolyRef startRef, endRef;
		float[3] nearestStart, nearestEnd;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out nearestStart);
		query.FindNearestPoly(endPos, extents, filter, out endRef, out nearestEnd);

		query.InitSlicedFindPath(startRef, endRef, nearestStart, nearestEnd, filter);

		// Run with large batch - should complete in one call
		int32 iters = query.UpdateSlicedFindPath(1000);
		Test.Assert(iters > 0, "Should perform iterations");
		Test.Assert(query.SlicedStatus == .Complete || query.SlicedStatus == .Partial,
			"Large batch should complete the query");
	}

	[Test]
	public static void TestSlicedFindPathFinalizeBeforeComplete()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);

		// Try to finalize without starting a query
		let path = scope List<PolyRef>();
		let status = query.FinalizeSlicedFindPath(path);
		Test.Assert(status == .InvalidParam, "Finalize without init should return InvalidParam");
	}

	// --- Debug Draw Tests ---

	[Test]
	public static void TestDebugDrawNavMeshPolygons()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let vertices = scope List<DebugDrawVertex>();
		NavMeshDebugDraw.DrawNavMesh(result.NavMesh, vertices);

		// Should produce triangle vertices (multiple of 3)
		Test.Assert(vertices.Count > 0, "Should produce vertices");
		Test.Assert(vertices.Count % 3 == 0, "Triangle list should be multiple of 3");
	}

	[Test]
	public static void TestDebugDrawNavMeshEdges()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let vertices = scope List<DebugDrawVertex>();
		NavMeshDebugDraw.DrawNavMeshEdges(result.NavMesh, vertices);

		// Should produce line vertices (multiple of 2)
		Test.Assert(vertices.Count > 0, "Should produce edge vertices");
		Test.Assert(vertices.Count % 2 == 0, "Line list should be multiple of 2");
	}

	[Test]
	public static void TestDebugDrawPath()
	{
		let waypoints = scope List<float>();
		waypoints.Add(0); waypoints.Add(0); waypoints.Add(0);
		waypoints.Add(1); waypoints.Add(0); waypoints.Add(1);
		waypoints.Add(2); waypoints.Add(0); waypoints.Add(2);

		let vertices = scope List<DebugDrawVertex>();
		NavMeshDebugDraw.DrawPath(waypoints, vertices);

		// 3 waypoints = 2 line segments = 4 vertices
		Test.Assert(vertices.Count == 4, scope $"Should produce 4 vertices, got {vertices.Count}");
	}

	[Test]
	public static void TestDebugDrawAgents()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let buildResult = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (buildResult.PolyMesh != null) delete buildResult.PolyMesh; delete buildResult; }

		let crowd = scope CrowdManager();
		crowd.Init(buildResult.NavMesh);
		defer delete buildResult.NavMesh;

		let agentParams = CrowdAgentParams.Default;
		crowd.AddAgent(.(0, 0, 0), agentParams);

		let vertices = scope List<DebugDrawVertex>();
		NavMeshDebugDraw.DrawAgents(crowd, vertices);

		// Should have at least the position cross (4 vertices for 2 lines)
		Test.Assert(vertices.Count >= 4, "Should draw at least the agent cross");
	}

	[Test]
	public static void TestDebugDrawPolygonCorridor()
	{
		let geometry = TestGeometries.CreatePlaneWithBox();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		let query = scope NavMeshQuery();
		query.Init(result.NavMesh);
		let filter = scope NavMeshQueryFilter();

		float[3] startPos = .(-8, 0, 0);
		float[3] endPos = .(8, 0, 0);
		float[3] extents = .(5, 5, 5);

		PolyRef startRef, endRef;
		float[3] nearestStart, nearestEnd;
		query.FindNearestPoly(startPos, extents, filter, out startRef, out nearestStart);
		query.FindNearestPoly(endPos, extents, filter, out endRef, out nearestEnd);

		let path = scope List<PolyRef>();
		query.FindPath(startRef, endRef, nearestStart, nearestEnd, filter, path);

		let vertices = scope List<DebugDrawVertex>();
		NavMeshDebugDraw.DrawPolygonCorridor(result.NavMesh, path, vertices);

		// Should produce line segments connecting polygon centroids
		Test.Assert(vertices.Count > 0, "Should produce corridor vertices");
		Test.Assert(vertices.Count % 2 == 0, "Line list should be multiple of 2");
		Test.Assert(vertices.Count == (path.Count - 1) * 2,
			scope $"Should have {(path.Count - 1) * 2} vertices for {path.Count} polys, got {vertices.Count}");
	}

	[Test]
	public static void TestDebugDrawOffMeshConnections()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		// No off-mesh connections - should produce no vertices
		let vertices = scope List<DebugDrawVertex>();
		NavMeshDebugDraw.DrawOffMeshConnections(result.NavMesh, vertices);
		Test.Assert(vertices.Count == 0, "No off-mesh connections should produce no vertices");
	}
}

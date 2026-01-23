using System;
using System.Collections;
using Sedulous.Navigation;
using Sedulous.Navigation.Recast;
using Sedulous.Navigation.Detour;

namespace Sedulous.Navigation.Tests;

class NavMeshQueryTests
{
	[Test]
	public static void TestBuildAndQueryFlatPlane()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		Test.Assert(result.Success, "Build should succeed for flat plane");
		Test.Assert(result.NavMesh != null, "NavMesh should be created");
		Test.Assert(result.Stats.PolyCount > 0, "Should have polygons");
	}

	[Test]
	public static void TestFindNearestPoly()
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

		PolyRef nearestRef;
		float[3] nearestPoint;
		float[3] center = .(0, 0.5f, 0);
		float[3] extents = .(10, 10, 10);

		let status = query.FindNearestPoly(center, extents, filter, out nearestRef, out nearestPoint);
		Test.Assert(status.Succeeded, "FindNearestPoly should succeed");
		Test.Assert(nearestRef.IsValid, "Should find a valid polygon");
	}

	[Test]
	public static void TestFindPath()
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

		// Find start and end polygons
		float[3] startPos = .(-4, 0.5f, -4);
		float[3] endPos = .(4, 0.5f, 4);
		float[3] extents = .(10, 10, 10);

		PolyRef startRef, endRef;
		float[3] snappedStart, snappedEnd;

		query.FindNearestPoly(startPos, extents, filter, out startRef, out snappedStart);
		query.FindNearestPoly(endPos, extents, filter, out endRef, out snappedEnd);

		if (!startRef.IsValid || !endRef.IsValid) return;

		let path = scope List<PolyRef>();
		let status = query.FindPath(startRef, endRef, snappedStart, snappedEnd, filter, path);

		Test.Assert(status.Succeeded, "FindPath should succeed");
		Test.Assert(path.Count > 0, "Path should have at least one polygon");
	}

	[Test]
	public static void TestFindStraightPath()
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

		let straightPath = scope List<float>();
		let straightFlags = scope List<StraightPathFlags>();
		let straightRefs = scope List<PolyRef>();

		let status = query.FindStraightPath(snappedStart, snappedEnd, path, straightPath, straightFlags, straightRefs);

		Test.Assert(status.Succeeded, "FindStraightPath should succeed");
		Test.Assert(straightPath.Count >= 6, "Should have at least start and end (2 points * 3 coords)");
	}

	[Test]
	public static void TestBuildPlaneWithBox()
	{
		let geometry = TestGeometries.CreatePlaneWithBox();
		defer delete geometry;

		var config = NavMeshBuildConfig.Default;
		config.CellSize = 0.5f;
		config.CellHeight = 0.2f;

		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer { if (result.NavMesh != null) delete result.NavMesh; if (result.PolyMesh != null) delete result.PolyMesh; delete result; }

		// This should build successfully with polygons around the box
		if (!result.Success && result.ErrorMessage != null)
			Test.Assert(result.Success, result.ErrorMessage);
		else
			Test.Assert(result.Success, "Build with box should succeed");
	}
}

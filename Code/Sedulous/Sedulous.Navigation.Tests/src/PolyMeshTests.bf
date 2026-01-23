using System;
using Sedulous.Navigation.Recast;

namespace Sedulous.Navigation.Tests;

class PolyMeshTests
{
	[Test]
	public static void TestBuildFromContours()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let config = NavMeshBuildConfig.Default;
		let bounds = geometry.Bounds;
		float[3] bmin = .(bounds.Min.X, bounds.Min.Y, bounds.Min.Z);
		float[3] bmax = .(bounds.Max.X, bounds.Max.Y, bounds.Max.Z);

		int32 width = (int32)((bmax[0] - bmin[0]) / config.CellSize + 0.5f);
		int32 height = (int32)((bmax[2] - bmin[2]) / config.CellSize + 0.5f);

		let hf = new Heightfield(width, height, bmin, bmax, config.CellSize, config.CellHeight);
		defer delete hf;
		hf.RasterizeTriangles(geometry);
		hf.FilterWalkableLowHeightSpans(config.WalkableHeight);

		let chf = CompactHeightfield.Build(hf, config.WalkableHeight, config.WalkableClimb);
		defer delete chf;

		chf.ErodeWalkableArea(config.WalkableRadius);
		chf.BuildDistanceField();
		chf.BuildRegionsWatershed(config.MinRegionArea, config.MergeRegionArea);

		if (chf.MaxRegions <= 1) return; // Skip if no regions

		let contourSet = ContourSet.Build(chf, config.MaxSimplificationError, config.MaxEdgeLength);
		defer delete contourSet;

		if (contourSet.Contours.Count == 0) return;

		let polyMesh = PolyMesh.Build(contourSet, config.MaxVertsPerPoly);
		defer delete polyMesh;

		Test.Assert(polyMesh.VertexCount > 0, "PolyMesh should have vertices");
		Test.Assert(polyMesh.PolyCount > 0, "PolyMesh should have polygons");
		Test.Assert(polyMesh.MaxVertsPerPoly == config.MaxVertsPerPoly, "MaxVertsPerPoly should match config");

		// Verify polygon integrity
		for (int32 i = 0; i < polyMesh.PolyCount; i++)
		{
			int32 vertCount = polyMesh.GetPolyVertCount(i);
			Test.Assert(vertCount >= 3, "Each polygon should have at least 3 vertices");
			Test.Assert(vertCount <= polyMesh.MaxVertsPerPoly, "Polygon should not exceed max verts");
		}
	}
}

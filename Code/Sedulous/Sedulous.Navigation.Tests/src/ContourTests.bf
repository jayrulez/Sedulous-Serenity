using System;
using Sedulous.Navigation.Recast;

namespace Sedulous.Navigation.Tests;

class ContourTests
{
	[Test]
	public static void TestBuildContoursFromRegions()
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

		if (chf.MaxRegions <= 1)
		{
			// If no regions were built (geometry too small), skip
			return;
		}

		let contourSet = ContourSet.Build(chf, config.MaxSimplificationError, config.MaxEdgeLength);
		defer delete contourSet;

		Test.Assert(contourSet.Contours.Count > 0, "Should have at least one contour");

		for (let contour in contourSet.Contours)
		{
			Test.Assert(contour.Vertices.Count >= 3, "Contour should have at least 3 vertices");
			Test.Assert(contour.RegionId > 0, "Contour should have a valid region ID");
		}
	}
}

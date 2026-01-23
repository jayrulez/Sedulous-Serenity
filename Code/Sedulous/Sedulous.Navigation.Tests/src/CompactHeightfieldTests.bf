using System;
using Sedulous.Navigation.Recast;

namespace Sedulous.Navigation.Tests;

class CompactHeightfieldTests
{
	[Test]
	public static void TestBuildFromHeightfield()
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

		let chf = CompactHeightfield.Build(hf, config.WalkableHeight, config.WalkableClimb);
		defer delete chf;

		Test.Assert(chf.SpanCount > 0, "Compact heightfield should have spans");
		Test.Assert(chf.Width == width, "Width should match");
		Test.Assert(chf.Height == height, "Height should match");
	}

	[Test]
	public static void TestBuildRegionsWatershed()
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

		let chf = CompactHeightfield.Build(hf, config.WalkableHeight, config.WalkableClimb);
		defer delete chf;

		chf.ErodeWalkableArea(config.WalkableRadius);
		chf.BuildDistanceField();
		chf.BuildRegionsWatershed(config.MinRegionArea, config.MergeRegionArea);

		Test.Assert(chf.MaxRegions >= 1, "Should have at least one region");
	}

	[Test]
	public static void TestErodeWalkableArea()
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

		let chf = CompactHeightfield.Build(hf, config.WalkableHeight, config.WalkableClimb);
		defer delete chf;

		int32 walkableBefore = 0;
		for (int32 i = 0; i < chf.SpanCount; i++)
		{
			if (chf.Areas[i] != NavArea.Null)
				walkableBefore++;
		}

		chf.ErodeWalkableArea(2);

		int32 walkableAfter = 0;
		for (int32 i = 0; i < chf.SpanCount; i++)
		{
			if (chf.Areas[i] != NavArea.Null)
				walkableAfter++;
		}

		// Erosion should reduce walkable area
		Test.Assert(walkableAfter <= walkableBefore, "Erosion should reduce or maintain walkable area");
	}
}

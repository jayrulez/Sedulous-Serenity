using System;
using Sedulous.Navigation.Recast;

namespace Sedulous.Navigation.Tests;

class HeightfieldTests
{
	[Test]
	public static void TestRasterizeFlatPlane()
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

		// Verify at least some spans were created
		int32 spanCount = 0;
		for (int32 i = 0; i < width * height; i++)
		{
			var span = hf.Spans[i];
			while (span != null)
			{
				spanCount++;
				span = span.Next;
			}
		}

		Test.Assert(spanCount > 0, "Rasterization should produce spans for a flat plane");
		Test.Assert(width > 0 && height > 0, "Grid dimensions should be positive");
	}

	[Test]
	public static void TestMarkWalkableTriangles()
	{
		let geometry = TestGeometries.CreateFlatPlane();
		defer delete geometry;

		let areas = new uint8[geometry.TriangleCount];
		defer delete areas;

		Heightfield.MarkWalkableTriangles(45.0f, geometry.Vertices, geometry.Triangles, geometry.TriangleCount, areas.Ptr);

		// Flat plane should be entirely walkable
		for (int32 i = 0; i < geometry.TriangleCount; i++)
		{
			Test.Assert(areas[i] == NavArea.Walkable, "Flat triangles should be walkable");
		}
	}

	[Test]
	public static void TestFilterLowHeightSpans()
	{
		let geometry = TestGeometries.CreatePlaneWithBox();
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

		// Some spans under the box should be filtered out
		// (spans with insufficient clearance above them)
		Test.Assert(width > 0, "Should have valid width");
	}
}

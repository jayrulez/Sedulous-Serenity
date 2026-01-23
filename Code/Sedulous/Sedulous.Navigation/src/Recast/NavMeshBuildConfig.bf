using System;

namespace Sedulous.Navigation.Recast;

/// Specifies how regions are built during navmesh generation.
enum RegionBuildStrategy : int32
{
	/// Distance-field based watershed. Best quality, moderate speed.
	Watershed = 0,
	/// Row-based monotone partitioning. Fast but more polygons.
	Monotone = 1,
	/// Layer-based partitioning. Good for tiled builds.
	Layer = 2
}

/// Configuration parameters for navmesh building.
[CRepr]
struct NavMeshBuildConfig
{
	/// Voxel cell size in the xz plane (world units).
	public float CellSize;
	/// Voxel cell height (world units).
	public float CellHeight;
	/// Maximum walkable slope angle in degrees.
	public float WalkableSlopeAngle;
	/// Minimum floor-to-ceiling clearance in voxels.
	public int32 WalkableHeight;
	/// Maximum ledge height that can be climbed in voxels.
	public int32 WalkableClimb;
	/// Agent radius for erosion in voxels.
	public int32 WalkableRadius;
	/// Maximum contour edge length in voxels.
	public int32 MaxEdgeLength;
	/// Maximum distance error for contour simplification.
	public float MaxSimplificationError;
	/// Minimum region area in voxels squared.
	public int32 MinRegionArea;
	/// Threshold below which regions are merged into neighbors.
	public int32 MergeRegionArea;
	/// Maximum vertices per polygon (3-6).
	public int32 MaxVertsPerPoly;
	/// Detail mesh sample spacing (0 = no detail mesh).
	public float DetailSampleDist;
	/// Maximum detail mesh height error.
	public float DetailSampleMaxError;
	/// Tile size in cells (0 = single non-tiled mesh).
	public int32 TileSize;
	/// Border size in cells for tile edge padding.
	public int32 BorderSize;
	/// Strategy for building regions.
	public RegionBuildStrategy RegionStrategy;

	/// World-space width of the build area (set during building).
	public float Width;
	/// World-space height/depth of the build area (set during building).
	public float Height;
	/// World-space minimum bounds (set during building).
	public float[3] BMin;
	/// World-space maximum bounds (set during building).
	public float[3] BMax;

	/// Returns a default configuration suitable for a human-sized agent.
	public static NavMeshBuildConfig Default
	{
		get
		{
			NavMeshBuildConfig config = .();
			config.CellSize = 0.3f;
			config.CellHeight = 0.2f;
			config.WalkableSlopeAngle = 45.0f;
			config.WalkableHeight = 10; // 2.0m at 0.2 cell height
			config.WalkableClimb = 4;   // 0.8m
			config.WalkableRadius = 2;  // 0.6m at 0.3 cell size
			config.MaxEdgeLength = 40;  // 12m
			config.MaxSimplificationError = 1.3f;
			config.MinRegionArea = 64;  // 8x8 cells
			config.MergeRegionArea = 400; // 20x20 cells
			config.MaxVertsPerPoly = 6;
			config.DetailSampleDist = 6.0f;
			config.DetailSampleMaxError = 1.0f;
			config.TileSize = 0;
			config.BorderSize = 0;
			config.RegionStrategy = .Watershed;
			config.Width = 0;
			config.Height = 0;
			config.BMin = .(0, 0, 0);
			config.BMax = .(0, 0, 0);
			return config;
		}
	}

	/// Calculates the grid size based on the bounding box and cell size.
	public void CalcGridSize(float bminX, float bminZ, float bmaxX, float bmaxZ) mut
	{
		BMin[0] = bminX;
		BMin[2] = bminZ;
		BMax[0] = bmaxX;
		BMax[2] = bmaxZ;
		Width = (int32)((bmaxX - bminX) / CellSize + 0.5f);
		Height = (int32)((bmaxZ - bminZ) / CellSize + 0.5f);
	}
}

using System;
using System.Collections;
using Sedulous.Navigation.Detour;
using Sedulous.Jobs;

namespace Sedulous.Navigation.Recast;

/// Result of building a tiled navigation mesh.
class TiledNavMeshBuildResult
{
	/// Whether the build was successful (at least one tile was built).
	public bool Success;
	/// The resulting navigation mesh (caller takes ownership).
	public NavMesh NavMesh;
	/// Number of tiles successfully built.
	public int32 TileCount;
	/// Total number of tiles attempted.
	public int32 TotalTilesAttempted;
	/// Number of polygons across all tiles.
	public int32 TotalPolyCount;
	/// Error message if the build completely failed.
	public String ErrorMessage ~ delete _;

	public ~this()
	{
	}
}

/// Builds a tiled navigation mesh from input geometry.
/// Tiles are built independently and then stitched together via cross-tile links.
class TiledNavMeshBuilder
{
	private NavMeshBuildConfig mConfig;
	private int32 mTileCountX;
	private int32 mTileCountZ;
	private float mTileWorldSize;
	private float[3] mWorldBMin;
	private float[3] mWorldBMax;

	/// Number of tiles in the X direction.
	public int32 TileCountX => mTileCountX;
	/// Number of tiles in the Z direction.
	public int32 TileCountZ => mTileCountZ;
	/// Total number of tiles.
	public int32 TotalTileCount => mTileCountX * mTileCountZ;

	/// Initializes the tiled builder with world bounds and configuration.
	/// Config.TileSize must be > 0 (tile size in cells).
	public void Initialize(float[3] worldBMin, float[3] worldBMax, in NavMeshBuildConfig config)
	{
		mConfig = config;
		mWorldBMin = worldBMin;
		mWorldBMax = worldBMax;

		// Tile world size = TileSize cells * CellSize
		mTileWorldSize = (float)config.TileSize * config.CellSize;

		// Calculate tile grid dimensions
		float worldWidth = worldBMax[0] - worldBMin[0];
		float worldDepth = worldBMax[2] - worldBMin[2];

		mTileCountX = Math.Max(1, (int32)Math.Ceiling(worldWidth / mTileWorldSize));
		mTileCountZ = Math.Max(1, (int32)Math.Ceiling(worldDepth / mTileWorldSize));
	}

	/// Builds all tiles sequentially.
	/// Returns a TiledNavMeshBuildResult with the assembled NavMesh.
	public TiledNavMeshBuildResult BuildAll(IInputGeometryProvider geometry)
	{
		let result = new TiledNavMeshBuildResult();

		if (mTileWorldSize <= 0 || mTileCountX <= 0 || mTileCountZ <= 0)
		{
			result.ErrorMessage = new String("Builder not initialized or TileSize is 0.");
			return result;
		}

		// Create NavMesh
		let navMesh = new NavMesh();
		NavMeshParams navParams = .();
		navParams.Origin = mWorldBMin;
		navParams.TileWidth = mTileWorldSize;
		navParams.TileHeight = mTileWorldSize;
		navParams.MaxTiles = mTileCountX * mTileCountZ;
		navParams.MaxPolys = mConfig.MaxVertsPerPoly * 1024; // Generous poly limit

		if (navMesh.Init(navParams) != .Success)
		{
			delete navMesh;
			result.ErrorMessage = new String("Failed to initialize NavMesh.");
			return result;
		}

		result.TotalTilesAttempted = mTileCountX * mTileCountZ;

		// Build each tile
		for (int32 tz = 0; tz < mTileCountZ; tz++)
		{
			for (int32 tx = 0; tx < mTileCountX; tx++)
			{
				float[3] tileBMin, tileBMax;
				GetTileBounds(tx, tz, out tileBMin, out tileBMax);

				var tileCfg = mConfig;
				tileCfg.BorderSize = (int32)Math.Ceiling((float)mConfig.WalkableRadius / mConfig.CellSize) + 3;

				let tile = NavMeshBuilder.BuildTile(geometry, tileCfg, tileBMin, tileBMax, tx, tz);
				if (tile != null)
				{
					PolyRef baseRef;
					navMesh.AddTile(tile, out baseRef);
					result.TileCount++;
					result.TotalPolyCount += tile.PolyCount;
				}
			}
		}

		if (result.TileCount == 0)
		{
			delete navMesh;
			result.ErrorMessage = new String("No tiles were successfully built.");
			return result;
		}

		// Connect adjacent tiles
		navMesh.ConnectAllTiles();

		result.NavMesh = navMesh;
		result.Success = true;
		return result;
	}

	/// Builds all tiles in parallel using the provided job system.
	/// Returns a TiledNavMeshBuildResult with the assembled NavMesh.
	public TiledNavMeshBuildResult BuildAllParallel(IInputGeometryProvider geometry, JobSystem jobSystem)
	{
		let result = new TiledNavMeshBuildResult();

		if (mTileWorldSize <= 0 || mTileCountX <= 0 || mTileCountZ <= 0)
		{
			result.ErrorMessage = new String("Builder not initialized or TileSize is 0.");
			return result;
		}

		int32 totalTiles = mTileCountX * mTileCountZ;
		result.TotalTilesAttempted = totalTiles;

		// Build tiles in parallel
		let tiles = new NavMeshTile[totalTiles];
		defer delete tiles;

		let jobs = new JobBase[totalTiles];
		defer delete jobs;

		for (int32 tz = 0; tz < mTileCountZ; tz++)
		{
			for (int32 tx = 0; tx < mTileCountX; tx++)
			{
				int32 tileIdx = tx + tz * mTileCountX;
				int32 capturedTx = tx;
				int32 capturedTz = tz;
				int32 capturedIdx = tileIdx;

				delegate void() jobDelegate = new () =>
				{
					float[3] tileBMin, tileBMax;
					GetTileBounds(capturedTx, capturedTz, out tileBMin, out tileBMax);

					var tileCfg = mConfig;
					tileCfg.BorderSize = (int32)Math.Ceiling((float)mConfig.WalkableRadius / mConfig.CellSize) + 3;

					tiles[capturedIdx] = NavMeshBuilder.BuildTile(geometry, tileCfg, tileBMin, tileBMax, capturedTx, capturedTz);
				};

				let job = new DelegateJob(jobDelegate, true, "BuildTile");
				jobs[tileIdx] = job;
				jobSystem.AddJob(job);
			}
		}

		// Dispatch jobs to workers and wait for completion
		jobSystem.Update();
		for (int32 i = 0; i < totalTiles; i++)
		{
			if (jobs[i] != null)
				jobs[i].Wait();
		}

		// Create NavMesh and add tiles
		let navMesh = new NavMesh();
		NavMeshParams navParams = .();
		navParams.Origin = mWorldBMin;
		navParams.TileWidth = mTileWorldSize;
		navParams.TileHeight = mTileWorldSize;
		navParams.MaxTiles = totalTiles;
		navParams.MaxPolys = mConfig.MaxVertsPerPoly * 1024;

		if (navMesh.Init(navParams) != .Success)
		{
			delete navMesh;
			result.ErrorMessage = new String("Failed to initialize NavMesh.");
			return result;
		}

		for (int32 i = 0; i < totalTiles; i++)
		{
			if (tiles[i] != null)
			{
				PolyRef baseRef;
				navMesh.AddTile(tiles[i], out baseRef);
				result.TileCount++;
				result.TotalPolyCount += tiles[i].PolyCount;
			}
		}

		if (result.TileCount == 0)
		{
			delete navMesh;
			result.ErrorMessage = new String("No tiles were successfully built.");
			return result;
		}

		navMesh.ConnectAllTiles();

		result.NavMesh = navMesh;
		result.Success = true;
		return result;
	}

	/// Gets the world-space bounds for a specific tile.
	public void GetTileBounds(int32 tx, int32 tz, out float[3] tileBMin, out float[3] tileBMax)
	{
		tileBMin[0] = mWorldBMin[0] + (float)tx * mTileWorldSize;
		tileBMin[1] = mWorldBMin[1];
		tileBMin[2] = mWorldBMin[2] + (float)tz * mTileWorldSize;

		tileBMax[0] = Math.Min(tileBMin[0] + mTileWorldSize, mWorldBMax[0]);
		tileBMax[1] = mWorldBMax[1];
		tileBMax[2] = Math.Min(tileBMin[2] + mTileWorldSize, mWorldBMax[2]);
	}

	/// Gets the tile coordinates for a world position.
	public TileCoord GetTileCoord(float x, float z)
	{
		int32 tx = (int32)((x - mWorldBMin[0]) / mTileWorldSize);
		int32 tz = (int32)((z - mWorldBMin[2]) / mTileWorldSize);
		tx = Math.Clamp(tx, 0, mTileCountX - 1);
		tz = Math.Clamp(tz, 0, mTileCountZ - 1);
		return TileCoord(tx, tz);
	}
}

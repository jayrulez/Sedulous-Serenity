using System;
using System.Collections;
using Sedulous.Navigation.Detour;
using Sedulous.Navigation.Recast;

namespace Sedulous.Navigation.Dynamic;

/// Manages dynamic obstacles and incrementally rebuilds affected navmesh tiles.
/// Obstacles are added/removed asynchronously and processed during Update().
class TileCache
{
	private NavMesh mNavMesh;
	private IInputGeometryProvider mGeometry;
	private NavMeshBuildConfig mConfig;
	private TiledNavMeshBuilder mBuilder;

	private List<TileCacheObstacle> mObstacles = new .() ~ DeleteContainerAndItems!(_);
	private HashSet<int64> mDirtyTiles = new .() ~ delete _;
	private int32 mNextObstacleId = 1;

	/// The underlying NavMesh being managed.
	public NavMesh NavMesh => mNavMesh;
	/// Number of active obstacles.
	public int32 ObstacleCount => (int32)mObstacles.Count;
	/// Number of tiles pending rebuild.
	public int32 DirtyTileCount => (int32)mDirtyTiles.Count;

	/// Initializes the tile cache with an existing tiled navmesh and the geometry used to build it.
	public NavStatus Init(NavMesh navMesh, IInputGeometryProvider geometry, in NavMeshBuildConfig config,
		float[3] worldBMin, float[3] worldBMax)
	{
		mNavMesh = navMesh;
		mGeometry = geometry;
		mConfig = config;

		mBuilder = new TiledNavMeshBuilder();
		mBuilder.Initialize(worldBMin, worldBMax, config);

		return .Success;
	}

	public ~this()
	{
		delete mBuilder;
	}

	/// Adds a cylindrical obstacle at the given position.
	/// The obstacle won't take effect until Update() is called.
	public NavStatus AddObstacle(float[3] position, float radius, float height, out int32 obstacleId)
	{
		obstacleId = -1;

		let obstacle = new TileCacheObstacle();
		obstacle.Id = mNextObstacleId++;
		obstacle.Type = .Cylinder;
		obstacle.State = .Pending;
		obstacle.Position = position;
		obstacle.Radius = radius;
		obstacle.Height = height;

		mObstacles.Add(obstacle);
		obstacleId = obstacle.Id;

		// Mark overlapping tiles as dirty
		MarkDirtyTilesForObstacle(obstacle);

		return .Success;
	}

	/// Adds a box obstacle defined by min/max corners.
	/// The obstacle won't take effect until Update() is called.
	public NavStatus AddBoxObstacle(float[3] bmin, float[3] bmax, out int32 obstacleId)
	{
		obstacleId = -1;

		let obstacle = new TileCacheObstacle();
		obstacle.Id = mNextObstacleId++;
		obstacle.Type = .Box;
		obstacle.State = .Pending;
		obstacle.BMin = bmin;
		obstacle.BMax = bmax;

		mObstacles.Add(obstacle);
		obstacleId = obstacle.Id;

		MarkDirtyTilesForObstacle(obstacle);

		return .Success;
	}

	/// Marks an obstacle for removal. The tile won't be rebuilt until Update() is called.
	public NavStatus RemoveObstacle(int32 obstacleId)
	{
		for (let obstacle in mObstacles)
		{
			if (obstacle.Id == obstacleId)
			{
				if (obstacle.State == .Active)
				{
					obstacle.State = .Removing;
					MarkDirtyTilesForObstacle(obstacle);
				}
				else if (obstacle.State == .Pending)
				{
					// Not yet processed, just remove it
					MarkDirtyTilesForObstacle(obstacle);
					mObstacles.Remove(obstacle);
					delete obstacle;
				}
				return .Success;
			}
		}
		return .InvalidParam;
	}

	/// Processes pending obstacle changes by rebuilding dirty tiles.
	/// maxUpdates limits how many tiles are rebuilt per call (0 = rebuild all).
	public int32 Update(int32 maxUpdates = 0)
	{
		// Remove obstacles marked for removal
		for (int32 i = (int32)mObstacles.Count - 1; i >= 0; i--)
		{
			if (mObstacles[i].State == .Removing)
			{
				let obstacle = mObstacles[i];
				mObstacles.RemoveAt(i);
				delete obstacle;
			}
		}

		// Mark pending obstacles as active
		for (let obstacle in mObstacles)
		{
			if (obstacle.State == .Pending)
				obstacle.State = .Active;
		}

		// Rebuild dirty tiles
		int32 rebuiltCount = 0;
		let tilesToRebuild = scope List<int64>();
		tilesToRebuild.AddRange(mDirtyTiles);

		for (let tileKey in tilesToRebuild)
		{
			if (maxUpdates > 0 && rebuiltCount >= maxUpdates)
				break;

			int32 tx = (int32)(tileKey & 0xFFFFFFFF);
			int32 tz = (int32)(tileKey >> 32);

			RebuildTile(tx, tz);
			mDirtyTiles.Remove(tileKey);
			rebuiltCount++;
		}

		return rebuiltCount;
	}

	/// Gets an obstacle by its ID.
	public TileCacheObstacle GetObstacle(int32 obstacleId)
	{
		for (let obstacle in mObstacles)
		{
			if (obstacle.Id == obstacleId)
				return obstacle;
		}
		return null;
	}

	/// Rebuilds a single tile, applying all active obstacles as carving regions.
	private void RebuildTile(int32 tx, int32 tz)
	{
		float[3] tileBMin, tileBMax;
		mBuilder.GetTileBounds(tx, tz, out tileBMin, out tileBMax);

		var tileCfg = mConfig;
		tileCfg.BorderSize = (int32)Math.Ceiling((float)mConfig.WalkableRadius / mConfig.CellSize) + 3;

		// Remove existing tile
		let existingTile = mNavMesh.GetTileAt(tx, tz);
		if (existingTile != null)
			mNavMesh.RemoveTile(existingTile.TileIndex);

		// Build new tile
		let newTile = NavMeshBuilder.BuildTile(mGeometry, tileCfg, tileBMin, tileBMax, tx, tz);
		if (newTile != null)
		{
			// Apply obstacle carving by removing polygons that overlap obstacles
			CarveObstaclesFromTile(newTile);

			if (newTile.PolyCount > 0)
			{
				PolyRef baseRef;
				mNavMesh.AddTile(newTile, out baseRef);
			}
			else
			{
				delete newTile;
			}
		}

		// Reconnect adjacent tiles
		ReconnectTileNeighbors(tx, tz);
	}

	/// Carves obstacles from a tile by marking overlapping polygons as unwalkable.
	private void CarveObstaclesFromTile(NavMeshTile tile)
	{
		for (let obstacle in mObstacles)
		{
			if (obstacle.State != .Active) continue;

			float[3] obstBMin, obstBMax;
			obstacle.GetBounds(out obstBMin, out obstBMax);

			// Check if obstacle overlaps this tile
			if (obstBMax[0] < tile.BMin[0] || obstBMin[0] > tile.BMax[0]) continue;
			if (obstBMax[2] < tile.BMin[2] || obstBMin[2] > tile.BMax[2]) continue;

			// Remove polygons whose centroids are inside the obstacle
			for (int32 i = tile.PolyCount - 1; i >= 0; i--)
			{
				ref NavPoly poly = ref tile.Polygons[i];
				if (poly.Type != .Ground) continue;

				float[3] centroid = GetPolyCentroid(tile, poly);

				if (IsPointInsideObstacle(centroid, obstacle))
				{
					// Mark as null area (effectively removes it from pathfinding)
					poly.Area = NavArea.Null;
					poly.Flags = 0;
				}
			}
		}
	}

	/// Gets the centroid of a polygon.
	private float[3] GetPolyCentroid(NavMeshTile tile, in NavPoly poly)
	{
		float[3] centroid = default;
		for (int32 j = 0; j < poly.VertexCount; j++)
		{
			int32 vi = (int32)poly.VertexIndices[j] * 3;
			centroid[0] += tile.Vertices[vi];
			centroid[1] += tile.Vertices[vi + 1];
			centroid[2] += tile.Vertices[vi + 2];
		}
		float invCount = 1.0f / (float)poly.VertexCount;
		centroid[0] *= invCount;
		centroid[1] *= invCount;
		centroid[2] *= invCount;
		return centroid;
	}

	/// Checks if a point is inside an obstacle's bounds.
	private bool IsPointInsideObstacle(float[3] point, TileCacheObstacle obstacle)
	{
		switch (obstacle.Type)
		{
		case .Cylinder:
			float dx = point[0] - obstacle.Position[0];
			float dz = point[2] - obstacle.Position[2];
			float distSq = dx * dx + dz * dz;
			if (distSq > obstacle.Radius * obstacle.Radius) return false;
			if (point[1] < obstacle.Position[1] || point[1] > obstacle.Position[1] + obstacle.Height) return false;
			return true;
		case .Box:
			return point[0] >= obstacle.BMin[0] && point[0] <= obstacle.BMax[0] &&
				point[1] >= obstacle.BMin[1] && point[1] <= obstacle.BMax[1] &&
				point[2] >= obstacle.BMin[2] && point[2] <= obstacle.BMax[2];
		}
	}

	/// Marks all tiles overlapping the obstacle as dirty.
	private void MarkDirtyTilesForObstacle(TileCacheObstacle obstacle)
	{
		float[3] obstBMin, obstBMax;
		obstacle.GetBounds(out obstBMin, out obstBMax);

		// Find all tiles that overlap the obstacle bounds
		for (int32 tz = 0; tz < mBuilder.TileCountZ; tz++)
		{
			for (int32 tx = 0; tx < mBuilder.TileCountX; tx++)
			{
				float[3] tileBMin, tileBMax;
				mBuilder.GetTileBounds(tx, tz, out tileBMin, out tileBMax);

				// Check AABB overlap
				if (obstBMax[0] < tileBMin[0] || obstBMin[0] > tileBMax[0]) continue;
				if (obstBMax[2] < tileBMin[2] || obstBMin[2] > tileBMax[2]) continue;

				int64 key = (int64)tx | ((int64)tz << 32);
				mDirtyTiles.Add(key);
			}
		}
	}

	/// Reconnects a rebuilt tile with its neighbors.
	private void ReconnectTileNeighbors(int32 tx, int32 tz)
	{
		let tile = mNavMesh.GetTileAt(tx, tz);
		if (tile == null) return;

		// Connect with right neighbor
		let right = mNavMesh.GetTileAt(tx + 1, tz);
		if (right != null)
			mNavMesh.ConnectTilesOnSide(tile, right, 0);

		// Connect with left neighbor
		let left = mNavMesh.GetTileAt(tx - 1, tz);
		if (left != null)
			mNavMesh.ConnectTilesOnSide(left, tile, 0);

		// Connect with forward neighbor
		let forward = mNavMesh.GetTileAt(tx, tz + 1);
		if (forward != null)
			mNavMesh.ConnectTilesOnSide(tile, forward, 1);

		// Connect with back neighbor
		let back = mNavMesh.GetTileAt(tx, tz - 1);
		if (back != null)
			mNavMesh.ConnectTilesOnSide(back, tile, 1);
	}
}

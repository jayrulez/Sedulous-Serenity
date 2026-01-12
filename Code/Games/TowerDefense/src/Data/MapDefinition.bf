namespace TowerDefense.Data;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Definition of a tower defense map.
/// Contains grid layout, enemy path waypoints, and game settings.
class MapDefinition
{
	/// Map display name.
	public String Name = new .() ~ delete _;

	/// Grid width in tiles.
	public int32 Width;

	/// Grid height in tiles.
	public int32 Height;

	/// Tile grid data (row-major: [y * Width + x]).
	public TileType[] Tiles ~ delete _;

	/// Enemy path waypoints in world coordinates.
	/// Enemies follow these points from first to last.
	public List<Vector3> Waypoints = new .() ~ delete _;

	/// Starting money for the player.
	public int32 StartingMoney = 200;

	/// Starting lives for the player.
	public int32 StartingLives = 20;

	/// Size of each tile in world units.
	public float TileSize = 2.0f;

	/// Gets the tile type at the given grid position.
	public TileType GetTile(int32 x, int32 y)
	{
		if (x < 0 || x >= Width || y < 0 || y >= Height)
			return .Blocked;
		return Tiles[y * Width + x];
	}

	/// Sets the tile type at the given grid position.
	public void SetTile(int32 x, int32 y, TileType type)
	{
		if (x >= 0 && x < Width && y >= 0 && y < Height)
			Tiles[y * Width + x] = type;
	}

	/// Converts grid coordinates to world position (center of tile).
	public Vector3 GridToWorld(int32 gridX, int32 gridY)
	{
		// Grid origin is at world origin, tiles extend in +X and +Z
		float worldX = (gridX - Width / 2.0f + 0.5f) * TileSize;
		float worldZ = (gridY - Height / 2.0f + 0.5f) * TileSize;
		return .(worldX, 0, worldZ);
	}

	/// Converts world position to grid coordinates.
	/// Returns (-1, -1) if outside the grid.
	public (int32 x, int32 y) WorldToGrid(Vector3 worldPos)
	{
		float gridXf = (worldPos.X / TileSize) + Width / 2.0f;
		float gridYf = (worldPos.Z / TileSize) + Height / 2.0f;

		int32 gridX = (int32)Math.Floor(gridXf);
		int32 gridY = (int32)Math.Floor(gridYf);

		if (gridX < 0 || gridX >= Width || gridY < 0 || gridY >= Height)
			return (-1, -1);

		return (gridX, gridY);
	}

	/// Gets the spawn point (first waypoint).
	public Vector3 SpawnPoint => Waypoints.Count > 0 ? Waypoints[0] : .Zero;

	/// Gets the exit point (last waypoint).
	public Vector3 ExitPoint => Waypoints.Count > 0 ? Waypoints[Waypoints.Count - 1] : .Zero;

	/// Allocates the tile array for the given dimensions.
	public void AllocateTiles(int32 width, int32 height)
	{
		Width = width;
		Height = height;
		if (Tiles != null)
			delete Tiles;
		Tiles = new TileType[width * height];

		// Default all tiles to grass
		for (int i = 0; i < Tiles.Count; i++)
			Tiles[i] = .Grass;
	}

	/// Sets a row of tiles from a string pattern.
	/// G=Grass, P=Path, W=Water, B=Blocked, S=Spawn, E=Exit
	public void SetRow(int32 y, StringView pattern)
	{
		for (int32 x = 0; x < Math.Min((int32)pattern.Length, Width); x++)
		{
			TileType type = .Grass;
			switch (pattern[x])
			{
			case 'G', '.': type = .Grass;
			case 'P', '#': type = .Path;
			case 'W', '~': type = .Water;
			case 'B', 'X': type = .Blocked;
			case 'S': type = .Spawn;
			case 'E': type = .Exit;
			}
			SetTile(x, y, type);
		}
	}
}

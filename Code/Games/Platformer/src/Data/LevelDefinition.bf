namespace Platformer.Data;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Platformer.Components;

/// Describes an enemy placement in a level.
struct EnemyPlacement
{
	public EnemyType Type;
	public int32 GridX;
	public int32 GridY;
	/// Left patrol boundary (grid X). -1 means auto-detect from platform edges.
	public int32 PatrolLeft;
	/// Right patrol boundary (grid X). -1 means auto-detect from platform edges.
	public int32 PatrolRight;

	public this(EnemyType type, int32 x, int32 y, int32 patrolLeft = -1, int32 patrolRight = -1)
	{
		Type = type;
		GridX = x;
		GridY = y;
		PatrolLeft = patrolLeft;
		PatrolRight = patrolRight;
	}
}

/// Describes a moving platform in a level.
struct MovingPlatformPlacement
{
	public int32 StartX, StartY;
	public int32 EndX, EndY;
	public float Speed;

	public this(int32 sx, int32 sy, int32 ex, int32 ey, float speed = 2.0f)
	{
		StartX = sx; StartY = sy;
		EndX = ex; EndY = ey;
		Speed = speed;
	}
}

/// Describes a moving hazard in a level.
struct HazardPlacement
{
	public HazardType Type;
	public int32 StartX, StartY;
	public int32 EndX, EndY;
	public float Speed;

	public this(HazardType type, int32 sx, int32 sy, int32 ex, int32 ey, float speed = 3.0f)
	{
		Type = type;
		StartX = sx; StartY = sy;
		EndX = ex; EndY = ey;
		Speed = speed;
	}
}

/// Definition of a platformer level.
/// Contains grid layout, enemy placements, and game settings.
class LevelDefinition
{
	/// Level display name.
	public String Name = new .() ~ delete _;

	/// Grid width in tiles.
	public int32 Width;

	/// Grid height in tiles.
	public int32 Height;

	/// Tile grid data (row-major: [y * Width + x]). Row 0 is bottom.
	public TileType[] Tiles ~ delete _;

	/// Player spawn position (grid coordinates).
	public int32 SpawnX;
	public int32 SpawnY;

	/// Goal flag position (grid coordinates).
	public int32 GoalX;
	public int32 GoalY;

	/// Enemy placements.
	public List<EnemyPlacement> Enemies = new .() ~ delete _;

	/// Moving platform placements.
	public List<MovingPlatformPlacement> MovingPlatforms = new .() ~ delete _;

	/// Moving hazard placements (saws, spiked balls).
	public List<HazardPlacement> MovingHazards = new .() ~ delete _;

	/// Tile size in world units.
	public float TileSize = 1.0f;

	/// Gets the tile type at the given grid position.
	public TileType GetTile(int32 x, int32 y)
	{
		if (x < 0 || x >= Width || y < 0 || y >= Height)
			return .Empty;
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
		float worldX = gridX * TileSize + TileSize * 0.5f;
		float worldY = gridY * TileSize + TileSize * 0.5f;
		return .(worldX, worldY, 0);
	}

	/// Converts world position to grid coordinates.
	public (int32 x, int32 y) WorldToGrid(Vector3 worldPos)
	{
		int32 gridX = (int32)Math.Floor(worldPos.X / TileSize);
		int32 gridY = (int32)Math.Floor(worldPos.Y / TileSize);
		return (gridX, gridY);
	}

	/// Allocates the tile array for the given dimensions.
	public void AllocateTiles(int32 width, int32 height)
	{
		Width = width;
		Height = height;
		if (Tiles != null)
			delete Tiles;
		Tiles = new TileType[width * height];

		for (int i = 0; i < Tiles.Count; i++)
			Tiles[i] = .Empty;
	}

	/// Sets a row of tiles from a string pattern.
	/// Row 0 is the bottom row.
	/// Characters: .=Empty, G=Grass, D=Dirt, B=Brick, C=Crate, S=Spike, ?=Question, !=Exclamation,
	/// P=PlayerSpawn, F=GoalFlag, $=Coin, *=Gem, H=Heart, K=Key, L=Door, ^=Bouncer, T=Tree, R=Rock
	/// E=Enemy (placed via Enemies list, acts as ground tile)
	public void SetRow(int32 y, StringView pattern)
	{
		for (int32 x = 0; x < Math.Min((int32)pattern.Length, Width); x++)
		{
			TileType type = .Empty;
			switch (pattern[x])
			{
			case '.': type = .Empty;
			case 'G': type = .Grass;
			case 'D': type = .Dirt;
			case 'B': type = .Brick;
			case 'C': type = .Crate;
			case 'S': type = .Spike;
			case '?': type = .Question;
			case '!': type = .Exclamation;
			case 'P':
				SpawnX = x;
				SpawnY = y;
				type = .Empty; // Player floats above ground
			case 'F':
				GoalX = x;
				GoalY = y;
				type = .Empty;
			case '$', '*', 'H', 'K', 'L', '^', 'T', 'R', '>', 'E', 'O', 'W':
				type = .Empty; // These are entity placements, not tiles
			}
			SetTile(x, y, type);
		}
	}

	/// Scans the grid pattern to find entity placements and populates coin/gem/etc positions.
	/// Call this after all SetRow calls.
	public void ScanEntityPlacements(StringView[] rows, List<(int32 x, int32 y, char8 type)> outPlacements)
	{
		for (int32 rowIdx = 0; rowIdx < rows.Count && rowIdx < Height; rowIdx++)
		{
			let pattern = rows[rowIdx];
			// rows[0] corresponds to the bottom row (y=0)
			int32 y = rowIdx;
			for (int32 x = 0; x < Math.Min((int32)pattern.Length, Width); x++)
			{
				let ch = pattern[x];
				switch (ch)
				{
				case '$', '*', 'H', 'K', 'L', '^', 'T', 'R', '>', 'O', 'W':
					outPlacements.Add((x, y, ch));
				default:
				}
			}
		}
	}
}

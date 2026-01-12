namespace TowerDefense.Data;

/// Types of tiles in the map grid.
enum TileType : uint8
{
	/// Grass tile - towers can be placed here.
	Grass,

	/// Path tile - enemies walk here, no towers allowed.
	Path,

	/// Water tile - blocked, no towers or enemies.
	Water,

	/// Blocked tile - obstacles, no towers or enemies.
	Blocked,

	/// Spawn point - where enemies enter the map.
	Spawn,

	/// Exit point - where enemies leave (player loses life).
	Exit
}

extension TileType
{
	/// Returns true if towers can be placed on this tile.
	public bool IsBuildable => this == .Grass;

	/// Returns true if enemies can walk on this tile.
	public bool IsWalkable => this == .Path || this == .Spawn || this == .Exit;

	/// Returns true if this tile blocks movement and building.
	public bool IsBlocked => this == .Water || this == .Blocked;
}

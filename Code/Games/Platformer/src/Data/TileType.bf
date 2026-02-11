namespace Platformer.Data;

enum TileType
{
	case Empty;
	case Grass;
	case Dirt;
	case Brick;
	case Crate;
	case Spike;
	case Question;
	case Exclamation;

	/// Whether this tile type is a solid platform the player can stand on.
	public bool IsSolid
	{
		get
		{
			switch (this)
			{
			case .Grass, .Dirt, .Brick, .Crate, .Question, .Exclamation:
				return true;
			default:
				return false;
			}
		}
	}

	/// Whether this tile type is a hazard that damages the player.
	public bool IsHazard
	{
		get
		{
			return this == .Spike;
		}
	}
}

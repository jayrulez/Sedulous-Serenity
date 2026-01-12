namespace TowerDefense.Data;

/// Types of targets a tower can attack.
enum TowerTargetType : uint8
{
	/// Can only attack ground enemies.
	Ground,

	/// Can only attack air enemies.
	Air,

	/// Can attack both ground and air enemies.
	Both
}

extension TowerTargetType
{
	/// Checks if this tower can target the given enemy type.
	public bool CanTarget(EnemyType enemyType)
	{
		switch (this)
		{
		case .Ground: return enemyType == .Ground;
		case .Air: return enemyType == .Air;
		case .Both: return true;
		}
	}
}

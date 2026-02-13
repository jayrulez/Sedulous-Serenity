namespace StormTactics.Battle;

static class BattleConstants
{
	/// Base time unit for action speed calculation.
	/// timeToAct = TIME_UNIT / actionSpeed
	public const int32 TIME_UNIT = 1000;

	/// Maximum number of turns before a battle is declared a draw.
	public const int32 MAX_TURNS = 100;

	/// Default grid columns.
	public const int32 DEFAULT_COLUMNS = 7;

	/// Default grid rows.
	public const int32 DEFAULT_ROWS = 6;

	/// Minimum grid columns (used when sizing the battle grid).
	public const int32 MIN_COLUMNS = 8;

	/// Minimum grid rows (used when sizing the battle grid).
	public const int32 MIN_ROWS = 4;

	/// Attacker deployment zone is 1/DEPLOY_DIVISOR of total columns.
	public const int32 DEPLOY_DIVISOR = 3;

	/// Deployment zone columns for the minimum grid size.
	public const int32 DEPLOY_COLUMNS = MIN_COLUMNS / DEPLOY_DIVISOR;

	/// Deployment zone rows for the minimum grid size.
	public const int32 DEPLOY_ROWS = MIN_ROWS;

	/// Maximum number of formation presets a player can have.
	public const int32 MAX_FORMATION_PRESETS = 4;

	/// Defense reduction formula cap (max 80% reduction).
	public const float MAX_DEFENSE_REDUCTION = 0.8f;

	/// Defense scaling factor. defenseReduction = defense / (defense + DEFENSE_SCALE).
	public const float DEFENSE_SCALE = 100.0f;

	/// Piercing damage ignores this fraction of physical defense.
	public const float PIERCING_ARMOR_IGNORE = 0.5f;

	/// Magic damage ignores physical defense entirely.
	public const float MAGIC_DEFENSE_IGNORE = 1.0f;
}

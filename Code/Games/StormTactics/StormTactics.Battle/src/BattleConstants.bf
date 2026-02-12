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

	/// Defense reduction formula cap (max 80% reduction).
	public const float MAX_DEFENSE_REDUCTION = 0.8f;

	/// Defense scaling factor. defenseReduction = defense / (defense + DEFENSE_SCALE).
	public const float DEFENSE_SCALE = 100.0f;

	/// Piercing damage ignores this fraction of physical defense.
	public const float PIERCING_ARMOR_IGNORE = 0.5f;

	/// Magic damage ignores physical defense entirely.
	public const float MAGIC_DEFENSE_IGNORE = 1.0f;
}

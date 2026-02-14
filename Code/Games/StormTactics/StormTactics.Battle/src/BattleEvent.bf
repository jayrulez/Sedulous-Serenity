namespace StormTactics.Battle;

using System;
using StormTactics.Core;

/// All events that can occur during a battle step.
/// Consumed by the client for animation/UI or by the server for validation.
enum BattleEventType
{
	BattleStarted,
	TurnStarted,
	UnitMoved,
	UnitAttacked,
	DamageDealt,
	HealApplied,
	UnitDied,
	BuffApplied,
	BuffRemoved,
	BuffTicked,
	SkillUsed,
	CounterAttack,
	UnitSummoned,
	BossPhase,
	BattleEnded
}

class BattleEvent
{
	public BattleEventType mType;
	public int32 mSourceUnit = -1;
	public int32 mTargetUnit = -1;
	public int32 mValue;            // Damage amount, heal amount, etc.
	public int32 mSkillId;
	public int32 mBuffId;
	public HexCoord mFromHex;
	public HexCoord mToHex;
	public Force mWinner;           // For BattleEnded
	public DamageType mDamageType;
	public bool mIsCritical;
}

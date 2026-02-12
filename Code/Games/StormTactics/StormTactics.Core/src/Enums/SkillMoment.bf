namespace StormTactics.Core;

/// When a skill triggers during battle.
enum SkillMoment : int32
{
	Passive = 0,
	OnBattleStart = 1,
	OnActionBegin = 2,
	OnAttack = 3,
	OnHit = 4,
	OnDamaged = 5,
	OnKill = 6,
	OnDeath = 7,
	OnTurnEnd = 8
}

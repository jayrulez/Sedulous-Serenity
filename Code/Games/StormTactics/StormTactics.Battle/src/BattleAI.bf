namespace StormTactics.Battle;

using System;
using System.Collections;
using StormTactics.Core;

/// Battle AI that decides actions for a unit on its turn.
/// Supports difficulty levels that control how smart the AI plays.
static class BattleAI
{
	/// Decide what action a unit should take.
	public static BattleAction DecideAction(BattleSimulation sim, int32 unitIdx, AIDifficulty difficulty = .Normal)
	{
		let unit = sim.GetUnit(unitIdx);
		if (unit == null || !unit.mAlive)
			return BattleAction.MakeWait(unitIdx);

		// Charmed units attack random allies instead
		let targetForce = unit.IsCharmed ?
			unit.mForce :
			(unit.mForce == .Attacker ? Force.Defender : Force.Attacker);

		switch (difficulty)
		{
		case .Easy:
			return DecideEasy(sim, unitIdx, unit, targetForce);
		case .Normal:
			return DecideNormal(sim, unitIdx, unit, targetForce);
		case .Hard:
			return DecideHard(sim, unitIdx, unit, targetForce);
		}
	}

	// =========================================================================
	// Easy: Random target selection, no skill usage, just attack or move
	// =========================================================================

	private static BattleAction DecideEasy(BattleSimulation sim, int32 unitIdx, BattleUnit unit, Force targetForce)
	{
		// Pick a random enemy in range to attack
		let attackTarget = FindRandomAttackTarget(sim, unit, targetForce);
		if (attackTarget >= 0)
			return BattleAction.MakeAttack(unitIdx, attackTarget);

		// Move toward nearest enemy
		let moveTarget = FindBestMoveTarget(sim, unit, targetForce);
		if (moveTarget.Q != unit.mPosition.Q || moveTarget.R != unit.mPosition.R)
			return BattleAction.MakeMove(unitIdx, moveTarget);

		return BattleAction.MakeWait(unitIdx);
	}

	// =========================================================================
	// Normal: Focus fire lowest HP, basic skill usage (attack skills only)
	// =========================================================================

	private static BattleAction DecideNormal(BattleSimulation sim, int32 unitIdx, BattleUnit unit, Force targetForce)
	{
		// Try attack (with focus fire on lowest HP)
		let attackTarget = FindBestAttackTarget(sim, unit, targetForce);
		if (attackTarget >= 0)
			return BattleAction.MakeAttack(unitIdx, attackTarget);

		// Move toward nearest enemy
		let moveTarget = FindBestMoveTarget(sim, unit, targetForce);
		if (moveTarget.Q != unit.mPosition.Q || moveTarget.R != unit.mPosition.R)
			return BattleAction.MakeMove(unitIdx, moveTarget);

		return BattleAction.MakeWait(unitIdx);
	}

	// =========================================================================
	// Hard: Full priority system — heal > buff > attack, optimal targeting
	// =========================================================================

	private static BattleAction DecideHard(BattleSimulation sim, int32 unitIdx, BattleUnit unit, Force targetForce)
	{
		let allyForce = unit.IsCharmed ?
			(unit.mForce == .Attacker ? Force.Defender : Force.Attacker) :
			unit.mForce;

		// Priority 1: Heal wounded allies (if we have heal skills)
		let healAction = TryHealAlly(sim, unitIdx, unit, allyForce);
		if (healAction.mType != .Wait)
			return healAction;

		// Priority 2: Apply buffs to allies (if we have buff skills, battle start or no enemies in range)
		let buffAction = TryBuffAlly(sim, unitIdx, unit, allyForce);
		if (buffAction.mType != .Wait)
			return buffAction;

		// Priority 3: Attack with focus fire
		let attackTarget = FindBestAttackTarget(sim, unit, targetForce);
		if (attackTarget >= 0)
			return BattleAction.MakeAttack(unitIdx, attackTarget);

		// Priority 4: Move toward nearest enemy
		let moveTarget = FindBestMoveTarget(sim, unit, targetForce);
		if (moveTarget.Q != unit.mPosition.Q || moveTarget.R != unit.mPosition.R)
			return BattleAction.MakeMove(unitIdx, moveTarget);

		return BattleAction.MakeWait(unitIdx);
	}

	// =========================================================================
	// Skill heuristics
	// =========================================================================

	/// Try to use a heal skill on a wounded ally.
	/// Returns a UseSkill action if a good heal target exists, or Wait if not.
	private static BattleAction TryHealAlly(BattleSimulation sim, int32 unitIdx, BattleUnit unit, Force allyForce)
	{
		if (unit.IsSilenced) return BattleAction.MakeWait(unitIdx);

		let configs = sim.Configs;

		for (let skillId in unit.mConfig.mSkillIds)
		{
			let skillConfig = configs.GetSkill(skillId);
			if (skillConfig == null) continue;
			if (unit.IsSkillOnCooldown(skillId)) continue;
			if (unit.IsSkillUsesExhausted(skillId, skillConfig)) continue;

			// Check if this skill has a heal effect
			bool hasHeal = false;
			for (let effect in skillConfig.mEffects)
			{
				if (effect.mType == .Heal) { hasHeal = true; break; }
			}
			if (!hasHeal) continue;

			// Find best heal target
			let targetIdx = FindHealTarget(sim, unit, allyForce, skillConfig.mTarget);
			if (targetIdx >= 0)
				return BattleAction.MakeSkill(unitIdx, skillId, targetIdx);
		}

		return BattleAction.MakeWait(unitIdx);
	}

	/// Try to use a buff skill on an ally.
	private static BattleAction TryBuffAlly(BattleSimulation sim, int32 unitIdx, BattleUnit unit, Force allyForce)
	{
		if (unit.IsSilenced) return BattleAction.MakeWait(unitIdx);

		let configs = sim.Configs;

		for (let skillId in unit.mConfig.mSkillIds)
		{
			let skillConfig = configs.GetSkill(skillId);
			if (skillConfig == null) continue;
			if (unit.IsSkillOnCooldown(skillId)) continue;
			if (unit.IsSkillUsesExhausted(skillId, skillConfig)) continue;

			// Check if this skill only applies buffs (no damage)
			bool hasBuff = false;
			bool hasDamage = false;
			for (let effect in skillConfig.mEffects)
			{
				if (effect.mType == .ApplyBuff) hasBuff = true;
				if (effect.mType == .Damage) hasDamage = true;
			}
			if (!hasBuff || hasDamage) continue;

			// Only apply buff skills targeting allies
			switch (skillConfig.mTarget)
			{
			case .Self:
				return BattleAction.MakeSkill(unitIdx, skillId, unitIdx);
			case .AllAllies, .SingleAlly:
				return BattleAction.MakeSkill(unitIdx, skillId, unitIdx);
			default:
				continue;
			}
		}

		return BattleAction.MakeWait(unitIdx);
	}

	/// Find the best ally to heal. Returns index or -1.
	/// Only heals if an ally is below 50% HP.
	private static int32 FindHealTarget(BattleSimulation sim, BattleUnit healer, Force allyForce, SkillTarget targetType)
	{
		int32 bestTarget = -1;
		float bestHPRatio = 0.5f; // Only heal allies below 50%

		for (int32 i = 0; i < sim.UnitCount; i++)
		{
			let target = sim.GetUnit(i);
			if (target == null || !target.mAlive) continue;
			if (target.mForce != allyForce) continue;

			let hpRatio = (float)target.mCurrentHP / (float)target.mMaxHP;
			if (hpRatio < bestHPRatio)
			{
				bestHPRatio = hpRatio;
				bestTarget = i;
			}
		}

		// For MostWoundedAlly target type, return the most wounded
		// For Self target type, only heal self if wounded
		if (targetType == .Self)
		{
			let selfRatio = (float)healer.mCurrentHP / (float)healer.mMaxHP;
			return selfRatio < 0.5f ? healer.mIndex : -1;
		}

		return bestTarget;
	}

	// =========================================================================
	// Target selection
	// =========================================================================

	/// Find a random enemy to attack in range (Easy difficulty).
	private static int32 FindRandomAttackTarget(BattleSimulation sim, BattleUnit attacker, Force targetForce)
	{
		let candidates = scope List<int32>();

		for (int32 i = 0; i < sim.UnitCount; i++)
		{
			let target = sim.GetUnit(i);
			if (target == null || !target.mAlive) continue;
			if (target.mForce != targetForce) continue;

			let dist = attacker.mPosition.DistanceTo(target.mPosition);
			if (dist <= attacker.mModifiedAttackRange)
				candidates.Add(i);
		}

		if (candidates.Count == 0) return -1;
		return candidates[sim.Rng.Next((.)candidates.Count)];
	}

	/// Find the best enemy to attack in range.
	/// Prefers lowest HP target (focus fire), then closest.
	private static int32 FindBestAttackTarget(BattleSimulation sim, BattleUnit attacker, Force targetForce)
	{
		int32 bestTarget = -1;
		int32 bestHP = int32.MaxValue;
		int32 bestDist = int32.MaxValue;

		for (int32 i = 0; i < sim.UnitCount; i++)
		{
			let target = sim.GetUnit(i);
			if (target == null || !target.mAlive) continue;
			if (target.mForce != targetForce) continue;

			let dist = attacker.mPosition.DistanceTo(target.mPosition);
			if (dist > attacker.mModifiedAttackRange) continue;

			if (target.mCurrentHP < bestHP || (target.mCurrentHP == bestHP && dist < bestDist))
			{
				bestTarget = i;
				bestHP = target.mCurrentHP;
				bestDist = dist;
			}
		}

		return bestTarget;
	}

	// =========================================================================
	// Movement
	// =========================================================================

	/// Find the best hex to move toward to get in range of an enemy.
	private static HexCoord FindBestMoveTarget(BattleSimulation sim, BattleUnit unit, Force targetForce)
	{
		// Find the nearest enemy
		int32 nearestEnemyIdx = -1;
		int32 nearestDist = int32.MaxValue;

		for (int32 i = 0; i < sim.UnitCount; i++)
		{
			let target = sim.GetUnit(i);
			if (target == null || !target.mAlive) continue;
			if (target.mForce != targetForce) continue;

			let dist = unit.mPosition.DistanceTo(target.mPosition);
			if (dist < nearestDist)
			{
				nearestDist = dist;
				nearestEnemyIdx = i;
			}
		}

		if (nearestEnemyIdx < 0)
			return unit.mPosition;

		let enemyPos = sim.GetUnit(nearestEnemyIdx).mPosition;
		let grid = sim.Grid;

		// Get reachable cells
		let reachable = scope List<HexCoord>();
		let pathfinder = scope HexPathfinder(grid);
		let flying = unit.mConfig.mMoveType == .Flying;
		pathfinder.GetReachableCells(unit.mPosition, unit.mModifiedMoveRange, flying, reachable);

		// Pick the reachable cell closest to the enemy
		var bestHex = unit.mPosition;
		int32 bestMoveDist = nearestDist;

		for (let hex in reachable)
		{
			if (hex.Q == unit.mPosition.Q && hex.R == unit.mPosition.R) continue;
			let occupant = grid.GetOccupant(hex);
			if (occupant >= 0) continue;

			let dist = hex.DistanceTo(enemyPos);
			if (dist < bestMoveDist)
			{
				bestMoveDist = dist;
				bestHex = hex;
			}
		}

		return bestHex;
	}
}

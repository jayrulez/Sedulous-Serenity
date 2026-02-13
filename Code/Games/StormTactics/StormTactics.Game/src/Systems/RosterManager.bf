namespace StormTactics.Game;

using System;
using StormTactics.Core;

/// Effective stats after star level multipliers and equipment.
struct EffectiveStats
{
	public int32 mHP;
	public int32 mDamage;
	public int32 mDefense;
	public int32 mActionSpeed;
	public int32 mMoveRange;
	public int32 mAttackRange;
	public int32 mPower;
}

/// Manages the player's unit roster: ownership, shards, star upgrades, and effective stats.
class RosterManager
{
	public const int32 MAX_UNIT_LEVEL = 30;
	public const int32 BASE_EXP_PER_LEVEL = 100; // EXP to reach level 2; scales linearly

	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;
	private EquipmentManager mEquipMgr;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;
	}

	/// Set equipment manager reference for stat calculations.
	public void SetEquipmentManager(EquipmentManager equipMgr)
	{
		mEquipMgr = equipMgr;
	}

	/// Check if the player owns a unit.
	public bool HasUnit(int32 unitId) => mSave.GetOwnedUnit(unitId) != null;

	/// Add a new unit to the roster. Returns false if already owned.
	public bool AddUnit(int32 unitId)
	{
		if (HasUnit(unitId)) return false;

		let unit = new OwnedUnitData();
		unit.mUnitId = unitId;
		unit.mStarLevel = 1;
		unit.mLevel = 1;
		mSave.mOwnedUnits.Add(unit);
		return true;
	}

	/// Add shards for a unit. If the unit isn't owned, adds it first.
	public void AddShards(int32 unitId, int32 amount)
	{
		if (!HasUnit(unitId))
			AddUnit(unitId);

		let unit = mSave.GetOwnedUnit(unitId);
		if (unit != null)
			unit.mShards += amount;
	}

	/// Try to star-up a unit. Returns true if successful.
	public bool TryStarUp(int32 unitId)
	{
		let owned = mSave.GetOwnedUnit(unitId);
		if (owned == null) return false;

		let nextStar = owned.mStarLevel + 1;
		let starConfig = mConfigs.GetStarLevel(unitId, nextStar);
		if (starConfig == null) return false; // Already at max star

		if (owned.mShards < starConfig.mShardsRequired)
			return false;

		owned.mShards -= starConfig.mShardsRequired;
		owned.mStarLevel = nextStar;
		Console.WriteLine("[Roster] Unit {} starred up to {}", unitId, nextStar);
		return true;
	}

	/// Get shards required for next star level. Returns 0 if at max.
	public int32 GetShardsForNextStar(int32 unitId)
	{
		let owned = mSave.GetOwnedUnit(unitId);
		if (owned == null) return 0;

		let starConfig = mConfigs.GetStarLevel(unitId, owned.mStarLevel + 1);
		return starConfig != null ? starConfig.mShardsRequired : 0;
	}

	/// Check if a unit can be starred up right now.
	public bool CanStarUp(int32 unitId)
	{
		let owned = mSave.GetOwnedUnit(unitId);
		if (owned == null) return false;

		let starConfig = mConfigs.GetStarLevel(unitId, owned.mStarLevel + 1);
		if (starConfig == null) return false;

		return owned.mShards >= starConfig.mShardsRequired;
	}

	// --- Unit Leveling ---

	/// Get EXP required to reach the next level from the given level.
	public static int32 ExpForLevel(int32 level)
	{
		return BASE_EXP_PER_LEVEL * level; // Level 1→2 = 100, Level 2→3 = 200, etc.
	}

	/// Add EXP to a unit and process level-ups. Returns number of levels gained.
	public int32 AddUnitExp(int32 unitId, int32 amount)
	{
		if (amount <= 0) return 0;

		let owned = mSave.GetOwnedUnit(unitId);
		if (owned == null) return 0;
		if (owned.mLevel >= MAX_UNIT_LEVEL) return 0;

		owned.mExp += amount;
		int32 levelsGained = 0;

		while (owned.mLevel < MAX_UNIT_LEVEL)
		{
			let required = ExpForLevel(owned.mLevel);
			if (owned.mExp >= required)
			{
				owned.mExp -= required;
				owned.mLevel++;
				levelsGained++;
			}
			else
				break;
		}

		// Cap EXP at 0 if max level
		if (owned.mLevel >= MAX_UNIT_LEVEL)
			owned.mExp = 0;

		if (levelsGained > 0)
			Console.WriteLine("[Roster] Unit {} leveled up to {}", unitId, owned.mLevel);

		return levelsGained;
	}

	/// Get EXP needed for a unit's next level. Returns 0 if at max level.
	public int32 GetUnitExpToNextLevel(int32 unitId)
	{
		let owned = mSave.GetOwnedUnit(unitId);
		if (owned == null || owned.mLevel >= MAX_UNIT_LEVEL) return 0;
		return ExpForLevel(owned.mLevel);
	}

	// --- Skill Unlock ---

	/// Get all skill IDs unlocked for a unit at its current star level.
	/// Collects skills from all star configs up to and including current star.
	public void GetUnlockedSkills(int32 unitId, System.Collections.List<int32> outSkillIds)
	{
		let owned = mSave.GetOwnedUnit(unitId);
		if (owned == null) return;

		for (int32 star = 1; star <= owned.mStarLevel; star++)
		{
			let starConfig = mConfigs.GetStarLevel(unitId, star);
			if (starConfig != null)
			{
				for (let skillId in starConfig.mUnlockedSkillIds)
					if (!outSkillIds.Contains(skillId))
						outSkillIds.Add(skillId);
			}
		}
	}

	/// Calculate effective stats for a unit, factoring in level, star multipliers and equipment.
	public EffectiveStats GetEffectiveStats(int32 unitId)
	{
		var stats = EffectiveStats();

		let config = mConfigs.GetUnit(unitId);
		if (config == null) return stats;

		let owned = mSave.GetOwnedUnit(unitId);

		// Base stats from config
		float hp = (float)(config.mSoldierHP * config.mSoldierCount);
		float damage = (float)config.mSoldierDamage;
		float defense = (float)config.mDefense;
		float actionSpeed = (float)config.mActionSpeed;
		float moveRange = (float)config.mMoveRange;
		float attackRange = (float)config.mAttackRange;

		// Star level multipliers (cumulative from level 1 to current)
		if (owned != null)
		{
			for (int32 star = 1; star <= owned.mStarLevel; star++)
			{
				let starConfig = mConfigs.GetStarLevel(unitId, star);
				if (starConfig != null)
				{
					hp *= starConfig.mHPMultiplier;
					damage *= starConfig.mDamageMultiplier;
					defense *= starConfig.mDefenseMultiplier;
				}
			}

			// Unit level scaling: +2% per level above 1
			if (owned.mLevel > 1)
			{
				let levelBonus = 1.0f + (float)(owned.mLevel - 1) * 0.02f;
				hp *= levelBonus;
				damage *= levelBonus;
				defense *= levelBonus;
			}
		}

		// Equipment bonuses
		if (mEquipMgr != null)
		{
			float hpFlat, hpPct, dmgFlat, dmgPct, defFlat, defPct, spdFlat, spdPct;
			mEquipMgr.GetEquipStatBonuses(unitId,
				out hpFlat, out hpPct, out dmgFlat, out dmgPct,
				out defFlat, out defPct, out spdFlat, out spdPct);

			hp = hp * (1.0f + hpPct) + hpFlat;
			damage = damage * (1.0f + dmgPct) + dmgFlat;
			defense = defense * (1.0f + defPct) + defFlat;
			actionSpeed = actionSpeed * (1.0f + spdPct) + spdFlat;
		}

		stats.mHP = (int32)hp;
		stats.mDamage = (int32)damage;
		stats.mDefense = (int32)defense;
		stats.mActionSpeed = (int32)actionSpeed;
		stats.mMoveRange = (int32)moveRange;
		stats.mAttackRange = (int32)attackRange;

		// Power rating: weighted sum
		stats.mPower = stats.mHP / 5 + stats.mDamage * 3 + stats.mDefense * 2 + stats.mActionSpeed;

		return stats;
	}

	/// Calculate total roster power (sum of all owned unit powers).
	public int32 GetTotalPower()
	{
		int32 total = 0;
		for (let owned in mSave.mOwnedUnits)
			total += GetEffectiveStats(owned.mUnitId).mPower;
		return total;
	}
}

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

	/// Calculate effective stats for a unit, factoring in star multipliers and equipment.
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

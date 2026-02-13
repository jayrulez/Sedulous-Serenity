namespace StormTactics.Battle;

using System;
using System.Collections;
using StormTactics.Core;

/// Runtime state of a unit in battle.
class BattleUnit
{
	// --- Identity ---
	public int32 mIndex;            // Position in the battle's unit array
	public UnitConfig mConfig;
	public Force mForce;
	public int32 mFormationSlot;
	public int32 mLevel = 1;        // Display-only: unit level
	public int32 mStarLevel = 1;    // Display-only: star level

	// --- Position ---
	public HexCoord mPosition;

	// --- HP ---
	public int32 mMaxHP;
	public int32 mCurrentHP;
	public bool mAlive = true;

	// --- Turn timing ---
	public float mActionTimer;      // Time remaining until this unit acts

	// --- Buffs ---
	public List<BuffInstance> mBuffs = new .() ~ DeleteContainerAndItems!(_);

	// --- Skill cooldowns ---
	public Dictionary<int32, int32> mSkillCooldowns = new .() ~ delete _;  // skillId → turns remaining
	public Dictionary<int32, int32> mSkillUsesThisBattle = new .() ~ delete _; // skillId → times used

	// --- Cached modified stats ---
	public int32 mModifiedDamage;
	public int32 mModifiedDefense;
	public int32 mModifiedActionSpeed;
	public int32 mModifiedMoveRange;
	public int32 mModifiedAttackRange;

	// --- Per-turn counters ---
	public int32 mCounterAttacksThisTurn;

	// --- Properties ---

	public int32 SoldierHP => mConfig.mSoldierHP;

	/// Current soldier count based on remaining HP.
	public int32 SoldierCount
	{
		get
		{
			if (!mAlive || mCurrentHP <= 0) return 0;
			return (int32)Math.Ceiling((float)mCurrentHP / (float)SoldierHP);
		}
	}

	public bool IsStunned
	{
		get
		{
			for (let buff in mBuffs)
				if (buff.mConfig.mTag == .Stun) return true;
			return false;
		}
	}

	public bool IsSilenced
	{
		get
		{
			for (let buff in mBuffs)
				if (buff.mConfig.mTag == .Silence) return true;
			return false;
		}
	}

	public bool IsCharmed
	{
		get
		{
			for (let buff in mBuffs)
				if (buff.mConfig.mTag == .Charm) return true;
			return false;
		}
	}

	public bool HasImmunity(BuffTag tag)
	{
		for (let buff in mBuffs)
			if (buff.mConfig.mTag == .Immune) return true;
		return false;
	}

	// --- Initialization ---

	public void Initialize(int32 index, UnitConfig config, Force force, HexCoord position, int32 formationSlot)
	{
		mIndex = index;
		mConfig = config;
		mForce = force;
		mPosition = position;
		mFormationSlot = formationSlot;
		mMaxHP = config.mSoldierHP * config.mSoldierCount;
		mCurrentHP = mMaxHP;
		mAlive = true;
		mActionTimer = (float)BattleConstants.TIME_UNIT / (float)config.mActionSpeed;
		RecalculateStats();
	}

	/// Recalculate modified stats from base + buff modifiers.
	public void RecalculateStats()
	{
		float damageMult = 1.0f;
		float defenseMult = 1.0f;
		float speedMult = 1.0f;
		float moveRangeMult = 1.0f;
		float attackRangeMult = 1.0f;
		int32 damageFlat = 0;
		int32 defenseFlat = 0;
		int32 speedFlat = 0;
		int32 moveRangeFlat = 0;
		int32 attackRangeFlat = 0;

		for (let buff in mBuffs)
		{
			for (let mod in buff.mConfig.mStatModifiers)
			{
				switch (mod.mAttribute)
				{
				case .Damage:
					damageFlat += (int32)mod.mFlatValue;
					damageMult += mod.mPercentValue;
				case .Defense:
					defenseFlat += (int32)mod.mFlatValue;
					defenseMult += mod.mPercentValue;
				case .ActionSpeed:
					speedFlat += (int32)mod.mFlatValue;
					speedMult += mod.mPercentValue;
				case .MoveRange:
					moveRangeFlat += (int32)mod.mFlatValue;
					moveRangeMult += mod.mPercentValue;
				case .AttackRange:
					attackRangeFlat += (int32)mod.mFlatValue;
					attackRangeMult += mod.mPercentValue;
				case .HP:
					// HP modifiers don't affect max HP in combat (only pre-battle)
				}
			}
		}

		mModifiedDamage = Math.Max(0, (int32)((float)(mConfig.mSoldierDamage + damageFlat) * damageMult));
		mModifiedDefense = Math.Max(0, (int32)((float)(mConfig.mDefense + defenseFlat) * defenseMult));
		mModifiedActionSpeed = Math.Max(1, (int32)((float)(mConfig.mActionSpeed + speedFlat) * speedMult));
		mModifiedMoveRange = Math.Max(0, (int32)((float)(mConfig.mMoveRange + moveRangeFlat) * moveRangeMult));
		mModifiedAttackRange = Math.Max(1, (int32)((float)(mConfig.mAttackRange + attackRangeFlat) * attackRangeMult));
	}

	// --- Damage & healing ---

	/// Apply damage, returns actual damage dealt.
	public int32 TakeDamage(int32 amount)
	{
		let actual = Math.Min(mCurrentHP, amount);
		mCurrentHP -= actual;
		if (mCurrentHP <= 0)
		{
			mCurrentHP = 0;
			mAlive = false;
		}
		return actual;
	}

	/// Apply healing, returns actual HP restored.
	public int32 Heal(int32 amount)
	{
		let actual = Math.Min(mMaxHP - mCurrentHP, amount);
		mCurrentHP += actual;
		return actual;
	}

	// --- Cooldowns ---

	public bool IsSkillOnCooldown(int32 skillId)
	{
		if (mSkillCooldowns.TryGetValue(skillId, let cd))
			return cd > 0;
		return false;
	}

	public bool IsSkillUsesExhausted(int32 skillId, SkillConfig skillConfig)
	{
		if (skillConfig.mMaxUsesPerBattle <= 0) return false;
		if (mSkillUsesThisBattle.TryGetValue(skillId, let uses))
			return uses >= skillConfig.mMaxUsesPerBattle;
		return false;
	}

	public void PutSkillOnCooldown(int32 skillId, int32 cooldown)
	{
		mSkillCooldowns[skillId] = cooldown;
	}

	public void RecordSkillUse(int32 skillId)
	{
		if (mSkillUsesThisBattle.TryGetValue(skillId, let uses))
			mSkillUsesThisBattle[skillId] = uses + 1;
		else
			mSkillUsesThisBattle[skillId] = 1;
	}

	public void TickCooldowns()
	{
		let toRemove = scope List<int32>();
		for (let kv in mSkillCooldowns)
		{
			mSkillCooldowns[kv.key] = kv.value - 1;
			if (kv.value - 1 <= 0)
				toRemove.Add(kv.key);
		}
		for (let key in toRemove)
			mSkillCooldowns.Remove(key);
	}

	// --- Turn reset ---

	public void OnTurnStart()
	{
		mCounterAttacksThisTurn = 0;
	}

	public void ResetActionTimer()
	{
		mActionTimer = (float)BattleConstants.TIME_UNIT / (float)mModifiedActionSpeed;
	}
}

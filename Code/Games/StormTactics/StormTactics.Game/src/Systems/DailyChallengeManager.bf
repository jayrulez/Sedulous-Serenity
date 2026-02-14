namespace StormTactics.Game;

using System;
using System.Collections;
using StormTactics.Core;

/// Manages daily rotating challenges with unit restrictions.
/// Each day, 3 challenges are selected from a pool of templates.
class DailyChallengeManager
{
	public const int32 CHALLENGES_PER_DAY = 3;
	public const int64 DAILY_RESET_SECONDS = 86400;

	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;
	private List<DailyChallengeTemplate> mTemplates = new .() ~ DeleteContainerAndItems!(_);
	private DailyChallengeTemplate[CHALLENGES_PER_DAY] mTodayChallenges;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;
		BuildTemplatePool();
		CheckDailyReset();
	}

	/// Check if a new day has started and reset challenges if so.
	public void CheckDailyReset()
	{
		let now = GetCurrentTimestamp();
		let currentDay = (int32)(now / DAILY_RESET_SECONDS);

		if (currentDay != mSave.mDailyChallengeDay)
		{
			mSave.mDailyChallengeDay = currentDay;
			mSave.mDailyChallengesCompleted = 0;
			mSave.mLastDailyChallengeTime = now;
			Console.WriteLine("[DailyChallenge] New day {} — challenges reset", currentDay);
		}

		SelectTodayChallenges();
	}

	/// Get today's challenge at the given index (0-2).
	public DailyChallengeTemplate GetChallenge(int32 index)
	{
		if (index < 0 || index >= CHALLENGES_PER_DAY) return null;
		return mTodayChallenges[index];
	}

	/// Check if a challenge has been completed today.
	public bool IsChallengeCompleted(int32 index)
	{
		return (mSave.mDailyChallengesCompleted & (1 << index)) != 0;
	}

	/// Mark a challenge as completed.
	public void MarkCompleted(int32 index)
	{
		mSave.mDailyChallengesCompleted |= (1 << index);
	}

	/// Check if a unit is allowed for the given challenge.
	public bool IsUnitAllowed(int32 challengeIndex, UnitConfig unit)
	{
		if (unit == null) return false;
		let tmpl = GetChallenge(challengeIndex);
		if (tmpl == null) return true;

		switch (tmpl.mRestrictionType)
		{
		case .AllowClasses:
			return (tmpl.mRestrictionMask & (1 << (int32)unit.mUnitClass)) != 0;
		case .BlockClasses:
			return (tmpl.mRestrictionMask & (1 << (int32)unit.mUnitClass)) == 0;
		case .AllowDamageTypes:
			return (tmpl.mRestrictionMask & (1 << (int32)unit.mDamageType)) != 0;
		case .AllowRaces:
			return (tmpl.mRestrictionMask & (1 << (int32)unit.mRace)) != 0;
		}
	}

	/// Seconds until the next daily reset. Returns 0 if reset is due.
	public int32 SecondsUntilReset
	{
		get
		{
			let now = GetCurrentTimestamp();
			let nextReset = ((now / DAILY_RESET_SECONDS) + 1) * DAILY_RESET_SECONDS;
			return (int32)Math.Max(0, nextReset - now);
		}
	}

	/// Select today's challenges using day number as deterministic seed.
	private void SelectTodayChallenges()
	{
		if (mTemplates.Count == 0) return;

		let rng = scope Random(mSave.mDailyChallengeDay);
		let indices = scope List<int32>();
		for (int32 i = 0; i < (int32)mTemplates.Count; i++)
			indices.Add(i);

		// Fisher-Yates shuffle to pick first 3
		let count = Math.Min(CHALLENGES_PER_DAY, (int32)indices.Count);
		for (int32 i = 0; i < count; i++)
		{
			let j = i + (int32)(rng.Next((int32)indices.Count - i));
			let tmp = indices[i];
			indices[i] = indices[j];
			indices[j] = tmp;
			mTodayChallenges[i] = mTemplates[indices[i]];
		}

		Console.WriteLine("[DailyChallenge] Today's challenges: {}, {}, {}",
			mTodayChallenges[0]?.mName ?? "?",
			mTodayChallenges[1]?.mName ?? "?",
			mTodayChallenges[2]?.mName ?? "?");
	}

	/// Build the pool of all challenge templates.
	private void BuildTemplatePool()
	{
		// Class restrictions
		AddTemplate(1, "Tank & Healer", "Only Tank and Healer units allowed",
			1, 1.0f, .AllowClasses, ClassMask(.Tank, .Healer), 300, 200, 10);

		AddTemplate(2, "Ranged Assault", "Only Ranger and Caster units allowed",
			2, 1.0f, .AllowClasses, ClassMask(.Ranger, .Caster), 300, 200, 10);

		AddTemplate(3, "Front Line", "Only Tank and Striker units allowed",
			3, 1.0f, .AllowClasses, ClassMask(.Tank, .Striker), 300, 200, 10);

		AddTemplate(10, "Light Infantry", "Only Striker and Ranger units allowed",
			5, 1.0f, .AllowClasses, ClassMask(.Striker, .Ranger), 300, 200, 10);

		AddTemplate(11, "Arcane Vanguard", "Only Caster and Healer units allowed",
			1, 1.2f, .AllowClasses, ClassMask(.Caster, .Healer), 400, 250, 15);

		AddTemplate(9, "Siege Masters", "Only Siege and Tank units allowed",
			4, 1.3f, .AllowClasses, ClassMask(.Siege, .Tank), 500, 300, 20);

		AddTemplate(8, "No Healers", "All units except Healers allowed",
			3, 1.0f, .BlockClasses, ClassMask(.Healer), 350, 220, 12);

		// Damage type restrictions
		AddTemplate(4, "Magic Only", "Only units with Magic damage allowed",
			4, 1.2f, .AllowDamageTypes, DamageMask(.Magic), 400, 250, 15);

		AddTemplate(5, "Physical Might", "Only Physical and Piercing damage allowed",
			5, 1.2f, .AllowDamageTypes, DamageMask(.Physical, .Piercing), 400, 250, 15);

		// Race restrictions
		AddTemplate(6, "Human Alliance", "Only Human units allowed",
			1, 1.0f, .AllowRaces, RaceMask(.Human), 300, 200, 10);

		AddTemplate(7, "Undead & Demons", "Only Undead and Demon units allowed",
			2, 1.3f, .AllowRaces, RaceMask(.Undead, .Demon), 500, 300, 20);

		AddTemplate(12, "Beast Tamers", "Only Beast and Elemental units allowed",
			3, 1.3f, .AllowRaces, RaceMask(.Beast, .Elemental), 500, 300, 20);
	}

	private void AddTemplate(int32 id, StringView name, StringView desc,
		int32 stageId, float scale, ChallengeRestrictionType type, int32 mask,
		int32 gold, int32 exp, int32 gems)
	{
		let tmpl = new DailyChallengeTemplate();
		tmpl.mId = id;
		tmpl.mName.Set(name);
		tmpl.mDescription.Set(desc);
		tmpl.mStageId = stageId;
		tmpl.mDifficultyScale = scale;
		tmpl.mRestrictionType = type;
		tmpl.mRestrictionMask = mask;
		tmpl.mGoldReward = gold;
		tmpl.mExpReward = exp;
		tmpl.mGemReward = gems;
		mTemplates.Add(tmpl);
	}

	// --- Bitmask helpers ---

	private static int32 ClassMask(params UnitClass[] classes)
	{
		int32 mask = 0;
		for (let c in classes) mask |= (1 << (int32)c);
		return mask;
	}

	private static int32 DamageMask(params DamageType[] types)
	{
		int32 mask = 0;
		for (let t in types) mask |= (1 << (int32)t);
		return mask;
	}

	private static int32 RaceMask(params UnitRace[] races)
	{
		int32 mask = 0;
		for (let r in races) mask |= (1 << (int32)r);
		return mask;
	}

	private static int64 GetCurrentTimestamp()
	{
		return DateTime.UtcNow.ToFileTime() / 10000000 - 11644473600;
	}
}

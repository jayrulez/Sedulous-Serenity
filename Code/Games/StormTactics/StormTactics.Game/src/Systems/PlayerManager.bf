namespace StormTactics.Game;

using System;
using StormTactics.Core;

/// Manages hero level/EXP, stamina, currencies, and stage unlock tracking.
class PlayerManager
{
	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;
	}

	// --- Hero EXP / Level ---

	/// Add EXP and process any level-ups. Returns number of levels gained.
	public int32 AddHeroExp(int32 amount)
	{
		if (amount <= 0) return 0;

		mSave.mHeroExp += amount;
		int32 levelsGained = 0;

		while (true)
		{
			let levelConfig = mConfigs.GetHeroLevel(mSave.mHeroLevel);
			if (levelConfig == null) break; // Max level reached (no config for next)

			if (mSave.mHeroExp >= levelConfig.mExpRequired)
			{
				mSave.mHeroExp -= levelConfig.mExpRequired;
				mSave.mHeroLevel++;
				levelsGained++;
				Console.WriteLine("[PlayerManager] Level up! Now level {}", mSave.mHeroLevel);
			}
			else
			{
				break;
			}
		}

		return levelsGained;
	}

	/// Get EXP needed for current level (0 if at max).
	public int32 ExpToNextLevel
	{
		get
		{
			let config = mConfigs.GetHeroLevel(mSave.mHeroLevel);
			return config != null ? config.mExpRequired : 0;
		}
	}

	// --- Stamina ---

	/// Get max stamina for current hero level.
	public int32 MaxStamina
	{
		get
		{
			let config = mConfigs.GetHeroLevel(mSave.mHeroLevel);
			return config != null ? config.mMaxStamina : 30;
		}
	}

	/// Try to spend stamina. Returns true if successful.
	public bool TrySpendStamina(int32 amount)
	{
		if (mSave.mStamina < amount) return false;
		mSave.mStamina -= amount;
		return true;
	}

	/// Add stamina (capped at max).
	public void AddStamina(int32 amount)
	{
		mSave.mStamina = Math.Min(mSave.mStamina + amount, MaxStamina);
	}

	// --- Currencies ---

	public bool TrySpendGold(int32 amount)
	{
		if (mSave.mGold < amount) return false;
		mSave.mGold -= amount;
		return true;
	}

	public void AddGold(int32 amount)
	{
		mSave.mGold += amount;
	}

	public bool TrySpendGems(int32 amount)
	{
		if (mSave.mGems < amount) return false;
		mSave.mGems -= amount;
		return true;
	}

	public void AddGems(int32 amount)
	{
		mSave.mGems += amount;
	}

	public void AddArenaTokens(int32 amount) { mSave.mArenaTokens += amount; }
	public void AddGuildTokens(int32 amount) { mSave.mGuildTokens += amount; }

	// --- Stage Progress ---

	/// Check if a stage is unlocked for the player.
	public bool IsStageUnlocked(int32 stageId)
	{
		let stage = mConfigs.GetStage(stageId);
		if (stage == null) return false;

		// First stage (no unlock requirement) is always available
		if (stage.mUnlockStageId == 0) return true;

		// Need to have cleared the prerequisite stage
		return mSave.mMaxStageClearedId >= stage.mUnlockStageId;
	}

	/// Record a stage clear with star rating. Updates max cleared ID.
	public void RecordStageClear(int32 stageId, int32 stars)
	{
		mSave.RecordStageClear(stageId, stars);
		if (stageId > mSave.mMaxStageClearedId)
			mSave.mMaxStageClearedId = stageId;
	}

	/// Get best star rating for a stage.
	public int32 GetBestStars(int32 stageId) => mSave.GetBestStars(stageId);

	// --- Formation Slots ---

	/// Get max formation slots for current hero level.
	public int32 MaxFormationSlots
	{
		get
		{
			let config = mConfigs.GetHeroLevel(mSave.mHeroLevel);
			return config != null ? config.mMaxFormationSlots : 3;
		}
	}
}

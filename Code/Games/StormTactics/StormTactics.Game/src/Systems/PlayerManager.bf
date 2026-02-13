namespace StormTactics.Game;

using System;
using StormTactics.Core;

/// Manages hero level/EXP, stamina, currencies, and stage unlock tracking.
class PlayerManager
{
	public const int32 STAMINA_REGEN_SECONDS = 300; // 5 minutes per stamina point

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

	/// Process stamina regeneration based on elapsed real time.
	/// Call on game load and periodically during gameplay.
	public void UpdateStaminaRegen()
	{
		let now = GetCurrentTimestamp();

		// First-time init
		if (mSave.mLastStaminaTime == 0)
		{
			mSave.mLastStaminaTime = now;
			return;
		}

		if (mSave.mStamina >= MaxStamina)
		{
			mSave.mLastStaminaTime = now;
			return;
		}

		let elapsed = now - mSave.mLastStaminaTime;
		if (elapsed <= 0) return;

		let regenPoints = (int32)(elapsed / STAMINA_REGEN_SECONDS);
		if (regenPoints > 0)
		{
			let oldStamina = mSave.mStamina;
			mSave.mStamina = Math.Min(mSave.mStamina + regenPoints, MaxStamina);
			// Only consume the time for the points actually regenerated
			let consumed = mSave.mStamina - oldStamina;
			mSave.mLastStaminaTime += (int64)(consumed * STAMINA_REGEN_SECONDS);
		}
	}

	/// Seconds until next stamina point regenerates. Returns 0 if stamina is full.
	public int32 SecondsUntilNextStamina
	{
		get
		{
			if (mSave.mStamina >= MaxStamina) return 0;
			let now = GetCurrentTimestamp();
			let elapsed = now - mSave.mLastStaminaTime;
			return (int32)Math.Max(0, STAMINA_REGEN_SECONDS - elapsed);
		}
	}

	/// Get current unix timestamp in seconds.
	private static int64 GetCurrentTimestamp()
	{
		return DateTime.UtcNow.ToFileTime() / 10000000 - 11644473600;
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

	/// Get sweep count for a stage.
	public int32 GetSweepCount(int32 stageId) => mSave.GetSweepCount(stageId);

	/// Check if a stage can be swept (has sweeps remaining).
	public bool CanSweep(int32 stageId)
	{
		let stage = mConfigs.GetStage(stageId);
		if (stage == null) return false;
		if (GetBestStars(stageId) < 3) return false;
		if (stage.mSweepLimit > 0 && mSave.GetSweepCount(stageId) >= stage.mSweepLimit) return false;
		return true;
	}

	/// Increment sweep count for a stage.
	public void IncrementSweepCount(int32 stageId) => mSave.IncrementSweepCount(stageId);

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

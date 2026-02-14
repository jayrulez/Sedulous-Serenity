namespace StormTactics.Game;

using System;
using System.Collections;
using StormTactics.Core;

/// Holds the result of processing stage rewards for display.
class RewardResult
{
	public int32 mGoldGained;
	public int32 mExpGained;
	public int32 mGemsGained;
	public int32 mLevelsGained;
	public bool mIsFirstClear;
	public List<ItemRewardInfo> mItems = new .() ~ DeleteContainerAndItems!(_);
}

class ItemRewardInfo
{
	public int32 mItemId;
	public String mItemName = new .() ~ delete _;
	public int32 mQuantity;
}

/// Processes rewards after a stage clear.
class RewardProcessor
{
	private PlayerManager mPlayerMgr;
	private InventoryManager mInventoryMgr;
	private ConfigDatabase mConfigs;
	private Random mRng = new .() ~ delete _;

	public void Initialize(PlayerManager playerMgr, InventoryManager inventoryMgr, ConfigDatabase configs)
	{
		mPlayerMgr = playerMgr;
		mInventoryMgr = inventoryMgr;
		mConfigs = configs;
	}

	/// Process rewards for completing a stage. Returns the reward summary for display.
	/// Caller owns the returned RewardResult.
	public RewardResult ProcessStageRewards(int32 stageId, int32 starRating, bool isHardMode = false)
	{
		let result = new RewardResult();

		let stage = mConfigs.GetStage(stageId);
		if (stage == null) return result;

		// Check if this is first clear (no stars recorded yet)
		let previousBest = isHardMode ? mPlayerMgr.GetHardStars(stageId) : mPlayerMgr.GetBestStars(stageId);
		result.mIsFirstClear = (previousBest == 0);

		// Base gold reward: difficulty * 50 + star bonus (1.5x for hard mode)
		int32 baseGold = stage.mDifficulty * 50 + starRating * 20;
		if (isHardMode)
			baseGold = (int32)((float)baseGold * 1.5f);
		result.mGoldGained = baseGold;

		// Base EXP reward: difficulty * 30 (1.5x for hard mode)
		int32 baseExp = stage.mDifficulty * 30;
		if (isHardMode)
			baseExp = (int32)((float)baseExp * 1.5f);
		result.mExpGained = baseExp;

		// First-clear bonus
		if (result.mIsFirstClear)
		{
			if (stage.mFirstClearGold > 0)
				result.mGoldGained += stage.mFirstClearGold;
			if (stage.mFirstClearGems > 0)
				result.mGemsGained += stage.mFirstClearGems;
		}

		// Apply gold, gems, EXP
		mPlayerMgr.AddGold(result.mGoldGained);
		if (result.mGemsGained > 0)
			mPlayerMgr.AddGems(result.mGemsGained);
		result.mLevelsGained = mPlayerMgr.AddHeroExp(result.mExpGained);

		// Record stage clear
		if (isHardMode)
			mPlayerMgr.RecordHardClear(stageId, starRating);
		else
			mPlayerMgr.RecordStageClear(stageId, starRating);

		// Item rewards with drop chance
		for (let reward in stage.mRewards)
		{
			float roll = (float)mRng.NextDouble();
			if (roll <= reward.mDropChance)
			{
				int32 added = mInventoryMgr.AddItem(reward.mItemId, reward.mQuantity);
				if (added > 0)
				{
					let info = new ItemRewardInfo();
					info.mItemId = reward.mItemId;
					info.mQuantity = added;

					let itemConfig = mConfigs.GetItem(reward.mItemId);
					if (itemConfig != null)
						info.mItemName.Set(itemConfig.mName);
					else
						info.mItemName.AppendF("Item #{}", reward.mItemId);

					result.mItems.Add(info);
				}
			}
		}

		return result;
	}

	/// Sweep a 3-starred stage: spend stamina, grant rewards without battle.
	/// Returns null if stage is not sweepable (not 3-starred or not enough stamina).
	/// Caller owns the returned RewardResult.
	public RewardResult SweepStage(int32 stageId, bool isHardMode = false)
	{
		let stage = mConfigs.GetStage(stageId);
		if (stage == null) return null;

		// Must be 3-starred and have sweeps remaining
		if (isHardMode)
		{
			if (!mPlayerMgr.CanSweepHard(stageId)) return null;
		}
		else
		{
			if (!mPlayerMgr.CanSweep(stageId)) return null;
		}

		// Must have enough stamina
		if (!mPlayerMgr.TrySpendStamina(stage.mStaminaCost)) return null;

		// Increment sweep count
		if (isHardMode)
			mPlayerMgr.IncrementHardSweepCount(stageId);
		else
			mPlayerMgr.IncrementSweepCount(stageId);

		// Grant same rewards as a 3-star clear (no first-clear bonus since already cleared)
		let result = new RewardResult();

		int32 baseGold = stage.mDifficulty * 50 + 3 * 20;
		if (isHardMode)
			baseGold = (int32)((float)baseGold * 1.5f);
		result.mGoldGained = baseGold;
		mPlayerMgr.AddGold(baseGold);

		int32 baseExp = stage.mDifficulty * 30;
		if (isHardMode)
			baseExp = (int32)((float)baseExp * 1.5f);
		result.mExpGained = baseExp;
		result.mLevelsGained = mPlayerMgr.AddHeroExp(baseExp);

		// Item rewards with drop chance
		for (let reward in stage.mRewards)
		{
			float roll = (float)mRng.NextDouble();
			if (roll <= reward.mDropChance)
			{
				int32 added = mInventoryMgr.AddItem(reward.mItemId, reward.mQuantity);
				if (added > 0)
				{
					let info = new ItemRewardInfo();
					info.mItemId = reward.mItemId;
					info.mQuantity = added;

					let itemConfig = mConfigs.GetItem(reward.mItemId);
					if (itemConfig != null)
						info.mItemName.Set(itemConfig.mName);
					else
						info.mItemName.AppendF("Item #{}", reward.mItemId);

					result.mItems.Add(info);
				}
			}
		}

		return result;
	}
}

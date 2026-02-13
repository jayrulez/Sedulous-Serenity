namespace StormTactics.Game;

using System;
using System.Collections;
using StormTactics.Core;

/// Holds the result of processing stage rewards for display.
class RewardResult
{
	public int32 mGoldGained;
	public int32 mExpGained;
	public int32 mLevelsGained;
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
	public RewardResult ProcessStageRewards(int32 stageId, int32 starRating)
	{
		let result = new RewardResult();

		let stage = mConfigs.GetStage(stageId);
		if (stage == null) return result;

		// Base gold reward: difficulty * 50 + star bonus
		int32 baseGold = stage.mDifficulty * 50 + starRating * 20;
		mPlayerMgr.AddGold(baseGold);
		result.mGoldGained = baseGold;

		// Base EXP reward: difficulty * 30
		int32 baseExp = stage.mDifficulty * 30;
		result.mLevelsGained = mPlayerMgr.AddHeroExp(baseExp);
		result.mExpGained = baseExp;

		// Record stage clear
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
}

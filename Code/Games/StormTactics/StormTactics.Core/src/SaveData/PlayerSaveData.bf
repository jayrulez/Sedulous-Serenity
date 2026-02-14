namespace StormTactics.Core;

using System;
using System.Collections;
using Sedulous.Serialization;

class PlayerSaveData : ISerializable
{
	// Profile
	public int32 mHeroLevel = 1;
	public int32 mHeroExp;
	public int32 mGold = 500;
	public int32 mGems = 100;
	public int32 mArenaTokens;
	public int32 mGuildTokens;
	public int32 mStamina = 30;
	public int64 mLastStaminaTime;

	// Stage progress
	public int32 mMaxStageClearedId;
	public List<StageStar> mStageStars = new .() ~ DeleteContainerAndItems!(_);

	// Units
	public List<OwnedUnitData> mOwnedUnits = new .() ~ DeleteContainerAndItems!(_);

	// Inventory
	public List<InventorySlot> mInventory = new .() ~ DeleteContainerAndItems!(_);

	// Equipment
	public List<OwnedEquipData> mOwnedEquips = new .() ~ DeleteContainerAndItems!(_);
	public int32 mNextEquipInstanceId = 1;

	// Formations
	public List<FormationPreset> mFormationPresets = new .() ~ DeleteContainerAndItems!(_);
	public int32 mActiveFormationIndex;

	// Shop
	public List<ShopPurchaseRecord> mShopPurchases = new .() ~ DeleteContainerAndItems!(_);
	public int64 mLastShopRefreshTime;

	// Gacha
	public int32 mGachaPityCounter;

	// Daily challenges
	public int64 mLastDailyChallengeTime;
	public int32 mDailyChallengeDay;
	public int32 mDailyChallengesCompleted; // Bitmask: bit 0/1/2 = challenge 1/2/3

	// Boss Rush
	public int32 mBossesDefeated; // Bitmask: bit N = boss index N first-cleared

	// Settings
	public GameSettings mGameSettings = new .() ~ delete _;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("HeroLevel", ref mHeroLevel);
		s.Int32("HeroExp", ref mHeroExp);
		s.Int32("Gold", ref mGold);
		s.Int32("Gems", ref mGems);
		s.Int32("ArenaTokens", ref mArenaTokens);
		s.Int32("GuildTokens", ref mGuildTokens);
		s.Int32("Stamina", ref mStamina);
		s.Int64("LastStaminaTime", ref mLastStaminaTime);

		s.Int32("MaxStageClearedId", ref mMaxStageClearedId);
		s.ObjectList("StageStars", mStageStars);

		s.ObjectList("OwnedUnits", mOwnedUnits);
		s.ObjectList("Inventory", mInventory);
		s.ObjectList("OwnedEquips", mOwnedEquips);
		s.Int32("NextEquipInstanceId", ref mNextEquipInstanceId);

		s.ObjectList("FormationPresets", mFormationPresets);
		s.Int32("ActiveFormationIndex", ref mActiveFormationIndex);

		s.ObjectList("ShopPurchases", mShopPurchases);
		s.Int64("LastShopRefreshTime", ref mLastShopRefreshTime);
		s.Int32("GachaPityCounter", ref mGachaPityCounter);
		s.Int64("LastDailyChallengeTime", ref mLastDailyChallengeTime);
		s.Int32("DailyChallengeDay", ref mDailyChallengeDay);
		s.Int32("DailyChallengesCompleted", ref mDailyChallengesCompleted);
		s.Int32("BossesDefeated", ref mBossesDefeated);
		s.Object("GameSettings", ref mGameSettings);

		return .Ok;
	}

	// --- Convenience accessors ---

	/// Get best star rating for a stage. Returns 0 if never cleared.
	public int32 GetBestStars(int32 stageId)
	{
		for (let ss in mStageStars)
			if (ss.mStageId == stageId) return ss.mStars;
		return 0;
	}

	/// Record a stage clear with star rating. Updates if better.
	public void RecordStageClear(int32 stageId, int32 stars)
	{
		for (let ss in mStageStars)
		{
			if (ss.mStageId == stageId)
			{
				if (stars > ss.mStars)
					ss.mStars = stars;
				return;
			}
		}
		let entry = new StageStar();
		entry.mStageId = stageId;
		entry.mStars = stars;
		mStageStars.Add(entry);
	}

	/// Get sweep count for a stage.
	public int32 GetSweepCount(int32 stageId)
	{
		for (let ss in mStageStars)
			if (ss.mStageId == stageId) return ss.mSweepCount;
		return 0;
	}

	/// Increment sweep count for a stage.
	public void IncrementSweepCount(int32 stageId)
	{
		for (let ss in mStageStars)
		{
			if (ss.mStageId == stageId)
			{
				ss.mSweepCount++;
				return;
			}
		}
	}

	// --- Hard mode accessors ---

	/// Get best hard mode star rating for a stage. Returns 0 if never cleared on hard.
	public int32 GetHardStars(int32 stageId)
	{
		for (let ss in mStageStars)
			if (ss.mStageId == stageId) return ss.mHardStars;
		return 0;
	}

	/// Record a hard mode stage clear with star rating. Updates if better.
	public void RecordHardClear(int32 stageId, int32 stars)
	{
		for (let ss in mStageStars)
		{
			if (ss.mStageId == stageId)
			{
				if (stars > ss.mHardStars)
					ss.mHardStars = stars;
				return;
			}
		}
		let entry = new StageStar();
		entry.mStageId = stageId;
		entry.mHardStars = stars;
		mStageStars.Add(entry);
	}

	/// Get hard mode sweep count for a stage.
	public int32 GetHardSweepCount(int32 stageId)
	{
		for (let ss in mStageStars)
			if (ss.mStageId == stageId) return ss.mHardSweepCount;
		return 0;
	}

	/// Increment hard mode sweep count for a stage.
	public void IncrementHardSweepCount(int32 stageId)
	{
		for (let ss in mStageStars)
		{
			if (ss.mStageId == stageId)
			{
				ss.mHardSweepCount++;
				return;
			}
		}
	}

	/// Find owned unit data by unit config ID. Returns null if not owned.
	public OwnedUnitData GetOwnedUnit(int32 unitId)
	{
		for (let unit in mOwnedUnits)
			if (unit.mUnitId == unitId) return unit;
		return null;
	}

	/// Find inventory slot for an item. Returns null if not in inventory.
	public InventorySlot GetInventorySlot(int32 itemId)
	{
		for (let slot in mInventory)
			if (slot.mItemId == itemId) return slot;
		return null;
	}

	/// Find owned equip by instance ID. Returns null if not found.
	public OwnedEquipData GetOwnedEquip(int32 instanceId)
	{
		for (let equip in mOwnedEquips)
			if (equip.mInstanceId == instanceId) return equip;
		return null;
	}

	/// Get purchase count for a shop item. Returns 0 if never purchased.
	public int32 GetShopPurchaseCount(int32 shopItemId)
	{
		for (let record in mShopPurchases)
			if (record.mShopItemId == shopItemId) return record.mPurchaseCount;
		return 0;
	}

	/// Increment purchase count for a shop item.
	public void IncrementShopPurchase(int32 shopItemId)
	{
		for (let record in mShopPurchases)
		{
			if (record.mShopItemId == shopItemId)
			{
				record.mPurchaseCount++;
				return;
			}
		}
		let record = new ShopPurchaseRecord();
		record.mShopItemId = shopItemId;
		record.mPurchaseCount = 1;
		mShopPurchases.Add(record);
	}
}

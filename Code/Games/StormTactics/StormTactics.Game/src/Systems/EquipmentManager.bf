namespace StormTactics.Game;

using System;
using StormTactics.Core;

/// Manages equipping/unequipping gear, enhancement, and calculating stat bonuses.
class EquipmentManager
{
	public const int32 MAX_ENHANCE_LEVEL = 10;
	public const int32 ENHANCE_STONE_ITEM_ID = 1012;
	public const int32 ENHANCE_STONES_PER_LEVEL = 3;

	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;
	private PlayerManager mPlayerMgr;
	private InventoryManager mInvMgr;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;
	}

	/// Set manager references for enhancement costs.
	public void SetManagers(PlayerManager playerMgr, InventoryManager invMgr)
	{
		mPlayerMgr = playerMgr;
		mInvMgr = invMgr;
	}

	/// Equip an owned equip (by instance ID) to a unit in the given slot.
	/// Returns true if successful.
	public bool Equip(int32 unitId, int32 equipInstanceId, EquipSlot slot)
	{
		let unit = mSave.GetOwnedUnit(unitId);
		if (unit == null) return false;

		let equip = mSave.GetOwnedEquip(equipInstanceId);
		if (equip == null) return false;

		let config = mConfigs.GetEquip(equip.mEquipId);
		if (config == null) return false;

		// Verify slot matches
		if (config.mSlot != slot) return false;

		// Unequip from any other unit that has this equip
		for (let other in mSave.mOwnedUnits)
		{
			if (other.mEquipWeaponId == equipInstanceId) other.mEquipWeaponId = 0;
			if (other.mEquipArmorId == equipInstanceId) other.mEquipArmorId = 0;
			if (other.mEquipAccessoryId == equipInstanceId) other.mEquipAccessoryId = 0;
		}

		// Assign to the target slot
		switch (slot)
		{
		case .Weapon:    unit.mEquipWeaponId = equipInstanceId;
		case .Armor:     unit.mEquipArmorId = equipInstanceId;
		case .Accessory: unit.mEquipAccessoryId = equipInstanceId;
		}

		return true;
	}

	/// Unequip an item from a unit's slot.
	public void Unequip(int32 unitId, EquipSlot slot)
	{
		let unit = mSave.GetOwnedUnit(unitId);
		if (unit == null) return;

		switch (slot)
		{
		case .Weapon:    unit.mEquipWeaponId = 0;
		case .Armor:     unit.mEquipArmorId = 0;
		case .Accessory: unit.mEquipAccessoryId = 0;
		}
	}

	/// Get the equip instance ID in a unit's slot (0 = empty).
	public int32 GetEquipInSlot(int32 unitId, EquipSlot slot)
	{
		let unit = mSave.GetOwnedUnit(unitId);
		if (unit == null) return 0;

		switch (slot)
		{
		case .Weapon:    return unit.mEquipWeaponId;
		case .Armor:     return unit.mEquipArmorId;
		case .Accessory: return unit.mEquipAccessoryId;
		default: return 0;
		}
	}

	/// Check if an equip instance is currently equipped by any unit.
	public bool IsEquipped(int32 equipInstanceId)
	{
		for (let unit in mSave.mOwnedUnits)
		{
			if (unit.mEquipWeaponId == equipInstanceId) return true;
			if (unit.mEquipArmorId == equipInstanceId) return true;
			if (unit.mEquipAccessoryId == equipInstanceId) return true;
		}
		return false;
	}

	/// Get aggregate stat bonuses from all equipment on a unit.
	public void GetEquipStatBonuses(int32 unitId,
		out float hpFlat, out float hpPct,
		out float dmgFlat, out float dmgPct,
		out float defFlat, out float defPct,
		out float spdFlat, out float spdPct)
	{
		hpFlat = 0; hpPct = 0;
		dmgFlat = 0; dmgPct = 0;
		defFlat = 0; defPct = 0;
		spdFlat = 0; spdPct = 0;

		let unit = mSave.GetOwnedUnit(unitId);
		if (unit == null) return;

		int32[3] slotIds = .(unit.mEquipWeaponId, unit.mEquipArmorId, unit.mEquipAccessoryId);
		for (let instanceId in slotIds)
		{
			if (instanceId == 0) continue;
			let equip = mSave.GetOwnedEquip(instanceId);
			if (equip == null) continue;
			let config = mConfigs.GetEquip(equip.mEquipId);
			if (config == null) continue;

			// Enhancement multiplier: +10% per enhance level
			let enhanceMult = 1.0f + (float)equip.mEnhanceLevel * 0.1f;

			for (let mod in config.mStatBonuses)
			{
				switch (mod.mAttribute)
				{
				case .HP:          hpFlat += mod.mFlatValue * enhanceMult; hpPct += mod.mPercentValue * enhanceMult;
				case .Damage:      dmgFlat += mod.mFlatValue * enhanceMult; dmgPct += mod.mPercentValue * enhanceMult;
				case .Defense:     defFlat += mod.mFlatValue * enhanceMult; defPct += mod.mPercentValue * enhanceMult;
				case .ActionSpeed: spdFlat += mod.mFlatValue * enhanceMult; spdPct += mod.mPercentValue * enhanceMult;
				default:
				}
			}
		}
	}

	/// Add a new equip to the player's inventory. Returns the new instance ID.
	public int32 AddEquip(int32 equipId)
	{
		let instanceId = mSave.mNextEquipInstanceId;
		mSave.mNextEquipInstanceId++;

		let equip = new OwnedEquipData();
		equip.mInstanceId = instanceId;
		equip.mEquipId = equipId;
		equip.mEnhanceLevel = 0;
		mSave.mOwnedEquips.Add(equip);

		return instanceId;
	}

	// --- Enhancement ---

	/// Get the gold cost to enhance an equip at its current level.
	public int32 GetEnhanceCost(int32 equipInstanceId)
	{
		let equip = mSave.GetOwnedEquip(equipInstanceId);
		if (equip == null || equip.mEnhanceLevel >= MAX_ENHANCE_LEVEL) return 0;

		// Gold cost scales: 100 * (currentLevel + 1)
		return 100 * (equip.mEnhanceLevel + 1);
	}

	/// Check if an equip can be enhanced right now.
	public bool CanEnhance(int32 equipInstanceId)
	{
		let equip = mSave.GetOwnedEquip(equipInstanceId);
		if (equip == null || equip.mEnhanceLevel >= MAX_ENHANCE_LEVEL) return false;
		if (mPlayerMgr == null || mInvMgr == null) return false;

		let goldCost = GetEnhanceCost(equipInstanceId);
		if (mSave.mGold < goldCost) return false;
		if (!mInvMgr.HasItem(ENHANCE_STONE_ITEM_ID, ENHANCE_STONES_PER_LEVEL)) return false;

		return true;
	}

	/// Try to enhance an equip. Costs gold + Enhancement Stones.
	/// Returns true if successful.
	public bool TryEnhance(int32 equipInstanceId)
	{
		if (!CanEnhance(equipInstanceId)) return false;

		let equip = mSave.GetOwnedEquip(equipInstanceId);
		if (equip == null) return false;

		let goldCost = GetEnhanceCost(equipInstanceId);
		if (!mPlayerMgr.TrySpendGold(goldCost)) return false;
		mInvMgr.RemoveItem(ENHANCE_STONE_ITEM_ID, ENHANCE_STONES_PER_LEVEL);

		equip.mEnhanceLevel++;
		Console.WriteLine("[Equipment] Enhanced equip {} to +{}", equipInstanceId, equip.mEnhanceLevel);
		return true;
	}
}

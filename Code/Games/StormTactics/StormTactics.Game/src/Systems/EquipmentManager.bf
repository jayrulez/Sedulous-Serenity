namespace StormTactics.Game;

using System;
using StormTactics.Core;

/// Manages equipping/unequipping gear and calculating stat bonuses.
class EquipmentManager
{
	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;
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

			for (let mod in config.mStatBonuses)
			{
				switch (mod.mAttribute)
				{
				case .HP:          hpFlat += mod.mFlatValue; hpPct += mod.mPercentValue;
				case .Damage:      dmgFlat += mod.mFlatValue; dmgPct += mod.mPercentValue;
				case .Defense:     defFlat += mod.mFlatValue; defPct += mod.mPercentValue;
				case .ActionSpeed: spdFlat += mod.mFlatValue; spdPct += mod.mPercentValue;
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
}

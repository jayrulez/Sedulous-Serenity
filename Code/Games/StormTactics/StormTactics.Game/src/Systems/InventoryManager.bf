namespace StormTactics.Game;

using System;
using StormTactics.Core;

/// Manages the player's item inventory with stacking.
class InventoryManager
{
	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;
	}

	/// Add items to inventory, respecting stack limits. Returns actual amount added.
	public int32 AddItem(int32 itemId, int32 quantity)
	{
		if (quantity <= 0) return 0;

		let config = mConfigs.GetItem(itemId);
		int32 stackMax = config != null ? config.mStackMax : 999;

		let slot = mSave.GetInventorySlot(itemId);
		if (slot != null)
		{
			int32 canAdd = Math.Max(0, stackMax - slot.mQuantity);
			int32 toAdd = Math.Min(quantity, canAdd);
			slot.mQuantity += toAdd;
			return toAdd;
		}
		else
		{
			let newSlot = new InventorySlot();
			newSlot.mItemId = itemId;
			newSlot.mQuantity = Math.Min(quantity, stackMax);
			mSave.mInventory.Add(newSlot);
			return newSlot.mQuantity;
		}
	}

	/// Remove items from inventory. Returns actual amount removed.
	public int32 RemoveItem(int32 itemId, int32 quantity)
	{
		if (quantity <= 0) return 0;

		let slot = mSave.GetInventorySlot(itemId);
		if (slot == null) return 0;

		int32 toRemove = Math.Min(quantity, slot.mQuantity);
		slot.mQuantity -= toRemove;

		// Remove empty slot
		if (slot.mQuantity <= 0)
		{
			mSave.mInventory.Remove(slot);
			delete slot;
		}

		return toRemove;
	}

	/// Check if the player has at least the given quantity of an item.
	public bool HasItem(int32 itemId, int32 quantity = 1)
	{
		let slot = mSave.GetInventorySlot(itemId);
		return slot != null && slot.mQuantity >= quantity;
	}

	/// Get the quantity of an item in inventory.
	public int32 GetItemCount(int32 itemId)
	{
		let slot = mSave.GetInventorySlot(itemId);
		return slot != null ? slot.mQuantity : 0;
	}
}

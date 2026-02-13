namespace StormTactics.Game;

using System;
using StormTactics.Core;

/// Manages the player's item inventory with stacking, usage, and selling.
class InventoryManager
{
	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;
	private PlayerManager mPlayerMgr;
	private RosterManager mRosterMgr;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;
	}

	/// Set manager references for item usage effects.
	public void SetManagers(PlayerManager playerMgr, RosterManager rosterMgr)
	{
		mPlayerMgr = playerMgr;
		mRosterMgr = rosterMgr;
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

	/// Use a consumable item. targetUnitId is required for AddUnitExp effect.
	/// Returns true if the item was consumed successfully.
	public bool UseItem(int32 itemId, int32 targetUnitId = 0)
	{
		let config = mConfigs.GetItem(itemId);
		if (config == null || config.mType != .Consumable) return false;
		if (config.mConsumableEffect == .None) return false;
		if (!HasItem(itemId)) return false;

		switch (config.mConsumableEffect)
		{
		case .RestoreStamina:
			if (mPlayerMgr == null) return false;
			if (mPlayerMgr.MaxStamina <= mSave.mStamina) return false; // Already full
			mPlayerMgr.AddStamina(config.mEffectValue);

		case .AddUnitExp:
			if (mRosterMgr == null || targetUnitId <= 0) return false;
			if (!mRosterMgr.HasUnit(targetUnitId)) return false;
			mRosterMgr.AddUnitExp(targetUnitId, config.mEffectValue);

		case .AddGold:
			if (mPlayerMgr == null) return false;
			mPlayerMgr.AddGold(config.mEffectValue);

		default:
			return false;
		}

		RemoveItem(itemId, 1);
		Console.WriteLine("[Inventory] Used item {} ({})", config.mName, config.mConsumableEffect);
		return true;
	}

	/// Check if an item can be used (is consumable with valid effect).
	public bool CanUseItem(int32 itemId)
	{
		let config = mConfigs.GetItem(itemId);
		if (config == null || config.mType != .Consumable) return false;
		return config.mConsumableEffect != .None;
	}

	/// Check if an item needs a target unit to use (e.g. EXP potions).
	public bool ItemNeedsTarget(int32 itemId)
	{
		let config = mConfigs.GetItem(itemId);
		if (config == null) return false;
		return config.mConsumableEffect == .AddUnitExp;
	}

	/// Sell one unit of an item for gold. Returns gold gained (0 if not sellable).
	public int32 SellItem(int32 itemId, int32 quantity = 1)
	{
		let config = mConfigs.GetItem(itemId);
		if (config == null || config.mSellPrice <= 0) return 0;
		if (config.mType == .Currency) return 0; // Can't sell currency
		if (!HasItem(itemId, quantity)) return 0;

		let removed = RemoveItem(itemId, quantity);
		let gold = config.mSellPrice * removed;
		if (mPlayerMgr != null)
			mPlayerMgr.AddGold(gold);

		Console.WriteLine("[Inventory] Sold {}x {} for {} gold", removed, config.mName, gold);
		return gold;
	}

	/// Check if an item can be sold.
	public bool CanSellItem(int32 itemId)
	{
		let config = mConfigs.GetItem(itemId);
		if (config == null) return false;
		return config.mSellPrice > 0 && config.mType != .Currency;
	}
}

namespace StormTactics.Game;

using System;
using StormTactics.Core;

/// Manages shop purchases, currency spending, purchase limits, and daily refresh.
class ShopManager
{
	public const int64 SHOP_REFRESH_SECONDS = 86400; // 24 hours

	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;
	private PlayerManager mPlayerMgr;
	private InventoryManager mInvMgr;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs, PlayerManager playerMgr, InventoryManager invMgr)
	{
		mSave = save;
		mConfigs = configs;
		mPlayerMgr = playerMgr;
		mInvMgr = invMgr;
	}

	/// Check and apply daily shop refresh if enough time has passed.
	/// Call on game load and when entering the shop screen.
	public bool CheckRefresh()
	{
		let now = GetCurrentTimestamp();

		if (mSave.mLastShopRefreshTime == 0)
		{
			mSave.mLastShopRefreshTime = now;
			return false;
		}

		let elapsed = now - mSave.mLastShopRefreshTime;
		if (elapsed >= SHOP_REFRESH_SECONDS)
		{
			RefreshShop();
			mSave.mLastShopRefreshTime = now;
			return true;
		}

		return false;
	}

	/// Force-refresh the shop: reset all purchase counts.
	public void RefreshShop()
	{
		for (let record in mSave.mShopPurchases)
			delete record;
		mSave.mShopPurchases.Clear();
		Console.WriteLine("[Shop] Shop refreshed - all purchase counts reset");
	}

	/// Seconds until the next automatic shop refresh. Returns 0 if refresh is due.
	public int32 SecondsUntilRefresh
	{
		get
		{
			if (mSave.mLastShopRefreshTime == 0) return 0;
			let now = GetCurrentTimestamp();
			let elapsed = now - mSave.mLastShopRefreshTime;
			return (int32)Math.Max(0, SHOP_REFRESH_SECONDS - elapsed);
		}
	}

	private static int64 GetCurrentTimestamp()
	{
		return DateTime.UtcNow.ToFileTime() / 10000000 - 11644473600;
	}

	/// Check if a shop item can be purchased.
	public bool CanPurchase(int32 shopItemId)
	{
		let config = mConfigs.GetShopItem(shopItemId);
		if (config == null) return false;

		// Check purchase limit
		if (config.mPurchaseLimit > 0)
		{
			if (mSave.GetShopPurchaseCount(shopItemId) >= config.mPurchaseLimit)
				return false;
		}

		// Check currency
		return HasCurrency(config.mCurrencyType, config.mCost);
	}

	/// Try to purchase a shop item. Returns true if successful.
	public bool TryPurchase(int32 shopItemId)
	{
		if (!CanPurchase(shopItemId)) return false;

		let config = mConfigs.GetShopItem(shopItemId);
		if (config == null) return false;

		// Spend currency
		if (!SpendCurrency(config.mCurrencyType, config.mCost))
			return false;

		// Add item to inventory
		mInvMgr.AddItem(config.mItemId, config.mQuantity);

		// Record purchase
		mSave.IncrementShopPurchase(shopItemId);

		Console.WriteLine("[Shop] Purchased shop item {} (item:{} x{})", shopItemId, config.mItemId, config.mQuantity);
		return true;
	}

	/// Get remaining purchase count for a limited item. Returns -1 for unlimited.
	public int32 GetRemainingPurchases(int32 shopItemId)
	{
		let config = mConfigs.GetShopItem(shopItemId);
		if (config == null) return 0;
		if (config.mPurchaseLimit == 0) return -1; // Unlimited

		return Math.Max(0, config.mPurchaseLimit - mSave.GetShopPurchaseCount(shopItemId));
	}

	/// Check if an item is sold out.
	public bool IsSoldOut(int32 shopItemId)
	{
		let remaining = GetRemainingPurchases(shopItemId);
		return remaining == 0;
	}

	private bool HasCurrency(CurrencyType type, int32 amount)
	{
		switch (type)
		{
		case .Gold:        return mSave.mGold >= amount;
		case .Gems:        return mSave.mGems >= amount;
		case .ArenaTokens: return false; // Not implemented yet
		case .GuildTokens: return false; // Not implemented yet
		default:           return false;
		}
	}

	private bool SpendCurrency(CurrencyType type, int32 amount)
	{
		switch (type)
		{
		case .Gold: return mPlayerMgr.TrySpendGold(amount);
		case .Gems: return mPlayerMgr.TrySpendGems(amount);
		default:    return false;
		}
	}
}

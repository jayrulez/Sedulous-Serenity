namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

class ShopItemConfig : ISerializable
{
	public int32 mId;
	public int32 mItemId;
	public int32 mQuantity = 1;
	public int32 mCost;
	public CurrencyType mCurrencyType;
	public int32 mPurchaseLimit; // 0 = unlimited
	public int32 mRefreshGroup;  // Items in the same group refresh together
	public bool mFeatured;       // Highlighted in the shop UI

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Id", ref mId);
		s.Int32("ItemId", ref mItemId);
		s.Int32("Quantity", ref mQuantity);
		s.Int32("Cost", ref mCost);
		s.Enum("CurrencyType", ref mCurrencyType);
		s.Int32("PurchaseLimit", ref mPurchaseLimit);
		s.Int32("RefreshGroup", ref mRefreshGroup);
		s.Bool("Featured", ref mFeatured);
		return .Ok;
	}
}

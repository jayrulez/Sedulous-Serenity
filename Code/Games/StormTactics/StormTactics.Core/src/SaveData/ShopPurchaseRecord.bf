namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

class ShopPurchaseRecord : ISerializable
{
	public int32 mShopItemId;
	public int32 mPurchaseCount;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("ShopItemId", ref mShopItemId);
		s.Int32("PurchaseCount", ref mPurchaseCount);
		return .Ok;
	}
}

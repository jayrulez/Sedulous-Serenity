namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

class InventorySlot : ISerializable
{
	public int32 mItemId;
	public int32 mQuantity;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("ItemId", ref mItemId);
		s.Int32("Quantity", ref mQuantity);
		return .Ok;
	}
}

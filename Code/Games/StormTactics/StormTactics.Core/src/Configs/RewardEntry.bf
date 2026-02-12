namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

/// A reward item with quantity and drop chance.
class RewardEntry : ISerializable
{
	public int32 mItemId;
	public int32 mQuantity = 1;
	public float mDropChance = 1.0f; // 1.0 = guaranteed

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("ItemId", ref mItemId);
		s.Int32("Quantity", ref mQuantity);
		s.Float("DropChance", ref mDropChance);
		return .Ok;
	}
}

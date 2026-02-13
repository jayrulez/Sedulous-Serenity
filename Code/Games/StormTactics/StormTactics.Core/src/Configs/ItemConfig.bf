namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

class ItemConfig : ISerializable
{
	public int32 mId;
	public String mName = new .() ~ delete _;
	public String mDescription = new .() ~ delete _;
	public String mIcon = new .() ~ delete _;
	public ItemType mType;
	public int32 mStackMax = 999;
	public ConsumableEffect mConsumableEffect;
	public int32 mEffectValue;
	public int32 mSellPrice;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Id", ref mId);
		s.String("Name", mName);
		s.String("Description", mDescription);
		s.String("Icon", mIcon);
		s.Enum("Type", ref mType);
		s.Int32("StackMax", ref mStackMax);
		s.Enum("ConsumableEffect", ref mConsumableEffect);
		s.Int32("EffectValue", ref mEffectValue);
		s.Int32("SellPrice", ref mSellPrice);
		return .Ok;
	}
}

namespace StormTactics.Core;

using System;
using System.Collections;
using Sedulous.Serialization;

class EquipConfig : ISerializable
{
	public int32 mId;
	public String mName = new .() ~ delete _;
	public String mDescription = new .() ~ delete _;
	public String mIcon = new .() ~ delete _;
	public EquipSlot mSlot;
	public Rarity mRarity;
	public int32 mRequiredLevel;
	public List<StatModifier> mStatBonuses = new .() ~ DeleteContainerAndItems!(_);

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Id", ref mId);
		s.String("Name", mName);
		s.String("Description", mDescription);
		s.String("Icon", mIcon);
		s.Enum("Slot", ref mSlot);
		s.Enum("Rarity", ref mRarity);
		s.Int32("RequiredLevel", ref mRequiredLevel);
		s.ObjectList("StatBonuses", mStatBonuses);
		return .Ok;
	}
}

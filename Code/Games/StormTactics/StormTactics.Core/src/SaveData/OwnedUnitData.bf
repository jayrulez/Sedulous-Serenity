namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

class OwnedUnitData : ISerializable
{
	public int32 mUnitId;
	public int32 mStarLevel = 1;
	public int32 mShards;
	public int32 mLevel = 1;
	public int32 mExp;
	public int32 mEquipWeaponId;    // OwnedEquipData instance ID (0 = none)
	public int32 mEquipArmorId;
	public int32 mEquipAccessoryId;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("UnitId", ref mUnitId);
		s.Int32("StarLevel", ref mStarLevel);
		s.Int32("Shards", ref mShards);
		s.Int32("Level", ref mLevel);
		s.Int32("Exp", ref mExp);
		s.Int32("EquipWeaponId", ref mEquipWeaponId);
		s.Int32("EquipArmorId", ref mEquipArmorId);
		s.Int32("EquipAccessoryId", ref mEquipAccessoryId);
		return .Ok;
	}
}

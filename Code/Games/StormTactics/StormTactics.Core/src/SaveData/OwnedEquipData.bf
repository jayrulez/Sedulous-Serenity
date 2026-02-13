namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

class OwnedEquipData : ISerializable
{
	public int32 mInstanceId;   // Unique per save, auto-incremented
	public int32 mEquipId;      // References EquipConfig.mId
	public int32 mEnhanceLevel;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("InstanceId", ref mInstanceId);
		s.Int32("EquipId", ref mEquipId);
		s.Int32("EnhanceLevel", ref mEnhanceLevel);
		return .Ok;
	}
}

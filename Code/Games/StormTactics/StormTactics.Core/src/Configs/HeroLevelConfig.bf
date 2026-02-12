namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

class HeroLevelConfig : ISerializable
{
	public int32 mLevel;
	public int32 mExpRequired;
	public int32 mMaxStamina;
	public int32 mMaxFormationSlots;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Level", ref mLevel);
		s.Int32("ExpRequired", ref mExpRequired);
		s.Int32("MaxStamina", ref mMaxStamina);
		s.Int32("MaxFormationSlots", ref mMaxFormationSlots);
		return .Ok;
	}
}

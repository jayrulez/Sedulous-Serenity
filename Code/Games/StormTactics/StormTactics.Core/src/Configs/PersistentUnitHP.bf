namespace StormTactics.Core;

using Sedulous.Serialization;

/// Stores a unit's HP state for persistence across sequential battles (Tower/Crusade).
class PersistentUnitHP : ISerializable
{
	public int32 mUnitId;
	public int32 mCurrentHP;
	public int32 mMaxHP;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("UnitId", ref mUnitId);
		s.Int32("CurrentHP", ref mCurrentHP);
		s.Int32("MaxHP", ref mMaxHP);
		return .Ok;
	}
}

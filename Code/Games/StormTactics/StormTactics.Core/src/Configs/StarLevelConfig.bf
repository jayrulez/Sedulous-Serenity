namespace StormTactics.Core;

using System;
using System.Collections;
using Sedulous.Serialization;

class StarLevelConfig : ISerializable
{
	public int32 mUnitId;
	public int32 mStarLevel;
	public int32 mShardsRequired;
	public float mHPMultiplier = 1.0f;
	public float mDamageMultiplier = 1.0f;
	public float mDefenseMultiplier = 1.0f;
	public List<int32> mUnlockedSkillIds = new .() ~ delete _;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("UnitId", ref mUnitId);
		s.Int32("StarLevel", ref mStarLevel);
		s.Int32("ShardsRequired", ref mShardsRequired);
		s.Float("HPMultiplier", ref mHPMultiplier);
		s.Float("DamageMultiplier", ref mDamageMultiplier);
		s.Float("DefenseMultiplier", ref mDefenseMultiplier);
		s.ArrayInt32("UnlockedSkillIds", mUnlockedSkillIds);
		return .Ok;
	}
}

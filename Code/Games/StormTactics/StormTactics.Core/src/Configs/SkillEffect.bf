namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

/// A single effect within a skill (damage, heal, apply buff, etc.)
class SkillEffect : ISerializable
{
	public SkillEffectType mType;
	public float mValue;       // Damage multiplier, heal amount, etc.
	public int32 mBuffId;      // Buff to apply (if type == ApplyBuff)
	public int32 mSummonUnitId; // Unit to summon (if type == Summon)
	public int32 mDispelCount; // Number of buffs to dispel (if type == Dispel)

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Enum("Type", ref mType);
		s.Float("Value", ref mValue);
		s.Int32("BuffId", ref mBuffId);
		s.Int32("SummonUnitId", ref mSummonUnitId);
		s.Int32("DispelCount", ref mDispelCount);
		return .Ok;
	}
}

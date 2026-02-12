namespace StormTactics.Core;

using System;
using System.Collections;
using Sedulous.Serialization;

class SkillConfig : ISerializable
{
	public int32 mId;
	public String mName = new .() ~ delete _;
	public String mDescription = new .() ~ delete _;
	public String mIcon = new .() ~ delete _;
	public SkillMoment mMoment;
	public SkillTarget mTarget;
	public int32 mCooldown;        // Turns between uses (0 = no cooldown)
	public float mChance = 1.0f;   // Proc rate (1.0 = always)
	public int32 mMaxUsesPerBattle; // 0 = unlimited
	public List<SkillEffect> mEffects = new .() ~ DeleteContainerAndItems!(_);

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Id", ref mId);
		s.String("Name", mName);
		s.String("Description", mDescription);
		s.String("Icon", mIcon);
		s.Enum("Moment", ref mMoment);
		s.Enum("Target", ref mTarget);
		s.Int32("Cooldown", ref mCooldown);
		s.Float("Chance", ref mChance);
		s.Int32("MaxUsesPerBattle", ref mMaxUsesPerBattle);
		s.ObjectList("Effects", mEffects);
		return .Ok;
	}
}

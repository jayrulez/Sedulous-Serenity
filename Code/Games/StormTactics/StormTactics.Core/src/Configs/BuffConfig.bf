namespace StormTactics.Core;

using System;
using System.Collections;
using Sedulous.Serialization;

class BuffConfig : ISerializable
{
	public int32 mId;
	public String mName = new .() ~ delete _;
	public String mDescription = new .() ~ delete _;
	public String mIcon = new .() ~ delete _;
	public BuffFlag mFlag;
	public BuffTag mTag;
	public int32 mDuration;       // Turns (0 = permanent until dispelled)
	public bool mCanDispel = true;
	public float mDotDamage;      // Damage per turn (negative = damage)
	public float mHotHeal;        // Heal per turn
	public List<StatModifier> mStatModifiers = new .() ~ DeleteContainerAndItems!(_);

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Id", ref mId);
		s.String("Name", mName);
		s.String("Description", mDescription);
		s.String("Icon", mIcon);
		s.Enum("Flag", ref mFlag);
		s.Enum("Tag", ref mTag);
		s.Int32("Duration", ref mDuration);
		s.Bool("CanDispel", ref mCanDispel);
		s.Float("DotDamage", ref mDotDamage);
		s.Float("HotHeal", ref mHotHeal);
		s.ObjectList("StatModifiers", mStatModifiers);
		return .Ok;
	}
}

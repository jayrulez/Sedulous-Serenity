namespace StormTactics.Core;

using System;
using System.Collections;
using Sedulous.Serialization;

class BossPhase : ISerializable
{
	public float mHPThreshold;  // 0.0-1.0 (e.g., 0.5 = 50% HP)
	public int32 mBuffId;       // Buff to apply when threshold crossed
	public bool mTriggered;     // Runtime state — not serialized

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Float("HPThreshold", ref mHPThreshold);
		s.Int32("BuffId", ref mBuffId);
		return .Ok;
	}
}

class BossTemplate : ISerializable
{
	public int32 mId;
	public String mName = new .() ~ delete _;
	public String mDescription = new .() ~ delete _;
	public String mMechanicHint = new .() ~ delete _;
	public int32 mUnitId;
	public float mHPScale = 1.0f;
	public float mDamageScale = 1.0f;
	public float mDefenseScale = 1.0f;
	public List<BossPhase> mPhases = new .() ~ DeleteContainerAndItems!(_);
	public int32 mGoldReward;
	public int32 mExpReward;
	public int32 mFirstClearGems;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Id", ref mId);
		s.String("Name", mName);
		s.String("Description", mDescription);
		s.String("MechanicHint", mMechanicHint);
		s.Int32("UnitId", ref mUnitId);
		s.Float("HPScale", ref mHPScale);
		s.Float("DamageScale", ref mDamageScale);
		s.Float("DefenseScale", ref mDefenseScale);
		s.ObjectList("Phases", mPhases);
		s.Int32("GoldReward", ref mGoldReward);
		s.Int32("ExpReward", ref mExpReward);
		s.Int32("FirstClearGems", ref mFirstClearGems);
		return .Ok;
	}
}

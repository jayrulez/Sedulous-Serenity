namespace StormTactics.Core;

using System;
using System.Collections;
using Sedulous.Serialization;

class UnitConfig : ISerializable
{
	public int32 mId;
	public String mName = new .() ~ delete _;
	public Rarity mRarity;
	public UnitClass mUnitClass;
	public UnitRace mRace;
	public int32 mSoldierHP;
	public int32 mSoldierCount;
	public int32 mDefense;
	public int32 mSoldierDamage;
	public DamageType mDamageType;
	public bool mIsRanged;
	public int32 mAttackRange = 1;
	public AttackPattern mAttackPattern;
	public MoveType mMoveType;
	public int32 mMoveRange = 1;
	public int32 mActionSpeed = 80;
	public List<int32> mSkillIds = new .() ~ delete _;
	public String mIcon = new .() ~ delete _;
	public String mModelName = new .() ~ delete _;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Id", ref mId);
		s.String("Name", mName);
		s.Enum("Rarity", ref mRarity);
		s.Enum("UnitClass", ref mUnitClass);
		s.Enum("Race", ref mRace);
		s.Int32("SoldierHP", ref mSoldierHP);
		s.Int32("SoldierCount", ref mSoldierCount);
		s.Int32("Defense", ref mDefense);
		s.Int32("SoldierDamage", ref mSoldierDamage);
		s.Enum("DamageType", ref mDamageType);
		s.Bool("IsRanged", ref mIsRanged);
		s.Int32("AttackRange", ref mAttackRange);
		s.Enum("AttackPattern", ref mAttackPattern);
		s.Enum("MoveType", ref mMoveType);
		s.Int32("MoveRange", ref mMoveRange);
		s.Int32("ActionSpeed", ref mActionSpeed);
		s.ArrayInt32("SkillIds", mSkillIds);
		s.String("Icon", mIcon);
		s.String("ModelName", mModelName);
		return .Ok;
	}
}

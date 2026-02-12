namespace StormTactics.Core;

using System;
using System.Collections;
using Sedulous.Serialization;

class StageConfig : ISerializable
{
	public int32 mId;
	public String mName = new .() ~ delete _;
	public int32 mChapter;
	public int32 mDifficulty;
	public int32 mStaminaCost = 6;
	public int32 mRecommendedPower;
	public int32 mUnlockStageId; // Previous stage that must be cleared (0 = none)
	public List<FormationSlot> mEnemyFormation = new .() ~ DeleteContainerAndItems!(_);
	public List<RewardEntry> mRewards = new .() ~ DeleteContainerAndItems!(_);

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Id", ref mId);
		s.String("Name", mName);
		s.Int32("Chapter", ref mChapter);
		s.Int32("Difficulty", ref mDifficulty);
		s.Int32("StaminaCost", ref mStaminaCost);
		s.Int32("RecommendedPower", ref mRecommendedPower);
		s.Int32("UnlockStageId", ref mUnlockStageId);
		s.ObjectList("EnemyFormation", mEnemyFormation);
		s.ObjectList("Rewards", mRewards);
		return .Ok;
	}
}

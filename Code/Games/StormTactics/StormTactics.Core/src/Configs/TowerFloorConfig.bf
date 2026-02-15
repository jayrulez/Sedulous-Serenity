namespace StormTactics.Core;

using System;
using System.Collections;
using Sedulous.Serialization;

/// Configuration for a single tower floor — enemies, rewards, difficulty.
class TowerFloorConfig : ISerializable
{
	public int32 mId;
	public String mName = new .() ~ delete _;
	public float mDifficultyScale = 1.0f;
	public List<FormationSlot> mEnemyFormation = new .() ~ DeleteContainerAndItems!(_);
	public int32 mGoldReward;
	public int32 mExpReward;
	public int32 mGemReward;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Id", ref mId);
		s.String("Name", mName);
		s.Float("DifficultyScale", ref mDifficultyScale);
		s.ObjectList("EnemyFormation", mEnemyFormation);
		s.Int32("GoldReward", ref mGoldReward);
		s.Int32("ExpReward", ref mExpReward);
		s.Int32("GemReward", ref mGemReward);
		return .Ok;
	}
}

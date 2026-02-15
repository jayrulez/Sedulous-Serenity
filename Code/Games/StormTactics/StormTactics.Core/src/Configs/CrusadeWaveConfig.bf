namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

/// Configuration for a single crusade wave — references a campaign stage for enemies.
class CrusadeWaveConfig : ISerializable
{
	public int32 mId;
	public String mName = new .() ~ delete _;
	public int32 mStageId;         // Campaign stage to copy enemies from
	public float mDifficultyScale = 1.0f;
	public int32 mGoldReward;
	public int32 mExpReward;
	public int32 mGemReward;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("Id", ref mId);
		s.String("Name", mName);
		s.Int32("StageId", ref mStageId);
		s.Float("DifficultyScale", ref mDifficultyScale);
		s.Int32("GoldReward", ref mGoldReward);
		s.Int32("ExpReward", ref mExpReward);
		s.Int32("GemReward", ref mGemReward);
		return .Ok;
	}
}

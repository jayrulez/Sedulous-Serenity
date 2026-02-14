namespace StormTactics.Core;

using System;
using Sedulous.Serialization;

/// Helper for serializing stage → star rating mapping.
class StageStar : ISerializable
{
	public int32 mStageId;
	public int32 mStars;
	public int32 mSweepCount;
	public int32 mHardStars;       // Best hard mode star rating (0-3)
	public int32 mHardSweepCount;  // Hard mode sweep count

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("StageId", ref mStageId);
		s.Int32("Stars", ref mStars);
		s.Int32("SweepCount", ref mSweepCount);
		s.Int32("HardStars", ref mHardStars);
		s.Int32("HardSweepCount", ref mHardSweepCount);
		return .Ok;
	}
}

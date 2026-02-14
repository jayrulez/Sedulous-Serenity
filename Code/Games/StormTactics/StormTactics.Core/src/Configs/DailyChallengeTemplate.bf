namespace StormTactics.Core;

using System;

enum ChallengeRestrictionType : int32
{
	AllowClasses,      // Only specified UnitClass values allowed
	BlockClasses,      // All classes except specified
	AllowDamageTypes,  // Only specified DamageType values allowed
	AllowRaces         // Only specified UnitRace values allowed
}

class DailyChallengeTemplate
{
	public int32 mId;
	public String mName = new .() ~ delete _;
	public String mDescription = new .() ~ delete _;
	public int32 mStageId;                    // Enemy formation from this stage
	public float mDifficultyScale = 1.0f;     // Enemy stat multiplier
	public ChallengeRestrictionType mRestrictionType;
	public int32 mRestrictionMask;            // Bitmask of allowed/blocked enum values
	public int32 mGoldReward;
	public int32 mExpReward;
	public int32 mGemReward;
}

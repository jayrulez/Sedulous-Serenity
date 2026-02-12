namespace StormTactics.Battle;

using System;
using StormTactics.Core;

/// Runtime instance of a buff/debuff on a unit.
class BuffInstance
{
	public BuffConfig mConfig;
	public int32 mRemainingDuration; // Turns remaining (0 = permanent until dispelled)
	public int32 mSourceUnit;        // Index of the unit that applied it

	public this(BuffConfig config, int32 sourceUnit)
	{
		mConfig = config;
		mRemainingDuration = config.mDuration;
		mSourceUnit = sourceUnit;
	}

	/// Returns true if this buff has expired (duration-based only).
	public bool IsExpired => mConfig.mDuration > 0 && mRemainingDuration <= 0;

	/// Tick one turn. Returns true if still active.
	public bool Tick()
	{
		if (mConfig.mDuration > 0)
			mRemainingDuration--;
		return !IsExpired;
	}
}

namespace StormTactics.Game;

using System;
using System.Collections;
using StormTactics.Core;

/// Manages boss rush mode — loads boss templates from ConfigDatabase,
/// tracks first-clear status via PlayerSaveData bitmask.
class BossRushManager
{
	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;
	private List<BossTemplate> mBossList = new .() ~ delete _;

	public int32 BossCount => (int32)mBossList.Count;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;

		// Collect all boss templates sorted by ID
		for (let boss in configs.Bosses)
			mBossList.Add(boss);
		mBossList.Sort(scope (a, b) => a.mId <=> b.mId);
	}

	public BossTemplate GetBoss(int32 index)
	{
		if (index < 0 || index >= mBossList.Count)
			return null;
		return mBossList[index];
	}

	public bool IsBossDefeated(int32 index) => (mSave.mBossesDefeated & (1 << index)) != 0;

	public void MarkBossDefeated(int32 index)
	{
		mSave.mBossesDefeated |= (1 << index);
	}

	/// Reset triggered state on all phases for a boss (call before starting battle).
	public void ResetPhases(int32 index)
	{
		let boss = GetBoss(index);
		if (boss == null) return;
		for (let phase in boss.mPhases)
			phase.mTriggered = false;
	}
}

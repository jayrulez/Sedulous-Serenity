namespace StormTactics.Game;

using System;
using System.Collections;
using StormTactics.Core;
using StormTactics.Battle;

/// Manages tower mode — 10 sequential floors with persistent HP, daily reset.
class TowerManager
{
	public const int64 DAILY_RESET_SECONDS = 86400;

	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;
	private List<TowerFloorConfig> mFloors = new .() ~ delete _;
	private List<PersistentUnitHP> mSavedHP = new .() ~ DeleteContainerAndItems!(_);

	public int32 FloorCount => (int32)mFloors.Count;
	public int32 CurrentFloor => mSave.mTowerFloor;
	public bool IsComplete => mSave.mTowerFloor >= FloorCount;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;

		for (let floor in configs.TowerFloors)
			mFloors.Add(floor);
		mFloors.Sort(scope (a, b) => a.mId <=> b.mId);

		CheckDailyReset();
	}

	/// Check if a new day has started and reset tower progress.
	public void CheckDailyReset()
	{
		let now = GetCurrentTimestamp();
		let currentDay = (int32)(now / DAILY_RESET_SECONDS);

		if (currentDay != mSave.mTowerDay)
		{
			mSave.mTowerDay = currentDay;
			mSave.mTowerFloor = 0;
			ClearHP();
			Console.WriteLine("[Tower] New day {} — tower reset", currentDay);
		}
	}

	/// Get the floor config at the given 0-based index.
	public TowerFloorConfig GetFloor(int32 index)
	{
		if (index < 0 || index >= mFloors.Count)
			return null;
		return mFloors[index];
	}

	/// Seconds until the next daily reset.
	public int32 SecondsUntilReset
	{
		get
		{
			let now = GetCurrentTimestamp();
			let nextReset = ((now / DAILY_RESET_SECONDS) + 1) * DAILY_RESET_SECONDS;
			return (int32)Math.Max(0, nextReset - now);
		}
	}

	/// Advance to the next floor after victory.
	public void AdvanceFloor()
	{
		mSave.mTowerFloor++;
	}

	/// Capture surviving attacker HP after a battle victory.
	public void CaptureHP(BattleSimulation sim)
	{
		for (let hp in mSavedHP) delete hp;
		mSavedHP.Clear();

		for (int32 i = 0; i < sim.UnitCount; i++)
		{
			let unit = sim.GetUnit(i);
			if (unit == null || unit.mForce != .Attacker) continue;
			let hp = new PersistentUnitHP();
			hp.mUnitId = unit.mConfig.mId;
			hp.mCurrentHP = unit.mAlive ? unit.mCurrentHP : 0;
			hp.mMaxHP = unit.mMaxHP;
			mSavedHP.Add(hp);
		}
	}

	/// Restore saved HP on attacker units after battle Initialize.
	public void RestoreHP(BattleSimulation sim)
	{
		if (mSavedHP.Count == 0) return;

		for (int32 i = 0; i < sim.UnitCount; i++)
		{
			let unit = sim.GetUnit(i);
			if (unit == null || unit.mForce != .Attacker) continue;

			for (let saved in mSavedHP)
			{
				if (saved.mUnitId == unit.mConfig.mId)
				{
					if (saved.mMaxHP > 0)
					{
						float ratio = (float)saved.mCurrentHP / (float)saved.mMaxHP;
						unit.mCurrentHP = Math.Max(1, (int32)(ratio * (float)unit.mMaxHP));
					}
					break;
				}
			}
		}
	}

	/// Check if a unit died in an earlier floor this run.
	public bool IsUnitDead(int32 unitId)
	{
		for (let saved in mSavedHP)
		{
			if (saved.mUnitId == unitId)
				return saved.mCurrentHP <= 0;
		}
		return false;
	}

	/// Clear all saved HP data (on reset or defeat).
	public void ClearHP()
	{
		for (let hp in mSavedHP) delete hp;
		mSavedHP.Clear();
	}

	private static int64 GetCurrentTimestamp()
	{
		return DateTime.UtcNow.ToFileTime() / 10000000 - 11644473600;
	}
}

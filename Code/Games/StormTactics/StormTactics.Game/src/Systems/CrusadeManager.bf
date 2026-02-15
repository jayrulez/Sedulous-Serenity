namespace StormTactics.Game;

using System;
using System.Collections;
using StormTactics.Core;
using StormTactics.Battle;

/// Manages crusade mode — 15 sequential waves with persistent HP, weekly reset.
/// Players have a limited unit pool; dead units stay dead. Enemy HP persists on defeat.
/// Run ends when all available units are exhausted.
class CrusadeManager
{
	public const int64 WEEKLY_RESET_SECONDS = 604800;
	public const int32 MAX_UNIT_POOL = 20;

	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;
	private List<CrusadeWaveConfig> mWaves = new .() ~ delete _;
	private List<PersistentUnitHP> mSavedHP = new .() ~ DeleteContainerAndItems!(_);
	private List<PersistentUnitHP> mSavedDefenderHP = new .() ~ DeleteContainerAndItems!(_);
	private HashSet<int32> mUsedUnitIds = new .() ~ delete _;

	public int32 WaveCount => (int32)mWaves.Count;
	public int32 CurrentWave => mSave.mCrusadeWave;
	public bool IsComplete => mSave.mCrusadeWave >= WaveCount;
	public int32 UsedUnitCount => (int32)mUsedUnitIds.Count;
	public int32 MaxUnitPool => MAX_UNIT_POOL;
	public bool HasSavedDefenderHP => mSavedDefenderHP.Count > 0;

	public void Initialize(PlayerSaveData save, ConfigDatabase configs)
	{
		mSave = save;
		mConfigs = configs;

		for (let wave in configs.CrusadeWaves)
			mWaves.Add(wave);
		mWaves.Sort(scope (a, b) => a.mId <=> b.mId);

		CheckWeeklyReset();
	}

	/// Check if a new week has started and reset crusade progress.
	public void CheckWeeklyReset()
	{
		let now = GetCurrentTimestamp();
		let currentWeek = (int32)(now / WEEKLY_RESET_SECONDS);

		if (currentWeek != mSave.mCrusadeWeek)
		{
			mSave.mCrusadeWeek = currentWeek;
			mSave.mCrusadeWave = 0;
			ClearAll();
			Console.WriteLine("[Crusade] New week {} — crusade reset", currentWeek);
		}
	}

	/// Get the wave config at the given 0-based index.
	public CrusadeWaveConfig GetWave(int32 index)
	{
		if (index < 0 || index >= mWaves.Count)
			return null;
		return mWaves[index];
	}

	/// Get the stage config for a wave's enemy formation.
	public StageConfig GetWaveStage(int32 index)
	{
		let wave = GetWave(index);
		if (wave == null) return null;
		return mConfigs.GetStage(wave.mStageId);
	}

	/// Seconds until the next weekly reset.
	public int32 SecondsUntilReset
	{
		get
		{
			let now = GetCurrentTimestamp();
			let nextReset = ((now / WEEKLY_RESET_SECONDS) + 1) * WEEKLY_RESET_SECONDS;
			return (int32)Math.Max(0, nextReset - now);
		}
	}

	/// Advance to the next wave after victory.
	public void AdvanceWave()
	{
		mSave.mCrusadeWave++;
	}

	// --- Attacker HP persistence ---

	/// Merge-capture attacker HP: updates existing entries, adds new ones.
	/// Preserves HP data for units not in the current battle.
	public void MergeCaptureHP(BattleSimulation sim)
	{
		for (int32 i = 0; i < sim.UnitCount; i++)
		{
			let unit = sim.GetUnit(i);
			if (unit == null || unit.mForce != .Attacker) continue;

			// Mark as used
			mUsedUnitIds.Add(unit.mConfig.mId);

			// Update or add HP entry
			bool found = false;
			for (let saved in mSavedHP)
			{
				if (saved.mUnitId == unit.mConfig.mId)
				{
					saved.mCurrentHP = unit.mAlive ? unit.mCurrentHP : 0;
					saved.mMaxHP = unit.mMaxHP;
					found = true;
					break;
				}
			}
			if (!found)
			{
				let hp = new PersistentUnitHP();
				hp.mUnitId = unit.mConfig.mId;
				hp.mCurrentHP = unit.mAlive ? unit.mCurrentHP : 0;
				hp.mMaxHP = unit.mMaxHP;
				mSavedHP.Add(hp);
			}
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

	/// Check if a unit died during this crusade run.
	public bool IsUnitDead(int32 unitId)
	{
		for (let saved in mSavedHP)
		{
			if (saved.mUnitId == unitId)
				return saved.mCurrentHP <= 0;
		}
		return false;
	}

	/// Check if a unit is available for deployment.
	/// Available = not dead AND (already used OR pool not full).
	public bool IsUnitAvailable(int32 unitId)
	{
		if (IsUnitDead(unitId)) return false;
		if (mUsedUnitIds.Contains(unitId)) return true;
		return (int32)mUsedUnitIds.Count < MAX_UNIT_POOL;
	}

	// --- Defender HP persistence ---

	/// Capture defender HP after a defeat (so enemies stay damaged on retry).
	public void CaptureDefenderHP(BattleSimulation sim)
	{
		for (let hp in mSavedDefenderHP) delete hp;
		mSavedDefenderHP.Clear();

		for (int32 i = 0; i < sim.UnitCount; i++)
		{
			let unit = sim.GetUnit(i);
			if (unit == null || unit.mForce != .Defender) continue;
			let hp = new PersistentUnitHP();
			hp.mUnitId = unit.mConfig.mId;
			hp.mCurrentHP = unit.mAlive ? unit.mCurrentHP : 0;
			hp.mMaxHP = unit.mMaxHP;
			mSavedDefenderHP.Add(hp);
		}
	}

	/// Restore defender HP after battle Initialize (for retries).
	/// Assumes dead defenders were already filtered from the formation,
	/// so this matches surviving entries by index order.
	public void RestoreDefenderHP(BattleSimulation sim)
	{
		if (mSavedDefenderHP.Count == 0) return;

		// Build list of surviving defender entries (skip dead)
		let surviving = scope List<PersistentUnitHP>();
		for (let saved in mSavedDefenderHP)
		{
			if (saved.mCurrentHP > 0)
				surviving.Add(saved);
		}

		int32 defIdx = 0;
		for (int32 i = 0; i < sim.UnitCount; i++)
		{
			let unit = sim.GetUnit(i);
			if (unit == null || unit.mForce != .Defender) continue;
			if (defIdx < surviving.Count)
			{
				let saved = surviving[defIdx];
				if (saved.mMaxHP > 0)
				{
					float ratio = (float)saved.mCurrentHP / (float)saved.mMaxHP;
					unit.mCurrentHP = Math.Max(1, (int32)(ratio * (float)unit.mMaxHP));
				}
				defIdx++;
			}
		}
	}

	/// Get the number of dead defenders (for filtering formation on retry).
	public int32 GetDeadDefenderCount()
	{
		int32 count = 0;
		for (let saved in mSavedDefenderHP)
		{
			if (saved.mCurrentHP <= 0)
				count++;
		}
		return count;
	}

	/// Check if defender at the given formation index is dead.
	public bool IsDefenderDead(int32 formationIndex)
	{
		if (formationIndex < 0 || formationIndex >= mSavedDefenderHP.Count)
			return false;
		return mSavedDefenderHP[formationIndex].mCurrentHP <= 0;
	}

	/// Clear defender HP data (on wave advance or reset).
	public void ClearDefenderHP()
	{
		for (let hp in mSavedDefenderHP) delete hp;
		mSavedDefenderHP.Clear();
	}

	// --- Reset ---

	/// Clear all persistent state (on weekly reset).
	public void ClearAll()
	{
		for (let hp in mSavedHP) delete hp;
		mSavedHP.Clear();
		ClearDefenderHP();
		mUsedUnitIds.Clear();
	}

	private static int64 GetCurrentTimestamp()
	{
		return DateTime.UtcNow.ToFileTime() / 10000000 - 11644473600;
	}
}

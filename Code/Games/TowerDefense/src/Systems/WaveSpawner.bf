namespace TowerDefense.Systems;

using System;
using System.Collections;
using Sedulous.Foundation.Core;
using TowerDefense.Data;

/// Manages wave spawning and progression.
class WaveSpawner
{
	// Wave definitions (not owned - just references to map's waves)
	private List<WaveDefinition> mWaves ~ delete _;

	// Current state
	private int32 mCurrentWaveIndex = -1;
	private int32 mCurrentGroupIndex = 0;
	private int32 mEnemiesSpawnedInGroup = 0;
	private float mSpawnTimer = 0.0f;
	private float mGroupDelayTimer = 0.0f;
	private bool mIsSpawning = false;
	private bool mWaitingForGroupDelay = false;

	// Tracking
	private int32 mEnemiesAlive = 0;
	private int32 mTotalEnemiesInWave = 0;

	// Event accessors
	private EventAccessor<WaveStartedDelegate> mOnWaveStarted = new .() ~ delete _;
	private EventAccessor<WaveCompletedDelegate> mOnWaveCompleted = new .() ~ delete _;
	private EventAccessor<AllWavesCompletedDelegate> mOnAllWavesCompleted = new .() ~ delete _;
	private EventAccessor<SpawnEnemyDelegate> mOnSpawnEnemy = new .() ~ delete _;

	/// Event fired when a wave starts.
	public EventAccessor<WaveStartedDelegate> OnWaveStarted => mOnWaveStarted;

	/// Event fired when a wave is completed.
	public EventAccessor<WaveCompletedDelegate> OnWaveCompleted => mOnWaveCompleted;

	/// Event fired when all waves are completed (victory).
	public EventAccessor<AllWavesCompletedDelegate> OnAllWavesCompleted => mOnAllWavesCompleted;

	/// Event fired when an enemy should be spawned.
	public EventAccessor<SpawnEnemyDelegate> OnSpawnEnemy => mOnSpawnEnemy;

	/// Whether a wave is currently in progress.
	public bool IsWaveInProgress => mIsSpawning || mEnemiesAlive > 0;

	/// Whether all waves have been completed.
	public bool AllWavesCompleted => mCurrentWaveIndex >= mWaves.Count && mEnemiesAlive == 0;

	/// Current wave number (1-based for display).
	public int32 CurrentWaveNumber => mCurrentWaveIndex + 1;

	/// Total number of waves.
	public int32 TotalWaves => (.)mWaves.Count;

	/// Number of enemies still alive.
	public int32 EnemiesAlive => mEnemiesAlive;

	/// Creates a new WaveSpawner.
	public this()
	{
		mWaves = new .();
	}

	/// Adds a wave definition.
	public void AddWave(WaveDefinition wave)
	{
		mWaves.Add(wave);
	}

	/// Clears all wave definitions (does not delete them - they're owned by map).
	public void ClearWaves()
	{
		mWaves.Clear();
		mCurrentWaveIndex = -1;
	}

	/// Starts the next wave. Returns false if no more waves.
	public bool StartNextWave()
	{
		if (mIsSpawning || mEnemiesAlive > 0)
		{
			Console.WriteLine("Cannot start wave - current wave still in progress!");
			return false;
		}

		mCurrentWaveIndex++;

		if (mCurrentWaveIndex >= mWaves.Count)
		{
			Console.WriteLine("All waves completed!");
			mOnAllWavesCompleted.[Friend]Invoke();
			return false;
		}

		// Initialize wave state
		mCurrentGroupIndex = 0;
		mEnemiesSpawnedInGroup = 0;
		mSpawnTimer = 0.0f;
		mIsSpawning = true;
		mTotalEnemiesInWave = CalculateTotalEnemies(mWaves[mCurrentWaveIndex]);

		// Check for initial group delay
		let wave = mWaves[mCurrentWaveIndex];
		if (wave.Groups.Count > 0 && wave.Groups[0].GroupDelay > 0)
		{
			mWaitingForGroupDelay = true;
			mGroupDelayTimer = wave.Groups[0].GroupDelay;
		}
		else
		{
			mWaitingForGroupDelay = false;
		}

		Console.WriteLine($"Wave {mCurrentWaveIndex + 1} started! ({mTotalEnemiesInWave} enemies)");
		mOnWaveStarted.[Friend]Invoke(mCurrentWaveIndex + 1);

		return true;
	}

	/// Calculates total enemies in a wave.
	private int32 CalculateTotalEnemies(WaveDefinition wave)
	{
		int32 total = 0;
		for (let group in wave.Groups)
			total += group.Count;
		return total;
	}

	/// Updates the spawner. Should be called every frame.
	public void Update(float deltaTime)
	{
		if (!mIsSpawning)
			return;

		let wave = mWaves[mCurrentWaveIndex];

		// Handle group delay
		if (mWaitingForGroupDelay)
		{
			mGroupDelayTimer -= deltaTime;
			if (mGroupDelayTimer <= 0)
			{
				mWaitingForGroupDelay = false;
				mSpawnTimer = 0.0f;
			}
			return;
		}

		// Update spawn timer
		mSpawnTimer -= deltaTime;
		if (mSpawnTimer <= 0)
		{
			// Spawn enemy
			if (mCurrentGroupIndex < wave.Groups.Count)
			{
				let group = wave.Groups[mCurrentGroupIndex];

				if (mEnemiesSpawnedInGroup < group.Count)
				{
					// Spawn an enemy
					mOnSpawnEnemy.[Friend]Invoke(group.EnemyType);
					mEnemiesAlive++;
					mEnemiesSpawnedInGroup++;
					mSpawnTimer = group.SpawnDelay;
				}

				// Check if group is complete
				if (mEnemiesSpawnedInGroup >= group.Count)
				{
					mCurrentGroupIndex++;
					mEnemiesSpawnedInGroup = 0;

					// Check for next group delay
					if (mCurrentGroupIndex < wave.Groups.Count)
					{
						let nextGroup = wave.Groups[mCurrentGroupIndex];
						if (nextGroup.GroupDelay > 0)
						{
							mWaitingForGroupDelay = true;
							mGroupDelayTimer = nextGroup.GroupDelay;
						}
					}
				}
			}

			// Check if all spawning is complete
			if (mCurrentGroupIndex >= wave.Groups.Count)
			{
				mIsSpawning = false;
				Console.WriteLine("All enemies spawned for this wave");
			}
		}
	}

	/// Called when an enemy is killed or exits.
	public void OnEnemyRemoved()
	{
		mEnemiesAlive = Math.Max(0, mEnemiesAlive - 1);

		// Check for wave completion
		if (!mIsSpawning && mEnemiesAlive == 0 && mCurrentWaveIndex >= 0 && mCurrentWaveIndex < mWaves.Count)
		{
			let wave = mWaves[mCurrentWaveIndex];
			Console.WriteLine($"Wave {mCurrentWaveIndex + 1} completed! Bonus: ${wave.BonusReward}");
			mOnWaveCompleted.[Friend]Invoke(mCurrentWaveIndex + 1, wave.BonusReward);

			// Check for all waves completed
			if (mCurrentWaveIndex >= mWaves.Count - 1)
			{
				mOnAllWavesCompleted.[Friend]Invoke();
			}
		}
	}

	/// Resets the spawner to initial state.
	public void Reset()
	{
		mCurrentWaveIndex = -1;
		mCurrentGroupIndex = 0;
		mEnemiesSpawnedInGroup = 0;
		mSpawnTimer = 0.0f;
		mGroupDelayTimer = 0.0f;
		mIsSpawning = false;
		mWaitingForGroupDelay = false;
		mEnemiesAlive = 0;
		mTotalEnemiesInWave = 0;
	}
}

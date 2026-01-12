namespace TowerDefense.Data;

using System;
using System.Collections;

/// Defines a group of enemies within a wave.
struct WaveGroup
{
	/// Type of enemy to spawn (matches EnemyDefinition preset name).
	public EnemyPreset EnemyType;

	/// Number of enemies in this group.
	public int32 Count;

	/// Delay between spawning each enemy (seconds).
	public float SpawnDelay;

	/// Delay before this group starts spawning (seconds).
	public float GroupDelay;
}

/// Enemy preset types for wave definitions.
enum EnemyPreset
{
	BasicTank,
	FastTank,
	ArmoredTank,
	Helicopter,
	BossTank
}

/// Defines a wave of enemies.
class WaveDefinition
{
	/// Groups of enemies in this wave.
	public List<WaveGroup> Groups = new .() ~ delete _;

	/// Bonus money awarded for completing this wave.
	public int32 BonusReward = 50;

	/// Adds a group of enemies to this wave.
	public void AddGroup(EnemyPreset enemyType, int32 count, float spawnDelay = 1.5f, float groupDelay = 0.0f)
	{
		Groups.Add(.()
		{
			EnemyType = enemyType,
			Count = count,
			SpawnDelay = spawnDelay,
			GroupDelay = groupDelay
		});
	}

	/// Creates Wave 1: Introduction - few basic enemies.
	public static WaveDefinition CreateWave1()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 25;
		wave.AddGroup(.BasicTank, 5, 1.5f);
		return wave;
	}

	/// Creates Wave 2: More enemies.
	public static WaveDefinition CreateWave2()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 50;
		wave.AddGroup(.BasicTank, 8, 1.2f);
		return wave;
	}

	/// Creates Wave 3: Introduce fast enemies.
	public static WaveDefinition CreateWave3()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 75;
		wave.AddGroup(.BasicTank, 5, 1.5f);
		wave.AddGroup(.FastTank, 3, 1.0f, 2.0f);
		return wave;
	}

	/// Creates Wave 4: Mixed ground assault.
	public static WaveDefinition CreateWave4()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 100;
		wave.AddGroup(.FastTank, 4, 1.0f);
		wave.AddGroup(.BasicTank, 6, 1.2f, 1.5f);
		wave.AddGroup(.ArmoredTank, 2, 2.0f, 2.0f);
		return wave;
	}

	/// Creates Wave 5: Air attack.
	public static WaveDefinition CreateWave5()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 125;
		wave.AddGroup(.BasicTank, 4, 1.5f);
		wave.AddGroup(.Helicopter, 4, 1.5f, 2.0f);
		return wave;
	}

	/// Creates Wave 6: Heavy assault.
	public static WaveDefinition CreateWave6()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 150;
		wave.AddGroup(.ArmoredTank, 3, 2.0f);
		wave.AddGroup(.FastTank, 6, 0.8f, 2.0f);
		wave.AddGroup(.Helicopter, 3, 1.5f, 1.0f);
		return wave;
	}

	/// Creates Wave 7: Boss wave.
	public static WaveDefinition CreateWave7()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 200;
		wave.AddGroup(.BasicTank, 6, 1.0f);
		wave.AddGroup(.ArmoredTank, 4, 1.5f, 2.0f);
		wave.AddGroup(.BossTank, 1, 0.0f, 3.0f);
		return wave;
	}
}

namespace TowerDefense.Maps;

using System;
using Sedulous.Mathematics;
using TowerDefense.Data;

/// Third map: Fortress
/// A challenging map with a long winding path around a central fortress.
///
/// Layout (16x12):
/// ~~~~~~~~~~~~~~~~
/// ~S###..........~
/// ~...#..........~
/// ~...######.....~
/// ~........#.....~
/// ~........#.....~
/// ~...######.....~
/// ~...#..........~
/// ~...######.....~
/// ~........#.....~
/// ~........###E..~
/// ~~~~~~~~~~~~~~~~
///
/// Legend: .=Stone, #=Path, S=Spawn, E=Exit, ~=Water (moat)
static class Map03_Fortress
{
	public static MapDefinition Create()
	{
		let map = new MapDefinition();
		map.Name.Set("Fortress");
		map.StartingMoney = 300;
		map.StartingLives = 10;  // Hardest map, fewest lives
		map.TileSize = 2.0f;

		// Allocate 16x12 grid
		map.AllocateTiles(16, 12);

		// Define the map layout (row 0 is top/north)
		// Water moat around the edges, winding path inside
		map.SetRow(0,  "~~~~~~~~~~~~~~~~");
		map.SetRow(1,  "~S###..........~");
		map.SetRow(2,  "~...#..........~");
		map.SetRow(3,  "~...######.....~");
		map.SetRow(4,  "~........#.....~");
		map.SetRow(5,  "~........#.....~");
		map.SetRow(6,  "~...######.....~");
		map.SetRow(7,  "~...#..........~");
		map.SetRow(8,  "~...######.....~");
		map.SetRow(9,  "~........#.....~");
		map.SetRow(10, "~........###E..~");
		map.SetRow(11, "~~~~~~~~~~~~~~~~");

		// Define waypoints for enemy pathfinding
		// Long winding path through the fortress
		map.Waypoints.Add(map.GridToWorld(-1, 1));  // Spawn (off-grid left)
		map.Waypoints.Add(map.GridToWorld(1, 1));   // Enter grid
		map.Waypoints.Add(map.GridToWorld(4, 1));   // Turn down
		map.Waypoints.Add(map.GridToWorld(4, 3));   // Turn right
		map.Waypoints.Add(map.GridToWorld(9, 3));   // Turn down
		map.Waypoints.Add(map.GridToWorld(9, 6));   // Turn left
		map.Waypoints.Add(map.GridToWorld(4, 6));   // Turn down
		map.Waypoints.Add(map.GridToWorld(4, 8));   // Turn right
		map.Waypoints.Add(map.GridToWorld(9, 8));   // Turn down
		map.Waypoints.Add(map.GridToWorld(9, 10));  // Turn right
		map.Waypoints.Add(map.GridToWorld(12, 10)); // Near exit
		map.Waypoints.Add(map.GridToWorld(16, 10)); // Exit (off-grid right)

		// Add wave definitions - harder variants for fortress
		map.Waves.Add(CreateFortressWave1());
		map.Waves.Add(CreateFortressWave2());
		map.Waves.Add(CreateFortressWave3());
		map.Waves.Add(CreateFortressWave4());
		map.Waves.Add(CreateFortressWave5());
		map.Waves.Add(CreateFortressWave6());
		map.Waves.Add(CreateFortressWave7());
		map.Waves.Add(CreateFortressWave8());  // Extra hard final wave

		return map;
	}

	// Fortress-specific waves (harder than standard)
	private static WaveDefinition CreateFortressWave1()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 30;
		wave.AddGroup(.BasicTank, 6, 1.2f);
		return wave;
	}

	private static WaveDefinition CreateFortressWave2()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 50;
		wave.AddGroup(.BasicTank, 8, 1.0f);
		wave.AddGroup(.FastTank, 3, 0.8f, 2.0f);
		return wave;
	}

	private static WaveDefinition CreateFortressWave3()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 75;
		wave.AddGroup(.FastTank, 6, 0.8f);
		wave.AddGroup(.ArmoredTank, 3, 1.5f, 3.0f);
		return wave;
	}

	private static WaveDefinition CreateFortressWave4()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 100;
		wave.AddGroup(.BasicTank, 10, 0.8f);
		wave.AddGroup(.Helicopter, 5, 1.0f, 2.0f);
		return wave;
	}

	private static WaveDefinition CreateFortressWave5()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 125;
		wave.AddGroup(.ArmoredTank, 5, 1.2f);
		wave.AddGroup(.FastTank, 8, 0.6f, 2.0f);
		wave.AddGroup(.Helicopter, 4, 1.0f, 3.0f);
		return wave;
	}

	private static WaveDefinition CreateFortressWave6()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 150;
		wave.AddGroup(.Helicopter, 8, 0.8f);
		wave.AddGroup(.ArmoredTank, 6, 1.0f, 3.0f);
		return wave;
	}

	private static WaveDefinition CreateFortressWave7()
	{
		let wave = new WaveDefinition();
		wave.BonusReward = 175;
		wave.AddGroup(.ArmoredTank, 8, 1.0f);
		wave.AddGroup(.FastTank, 10, 0.5f, 2.0f);
		wave.AddGroup(.BossTank, 1, 0.0f, 5.0f);
		return wave;
	}

	private static WaveDefinition CreateFortressWave8()
	{
		// Ultimate challenge wave
		let wave = new WaveDefinition();
		wave.BonusReward = 250;
		wave.AddGroup(.FastTank, 12, 0.4f);
		wave.AddGroup(.ArmoredTank, 6, 1.0f, 2.0f);
		wave.AddGroup(.Helicopter, 8, 0.6f, 3.0f);
		wave.AddGroup(.BossTank, 2, 2.0f, 5.0f);  // 2 bosses!
		return wave;
	}
}

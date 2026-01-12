namespace TowerDefense.Maps;

using System;
using Sedulous.Mathematics;
using TowerDefense.Data;

/// First map: Grasslands
/// A simple S-curve path through a grassy field.
///
/// Layout (12x8):
/// ............
/// S###........
/// ...#........
/// ...####.....
/// .......#....
/// .......####E
/// ............
/// ............
///
/// Legend: .=Grass, #=Path, S=Spawn, E=Exit
static class Map01_Grasslands
{
	public static MapDefinition Create()
	{
		let map = new MapDefinition();
		map.Name.Set("Grasslands");
		map.StartingMoney = 200;
		map.StartingLives = 20;
		map.TileSize = 2.0f;

		// Allocate 12x8 grid
		map.AllocateTiles(12, 8);

		// Define the map layout (row 0 is top/north, row 7 is bottom/south)
		// Using pattern: .=Grass, #=Path, S=Spawn, E=Exit, ~=Water
		map.SetRow(0, "............");
		map.SetRow(1, "S###........");
		map.SetRow(2, "...#........");
		map.SetRow(3, "...####.....");
		map.SetRow(4, ".......#....");
		map.SetRow(5, ".......####E");
		map.SetRow(6, "............");
		map.SetRow(7, "............");

		// Define waypoints for enemy pathfinding
		// Waypoints are in world coordinates (center of tiles)
		// Path: Spawn -> right -> down -> right -> down -> right -> Exit
		map.Waypoints.Add(map.GridToWorld(-1, 1));  // Spawn (off-grid left)
		map.Waypoints.Add(map.GridToWorld(0, 1));   // Enter grid
		map.Waypoints.Add(map.GridToWorld(3, 1));   // Turn down
		map.Waypoints.Add(map.GridToWorld(3, 3));   // Turn right
		map.Waypoints.Add(map.GridToWorld(6, 3));   // Turn down
		map.Waypoints.Add(map.GridToWorld(7, 3));   // Continue
		map.Waypoints.Add(map.GridToWorld(7, 5));   // Turn right
		map.Waypoints.Add(map.GridToWorld(10, 5));  // Near exit
		map.Waypoints.Add(map.GridToWorld(12, 5)); // Exit (off-grid right)

		// Add wave definitions
		map.Waves.Add(WaveDefinition.CreateWave1());  // Introduction
		map.Waves.Add(WaveDefinition.CreateWave2());  // More enemies
		map.Waves.Add(WaveDefinition.CreateWave3());  // Introduce fast tanks
		map.Waves.Add(WaveDefinition.CreateWave4());  // Mixed assault
		map.Waves.Add(WaveDefinition.CreateWave5());  // Air attack
		map.Waves.Add(WaveDefinition.CreateWave6());  // Heavy assault
		map.Waves.Add(WaveDefinition.CreateWave7());  // Boss wave

		return map;
	}
}

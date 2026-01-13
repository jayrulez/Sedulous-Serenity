namespace TowerDefense.Maps;

using System;
using Sedulous.Mathematics;
using TowerDefense.Data;

/// Second map: Desert Canyon
/// A winding path through a desert canyon with water hazards.
///
/// Layout (14x10):
/// ..............
/// S###..........
/// ...#..........
/// ...#####......
/// .......#......
/// ...#####......
/// ...#..........
/// ...#####..~~~~
/// .......#..~~~~
/// .......####E~~
///
/// Legend: .=Sand, #=Path, S=Spawn, E=Exit, ~=Water
static class Map02_Desert
{
	public static MapDefinition Create()
	{
		let map = new MapDefinition();
		map.Name.Set("Desert Canyon");
		map.StartingMoney = 250;
		map.StartingLives = 15;  // Harder map, fewer lives
		map.TileSize = 2.0f;

		// Allocate 14x10 grid
		map.AllocateTiles(14, 10);

		// Define the map layout (row 0 is top/north)
		// Using pattern: .=Sand, #=Path, S=Spawn, E=Exit, ~=Water
		map.SetRow(0, "..............");
		map.SetRow(1, "S###..........");
		map.SetRow(2, "...#..........");
		map.SetRow(3, "...#####......");
		map.SetRow(4, ".......#......");
		map.SetRow(5, "...#####......");
		map.SetRow(6, "...#..........");
		map.SetRow(7, "...#####..~~~~");
		map.SetRow(8, ".......#..~~~~");
		map.SetRow(9, ".......####E~~");

		// Define waypoints for enemy pathfinding
		// Path: Spawn -> right -> down -> right -> down -> left -> down -> right -> down -> right -> Exit
		map.Waypoints.Add(map.GridToWorld(-1, 1));  // Spawn (off-grid left)
		map.Waypoints.Add(map.GridToWorld(0, 1));   // Enter grid
		map.Waypoints.Add(map.GridToWorld(3, 1));   // Turn down
		map.Waypoints.Add(map.GridToWorld(3, 3));   // Turn right
		map.Waypoints.Add(map.GridToWorld(7, 3));   // Turn down
		map.Waypoints.Add(map.GridToWorld(7, 4));   // Turn left
		map.Waypoints.Add(map.GridToWorld(3, 5));   // Turn down (going back left)
		map.Waypoints.Add(map.GridToWorld(3, 7));   // Turn right
		map.Waypoints.Add(map.GridToWorld(7, 7));   // Turn down
		map.Waypoints.Add(map.GridToWorld(7, 9));   // Turn right
		map.Waypoints.Add(map.GridToWorld(10, 9));  // Near exit
		map.Waypoints.Add(map.GridToWorld(14, 9));  // Exit (off-grid right)

		// Add wave definitions - same waves but they feel harder on this map
		map.Waves.Add(WaveDefinition.CreateWave1());
		map.Waves.Add(WaveDefinition.CreateWave2());
		map.Waves.Add(WaveDefinition.CreateWave3());
		map.Waves.Add(WaveDefinition.CreateWave4());
		map.Waves.Add(WaveDefinition.CreateWave5());
		map.Waves.Add(WaveDefinition.CreateWave6());
		map.Waves.Add(WaveDefinition.CreateWave7());

		return map;
	}
}

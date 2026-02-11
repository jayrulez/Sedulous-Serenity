namespace Platformer.Levels;

using System;
using Platformer.Data;

/// Level 1: Green Meadows - Tutorial level teaching movement and jumping.
static class Level01_GreenMeadows
{
	public static LevelDefinition Create()
	{
		let level = new LevelDefinition();
		level.Name.Set("Green Meadows");
		level.AllocateTiles(40, 12);

		// Build from bottom up (row 0 = bottom)
		StringView[12] rows = .(
			"DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD",  // 0
			"DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD",  // 1
			"DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD",  // 2
			"DDDD...............................DDDDDDDD",  // 3
			"DDDD...............................DDDDDDDD",  // 4
			"GGGG.........G.....G......GGGGG.GGGGGGGGGG",  // 5
			"P.....GGGGG...GGG...GGGGG......GGGGGGGGGGG",  // 6
			".......$$$..........................$.....F.",  // 7
			"........................................T...",  // 8
			".......................T.........T..........",  // 9
			"........................................T...",  // 10
			"..........................................."   // 11
		);

		for (int32 i = 0; i < 12; i++)
			level.SetRow(i, rows[i]);

		// Player spawn is set by 'P' in row 6, x=0
		level.SpawnX = 0;
		level.SpawnY = 6;

		// Goal flag
		level.GoalX = 37;
		level.GoalY = 7;

		// Enemies: one slime on the middle platform
		level.Enemies.Add(EnemyPlacement(.Slime, 27, 6, 25, 30));

		return level;
	}

	/// Populates entity placements from the grid.
	public static void PopulateEntities(LevelDefinition level, LevelBuilder builder)
	{
		// Coins above the first platform
		builder.CreatePickupEntity(.Coin, level.GridToWorld(7, 7) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(8, 7) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(9, 7) + .(0, 0.3f, 0));

		// Coin near the end
		builder.CreatePickupEntity(.Coin, level.GridToWorld(33, 7) + .(0, 0.3f, 0));

		// Trees (decorations behind the play area)
		builder.CreateDecorationEntity("tree", level.GridToWorld(23, 9) + .(0, 0.5f, -3.0f), .(1.5f, 1.5f, 1.5f));
		builder.CreateDecorationEntity("tree", level.GridToWorld(33, 9) + .(0, 0.5f, -3.0f), .(1.5f, 1.5f, 1.5f));
		builder.CreateDecorationEntity("tree", level.GridToWorld(38, 8) + .(0, 0.5f, -3.0f), .(1.2f, 1.2f, 1.2f));
		builder.CreateDecorationEntity("tree", level.GridToWorld(38, 10) + .(0, 0.5f, -3.0f), .(1.0f, 1.0f, 1.0f));

		// Bushes
		builder.CreateDecorationEntity("bush", level.GridToWorld(2, 6) + .(0, 0.5f, -2.0f), .(0.8f, 0.8f, 0.8f));
		builder.CreateDecorationEntity("bush", level.GridToWorld(15, 6) + .(0, 0.5f, -2.0f), .(0.8f, 0.8f, 0.8f));

		// Grass tufts
		builder.CreateDecorationEntity("grass1", level.GridToWorld(5, 6) + .(0, 0.5f, 0.3f), .(0.5f, 0.5f, 0.5f));
		builder.CreateDecorationEntity("grass1", level.GridToWorld(20, 6) + .(0, 0.5f, 0.3f), .(0.5f, 0.5f, 0.5f));
	}
}

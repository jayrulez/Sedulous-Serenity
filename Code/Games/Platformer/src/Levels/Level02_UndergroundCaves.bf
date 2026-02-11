namespace Platformer.Levels;

using Platformer.Data;
using System;

/// Level 2: Underground Caves - Introduces hazards, keys, and vertical platforming.
static class Level02_UndergroundCaves
{
	public static LevelDefinition Create()
	{
		let level = new LevelDefinition();
		level.Name.Set("Underground Caves");
		level.AllocateTiles(50, 16);

		// Row 0 = bottom, Row 15 = top
		StringView[16] rows = .(
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",  // 0
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",  // 1
			"BBBBBBBBBBBBBB....BBBBBB....BBBBBBBBBB....BBBBBBB",  // 2
			"BBBBB.........BBBB......BBBB......BBBBB.BBBBBBBBB",  // 3
			"BBBBB.....S...BBBB....?.BBBB......BBBBB.BBBBBBBBB",  // 4
			"P....BBBBBBBB.....BBBBBBBB...BBBBB.....BBBB....FB",  // 5
			".....BBBB.........BBB...........BBB..............B",  // 6
			"..........BBB..............................BBBBBBB",  // 7
			"..............BBB..........BBB.........BBBB.....BB",  // 8
			"..................BBB...........BBB.........BBBBBB",  // 9
			"..............................................BBBB",  // 10
			"..................................................",  // 11
			"..................................................",  // 12
			"..................................................",  // 13
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",  // 14
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"   // 15
		);

		for (int32 i = 0; i < 16; i++)
			level.SetRow(i, rows[i]);

		level.SpawnX = 0;
		level.SpawnY = 5;
		level.GoalX = 47;
		level.GoalY = 5;

		// Enemies
		level.Enemies.Add(EnemyPlacement(.Crab, 15, 5, 13, 18));
		level.Enemies.Add(EnemyPlacement(.Bee, 25, 8, 22, 30));
		level.Enemies.Add(EnemyPlacement(.Crab, 35, 5, 32, 38));

		// Moving platforms (avoid bricks at row 7 col 10-12)
		level.MovingPlatforms.Add(MovingPlatformPlacement(9, 6, 9, 9, 1.5f));
		level.MovingPlatforms.Add(MovingPlatformPlacement(30, 8, 34, 8, 2.0f));

		return level;
	}

	public static void PopulateEntities(LevelDefinition level, LevelBuilder builder)
	{
		// Key to unlock door near the goal
		builder.CreatePickupEntity(.Key, level.GridToWorld(22, 7) + .(0, 0.3f, 0));

		// Door near goal
		builder.CreateDoorEntity(level.GridToWorld(44, 5) + .(0, 0.25f, 0));

		// Coins scattered through the level (avoid bricks at row 6 col 5-8)
		builder.CreatePickupEntity(.Coin, level.GridToWorld(6, 7) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(7, 7) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(8, 7) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(20, 7) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(32, 7) + .(0, 0.3f, 0));

		// Gems in hard-to-reach spots
		builder.CreatePickupEntity(.GemBlue, level.GridToWorld(38, 10) + .(0, 0.3f, 0));

		// Heart before the harder section
		builder.CreatePickupEntity(.Heart, level.GridToWorld(28, 6) + .(0, 0.3f, 0));

		// Bouncer to reach upper areas
		builder.CreateBouncerEntity(level.GridToWorld(40, 5) + .(0, 0.25f, 0));

		// Rock decorations (underground cave theme)
		builder.CreateDecorationEntity("rock1", level.GridToWorld(3, 5) + .(0, 0.5f, -1.0f), .(0.6f, 0.6f, 0.6f));
		builder.CreateDecorationEntity("rock2", level.GridToWorld(18, 5) + .(0, 0.5f, -1.0f), .(0.5f, 0.5f, 0.5f));
	}
}

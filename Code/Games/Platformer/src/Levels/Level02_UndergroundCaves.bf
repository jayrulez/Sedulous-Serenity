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

		//              00000000001111111111222222222233333333334444444444
		//              01234567890123456789012345678901234567890123456789
		StringView[16] rows = .(
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", // 0  floor
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", // 1  floor
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", // 2  sub-floor
			"BBBBB............................BBBBBBBBBBBBBBBBB", // 3  underground
			"BBBBBB...BBBBB...BBBSBB..BBBBB...BBBBB..BBBBBBBBBB", // 4  main ground
			"P..............................................F..", // 5  player / goal
			"..................................................", // 6
			"........................BBBBB.........................", // 7  upper platform
			"..................................................", // 8
			"..................................................", // 9
			"..................................................", // 10
			"..................................................", // 11
			"..................................................", // 12
			"..................................................", // 13
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", // 14 ceiling
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"  // 15 ceiling
		);

		for (int32 i = 0; i < 16; i++)
			level.SetRow(i, rows[i]);

		level.SpawnX = 0;
		level.SpawnY = 5;
		level.GoalX = 47;
		level.GoalY = 5;

		// Enemies
		level.Enemies.Add(EnemyPlacement(.Crab, 11, 5, 9, 13));
		level.Enemies.Add(EnemyPlacement(.Bee, 20, 7, 15, 25));
		level.Enemies.Add(EnemyPlacement(.Crab, 43, 5, 40, 47));

		// Moving platform over a gap
		level.MovingPlatforms.Add(MovingPlatformPlacement(36, 6, 40, 6, 2.0f));

		return level;
	}

	public static void PopulateEntities(LevelDefinition level, LevelBuilder builder)
	{
		// Key on upper platform (reach via bouncer)
		builder.CreatePickupEntity(.Key, level.GridToWorld(26, 8) + .(0, 0.3f, 0));

		// Door near goal
		builder.CreateDoorEntity(level.GridToWorld(44, 5) + .(0, 0.25f, 0));

		// Bouncer to reach upper platform
		builder.CreateBouncerEntity(level.GridToWorld(26, 5) + .(0, 0.25f, 0));

		// Coins scattered through the level
		builder.CreatePickupEntity(.Coin, level.GridToWorld(10, 6) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(11, 6) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(12, 6) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(34, 6) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(42, 6) + .(0, 0.3f, 0));

		// Gem on upper platform
		builder.CreatePickupEntity(.GemBlue, level.GridToWorld(25, 8) + .(0, 0.3f, 0));

		// Heart before the harder section
		builder.CreatePickupEntity(.Heart, level.GridToWorld(30, 6) + .(0, 0.3f, 0));

		// Rock decorations
		builder.CreateDecorationEntity("rock1", level.GridToWorld(3, 5) + .(0, 0.5f, -1.0f), .(0.6f, 0.6f, 0.6f));
		builder.CreateDecorationEntity("rock2", level.GridToWorld(18, 5) + .(0, 0.5f, -1.0f), .(0.5f, 0.5f, 0.5f));
	}
}

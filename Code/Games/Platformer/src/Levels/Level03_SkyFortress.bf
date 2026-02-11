namespace Platformer.Levels;

using System;
using Platformer.Data;
using Platformer.Components;

/// Level 3: Sky Fortress - Floating platforms, cannons, and precise jumping.
static class Level03_SkyFortress
{
	public static LevelDefinition Create()
	{
		let level = new LevelDefinition();
		level.Name.Set("Sky Fortress");
		level.AllocateTiles(60, 20);

		// Row 0 = bottom (void), platforms float in the middle
		StringView[20] rows = .(
			"..........................................................",  // 0 void
			"..........................................................",  // 1 void
			"..........................................................",  // 2 void
			"GGGGG..........GGG..........GGG..........GGG.............",  // 3
			"DDDDD..........DDD..........DDD..........DDD.............",  // 4
			"P..............................................................",  // 5
			"...................................................................",  // 6
			"........GGGGG..........GGGGG..........GGGG..........GGGGG",  // 7
			"........DDDDD..........DDDDD..........DDDD..........DDDDD",  // 8
			"..............................................................",  // 9
			"..............................................................",  // 10
			"..........GGGGG..........BBB..........GGGGG..........BBBBB",  // 11
			"..........DDDDD..........BBB..........DDDDD..........BBBBB",  // 12
			"..............................................................",  // 13
			"..............BBB...........GGGGG.............BBB.........",  // 14
			"..............BBB...........DDDDD.............BBB.........",  // 15
			"..............................................................",  // 16
			"..................................................GGGGGGGG",  // 17
			"..................................................GGGGGFGG",  // 18
			".........................................................."    // 19
		);

		for (int32 i = 0; i < 20; i++)
			level.SetRow(i, rows[i]);

		level.SpawnX = 0;
		level.SpawnY = 5;
		level.GoalX = 55;
		level.GoalY = 18;

		// Enemies
		level.Enemies.Add(EnemyPlacement(.Bee, 20, 9, 16, 26));
		level.Enemies.Add(EnemyPlacement(.Bee, 40, 13, 36, 44));
		level.Enemies.Add(EnemyPlacement(.Skull, 48, 15, 45, 52));

		// Moving platforms over gaps
		level.MovingPlatforms.Add(MovingPlatformPlacement(5, 5, 8, 7, 1.5f));
		level.MovingPlatforms.Add(MovingPlatformPlacement(25, 9, 28, 11, 2.0f));
		level.MovingPlatforms.Add(MovingPlatformPlacement(45, 14, 50, 17, 2.5f));

		// Moving hazards
		level.MovingHazards.Add(HazardPlacement(.Saw, 15, 7, 15, 11, 2.0f));
		level.MovingHazards.Add(HazardPlacement(.SpikyBall, 35, 11, 40, 11, 3.0f));

		return level;
	}

	public static void PopulateEntities(LevelDefinition level, LevelBuilder builder)
	{
		// Keys for progression
		builder.CreatePickupEntity(.Key, level.GridToWorld(22, 12) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Key, level.GridToWorld(42, 12) + .(0, 0.3f, 0));

		// Doors
		builder.CreateDoorEntity(level.GridToWorld(50, 17) + .(0, 0.25f, 0));

		// Coins along the path
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(9 + i, 8) + .(0, 0.3f, 0));
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(30 + i, 12) + .(0, 0.3f, 0));

		// Star in a challenging spot
		builder.CreatePickupEntity(.Star, level.GridToWorld(55, 19) + .(0, 0.3f, 0));

		// Gems
		builder.CreatePickupEntity(.GemPink, level.GridToWorld(14, 14) + .(0, 0.3f, 0));

		// Heart
		builder.CreatePickupEntity(.Heart, level.GridToWorld(35, 12) + .(0, 0.3f, 0));

		// Bouncers
		builder.CreateBouncerEntity(level.GridToWorld(5, 3) + .(0, 0.25f, 0));
	}
}

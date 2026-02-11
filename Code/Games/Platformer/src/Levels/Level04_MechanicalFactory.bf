namespace Platformer.Levels;

using System;
using Platformer.Data;
using Platformer.Components;

/// Level 4: Mechanical Factory - Dense hazards and puzzle-like routing.
static class Level04_MechanicalFactory
{
	public static LevelDefinition Create()
	{
		let level = new LevelDefinition();
		level.Name.Set("Mechanical Factory");
		level.AllocateTiles(55, 18);

		StringView[18] rows = .(
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",  // 0
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",  // 1
			"BBBBBBBBBBBBBBBBB....BBBBBB......BBBBBBBBBBBBB....BBBB",  // 2
			"BBBBB....CCCC....BBBB......CCCC.......BBBBB...BBBBBBB",  // 3
			"P....BBBB....CCCC....BBBB......CCCC.......BB.BBBBBBBB",  // 4
			"BBBB.........CCCC....BBBB..S...CCCC.......BB.........B",  // 5
			".....CCCC.........BBBB....BBBBB.......CCCC....BBBBBBB",  // 6
			".............BBBB..........BBBBB...CCCC....BBBB.....FB",  // 7
			"......CCCC.......BBBB..........BBBB.......BBBB.......B",  // 8
			"...........CCCC.......BBBB.........BBBB.......BBBBBBB",  // 9
			"..............BBBB.........BBBB.........BBBB...........",  // 10
			".......................................................",  // 11
			".......................................................",  // 12
			".......................................................",  // 13
			".......................................................",  // 14
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",  // 15
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",  // 16
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"   // 17
		);

		for (int32 i = 0; i < 18; i++)
			level.SetRow(i, rows[i]);

		level.SpawnX = 0;
		level.SpawnY = 4;
		level.GoalX = 52;
		level.GoalY = 7;

		// Enemies
		level.Enemies.Add(EnemyPlacement(.Crab, 12, 5, 9, 16));
		level.Enemies.Add(EnemyPlacement(.Slime, 25, 5, 22, 28));
		level.Enemies.Add(EnemyPlacement(.Bee, 35, 8, 32, 40));
		level.Enemies.Add(EnemyPlacement(.Crab, 45, 7, 42, 48));

		// Moving platforms
		level.MovingPlatforms.Add(MovingPlatformPlacement(8, 6, 8, 9, 2.0f));
		level.MovingPlatforms.Add(MovingPlatformPlacement(20, 7, 24, 7, 2.5f));
		level.MovingPlatforms.Add(MovingPlatformPlacement(38, 8, 38, 10, 1.5f));

		// Moving hazards - saws
		level.MovingHazards.Add(HazardPlacement(.Saw, 15, 5, 15, 8, 2.5f));
		level.MovingHazards.Add(HazardPlacement(.Saw, 30, 6, 30, 9, 3.0f));
		level.MovingHazards.Add(HazardPlacement(.Saw, 42, 5, 42, 8, 2.0f));

		return level;
	}

	public static void PopulateEntities(LevelDefinition level, LevelBuilder builder)
	{
		// Two keys needed
		builder.CreatePickupEntity(.Key, level.GridToWorld(18, 6) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Key, level.GridToWorld(40, 9) + .(0, 0.3f, 0));

		// Two doors
		builder.CreateDoorEntity(level.GridToWorld(35, 7) + .(0, 0.25f, 0));
		builder.CreateDoorEntity(level.GridToWorld(49, 7) + .(0, 0.25f, 0));

		// Coins
		for (int32 i = 0; i < 4; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(5 + i * 3, 5) + .(0, 0.3f, 0));
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(25 + i, 6) + .(0, 0.3f, 0));

		// Gems in harder spots
		builder.CreatePickupEntity(.GemGreen, level.GridToWorld(10, 9) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.GemBlue, level.GridToWorld(33, 10) + .(0, 0.3f, 0));

		// Hearts
		builder.CreatePickupEntity(.Heart, level.GridToWorld(22, 5) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Heart, level.GridToWorld(44, 8) + .(0, 0.3f, 0));

		// Bouncers
		builder.CreateBouncerEntity(level.GridToWorld(6, 4) + .(0, 0.25f, 0));
		builder.CreateBouncerEntity(level.GridToWorld(28, 5) + .(0, 0.25f, 0));

		// Exclamation block star reward
		builder.CreatePickupEntity(.Star, level.GridToWorld(10, 10) + .(0, 0.3f, 0));
	}
}

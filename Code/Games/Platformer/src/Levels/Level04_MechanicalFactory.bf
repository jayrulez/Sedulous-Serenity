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

		// Factory ground path with brick/crate platforms, 3-tile gaps, saws.
		//             0000000000111111111122222222223333333333444444444455555
		//             0123456789012345678901234567890123456789012345678901234
		StringView[18] rows = .(
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", // 0  floor
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", // 1  floor
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", // 2  sub-floor
			"BBBBBB...CCCC...BBBBB...CCCC...BBBBB...BBBBB..BBBBBBBBB", // 3  main ground
			"P....................................................F.", // 4  player / goal
			".......................................................", // 5
			".......................................................", // 6
			".......................................................", // 7
			".......................................................", // 8
			".......................................................", // 9
			".......................................................", // 10
			".......................................................", // 11
			".......................................................", // 12
			".......................................................", // 13
			".......................................................", // 14
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", // 15 ceiling
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", // 16 ceiling
			"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"  // 17 ceiling
		);

		for (int32 i = 0; i < 18; i++)
			level.SetRow(i, rows[i]);

		level.SpawnX = 0;
		level.SpawnY = 4;
		level.GoalX = 53;
		level.GoalY = 4;

		// Enemies
		level.Enemies.Add(EnemyPlacement(.Crab, 10, 4, 9, 12));
		level.Enemies.Add(EnemyPlacement(.Slime, 25, 4, 24, 27));
		level.Enemies.Add(EnemyPlacement(.Bee, 35, 6, 31, 40));
		level.Enemies.Add(EnemyPlacement(.Crab, 48, 4, 46, 52));

		// Moving platforms
		level.MovingPlatforms.Add(MovingPlatformPlacement(8, 5, 8, 7, 2.0f));
		level.MovingPlatforms.Add(MovingPlatformPlacement(20, 5, 24, 5, 2.5f));
		level.MovingPlatforms.Add(MovingPlatformPlacement(38, 5, 38, 7, 1.5f));

		// Moving hazards - saws between platforms
		level.MovingHazards.Add(HazardPlacement(.Saw, 15, 4, 15, 7, 2.5f));
		level.MovingHazards.Add(HazardPlacement(.Saw, 30, 4, 30, 7, 3.0f));
		level.MovingHazards.Add(HazardPlacement(.Saw, 42, 4, 42, 6, 2.0f));

		return level;
	}

	public static void PopulateEntities(LevelDefinition level, LevelBuilder builder)
	{
		// Two keys needed for progression
		builder.CreatePickupEntity(.Key, level.GridToWorld(18, 4) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Key, level.GridToWorld(40, 4) + .(0, 0.3f, 0));

		// Two doors
		builder.CreateDoorEntity(level.GridToWorld(44, 4) + .(0, 0.25f, 0));
		builder.CreateDoorEntity(level.GridToWorld(50, 4) + .(0, 0.25f, 0));

		// Coins
		for (int32 i = 0; i < 4; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(5 + i * 3, 5) + .(0, 0.3f, 0));
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(25 + i, 5) + .(0, 0.3f, 0));

		// Gems in harder spots
		builder.CreatePickupEntity(.GemGreen, level.GridToWorld(10, 6) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.GemBlue, level.GridToWorld(33, 6) + .(0, 0.3f, 0));

		// Hearts
		builder.CreatePickupEntity(.Heart, level.GridToWorld(22, 4) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Heart, level.GridToWorld(44, 5) + .(0, 0.3f, 0));

		// Bouncers
		builder.CreateBouncerEntity(level.GridToWorld(6, 4) + .(0, 0.25f, 0));
		builder.CreateBouncerEntity(level.GridToWorld(28, 4) + .(0, 0.25f, 0));

		// Star reward
		builder.CreatePickupEntity(.Star, level.GridToWorld(10, 8) + .(0, 0.3f, 0));
	}
}

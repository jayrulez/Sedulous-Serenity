namespace Platformer.Levels;

using System;
using Platformer.Data;
using Platformer.Components;

/// Level 3: Sky Fortress - Floating platforms, ascending path, and precise jumping.
static class Level03_SkyFortress
{
	public static LevelDefinition Create()
	{
		let level = new LevelDefinition();
		level.Name.Set("Sky Fortress");
		level.AllocateTiles(60, 20);

		// Ascending staircase of floating platforms over void.
		// Platform pairs (G top, D bottom) at 5 tiles wide each.
		// Same-height gaps = 2 tiles, ascending gaps = 1 tile.
		// Platforms: (0-4,y3) (7-11,y3) (13-17,y5) (20-24,y5)
		//           (26-30,y7) (33-37,y7) (39-43,y9) (46-50,y9) (52-59,y11)

		//             000000000011111111112222222222333333333344444444445555555555
		//             012345678901234567890123456789012345678901234567890123456789
		StringView[20] rows = .(
			"............................................................", // 0  void
			"............................................................", // 1  void
			"DDDDD..DDDDD................................................", // 2
			"GGGGG..GGGGG................................................", // 3
			"P............DDDDD..DDDDD...................................", // 4
			".............GGGGG..GGGGG...................................", // 5
			"..........................DDDDD..DDDDD......................", // 6
			"..........................GGGGG..GGGGG......................", // 7
			".......................................DDDDD..DDDDD.........", // 8
			".......................................GGGGG..GGGGG.........", // 9
			"....................................................DDDDDDDD", // 10
			"....................................................GGGGGGGG", // 11
			".......................................................F....", // 12
			"............................................................", // 13
			"............................................................", // 14
			"............................................................", // 15
			"............................................................", // 16
			"............................................................", // 17
			"............................................................", // 18
			"............................................................"  // 19
		);

		for (int32 i = 0; i < 20; i++)
			level.SetRow(i, rows[i]);

		level.SpawnX = 0;
		level.SpawnY = 4;
		level.GoalX = 55;
		level.GoalY = 12;

		// Enemies
		level.Enemies.Add(EnemyPlacement(.Bee, 10, 5, 7, 14));
		level.Enemies.Add(EnemyPlacement(.Bee, 36, 9, 33, 43));
		level.Enemies.Add(EnemyPlacement(.Skull, 56, 12, 53, 58));

		// Moving platforms to help with ascending jumps
		level.MovingPlatforms.Add(MovingPlatformPlacement(11, 4, 13, 5, 1.5f));
		level.MovingPlatforms.Add(MovingPlatformPlacement(50, 10, 52, 10, 2.0f));

		// Moving hazards
		level.MovingHazards.Add(HazardPlacement(.Saw, 24, 5, 24, 7, 2.0f));
		level.MovingHazards.Add(HazardPlacement(.SpikyBall, 35, 8, 40, 8, 3.0f));

		return level;
	}

	public static void PopulateEntities(LevelDefinition level, LevelBuilder builder)
	{
		// Key for door near goal
		builder.CreatePickupEntity(.Key, level.GridToWorld(34, 8) + .(0, 0.3f, 0));

		// Door before goal area
		builder.CreateDoorEntity(level.GridToWorld(52, 12) + .(0, 0.25f, 0));

		// Coins along the path
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(8 + i, 4) + .(0, 0.3f, 0));
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(27 + i, 8) + .(0, 0.3f, 0));

		// Star above the goal platform
		builder.CreatePickupEntity(.Star, level.GridToWorld(57, 13) + .(0, 0.3f, 0));

		// Gems
		builder.CreatePickupEntity(.GemPink, level.GridToWorld(21, 6) + .(0, 0.3f, 0));

		// Heart mid-level
		builder.CreatePickupEntity(.Heart, level.GridToWorld(40, 10) + .(0, 0.3f, 0));
	}
}

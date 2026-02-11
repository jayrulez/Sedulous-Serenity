namespace Platformer.Levels;

using System;
using Platformer.Data;
using Platformer.Components;

/// Level 5: The Final Challenge - Multi-section gauntlet combining all mechanics.
static class Level05_FinalChallenge
{
	public static LevelDefinition Create()
	{
		let level = new LevelDefinition();
		level.Name.Set("The Final Challenge");
		level.AllocateTiles(70, 24);

		// Three sections: Outdoor (0-22), Cave (23-45), Sky Fortress (46-69)
		StringView[24] rows = .(
			"DDDDDDDDDDDDDDDDDDDDDDBBBBBBBBBBBBBBBBBBBBBB............................",  // 0
			"DDDDDDDDDDDDDDDDDDDDDDBBBBBBBBBBBBBBBBBBBBBB............................",  // 1
			"DDDDDDDDDDDDDDDDDDDDDDBBBBBB......BBBBBBBBBB............................",  // 2
			"DDDDD......DDDDDDDDDDDDBB....BBBB....BBBBBBB............................",  // 3
			"GGGGG......GGGGG...GGGGGBB....BBBB.S..BBBBBBB.........GGG...............",  // 4
			"P....GGGGG.............BBB.BBBB....BBBBB...BBB.........DDD...............",  // 5
			"............................BBBB........BBB...BBB.............GGG.........",  // 6
			"........GGGGG.....GGG....BBB.....BBBB....BBB..........GGG...DDD.........",  // 7
			"........DDDDD.....DDD.........BBBB....BBBB.......GGG..DDD...............",  // 8
			".............................BBBB...........GGG...DDD.............GGGGGGG",  // 9
			"..............................................DDD.............GGGG.DDDDDDD",  // 10
			"..................................................GGG........DDDD.DDDDDDD",  // 11
			"..................................................DDD........DDDD.DDDDDDD",  // 12
			".............................................................DDDD.DDDDDDD",  // 13
			".............................................................DDDD.DDDDDDD",  // 14
			"..............................................................GGGG.GGGGGGG",  // 15
			"..............................................................DDDD.DDDDDFG",  // 16
			"......................................................................GGG",  // 17
			"......................................................................DDD",  // 18
			"......................................................................DDD",  // 19
			"......................................................................DDD",  // 20
			"......................................................................DDD",  // 21
			"......................................................................DDD",  // 22
			"......................................................................DDD"   // 23
		);

		for (int32 i = 0; i < 24; i++)
			level.SetRow(i, rows[i]);

		level.SpawnX = 0;
		level.SpawnY = 5;
		level.GoalX = 67;
		level.GoalY = 16;

		// Section A enemies (outdoor)
		level.Enemies.Add(EnemyPlacement(.Slime, 8, 7, 6, 12));
		level.Enemies.Add(EnemyPlacement(.Crab, 15, 5, 12, 18));

		// Section B enemies (cave)
		level.Enemies.Add(EnemyPlacement(.Bee, 30, 7, 27, 35));
		level.Enemies.Add(EnemyPlacement(.Crab, 38, 6, 35, 42));

		// Section C enemies (sky fortress)
		level.Enemies.Add(EnemyPlacement(.Bee, 52, 10, 48, 56));
		level.Enemies.Add(EnemyPlacement(.Skull, 60, 13, 57, 64));

		// Moving platforms
		level.MovingPlatforms.Add(MovingPlatformPlacement(12, 5, 16, 5, 2.0f));  // Section A gap
		level.MovingPlatforms.Add(MovingPlatformPlacement(34, 7, 38, 7, 2.5f));  // Section B
		level.MovingPlatforms.Add(MovingPlatformPlacement(48, 7, 48, 10, 2.0f)); // Section C vertical
		level.MovingPlatforms.Add(MovingPlatformPlacement(56, 10, 60, 10, 3.0f)); // Section C horizontal
		level.MovingPlatforms.Add(MovingPlatformPlacement(62, 12, 62, 15, 2.0f)); // Section C final

		// Moving hazards
		level.MovingHazards.Add(HazardPlacement(.Saw, 26, 5, 26, 8, 2.0f));    // Cave entrance
		level.MovingHazards.Add(HazardPlacement(.Saw, 40, 6, 40, 9, 2.5f));    // Cave mid
		level.MovingHazards.Add(HazardPlacement(.SpikyBall, 54, 9, 58, 9, 3.0f)); // Sky patrol

		return level;
	}

	public static void PopulateEntities(LevelDefinition level, LevelBuilder builder)
	{
		// Three keys required for the final gate
		builder.CreatePickupEntity(.Key, level.GridToWorld(10, 8) + .(0, 0.3f, 0));  // Section A
		builder.CreatePickupEntity(.Key, level.GridToWorld(32, 8) + .(0, 0.3f, 0));  // Section B
		builder.CreatePickupEntity(.Key, level.GridToWorld(55, 12) + .(0, 0.3f, 0)); // Section C

		// Final gate (3 doors stacked)
		builder.CreateDoorEntity(level.GridToWorld(65, 15) + .(0, 0.25f, 0));
		builder.CreateDoorEntity(level.GridToWorld(65, 16) + .(0, 0.25f, 0));

		// Coins through all sections
		// Section A
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(3 + i, 6) + .(0, 0.3f, 0));
		for (int32 i = 0; i < 2; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(18 + i, 5) + .(0, 0.3f, 0));

		// Section B
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(28 + i * 2, 6) + .(0, 0.3f, 0));

		// Section C
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(50 + i, 8) + .(0, 0.3f, 0));

		// Gems as completionist challenge
		builder.CreatePickupEntity(.GemBlue, level.GridToWorld(20, 7) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.GemGreen, level.GridToWorld(36, 9) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.GemPink, level.GridToWorld(58, 11) + .(0, 0.3f, 0));

		// Minimal hearts (1-2)
		builder.CreatePickupEntity(.Heart, level.GridToWorld(24, 5) + .(0, 0.3f, 0));

		// Bouncers for vertical sections
		builder.CreateBouncerEntity(level.GridToWorld(46, 4) + .(0, 0.25f, 0));
		builder.CreateBouncerEntity(level.GridToWorld(62, 9) + .(0, 0.25f, 0));

		// Star at the top of the final tower
		builder.CreatePickupEntity(.Star, level.GridToWorld(68, 17) + .(0, 0.3f, 0));

		// Decorations - trees in outdoor section
		builder.CreateDecorationEntity("tree", level.GridToWorld(2, 5) + .(0, 1.0f, -3.0f), .(1.5f, 1.5f, 1.5f));
		builder.CreateDecorationEntity("bush", level.GridToWorld(14, 5) + .(0, 0.5f, -2.0f), .(0.8f, 0.8f, 0.8f));
	}
}

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

		// Three sections: Outdoor A (x=0-22), Cave B (x=23-45), Sky C (x=46-69)
		// All share ground at row 3. Gaps: A=2, B=3, C=3.
		// Section C floats over void.
		//
		// Row 3 platforms:
		// A: x=0-4, 7-10, 14-17, 20-22
		// B: x=23-26, 30-33, 37-40, 43-45
		// C: x=47-50, 54-58, 62-69

		//             0000000000111111111122222222223333333333444444444455555555556666666666
		//             0123456789012345678901234567890123456789012345678901234567890123456789
		StringView[24] rows = .(
			"DDDDDDDDDDDDDDDDDDDDDDDBBBBBBBBBBBBBBBBBBBBBBBB........................", // 0
			"DDDDDDDDDDDDDDDDDDDDDDDBBBBBBBBBBBBBBBBBBBBBBBB........................", // 1
			"DDDDD..DDDD...DDDD..DDDBBBB...BBBB...BBBB..BBB.DDDD...DDDDD...DDDDDDDD", // 2
			"GGGGG..GGGG...GGGG..GGGBBBB...BBBB...BBBB..BBB.GGGG...GGGGG...GGGGGGGG", // 3
			"P..................................................................F....", // 4
			"......................................................................", // 5
			"......................................................................", // 6
			"......................................................................", // 7
			"......................................................................", // 8
			"......................................................................", // 9
			"......................................................................", // 10
			"......................................................................", // 11
			"......................................................................", // 12
			"......................................................................", // 13
			"......................................................................", // 14
			"......................................................................", // 15
			"......................................................................", // 16
			"......................................................................", // 17
			"......................................................................", // 18
			"......................................................................", // 19
			"......................................................................", // 20
			"......................................................................", // 21
			"......................................................................", // 22
			"......................................................................"  // 23
		);

		for (int32 i = 0; i < 24; i++)
			level.SetRow(i, rows[i]);

		level.SpawnX = 0;
		level.SpawnY = 4;
		level.GoalX = 66;
		level.GoalY = 4;

		// Section A enemies (outdoor)
		level.Enemies.Add(EnemyPlacement(.Slime, 8, 4, 7, 10));
		level.Enemies.Add(EnemyPlacement(.Crab, 15, 4, 14, 17));

		// Section B enemies (cave)
		level.Enemies.Add(EnemyPlacement(.Bee, 30, 6, 27, 35));
		level.Enemies.Add(EnemyPlacement(.Crab, 38, 4, 37, 40));

		// Section C enemies (sky fortress)
		level.Enemies.Add(EnemyPlacement(.Bee, 55, 6, 50, 60));
		level.Enemies.Add(EnemyPlacement(.Skull, 65, 4, 62, 68));

		// Moving platforms
		level.MovingPlatforms.Add(MovingPlatformPlacement(33, 5, 37, 5, 2.0f));  // Section B bridge
		level.MovingPlatforms.Add(MovingPlatformPlacement(50, 4, 54, 4, 2.5f));  // Section C bridge

		// Moving hazards
		level.MovingHazards.Add(HazardPlacement(.Saw, 22, 4, 22, 7, 2.0f));     // A-B transition
		level.MovingHazards.Add(HazardPlacement(.Saw, 52, 4, 52, 7, 2.5f));     // C mid
		level.MovingHazards.Add(HazardPlacement(.SpikyBall, 58, 5, 63, 5, 3.0f)); // C late

		return level;
	}

	public static void PopulateEntities(LevelDefinition level, LevelBuilder builder)
	{
		// Three keys required
		builder.CreatePickupEntity(.Key, level.GridToWorld(10, 4) + .(0, 0.3f, 0));  // Section A
		builder.CreatePickupEntity(.Key, level.GridToWorld(35, 4) + .(0, 0.3f, 0));  // Section B
		builder.CreatePickupEntity(.Key, level.GridToWorld(56, 4) + .(0, 0.3f, 0));  // Section C

		// Doors between sections and before goal
		builder.CreateDoorEntity(level.GridToWorld(43, 4) + .(0, 0.25f, 0));  // End of B
		builder.CreateDoorEntity(level.GridToWorld(62, 4) + .(0, 0.25f, 0));  // Before goal

		// Coins - Section A
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(3 + i, 5) + .(0, 0.3f, 0));
		// Coins - Section B
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(28 + i * 2, 5) + .(0, 0.3f, 0));
		// Coins - Section C
		for (int32 i = 0; i < 3; i++)
			builder.CreatePickupEntity(.Coin, level.GridToWorld(48 + i, 5) + .(0, 0.3f, 0));

		// Gems as completionist challenge
		builder.CreatePickupEntity(.GemBlue, level.GridToWorld(20, 5) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.GemGreen, level.GridToWorld(36, 5) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.GemPink, level.GridToWorld(58, 5) + .(0, 0.3f, 0));

		// Hearts (sparse - final challenge is hard)
		builder.CreatePickupEntity(.Heart, level.GridToWorld(24, 4) + .(0, 0.3f, 0));

		// Bouncers
		builder.CreateBouncerEntity(level.GridToWorld(3, 4) + .(0, 0.25f, 0));
		builder.CreateBouncerEntity(level.GridToWorld(47, 4) + .(0, 0.25f, 0));

		// Star at the end
		builder.CreatePickupEntity(.Star, level.GridToWorld(68, 5) + .(0, 0.3f, 0));

		// Decorations - trees in outdoor section
		builder.CreateDecorationEntity("tree", level.GridToWorld(2, 4) + .(0, 1.0f, -3.0f), .(1.5f, 1.5f, 1.5f));
		builder.CreateDecorationEntity("bush", level.GridToWorld(14, 4) + .(0, 0.5f, -2.0f), .(0.8f, 0.8f, 0.8f));
	}
}

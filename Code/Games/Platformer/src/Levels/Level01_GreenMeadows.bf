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

		//              0000000000111111111122222222223333333333
		//              0123456789012345678901234567890123456789
		StringView[12] rows = .(
			"DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD", // 0  solid ground
			"DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD", // 1  solid ground
			"DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD", // 2  solid ground
			"DDDD............................DDDDDDDD", // 3  underground
			"GGGG..GGGGG..GGGG..GGGG..GGGGG..GGGGGGGG", // 4  grass surface
			"P.....................................F.", // 5  player / goal
			"........................................", // 6
			"........................................", // 7
			"........................................", // 8
			"........................................", // 9
			"........................................", // 10
			"........................................"  // 11
		);

		for (int32 i = 0; i < 12; i++)
			level.SetRow(i, rows[i]);

		level.SpawnX = 0;
		level.SpawnY = 5;
		level.GoalX = 38;
		level.GoalY = 5;

		// Slime on the last platform
		level.Enemies.Add(EnemyPlacement(.Slime, 35, 5, 33, 38));

		return level;
	}

	/// Populates entity placements from the grid.
	public static void PopulateEntities(LevelDefinition level, LevelBuilder builder)
	{
		// Coins above the second platform
		builder.CreatePickupEntity(.Coin, level.GridToWorld(7, 6) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(8, 6) + .(0, 0.3f, 0));
		builder.CreatePickupEntity(.Coin, level.GridToWorld(9, 6) + .(0, 0.3f, 0));

		// Coin near the end
		builder.CreatePickupEntity(.Coin, level.GridToWorld(34, 6) + .(0, 0.3f, 0));

		// Trees (decorations behind the play area)
		builder.CreateDecorationEntity("tree", level.GridToWorld(15, 8) + .(0, 0.5f, -3.0f), .(1.5f, 1.5f, 1.5f));
		builder.CreateDecorationEntity("tree", level.GridToWorld(30, 8) + .(0, 0.5f, -3.0f), .(1.5f, 1.5f, 1.5f));

		// Bushes
		builder.CreateDecorationEntity("bush", level.GridToWorld(3, 5) + .(0, 0.5f, -2.0f), .(0.8f, 0.8f, 0.8f));
		builder.CreateDecorationEntity("bush", level.GridToWorld(20, 5) + .(0, 0.5f, -2.0f), .(0.8f, 0.8f, 0.8f));
	}
}

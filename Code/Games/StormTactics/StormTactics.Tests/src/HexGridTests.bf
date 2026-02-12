using System;
using System.Collections;
using StormTactics.Battle;
using StormTactics.Core;

namespace StormTactics.Tests;

class HexGridTests
{
	[Test]
	public static void TestGridCreation()
	{
		let grid = scope HexGrid(7, 5);
		Test.Assert(grid.Columns == 7);
		Test.Assert(grid.Rows == 5);

		// All cells should start walkable
		let hex = HexCoord.FromOffset(0, 0);
		Test.Assert(grid.GetState(hex) == .Walkable);
	}

	[Test]
	public static void TestBounds()
	{
		let grid = scope HexGrid(7, 5);

		Test.Assert(grid.InBounds(0, 0));
		Test.Assert(grid.InBounds(6, 4));
		Test.Assert(!grid.InBounds(-1, 0));
		Test.Assert(!grid.InBounds(7, 0));
		Test.Assert(!grid.InBounds(0, 5));
	}

	[Test]
	public static void TestOccupant()
	{
		let grid = scope HexGrid(7, 5);
		let hex = HexCoord.FromOffset(3, 2);

		Test.Assert(grid.GetOccupant(hex) == -1);
		Test.Assert(grid.IsPassable(hex));

		grid.SetOccupant(hex, 5);
		Test.Assert(grid.GetOccupant(hex) == 5);
		Test.Assert(grid.GetState(hex) == .Occupied);
		Test.Assert(!grid.IsPassable(hex));

		grid.ClearOccupant(hex);
		Test.Assert(grid.GetOccupant(hex) == -1);
		Test.Assert(grid.IsPassable(hex));
	}

	[Test]
	public static void TestBlockedCell()
	{
		let grid = scope HexGrid(7, 5);
		let hex = HexCoord.FromOffset(2, 1);

		grid.SetState(hex, .Blocked);
		Test.Assert(!grid.IsPassable(hex));
		Test.Assert(!grid.IsPassableFlying(hex)); // Blocked is blocked even for flying
	}

	[Test]
	public static void TestGetHexesInRange()
	{
		let grid = scope HexGrid(10, 10);
		let center = HexCoord.FromOffset(5, 5);
		let hexes = scope List<HexCoord>();

		grid.GetHexesInRange(center, 1, hexes);

		// Center + 6 neighbors = 7 (if all in bounds)
		Test.Assert(hexes.Count == 7);

		// Center should be included
		bool hasCenter = false;
		for (let h in hexes)
			if (h == center) hasCenter = true;
		Test.Assert(hasCenter);
	}

	[Test]
	public static void TestAttackPatternPoint()
	{
		let grid = scope HexGrid(7, 5);
		let attacker = HexCoord.FromOffset(2, 2);
		let target = HexCoord.FromOffset(3, 2);
		let cells = scope List<HexCoord>();

		grid.GetAttackPatternCells(attacker, target, .Point, cells);
		Test.Assert(cells.Count == 1);
		Test.Assert(cells[0] == target);
	}

	[Test]
	public static void TestAttackPatternAroundTarget()
	{
		let grid = scope HexGrid(10, 10);
		let attacker = HexCoord.FromOffset(3, 5);
		let target = HexCoord.FromOffset(5, 5);
		let cells = scope List<HexCoord>();

		grid.GetAttackPatternCells(attacker, target, .AroundTarget, cells);

		// Target + up to 6 neighbors
		Test.Assert(cells.Count >= 1);

		// Target should be in the list
		bool hasTarget = false;
		for (let h in cells)
			if (h == target) hasTarget = true;
		Test.Assert(hasTarget);
	}
}

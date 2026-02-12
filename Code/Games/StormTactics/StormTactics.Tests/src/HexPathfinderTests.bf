using System;
using System.Collections;
using StormTactics.Battle;
using StormTactics.Core;

namespace StormTactics.Tests;

class HexPathfinderTests
{
	[Test]
	public static void TestPathOpenField()
	{
		let grid = scope HexGrid(10, 10);
		let pathfinder = scope HexPathfinder(grid);

		let start = HexCoord.FromOffset(1, 1);
		let goal = HexCoord.FromOffset(4, 1);
		let path = scope List<HexCoord>();

		let found = pathfinder.FindPath(start, goal, false, path);
		Test.Assert(found);
		Test.Assert(path.Count > 0);
		Test.Assert(path[0] == start);
		Test.Assert(path[path.Count - 1] == goal);

		// Path should be optimal (straight line)
		let dist = start.DistanceTo(goal);
		Test.Assert(path.Count == dist + 1);
	}

	[Test]
	public static void TestPathAroundObstacle()
	{
		let grid = scope HexGrid(10, 10);

		// Block a cell between start and goal
		let blocker = HexCoord.FromOffset(3, 2);
		grid.SetState(blocker, .Blocked);

		let pathfinder = scope HexPathfinder(grid);
		let start = HexCoord.FromOffset(2, 2);
		let goal = HexCoord.FromOffset(4, 2);
		let path = scope List<HexCoord>();

		let found = pathfinder.FindPath(start, goal, false, path);
		Test.Assert(found);
		Test.Assert(path[0] == start);
		Test.Assert(path[path.Count - 1] == goal);

		// Path should not go through blocker
		for (let hex in path)
			Test.Assert(hex != blocker);
	}

	[Test]
	public static void TestPathUnreachable()
	{
		let grid = scope HexGrid(7, 5);
		let goal = HexCoord.FromOffset(3, 2);

		// Surround goal with blocked cells
		for (int dir = 0; dir < 6; dir++)
		{
			let neighbor = goal.Neighbor(dir);
			if (grid.InBounds(neighbor))
				grid.SetState(neighbor, .Blocked);
		}

		// Also block the goal itself
		grid.SetState(goal, .Blocked);

		let pathfinder = scope HexPathfinder(grid);
		let start = HexCoord.FromOffset(0, 0);
		let path = scope List<HexCoord>();

		let found = pathfinder.FindPath(start, goal, false, path);
		Test.Assert(!found);
	}

	[Test]
	public static void TestPathSameStartAndGoal()
	{
		let grid = scope HexGrid(7, 5);
		let pathfinder = scope HexPathfinder(grid);

		let start = HexCoord.FromOffset(2, 2);
		let path = scope List<HexCoord>();

		let found = pathfinder.FindPath(start, start, false, path);
		Test.Assert(found);
		Test.Assert(path.Count == 1);
		Test.Assert(path[0] == start);
	}

	[Test]
	public static void TestFlyingOverUnits()
	{
		let grid = scope HexGrid(10, 10);

		// Place a unit (occupant) blocking the direct path
		let blocker = HexCoord.FromOffset(3, 2);
		grid.SetOccupant(blocker, 99);

		let pathfinder = scope HexPathfinder(grid);
		let start = HexCoord.FromOffset(2, 2);
		let goal = HexCoord.FromOffset(4, 2);

		// Land unit cannot pass through occupied cell
		let landPath = scope List<HexCoord>();
		let landFound = pathfinder.FindPath(start, goal, false, landPath);
		Test.Assert(landFound);
		for (let hex in landPath)
			Test.Assert(hex != blocker); // Should route around

		// Flying unit CAN pass through occupied cell
		let flyPath = scope List<HexCoord>();
		let flyFound = pathfinder.FindPath(start, goal, true, flyPath);
		Test.Assert(flyFound);
		// Flying path should be shorter or equal (can pass through)
		Test.Assert(flyPath.Count <= landPath.Count);
	}

	[Test]
	public static void TestReachableCells()
	{
		let grid = scope HexGrid(10, 10);
		let pathfinder = scope HexPathfinder(grid);

		let start = HexCoord.FromOffset(5, 5);
		let reachable = scope List<HexCoord>();

		pathfinder.GetReachableCells(start, 1, false, reachable);

		// Should have 6 reachable neighbors (all in bounds on a 10x10 grid)
		Test.Assert(reachable.Count == 6);

		// Start should NOT be in reachable list
		for (let hex in reachable)
			Test.Assert(hex != start);

		// All reachable should be distance 1
		for (let hex in reachable)
			Test.Assert(start.DistanceTo(hex) == 1);
	}

	[Test]
	public static void TestReachableCellsRange2()
	{
		let grid = scope HexGrid(10, 10);
		let pathfinder = scope HexPathfinder(grid);

		let start = HexCoord.FromOffset(5, 5);
		let reachable = scope List<HexCoord>();

		pathfinder.GetReachableCells(start, 2, false, reachable);

		// Ring 1 = 6, ring 2 = 12, total = 18
		Test.Assert(reachable.Count == 18);

		// All should be within distance 2
		for (let hex in reachable)
			Test.Assert(start.DistanceTo(hex) <= 2);
	}

	[Test]
	public static void TestReachableBlockedReduces()
	{
		let grid = scope HexGrid(10, 10);
		let pathfinder = scope HexPathfinder(grid);
		let start = HexCoord.FromOffset(5, 5);

		// Get baseline reachable count
		let baseline = scope List<HexCoord>();
		pathfinder.GetReachableCells(start, 2, false, baseline);
		let baseCount = baseline.Count;

		// Block some neighbors
		for (int dir = 0; dir < 3; dir++)
		{
			let neighbor = start.Neighbor(dir);
			grid.SetState(neighbor, .Blocked);
		}

		let blocked = scope List<HexCoord>();
		pathfinder.GetReachableCells(start, 2, false, blocked);

		// Should have fewer reachable cells
		Test.Assert(blocked.Count < baseCount);
	}
}

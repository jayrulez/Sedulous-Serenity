using System;
using System.Collections;
using StormTactics.Battle;

namespace StormTactics.Tests;

class HexCoordTests
{
	[Test]
	public static void TestDistance()
	{
		let a = HexCoord(0, 0);
		let b = HexCoord(2, -1);
		Test.Assert(a.DistanceTo(b) == 2);

		let c = HexCoord(0, 0);
		let d = HexCoord(0, 3);
		Test.Assert(c.DistanceTo(d) == 3);

		// Distance to self is 0
		Test.Assert(a.DistanceTo(a) == 0);
	}

	[Test]
	public static void TestNeighbors()
	{
		let center = HexCoord(0, 0);
		let neighbors = scope List<HexCoord>();
		center.GetNeighbors(neighbors);

		Test.Assert(neighbors.Count == 6);

		// All neighbors should be distance 1
		for (let n in neighbors)
			Test.Assert(center.DistanceTo(n) == 1);
	}

	[Test]
	public static void TestEquality()
	{
		let a = HexCoord(3, -2);
		let b = HexCoord(3, -2);
		let c = HexCoord(3, -1);

		Test.Assert(a == b);
		Test.Assert(a != c);
	}

	[Test]
	public static void TestArithmetic()
	{
		let a = HexCoord(1, 2);
		let b = HexCoord(3, -1);

		let sum = a + b;
		Test.Assert(sum.Q == 4 && sum.R == 1);

		let diff = a - b;
		Test.Assert(diff.Q == -2 && diff.R == 3);

		let scaled = a * 3;
		Test.Assert(scaled.Q == 3 && scaled.R == 6);
	}

	[Test]
	public static void TestCubeConstraint()
	{
		// q + r + s should always == 0
		let hex = HexCoord(3, -5);
		Test.Assert(hex.Q + hex.R + hex.S == 0);
	}

	[Test]
	public static void TestRing()
	{
		let center = HexCoord(0, 0);
		let ring = scope List<HexCoord>();
		center.GetRing(1, ring);

		// Ring of radius 1 should have 6 hexes
		Test.Assert(ring.Count == 6);

		// All should be at distance 1
		for (let h in ring)
			Test.Assert(center.DistanceTo(h) == 1);

		ring.Clear();
		center.GetRing(2, ring);

		// Ring of radius 2 should have 12 hexes
		Test.Assert(ring.Count == 12);

		for (let h in ring)
			Test.Assert(center.DistanceTo(h) == 2);
	}

	[Test]
	public static void TestSpiral()
	{
		let center = HexCoord(0, 0);
		let spiral = scope List<HexCoord>();
		center.GetSpiral(1, spiral);

		// Spiral radius 1 = center (1) + ring1 (6) = 7
		Test.Assert(spiral.Count == 7);
		Test.Assert(spiral[0] == center);
	}

	[Test]
	public static void TestLineDraw()
	{
		let a = HexCoord(0, 0);
		let b = HexCoord(3, 0);
		let line = scope List<HexCoord>();
		a.LineTo(b, line);

		// Should include start and end, total 4 hexes
		Test.Assert(line.Count == 4);
		Test.Assert(line[0] == a);
		Test.Assert(line[3] == b);

		// Each step should be distance 1 from previous
		for (int i = 1; i < line.Count; i++)
			Test.Assert(line[i - 1].DistanceTo(line[i]) == 1);
	}

	[Test]
	public static void TestOffsetRoundTrip()
	{
		let original = HexCoord(3, -2);
		let (col, row) = original.ToOffset();
		let restored = HexCoord.FromOffset(col, row);
		Test.Assert(original == restored);

		// Test several values
		let coords = scope HexCoord[](.(0, 0), .(1, 1), .(-1, 2), .(4, -3));
		for (let hex in coords)
		{
			let (c, r) = hex.ToOffset();
			let back = HexCoord.FromOffset(c, r);
			Test.Assert(hex == back);
		}
	}

	[Test]
	public static void TestWorldRoundTrip()
	{
		let hexSize = 1.0f;
		let original = HexCoord(2, -1);
		let (wx, wz) = original.ToWorld(hexSize);
		let restored = HexCoord.FromWorld(wx, wz, hexSize);
		Test.Assert(original == restored);
	}
}

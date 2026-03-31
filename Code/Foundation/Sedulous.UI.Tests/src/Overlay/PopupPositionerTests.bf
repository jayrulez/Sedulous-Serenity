using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class PopupPositionerTests
{
	[Test]
	public static void BestFit_FitsBelow()
	{
		// Popup fits below anchor
		let pos = PopupPositioner.PositionBestFit(100, 50, .(50, 30, 100, 20), 400, 300);
		Test.Assert(pos.X == 50); // Left-aligned with anchor
		Test.Assert(pos.Y == 50); // Below anchor (30 + 20)
	}

	[Test]
	public static void BestFit_FlipsAbove()
	{
		// Popup doesn't fit below, flips above
		let pos = PopupPositioner.PositionBestFit(100, 50, .(50, 240, 100, 20), 400, 300);
		// Below would be Y=260, clips at 300 (260+50>300). Above = 240-50 = 190.
		Test.Assert(pos.Y == 190);
	}

	[Test]
	public static void BestFit_ClampsRight()
	{
		// Popup extends beyond right edge
		let pos = PopupPositioner.PositionBestFit(100, 50, .(350, 30, 100, 20), 400, 300);
		Test.Assert(pos.X == 300); // Clamped: 400 - 100 = 300
	}

	[Test]
	public static void BestFit_ClampsLeft()
	{
		// Anchor at far left, popup wider than available
		let pos = PopupPositioner.PositionBestFit(100, 50, .(-50, 30, 30, 20), 400, 300);
		Test.Assert(pos.X == 0); // Clamped to 0
	}

	[Test]
	public static void PositionBelow_Basic()
	{
		let pos = PopupPositioner.PositionBelow(80, 40, .(100, 50, 60, 30), 400, 300);
		Test.Assert(pos.X == 100);
		Test.Assert(pos.Y == 80); // 50 + 30
	}

	[Test]
	public static void PositionAbove_Basic()
	{
		let pos = PopupPositioner.PositionAbove(80, 40, .(100, 100, 60, 30), 400, 300);
		Test.Assert(pos.X == 100);
		Test.Assert(pos.Y == 60); // 100 - 40
	}

	[Test]
	public static void BestFit_ZeroSizeAnchor()
	{
		// Anchor is a point (context menu position)
		let pos = PopupPositioner.PositionBestFit(120, 200, .(150, 100, 0, 0), 400, 300);
		Test.Assert(pos.X == 150);
		Test.Assert(pos.Y == 100);
	}

	[Test]
	public static void BestFit_ClampsBottom()
	{
		// Both below and above don't fit perfectly, clamp to bottom
		let pos = PopupPositioner.PositionBestFit(100, 250, .(50, 100, 100, 20), 400, 300);
		// Below: Y=120, 120+250=370 > 300. Above: Y=100-250=-150 < 0, so stay below.
		// Final clamp: Y = 300-250 = 50
		Test.Assert(pos.Y == 50);
	}
}

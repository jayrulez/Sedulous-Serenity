using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class GravityTests
{
	[Test]
	public static void Apply_None_DefaultsToTopLeft()
	{
		float x, y, w, h;
		GravityHelper.Apply(.None, 200, 200, 50, 50, .Zero, out x, out y, out w, out h);
		Test.Assert(x == 0);
		Test.Assert(y == 0);
		Test.Assert(w == 50);
		Test.Assert(h == 50);
	}

	[Test]
	public static void Apply_Center_CentersChild()
	{
		float x, y, w, h;
		GravityHelper.Apply(.Center, 200, 200, 50, 50, .Zero, out x, out y, out w, out h);
		Test.Assert(x == 75);
		Test.Assert(y == 75);
		Test.Assert(w == 50);
		Test.Assert(h == 50);
	}

	[Test]
	public static void Apply_RightBottom_PushesToEnd()
	{
		float x, y, w, h;
		GravityHelper.Apply(.Right | .Bottom, 200, 200, 50, 50, .Zero, out x, out y, out w, out h);
		Test.Assert(x == 150);
		Test.Assert(y == 150);
		Test.Assert(w == 50);
		Test.Assert(h == 50);
	}

	[Test]
	public static void Apply_FillH_ExpandsWidth()
	{
		float x, y, w, h;
		GravityHelper.Apply(.FillH, 200, 200, 50, 50, .Zero, out x, out y, out w, out h);
		Test.Assert(x == 0);
		Test.Assert(w == 200);
		Test.Assert(h == 50); // Vertical not filled
	}

	[Test]
	public static void Apply_Fill_ExpandsBoth()
	{
		float x, y, w, h;
		GravityHelper.Apply(.Fill, 200, 200, 50, 50, .Zero, out x, out y, out w, out h);
		Test.Assert(x == 0);
		Test.Assert(y == 0);
		Test.Assert(w == 200);
		Test.Assert(h == 200);
	}

	[Test]
	public static void Apply_CenterH_WithMargin()
	{
		float x, y, w, h;
		// Available = 200 - 10 - 10 = 180, center 50 within 180 => x = 10 + (180-50)/2 = 75
		GravityHelper.Apply(.CenterH, 200, 200, 50, 50, .(10, 0, 10, 0), out x, out y, out w, out h);
		Test.Assert(x == 75);
		Test.Assert(w == 50);
	}

	[Test]
	public static void Apply_Right_WithMargin()
	{
		float x, y, w, h;
		// x = 200 - 20 - 50 = 130
		GravityHelper.Apply(.Right, 200, 200, 50, 50, .(0, 0, 20, 0), out x, out y, out w, out h);
		Test.Assert(x == 130);
		Test.Assert(w == 50);
	}

	[Test]
	public static void Apply_FillH_WithMargin_ReducesAvailable()
	{
		float x, y, w, h;
		// Available width = 200 - 10 - 10 = 180
		GravityHelper.Apply(.FillH | .Top, 200, 100, 50, 50, .(10, 5, 10, 5), out x, out y, out w, out h);
		Test.Assert(x == 10);
		Test.Assert(w == 180);
		Test.Assert(y == 5);
		Test.Assert(h == 50);
	}
}

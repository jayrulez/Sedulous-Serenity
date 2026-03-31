using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class HitTestTransformTests
{
	[Test]
	public static void HitTest_WithTranslation()
	{
		let v = scope TestView();
		v.Layout(0, 0, 100, 100);

		// Translate the view by (50, 50) — center origin means we shift around center
		v.RenderTransform = Matrix.CreateTranslation(50, 50, 0);
		v.RenderTransformOrigin = .(0, 0); // origin at top-left for simpler math

		// The view is at (0,0) size 100x100, but shifted by (50,50)
		// So the visual is at (50,50)-(150,150)
		// In parent coords (0,0) should miss (it's before the shifted view)
		Test.Assert(v.HitTest(.(25, 25)) == null);

		// (75, 75) should hit (inside shifted view)
		Test.Assert(v.HitTest(.(75, 75)) == v);
	}

	[Test]
	public static void HitTest_WithScale()
	{
		let v = scope TestView();
		v.Layout(0, 0, 100, 100);

		// Scale 2x around top-left origin
		v.RenderTransform = Matrix.CreateScale(2, 2, 1);
		v.RenderTransformOrigin = .(0, 0);

		// The view visually covers (0,0)-(200,200)
		// (150, 150) is inside the scaled view
		Test.Assert(v.HitTest(.(150, 150)) == v);

		// Without transform, (150,150) would be outside 100x100
		v.RenderTransform = Matrix.Identity;
		Test.Assert(v.HitTest(.(150, 150)) == null);
	}

	[Test]
	public static void HitTest_NoTransform_Simple()
	{
		let v = scope TestView();
		v.Layout(20, 30, 60, 40);

		// Inside
		Test.Assert(v.HitTest(.(50, 50)) == v);
		// Outside
		Test.Assert(v.HitTest(.(10, 10)) == null);
		// Edge (exact left, top)
		Test.Assert(v.HitTest(.(20, 30)) == v);
	}

	[Test]
	public static void ToScreen_SimpleChain()
	{
		let parent = scope TestViewGroup();
		let child = new TestView();
		parent.[Friend]AddViewInternal(child);

		parent.Layout(10, 20, 200, 200);
		child.Layout(5, 5, 50, 50);

		// child local (0,0) -> parent local (5,5) -> screen (15, 25)
		let screen = child.ToScreen(.(0, 0));
		Test.Assert(screen.X == 15);
		Test.Assert(screen.Y == 25);
	}

	[Test]
	public static void ToLocal_RoundTrips()
	{
		let parent = scope TestViewGroup();
		let child = new TestView();
		parent.[Friend]AddViewInternal(child);

		parent.Layout(10, 20, 200, 200);
		child.Layout(30, 40, 50, 50);

		let screenPoint = Vector2(60, 80);
		let local = child.ToLocal(screenPoint);
		let backToScreen = child.ToScreen(local);

		// Should round-trip within floating point tolerance
		Test.Assert(Math.Abs(backToScreen.X - screenPoint.X) < 0.01f);
		Test.Assert(Math.Abs(backToScreen.Y - screenPoint.Y) < 0.01f);
	}
}

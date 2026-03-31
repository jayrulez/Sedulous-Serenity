using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class ColorAnimationTests
{
	[Test]
	public static void ColorAnimation_InterpolatesCorrectly()
	{
		Color result = Color.Black;
		let from = Color(0, 0, 0, 255);
		let to = Color(255, 255, 255, 255);
		let anim = scope ColorAnimation(from, to, 1.0f, new [&] (c) => { result = c; });
		anim.Start();

		anim.Update(0.5f);
		// At midpoint, each channel should be ~127-128
		Test.Assert(result.R >= 126 && result.R <= 129);
		Test.Assert(result.G >= 126 && result.G <= 129);
		Test.Assert(result.B >= 126 && result.B <= 129);
		Test.Assert(result.A == 255);
	}

	[Test]
	public static void ColorAnimation_CompletesToTarget()
	{
		Color result = Color.Black;
		let from = Color(0, 0, 0, 255);
		let to = Color(255, 0, 128, 255);
		let anim = scope ColorAnimation(from, to, 0.5f, new [&] (c) => { result = c; });
		anim.Start();

		anim.Update(0.5f);
		Test.Assert(anim.IsComplete);
		Test.Assert(result.R == 255);
		Test.Assert(result.G == 0);
		Test.Assert(result.B == 128);
	}

	[Test]
	public static void ColorAnimation_WithEasing()
	{
		Color result = Color.Black;
		let from = Color(0, 0, 0, 255);
		let to = Color(200, 200, 200, 255);
		let anim = scope ColorAnimation(from, to, 1.0f, new [&] (c) => { result = c; }, Easings.EaseInQuadratic);
		anim.Start();

		anim.Update(0.5f);
		// EaseInQuadratic(0.5) = 0.25, so channels should be ~50
		Test.Assert(result.R >= 48 && result.R <= 52);
	}

	[Test]
	public static void ColorAnimation_AlphaChannel()
	{
		Color result = Color.Black;
		let from = Color(100, 100, 100, 0);
		let to = Color(100, 100, 100, 255);
		let anim = scope ColorAnimation(from, to, 1.0f, new [&] (c) => { result = c; });
		anim.Start();

		anim.Update(0.5f);
		Test.Assert(result.A >= 126 && result.A <= 129);
		Test.Assert(result.R >= 99 && result.R <= 101); // R should stay ~100
	}
}

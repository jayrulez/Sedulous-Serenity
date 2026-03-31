using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class FloatAnimationTests
{
	[Test]
	public static void FloatAnimation_InitialState()
	{
		float result = 0;
		let anim = scope FloatAnimation(0, 100, 1.0f, new [&] (v) => { result = v; });
		Test.Assert(!anim.IsRunning);
		Test.Assert(!anim.IsComplete);
		Test.Assert(anim.Duration == 1.0f);
		Test.Assert(anim.From == 0);
		Test.Assert(anim.To == 100);
	}

	[Test]
	public static void FloatAnimation_StartAndUpdate()
	{
		float result = 0;
		let anim = scope FloatAnimation(0, 100, 1.0f, new [&] (v) => { result = v; });
		anim.Start();
		Test.Assert(anim.IsRunning);

		anim.Update(0.5f); // Half-way
		Test.Assert(Math.Abs(result - 50) < 0.01f);
		Test.Assert(!anim.IsComplete);

		anim.Update(0.5f); // Complete
		Test.Assert(Math.Abs(result - 100) < 0.01f);
		Test.Assert(anim.IsComplete);
		Test.Assert(!anim.IsRunning);
	}

	[Test]
	public static void FloatAnimation_WithEasing()
	{
		float result = 0;
		let anim = scope FloatAnimation(0, 100, 1.0f, new [&] (v) => { result = v; }, Easings.EaseInQuadratic);
		anim.Start();

		anim.Update(0.5f); // Half-way with quadratic ease-in
		// EaseInQuadratic(0.5) = 0.25, so value should be 25
		Test.Assert(Math.Abs(result - 25) < 0.01f);
	}

	[Test]
	public static void FloatAnimation_Delay()
	{
		float result = -1;
		let anim = scope FloatAnimation(0, 100, 1.0f, new [&] (v) => { result = v; });
		anim.Delay = 0.5f;
		anim.Start();

		anim.Update(0.3f); // Still in delay
		Test.Assert(result == -1); // Setter not called during delay

		anim.Update(0.7f); // 0.3 + 0.7 = 1.0, past delay by 0.5s
		Test.Assert(Math.Abs(result - 50) < 0.01f); // Half of active duration

		anim.Update(0.5f); // Complete
		Test.Assert(Math.Abs(result - 100) < 0.01f);
		Test.Assert(anim.IsComplete);
	}

	[Test]
	public static void FloatAnimation_Repeat()
	{
		float result = 0;
		int completeCount = 0;
		let anim = scope FloatAnimation(0, 100, 0.5f, new [&] (v) => { result = v; });
		anim.RepeatCount = 1; // Play twice total
		anim.OnComplete.Subscribe(new [&] (a) => { completeCount++; });
		anim.Start();

		anim.Update(0.5f); // First cycle complete
		Test.Assert(!anim.IsComplete); // Still has one repeat left

		anim.Update(0.5f); // Second cycle complete
		Test.Assert(anim.IsComplete);
		Test.Assert(completeCount == 1);
	}

	[Test]
	public static void FloatAnimation_StopAndResume()
	{
		float result = 0;
		let anim = scope FloatAnimation(0, 100, 1.0f, new [&] (v) => { result = v; });
		anim.Start();

		anim.Update(0.3f);
		Test.Assert(Math.Abs(result - 30) < 0.01f);

		anim.Stop();
		Test.Assert(!anim.IsRunning);

		anim.Update(0.3f); // Should not advance
		Test.Assert(Math.Abs(result - 30) < 0.01f);

		anim.Start();
		anim.Update(0.7f); // Should complete
		Test.Assert(Math.Abs(result - 100) < 0.01f);
		Test.Assert(anim.IsComplete);
	}

	[Test]
	public static void FloatAnimation_Reset()
	{
		float result = 0;
		let anim = scope FloatAnimation(0, 100, 1.0f, new [&] (v) => { result = v; });
		anim.Start();
		anim.Update(1.0f);
		Test.Assert(anim.IsComplete);

		anim.Reset();
		Test.Assert(!anim.IsComplete);
		Test.Assert(!anim.IsRunning);
		Test.Assert(anim.Elapsed == 0);

		anim.Start();
		anim.Update(0.5f);
		Test.Assert(Math.Abs(result - 50) < 0.01f);
	}

	[Test]
	public static void FloatAnimation_ZeroDuration()
	{
		float result = 0;
		let anim = scope FloatAnimation(0, 100, 0, new [&] (v) => { result = v; });
		anim.Start();

		let complete = anim.Update(0.016f);
		Test.Assert(complete);
		Test.Assert(Math.Abs(result - 100) < 0.01f);
	}

	[Test]
	public static void FloatAnimation_OnComplete_Fires()
	{
		float result = 0;
		bool completed = false;
		let anim = scope FloatAnimation(0, 100, 0.5f, new [&] (v) => { result = v; });
		anim.OnComplete.Subscribe(new [&] (a) => { completed = true; });
		anim.Start();

		anim.Update(0.5f);
		Test.Assert(completed);
	}

	[Test]
	public static void FloatAnimation_NegativeValues()
	{
		float result = 0;
		let anim = scope FloatAnimation(50, -50, 1.0f, new [&] (v) => { result = v; });
		anim.Start();

		anim.Update(0.5f);
		Test.Assert(Math.Abs(result - 0) < 0.01f); // Midpoint of 50 to -50

		anim.Update(0.5f);
		Test.Assert(Math.Abs(result - (-50)) < 0.01f);
	}
}

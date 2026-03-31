using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class StoryboardTests
{
	[Test]
	public static void Storyboard_Sequential_PlaysInOrder()
	{
		float a = 0, b = 0;
		let sb = scope Storyboard(.Sequential);
		sb.Add(new FloatAnimation(0, 100, 0.5f, new [&] (v) => { a = v; }));
		sb.Add(new FloatAnimation(0, 200, 0.5f, new [&] (v) => { b = v; }));

		sb.Start();

		sb.Update(0.25f);
		Test.Assert(Math.Abs(a - 50) < 0.01f);
		Test.Assert(b == 0); // Second hasn't started

		sb.Update(0.25f); // First completes
		Test.Assert(Math.Abs(a - 100) < 0.01f);

		sb.Update(0.25f); // Second at halfway
		Test.Assert(Math.Abs(b - 100) < 0.01f);

		sb.Update(0.25f); // Second completes
		Test.Assert(Math.Abs(b - 200) < 0.01f);
		Test.Assert(sb.IsComplete);
	}

	[Test]
	public static void Storyboard_Parallel_PlaysSimultaneously()
	{
		float a = 0, b = 0;
		let sb = scope Storyboard(.Parallel);
		sb.Add(new FloatAnimation(0, 100, 1.0f, new [&] (v) => { a = v; }));
		sb.Add(new FloatAnimation(0, 200, 0.5f, new [&] (v) => { b = v; }));

		sb.Start();

		sb.Update(0.5f);
		Test.Assert(Math.Abs(a - 50) < 0.01f);
		Test.Assert(Math.Abs(b - 200) < 0.01f); // b finished
		Test.Assert(!sb.IsComplete); // a still running

		sb.Update(0.5f);
		Test.Assert(Math.Abs(a - 100) < 0.01f);
		Test.Assert(sb.IsComplete);
	}

	[Test]
	public static void Storyboard_Empty_CompletesImmediately()
	{
		let sb = scope Storyboard(.Sequential);
		sb.Start();

		let done = sb.Update(0.016f);
		Test.Assert(done);
		Test.Assert(sb.IsComplete);
	}

	[Test]
	public static void Storyboard_OnComplete_Fires()
	{
		bool completed = false;
		let sb = scope Storyboard(.Sequential);
		sb.Add(new FloatAnimation(0, 100, 0.5f, new (v) => { }));
		sb.OnComplete.Subscribe(new [&] (a) => { completed = true; });
		sb.Start();

		sb.Update(0.5f);
		Test.Assert(completed);
	}

	[Test]
	public static void Storyboard_Reset_ReplaysFromStart()
	{
		float a = 0;
		let sb = scope Storyboard(.Sequential);
		sb.Add(new FloatAnimation(0, 100, 0.5f, new [&] (v) => { a = v; }));
		sb.Start();

		sb.Update(0.5f);
		Test.Assert(sb.IsComplete);

		sb.Reset();
		Test.Assert(!sb.IsComplete);
		Test.Assert(!sb.IsRunning);

		sb.Start();
		sb.Update(0.25f);
		Test.Assert(Math.Abs(a - 50) < 0.01f);
	}

	[Test]
	public static void Storyboard_WithAnimationManager()
	{
		float result = 0;
		let mgr = scope AnimationManager();

		let sb = new Storyboard(.Sequential);
		sb.Add(new FloatAnimation(0, 50, 0.5f, new [&] (v) => { result = v; }));
		sb.Add(new FloatAnimation(50, 100, 0.5f, new [&] (v) => { result = v; }));
		mgr.Add(sb);

		mgr.Update(0.5f);
		Test.Assert(Math.Abs(result - 50) < 0.01f);

		mgr.Update(0.5f);
		Test.Assert(Math.Abs(result - 100) < 0.01f);
		Test.Assert(mgr.ActiveCount == 0); // Cleaned up
	}
}

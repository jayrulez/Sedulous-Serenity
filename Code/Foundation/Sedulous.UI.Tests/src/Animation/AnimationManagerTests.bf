using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

class AnimationManagerTests
{
	[Test]
	public static void AnimationManager_AddAndTick()
	{
		float result = 0;
		let mgr = scope AnimationManager();
		mgr.Add(new FloatAnimation(0, 100, 1.0f, new [&] (v) => { result = v; }));

		Test.Assert(mgr.ActiveCount == 1);

		mgr.Update(0.5f);
		Test.Assert(Math.Abs(result - 50) < 0.01f);
		Test.Assert(mgr.ActiveCount == 1);

		mgr.Update(0.5f);
		Test.Assert(Math.Abs(result - 100) < 0.01f);
		Test.Assert(mgr.ActiveCount == 0); // Removed after completion
	}

	[Test]
	public static void AnimationManager_MultipleAnimations()
	{
		float a = 0, b = 0;
		let mgr = scope AnimationManager();
		mgr.Add(new FloatAnimation(0, 100, 1.0f, new [&] (v) => { a = v; }));
		mgr.Add(new FloatAnimation(100, 0, 0.5f, new [&] (v) => { b = v; }));

		Test.Assert(mgr.ActiveCount == 2);

		mgr.Update(0.5f);
		Test.Assert(Math.Abs(a - 50) < 0.01f);
		Test.Assert(Math.Abs(b - 0) < 0.01f); // b completed (0.5 duration)
		Test.Assert(mgr.ActiveCount == 1); // b removed

		mgr.Update(0.5f);
		Test.Assert(mgr.ActiveCount == 0);
	}

	[Test]
	public static void AnimationManager_CancelAll()
	{
		float result = 0;
		let mgr = scope AnimationManager();
		mgr.Add(new FloatAnimation(0, 100, 1.0f, new [&] (v) => { result = v; }));
		mgr.Add(new FloatAnimation(0, 200, 2.0f, new (v) => { }));

		Test.Assert(mgr.ActiveCount == 2);
		mgr.CancelAll();
		Test.Assert(mgr.ActiveCount == 0);
	}

	[Test]
	public static void AnimationManager_CancelForView()
	{
		float a = 0, b = 0;
		let view1 = scope View();
		let view2 = scope View();
		let mgr = scope AnimationManager();

		let anim1 = new FloatAnimation(0, 100, 1.0f, new [&] (v) => { a = v; });
		anim1.Target = view1;
		mgr.Add(anim1);

		let anim2 = new FloatAnimation(0, 200, 1.0f, new [&] (v) => { b = v; });
		anim2.Target = view2;
		mgr.Add(anim2);

		Test.Assert(mgr.ActiveCount == 2);

		mgr.CancelForView(view1);
		Test.Assert(mgr.ActiveCount == 1);

		mgr.Update(0.5f);
		Test.Assert(Math.Abs(b - 100) < 0.01f); // view2 anim still running
	}

	[Test]
	public static void AnimationManager_OnComplete_Fires()
	{
		bool completed = false;
		let mgr = scope AnimationManager();
		let anim = new FloatAnimation(0, 100, 0.5f, new (v) => { });
		anim.OnComplete.Subscribe(new [&] (a) => { completed = true; });
		mgr.Add(anim);

		mgr.Update(0.5f);
		Test.Assert(completed);
		Test.Assert(mgr.ActiveCount == 0);
	}
}

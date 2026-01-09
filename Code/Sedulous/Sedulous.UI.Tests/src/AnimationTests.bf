using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

class EasingTests
{
	[Test]
	public static void LinearEasing()
	{
		Test.Assert(Easing.Linear(0) == 0);
		Test.Assert(Easing.Linear(0.5f) == 0.5f);
		Test.Assert(Easing.Linear(1) == 1);
	}

	[Test]
	public static void QuadraticEasingBoundaries()
	{
		// All easing functions should return 0 at t=0 and 1 at t=1
		Test.Assert(Easing.QuadraticIn(0) == 0);
		Test.Assert(Easing.QuadraticIn(1) == 1);
		Test.Assert(Easing.QuadraticOut(0) == 0);
		Test.Assert(Easing.QuadraticOut(1) == 1);
		Test.Assert(Easing.QuadraticInOut(0) == 0);
		Test.Assert(Easing.QuadraticInOut(1) == 1);
	}

	[Test]
	public static void CubicEasingBoundaries()
	{
		Test.Assert(Easing.CubicIn(0) == 0);
		Test.Assert(Easing.CubicIn(1) == 1);
		Test.Assert(Easing.CubicOut(0) == 0);
		Test.Assert(Easing.CubicOut(1) == 1);
		Test.Assert(Easing.CubicInOut(0) == 0);
		Test.Assert(Easing.CubicInOut(1) == 1);
	}

	[Test]
	public static void EaseInStartsSlow()
	{
		// EaseIn should be below linear at the start
		let t = 0.25f;
		Test.Assert(Easing.QuadraticIn(t) < t);
		Test.Assert(Easing.CubicIn(t) < t);
	}

	[Test]
	public static void EaseOutEndsSlow()
	{
		// EaseOut should be above linear near the end
		let t = 0.75f;
		Test.Assert(Easing.QuadraticOut(t) > t);
		Test.Assert(Easing.CubicOut(t) > t);
	}

	[Test]
	public static void EvaluateMatchesDirectCall()
	{
		let t = 0.5f;
		Test.Assert(Easing.Evaluate(.Linear, t) == Easing.Linear(t));
		Test.Assert(Easing.Evaluate(.QuadraticIn, t) == Easing.QuadraticIn(t));
		Test.Assert(Easing.Evaluate(.CubicOut, t) == Easing.CubicOut(t));
	}

	[Test]
	public static void BounceEasingBoundaries()
	{
		Test.Assert(Easing.BounceIn(0) == 0);
		Test.Assert(Easing.BounceIn(1) == 1);
		Test.Assert(Easing.BounceOut(0) == 0);
		Test.Assert(Easing.BounceOut(1) == 1);
	}

	[Test]
	public static void ElasticEasingBoundaries()
	{
		Test.Assert(Easing.ElasticIn(0) == 0);
		Test.Assert(Easing.ElasticIn(1) == 1);
		Test.Assert(Easing.ElasticOut(0) == 0);
		Test.Assert(Easing.ElasticOut(1) == 1);
	}
}

class AnimationTests
{
	[Test]
	public static void FloatAnimationInterpolates()
	{
		let anim = scope FloatAnimation(0, 100);
		anim.Duration = 1.0f;
		anim.Easing = .Linear;

		float capturedValue = 0;
		anim.OnValueChanged = new [&](v) => { capturedValue = v; }; // takes ownership

		anim.Start();
		anim.Update(0.5f); // 50% through

		// Should be approximately 50 (linear interpolation)
		Test.Assert(Math.Abs(capturedValue - 50) < 0.1f);
	}

	[Test]
	public static void AnimationCompletes()
	{
		let anim = scope FloatAnimation(0, 1);
		anim.Duration = 0.5f;

		bool completed = false;
		anim.Completed.Subscribe(new [&](a) => { completed = true; });

		anim.Start();
		Test.Assert(anim.State == .Playing);

		anim.Update(0.6f); // Past duration
		Test.Assert(anim.State == .Completed);
		Test.Assert(completed);
	}

	[Test]
	public static void AnimationWithDelay()
	{
		let anim = scope FloatAnimation(0, 100);
		anim.Duration = 1.0f;
		anim.Delay = 0.5f;
		anim.Easing = .Linear;

		float capturedValue = -1;
		anim.OnValueChanged = new [&](v) => { capturedValue = v; }; // takes ownership

		anim.Start();
		anim.Update(0.3f); // Still in delay

		// Value should still be at start
		Test.Assert(capturedValue <= 0);

		anim.Update(0.7f); // 0.5s into animation after delay
		Test.Assert(capturedValue > 40); // Should be around 50
	}

	[Test]
	public static void AnimationPauseResume()
	{
		let anim = scope FloatAnimation(0, 100);
		anim.Duration = 1.0f;

		anim.Start();
		Test.Assert(anim.State == .Playing);

		anim.Pause();
		Test.Assert(anim.State == .Paused);

		anim.Resume();
		Test.Assert(anim.State == .Playing);
	}

	[Test]
	public static void AnimationStop()
	{
		let anim = scope FloatAnimation(0, 100);
		anim.Duration = 1.0f;

		anim.Start();
		anim.Update(0.5f);

		anim.Stop();
		Test.Assert(anim.State == .Stopped);
	}

	[Test]
	public static void ColorAnimationInterpolates()
	{
		let anim = scope ColorAnimation(Color(0, 0, 0, 255), Color(255, 255, 255, 255));
		anim.Duration = 1.0f;
		anim.Easing = .Linear;

		Color capturedColor = Color(0, 0, 0, 0);
		anim.OnValueChanged = new [&] (c) => { capturedColor = c; }; // takes ownership

		anim.Start();
		anim.Update(0.5f);

		// Should be approximately gray
		Test.Assert(capturedColor.R > 100 && capturedColor.R < 156);
		Test.Assert(capturedColor.G > 100 && capturedColor.G < 156);
		Test.Assert(capturedColor.B > 100 && capturedColor.B < 156);
	}

	[Test]
	public static void ThicknessAnimationInterpolates()
	{
		let anim = scope ThicknessAnimation(Thickness(0), Thickness(10));
		anim.Duration = 1.0f;
		anim.Easing = .Linear;

		Thickness capturedThickness = Thickness(0);
		anim.OnValueChanged = new [&] (t) => { capturedThickness = t; }; // takes ownership

		anim.Start();
		anim.Update(0.5f);

		// Should be approximately 5 on all sides
		Test.Assert(Math.Abs(capturedThickness.Left - 5) < 0.1f);
		Test.Assert(Math.Abs(capturedThickness.Top - 5) < 0.1f);
	}
}

class AnimationManagerTests
{
	[Test]
	public static void ManagerAddsAnimation()
	{
		let manager = scope AnimationManager();
		let anim = new FloatAnimation(0, 1);
		anim.Duration = 1.0f;

		manager.Add(anim);
		Test.Assert(manager.Count == 1);
		Test.Assert(anim.State == .Playing);

		manager.Clear();
		delete anim;
	}

	[Test]
	public static void ManagerUpdatesAnimations()
	{
		let manager = scope AnimationManager();
		let anim = new FloatAnimation(0, 100);
		anim.Duration = 1.0f;

		float value = 0;
		anim.OnValueChanged = new [&](v) => { value = v; }; // takes ownership

		manager.Add(anim);
		manager.Update(0.5f);

		Test.Assert(value > 0);

		manager.Clear();
		delete anim;
	}

	[Test]
	public static void ManagerRemovesCompletedAnimations()
	{
		let manager = scope AnimationManager();
		let anim = new FloatAnimation(0, 1);
		anim.Duration = 0.5f;

		manager.Add(anim); // takes ownership
		Test.Assert(manager.Count == 1);

		manager.Update(0.6f); // Past duration

		// Animation should be removed after completion
		Test.Assert(manager.Count == 0);
	}

	[Test]
	public static void ManagerPauseResumeAll()
	{
		let manager = scope AnimationManager();
		let anim1 = new FloatAnimation(0, 1);
		let anim2 = new FloatAnimation(0, 1);
		anim1.Duration = 1.0f;
		anim2.Duration = 1.0f;

		manager.Add(anim1);
		manager.Add(anim2);

		manager.PauseAll();
		Test.Assert(anim1.State == .Paused);
		Test.Assert(anim2.State == .Paused);

		manager.ResumeAll();
		Test.Assert(anim1.State == .Playing);
		Test.Assert(anim2.State == .Playing);

		manager.Clear();
		delete anim1;
		delete anim2;
	}
}

class UIContextAnimationTests
{
	[Test]
	public static void ContextHasAnimationManager()
	{
		let context = scope UIContext();
		Test.Assert(context.Animations != null);
	}

	[Test]
	public static void ContextUpdatesAnimations()
	{
		let context = scope UIContext();
		let anim = new FloatAnimation(0, 100);
		anim.Duration = 1.0f;

		float value = 0;
		anim.OnValueChanged = new [&](v) => { value = v; }; // takes ownership

		context.Animations.Add(anim);
		context.Update(0.5f, 0.5);

		Test.Assert(value > 0);

		context.Animations.Clear();
		delete anim;
	}
}

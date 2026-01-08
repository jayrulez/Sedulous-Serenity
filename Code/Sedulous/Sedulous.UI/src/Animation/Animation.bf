using System;
using Sedulous.Foundation.Core;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Animation playback state.
public enum AnimationState
{
	/// Animation has not started.
	Stopped,
	/// Animation is playing.
	Playing,
	/// Animation is paused.
	Paused,
	/// Animation has completed.
	Completed
}

/// How the animation behaves when it reaches the end.
public enum AnimationFillMode
{
	/// Value resets to start when animation ends.
	None,
	/// Value stays at end value when animation completes.
	Forward,
	/// Value is set to start value before animation begins.
	Backward,
	/// Combines Forward and Backward.
	Both
}

/// How the animation repeats.
public enum AnimationRepeatBehavior
{
	/// Play once and stop.
	Once,
	/// Repeat indefinitely.
	Forever,
	/// Repeat a specific number of times.
	Count
}

/// Base class for all animations.
public abstract class Animation
{
	protected float mDuration = 1.0f;
	protected float mDelay = 0.0f;
	protected EasingType mEasing = .Linear;
	protected AnimationFillMode mFillMode = .Forward;
	protected AnimationRepeatBehavior mRepeatBehavior = .Once;
	protected int mRepeatCount = 1;
	protected bool mAutoReverse = false;

	protected AnimationState mState = .Stopped;
	protected float mElapsedTime = 0.0f;
	protected int mCurrentIteration = 0;
	protected bool mIsReversing = false;

	// Completed event
	private EventAccessor<delegate void(Animation)> mCompletedEvent = new .() ~ delete _;

	/// Event fired when the animation completes.
	public EventAccessor<delegate void(Animation)> Completed => mCompletedEvent;

	/// Duration of one animation cycle in seconds.
	public float Duration
	{
		get => mDuration;
		set => mDuration = Math.Max(0.001f, value);
	}

	/// Delay before animation starts in seconds.
	public float Delay
	{
		get => mDelay;
		set => mDelay = Math.Max(0, value);
	}

	/// The easing function to use.
	public EasingType Easing
	{
		get => mEasing;
		set => mEasing = value;
	}

	/// How the animation fills before/after playback.
	public AnimationFillMode FillMode
	{
		get => mFillMode;
		set => mFillMode = value;
	}

	/// How the animation repeats.
	public AnimationRepeatBehavior RepeatBehavior
	{
		get => mRepeatBehavior;
		set => mRepeatBehavior = value;
	}

	/// Number of times to repeat (when RepeatBehavior is Count).
	public int RepeatCount
	{
		get => mRepeatCount;
		set => mRepeatCount = Math.Max(1, value);
	}

	/// Whether to reverse direction on each repeat.
	public bool AutoReverse
	{
		get => mAutoReverse;
		set => mAutoReverse = value;
	}

	/// Current animation state.
	public AnimationState State => mState;

	/// Current progress within one cycle (0 to 1).
	public float Progress
	{
		get
		{
			if (mDuration <= 0) return 1;
			let cycleTime = mElapsedTime - mDelay;
			if (cycleTime < 0) return 0;
			let rawProgress = Math.Clamp(cycleTime / mDuration, 0, 1);
			return mIsReversing ? 1 - rawProgress : rawProgress;
		}
	}

	/// Current eased progress value.
	public float EasedProgress => Sedulous.UI.Easing.Evaluate(mEasing, Progress);

	/// Starts or restarts the animation.
	public void Start()
	{
		mElapsedTime = 0;
		mCurrentIteration = 0;
		mIsReversing = false;
		mState = .Playing;
		OnStart();
	}

	/// Pauses the animation.
	public void Pause()
	{
		if (mState == .Playing)
			mState = .Paused;
	}

	/// Resumes a paused animation.
	public void Resume()
	{
		if (mState == .Paused)
			mState = .Playing;
	}

	/// Stops the animation.
	public void Stop()
	{
		mState = .Stopped;
		mElapsedTime = 0;
		mCurrentIteration = 0;
		mIsReversing = false;
		OnStop();
	}

	/// Updates the animation by the given delta time.
	/// Returns true if animation is still active.
	public bool Update(float deltaTime)
	{
		if (mState != .Playing)
			return mState != .Completed && mState != .Stopped;

		mElapsedTime += deltaTime;

		// Handle delay
		if (mElapsedTime < mDelay)
		{
			if (mFillMode == .Backward || mFillMode == .Both)
				ApplyValue(0);
			return true;
		}

		let cycleTime = mElapsedTime - mDelay;
		var cycleProgress = cycleTime / mDuration;

		// Check for cycle completion
		if (cycleProgress >= 1.0f)
		{
			// Apply final value for this cycle
			let finalT = mIsReversing ? 0.0f : 1.0f;
			ApplyValue(Sedulous.UI.Easing.Evaluate(mEasing, finalT));

			// Handle repeat
			if (mAutoReverse)
			{
				if (mIsReversing)
				{
					mCurrentIteration++;
					mIsReversing = false;
				}
				else
				{
					mIsReversing = true;
				}
				mElapsedTime = mDelay;
			}
			else
			{
				mCurrentIteration++;
				mElapsedTime = mDelay;
			}

			// Check if we should continue
			bool shouldContinue = false;
			switch (mRepeatBehavior)
			{
			case .Forever:
				shouldContinue = true;
			case .Once:
				shouldContinue = false;
			case .Count:
				shouldContinue = mCurrentIteration < mRepeatCount;
			}

			if (!shouldContinue)
			{
				mState = .Completed;
				if (mFillMode == .None || mFillMode == .Backward)
					ApplyValue(0);
				OnCompleted();
				mCompletedEvent.[Friend]Invoke(this);
				return false;
			}

			return true;
		}

		// Apply current value
		let progress = mIsReversing ? 1.0f - cycleProgress : cycleProgress;
		let easedProgress = Sedulous.UI.Easing.Evaluate(mEasing, progress);
		ApplyValue(easedProgress);

		return true;
	}

	/// Called when animation starts.
	protected virtual void OnStart() { }

	/// Called when animation stops.
	protected virtual void OnStop() { }

	/// Called when animation completes.
	protected virtual void OnCompleted() { }

	/// Applies the animated value at the given progress (0-1, after easing).
	protected abstract void ApplyValue(float easedProgress);
}

/// Animation that interpolates a float value.
public class FloatAnimation : Animation
{
	public float From;
	public float To;
	public delegate void(float) OnValueChanged ~ delete _;

	public this(float from, float to)
	{
		From = from;
		To = to;
	}

	protected override void ApplyValue(float easedProgress)
	{
		let value = From + (To - From) * easedProgress;
		if (OnValueChanged != null)
			OnValueChanged(value);
	}
}

/// Animation that interpolates a Color value.
public class ColorAnimation : Animation
{
	public Color From;
	public Color To;
	public delegate void(Color) OnValueChanged ~ delete _;

	public this(Color from, Color to)
	{
		From = from;
		To = to;
	}

	protected override void ApplyValue(float easedProgress)
	{
		let r = (uint8)(From.R + (int)(To.R - From.R) * easedProgress);
		let g = (uint8)(From.G + (int)(To.G - From.G) * easedProgress);
		let b = (uint8)(From.B + (int)(To.B - From.B) * easedProgress);
		let a = (uint8)(From.A + (int)(To.A - From.A) * easedProgress);
		if (OnValueChanged != null)
			OnValueChanged(Color(r, g, b, a));
	}
}

/// Animation that interpolates a Thickness value.
public class ThicknessAnimation : Animation
{
	public Thickness From;
	public Thickness To;
	public delegate void(Thickness) OnValueChanged ~ delete _;

	public this(Thickness from, Thickness to)
	{
		From = from;
		To = to;
	}

	protected override void ApplyValue(float easedProgress)
	{
		let left = From.Left + (To.Left - From.Left) * easedProgress;
		let top = From.Top + (To.Top - From.Top) * easedProgress;
		let right = From.Right + (To.Right - From.Right) * easedProgress;
		let bottom = From.Bottom + (To.Bottom - From.Bottom) * easedProgress;
		if (OnValueChanged != null)
			OnValueChanged(Thickness(left, top, right, bottom));
	}
}

/// Animation that interpolates a Vector2 value.
public class Vector2Animation : Animation
{
	public Vector2 From;
	public Vector2 To;
	public delegate void(Vector2) OnValueChanged ~ delete _;

	public this(Vector2 from, Vector2 to)
	{
		From = from;
		To = to;
	}

	protected override void ApplyValue(float easedProgress)
	{
		let x = From.X + (To.X - From.X) * easedProgress;
		let y = From.Y + (To.Y - From.Y) * easedProgress;
		if (OnValueChanged != null)
			OnValueChanged(.(x, y));
	}
}

/// Animation that interpolates a RectangleF value.
public class RectangleAnimation : Animation
{
	public RectangleF From;
	public RectangleF To;
	public delegate void(RectangleF) OnValueChanged ~ delete _;

	public this(RectangleF from, RectangleF to)
	{
		From = from;
		To = to;
	}

	protected override void ApplyValue(float easedProgress)
	{
		let x = From.X + (To.X - From.X) * easedProgress;
		let y = From.Y + (To.Y - From.Y) * easedProgress;
		let w = From.Width + (To.Width - From.Width) * easedProgress;
		let h = From.Height + (To.Height - From.Height) * easedProgress;
		if (OnValueChanged != null)
			OnValueChanged(.(x, y, w, h));
	}
}

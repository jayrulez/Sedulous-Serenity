using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Animation playback state.
enum AnimationState
{
	/// Animation has not started.
	Stopped,
	/// Animation is currently playing.
	Playing,
	/// Animation is paused.
	Paused,
	/// Animation has completed.
	Completed
}

/// Animation repeat behavior.
enum RepeatBehavior
{
	/// Play once and stop.
	Once,
	/// Loop forever.
	Forever,
	/// Play a specific number of times.
	Count
}

/// Base class for all animations.
abstract class Animation
{
	protected Widget mTarget;
	protected float mDuration = 1.0f;
	protected float mDelay = 0;
	protected float mElapsedTime = 0;
	protected EaseFunction mEasing = .Linear;
	protected bool mAutoReverse = false;
	protected RepeatBehavior mRepeatBehavior = .Once;
	protected int32 mRepeatCount = 1;
	protected int32 mCurrentRepeat = 0;
	protected AnimationState mState = .Stopped;
	protected bool mIsReversing = false;

	/// Event raised when the animation completes.
	public Event<delegate void()> OnCompleted ~ _.Dispose();

	/// Event raised when a single iteration completes.
	public Event<delegate void(int32 iteration)> OnIterationCompleted ~ _.Dispose();

	/// Gets or sets the target widget.
	public Widget Target
	{
		get => mTarget;
		set => mTarget = value;
	}

	/// Gets or sets the animation duration in seconds.
	public float Duration
	{
		get => mDuration;
		set => mDuration = Math.Max(0.001f, value);
	}

	/// Gets or sets the delay before starting in seconds.
	public float Delay
	{
		get => mDelay;
		set => mDelay = Math.Max(0, value);
	}

	/// Gets or sets the easing function.
	public EaseFunction EaseFunc
	{
		get => mEasing;
		set => mEasing = value;
	}

	/// Gets or sets whether the animation auto-reverses.
	public bool AutoReverse
	{
		get => mAutoReverse;
		set => mAutoReverse = value;
	}

	/// Gets or sets the repeat behavior.
	public RepeatBehavior RepeatBehavior
	{
		get => mRepeatBehavior;
		set => mRepeatBehavior = value;
	}

	/// Gets or sets the repeat count (when RepeatBehavior is Count).
	public int32 RepeatCount
	{
		get => mRepeatCount;
		set => mRepeatCount = Math.Max(1, value);
	}

	/// Gets the current animation state.
	public AnimationState State => mState;

	/// Gets whether the animation is currently playing.
	public bool IsPlaying => mState == .Playing;

	/// Gets the current progress (0-1).
	public float Progress
	{
		get
		{
			if (mDuration <= 0)
				return 1;
			let progress = Math.Clamp((mElapsedTime - mDelay) / mDuration, 0, 1);
			return mIsReversing ? 1 - progress : progress;
		}
	}

	/// Gets the eased progress value.
	public float EasedProgress => Easing.Evaluate(mEasing, Progress);

	/// Starts or resumes the animation.
	public void Play()
	{
		if (mState == .Completed)
			Reset();

		mState = .Playing;
	}

	/// Pauses the animation.
	public void Pause()
	{
		if (mState == .Playing)
			mState = .Paused;
	}

	/// Stops the animation and resets to the beginning.
	public void Stop()
	{
		mState = .Stopped;
		Reset();
	}

	/// Resets the animation to its initial state.
	public void Reset()
	{
		mElapsedTime = 0;
		mCurrentRepeat = 0;
		mIsReversing = false;
		if (mState != .Playing)
			mState = .Stopped;
	}

	/// Updates the animation by the given delta time.
	/// Returns true if the animation is still active.
	public bool Update(float deltaTime)
	{
		if (mState != .Playing)
			return mState != .Completed && mState != .Stopped;

		mElapsedTime += deltaTime;

		// Handle delay
		if (mElapsedTime < mDelay)
			return true;

		// Calculate progress
		let animTime = mElapsedTime - mDelay;
		let iterationDuration = mAutoReverse ? mDuration * 2 : mDuration;

		if (animTime >= iterationDuration)
		{
			// Iteration complete
			mCurrentRepeat++;
			OnIterationCompleted(mCurrentRepeat);

			bool shouldContinue = false;
			switch (mRepeatBehavior)
			{
			case .Once:
				shouldContinue = false;
			case .Forever:
				shouldContinue = true;
			case .Count:
				shouldContinue = mCurrentRepeat < mRepeatCount;
			}

			if (shouldContinue)
			{
				// Start next iteration
				mElapsedTime = mDelay + (animTime - iterationDuration);
				mIsReversing = false;
			}
			else
			{
				// Animation complete
				mState = .Completed;
				ApplyValue(mAutoReverse ? 0 : 1);
				OnCompleted();
				return false;
			}
		}
		else if (mAutoReverse && animTime >= mDuration)
		{
			mIsReversing = true;
		}

		// Apply current value
		ApplyValue(EasedProgress);
		return true;
	}

	/// Applies the animated value at the given progress (0-1).
	protected abstract void ApplyValue(float progress);

	/// Seeks to the specified progress (0-1).
	public void Seek(float progressValue)
	{
		var progress = Math.Clamp(progressValue, 0, 1);
		mElapsedTime = mDelay + progress * mDuration;
		mIsReversing = false;
		ApplyValue(Easing.Evaluate(mEasing, progress));
	}
}

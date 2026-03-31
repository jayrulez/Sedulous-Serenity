namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// Abstract base class for all property animations.
/// Manages elapsed time, easing, delay, repeat, and auto-reverse.
public abstract class Animation
{
	private float mElapsed = 0;
	private float mDuration;
	private float mDelay = 0;
	private EasingFunction mEasing;
	private bool mIsRunning = false;
	private bool mIsComplete = false;
	private bool mAutoReverse = false;
	private int mRepeatCount = 0; // 0 = play once, -1 = infinite
	private int mCurrentRepeat = 0;
	private View mTarget;

	private EventAccessor<delegate void(Animation)> mOnComplete = new .() ~ delete _;

	/// Event fired when the animation completes (after all repeats).
	public EventAccessor<delegate void(Animation)> OnComplete => mOnComplete;

	/// The view this animation targets (optional, used by AnimationManager.CancelForView).
	public View Target
	{
		get => mTarget;
		set { mTarget = value; }
	}

	/// Duration of one cycle in seconds.
	public float Duration
	{
		get => mDuration;
		set { mDuration = Math.Max(value, 0); }
	}

	/// Delay before animation starts in seconds.
	public float Delay
	{
		get => mDelay;
		set { mDelay = Math.Max(value, 0); }
	}

	/// Easing function applied to the progress. Null = linear.
	public EasingFunction Easing
	{
		get => mEasing;
		set { mEasing = value; }
	}

	/// Whether the animation plays backward on alternate repeats.
	public bool AutoReverse
	{
		get => mAutoReverse;
		set { mAutoReverse = value; }
	}

	/// Number of times to repeat after the first play. 0 = once, -1 = infinite.
	public int RepeatCount
	{
		get => mRepeatCount;
		set { mRepeatCount = value; }
	}

	/// Whether the animation is currently running.
	public bool IsRunning => mIsRunning;

	/// Whether the animation has completed (all repeats finished).
	public bool IsComplete => mIsComplete;

	/// Current elapsed time within the current cycle.
	public float Elapsed => mElapsed;

	public this(float duration, EasingFunction easing = null)
	{
		mDuration = Math.Max(duration, 0);
		mEasing = easing;
	}

	/// Start or resume the animation.
	public void Start()
	{
		if (!mIsComplete)
			mIsRunning = true;
	}

	/// Pause the animation without resetting.
	public void Stop()
	{
		mIsRunning = false;
	}

	/// Reset the animation to its initial state.
	public virtual void Reset()
	{
		mElapsed = 0;
		mCurrentRepeat = 0;
		mIsRunning = false;
		mIsComplete = false;
	}

	/// Advance the animation by deltaTime. Returns true when fully complete.
	public virtual bool Update(float deltaTime)
	{
		if (!mIsRunning || mIsComplete)
			return mIsComplete;

		mElapsed += deltaTime;

		// Handle delay
		if (mDelay > 0 && mElapsed < mDelay)
			return false;

		float activeTime = mElapsed - mDelay;

		if (mDuration <= 0)
		{
			// Zero-duration: snap to end
			Apply(1.0f);
			FinishCycle();
			return mIsComplete;
		}

		if (activeTime >= mDuration)
		{
			// Cycle complete
			Apply(1.0f);
			FinishCycle();
			return mIsComplete;
		}

		// Normal progress
		float t = activeTime / mDuration;

		// Auto-reverse: play backward on odd repeats
		if (mAutoReverse && (mCurrentRepeat & 1) != 0)
			t = 1.0f - t;

		// Apply easing
		float easedT = (mEasing != null) ? mEasing(t) : t;
		Apply(easedT);

		return false;
	}

	/// Apply the interpolated value at progress t (0-1, after easing).
	protected abstract void Apply(float t);

	/// Mark the animation as complete. For use by subclasses that override Update.
	protected void MarkComplete()
	{
		mIsRunning = false;
		mIsComplete = true;
		mOnComplete.[Friend]Invoke(this);
	}

	private void FinishCycle()
	{
		if (mRepeatCount == -1 || mCurrentRepeat < mRepeatCount)
		{
			// Start next repeat
			mCurrentRepeat++;
			mElapsed = mDelay; // Reset to start of active time
		}
		else
		{
			// All repeats done
			mIsRunning = false;
			mIsComplete = true;
			mOnComplete.[Friend]Invoke(this);
		}
	}
}

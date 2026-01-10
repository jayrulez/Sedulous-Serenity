namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Playback state for animation.
enum AnimationState
{
	Stopped,
	Playing,
	Paused
}

/// Plays animations on a skeleton.
class AnimationPlayer
{
	private Skeleton mSkeleton;
	private AnimationClip mCurrentClip;
	private float mCurrentTime;
	private AnimationState mState = .Stopped;
	private float mSpeed = 1.0f;
	private bool mLooping = true;

	/// Bone matrices for GPU upload (skinning matrices).
	public Matrix[] BoneMatrices ~ delete _;

	/// The skeleton being animated.
	public Skeleton Skeleton => mSkeleton;

	/// Current animation clip.
	public AnimationClip CurrentClip => mCurrentClip;

	/// Current playback time in seconds.
	public float CurrentTime => mCurrentTime;

	/// Playback state.
	public AnimationState State => mState;

	/// Playback speed multiplier.
	public float Speed
	{
		get => mSpeed;
		set => mSpeed = value;
	}

	/// Whether to loop the animation.
	public bool Looping
	{
		get => mLooping;
		set => mLooping = value;
	}

	public this(Skeleton skeleton)
	{
		mSkeleton = skeleton;
		BoneMatrices = new Matrix[Sedulous.Renderer.Skeleton.MAX_BONES];

		// Initialize to identity
		for (int i = 0; i < BoneMatrices.Count; i++)
			BoneMatrices[i] = .Identity;
	}

	/// Plays an animation clip.
	public void Play(AnimationClip clip, bool restart = true)
	{
		mCurrentClip = clip;
		if (restart)
			mCurrentTime = 0;
		mState = .Playing;
	}

	/// Stops playback.
	public void Stop()
	{
		mState = .Stopped;
		mCurrentTime = 0;
		UpdateBoneMatrices();
	}

	/// Pauses playback.
	public void Pause()
	{
		if (mState == .Playing)
			mState = .Paused;
	}

	/// Resumes playback.
	public void Resume()
	{
		if (mState == .Paused)
			mState = .Playing;
	}

	/// Updates the animation. Call each frame.
	public void Update(float deltaTime)
	{
		if (mState != .Playing || mCurrentClip == null)
			return;

		// Advance time
		mCurrentTime += deltaTime * mSpeed;

		// Handle looping/clamping
		if (mCurrentTime >= mCurrentClip.Duration)
		{
			if (mLooping)
			{
				mCurrentTime = mCurrentTime % mCurrentClip.Duration;
			}
			else
			{
				mCurrentTime = mCurrentClip.Duration;
				mState = .Stopped;
			}
		}
		else if (mCurrentTime < 0)
		{
			if (mLooping)
			{
				mCurrentTime = mCurrentClip.Duration + (mCurrentTime % mCurrentClip.Duration);
			}
			else
			{
				mCurrentTime = 0;
				mState = .Stopped;
			}
		}

		// Sample animation and apply to skeleton
		mCurrentClip.Sample(mCurrentTime, mSkeleton);

		// Update bone matrices
		UpdateBoneMatrices();
	}

	/// Updates the bone matrices from current skeleton pose.
	public void UpdateBoneMatrices()
	{
		// Update skeleton world transforms
		mSkeleton.UpdateMatrices();

		// Copy skinning matrices to our buffer
		mSkeleton.CopySkinningMatrices(&BoneMatrices[0], Sedulous.Renderer.Skeleton.MAX_BONES);
	}

	/// Seeks to a specific time.
	public void Seek(float time)
	{
		mCurrentTime = Math.Clamp(time, 0, mCurrentClip?.Duration ?? 0);

		if (mCurrentClip != null)
		{
			mCurrentClip.Sample(mCurrentTime, mSkeleton);
			UpdateBoneMatrices();
		}
	}

	/// Gets normalized progress (0-1).
	public float NormalizedTime
	{
		get
		{
			if (mCurrentClip == null || mCurrentClip.Duration <= 0)
				return 0;
			return mCurrentTime / mCurrentClip.Duration;
		}
		set
		{
			if (mCurrentClip != null)
				Seek(value * mCurrentClip.Duration);
		}
	}
}

using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// A group of animations that play simultaneously.
class AnimationGroup
{
	private List<Animation> mAnimations = new .() ~ delete _;
	private AnimationState mState = .Stopped;
	private int32 mCompletedCount = 0;

	/// Event raised when all animations complete.
	public Event<delegate void()> OnCompleted ~ _.Dispose();

	/// Gets the animations in this group.
	public List<Animation> Animations => mAnimations;

	/// Gets the current state.
	public AnimationState State => mState;

	/// Gets whether the group is playing.
	public bool IsPlaying => mState == .Playing;

	/// Adds an animation to the group.
	public void Add(Animation animation)
	{
		mAnimations.Add(animation);
	}

	/// Removes an animation from the group.
	public void Remove(Animation animation)
	{
		mAnimations.Remove(animation);
	}

	/// Clears all animations.
	public void Clear()
	{
		mAnimations.Clear();
	}

	/// Starts all animations.
	public void Play()
	{
		mState = .Playing;
		mCompletedCount = 0;
		for (let anim in mAnimations)
		{
			anim.Play();
		}
	}

	/// Pauses all animations.
	public void Pause()
	{
		mState = .Paused;
		for (let anim in mAnimations)
		{
			anim.Pause();
		}
	}

	/// Stops all animations.
	public void Stop()
	{
		mState = .Stopped;
		mCompletedCount = 0;
		for (let anim in mAnimations)
		{
			anim.Stop();
		}
	}

	/// Updates all animations.
	public bool Update(float deltaTime)
	{
		if (mState != .Playing)
			return mState != .Completed && mState != .Stopped;

		int32 stillPlaying = 0;
		for (let anim in mAnimations)
		{
			if (anim.Update(deltaTime))
				stillPlaying++;
		}

		if (stillPlaying == 0)
		{
			mState = .Completed;
			OnCompleted();
			return false;
		}

		return true;
	}
}

/// A sequence of animations that play one after another.
class AnimationSequence
{
	private List<Animation> mAnimations = new .() ~ delete _;
	private AnimationState mState = .Stopped;
	private int32 mCurrentIndex = 0;

	/// Event raised when the sequence completes.
	public Event<delegate void()> OnCompleted ~ _.Dispose();

	/// Event raised when moving to the next animation.
	public Event<delegate void(int32 index)> OnAnimationChanged ~ _.Dispose();

	/// Gets the animations in this sequence.
	public List<Animation> Animations => mAnimations;

	/// Gets the current state.
	public AnimationState State => mState;

	/// Gets whether the sequence is playing.
	public bool IsPlaying => mState == .Playing;

	/// Gets the current animation index.
	public int32 CurrentIndex => mCurrentIndex;

	/// Gets the current animation.
	public Animation CurrentAnimation
	{
		get => (mCurrentIndex >= 0 && mCurrentIndex < mAnimations.Count) ? mAnimations[mCurrentIndex] : null;
	}

	/// Adds an animation to the sequence.
	public void Add(Animation animation)
	{
		mAnimations.Add(animation);
	}

	/// Removes an animation from the sequence.
	public void Remove(Animation animation)
	{
		mAnimations.Remove(animation);
	}

	/// Clears all animations.
	public void Clear()
	{
		mAnimations.Clear();
		mCurrentIndex = 0;
	}

	/// Starts the sequence from the beginning.
	public void Play()
	{
		if (mAnimations.Count == 0)
			return;

		mState = .Playing;
		mCurrentIndex = 0;
		mAnimations[0].Play();
		OnAnimationChanged(0);
	}

	/// Pauses the current animation.
	public void Pause()
	{
		mState = .Paused;
		if (CurrentAnimation != null)
			CurrentAnimation.Pause();
	}

	/// Stops the sequence.
	public void Stop()
	{
		mState = .Stopped;
		mCurrentIndex = 0;
		for (let anim in mAnimations)
		{
			anim.Stop();
		}
	}

	/// Updates the current animation.
	public bool Update(float deltaTime)
	{
		if (mState != .Playing || mAnimations.Count == 0)
			return mState != .Completed && mState != .Stopped;

		let current = CurrentAnimation;
		if (current == null)
		{
			mState = .Completed;
			OnCompleted();
			return false;
		}

		if (!current.Update(deltaTime))
		{
			// Current animation completed, move to next
			mCurrentIndex++;

			if (mCurrentIndex >= mAnimations.Count)
			{
				mState = .Completed;
				OnCompleted();
				return false;
			}

			// Start next animation
			mAnimations[mCurrentIndex].Play();
			OnAnimationChanged(mCurrentIndex);
		}

		return true;
	}

	/// Skips to the specified animation index.
	public void SkipTo(int32 index)
	{
		if (index < 0 || index >= mAnimations.Count)
			return;

		// Stop current
		if (CurrentAnimation != null)
			CurrentAnimation.Stop();

		mCurrentIndex = index;
		if (mState == .Playing)
		{
			mAnimations[mCurrentIndex].Play();
			OnAnimationChanged(mCurrentIndex);
		}
	}
}

/// Manages active animations and updates them each frame.
class AnimationManager
{
	private List<Animation> mAnimations = new .() ~ delete _;
	private List<AnimationGroup> mGroups = new .() ~ delete _;
	private List<AnimationSequence> mSequences = new .() ~ delete _;
	private List<Animation> mToRemove = new .() ~ delete _;
	private List<AnimationGroup> mGroupsToRemove = new .() ~ delete _;
	private List<AnimationSequence> mSequencesToRemove = new .() ~ delete _;

	/// Registers an animation to be updated.
	public void Register(Animation animation)
	{
		if (!mAnimations.Contains(animation))
			mAnimations.Add(animation);
	}

	/// Unregisters an animation.
	public void Unregister(Animation animation)
	{
		mAnimations.Remove(animation);
	}

	/// Registers an animation group.
	public void Register(AnimationGroup group)
	{
		if (!mGroups.Contains(group))
			mGroups.Add(group);
	}

	/// Unregisters an animation group.
	public void Unregister(AnimationGroup group)
	{
		mGroups.Remove(group);
	}

	/// Registers an animation sequence.
	public void Register(AnimationSequence sequence)
	{
		if (!mSequences.Contains(sequence))
			mSequences.Add(sequence);
	}

	/// Unregisters an animation sequence.
	public void Unregister(AnimationSequence sequence)
	{
		mSequences.Remove(sequence);
	}

	/// Updates all registered animations.
	public void Update(float deltaTime)
	{
		// Update individual animations
		for (let anim in mAnimations)
		{
			if (!anim.Update(deltaTime))
				mToRemove.Add(anim);
		}

		// Remove completed animations
		for (let anim in mToRemove)
			mAnimations.Remove(anim);
		mToRemove.Clear();

		// Update groups
		for (let group in mGroups)
		{
			if (!group.Update(deltaTime))
				mGroupsToRemove.Add(group);
		}

		for (let group in mGroupsToRemove)
			mGroups.Remove(group);
		mGroupsToRemove.Clear();

		// Update sequences
		for (let seq in mSequences)
		{
			if (!seq.Update(deltaTime))
				mSequencesToRemove.Add(seq);
		}

		for (let seq in mSequencesToRemove)
			mSequences.Remove(seq);
		mSequencesToRemove.Clear();
	}

	/// Stops all animations.
	public void StopAll()
	{
		for (let anim in mAnimations)
			anim.Stop();
		mAnimations.Clear();

		for (let group in mGroups)
			group.Stop();
		mGroups.Clear();

		for (let seq in mSequences)
			seq.Stop();
		mSequences.Clear();
	}

	/// Gets the number of active animations.
	public int32 ActiveCount => (int32)(mAnimations.Count + mGroups.Count + mSequences.Count);

	/// Pauses all animations.
	public void PauseAll()
	{
		for (let anim in mAnimations)
			anim.Pause();

		for (let group in mGroups)
			group.Pause();

		for (let seq in mSequences)
			seq.Pause();
	}

	/// Resumes all paused animations.
	public void ResumeAll()
	{
		for (let anim in mAnimations)
		{
			if (anim.State == .Paused)
				anim.Play();
		}

		for (let group in mGroups)
		{
			if (group.State == .Paused)
				group.Play();
		}

		for (let seq in mSequences)
		{
			if (seq.State == .Paused)
				seq.Play();
		}
	}

	/// Creates and registers a float animation.
	public FloatAnimation AnimateFloat(float from, float to, float duration, FloatSetter setter, EaseFunction easing = .Linear)
	{
		let anim = new FloatAnimation(from, to);
		anim.Duration = duration;
		anim.EaseFunc = easing;
		anim.SetSetter(setter);
		Register(anim);
		anim.Play();
		return anim;
	}

	/// Creates and registers a color animation.
	public ColorAnimation AnimateColor(Color from, Color to, float duration, ColorSetter setter, EaseFunction easing = .Linear)
	{
		let anim = new ColorAnimation(from, to);
		anim.Duration = duration;
		anim.EaseFunc = easing;
		anim.SetSetter(setter);
		Register(anim);
		anim.Play();
		return anim;
	}

	/// Creates and registers a Vector2 animation.
	public Vector2Animation AnimateVector2(Vector2 from, Vector2 to, float duration, Vector2Setter setter, EaseFunction easing = .Linear)
	{
		let anim = new Vector2Animation(from, to);
		anim.Duration = duration;
		anim.EaseFunc = easing;
		anim.SetSetter(setter);
		Register(anim);
		anim.Play();
		return anim;
	}
}

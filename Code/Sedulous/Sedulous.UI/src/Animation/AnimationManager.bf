using System;
using System.Collections;

namespace Sedulous.UI;

/// Manages active animations in the UI system.
public class AnimationManager
{
	private List<Animation> mAnimations = new .() ~ delete _;
	private List<Animation> mPendingAdd = new .() ~ delete _;
	private List<Animation> mPendingRemove = new .() ~ delete _;
	private bool mIsUpdating = false;

	/// Number of active animations.
	public int Count => mAnimations.Count;

	/// Adds an animation to be managed.
	/// The animation will be started automatically.
	public void Add(Animation animation)
	{
		if (mIsUpdating)
			mPendingAdd.Add(animation);
		else
		{
			mAnimations.Add(animation);
			animation.Start();
		}
	}

	/// Removes an animation from management.
	public void Remove(Animation animation)
	{
		if (mIsUpdating)
			mPendingRemove.Add(animation);
		else
		{
			animation.Stop();
			mAnimations.Remove(animation);
		}
	}

	/// Stops and removes all animations.
	public void Clear()
	{
		for (let anim in mAnimations)
			anim.Stop();
		mAnimations.Clear();
		mPendingAdd.Clear();
		mPendingRemove.Clear();
	}

	/// Updates all animations by the given delta time.
	public void Update(float deltaTime)
	{
		mIsUpdating = true;

		// Update all animations
		for (int i = mAnimations.Count - 1; i >= 0; i--)
		{
			let anim = mAnimations[i];
			if (!anim.Update(deltaTime))
			{
				// Animation completed, remove it
				var animation = mAnimations[i];
				mAnimations.RemoveAt(i);
				delete animation;
			}
		}

		mIsUpdating = false;

		// Process pending operations
		for (let anim in mPendingRemove)
		{
			anim.Stop();
			mAnimations.Remove(anim);
		}
		mPendingRemove.Clear();

		for (let anim in mPendingAdd)
		{
			mAnimations.Add(anim);
			anim.Start();
		}
		mPendingAdd.Clear();
	}

	/// Pauses all animations.
	public void PauseAll()
	{
		for (let anim in mAnimations)
			anim.Pause();
	}

	/// Resumes all animations.
	public void ResumeAll()
	{
		for (let anim in mAnimations)
			anim.Resume();
	}
}

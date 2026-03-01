namespace Sedulous.Engine.Animation;

using System;
using System.Collections;
using Sedulous.Animation;
using Sedulous.Engine.Scenes;

/// Property animation instance storage and API.
extension AnimationSceneModule
{
	// ==================== Property Animation Instance Storage ====================

	public struct PropertyAnimationInstanceData
	{
		public EntityId Entity;
		public PropertyAnimationPlayer Player; // Owned by module
		public bool Playing;
		public float Speed;
		public bool Active; // Slot in use
	}

	private List<PropertyAnimationInstanceData> mPropertyAnimInstances = new .() ~ delete _;
	private List<int32> mFreePropertyAnimSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToPropertyAnim = new .() ~ delete _;

	/// Provides read access to instances for serialization.
	public List<PropertyAnimationInstanceData> PropertyAnimInstances => mPropertyAnimInstances;

	// ==================== Property Animation API ====================

	/// Plays a property animation clip on an entity.
	/// Creates a PropertyAnimationPlayer and PropertyAnimationComponent if needed.
	public PropertyAnimationPlayer PlayPropertyAnimation(EntityId entity, PropertyAnimationClip clip, bool loop = false)
	{
		if (mScene == null || clip == null || mPropertyBinderRegistry == null)
			return null;

		clip.IsLooping = loop;

		// Get or create instance slot
		int32 slotIdx;
		if (mEntityToPropertyAnim.TryGetValue(entity, let existingIdx))
		{
			slotIdx = existingIdx;
			// Reuse existing player
			var instance = ref mPropertyAnimInstances[slotIdx];
			if (instance.Player != null)
			{
				instance.Player.Play(clip);
				instance.Playing = true;
				instance.Speed = instance.Player.Speed;
				return instance.Player;
			}
		}
		else
		{
			if (mFreePropertyAnimSlots.Count > 0)
			{
				slotIdx = mFreePropertyAnimSlots.PopBack();
			}
			else
			{
				slotIdx = (int32)mPropertyAnimInstances.Count;
				mPropertyAnimInstances.Add(.());
			}
			var instance = ref mPropertyAnimInstances[slotIdx];
			instance = .();
			instance.Entity = entity;
			instance.Speed = 1.0f;
			instance.Active = true;
			mEntityToPropertyAnim[entity] = slotIdx;

			var comp = mScene.GetComponent<PropertyAnimationComponent>(entity);
			if (comp == null)
			{
				mScene.SetComponent<PropertyAnimationComponent>(entity, .());
				comp = mScene.GetComponent<PropertyAnimationComponent>(entity);
			}
			comp.InternalHandle = slotIdx;
		}

		let player = new PropertyAnimationPlayer(mScene, entity, mPropertyBinderRegistry);
		player.Play(clip);
		mPropertyAnimInstances[slotIdx].Player = player;
		mPropertyAnimInstances[slotIdx].Playing = true;
		mPropertyAnimInstances[slotIdx].Speed = player.Speed;

		return player;
	}

	/// Stops property animation on an entity.
	public void StopPropertyAnimation(EntityId entity)
	{
		if (!mEntityToPropertyAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mPropertyAnimInstances[idx];
		if (instance.Active && instance.Player != null)
		{
			instance.Player.Stop();
			instance.Playing = false;
		}
	}

	/// Pauses property animation on an entity.
	public void PausePropertyAnimation(EntityId entity)
	{
		if (!mEntityToPropertyAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mPropertyAnimInstances[idx];
		if (instance.Active && instance.Player != null)
		{
			instance.Player.Pause();
			instance.Playing = false;
		}
	}

	/// Resumes property animation on an entity.
	public void ResumePropertyAnimation(EntityId entity)
	{
		if (!mEntityToPropertyAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mPropertyAnimInstances[idx];
		if (instance.Active && instance.Player != null)
		{
			instance.Player.Resume();
			instance.Playing = true;
		}
	}

	/// Gets the property animation player for an entity.
	public PropertyAnimationPlayer GetPropertyAnimationPlayer(EntityId entity)
	{
		if (!mEntityToPropertyAnim.TryGetValue(entity, let idx))
			return null;

		let instance = ref mPropertyAnimInstances[idx];
		if (instance.Active)
			return instance.Player;

		return null;
	}

	/// Destroys property animation data for an entity.
	public void DestroyPropertyAnimation(EntityId entity)
	{
		if (!mEntityToPropertyAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mPropertyAnimInstances[idx];
		if (instance.Active)
		{
			if (instance.Player != null)
			{
				delete instance.Player;
				instance.Player = null;
			}
			instance.Active = false;
			mFreePropertyAnimSlots.Add(idx);
		}
		mEntityToPropertyAnim.Remove(entity);

		if (mScene != null)
		{
			if (let comp = mScene.GetComponent<PropertyAnimationComponent>(entity))
				comp.InternalHandle = -1;
		}
	}
}

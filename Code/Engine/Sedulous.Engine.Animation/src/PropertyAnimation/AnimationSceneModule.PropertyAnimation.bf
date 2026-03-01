namespace Sedulous.Engine.Animation;

using System;
using System.Collections;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Engine.Scenes;
using Sedulous.Resources;

/// Property animation instance storage and API.
extension AnimationSceneModule
{
	// ==================== Property Animation Instance Storage ====================

	public struct PropertyAnimationInstanceData
	{
		public EntityId Entity;
		public PropertyAnimationPlayer Player; // Owned by module
		public ResourceRef ClipRef;
		public ResourceHandle<PropertyAnimationClipResource> ClipRes;
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

	/// Creates a property animation instance from a resource reference (deferred loading).
	/// The clip will be resolved on the next Update frame.
	public void CreatePropertyAnimationFromRef(EntityId entity, ResourceRef clipRef, bool playing = true, float speed = 1.0f)
	{
		if (mScene == null)
			return;

		// Allocate a slot
		int32 slotIdx;
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
		if (clipRef.IsValid)
			instance.ClipRef = ResourceRef(clipRef.Id, clipRef.Path);
		instance.Playing = playing;
		instance.Speed = speed;
		instance.Active = true;

		mEntityToPropertyAnim[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<PropertyAnimationComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<PropertyAnimationComponent>(entity, .());
			comp = mScene.GetComponent<PropertyAnimationComponent>(entity);
		}
		comp.InternalHandle = slotIdx;
	}

	/// Resolves deserialized ResourceRef fields to loaded ResourceHandles for property animations.
	/// When the clip resource is loaded, sets up the PropertyAnimationPlayer.
	private void ResolvePropertyAnimResourceRefs()
	{
		let resourceSystem = mSubsystem.Context?.Resources;
		if (resourceSystem == null)
			return;

		for (var instance in ref mPropertyAnimInstances)
		{
			if (!instance.Active)
				continue;

			bool clipChanged = false;

			// Resolve clip ref
			if (instance.ClipRef.IsValid)
			{
				bool needsLoad = !instance.ClipRes.IsValid;
				if (!needsLoad && instance.ClipRef.HasId && instance.ClipRes.Resource != null && instance.ClipRes.Resource.Id != instance.ClipRef.Id)
				{
					instance.ClipRes.Release();
					needsLoad = true;
					clipChanged = true;
				}
				if (needsLoad)
				{
					if (resourceSystem.LoadByRef<PropertyAnimationClipResource>(instance.ClipRef) case .Ok(let handle))
						instance.ClipRes = handle;
				}
			}

			// Set up player when resource is loaded
			if (instance.ClipRes.IsValid)
			{
				if (instance.Player == null || clipChanged)
				{
					let clip = instance.ClipRes.Resource?.Clip;
					if (clip != null && mPropertyBinderRegistry != null)
					{
						// Delete old player if exists
						if (instance.Player != null)
							delete instance.Player;

						let player = new PropertyAnimationPlayer(mScene, instance.Entity, mPropertyBinderRegistry);
						instance.Player = player;
						player.Speed = instance.Speed;

						if (instance.Playing)
							player.Play(clip);
					}
				}
			}
		}
	}

	/// Destroys property animation data for an entity.
	public void DestroyPropertyAnimation(EntityId entity)
	{
		if (!mEntityToPropertyAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mPropertyAnimInstances[idx];
		if (instance.Active)
		{
			instance.ClipRes.Release();
			instance.ClipRef.Dispose();
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

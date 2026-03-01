namespace Sedulous.Engine.Animation;

using System;
using System.Collections;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Resources;

/// Skeletal animation instance storage and API.
extension AnimationSceneModule
{
	// ==================== Skeletal Animation Instance Storage ====================

	public struct SkeletalAnimationInstanceData
	{
		public EntityId Entity;
		public AnimationPlayer Player; // Owned by module
		public ResourceHandle<SkeletonResource> SkeletonRes;
		public ResourceRef SkeletonRef;
		public ResourceHandle<AnimationClipResource> AnimationClipRes;
		public ResourceRef AnimationClipRef;
		public bool Playing;
		public bool Loop;
		public bool Active; // Slot in use
	}

	private List<SkeletalAnimationInstanceData> mSkeletalAnimInstances = new .() ~ delete _;
	private List<int32> mFreeSkeletalAnimSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToSkeletalAnim = new .() ~ delete _;

	/// Provides read access to instances for serialization.
	public List<SkeletalAnimationInstanceData> SkeletalAnimInstances => mSkeletalAnimInstances;

	// ==================== Skeletal Animation API ====================

	/// Creates a skeletal animation instance from resource references (deferred loading).
	/// The skeleton and clip will be resolved on the next Update frame.
	public void CreateSkeletalAnimation(EntityId entity, ResourceRef skeletonRef, ResourceRef clipRef, bool playing = true, bool loop = true)
	{
		if (mScene == null)
			return;

		// Allocate a slot
		int32 slotIdx;
		if (mFreeSkeletalAnimSlots.Count > 0)
		{
			slotIdx = mFreeSkeletalAnimSlots.PopBack();
		}
		else
		{
			slotIdx = (int32)mSkeletalAnimInstances.Count;
			mSkeletalAnimInstances.Add(.());
		}

		var instance = ref mSkeletalAnimInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		if (skeletonRef.IsValid)
			instance.SkeletonRef = ResourceRef(skeletonRef.Id, skeletonRef.Path);
		if (clipRef.IsValid)
			instance.AnimationClipRef = ResourceRef(clipRef.Id, clipRef.Path);
		instance.Playing = playing;
		instance.Loop = loop;
		instance.Active = true;

		mEntityToSkeletalAnim[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<SkeletalAnimationComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<SkeletalAnimationComponent>(entity, .());
			comp = mScene.GetComponent<SkeletalAnimationComponent>(entity);
		}
		comp.InternalHandle = slotIdx;
	}

	/// Sets up skeletal animation for an entity with an already-loaded skeleton.
	/// Creates the AnimationPlayer immediately.
	public AnimationPlayer SetupAnimation(EntityId entity, Skeleton skeleton)
	{
		if (mScene == null || skeleton == null)
			return null;

		// Get or create instance slot
		int32 slotIdx;
		if (mEntityToSkeletalAnim.TryGetValue(entity, let existingIdx))
		{
			slotIdx = existingIdx;
			// Delete existing player
			var instance = ref mSkeletalAnimInstances[slotIdx];
			if (instance.Player != null)
			{
				delete instance.Player;
				instance.Player = null;
			}
		}
		else
		{
			// Allocate new slot
			if (mFreeSkeletalAnimSlots.Count > 0)
			{
				slotIdx = mFreeSkeletalAnimSlots.PopBack();
			}
			else
			{
				slotIdx = (int32)mSkeletalAnimInstances.Count;
				mSkeletalAnimInstances.Add(.());
			}
			var instance = ref mSkeletalAnimInstances[slotIdx];
			instance = .();
			instance.Entity = entity;
			instance.Loop = true;
			instance.Active = true;
			mEntityToSkeletalAnim[entity] = slotIdx;

			// Set handle on entity component
			var comp = mScene.GetComponent<SkeletalAnimationComponent>(entity);
			if (comp == null)
			{
				mScene.SetComponent<SkeletalAnimationComponent>(entity, .());
				comp = mScene.GetComponent<SkeletalAnimationComponent>(entity);
			}
			comp.InternalHandle = slotIdx;
		}

		// Create new player
		let player = new AnimationPlayer(skeleton);
		mSkeletalAnimInstances[slotIdx].Player = player;

		return player;
	}

	/// Plays an animation clip on an entity.
	public void Play(EntityId entity, AnimationClip clip, bool loop = true)
	{
		if (mScene == null || clip == null)
			return;

		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mSkeletalAnimInstances[idx];
		if (instance.Active && instance.Player != null)
		{
			clip.IsLooping = loop;
			instance.Player.Play(clip);
			instance.Playing = true;
			instance.Loop = loop;
		}
	}

	/// Stops animation on an entity.
	public void Stop(EntityId entity)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mSkeletalAnimInstances[idx];
		if (instance.Active && instance.Player != null)
		{
			instance.Player.Stop();
			instance.Playing = false;
		}
	}

	/// Pauses animation on an entity.
	public void Pause(EntityId entity)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mSkeletalAnimInstances[idx];
		if (instance.Active && instance.Player != null)
		{
			instance.Player.Pause();
			instance.Playing = false;
		}
	}

	/// Resumes animation on an entity.
	public void Resume(EntityId entity)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mSkeletalAnimInstances[idx];
		if (instance.Active && instance.Player != null)
		{
			instance.Player.Resume();
			instance.Playing = true;
		}
	}

	/// Gets the skinning matrices for an entity's animation.
	public Span<Matrix> GetSkinningMatrices(EntityId entity)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return .();

		let instance = ref mSkeletalAnimInstances[idx];
		if (instance.Active && instance.Player != null)
			return instance.Player.GetSkinningMatrices();

		return .();
	}

	/// Gets the previous frame's skinning matrices (for motion blur).
	public Span<Matrix> GetPrevSkinningMatrices(EntityId entity)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return .();

		let instance = ref mSkeletalAnimInstances[idx];
		if (instance.Active && instance.Player != null)
			return instance.Player.GetPrevSkinningMatrices();

		return .();
	}

	/// Gets the resolved skeleton for an entity (for bone count, etc.).
	public Skeleton GetSkeleton(EntityId entity)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return null;

		let instance = ref mSkeletalAnimInstances[idx];
		if (instance.Active)
			return instance.SkeletonRes.Resource?.Skeleton;

		return null;
	}

	/// Gets the animation player for an entity.
	public AnimationPlayer GetPlayer(EntityId entity)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return null;

		let instance = ref mSkeletalAnimInstances[idx];
		if (instance.Active)
			return instance.Player;

		return null;
	}

	/// Sets the animation speed for an entity.
	public void SetSpeed(EntityId entity, float speed)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mSkeletalAnimInstances[idx];
		if (instance.Active && instance.Player != null)
			instance.Player.Speed = speed;
	}

	/// Gets whether the animation is currently playing.
	public bool IsPlaying(EntityId entity)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return false;

		let instance = ref mSkeletalAnimInstances[idx];
		return instance.Active && instance.Playing;
	}

	/// Destroys skeletal animation data for an entity.
	public void DestroySkeletalAnimation(EntityId entity)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mSkeletalAnimInstances[idx];
		if (instance.Active)
		{
			instance.SkeletonRes.Release();
			instance.SkeletonRef.Dispose();
			instance.AnimationClipRes.Release();
			instance.AnimationClipRef.Dispose();
			if (instance.Player != null)
			{
				delete instance.Player;
				instance.Player = null;
			}
			instance.Active = false;
			mFreeSkeletalAnimSlots.Add(idx);
		}
		mEntityToSkeletalAnim.Remove(entity);

		// Clear handle on component
		if (mScene != null)
		{
			if (let comp = mScene.GetComponent<SkeletalAnimationComponent>(entity))
				comp.InternalHandle = -1;
		}
	}

	/// Resolves deserialized ResourceRef fields to loaded ResourceHandles for skeletal animations.
	/// When both skeleton and animation clip are loaded, sets up the AnimationPlayer.
	private void ResolveSkeletalAnimResourceRefs()
	{
		let resourceSystem = mSubsystem.Context?.Resources;
		if (resourceSystem == null)
			return;

		for (var instance in ref mSkeletalAnimInstances)
		{
			if (!instance.Active)
				continue;

			bool skeletonChanged = false;
			bool clipChanged = false;

			// Resolve skeleton ref
			if (instance.SkeletonRef.IsValid)
			{
				bool needsLoad = !instance.SkeletonRes.IsValid;
				if (!needsLoad && instance.SkeletonRef.HasId && instance.SkeletonRes.Resource != null && instance.SkeletonRes.Resource.Id != instance.SkeletonRef.Id)
				{
					instance.SkeletonRes.Release();
					needsLoad = true;
					skeletonChanged = true;
				}
				if (needsLoad)
				{
					if (resourceSystem.LoadByRef<SkeletonResource>(instance.SkeletonRef) case .Ok(let handle))
						instance.SkeletonRes = handle;
				}
			}

			// Resolve animation clip ref
			if (instance.AnimationClipRef.IsValid)
			{
				bool needsLoad = !instance.AnimationClipRes.IsValid;
				if (!needsLoad && instance.AnimationClipRef.HasId && instance.AnimationClipRes.Resource != null && instance.AnimationClipRes.Resource.Id != instance.AnimationClipRef.Id)
				{
					instance.AnimationClipRes.Release();
					needsLoad = true;
					clipChanged = true;
				}
				if (needsLoad)
				{
					if (resourceSystem.LoadByRef<AnimationClipResource>(instance.AnimationClipRef) case .Ok(let handle))
						instance.AnimationClipRes = handle;
				}
			}

			// Set up animation player when both resources are loaded
			if (instance.SkeletonRes.IsValid && instance.AnimationClipRes.IsValid)
			{
				if (instance.Player == null || skeletonChanged || clipChanged)
				{
					let skeleton = instance.SkeletonRes.Resource?.Skeleton;
					let clip = instance.AnimationClipRes.Resource?.Clip;
					if (skeleton != null && clip != null)
					{
						// Delete old player if exists
						if (instance.Player != null)
							delete instance.Player;

						let player = new AnimationPlayer(skeleton);
						instance.Player = player;

						if (instance.Playing)
						{
							clip.IsLooping = instance.Loop;
							player.Play(clip);
						}
					}
				}
			}
		}
	}
}

namespace Sedulous.Framework.Animation;

using System;
using System.Collections;
using Sedulous.Animation;
using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;

/// Component for entities with skeletal animation.
struct SkeletalAnimationComponent
{
	/// The animation player for this entity.
	public AnimationPlayer Player;
	/// The skeleton reference.
	public Skeleton Skeleton;
	/// Whether the animation is playing.
	public bool Playing;

	public static SkeletalAnimationComponent Default => .() {
		Player = null,
		Skeleton = null,
		Playing = false
	};
}

/// Scene module that manages entity animations.
/// Created automatically by AnimationSubsystem for each scene.
class AnimationSceneModule : SceneModule
{
	private AnimationSubsystem mSubsystem;
	private Scene mScene;

	// Animation players owned by this module (one per animated entity)
	private Dictionary<uint64, AnimationPlayer> mPlayers = new .() ~ {
		for (let (_, player) in _)
			delete player;
		delete _;
	};

	/// Creates an AnimationSceneModule linked to the given subsystem.
	public this(AnimationSubsystem subsystem)
	{
		mSubsystem = subsystem;
	}

	/// Gets the animation subsystem.
	public AnimationSubsystem Subsystem => mSubsystem;

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;
	}

	public override void OnSceneDestroy(Scene scene)
	{
		// Clean up all animation players
		for (let (_, player) in mPlayers)
			delete player;
		mPlayers.Clear();
		mScene = null;
	}

	public override void Update(Scene scene, float deltaTime)
	{
		// Update all animation players
		for (let (entity, anim) in scene.Query<SkeletalAnimationComponent>())
		{
			if (anim.Player == null || !anim.Playing)
				continue;

			anim.Player.Update(deltaTime);
		}
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		// Clean up animation player
		let key = PackEntityId(entity);
		if (mPlayers.TryGetValue(key, let player))
		{
			mPlayers.Remove(key);
			delete player;
		}
	}

	// ==================== Animation Control ====================

	/// Sets up skeletal animation for an entity.
	public AnimationPlayer SetupAnimation(EntityId entity, Skeleton skeleton)
	{
		if (mScene == null || skeleton == null)
			return null;

		let key = PackEntityId(entity);

		// Remove existing player
		if (mPlayers.TryGetValue(key, let existing))
		{
			mPlayers.Remove(key);
			delete existing;
		}

		// Create new player
		let player = new AnimationPlayer(skeleton);
		mPlayers[key] = player;

		// Set up component
		var anim = mScene.GetComponent<SkeletalAnimationComponent>(entity);
		if (anim == null)
		{
			mScene.SetComponent<SkeletalAnimationComponent>(entity, .Default);
			anim = mScene.GetComponent<SkeletalAnimationComponent>(entity);
		}

		anim.Player = player;
		anim.Skeleton = skeleton;
		anim.Playing = false;

		return player;
	}

	/// Plays an animation clip on an entity.
	public void Play(EntityId entity, AnimationClip clip, bool loop = true)
	{
		if (mScene == null)
			return;

		if (let anim = mScene.GetComponent<SkeletalAnimationComponent>(entity))
		{
			if (anim.Player != null)
			{
				anim.Player.Play(clip, loop);
				anim.Playing = true;
			}
		}
	}

	/// Stops animation on an entity.
	public void Stop(EntityId entity)
	{
		if (mScene == null)
			return;

		if (let anim = mScene.GetComponent<SkeletalAnimationComponent>(entity))
		{
			if (anim.Player != null)
			{
				anim.Player.Stop();
				anim.Playing = false;
			}
		}
	}

	/// Pauses animation on an entity.
	public void Pause(EntityId entity)
	{
		if (mScene == null)
			return;

		if (let anim = mScene.GetComponent<SkeletalAnimationComponent>(entity))
		{
			if (anim.Player != null)
			{
				anim.Player.Pause();
				anim.Playing = false;
			}
		}
	}

	/// Resumes animation on an entity.
	public void Resume(EntityId entity)
	{
		if (mScene == null)
			return;

		if (let anim = mScene.GetComponent<SkeletalAnimationComponent>(entity))
		{
			if (anim.Player != null)
			{
				anim.Player.Resume();
				anim.Playing = true;
			}
		}
	}

	/// Gets the skinning matrices for an entity's animation.
	/// Use this to upload bone transforms to the GPU.
	public Span<Matrix> GetSkinningMatrices(EntityId entity)
	{
		if (mScene == null)
			return .();

		if (let anim = mScene.GetComponent<SkeletalAnimationComponent>(entity))
		{
			if (anim.Player != null)
				return anim.Player.GetSkinningMatrices();
		}
		return .();
	}

	/// Sets the animation speed for an entity.
	public void SetSpeed(EntityId entity, float speed)
	{
		if (mScene == null)
			return;

		if (let anim = mScene.GetComponent<SkeletalAnimationComponent>(entity))
		{
			if (anim.Player != null)
				anim.Player.Speed = speed;
		}
	}

	/// Gets whether the animation is currently playing.
	public bool IsPlaying(EntityId entity)
	{
		if (mScene == null)
			return false;

		if (let anim = mScene.GetComponent<SkeletalAnimationComponent>(entity))
			return anim.Playing;

		return false;
	}

	// ==================== Private ====================

	/// Packs entity ID into a uint64 for dictionary key.
	private static uint64 PackEntityId(EntityId entity)
	{
		return ((uint64)entity.Index) | (((uint64)entity.Generation) << 32);
	}
}

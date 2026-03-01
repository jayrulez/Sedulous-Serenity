namespace Sedulous.Engine.Animation;

using System;
using System.Collections;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Resources;
using Sedulous.Serialization;

/// Scene module that manages entity animations.
/// Created automatically by AnimationSubsystem for each scene.
///
/// All animation data is owned by this module in internal instance storage.
/// Components are thin handles into this storage.
///
/// Component-specific storage and API are split into extension files:
///   AnimationSceneModule.SkeletalAnimation.bf
///   AnimationSceneModule.AnimationGraph.bf
///   AnimationSceneModule.PropertyAnimation.bf
class AnimationSceneModule : SceneModule
{
	private AnimationSubsystem mSubsystem;
	private Scene mScene;
	private PropertyBinderRegistry mPropertyBinderRegistry;

	// ==================== Construction ====================

	/// Creates an AnimationSceneModule linked to the given subsystem.
	public this(AnimationSubsystem subsystem, PropertyBinderRegistry propertyBinderRegistry)
	{
		mSubsystem = subsystem;
		mPropertyBinderRegistry = propertyBinderRegistry;
	}

	/// Gets the animation subsystem.
	public AnimationSubsystem Subsystem => mSubsystem;

	// ==================== Scene Lifecycle ====================

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;

		// Register custom serializers for module-owned components
		scene.RegisterComponentSerializer(new SkeletalAnimationComponentSerializer());
		scene.RegisterComponentSerializer(new AnimationGraphComponentSerializer());
		scene.RegisterComponentSerializer(new PropertyAnimationComponentSerializer());
	}

	public override void OnSceneDestroy(Scene scene)
	{
		// Release skeletal animation instances
		for (var instance in ref mSkeletalAnimInstances)
		{
			if (!instance.Active) continue;
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
		}
		mSkeletalAnimInstances.Clear();
		mFreeSkeletalAnimSlots.Clear();
		mEntityToSkeletalAnim.Clear();

		// Release graph animation instances
		for (var instance in ref mGraphAnimInstances)
		{
			if (!instance.Active) continue;
			instance.SkeletonRes.Release();
			instance.SkeletonRef.Dispose();
			if (instance.Player != null)
			{
				delete instance.Player;
				instance.Player = null;
			}
			instance.Active = false;
		}
		mGraphAnimInstances.Clear();
		mFreeGraphAnimSlots.Clear();
		mEntityToGraphAnim.Clear();

		// Release property animation instances
		for (var instance in ref mPropertyAnimInstances)
		{
			if (!instance.Active) continue;
			instance.ClipRes.Release();
			instance.ClipRef.Dispose();
			if (instance.Player != null)
			{
				delete instance.Player;
				instance.Player = null;
			}
			instance.Active = false;
		}
		mPropertyAnimInstances.Clear();
		mFreePropertyAnimSlots.Clear();
		mEntityToPropertyAnim.Clear();

		mScene = null;
	}

	public override void Update(Scene scene, float deltaTime)
	{
		// Resolve deserialized resource references
		ResolveSkeletalAnimResourceRefs();
		ResolveGraphResourceRefs();
		ResolvePropertyAnimResourceRefs();

		// Update all skeletal animation players
		for (var instance in ref mSkeletalAnimInstances)
		{
			if (!instance.Active || instance.Player == null)
				continue;

			// Detect Playing toggled on: player exists but isn't currently playing a clip
			if (instance.Playing && instance.Player.State != PlaybackState.Playing)
			{
				let clip = instance.AnimationClipRes.Resource?.Clip;
				if (clip != null)
				{
					clip.IsLooping = instance.Loop;
					instance.Player.Play(clip);
				}
			}

			// Sync Loop property to the clip
			if (instance.Player.CurrentClip != null)
				instance.Player.CurrentClip.IsLooping = instance.Loop;

			if (!instance.Playing)
				continue;

			instance.Player.Update(deltaTime);
		}

		// Update all property animation players
		for (var instance in ref mPropertyAnimInstances)
		{
			if (!instance.Active || instance.Player == null)
				continue;

			// Sync speed
			instance.Player.Speed = instance.Speed;

			// Detect Playing toggled on: player exists but isn't currently playing a clip
			if (instance.Playing && instance.Player.State != PropertyPlaybackState.Playing)
			{
				let clip = instance.ClipRes.Resource?.Clip;
				if (clip != null)
					instance.Player.Play(clip);
			}

			if (!instance.Playing)
				continue;

			instance.Player.Update(deltaTime);
		}

		// Update all graph players
		for (var instance in ref mGraphAnimInstances)
		{
			if (!instance.Active || instance.Player == null || !instance.GraphActive)
				continue;

			instance.Player.Update(deltaTime);

			// Sync graph player output to standard animation player for render module
			if (mEntityToSkeletalAnim.TryGetValue(instance.Entity, let skelIdx))
			{
				let skelInstance = ref mSkeletalAnimInstances[skelIdx];
				if (skelInstance.Active && skelInstance.Player != null)
					skelInstance.Player.OverrideSkinningMatrices(instance.Player.GetSkinningMatrices(), instance.Player.GetPrevSkinningMatrices());
			}
		}
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		DestroySkeletalAnimation(entity);
		DestroyGraphAnimation(entity);
		DestroyPropertyAnimation(entity);
	}
}

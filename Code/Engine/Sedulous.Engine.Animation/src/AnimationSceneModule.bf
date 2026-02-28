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
class AnimationSceneModule : SceneModule
{
	private AnimationSubsystem mSubsystem;
	private Scene mScene;
	private PropertyBinderRegistry mPropertyBinderRegistry;

	// Animation players owned by this module (one per animated entity)
	private Dictionary<uint64, AnimationPlayer> mPlayers = new .() ~ {
		for (let entry in _)
			delete entry.value;
		delete _;
	};

	// Graph players owned by this module (one per graph-animated entity)
	private Dictionary<uint64, AnimationGraphPlayer> mGraphPlayers = new .() ~ {
		for (let entry in _)
			delete entry.value;
		delete _;
	};

	// Property animation players owned by this module (one per property-animated entity)
	private Dictionary<uint64, PropertyAnimationPlayer> mPropertyPlayers = new .() ~ {
		for (let entry in _)
			delete entry.value;
		delete _;
	};

	/// Creates an AnimationSceneModule linked to the given subsystem.
	public this(AnimationSubsystem subsystem, PropertyBinderRegistry propertyBinderRegistry)
	{
		mSubsystem = subsystem;
		mPropertyBinderRegistry = propertyBinderRegistry;
	}

	/// Gets the animation subsystem.
	public AnimationSubsystem Subsystem => mSubsystem;

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;
	}

	public override void OnSceneDestroy(Scene scene)
	{
		// Release resource handles and refs on all animation components
		for (let (entity, anim) in scene.Query<SkeletalAnimationComponent>())
		{
			anim.SkeletonRes.Release();
			anim.AnimationClipRes.Release();
			anim.SkeletonRef.Dispose();
			anim.AnimationClipRef.Dispose();
		}

		// Release resource handles and refs on all graph animation components
		for (let (entity, graphAnim) in scene.Query<AnimationGraphComponent>())
		{
			graphAnim.SkeletonRes.Release();
			graphAnim.SkeletonRef.Dispose();
		}

		// Clean up all animation players
		for (let (_, player) in mPlayers)
			delete player;
		mPlayers.Clear();

		// Clean up all graph players
		for (let (_, player) in mGraphPlayers)
			delete player;
		mGraphPlayers.Clear();

		// Clean up all property animation players
		for (let (_, player) in mPropertyPlayers)
			delete player;
		mPropertyPlayers.Clear();

		mScene = null;
	}

	public override void Update(Scene scene, float deltaTime)
	{
		// Resolve deserialized resource references
		ResolveResourceRefs(scene);

		// Update all animation players
		for (let (entity, anim) in scene.Query<SkeletalAnimationComponent>())
		{
			if (anim.Player == null)
				continue;

			// Detect Playing toggled on: player exists but isn't currently playing a clip
			if (anim.Playing && anim.Player.State != PlaybackState.Playing)
			{
				let clip = anim.AnimationClipRes.Resource?.Clip;
				if (clip != null)
				{
					clip.IsLooping = anim.Loop;
					anim.Player.Play(clip);
				}
			}

			// Sync Loop property to the clip
			if (anim.Player.CurrentClip != null)
				anim.Player.CurrentClip.IsLooping = anim.Loop;

			if (!anim.Playing)
				continue;

			anim.Player.Update(deltaTime);
		}

		// Resolve graph resource references
		ResolveGraphResourceRefs(scene);

		// Update all property animation players
		for (let (entity, propAnim) in scene.Query<PropertyAnimationComponent>())
		{
			if (propAnim.Player == null || !propAnim.Playing)
				continue;

			propAnim.Player.Update(deltaTime);
		}

		// Update all graph players
		for (let (entity, graphAnim) in scene.Query<AnimationGraphComponent>())
		{
			if (graphAnim.Player == null || !graphAnim.Active)
				continue;

			graphAnim.Player.Update(deltaTime);

			// Sync graph player output to standard animation player for render module
			if (let anim = scene.GetComponent<SkeletalAnimationComponent>(entity))
			{
				if (anim.Player != null)
					anim.Player.OverrideSkinningMatrices(graphAnim.Player.GetSkinningMatrices(), graphAnim.Player.GetPrevSkinningMatrices());
			}
		}
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		// Release resource handles and refs on the component
		if (let anim = scene.GetComponent<SkeletalAnimationComponent>(entity))
		{
			anim.SkeletonRes.Release();
			anim.AnimationClipRes.Release();
			anim.SkeletonRef.Dispose();
			anim.AnimationClipRef.Dispose();
		}

		// Release graph animation component resources
		if (let graphAnim = scene.GetComponent<AnimationGraphComponent>(entity))
		{
			graphAnim.SkeletonRes.Release();
			graphAnim.SkeletonRef.Dispose();
		}

		// Clean up animation player
		let key = PackEntityId(entity);
		if (mPlayers.TryGetValue(key, let player))
		{
			mPlayers.Remove(key);
			delete player;
		}

		// Clean up graph player
		if (mGraphPlayers.TryGetValue(key, let graphPlayer))
		{
			mGraphPlayers.Remove(key);
			delete graphPlayer;
		}

		// Clean up property animation player
		if (mPropertyPlayers.TryGetValue(key, let propPlayer))
		{
			mPropertyPlayers.Remove(key);
			delete propPlayer;
		}
	}

	// ==================== Resource Resolution ====================

	/// Resolves deserialized ResourceRef fields to loaded ResourceHandles.
	/// When both skeleton and animation clip are loaded, sets up the AnimationPlayer.
	private void ResolveResourceRefs(Scene scene)
	{
		let resourceSystem = mSubsystem.Context?.Resources;
		if (resourceSystem == null)
			return;

		for (let (entity, anim) in scene.Query<SkeletalAnimationComponent>())
		{
			bool skeletonChanged = false;
			bool clipChanged = false;

			// Resolve skeleton ref (load new or reload on ref change)
			if (anim.SkeletonRef.IsValid)
			{
				bool needsLoad = !anim.SkeletonRes.IsValid;
				if (!needsLoad && anim.SkeletonRef.HasId && anim.SkeletonRes.Resource != null && anim.SkeletonRes.Resource.Id != anim.SkeletonRef.Id)
				{
					anim.SkeletonRes.Release();
					needsLoad = true;
					skeletonChanged = true;
				}
				if (needsLoad)
				{
					if (resourceSystem.LoadByRef<SkeletonResource>(anim.SkeletonRef) case .Ok(let handle))
						anim.SkeletonRes = handle;
				}
			}

			// Resolve animation clip ref (load new or reload on ref change)
			if (anim.AnimationClipRef.IsValid)
			{
				bool needsLoad = !anim.AnimationClipRes.IsValid;
				if (!needsLoad && anim.AnimationClipRef.HasId && anim.AnimationClipRes.Resource != null && anim.AnimationClipRes.Resource.Id != anim.AnimationClipRef.Id)
				{
					anim.AnimationClipRes.Release();
					needsLoad = true;
					clipChanged = true;
				}
				if (needsLoad)
				{
					if (resourceSystem.LoadByRef<AnimationClipResource>(anim.AnimationClipRef) case .Ok(let handle))
						anim.AnimationClipRes = handle;
				}
			}

			// Set up animation player when both resources are loaded and no player exists yet
			// Also re-setup if skeleton or clip changed
			if (anim.SkeletonRes.IsValid && anim.AnimationClipRes.IsValid)
			{
				if (anim.Player == null || skeletonChanged || clipChanged)
				{
					let skeleton = anim.SkeletonRes.Resource?.Skeleton;
					let clip = anim.AnimationClipRes.Resource?.Clip;
					if (skeleton != null && clip != null)
					{
						let player = SetupAnimation(entity, skeleton);
						if (player != null && anim.Playing)
						{
							clip.IsLooping = anim.Loop;
							player.Play(clip);
						}
					}
				}
			}
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

		return player;
	}

	/// Plays an animation clip on an entity.
	public void Play(EntityId entity, AnimationClip clip, bool loop = true)
	{
		if (mScene == null || clip == null)
			return;

		if (let anim = mScene.GetComponent<SkeletalAnimationComponent>(entity))
		{
			if (anim.Player != null)
			{
				clip.IsLooping = loop;
				anim.Player.Play(clip);
				anim.Playing = true;
				anim.Loop = loop;
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

	// ==================== Graph Animation Control ====================

	/// Resolves deserialized ResourceRef fields on AnimationGraphComponents.
	private void ResolveGraphResourceRefs(Scene scene)
	{
		let resourceSystem = mSubsystem.Context?.Resources;
		if (resourceSystem == null)
			return;

		for (let (entity, graphAnim) in scene.Query<AnimationGraphComponent>())
		{
			// Resolve skeleton ref (load new or reload on ref change)
			if (graphAnim.SkeletonRef.IsValid)
			{
				bool needsLoad = !graphAnim.SkeletonRes.IsValid;
				if (!needsLoad && graphAnim.SkeletonRef.HasId && graphAnim.SkeletonRes.Resource != null && graphAnim.SkeletonRes.Resource.Id != graphAnim.SkeletonRef.Id)
				{
					graphAnim.SkeletonRes.Release();
					needsLoad = true;
				}
				if (needsLoad)
				{
					if (resourceSystem.LoadByRef<SkeletonResource>(graphAnim.SkeletonRef) case .Ok(let handle))
						graphAnim.SkeletonRes = handle;
				}
			}
		}
	}

	/// Sets up an animation graph player for an entity.
	/// The graph and skeleton must be provided; the player is created and stored.
	public AnimationGraphPlayer SetupGraphAnimation(EntityId entity, AnimationGraph graph, Skeleton skeleton)
	{
		if (mScene == null || graph == null || skeleton == null)
			return null;

		let key = PackEntityId(entity);

		// Remove existing graph player
		if (mGraphPlayers.TryGetValue(key, let existing))
		{
			mGraphPlayers.Remove(key);
			delete existing;
		}

		// Create new graph player
		let player = new AnimationGraphPlayer(graph, skeleton);
		mGraphPlayers[key] = player;

		// Set up component
		var graphAnim = mScene.GetComponent<AnimationGraphComponent>(entity);
		if (graphAnim == null)
		{
			mScene.SetComponent<AnimationGraphComponent>(entity, .Default);
			graphAnim = mScene.GetComponent<AnimationGraphComponent>(entity);
		}

		graphAnim.Player = player;
		graphAnim.Graph = graph;

		return player;
	}

	/// Gets the animation graph player for an entity.
	public AnimationGraphPlayer GetGraphPlayer(EntityId entity)
	{
		if (mScene == null)
			return null;

		if (let graphAnim = mScene.GetComponent<AnimationGraphComponent>(entity))
			return graphAnim.Player;

		return null;
	}

	/// Gets the skinning matrices produced by an entity's graph player.
	public Span<Matrix> GetGraphSkinningMatrices(EntityId entity)
	{
		if (mScene == null)
			return .();

		if (let graphAnim = mScene.GetComponent<AnimationGraphComponent>(entity))
		{
			if (graphAnim.Player != null)
				return graphAnim.Player.GetSkinningMatrices();
		}
		return .();
	}

	// ==================== Property Animation Control ====================

	/// Plays a property animation clip on an entity.
	/// Creates a PropertyAnimationPlayer and PropertyAnimationComponent if needed.
	public PropertyAnimationPlayer PlayPropertyAnimation(EntityId entity, PropertyAnimationClip clip, bool loop = false)
	{
		if (mScene == null || clip == null || mPropertyBinderRegistry == null)
			return null;

		clip.IsLooping = loop;

		let key = PackEntityId(entity);

		// Reuse or create player
		PropertyAnimationPlayer player;
		if (mPropertyPlayers.TryGetValue(key, let existing))
		{
			player = existing;
		}
		else
		{
			player = new PropertyAnimationPlayer(mScene, entity, mPropertyBinderRegistry);
			mPropertyPlayers[key] = player;
		}

		player.Play(clip);

		// Set up component
		var propAnim = mScene.GetComponent<PropertyAnimationComponent>(entity);
		if (propAnim == null)
		{
			mScene.SetComponent<PropertyAnimationComponent>(entity, .Default);
			propAnim = mScene.GetComponent<PropertyAnimationComponent>(entity);
		}

		propAnim.Player = player;
		propAnim.Playing = true;
		propAnim.Speed = player.Speed;

		return player;
	}

	/// Stops property animation on an entity.
	public void StopPropertyAnimation(EntityId entity)
	{
		if (mScene == null)
			return;

		if (let propAnim = mScene.GetComponent<PropertyAnimationComponent>(entity))
		{
			if (propAnim.Player != null)
			{
				propAnim.Player.Stop();
				propAnim.Playing = false;
			}
		}
	}

	/// Pauses property animation on an entity.
	public void PausePropertyAnimation(EntityId entity)
	{
		if (mScene == null)
			return;

		if (let propAnim = mScene.GetComponent<PropertyAnimationComponent>(entity))
		{
			if (propAnim.Player != null)
			{
				propAnim.Player.Pause();
				propAnim.Playing = false;
			}
		}
	}

	/// Resumes property animation on an entity.
	public void ResumePropertyAnimation(EntityId entity)
	{
		if (mScene == null)
			return;

		if (let propAnim = mScene.GetComponent<PropertyAnimationComponent>(entity))
		{
			if (propAnim.Player != null)
			{
				propAnim.Player.Resume();
				propAnim.Playing = true;
			}
		}
	}

	/// Gets the property animation player for an entity.
	public PropertyAnimationPlayer GetPropertyAnimationPlayer(EntityId entity)
	{
		let key = PackEntityId(entity);
		if (mPropertyPlayers.TryGetValue(key, let player))
			return player;
		return null;
	}

	// ==================== Private ====================

	/// Packs entity ID into a uint64 for dictionary key.
	private static uint64 PackEntityId(EntityId entity)
	{
		return ((uint64)entity.Index) | (((uint64)entity.Generation) << 32);
	}
}

namespace Sedulous.Engine.Animation;

using System;
using System.Collections;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Resources;

/// Animation graph instance storage and API.
extension AnimationSceneModule
{
	// ==================== Animation Graph Instance Storage ====================

	public struct AnimationGraphInstanceData
	{
		public EntityId Entity;
		public AnimationGraphPlayer Player; // Owned by module
		public AnimationGraph Graph; // Borrowed reference
		public ResourceHandle<SkeletonResource> SkeletonRes;
		public ResourceRef SkeletonRef;
		public bool GraphActive; // Whether graph is evaluating
		public bool Active; // Slot in use
	}

	private List<AnimationGraphInstanceData> mGraphAnimInstances = new .() ~ delete _;
	private List<int32> mFreeGraphAnimSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToGraphAnim = new .() ~ delete _;

	/// Provides read access to instances for serialization.
	public List<AnimationGraphInstanceData> GraphAnimInstances => mGraphAnimInstances;

	// ==================== Animation Graph API ====================

	/// Sets up an animation graph player for an entity.
	public AnimationGraphPlayer SetupGraphAnimation(EntityId entity, AnimationGraph graph, Skeleton skeleton)
	{
		if (mScene == null || graph == null || skeleton == null)
			return null;

		// Get or create instance slot
		int32 slotIdx;
		if (mEntityToGraphAnim.TryGetValue(entity, let existingIdx))
		{
			slotIdx = existingIdx;
			var instance = ref mGraphAnimInstances[slotIdx];
			if (instance.Player != null)
			{
				delete instance.Player;
				instance.Player = null;
			}
		}
		else
		{
			if (mFreeGraphAnimSlots.Count > 0)
			{
				slotIdx = mFreeGraphAnimSlots.PopBack();
			}
			else
			{
				slotIdx = (int32)mGraphAnimInstances.Count;
				mGraphAnimInstances.Add(.());
			}
			var instance = ref mGraphAnimInstances[slotIdx];
			instance = .();
			instance.Entity = entity;
			instance.GraphActive = true;
			instance.Active = true;
			mEntityToGraphAnim[entity] = slotIdx;

			// Set handle on entity component
			var comp = mScene.GetComponent<AnimationGraphComponent>(entity);
			if (comp == null)
			{
				mScene.SetComponent<AnimationGraphComponent>(entity, .());
				comp = mScene.GetComponent<AnimationGraphComponent>(entity);
			}
			comp.InternalHandle = slotIdx;
		}

		// Create new graph player
		let player = new AnimationGraphPlayer(graph, skeleton);
		mGraphAnimInstances[slotIdx].Player = player;
		mGraphAnimInstances[slotIdx].Graph = graph;

		return player;
	}

	/// Creates an animation graph instance from a resource reference (deferred loading).
	public void CreateGraphAnimationFromRef(EntityId entity, ResourceRef skeletonRef, bool active = true)
	{
		if (mScene == null)
			return;

		int32 slotIdx;
		if (mFreeGraphAnimSlots.Count > 0)
		{
			slotIdx = mFreeGraphAnimSlots.PopBack();
		}
		else
		{
			slotIdx = (int32)mGraphAnimInstances.Count;
			mGraphAnimInstances.Add(.());
		}

		var instance = ref mGraphAnimInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		if (skeletonRef.IsValid)
			instance.SkeletonRef = ResourceRef(skeletonRef.Id, skeletonRef.Path);
		instance.GraphActive = active;
		instance.Active = true;

		mEntityToGraphAnim[entity] = slotIdx;

		var comp = mScene.GetComponent<AnimationGraphComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<AnimationGraphComponent>(entity, .());
			comp = mScene.GetComponent<AnimationGraphComponent>(entity);
		}
		comp.InternalHandle = slotIdx;
	}

	/// Gets the animation graph player for an entity.
	public AnimationGraphPlayer GetGraphPlayer(EntityId entity)
	{
		if (!mEntityToGraphAnim.TryGetValue(entity, let idx))
			return null;

		let instance = ref mGraphAnimInstances[idx];
		if (instance.Active)
			return instance.Player;

		return null;
	}

	/// Gets the skinning matrices produced by an entity's graph player.
	public Span<Matrix> GetGraphSkinningMatrices(EntityId entity)
	{
		if (!mEntityToGraphAnim.TryGetValue(entity, let idx))
			return .();

		let instance = ref mGraphAnimInstances[idx];
		if (instance.Active && instance.Player != null)
			return instance.Player.GetSkinningMatrices();

		return .();
	}

	/// Destroys graph animation data for an entity.
	public void DestroyGraphAnimation(EntityId entity)
	{
		if (!mEntityToGraphAnim.TryGetValue(entity, let idx))
			return;

		var instance = ref mGraphAnimInstances[idx];
		if (instance.Active)
		{
			instance.SkeletonRes.Release();
			instance.SkeletonRef.Dispose();
			if (instance.Player != null)
			{
				delete instance.Player;
				instance.Player = null;
			}
			instance.Active = false;
			mFreeGraphAnimSlots.Add(idx);
		}
		mEntityToGraphAnim.Remove(entity);

		if (mScene != null)
		{
			if (let comp = mScene.GetComponent<AnimationGraphComponent>(entity))
				comp.InternalHandle = -1;
		}
	}

	/// Resolves deserialized ResourceRef fields on animation graph instances.
	private void ResolveGraphResourceRefs()
	{
		let resourceSystem = mSubsystem.Context?.Resources;
		if (resourceSystem == null)
			return;

		for (var instance in ref mGraphAnimInstances)
		{
			if (!instance.Active)
				continue;

			// Resolve skeleton ref
			if (instance.SkeletonRef.IsValid)
			{
				bool needsLoad = !instance.SkeletonRes.IsValid;
				if (!needsLoad && instance.SkeletonRef.HasId && instance.SkeletonRes.Resource != null && instance.SkeletonRes.Resource.Id != instance.SkeletonRef.Id)
				{
					instance.SkeletonRes.Release();
					needsLoad = true;
				}
				if (needsLoad)
				{
					if (resourceSystem.LoadByRef<SkeletonResource>(instance.SkeletonRef) case .Ok(let handle))
						instance.SkeletonRes = handle;
				}
			}
		}
	}
}

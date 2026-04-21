namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Render;

/// Trail emitter instance storage and API.
extension RenderSceneModule
{
	// ==================== Trail Emitter Instance Storage ====================

	public struct TrailEmitterInstanceData
	{
		public EntityId Entity;
		public TrailEmitterRenderHandle RenderHandle = .Invalid;
		public bool Active;
	}

	private List<TrailEmitterInstanceData> mTrailEmitterInstances = new .() ~ delete _;
	private List<int32> mFreeTrailEmitterSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToTrailEmitterInstance = new .() ~ delete _;

	public List<TrailEmitterInstanceData> TrailEmitterInstances => mTrailEmitterInstances;

	// ==================== Trail Emitter API ====================

	/// Helper: allocates a trail emitter instance slot and sets up the thin component handle.
	private int32 AllocateTrailEmitterSlot(EntityId entity, TrailEmitterRenderHandle proxyHandle)
	{
		int32 slotIdx;
		if (mFreeTrailEmitterSlots.Count > 0)
			slotIdx = mFreeTrailEmitterSlots.PopBack();
		else
		{
			slotIdx = (int32)mTrailEmitterInstances.Count;
			mTrailEmitterInstances.Add(.());
		}

		var instance = ref mTrailEmitterInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.RenderHandle = proxyHandle;
		instance.Active = true;
		mEntityToTrailEmitterInstance[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<TrailEmitterComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<TrailEmitterComponent>(entity, .());
			comp = mScene.GetComponent<TrailEmitterComponent>(entity);
		}
		comp.InternalHandle = slotIdx;

		return slotIdx;
	}

	/// Creates a trail emitter for an entity.
	public TrailEmitterRenderHandle CreateTrailEmitter(EntityId entity, int32 maxPoints = 32)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let handle = mWorld.CreateTrailEmitter();
		AllocateTrailEmitterSlot(entity, handle);

		// Configure proxy (TrailEmitter instance is created lazily by ParticleFeature)
		if (let proxy = mWorld.GetTrailEmitter(handle))
		{
			proxy.MaxPoints = maxPoints;
			proxy.IsActive = true;
		}

		return handle;
	}

	/// Creates a trail emitter from serialized data. Used by the serializer.
	public void CreateTrailEmitterFromData(EntityId entity, TrailEmitterComponentData data)
	{
		if (mScene == null || mWorld == null)
			return;

		let handle = mWorld.CreateTrailEmitter();
		AllocateTrailEmitterSlot(entity, handle);

		// Configure proxy (TrailEmitter instance is created lazily by ParticleFeature)
		if (let proxy = mWorld.GetTrailEmitter(handle))
		{
			proxy.BlendMode = data.BlendMode;
			proxy.MaxPoints = data.MaxPoints;
			proxy.Lifetime = data.Lifetime;
			proxy.WidthStart = data.WidthStart;
			proxy.WidthEnd = data.WidthEnd;
			proxy.MinVertexDistance = data.MinVertexDistance;
			proxy.Color = data.Color;
			proxy.SoftParticleDistance = data.SoftParticleDistance;
			proxy.LayerMask = data.LayerMask;
			proxy.IsEnabled = data.Enabled;
			proxy.IsActive = true;
		}
	}

	/// Adds a trail point for the given entity's trail emitter.
	public void AddTrailPoint(EntityId entity, Vector3 position, float width, Color color)
	{
		if (mEntityToTrailEmitterInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mTrailEmitterInstances[idx];
			if (instance.Active && instance.RenderHandle.IsValid)
				mWorld?.AddTrailPoint(instance.RenderHandle, position, width, color);
		}
	}

	/// Adds a trail point with distance filtering for the given entity's trail emitter.
	public void AddTrailPointFiltered(EntityId entity, Vector3 position, float width, Color color, float minDistance)
	{
		if (mEntityToTrailEmitterInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mTrailEmitterInstances[idx];
			if (instance.Active && instance.RenderHandle.IsValid)
				mWorld?.AddTrailPointFiltered(instance.RenderHandle, position, width, color, minDistance);
		}
	}

	/// Gets the trail emitter proxy for direct access.
	public TrailEmitterProxy* GetTrailEmitterProxy(EntityId entity)
	{
		if (mEntityToTrailEmitterInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mTrailEmitterInstances[idx];
			if (instance.Active && instance.RenderHandle.IsValid)
				return mWorld?.GetTrailEmitter(instance.RenderHandle);
		}
		return null;
	}

	/// Destroys all trail emitter instances (bulk teardown for scene destroy).
	private void DestroyAllTrailEmitters()
	{
		for (var instance in ref mTrailEmitterInstances)
		{
			if (!instance.Active) continue;
			if (mWorld != null && instance.RenderHandle.IsValid)
				mWorld.DestroyTrailEmitter(instance.RenderHandle);
			instance.Active = false;
		}
		mTrailEmitterInstances.Clear();
		mFreeTrailEmitterSlots.Clear();
		mEntityToTrailEmitterInstance.Clear();
	}

	/// Syncs trail emitter transform from world matrix.
	/// Trail emitter position is updated by the trail system itself — this is a no-op for consistency.
	private void SyncTrailEmitterTransform(EntityId entity, in Matrix worldMatrix)
	{
	}

	/// Destroys the trail emitter for an entity.
	public void DestroyTrailEmitter(EntityId entity)
	{
		if (!mEntityToTrailEmitterInstance.TryGetValue(entity, var idx))
			return;

		var instance = ref mTrailEmitterInstances[idx];
		if (instance.Active)
		{
			if (instance.RenderHandle.IsValid)
				mWorld?.DestroyTrailEmitter(instance.RenderHandle);
			instance.Active = false;
			mFreeTrailEmitterSlots.Add(idx);
		}
		mEntityToTrailEmitterInstance.Remove(entity);

		// Clear handle on component
		if (mScene != null)
		{
			if (let comp = mScene.GetComponent<TrailEmitterComponent>(entity))
				comp.InternalHandle = -1;
		}
	}

	/// Returns whether the entity has a trail emitter component managed by this module.
	public bool HasTrailEmitter(EntityId entity)
	{
		return mEntityToTrailEmitterInstance.ContainsKey(entity);
	}
}

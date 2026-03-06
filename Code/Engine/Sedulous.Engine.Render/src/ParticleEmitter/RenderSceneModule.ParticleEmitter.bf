namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Render;

/// Particle emitter instance storage and API.
extension RenderSceneModule
{
	// ==================== Particle Emitter Instance Storage ====================

	public struct ParticleEmitterInstanceData
	{
		public EntityId Entity;
		public ParticleEmitterProxyHandle ProxyHandle = .Invalid;
		public bool Active;
	}

	private List<ParticleEmitterInstanceData> mParticleEmitterInstances = new .() ~ delete _;
	private List<int32> mFreeParticleEmitterSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToParticleEmitterInstance = new .() ~ delete _;

	public List<ParticleEmitterInstanceData> ParticleEmitterInstances => mParticleEmitterInstances;

	// ==================== Particle Emitter API ====================

	/// Helper: allocates a particle emitter instance slot and sets up the thin component handle.
	private int32 AllocateParticleEmitterSlot(EntityId entity, ParticleEmitterProxyHandle proxyHandle)
	{
		int32 slotIdx;
		if (mFreeParticleEmitterSlots.Count > 0)
			slotIdx = mFreeParticleEmitterSlots.PopBack();
		else
		{
			slotIdx = (int32)mParticleEmitterInstances.Count;
			mParticleEmitterInstances.Add(.());
		}

		var instance = ref mParticleEmitterInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.ProxyHandle = proxyHandle;
		instance.Active = true;
		mEntityToParticleEmitterInstance[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<ParticleEmitterComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<ParticleEmitterComponent>(entity, .());
			comp = mScene.GetComponent<ParticleEmitterComponent>(entity);
		}
		comp.InternalHandle = slotIdx;

		return slotIdx;
	}

	/// Creates a particle emitter for an entity (GPU backend).
	public ParticleEmitterProxyHandle CreateParticleEmitter(EntityId entity)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let handle = mWorld.CreateParticleEmitter(backend: .GPU);
		AllocateParticleEmitterSlot(entity, handle);

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetParticleEmitterPosition(handle, worldMatrix.Translation);

		return handle;
	}

	/// Gets the particle emitter proxy for direct access.
	public ParticleEmitterProxy* GetParticleEmitterProxy(EntityId entity)
	{
		if (mEntityToParticleEmitterInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mParticleEmitterInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				return mWorld?.GetParticleEmitter(instance.ProxyHandle);
		}
		return null;
	}

	/// Gets the particle emitter proxy handle for an entity.
	public ParticleEmitterProxyHandle GetParticleEmitterProxyHandle(EntityId entity)
	{
		if (mEntityToParticleEmitterInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mParticleEmitterInstances[idx];
			if (instance.Active)
				return instance.ProxyHandle;
		}
		return .Invalid;
	}

	/// Creates a CPU-simulated particle emitter for an entity.
	public ParticleEmitterProxyHandle CreateCPUParticleEmitter(EntityId entity, int32 maxParticles = 1000)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let handle = mWorld.CreateParticleEmitter(.CPU, maxParticles);
		AllocateParticleEmitterSlot(entity, handle);

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetParticleEmitterPosition(handle, worldMatrix.Translation);

		return handle;
	}

	/// Creates a particle emitter from serialized data. Used by the serializer.
	public void CreateParticleEmitterFromData(EntityId entity, ParticleEmitterComponentData data)
	{
		if (mScene == null || mWorld == null)
			return;

		ParticleEmitterProxyHandle handle;
		if (data.Backend == .CPU)
			handle = mWorld.CreateParticleEmitter(.CPU, (int32)data.MaxParticles);
		else
			handle = mWorld.CreateParticleEmitter(.GPU);

		AllocateParticleEmitterSlot(entity, handle);

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetParticleEmitterPosition(handle, worldMatrix.Translation);

		// Configure proxy with all data
		if (let proxy = mWorld.GetParticleEmitter(handle))
		{
			proxy.SimulationSpace = data.SimulationSpace;
			proxy.BlendMode = data.BlendMode;
			proxy.RenderMode = data.RenderMode;
			proxy.MaxParticles = data.MaxParticles;
			proxy.SpawnRate = data.SpawnRate;
			proxy.ParticleLifetime = data.ParticleLifetime;
			proxy.BurstCount = data.BurstCount;
			proxy.BurstInterval = data.BurstInterval;
			proxy.BurstCycles = data.BurstCycles;
			proxy.StartSize = data.StartSize;
			proxy.EndSize = data.EndSize;
			proxy.StartColor = data.StartColor;
			proxy.EndColor = data.EndColor;
			proxy.InitialVelocity = data.InitialVelocity;
			proxy.VelocityRandomness = data.VelocityRandomness;
			proxy.GravityMultiplier = data.GravityMultiplier;
			proxy.Drag = data.Drag;
			proxy.VelocityInheritance = data.VelocityInheritance;
			proxy.SoftParticleDistance = data.SoftParticleDistance;
			proxy.StretchFactor = data.StretchFactor;
			proxy.SortParticles = data.SortParticles;
			proxy.Lit = data.Lit;
			proxy.AtlasColumns = data.AtlasColumns;
			proxy.AtlasRows = data.AtlasRows;
			proxy.AtlasFPS = data.AtlasFPS;
			proxy.AtlasLoop = data.AtlasLoop;
			proxy.SizeOverLifetime = data.SizeOverLifetime;
			proxy.ColorOverLifetime = data.ColorOverLifetime;
			proxy.SpeedOverLifetime = data.SpeedOverLifetime;
			proxy.AlphaOverLifetime = data.AlphaOverLifetime;
			proxy.RotationSpeedOverLifetime = data.RotationSpeedOverLifetime;
			proxy.ForceModules = data.ForceModules;
			proxy.LODStartDistance = data.LODStartDistance;
			proxy.LODCullDistance = data.LODCullDistance;
			proxy.LODMinRateMultiplier = data.LODMinRateMultiplier;
			proxy.LifetimeVarianceMin = data.LifetimeVarianceMin;
			proxy.LifetimeVarianceMax = data.LifetimeVarianceMax;
			proxy.Trail = data.Trail;
			proxy.Shape = data.Shape;
			proxy.SubEmitterOnly = data.SubEmitterOnly;
			proxy.LayerMask = data.LayerMask;
			proxy.IsEnabled = data.Enabled;
		}
	}

	/// Destroys all particle emitter instances (bulk teardown for scene destroy).
	private void DestroyAllParticleEmitters()
	{
		for (var instance in ref mParticleEmitterInstances)
		{
			if (!instance.Active) continue;
			if (mWorld != null && instance.ProxyHandle.IsValid)
				mWorld.DestroyParticleEmitter(instance.ProxyHandle);
			instance.Active = false;
		}
		mParticleEmitterInstances.Clear();
		mFreeParticleEmitterSlots.Clear();
		mEntityToParticleEmitterInstance.Clear();
	}

	/// Syncs particle emitter proxy transform from world matrix.
	private void SyncParticleEmitterTransform(EntityId entity, in Matrix worldMatrix)
	{
		if (mEntityToParticleEmitterInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mParticleEmitterInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				mWorld?.SetParticleEmitterPosition(instance.ProxyHandle, worldMatrix.Translation);
		}
	}

	/// Destroys the particle emitter for an entity.
	public void DestroyParticleEmitter(EntityId entity)
	{
		if (!mEntityToParticleEmitterInstance.TryGetValue(entity, var idx))
			return;

		var instance = ref mParticleEmitterInstances[idx];
		if (instance.Active)
		{
			if (instance.ProxyHandle.IsValid)
				mWorld?.DestroyParticleEmitter(instance.ProxyHandle);
			instance.Active = false;
			mFreeParticleEmitterSlots.Add(idx);
		}
		mEntityToParticleEmitterInstance.Remove(entity);

		// Clear handle on component
		if (mScene != null)
		{
			if (let comp = mScene.GetComponent<ParticleEmitterComponent>(entity))
				comp.InternalHandle = -1;
		}
	}

	/// Returns whether the entity has a particle emitter component managed by this module.
	public bool HasParticleEmitter(EntityId entity)
	{
		return mEntityToParticleEmitterInstance.ContainsKey(entity);
	}

	/// Duplicates the particle emitter from src entity to dst entity.
	/// Note: Particle emitter duplication is complex and not yet implemented.
	public void DuplicateParticleEmitter(EntityId src, EntityId dst)
	{
		// TODO: Particle emitter duplication is complex — skip for now.
	}
}

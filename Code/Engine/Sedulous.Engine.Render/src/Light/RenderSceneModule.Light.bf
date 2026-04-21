namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Render;

/// Light instance storage and API.
extension RenderSceneModule
{
	// ==================== Light Instance Storage ====================

	public struct LightInstanceData
	{
		public EntityId Entity;
		public LightRenderHandle RenderHandle = .Invalid;
		public bool Active;
	}

	private List<LightInstanceData> mLightInstances = new .() ~ delete _;
	private List<int32> mFreeLightSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToLightInstance = new .() ~ delete _;

	public List<LightInstanceData> LightInstances => mLightInstances;

	// ==================== Light API ====================

	/// Helper: allocates a light instance slot and sets up the thin component handle.
	private int32 AllocateLightSlot(EntityId entity, LightRenderHandle proxyHandle)
	{
		int32 slotIdx;
		if (mFreeLightSlots.Count > 0)
			slotIdx = mFreeLightSlots.PopBack();
		else
		{
			slotIdx = (int32)mLightInstances.Count;
			mLightInstances.Add(.());
		}

		var instance = ref mLightInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.RenderHandle = proxyHandle;
		instance.Active = true;
		mEntityToLightInstance[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<LightComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<LightComponent>(entity, .());
			comp = mScene.GetComponent<LightComponent>(entity);
		}
		comp.InternalHandle = slotIdx;

		return slotIdx;
	}

	/// Creates a directional light for an entity.
	public LightRenderHandle CreateDirectionalLight(EntityId entity, Vector3 color, float intensity)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		let direction = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));

		let handle = mWorld.CreateDirectionalLight(direction, color, intensity);
		AllocateLightSlot(entity, handle);

		return handle;
	}

	/// Creates a point light for an entity.
	public LightRenderHandle CreatePointLight(EntityId entity, Vector3 color, float intensity, float range)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		let position = worldMatrix.Translation;

		let handle = mWorld.CreatePointLight(position, color, intensity, range);
		AllocateLightSlot(entity, handle);

		return handle;
	}

	/// Creates a spot light for an entity.
	public LightRenderHandle CreateSpotLight(EntityId entity, Vector3 color, float intensity, float range, float innerAngle, float outerAngle)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let worldMatrix = mScene.GetWorldMatrix(entity);
		let position = worldMatrix.Translation;
		let direction = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));

		let handle = mWorld.CreateSpotLight(position, direction, color, intensity, range, innerAngle, outerAngle);
		AllocateLightSlot(entity, handle);

		return handle;
	}

	/// Sets light color and intensity.
	public void SetLightColor(EntityId entity, Vector3 color, float intensity)
	{
		if (mEntityToLightInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mLightInstances[idx];
			if (instance.Active && instance.RenderHandle.IsValid)
				mWorld?.SetLightColor(instance.RenderHandle, color, intensity);
		}
	}

	/// Enables or disables a light.
	public void SetLightEnabled(EntityId entity, bool enabled)
	{
		if (mEntityToLightInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mLightInstances[idx];
			if (instance.Active && instance.RenderHandle.IsValid)
				mWorld?.SetLightEnabled(instance.RenderHandle, enabled);
		}
	}

	/// Gets the light proxy for direct access.
	public LightProxy* GetLightProxy(EntityId entity)
	{
		if (mEntityToLightInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mLightInstances[idx];
			if (instance.Active && instance.RenderHandle.IsValid)
				return mWorld?.GetLight(instance.RenderHandle);
		}
		return null;
	}

	/// Returns whether the entity has a light component managed by this module.
	public bool HasLight(EntityId entity)
	{
		return mEntityToLightInstance.ContainsKey(entity);
	}

	/// Destroys all light instances (bulk teardown for scene destroy).
	private void DestroyAllLights()
	{
		for (var instance in ref mLightInstances)
		{
			if (!instance.Active) continue;
			if (mWorld != null && instance.RenderHandle.IsValid)
				mWorld.DestroyLight(instance.RenderHandle);
			instance.Active = false;
		}
		mLightInstances.Clear();
		mFreeLightSlots.Clear();
		mEntityToLightInstance.Clear();
	}

	/// Syncs light proxy transform from world matrix.
	private void SyncLightTransform(EntityId entity, in Matrix worldMatrix)
	{
		if (mEntityToLightInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mLightInstances[idx];
			if (instance.Active && instance.RenderHandle.IsValid)
			{
				if (let proxy = mWorld?.GetLight(instance.RenderHandle))
				{
					proxy.Position = worldMatrix.Translation;
					proxy.Direction = Vector3.Normalize(.(worldMatrix.M31, worldMatrix.M32, worldMatrix.M33));
				}
			}
		}
	}

	/// Destroys the light for an entity.
	public void DestroyLight(EntityId entity)
	{
		if (!mEntityToLightInstance.TryGetValue(entity, var idx))
			return;

		var instance = ref mLightInstances[idx];
		if (instance.Active)
		{
			if (instance.RenderHandle.IsValid && mWorld != null)
				mWorld.DestroyLight(instance.RenderHandle);
			instance.Active = false;
			mFreeLightSlots.Add(idx);
		}
		mEntityToLightInstance.Remove(entity);

		if (var comp = mScene?.GetComponent<LightComponent>(entity))
			comp.InternalHandle = -1;
	}

	/// Duplicates the light from src entity to dst entity.
	public void DuplicateLight(EntityId src, EntityId dst)
	{
		let proxy = GetLightProxy(src);
		if (proxy == null)
			return;

		switch (proxy.Type)
		{
		case .Directional:
			CreateDirectionalLight(dst, proxy.Color, proxy.Intensity);
		case .Point:
			CreatePointLight(dst, proxy.Color, proxy.Intensity, proxy.Range);
		case .Spot:
			CreateSpotLight(dst, proxy.Color, proxy.Intensity, proxy.Range, proxy.InnerConeAngle, proxy.OuterConeAngle);
		default:
			return;
		}

		if (let dstProxy = GetLightProxy(dst))
		{
			dstProxy.CastsShadows = proxy.CastsShadows;
			dstProxy.IsEnabled = proxy.IsEnabled;
		}
	}
}

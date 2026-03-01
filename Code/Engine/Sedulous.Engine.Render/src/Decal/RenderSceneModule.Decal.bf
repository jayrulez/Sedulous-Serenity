namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.RHI;
using Sedulous.Textures.Resources;
using Sedulous.Imaging;

/// Decal instance storage and API.
extension RenderSceneModule
{
	// ==================== Decal Instance Storage ====================

	public struct DecalInstanceData
	{
		public EntityId Entity;
		public DecalProxyHandle ProxyHandle = .Invalid;
		public ResourceRef TextureRef;
		public ResourceHandle<TextureResource> TextureRes;
		public TextureResource BoundTextureResource;
		public bool Active;
	}

	private List<DecalInstanceData> mDecalInstances = new .() ~ delete _;
	private List<int32> mFreeDecalSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToDecalInstance = new .() ~ delete _;

	public List<DecalInstanceData> DecalInstances => mDecalInstances;

	// ==================== Decal API ====================

	/// Helper: allocates a decal instance slot and sets up the thin component handle.
	private int32 AllocateDecalSlot(EntityId entity, DecalProxyHandle proxyHandle)
	{
		int32 slotIdx;
		if (mFreeDecalSlots.Count > 0)
			slotIdx = mFreeDecalSlots.PopBack();
		else
		{
			slotIdx = (int32)mDecalInstances.Count;
			mDecalInstances.Add(.());
		}

		var instance = ref mDecalInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.ProxyHandle = proxyHandle;
		instance.Active = true;
		mEntityToDecalInstance[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<DecalComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<DecalComponent>(entity, .());
			comp = mScene.GetComponent<DecalComponent>(entity);
		}
		comp.InternalHandle = slotIdx;

		return slotIdx;
	}

	/// Creates a decal for an entity.
	public DecalProxyHandle CreateDecal(EntityId entity)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let handle = mWorld.CreateDecal();
		AllocateDecalSlot(entity, handle);

		let worldMatrix = mScene.GetWorldMatrix(entity);
		Vector3 entityScale;
		Quaternion entityRotation;
		Vector3 entityPosition;
		worldMatrix.Decompose(out entityScale, out entityRotation, out entityPosition);
		mWorld.SetDecalTransform(handle, entityPosition, entityRotation, .(1, 1, 1));

		return handle;
	}

	/// Creates a decal from serialized data. Used by the serializer.
	public void CreateDecalFromData(EntityId entity, DecalComponentData data)
	{
		if (mScene == null || mWorld == null)
			return;

		let handle = mWorld.CreateDecal();
		let slotIdx = AllocateDecalSlot(entity, handle);

		// Store texture ref for deferred resolution
		var instance = ref mDecalInstances[slotIdx];
		if (data.TextureRef.IsValid)
			instance.TextureRef = ResourceRef(data.TextureRef.Id, data.TextureRef.Path);

		// Configure proxy
		if (let proxy = mWorld.GetDecal(handle))
		{
			proxy.Scale = data.Scale;
			proxy.Color = data.Color;
			proxy.AngleFadeStart = data.AngleFadeStart;
			proxy.AngleFadeEnd = data.AngleFadeEnd;
			proxy.SortOrder = data.SortOrder;
			proxy.BlendMode = data.BlendMode;
			proxy.IsActive = data.Enabled;
		}

		let worldMatrix = mScene.GetWorldMatrix(entity);
		Vector3 entityScale;
		Quaternion entityRotation;
		Vector3 entityPosition;
		worldMatrix.Decompose(out entityScale, out entityRotation, out entityPosition);
		mWorld.SetDecalTransform(handle, entityPosition, entityRotation, data.Scale);
	}

	/// Gets the decal proxy for direct access.
	public DecalProxy* GetDecalProxy(EntityId entity)
	{
		if (mEntityToDecalInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mDecalInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				return mWorld?.GetDecal(instance.ProxyHandle);
		}
		return null;
	}

	/// Sets decal texture via resource handle. Resolves in next PostUpdate.
	public void SetDecalTextureResource(EntityId entity, ResourceHandle<TextureResource> texture)
	{
		if (mEntityToDecalInstance.TryGetValue(entity, let idx))
		{
			var instance = ref mDecalInstances[idx];
			if (instance.Active)
			{
				instance.TextureRes.Release();
				instance.TextureRes = texture;
				instance.BoundTextureResource = null; // Force re-upload
			}
		}
	}

	/// Sets decal blend mode.
	public void SetDecalBlendMode(EntityId entity, DecalBlendMode mode)
	{
		if (mEntityToDecalInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mDecalInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				mWorld.SetDecalBlendMode(instance.ProxyHandle, mode);
		}
	}

	/// Sets decal color.
	public void SetDecalColor(EntityId entity, Vector4 color)
	{
		if (mEntityToDecalInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mDecalInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
			{
				if (let proxy = mWorld.GetDecal(instance.ProxyHandle))
					proxy.Color = color;
			}
		}
	}

	/// Returns whether the entity has a decal component managed by this module.
	public bool HasDecal(EntityId entity)
	{
		return mEntityToDecalInstance.ContainsKey(entity);
	}

	/// Destroys all decal instances (bulk teardown for scene destroy).
	private void DestroyAllDecals()
	{
		for (var instance in ref mDecalInstances)
		{
			if (!instance.Active) continue;
			instance.TextureRef.Dispose();
			instance.TextureRes.Release();
			if (mWorld != null && instance.ProxyHandle.IsValid)
				mWorld.DestroyDecal(instance.ProxyHandle);
			instance.Active = false;
		}
		mDecalInstances.Clear();
		mFreeDecalSlots.Clear();
		mEntityToDecalInstance.Clear();
	}

	/// Syncs decal proxy transform from world matrix.
	private void SyncDecalTransform(EntityId entity, in Matrix worldMatrix)
	{
		if (mEntityToDecalInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mDecalInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
			{
				Vector3 entityScale;
				Quaternion entityRotation;
				Vector3 entityPosition;
				worldMatrix.Decompose(out entityScale, out entityRotation, out entityPosition);
				if (let proxy = mWorld?.GetDecal(instance.ProxyHandle))
					mWorld.SetDecalTransform(instance.ProxyHandle, entityPosition, entityRotation, proxy.Scale);
			}
		}
	}

	/// Destroys the decal for an entity.
	public void DestroyDecal(EntityId entity)
	{
		if (!mEntityToDecalInstance.TryGetValue(entity, var idx))
			return;

		var instance = ref mDecalInstances[idx];
		if (instance.Active)
		{
			instance.TextureRef.Dispose();
			instance.TextureRes.Release();
			if (instance.ProxyHandle.IsValid && mWorld != null)
				mWorld.DestroyDecal(instance.ProxyHandle);
			instance.Active = false;
			mFreeDecalSlots.Add(idx);
		}
		mEntityToDecalInstance.Remove(entity);

		if (var comp = mScene?.GetComponent<DecalComponent>(entity))
			comp.InternalHandle = -1;
	}

	/// Resolves pending texture refs on module-owned decal instances.
	private void ResolveDecalInstanceRefs()
	{
		let resourceSystem = mSubsystem.Context?.Resources;
		if (resourceSystem == null)
			return;

		for (var instance in ref mDecalInstances)
		{
			if (!instance.Active)
				continue;

			// Resolve texture ref → resource handle (only for serialized refs)
			if (instance.TextureRef.IsValid)
			{
				bool needsLoad = !instance.TextureRes.IsValid;
				if (!needsLoad && instance.TextureRef.HasId && instance.TextureRes.Resource != null && instance.TextureRes.Resource.Id != instance.TextureRef.Id)
				{
					instance.TextureRes.Release();
					needsLoad = true;
				}
				if (needsLoad)
				{
					if (resourceSystem.LoadByRef<TextureResource>(instance.TextureRef) case .Ok(let handle))
						instance.TextureRes = handle;
				}
			}

			// Upload texture to GPU if resource changed
			let texResource = instance.TextureRes.Resource;
			if (texResource != instance.BoundTextureResource)
			{
				if (texResource != null && texResource.Image != null)
				{
					ITextureView view = null;
					let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
					if (gpuManager != null)
					{
						if (mTextureCache.TryGetValue(texResource, var gpuHandle))
						{
							view = gpuManager.GetTextureView(gpuHandle);
						}
						else
						{
							let image = texResource.Image;
							let texData = TextureData.FromImage(image);
							if (gpuManager.UploadTexture(texData) case .Ok(let newHandle))
							{
								mTextureCache[texResource] = newHandle;
								view = gpuManager.GetTextureView(newHandle);
							}
						}
					}
					if (view != null && instance.ProxyHandle.IsValid)
						mWorld.SetDecalTexture(instance.ProxyHandle, view);
					instance.BoundTextureResource = texResource;
				}
				else if (texResource == null && instance.BoundTextureResource != null)
				{
					instance.BoundTextureResource = null;
				}
			}
		}
	}
}

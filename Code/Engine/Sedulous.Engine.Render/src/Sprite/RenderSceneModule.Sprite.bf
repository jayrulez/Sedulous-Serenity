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

/// Sprite instance storage and API.
extension RenderSceneModule
{
	// ==================== Sprite Instance Storage ====================

	public struct SpriteInstanceData
	{
		public EntityId Entity;
		public SpriteProxyHandle ProxyHandle = .Invalid;
		public ResourceRef TextureRef;
		public ResourceHandle<TextureResource> TextureRes;
		public TextureResource BoundTextureResource;
		public bool Active;
	}

	private List<SpriteInstanceData> mSpriteInstances = new .() ~ delete _;
	private List<int32> mFreeSpriteSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToSpriteInstance = new .() ~ delete _;

	public List<SpriteInstanceData> SpriteInstances => mSpriteInstances;

	// ==================== Sprite API ====================

	/// Helper: allocates a sprite instance slot and sets up the thin component handle.
	private int32 AllocateSpriteSlot(EntityId entity, SpriteProxyHandle proxyHandle)
	{
		int32 slotIdx;
		if (mFreeSpriteSlots.Count > 0)
			slotIdx = mFreeSpriteSlots.PopBack();
		else
		{
			slotIdx = (int32)mSpriteInstances.Count;
			mSpriteInstances.Add(.());
		}

		var instance = ref mSpriteInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.ProxyHandle = proxyHandle;
		instance.Active = true;
		mEntityToSpriteInstance[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<SpriteComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<SpriteComponent>(entity, .());
			comp = mScene.GetComponent<SpriteComponent>(entity);
		}
		comp.InternalHandle = slotIdx;

		return slotIdx;
	}

	/// Creates a sprite for an entity.
	public SpriteProxyHandle CreateSprite(EntityId entity)
	{
		if (mScene == null || mWorld == null)
			return .Invalid;

		let handle = mWorld.CreateSprite();
		AllocateSpriteSlot(entity, handle);

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetSpritePosition(handle, worldMatrix.Translation);

		return handle;
	}

	/// Creates a sprite from serialized data. Used by the serializer.
	public void CreateSpriteFromData(EntityId entity, SpriteComponentData data)
	{
		if (mScene == null || mWorld == null)
			return;

		let handle = mWorld.CreateSprite();
		let slotIdx = AllocateSpriteSlot(entity, handle);

		// Store texture ref for deferred resolution
		var instance = ref mSpriteInstances[slotIdx];
		if (data.TextureRef.IsValid)
			instance.TextureRef = ResourceRef(data.TextureRef.Id, data.TextureRef.Path);

		// Configure proxy
		if (let proxy = mWorld.GetSprite(handle))
		{
			proxy.Size = data.Size;
			proxy.Color = .(data.Color.X, data.Color.Y, data.Color.Z, data.Color.W);
			proxy.UVRect = data.UVRect;
			proxy.LayerMask = data.LayerMask;
			proxy.IsActive = data.Enabled;
		}

		let worldMatrix = mScene.GetWorldMatrix(entity);
		mWorld.SetSpritePosition(handle, worldMatrix.Translation);
	}

	/// Gets the sprite proxy for direct access.
	public SpriteProxy* GetSpriteProxy(EntityId entity)
	{
		if (mEntityToSpriteInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mSpriteInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				return mWorld?.GetSprite(instance.ProxyHandle);
		}
		return null;
	}

	/// Sets sprite size.
	public void SetSpriteSize(EntityId entity, Vector2 size)
	{
		if (mEntityToSpriteInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mSpriteInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				mWorld.SetSpriteSize(instance.ProxyHandle, size);
		}
	}

	/// Sets sprite color.
	public void SetSpriteColor(EntityId entity, Color color)
	{
		if (mEntityToSpriteInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mSpriteInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				mWorld.SetSpriteColor(instance.ProxyHandle, color);
		}
	}

	/// Sets sprite texture.
	public void SetSpriteTexture(EntityId entity, ITextureView texture)
	{
		if (mEntityToSpriteInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mSpriteInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				mWorld.SetSpriteTexture(instance.ProxyHandle, texture);
		}
	}

	/// Sets sprite texture via resource handle. Resolves in next PostUpdate.
	public void SetSpriteTextureResource(EntityId entity, ResourceHandle<TextureResource> texture)
	{
		if (mEntityToSpriteInstance.TryGetValue(entity, let idx))
		{
			var instance = ref mSpriteInstances[idx];
			if (instance.Active)
			{
				instance.TextureRes.Release();
				instance.TextureRes = texture;
				instance.BoundTextureResource = null; // Force re-upload
			}
		}
	}

	/// Returns whether the entity has a sprite component managed by this module.
	public bool HasSprite(EntityId entity)
	{
		return mEntityToSpriteInstance.ContainsKey(entity);
	}

	/// Destroys all sprite instances (bulk teardown for scene destroy).
	private void DestroyAllSprites()
	{
		for (var instance in ref mSpriteInstances)
		{
			if (!instance.Active) continue;
			instance.TextureRef.Dispose();
			instance.TextureRes.Release();
			if (mWorld != null && instance.ProxyHandle.IsValid)
				mWorld.DestroySprite(instance.ProxyHandle);
			instance.Active = false;
		}
		mSpriteInstances.Clear();
		mFreeSpriteSlots.Clear();
		mEntityToSpriteInstance.Clear();
	}

	/// Syncs sprite proxy transform from world matrix.
	private void SyncSpriteTransform(EntityId entity, in Matrix worldMatrix)
	{
		if (mEntityToSpriteInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mSpriteInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				mWorld?.SetSpritePosition(instance.ProxyHandle, worldMatrix.Translation);
		}
	}

	/// Destroys the sprite for an entity.
	public void DestroySprite(EntityId entity)
	{
		if (!mEntityToSpriteInstance.TryGetValue(entity, var idx))
			return;

		var instance = ref mSpriteInstances[idx];
		if (instance.Active)
		{
			instance.TextureRef.Dispose();
			instance.TextureRes.Release();
			if (instance.ProxyHandle.IsValid && mWorld != null)
				mWorld.DestroySprite(instance.ProxyHandle);
			instance.Active = false;
			mFreeSpriteSlots.Add(idx);
		}
		mEntityToSpriteInstance.Remove(entity);

		if (var comp = mScene?.GetComponent<SpriteComponent>(entity))
			comp.InternalHandle = -1;
	}

	/// Duplicates the sprite from src entity to dst entity.
	public void DuplicateSprite(EntityId src, EntityId dst)
	{
		if (!mEntityToSpriteInstance.TryGetValue(src, var srcIdx))
			return;

		let srcInstance = ref mSpriteInstances[srcIdx];
		if (!srcInstance.Active)
			return;

		// Create sprite on dst
		let handle = CreateSprite(dst);
		if (!handle.IsValid)
			return;

		// Copy texture ref for deferred resolution
		if (!mEntityToSpriteInstance.TryGetValue(dst, var dstIdx))
			return;

		var dstInstance = ref mSpriteInstances[dstIdx];
		if (srcInstance.TextureRef.IsValid)
			dstInstance.TextureRef = ResourceRef(srcInstance.TextureRef.Id, srcInstance.TextureRef.Path);

		// Copy proxy properties
		let srcProxy = mWorld?.GetSprite(srcInstance.ProxyHandle);
		let dstProxy = mWorld?.GetSprite(dstInstance.ProxyHandle);
		if (srcProxy != null && dstProxy != null)
		{
			dstProxy.Size = srcProxy.Size;
			dstProxy.Color = srcProxy.Color;
			dstProxy.UVRect = srcProxy.UVRect;
			dstProxy.LayerMask = srcProxy.LayerMask;
			dstProxy.IsActive = srcProxy.IsActive;
		}
	}

	/// Resolves pending texture refs on module-owned sprite instances.
	private void ResolveSpriteInstanceRefs()
	{
		let resourceSystem = mSubsystem.Context?.Resources;
		if (resourceSystem == null)
			return;

		for (var instance in ref mSpriteInstances)
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
						mWorld.SetSpriteTexture(instance.ProxyHandle, view);
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

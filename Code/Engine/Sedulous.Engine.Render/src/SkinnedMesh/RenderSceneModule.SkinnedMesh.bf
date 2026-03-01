namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Engine.Animation;
using Sedulous.Engine.Scenes;
using Sedulous.Geometry.Resources;
using Sedulous.Core.Mathematics;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.Materials.Resources;
using Sedulous.Materials;
using Sedulous.RHI;

/// Skinned mesh instance storage and API.
extension RenderSceneModule
{
	// ==================== Skinned Mesh Instance Storage ====================

	/// Internal data for a skinned mesh instance, owned by this module.
	public struct SkinnedMeshInstanceData
	{
		public EntityId Entity;
		public SkinnedMeshProxyHandle ProxyHandle = .Invalid;
		public ResourceHandle<SkinnedMeshResource> MeshRes;
		public ResourceRef MeshRef;
		public ResourceRefArray<const RenderConfig.MaxMaterialsPerMesh> MaterialRefs;
		public ResourceHandle<MaterialResource>[RenderConfig.MaxMaterialsPerMesh] Materials;
		public MaterialInstance[RenderConfig.MaxMaterialsPerMesh] MaterialInstances;
		public SkinnedMeshResource BoundMeshResource; // Track which resource is currently bound to proxy
		public bool Enabled;
		public bool Active; // Slot in use
	}

	private List<SkinnedMeshInstanceData> mSkinnedMeshInstances = new .() ~ delete _;
	private List<int32> mFreeSkinnedMeshSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToSkinnedMeshInstance = new .() ~ delete _;

	// Cache: resource -> GPU handle (shared across entities using same skinned mesh resource)
	private Dictionary<SkinnedMeshResource, GPUMeshHandle> mSkinnedMeshCache = new .() ~ delete _;

	/// Provides read access to skinned mesh instances for serialization.
	public List<SkinnedMeshInstanceData> SkinnedMeshInstances => mSkinnedMeshInstances;

	// ==================== Skinned Mesh API ====================

	/// Creates a skinned mesh for an entity from a resource reference (deferred loading).
	/// The resource will be resolved in the next PostUpdate frame.
	public void CreateSkinnedMeshFromRef(EntityId entity, ResourceRef meshRef, bool enabled = true)
	{
		if (mScene == null || mWorld == null)
			return;

		// Allocate a slot
		int32 slotIdx;
		if (mFreeSkinnedMeshSlots.Count > 0)
		{
			slotIdx = mFreeSkinnedMeshSlots.PopBack();
		}
		else
		{
			slotIdx = (int32)mSkinnedMeshInstances.Count;
			mSkinnedMeshInstances.Add(.());
		}

		var instance = ref mSkinnedMeshInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		if (meshRef.IsValid)
			instance.MeshRef = ResourceRef(meshRef.Id, meshRef.Path);
		instance.Enabled = enabled;
		instance.Active = true;

		mEntityToSkinnedMeshInstance[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<SkinnedMeshComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<SkinnedMeshComponent>(entity, .());
			comp = mScene.GetComponent<SkinnedMeshComponent>(entity);
		}
		comp.InternalHandle = slotIdx;
	}

	/// Sets a material on a skinned mesh slot by resource reference (deferred loading).
	public void SetSkinnedMeshMaterialRef(EntityId entity, int32 slot, ResourceRef materialRef)
	{
		if (!mEntityToSkinnedMeshInstance.TryGetValue(entity, let idx))
			return;

		var instance = ref mSkinnedMeshInstances[idx];
		if (!instance.Active || slot < 0 || slot >= RenderConfig.MaxMaterialsPerMesh)
			return;

		// Release old ref
		instance.MaterialRefs[slot].Dispose();
		// Release old loaded resources
		instance.Materials[slot].Release();
		if (instance.MaterialInstances[slot] != null)
		{
			instance.MaterialInstances[slot].ReleaseRef();
			instance.MaterialInstances[slot] = null;
		}

		// Set new ref (will be resolved in ResolveSkinnedMeshInstanceRefs)
		if (materialRef.IsValid)
			instance.MaterialRefs[slot] = ResourceRef(materialRef.Id, materialRef.Path);

		// Ensure MaterialRefs.Count covers this slot
		if (slot >= instance.MaterialRefs.Count)
			instance.MaterialRefs.Count = slot + 1;
	}

	/// Sets a material on a skinned mesh slot by MaterialInstance.
	/// The module takes ownership of the ref (calls AddRef internally).
	public void SetSkinnedMeshMaterial(EntityId entity, int32 slot, MaterialInstance material)
	{
		if (!mEntityToSkinnedMeshInstance.TryGetValue(entity, let idx))
			return;

		var instance = ref mSkinnedMeshInstances[idx];
		if (!instance.Active || slot < 0 || slot >= RenderConfig.MaxMaterialsPerMesh)
			return;

		// Release old
		if (instance.MaterialInstances[slot] != null)
		{
			instance.MaterialInstances[slot].ReleaseRef();
			instance.MaterialInstances[slot] = null;
		}

		// Set new
		if (material != null)
		{
			material.AddRef();
			instance.MaterialInstances[slot] = material;
		}

		// Ensure MaterialRefs.Count covers this slot
		if (slot >= instance.MaterialRefs.Count)
			instance.MaterialRefs.Count = slot + 1;
	}

	/// Gets the skinned mesh proxy for an entity (for advanced read-only access).
	public SkinnedMeshProxy* GetSkinnedMeshProxy(EntityId entity)
	{
		if (mEntityToSkinnedMeshInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mSkinnedMeshInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				return mWorld?.GetSkinnedMesh(instance.ProxyHandle);
		}
		return null;
	}

	/// Gets the bound skinned mesh resource for an entity.
	public SkinnedMeshResource GetSkinnedMeshResource(EntityId entity)
	{
		if (mEntityToSkinnedMeshInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mSkinnedMeshInstances[idx];
			if (instance.Active)
				return instance.MeshRes.Resource;
		}
		return null;
	}

	/// Destroys all skinned mesh instances (bulk teardown for scene destroy).
	private void DestroyAllSkinnedMeshes()
	{
		for (var instance in ref mSkinnedMeshInstances)
		{
			if (!instance.Active)
				continue;
			instance.MeshRes.Release();
			instance.MeshRef.Dispose();
			for (int32 i = 0; i < instance.MaterialRefs.Count; i++)
			{
				instance.Materials[i].Release();
				instance.MaterialRefs[i].Dispose();
				if (instance.MaterialInstances[i] != null)
				{
					instance.MaterialInstances[i].ReleaseRef();
					instance.MaterialInstances[i] = null;
				}
			}
			if (mWorld != null && instance.ProxyHandle.IsValid)
			{
				if (let proxy = mWorld.GetSkinnedMesh(instance.ProxyHandle))
				{
					if (proxy.BoneBufferHandle.IsValid)
					{
						let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
						let frameNumber = mSubsystem.RenderSystem?.FrameNumber ?? 0;
						gpuManager?.ReleaseBoneBuffer(proxy.BoneBufferHandle, frameNumber);
					}
				}
				mWorld.DestroySkinnedMesh(instance.ProxyHandle);
			}
			instance.Active = false;
		}
		mSkinnedMeshInstances.Clear();
		mFreeSkinnedMeshSlots.Clear();
		mEntityToSkinnedMeshInstance.Clear();

		// Release cached GPU meshes
		let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
		let frameNumber = mSubsystem.RenderSystem?.FrameNumber ?? 0;
		if (gpuManager != null)
		{
			for (let handle in mSkinnedMeshCache.Values)
				gpuManager.ReleaseMesh(handle, frameNumber);
		}
		mSkinnedMeshCache.Clear();
	}

	/// Syncs skinned mesh proxy transform from world matrix.
	private void SyncSkinnedMeshTransform(EntityId entity, in Matrix worldMatrix)
	{
		if (mEntityToSkinnedMeshInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mSkinnedMeshInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				mWorld?.SetSkinnedMeshTransform(instance.ProxyHandle, worldMatrix);
		}
	}

	/// Destroys a skinned mesh instance for an entity.
	public void DestroySkinnedMesh(EntityId entity)
	{
		if (!mEntityToSkinnedMeshInstance.TryGetValue(entity, let idx))
			return;

		var instance = ref mSkinnedMeshInstances[idx];
		if (instance.Active)
		{
			instance.MeshRes.Release();
			instance.MeshRef.Dispose();
			for (int32 i = 0; i < instance.MaterialRefs.Count; i++)
			{
				instance.Materials[i].Release();
				instance.MaterialRefs[i].Dispose();
				if (instance.MaterialInstances[i] != null)
				{
					instance.MaterialInstances[i].ReleaseRef();
					instance.MaterialInstances[i] = null;
				}
			}
			// Release bone buffer
			if (instance.ProxyHandle.IsValid)
			{
				if (let proxy = mWorld?.GetSkinnedMesh(instance.ProxyHandle))
				{
					if (proxy.BoneBufferHandle.IsValid)
					{
						let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
						let frameNumber = mSubsystem.RenderSystem?.FrameNumber ?? 0;
						gpuManager?.ReleaseBoneBuffer(proxy.BoneBufferHandle, frameNumber);
					}
				}
				mWorld.DestroySkinnedMesh(instance.ProxyHandle);
			}
			instance.Active = false;
			mFreeSkinnedMeshSlots.Add(idx);
		}
		mEntityToSkinnedMeshInstance.Remove(entity);

		// Clear handle on component
		if (mScene != null)
		{
			if (let comp = mScene.GetComponent<SkinnedMeshComponent>(entity))
				comp.InternalHandle = -1;
		}
	}

	/// Marks skinned mesh bones as dirty (need GPU upload).
	public void MarkSkinnedMeshBonesDirty(EntityId entity)
	{
		if (mEntityToSkinnedMeshInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mSkinnedMeshInstances[idx];
			if (instance.Active && instance.ProxyHandle.IsValid)
				mWorld?.MarkSkinnedMeshBonesDirty(instance.ProxyHandle);
		}
	}

	/// Returns whether the entity has a skinned mesh component managed by this module.
	public bool HasSkinnedMesh(EntityId entity)
	{
		return mEntityToSkinnedMeshInstance.ContainsKey(entity);
	}

	/// Duplicates the skinned mesh from src entity to dst entity (copies ResourceRefs for deferred loading).
	public void DuplicateSkinnedMesh(EntityId src, EntityId dst)
	{
		if (!mEntityToSkinnedMeshInstance.TryGetValue(src, var srcIdx))
			return;

		var srcInstance = ref mSkinnedMeshInstances[srcIdx];
		if (!srcInstance.Active)
			return;

		// Create skinned mesh from ref (deferred resource loading)
		if (srcInstance.MeshRef.IsValid)
			CreateSkinnedMeshFromRef(dst, ResourceRef(srcInstance.MeshRef.Id, srcInstance.MeshRef.Path), srcInstance.Enabled);
		else
			return;

		// Copy material refs
		if (!mEntityToSkinnedMeshInstance.TryGetValue(dst, var dstIdx))
			return;

		for (int32 i = 0; i < srcInstance.MaterialRefs.Count; i++)
		{
			if (srcInstance.MaterialRefs[i].IsValid)
				SetSkinnedMeshMaterialRef(dst, i, ResourceRef(srcInstance.MaterialRefs[i].Id, srcInstance.MaterialRefs[i].Path));
		}
	}

	/// Internal: Uploads skinned mesh resource to GPU (if not cached) and sets mesh data on proxy.
	/// Bone buffer is created separately when the skeleton becomes available (via AnimationSceneModule).
	private void UploadAndSetSkinnedMeshData(EntityId entity, SkinnedMeshProxyHandle proxyHandle, SkinnedMeshResource resource)
	{
		if (resource == null || resource.Mesh == null || !proxyHandle.IsValid)
			return;

		// Check cache first for mesh
		GPUMeshHandle gpuMeshHandle;
		if (!mSkinnedMeshCache.TryGetValue(resource, out gpuMeshHandle))
		{
			// Upload mesh to GPU
			let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
			if (gpuManager == null)
				return;

			if (gpuManager.UploadMesh(resource.Mesh) case .Ok(let handle))
			{
				mSkinnedMeshCache[resource] = handle;
				gpuMeshHandle = handle;
			}
			else
				return;
		}

		// Set mesh data on proxy (bone buffer created later when skeleton is available)
		if (let proxy = mWorld?.GetSkinnedMesh(proxyHandle))
		{
			proxy.MeshHandle = gpuMeshHandle;
			proxy.SetLocalBounds(resource.Mesh.Bounds);
		}
	}

	/// Resolves pending resource refs on module-owned skinned mesh instances.
	/// Loads mesh/material resources, creates MaterialInstances, uploads to GPU, and syncs to proxies.
	private void ResolveSkinnedMeshInstanceRefs()
	{
		let resourceSystem = mSubsystem.Context?.Resources;
		if (resourceSystem == null)
			return;

		for (var instance in ref mSkinnedMeshInstances)
		{
			if (!instance.Active || !instance.Enabled)
				continue;

			// Resolve mesh ref → resource handle
			if (instance.MeshRef.IsValid)
			{
				bool needsLoad = !instance.MeshRes.IsValid;
				if (!needsLoad && instance.MeshRef.HasId && instance.MeshRes.Resource != null && instance.MeshRes.Resource.Id != instance.MeshRef.Id)
				{
					instance.MeshRes.Release();
					needsLoad = true;
				}
				if (needsLoad)
				{
					if (resourceSystem.LoadByRef<SkinnedMeshResource>(instance.MeshRef) case .Ok(let handle))
						instance.MeshRes = handle;
				}
			}

			// Resolve material refs → resource handles → MaterialInstances
			for (int32 i = 0; i < instance.MaterialRefs.Count; i++)
			{
				if (instance.MaterialRefs[i].IsValid)
				{
					bool needsLoad = !instance.Materials[i].IsValid;
					if (!needsLoad && instance.MaterialRefs[i].HasId && instance.Materials[i].Resource != null && instance.Materials[i].Resource.Id != instance.MaterialRefs[i].Id)
					{
						instance.Materials[i].Release();
						if (instance.MaterialInstances[i] != null)
						{
							instance.MaterialInstances[i].ReleaseRef();
							instance.MaterialInstances[i] = null;
						}
						needsLoad = true;
					}
					if (needsLoad)
					{
						if (resourceSystem.LoadByRef<MaterialResource>(instance.MaterialRefs[i]) case .Ok(let handle))
						{
							instance.Materials[i] = handle;
							if (handle.Resource?.Material != null && instance.MaterialInstances[i] == null)
							{
								instance.MaterialInstances[i] = new MaterialInstance(handle.Resource.Material);
								ResolveTextureRefs(instance.Entity, resourceSystem, handle.Resource, instance.MaterialInstances[i]);
							}
						}
					}
				}
			}

			// Detect mesh resource change → upload to GPU and bind to proxy
			let resource = instance.MeshRes.Resource;
			if (resource != instance.BoundMeshResource)
			{
				if (resource != null && resource.Mesh != null)
				{
					// Create proxy if needed
					if (!instance.ProxyHandle.IsValid)
					{
						instance.ProxyHandle = mWorld.CreateSkinnedMesh();
						// Sync initial transform
						if (mScene != null)
						{
							let worldMatrix = mScene.GetWorldMatrix(instance.Entity);
							mWorld.SetSkinnedMeshTransform(instance.ProxyHandle, worldMatrix);
						}
					}
					UploadAndSetSkinnedMeshData(instance.Entity, instance.ProxyHandle, resource);
					instance.BoundMeshResource = resource;
				}
				else if (resource == null && instance.BoundMeshResource != null)
				{
					instance.BoundMeshResource = null;
				}
			}

			// Sync materials to proxy
			if (instance.ProxyHandle.IsValid)
			{
				if (let proxy = mWorld.GetSkinnedMesh(instance.ProxyHandle))
				{
					for (int32 i = 0; i < instance.MaterialRefs.Count; i++)
					{
						if (instance.MaterialInstances[i] != proxy.Materials[i])
							mWorld.SetSkinnedMeshMaterial(instance.ProxyHandle, i, instance.MaterialInstances[i]);
					}
				}
			}

			// Handle bone buffer management via AnimationSceneModule
			if (instance.ProxyHandle.IsValid)
			{
				let animModule = mScene?.GetModule<AnimationSceneModule>();
				let skeleton = animModule?.GetSkeleton(instance.Entity);
				if (skeleton != null)
				{
					if (let proxy = mWorld.GetSkinnedMesh(instance.ProxyHandle))
					{
						let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
						if (gpuManager != null)
						{
							// Create or recreate bone buffer if needed
							let newBoneCount = (uint16)skeleton.BoneCount;
							if (!proxy.BoneBufferHandle.IsValid || proxy.BoneCount != newBoneCount)
							{
								if (proxy.BoneBufferHandle.IsValid)
								{
									let frameNumber = mSubsystem.RenderSystem?.FrameNumber ?? 0;
									gpuManager.ReleaseBoneBuffer(proxy.BoneBufferHandle, frameNumber);
									proxy.BoneBufferHandle = .Invalid;
									proxy.BoneCount = 0;
								}

								if (gpuManager.CreateBoneBuffer(newBoneCount) case .Ok(let boneHandle))
								{
									proxy.BoneBufferHandle = boneHandle;
									proxy.BoneCount = newBoneCount;
								}
							}

							// Upload bone matrices
							if (proxy.BoneBufferHandle.IsValid)
							{
								let currentMatrices = animModule.GetSkinningMatrices(instance.Entity);
								let prevMatrices = animModule.GetPrevSkinningMatrices(instance.Entity);
								if (currentMatrices.Length > 0)
								{
									gpuManager.UpdateBoneBuffer(
										proxy.BoneBufferHandle,
										currentMatrices.Ptr,
										prevMatrices.Ptr,
										proxy.BoneCount
									);
								}
							}
						}
					}
				}
			}
		}
	}
}

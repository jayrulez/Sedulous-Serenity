namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Geometry.Resources;
using Sedulous.Core.Mathematics;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.RHI;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Textures.Resources;
using Sedulous.Imaging;

/// Mesh instance storage and API.
extension RenderSceneModule
{
	// ==================== Mesh Instance Storage ====================

	/// Internal data for a static mesh instance, owned by this module.
	public struct MeshInstanceData
	{
		public EntityId Entity;
		public MeshRenderHandle RenderHandle = .Invalid;
		public ResourceHandle<StaticMeshResource> MeshRes;
		public ResourceRef MeshRef;
		public ResourceRefArray<const RenderConfig.MaxMaterialsPerMesh> MaterialRefs;
		public ResourceHandle<MaterialResource>[RenderConfig.MaxMaterialsPerMesh] Materials;
		public MaterialInstance[RenderConfig.MaxMaterialsPerMesh] MaterialInstances;
		public StaticMeshResource BoundMeshResource; // Track which resource is currently bound to proxy
		public bool Enabled;
		public bool Active; // Slot in use
	}

	private List<MeshInstanceData> mMeshInstances = new .() ~ delete _;
	private List<int32> mFreeMeshSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToMeshInstance = new .() ~ delete _;

	// Cache: resource -> GPU handle (shared across entities using same static mesh resource)
	private Dictionary<StaticMeshResource, GPUMeshHandle> mStaticMeshCache = new .() ~ delete _;

	/// Provides read access to mesh instances for serialization.
	public List<MeshInstanceData> MeshInstances => mMeshInstances;

	// ==================== Mesh API ====================

	/// Creates a static mesh for an entity from a loaded resource.
	/// The mesh is uploaded to GPU and a proxy is created.
	public void CreateMesh(EntityId entity, StaticMeshResource resource, bool enabled = true)
	{
		if (mScene == null || mWorld == null)
			return;

		// Allocate a slot
		int32 slotIdx;
		if (mFreeMeshSlots.Count > 0)
		{
			slotIdx = mFreeMeshSlots.PopBack();
		}
		else
		{
			slotIdx = (int32)mMeshInstances.Count;
			mMeshInstances.Add(.());
		}

		var instance = ref mMeshInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.Enabled = enabled;
		instance.Active = true;

		// Set resource directly (no ref needed, resource already loaded)
		if (resource != null)
		{
			instance.MeshRes = ResourceHandle<StaticMeshResource>(resource);

			if (resource.Mesh != null)
			{
				instance.RenderHandle = mWorld.CreateMesh();
				let worldMatrix = mScene.GetWorldMatrix(entity);
				mWorld.SetMeshTransform(instance.RenderHandle, worldMatrix);
				UploadAndSetMeshData(entity, instance.RenderHandle, resource);
				instance.BoundMeshResource = resource;
			}
		}

		mEntityToMeshInstance[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<MeshComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<MeshComponent>(entity, .());
			comp = mScene.GetComponent<MeshComponent>(entity);
		}
		comp.InternalHandle = slotIdx;
	}

	/// Creates a static mesh for an entity from a resource reference (deferred loading).
	/// The resource will be resolved in the next PostUpdate frame.
	public void CreateMeshFromRef(EntityId entity, ResourceRef meshRef, bool enabled = true)
	{
		if (mScene == null || mWorld == null)
			return;

		// Allocate a slot
		int32 slotIdx;
		if (mFreeMeshSlots.Count > 0)
		{
			slotIdx = mFreeMeshSlots.PopBack();
		}
		else
		{
			slotIdx = (int32)mMeshInstances.Count;
			mMeshInstances.Add(.());
		}

		var instance = ref mMeshInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		if (meshRef.IsValid)
			instance.MeshRef = ResourceRef(meshRef.Id, meshRef.Path);
		instance.Enabled = enabled;
		instance.Active = true;

		mEntityToMeshInstance[entity] = slotIdx;

		// Set handle on entity component
		var comp = mScene.GetComponent<MeshComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<MeshComponent>(entity, .());
			comp = mScene.GetComponent<MeshComponent>(entity);
		}
		comp.InternalHandle = slotIdx;
	}

	/// Sets a material on a mesh slot by MaterialInstance.
	/// The module takes ownership of the ref (calls AddRef internally).
	public void SetMeshMaterial(EntityId entity, int32 slot, MaterialInstance material)
	{
		if (!mEntityToMeshInstance.TryGetValue(entity, let idx))
			return;

		var instance = ref mMeshInstances[idx];
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

	/// Sets a material on a mesh slot by resource reference (deferred loading).
	public void SetMeshMaterialRef(EntityId entity, int32 slot, ResourceRef materialRef)
	{
		if (!mEntityToMeshInstance.TryGetValue(entity, let idx))
			return;

		var instance = ref mMeshInstances[idx];
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

		// Set new ref (will be resolved in ResolveMeshInstanceRefs)
		if (materialRef.IsValid)
			instance.MaterialRefs[slot] = ResourceRef(materialRef.Id, materialRef.Path);

		// Ensure MaterialRefs.Count covers this slot
		if (slot >= instance.MaterialRefs.Count)
			instance.MaterialRefs.Count = slot + 1;
	}

	/// Gets the mesh proxy for an entity (for advanced read-only access).
	public MeshProxy* GetMeshProxy(EntityId entity)
	{
		if (mEntityToMeshInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mMeshInstances[idx];
			if (instance.Active && instance.RenderHandle.IsValid)
				return mWorld?.GetMesh(instance.RenderHandle);
		}
		return null;
	}

	/// Gets the bound mesh resource for an entity.
	public StaticMeshResource GetMeshResource(EntityId entity)
	{
		if (mEntityToMeshInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mMeshInstances[idx];
			if (instance.Active)
				return instance.MeshRes.Resource;
		}
		return null;
	}

	/// Destroys a mesh instance for an entity.
	public void DestroyMesh(EntityId entity)
	{
		if (!mEntityToMeshInstance.TryGetValue(entity, let idx))
			return;

		var instance = ref mMeshInstances[idx];
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
			if (instance.RenderHandle.IsValid)
				mWorld.DestroyMesh(instance.RenderHandle);
			instance.Active = false;
			mFreeMeshSlots.Add(idx);
		}
		mEntityToMeshInstance.Remove(entity);

		// Clear handle on component
		if (mScene != null)
		{
			if (let comp = mScene.GetComponent<MeshComponent>(entity))
				comp.InternalHandle = -1;
		}
	}

	/// Destroys all mesh instances (bulk teardown for scene destroy).
	private void DestroyAllMeshes()
	{
		for (var instance in ref mMeshInstances)
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
			if (mWorld != null && instance.RenderHandle.IsValid)
				mWorld.DestroyMesh(instance.RenderHandle);
			instance.Active = false;
		}
		mMeshInstances.Clear();
		mFreeMeshSlots.Clear();
		mEntityToMeshInstance.Clear();

		// Release cached GPU meshes
		let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
		let frameNumber = mSubsystem.RenderSystem?.FrameNumber ?? 0;
		if (gpuManager != null)
		{
			for (let handle in mStaticMeshCache.Values)
				gpuManager.ReleaseMesh(handle, frameNumber);
		}
		mStaticMeshCache.Clear();
	}

	/// Syncs mesh proxy transform from world matrix.
	private void SyncMeshTransform(EntityId entity, in Matrix worldMatrix)
	{
		if (mEntityToMeshInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mMeshInstances[idx];
			if (instance.Active && instance.RenderHandle.IsValid)
				mWorld?.SetMeshTransform(instance.RenderHandle, worldMatrix);
		}
	}

	/// Internal: Uploads mesh resource to GPU (if not cached) and sets mesh data on proxy.
	private void UploadAndSetMeshData(EntityId entity, MeshRenderHandle proxyHandle, StaticMeshResource resource)
	{
		if (resource == null || resource.Mesh == null || !proxyHandle.IsValid)
			return;

		// Check cache first
		GPUMeshHandle gpuHandle;
		if (mStaticMeshCache.TryGetValue(resource, out gpuHandle))
		{
			// Already uploaded, just set the data
			mWorld?.SetMeshData(proxyHandle, gpuHandle, resource.Mesh.GetBounds());
			return;
		}

		// Upload to GPU
		let gpuManager = mSubsystem.RenderSystem?.ResourceManager;
		if (gpuManager == null)
			return;

		if (gpuManager.UploadMesh(resource.Mesh) case .Ok(let handle))
		{
			// Cache the mapping
			mStaticMeshCache[resource] = handle;

			// Set mesh data on proxy
			mWorld?.SetMeshData(proxyHandle, handle, resource.Mesh.GetBounds());
		}
	}

	/// Sets the render flags for a mesh.
	public void SetMeshFlags(EntityId entity, MeshFlags flags)
	{
		if (mEntityToMeshInstance.TryGetValue(entity, let idx))
		{
			let instance = ref mMeshInstances[idx];
			if (instance.Active && instance.RenderHandle.IsValid)
				mWorld?.SetMeshFlags(instance.RenderHandle, flags);
		}
	}

	/// Enables or disables a mesh.
	public void SetMeshEnabled(EntityId entity, bool enabled)
	{
		if (mEntityToMeshInstance.TryGetValue(entity, let idx))
		{
			var instance = ref mMeshInstances[idx];
			if (instance.Active)
			{
				instance.Enabled = enabled;
				if (instance.RenderHandle.IsValid)
				{
					if (let proxy = mWorld?.GetMesh(instance.RenderHandle))
					{
						if (enabled)
							proxy.Flags |= .Visible;
						else
							proxy.Flags &= ~.Visible;
					}
				}
			}
		}
	}

	/// Returns whether the entity has a mesh component managed by this module.
	public bool HasMesh(EntityId entity)
	{
		return mEntityToMeshInstance.ContainsKey(entity);
	}

	/// Duplicates the mesh from src entity to dst entity (copies ResourceRefs for deferred loading).
	public void DuplicateMesh(EntityId src, EntityId dst)
	{
		if (!mEntityToMeshInstance.TryGetValue(src, var srcIdx))
			return;

		var srcInstance = ref mMeshInstances[srcIdx];
		if (!srcInstance.Active)
			return;

		// Create mesh from ref (deferred resource loading)
		if (srcInstance.MeshRef.IsValid)
			CreateMeshFromRef(dst, ResourceRef(srcInstance.MeshRef.Id, srcInstance.MeshRef.Path), srcInstance.Enabled);
		else
			return;

		// Copy material refs
		if (!mEntityToMeshInstance.TryGetValue(dst, var dstIdx))
			return;

		for (int32 i = 0; i < srcInstance.MaterialRefs.Count; i++)
		{
			if (srcInstance.MaterialRefs[i].IsValid)
				SetMeshMaterialRef(dst, i, ResourceRef(srcInstance.MaterialRefs[i].Id, srcInstance.MaterialRefs[i].Path));
		}
	}

	/// Resolves pending resource refs on module-owned mesh instances.
	/// Loads mesh/material resources, creates MaterialInstances, uploads to GPU, and syncs to proxies.
	private void ResolveMeshInstanceRefs()
	{
		let resourceSystem = mSubsystem.Context?.Resources;
		if (resourceSystem == null)
			return;

		for (var instance in ref mMeshInstances)
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
					if (resourceSystem.LoadByRef<StaticMeshResource>(instance.MeshRef) case .Ok(let handle))
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
					if (!instance.RenderHandle.IsValid)
					{
						instance.RenderHandle = mWorld.CreateMesh();
						// Sync initial transform
						if (mScene != null)
						{
							let worldMatrix = mScene.GetWorldMatrix(instance.Entity);
							mWorld.SetMeshTransform(instance.RenderHandle, worldMatrix);
						}
					}
					UploadAndSetMeshData(instance.Entity, instance.RenderHandle, resource);
					instance.BoundMeshResource = resource;
				}
				else if (resource == null && instance.BoundMeshResource != null)
				{
					instance.BoundMeshResource = null;
				}
			}

			// Sync materials to proxy
			if (instance.RenderHandle.IsValid)
			{
				if (let proxy = mWorld.GetMesh(instance.RenderHandle))
				{
					for (int32 i = 0; i < instance.MaterialRefs.Count; i++)
					{
						if (instance.MaterialInstances[i] != proxy.Materials[i])
							mWorld.SetMeshMaterial(instance.RenderHandle, i, instance.MaterialInstances[i]);
					}
				}
			}
		}
	}
}

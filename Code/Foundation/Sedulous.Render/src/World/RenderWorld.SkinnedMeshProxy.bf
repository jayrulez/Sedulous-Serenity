using Sedulous.Materials;
using Sedulous.Core.Mathematics;
namespace Sedulous.Render;

extension RenderWorld
{
	private RenderPool<SkinnedMeshProxy> mSkinnedMeshProxies = new .() ~ delete _;

	// ========================================================================
	// Skinned Mesh API
	// ========================================================================

	/// Creates a new skinned mesh proxy.
	public SkinnedMeshRenderHandle CreateSkinnedMesh()
	{
		let handle = mSkinnedMeshProxies.Allocate();
		var proxy = mSkinnedMeshProxies.Get(handle);
		proxy.Reset();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		proxy.Flags = .DefaultOpaque;
		mSkinnedMeshesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a skinned mesh proxy by handle.
	public SkinnedMeshProxy* GetSkinnedMesh(SkinnedMeshRenderHandle handle)
	{
		return mSkinnedMeshProxies.Get(handle.Handle);
	}

	/// Gets a reference to a skinned mesh proxy.
	public ref SkinnedMeshProxy GetSkinnedMeshRef(SkinnedMeshRenderHandle handle)
	{
		return ref mSkinnedMeshProxies.GetRef(handle.Handle);
	}

	/// Destroys a skinned mesh proxy.
	public void DestroySkinnedMesh(SkinnedMeshRenderHandle handle)
	{
		if (mSkinnedMeshProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mSkinnedMeshProxies.Free(handle.Handle);
		mSkinnedMeshesDirty = true;
	}

	/// Sets skinned mesh transform.
	public void SetSkinnedMeshTransform(SkinnedMeshRenderHandle handle, Matrix worldMatrix)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			proxy.SetTransform(worldMatrix);
			mSkinnedMeshesDirty = true;
		}
	}

	/// Sets skinned mesh GPU handles and bounds.
	public void SetSkinnedMeshData(SkinnedMeshRenderHandle handle, GPUMeshHandle meshHandle, GPUBoneBufferHandle boneBufferHandle, BoundingBox localBounds, uint16 boneCount)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			proxy.MeshHandle = meshHandle;
			proxy.BoneBufferHandle = boneBufferHandle;
			proxy.BoneCount = boneCount;
			proxy.SetLocalBounds(localBounds);
			mSkinnedMeshesDirty = true;
		}
	}

	/// Sets skinned mesh material for a specific slot.
	public void SetSkinnedMeshMaterial(SkinnedMeshRenderHandle handle, int32 slot, MaterialInstance material)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			if (slot >= 0 && slot < RenderConfig.MaxMaterialsPerMesh)
			{
				proxy.Materials[slot] = material;
				if (slot >= proxy.MaterialCount)
					proxy.MaterialCount = slot + 1;
				mSkinnedMeshesDirty = true;
			}
		}
	}

	/// Sets skinned mesh material (slot 0 convenience overload).
	public void SetSkinnedMeshMaterial(SkinnedMeshRenderHandle handle, MaterialInstance material)
	{
		SetSkinnedMeshMaterial(handle, 0, material);
	}

	/// Sets skinned mesh flags.
	public void SetSkinnedMeshFlags(SkinnedMeshRenderHandle handle, MeshFlags flags)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			proxy.Flags = flags;
			mSkinnedMeshesDirty = true;
		}
	}

	/// Marks skinned mesh bones as dirty (need GPU upload).
	public void MarkSkinnedMeshBonesDirty(SkinnedMeshRenderHandle handle)
	{
		if (let proxy = GetSkinnedMesh(handle))
		{
			proxy.MarkBonesDirty();
			mSkinnedMeshesDirty = true;
		}
	}

	/// Iterates over all active skinned meshes.
	public void ForEachSkinnedMesh(RenderPoolCallback<SkinnedMeshProxy> callback)
	{
		mSkinnedMeshProxies.ForEach(callback);
	}
}

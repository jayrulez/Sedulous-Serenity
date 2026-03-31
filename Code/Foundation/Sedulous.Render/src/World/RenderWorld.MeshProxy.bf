using Sedulous.Materials;
using Sedulous.Core.Mathematics;
namespace Sedulous.Render;

extension RenderWorld
{
	private ProxyPool<MeshProxy> mMeshProxies = new .() ~ delete _;

	// ========================================================================
	// Mesh API
	// ========================================================================

	/// Creates a new mesh proxy.
	public MeshProxyHandle CreateMesh()
	{
		let handle = mMeshProxies.Allocate();
		var proxy = mMeshProxies.Get(handle);
		proxy.Reset();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		proxy.Flags = .DefaultOpaque;
		mMeshesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a mesh proxy by handle.
	public MeshProxy* GetMesh(MeshProxyHandle handle)
	{
		return mMeshProxies.Get(handle.Handle);
	}

	/// Gets a reference to a mesh proxy.
	public ref MeshProxy GetMeshRef(MeshProxyHandle handle)
	{
		return ref mMeshProxies.GetRef(handle.Handle);
	}

	/// Destroys a mesh proxy.
	public void DestroyMesh(MeshProxyHandle handle)
	{
		if (mMeshProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mMeshProxies.Free(handle.Handle);
		mMeshesDirty = true;
	}

	/// Sets mesh transform.
	public void SetMeshTransform(MeshProxyHandle handle, Matrix worldMatrix)
	{
		if (let proxy = mMeshProxies.Get(handle.Handle))
		{
			proxy.SetTransform(worldMatrix);
			mMeshesDirty = true;
		}
	}

	/// Sets mesh GPU handle and bounds.
	public void SetMeshData(MeshProxyHandle handle, GPUMeshHandle meshHandle, BoundingBox localBounds)
	{
		if (let proxy = mMeshProxies.Get(handle.Handle))
		{
			proxy.MeshHandle = meshHandle;
			proxy.SetLocalBounds(localBounds);
			mMeshesDirty = true;
		}
	}

	/// Sets mesh material for a specific slot.
	public void SetMeshMaterial(MeshProxyHandle handle, int32 slot, MaterialInstance material)
	{
		if (let proxy = mMeshProxies.Get(handle.Handle))
		{
			if (slot >= 0 && slot < RenderConfig.MaxMaterialsPerMesh)
			{
				proxy.Materials[slot] = material;
				if (slot >= proxy.MaterialCount)
					proxy.MaterialCount = slot + 1;
				mMeshesDirty = true;
			}
		}
	}

	/// Sets mesh material (slot 0 convenience overload).
	public void SetMeshMaterial(MeshProxyHandle handle, MaterialInstance material)
	{
		SetMeshMaterial(handle, 0, material);
	}

	/// Sets mesh flags.
	public void SetMeshFlags(MeshProxyHandle handle, MeshFlags flags)
	{
		if (let proxy = mMeshProxies.Get(handle.Handle))
		{
			proxy.Flags = flags;
			mMeshesDirty = true;
		}
	}

	/// Iterates over all active meshes.
	public void ForEachMesh(ProxyCallback<MeshProxy> callback)
	{
		mMeshProxies.ForEach(callback);
	}
}

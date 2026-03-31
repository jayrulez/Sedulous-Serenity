namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Materials;
using Sedulous.RHI;

extension RenderWorld
{
	private ProxyPool<StaticMeshProxy> mStaticMeshProxies = new .() ~ delete _;

	private bool mStaticMeshesDirty = false;

	/// Gets the static mesh proxy pool.
	public ProxyPool<StaticMeshProxy> StaticMeshProxies => mStaticMeshProxies;

	/// Gets the number of active static meshes.
	public int32 StaticMeshCount => mStaticMeshProxies.ActiveCount;

	/// Whether any static meshes have changed.
	public bool StaticMeshesDirty => mStaticMeshesDirty;

	/// Creates a new static mesh proxy.
	public StaticMeshProxyHandle CreateStaticMesh()
	{
		let handle = mStaticMeshProxies.Allocate();
		var proxy = mStaticMeshProxies.Get(handle);
		proxy.Reset();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		proxy.Flags = .DefaultOpaque;
		mStaticMeshesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a static mesh proxy by handle.
	public StaticMeshProxy* GetStaticMesh(StaticMeshProxyHandle handle)
	{
		return mStaticMeshProxies.Get(handle.Handle);
	}

	/// Gets a reference to a static mesh proxy.
	public ref StaticMeshProxy GetStaticMeshRef(StaticMeshProxyHandle handle)
	{
		return ref mStaticMeshProxies.GetRef(handle.Handle);
	}

	/// Destroys a static mesh proxy.
	public void DestroyStaticMesh(StaticMeshProxyHandle handle)
	{
		if (mStaticMeshProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mStaticMeshProxies.Free(handle.Handle);
		mStaticMeshesDirty = true;
	}

	/// Sets static mesh transform.
	public void SetStaticMeshTransform(StaticMeshProxyHandle handle, Matrix worldMatrix)
	{
		if (let proxy = mStaticMeshProxies.Get(handle.Handle))
		{
			proxy.SetTransform(worldMatrix);
			mStaticMeshesDirty = true;
		}
	}

	/// Sets static mesh GPU handle and bounds.
	public void SetStaticMeshData(StaticMeshProxyHandle handle, GPUMeshHandle meshHandle, BoundingBox localBounds)
	{
		if (let proxy = mStaticMeshProxies.Get(handle.Handle))
		{
			proxy.MeshHandle = meshHandle;
			proxy.SetLocalBounds(localBounds);
			mStaticMeshesDirty = true;
		}
	}

	/// Sets static mesh material for a specific slot.
	public void SetStaticMeshMaterial(StaticMeshProxyHandle handle, int32 slot, MaterialInstance material)
	{
		if (let proxy = mStaticMeshProxies.Get(handle.Handle))
		{
			if (slot >= 0 && slot < RenderConfig.MaxMaterialsPerMesh)
			{
				proxy.Materials[slot] = material;
				if (slot >= proxy.MaterialCount)
					proxy.MaterialCount = slot + 1;
				mStaticMeshesDirty = true;
			}
		}
	}

	/// Sets static mesh material (slot 0 convenience overload).
	public void SetStaticMeshMaterial(StaticMeshProxyHandle handle, MaterialInstance material)
	{
		SetStaticMeshMaterial(handle, 0, material);
	}

	/// Sets static mesh flags.
	public void SetStaticMeshFlags(StaticMeshProxyHandle handle, MeshFlags flags)
	{
		if (let proxy = mStaticMeshProxies.Get(handle.Handle))
		{
			proxy.Flags = flags;
			mStaticMeshesDirty = true;
		}
	}

	/// Iterates over all active static meshes.
	public void ForEachStaticMesh(ProxyCallback<StaticMeshProxy> callback)
	{
		mStaticMeshProxies.ForEach(callback);
	}
}

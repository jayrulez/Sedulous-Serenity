using Sedulous.RHI;
using Sedulous.Core.Mathematics;
namespace Sedulous.Render;

extension RenderWorld
{
	private ProxyPool<DecalProxy> mDecalProxies = new .() ~ delete _;

	// ========================================================================
	// Decal API
	// ========================================================================

	/// Creates a new decal proxy.
	public DecalProxyHandle CreateDecal()
	{
		let handle = mDecalProxies.Allocate();
		var proxy = mDecalProxies.Get(handle);
		*proxy = DecalProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mDecalsDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a decal proxy by handle.
	public DecalProxy* GetDecal(DecalProxyHandle handle)
	{
		return mDecalProxies.Get(handle.Handle);
	}

	/// Gets a reference to a decal proxy.
	public ref DecalProxy GetDecalRef(DecalProxyHandle handle)
	{
		return ref mDecalProxies.GetRef(handle.Handle);
	}

	/// Destroys a decal proxy.
	public void DestroyDecal(DecalProxyHandle handle)
	{
		if (mDecalProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mDecalProxies.Free(handle.Handle);
		mDecalsDirty = true;
	}

	/// Sets decal transform (position, rotation, scale).
	public void SetDecalTransform(DecalProxyHandle handle, Vector3 position, Quaternion rotation, Vector3 scale)
	{
		if (let proxy = mDecalProxies.Get(handle.Handle))
		{
			proxy.Position = position;
			proxy.Rotation = rotation;
			proxy.Scale = scale;
			mDecalsDirty = true;
		}
	}

	/// Sets decal albedo texture and sampler.
	public void SetDecalTexture(DecalProxyHandle handle, ITextureView texture, ISampler sampler = null)
	{
		if (let proxy = mDecalProxies.Get(handle.Handle))
		{
			proxy.AlbedoTexture = texture;
			proxy.Sampler = sampler;
			mDecalsDirty = true;
		}
	}

	/// Sets decal blend mode.
	public void SetDecalBlendMode(DecalProxyHandle handle, DecalBlendMode blendMode)
	{
		if (let proxy = mDecalProxies.Get(handle.Handle))
		{
			proxy.BlendMode = blendMode;
			mDecalsDirty = true;
		}
	}

	/// Enables or disables a decal.
	public void SetDecalEnabled(DecalProxyHandle handle, bool enabled)
	{
		if (let proxy = mDecalProxies.Get(handle.Handle))
		{
			proxy.IsActive = enabled;
			mDecalsDirty = true;
		}
	}

	/// Iterates over all active decals.
	public void ForEachDecal(ProxyCallback<DecalProxy> callback)
	{
		mDecalProxies.ForEach(callback);
	}
}

namespace Sedulous.Render;

extension RenderWorld
{
	private ProxyPool<GrassProxy> mGrassProxies = new .() ~ delete _;

	// ========================================================================
	// Grass API
	// ========================================================================

	/// Creates a new grass proxy.
	public GrassProxyHandle CreateGrass()
	{
		let handle = mGrassProxies.Allocate();
		var proxy = mGrassProxies.Get(handle);
		*proxy = GrassProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mGrassDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a grass proxy by handle.
	public GrassProxy* GetGrass(GrassProxyHandle handle)
	{
		return mGrassProxies.Get(handle.Handle);
	}

	/// Gets a reference to a grass proxy.
	public ref GrassProxy GetGrassRef(GrassProxyHandle handle)
	{
		return ref mGrassProxies.GetRef(handle.Handle);
	}

	/// Destroys a grass proxy.
	public void DestroyGrass(GrassProxyHandle handle)
	{
		if (mGrassProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mGrassProxies.Free(handle.Handle);
		mGrassDirty = true;
	}

	/// Marks grass as dirty (need GPU re-upload).
	public void MarkGrassDirty()
	{
		mGrassDirty = true;
	}

	/// Iterates over all active grass proxies.
	public void ForEachGrass(ProxyCallback<GrassProxy> callback)
	{
		mGrassProxies.ForEach(callback);
	}
}

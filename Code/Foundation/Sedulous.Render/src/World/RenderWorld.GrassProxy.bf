namespace Sedulous.Render;

extension RenderWorld
{
	private RenderPool<GrassProxy> mGrassProxies = new .() ~ delete _;

	// ========================================================================
	// Grass API
	// ========================================================================

	/// Creates a new grass proxy.
	public GrassRenderHandle CreateGrass()
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
	public GrassProxy* GetGrass(GrassRenderHandle handle)
	{
		return mGrassProxies.Get(handle.Handle);
	}

	/// Gets a reference to a grass proxy.
	public ref GrassProxy GetGrassRef(GrassRenderHandle handle)
	{
		return ref mGrassProxies.GetRef(handle.Handle);
	}

	/// Destroys a grass proxy.
	public void DestroyGrass(GrassRenderHandle handle)
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
	public void ForEachGrass(RenderPoolCallback<GrassProxy> callback)
	{
		mGrassProxies.ForEach(callback);
	}
}

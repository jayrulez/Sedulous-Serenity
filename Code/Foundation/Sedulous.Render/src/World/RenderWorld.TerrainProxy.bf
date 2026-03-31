namespace Sedulous.Render;

extension RenderWorld
{
	private ProxyPool<TerrainProxy> mTerrainProxies = new .() ~ delete _;

	// ========================================================================
	// Terrain API
	// ========================================================================

	/// Creates a new terrain proxy.
	public TerrainProxyHandle CreateTerrain()
	{
		let handle = mTerrainProxies.Allocate();
		var proxy = mTerrainProxies.Get(handle);
		*proxy = TerrainProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mTerrainsDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a terrain proxy by handle.
	public TerrainProxy* GetTerrain(TerrainProxyHandle handle)
	{
		return mTerrainProxies.Get(handle.Handle);
	}

	/// Gets a reference to a terrain proxy.
	public ref TerrainProxy GetTerrainRef(TerrainProxyHandle handle)
	{
		return ref mTerrainProxies.GetRef(handle.Handle);
	}

	/// Destroys a terrain proxy.
	public void DestroyTerrain(TerrainProxyHandle handle)
	{
		if (mTerrainProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mTerrainProxies.Free(handle.Handle);
		mTerrainsDirty = true;
	}

	/// Marks terrains as dirty (need GPU re-upload).
	public void MarkTerrainsDirty()
	{
		mTerrainsDirty = true;
	}

	/// Iterates over all active terrains.
	public void ForEachTerrain(ProxyCallback<TerrainProxy> callback)
	{
		mTerrainProxies.ForEach(callback);
	}
}

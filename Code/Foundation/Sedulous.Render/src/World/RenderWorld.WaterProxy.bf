namespace Sedulous.Render;

extension RenderWorld
{
	private RenderPool<WaterProxy> mWaterProxies = new .() ~ delete _;

	// ========================================================================
	// Water API
	// ========================================================================

	/// Creates a new water proxy.
	public WaterRenderHandle CreateWater()
	{
		let handle = mWaterProxies.Allocate();
		var proxy = mWaterProxies.Get(handle);
		*proxy = WaterProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mWatersDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a water proxy by handle.
	public WaterProxy* GetWater(WaterRenderHandle handle)
	{
		return mWaterProxies.Get(handle.Handle);
	}

	/// Gets a reference to a water proxy.
	public ref WaterProxy GetWaterRef(WaterRenderHandle handle)
	{
		return ref mWaterProxies.GetRef(handle.Handle);
	}

	/// Destroys a water proxy.
	public void DestroyWater(WaterRenderHandle handle)
	{
		if (mWaterProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mWaterProxies.Free(handle.Handle);
		mWatersDirty = true;
	}

	/// Marks waters as dirty (need GPU re-upload).
	public void MarkWatersDirty()
	{
		mWatersDirty = true;
	}

	/// Iterates over all active water planes.
	public void ForEachWater(RenderPoolCallback<WaterProxy> callback)
	{
		mWaterProxies.ForEach(callback);
	}
}

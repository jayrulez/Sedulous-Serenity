namespace Sedulous.Render;

extension RenderWorld
{
	private RenderPool<CurveDecalProxy> mCurveDecalProxies = new .() ~ delete _;

	// ========================================================================
	// Curve Decal API
	// ========================================================================

	/// Creates a new curve decal proxy.
	public CurveDecalRenderHandle CreateCurveDecal()
	{
		let handle = mCurveDecalProxies.Allocate();
		var proxy = mCurveDecalProxies.Get(handle);
		*proxy = CurveDecalProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mCurveDecalsDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a curve decal proxy by handle.
	public CurveDecalProxy* GetCurveDecal(CurveDecalRenderHandle handle)
	{
		return mCurveDecalProxies.Get(handle.Handle);
	}

	/// Gets a reference to a curve decal proxy.
	public ref CurveDecalProxy GetCurveDecalRef(CurveDecalRenderHandle handle)
	{
		return ref mCurveDecalProxies.GetRef(handle.Handle);
	}

	/// Destroys a curve decal proxy.
	public void DestroyCurveDecal(CurveDecalRenderHandle handle)
	{
		if (mCurveDecalProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mCurveDecalProxies.Free(handle.Handle);
		mCurveDecalsDirty = true;
	}

	/// Marks curve decals as dirty (need mesh rebuild).
	public void MarkCurveDecalsDirty()
	{
		mCurveDecalsDirty = true;
	}

	/// Iterates over all active curve decal proxies.
	public void ForEachCurveDecal(RenderPoolCallback<CurveDecalProxy> callback)
	{
		mCurveDecalProxies.ForEach(callback);
	}
}

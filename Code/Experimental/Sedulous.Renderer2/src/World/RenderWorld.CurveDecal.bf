namespace Sedulous.Renderer;

using System;
using System.Collections;

extension RenderWorld
{
	private ProxyPool<CurveDecalProxy> mCurveDecalProxies = new .() ~ delete _;

	private bool mCurveDecalsDirty = false;

	/// Gets the curve decal proxy pool.
	public ProxyPool<CurveDecalProxy> CurveDecalProxies => mCurveDecalProxies;

	/// Gets the number of active curve decals.
	public int32 CurveDecalCount => mCurveDecalProxies.ActiveCount;

	/// Whether any curve decals have changed.
	public bool CurveDecalsDirty => mCurveDecalsDirty;

	/// Creates a new curve decal proxy.
	public CurveDecalProxyHandle CreateCurveDecal()
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
	public CurveDecalProxy* GetCurveDecal(CurveDecalProxyHandle handle)
	{
		return mCurveDecalProxies.Get(handle.Handle);
	}

	/// Gets a reference to a curve decal proxy.
	public ref CurveDecalProxy GetCurveDecalRef(CurveDecalProxyHandle handle)
	{
		return ref mCurveDecalProxies.GetRef(handle.Handle);
	}

	/// Destroys a curve decal proxy.
	public void DestroyCurveDecal(CurveDecalProxyHandle handle)
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
	public void ForEachCurveDecal(ProxyCallback<CurveDecalProxy> callback)
	{
		mCurveDecalProxies.ForEach(callback);
	}
}

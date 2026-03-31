namespace Sedulous.Renderer;

using System;
using System.Collections;

extension RenderWorld
{
	private ProxyPool<ReflectionProbeProxy> mReflectionProbeProxies = new .() ~ delete _;

	private bool mReflectionProbesDirty = false;

	/// Gets the reflection probe proxy pool.
	public ProxyPool<ReflectionProbeProxy> ReflectionProbeProxies => mReflectionProbeProxies;

	/// Gets the number of active reflection probes.
	public int32 ReflectionProbeCount => mReflectionProbeProxies.ActiveCount;

	/// Whether any reflection probes have changed.
	public bool ReflectionProbesDirty => mReflectionProbesDirty;

	/// Creates a new reflection probe proxy.
	public ReflectionProbeProxyHandle CreateReflectionProbe()
	{
		let handle = mReflectionProbeProxies.Allocate();
		var proxy = mReflectionProbeProxies.Get(handle);
		*proxy = ReflectionProbeProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mReflectionProbesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a reflection probe proxy by handle.
	public ReflectionProbeProxy* GetReflectionProbe(ReflectionProbeProxyHandle handle)
	{
		return mReflectionProbeProxies.Get(handle.Handle);
	}

	/// Gets a reference to a reflection probe proxy.
	public ref ReflectionProbeProxy GetReflectionProbeRef(ReflectionProbeProxyHandle handle)
	{
		return ref mReflectionProbeProxies.GetRef(handle.Handle);
	}

	/// Destroys a reflection probe proxy.
	public void DestroyReflectionProbe(ReflectionProbeProxyHandle handle)
	{
		if (mReflectionProbeProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mReflectionProbeProxies.Free(handle.Handle);
		mReflectionProbesDirty = true;
	}

	/// Marks reflection probes as dirty (need GPU re-upload).
	public void MarkReflectionProbesDirty()
	{
		mReflectionProbesDirty = true;
	}

	/// Iterates over all active reflection probes.
	public void ForEachReflectionProbe(ProxyCallback<ReflectionProbeProxy> callback)
	{
		mReflectionProbeProxies.ForEach(callback);
	}
}

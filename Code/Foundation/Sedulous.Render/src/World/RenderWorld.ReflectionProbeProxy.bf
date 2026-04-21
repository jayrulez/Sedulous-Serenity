namespace Sedulous.Render;

extension RenderWorld
{
	private RenderPool<ReflectionProbeProxy> mReflectionProbeProxies = new .() ~ delete _;

	// ========================================================================
	// Reflection Probe API
	// ========================================================================

	/// Creates a new reflection probe proxy.
	public ReflectionProbeRenderHandle CreateReflectionProbe()
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
	public ReflectionProbeProxy* GetReflectionProbe(ReflectionProbeRenderHandle handle)
	{
		return mReflectionProbeProxies.Get(handle.Handle);
	}

	/// Gets a reference to a reflection probe proxy.
	public ref ReflectionProbeProxy GetReflectionProbeRef(ReflectionProbeRenderHandle handle)
	{
		return ref mReflectionProbeProxies.GetRef(handle.Handle);
	}

	/// Destroys a reflection probe proxy.
	public void DestroyReflectionProbe(ReflectionProbeRenderHandle handle)
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
	public void ForEachReflectionProbe(RenderPoolCallback<ReflectionProbeProxy> callback)
	{
		mReflectionProbeProxies.ForEach(callback);
	}
}

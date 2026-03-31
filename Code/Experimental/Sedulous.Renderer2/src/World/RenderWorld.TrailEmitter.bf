namespace Sedulous.Renderer;

using System;
using System.Collections;

extension RenderWorld
{
	private ProxyPool<TrailEmitterProxy> mTrailProxies = new .() ~ delete _;

	private bool mTrailsDirty = false;

	/// Gets the number of active trail emitters.
	public int32 TrailEmitterCount => mTrailProxies.ActiveCount;

	/// Whether any trails have changed.
	public bool TrailsDirty => mTrailsDirty;

	/// Creates a new standalone trail emitter proxy.
	public TrailEmitterProxyHandle CreateTrailEmitter()
	{
		let handle = mTrailProxies.Allocate();
		var proxy = mTrailProxies.Get(handle);
		*proxy = TrailEmitterProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mTrailsDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a trail emitter proxy by handle.
	public TrailEmitterProxy* GetTrailEmitter(TrailEmitterProxyHandle handle)
	{
		return mTrailProxies.Get(handle.Handle);
	}

	/// Destroys a trail emitter proxy.
	/// Trail emitter buffers are deferred for deletion to avoid destroying
	/// GPU resources that may still be referenced by in-flight command buffers.
	public void DestroyTrailEmitter(TrailEmitterProxyHandle handle)
	{
		if (mTrailProxies.TryGet(handle.Handle, let proxy))
		{
			if (proxy.Emitter != null)
			{
				var pending = PendingTrailDeletion();
				pending.Emitter = proxy.Emitter;
				pending.FramesRemaining = RenderConfig.FrameBufferCount + 1;
				mPendingTrailDeletions.Add(pending);
				proxy.Emitter = null;
			}
			proxy.Reset();
		}
		mTrailProxies.Free(handle.Handle);
		mTrailsDirty = true;
	}

	/// Iterates over all active trail emitters.
	public void ForEachTrailEmitter(ProxyCallback<TrailEmitterProxy> callback)
	{
		mTrailProxies.ForEach(callback);
	}
}

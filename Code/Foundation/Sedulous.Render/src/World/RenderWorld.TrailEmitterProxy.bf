namespace Sedulous.Render;

using Sedulous.Core.Mathematics;

extension RenderWorld
{
	private ProxyPool<TrailEmitterProxy> mTrailProxies = new .() ~ delete _;

	// ========================================================================
	// Trail API
	// ========================================================================

	/// Creates a new standalone trail emitter proxy and its TrailEmitter instance.
	public TrailEmitterProxyHandle CreateTrailEmitter()
	{
		let handle = mTrailProxies.Allocate();
		var proxy = mTrailProxies.Get(handle);
		*proxy = TrailEmitterProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mTrailsDirty = true;

		let trailHandle = TrailEmitterProxyHandle() { Handle = handle };
		mTrailEmitters[trailHandle] = new TrailEmitter(mDevice, proxy.MaxPoints);

		return trailHandle;
	}

	/// Gets a trail emitter proxy by handle.
	public TrailEmitterProxy* GetTrailEmitter(TrailEmitterProxyHandle handle)
	{
		return mTrailProxies.Get(handle.Handle);
	}

	/// Destroys a trail emitter proxy.
	/// TrailEmitter is deferred for deletion to avoid destroying
	/// GPU resources that may still be referenced by in-flight command buffers.
	public void DestroyTrailEmitter(TrailEmitterProxyHandle handle)
	{
		if (mTrailProxies.TryGet(handle.Handle, let proxy))
			proxy.Reset();
		mTrailProxies.Free(handle.Handle);
		mTrailsDirty = true;

		// Defer trail emitter deletion
		if (mTrailEmitters.GetAndRemove(handle) case .Ok(let pair))
		{
			var pending = PendingTrailDeletion();
			pending.Emitter = pair.value;
			pending.FramesRemaining = RenderConfig.FrameBufferCount + 1;
			mPendingTrailDeletions.Add(pending);
		}
	}

	/// Processes deferred trail emitter deletions. Call once per frame.
	public void ProcessDeferredTrailDeletions()
	{
		for (int32 i = (int32)mPendingTrailDeletions.Count - 1; i >= 0; i--)
		{
			var pending = ref mPendingTrailDeletions[i];
			pending.FramesRemaining--;
			if (pending.FramesRemaining <= 0)
			{
				delete pending.Emitter;
				mPendingTrailDeletions.RemoveAt(i);
			}
		}
	}

	/// Adds a trail point at the given world position.
	public void AddTrailPoint(TrailEmitterProxyHandle handle, Vector3 position, float width, Color color)
	{
		if (mTrailEmitters.TryGetValue(handle, let emitter))
			emitter.AddPoint(position, width, color);
	}

	/// Adds a trail point with distance filtering.
	public void AddTrailPointFiltered(TrailEmitterProxyHandle handle, Vector3 position, float width, Color color, float minDistance)
	{
		if (mTrailEmitters.TryGetValue(handle, let emitter))
			emitter.AddPointFiltered(position, width, color, minDistance);
	}

	/// Gets the TrailEmitter instance for a handle (used by ParticleFeature for rendering).
	public TrailEmitter GetTrailEmitterInstance(TrailEmitterProxyHandle handle)
	{
		if (mTrailEmitters.TryGetValue(handle, let emitter))
			return emitter;
		return null;
	}

	/// Iterates over all active trail emitters.
	public void ForEachTrailEmitter(ProxyCallback<TrailEmitterProxy> callback)
	{
		mTrailProxies.ForEach(callback);
	}
}

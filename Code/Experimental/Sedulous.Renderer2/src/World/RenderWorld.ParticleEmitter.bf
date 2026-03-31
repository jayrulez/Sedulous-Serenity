namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;

extension RenderWorld
{
	private ProxyPool<ParticleEmitterProxy> mParticleProxies = new .() ~ delete _;

	private bool mParticlesDirty = false;

	/// Gets the particle emitter proxy pool.
	public ProxyPool<ParticleEmitterProxy> ParticleProxies => mParticleProxies;

	/// Gets the number of active particle emitters.
	public int32 ParticleEmitterCount => mParticleProxies.ActiveCount;

	/// Whether any particles have changed.
	public bool ParticlesDirty => mParticlesDirty;

	/// Creates a new particle emitter proxy.
	/// CPUParticleEmitter is created lazily by ParticleFeature on first frame.
	public ParticleEmitterProxyHandle CreateParticleEmitter(ParticleSimulationBackend backend = .CPU, int32 maxParticles = 500)
	{
		let handle = mParticleProxies.Allocate();
		var proxy = mParticleProxies.Get(handle);
		*proxy = ParticleEmitterProxy.CreateDefault();
		proxy.Backend = backend;
		proxy.MaxParticles = (uint32)maxParticles;
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mParticlesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a particle emitter proxy by handle.
	public ParticleEmitterProxy* GetParticleEmitter(ParticleEmitterProxyHandle handle)
	{
		return mParticleProxies.Get(handle.Handle);
	}

	/// Gets a reference to a particle emitter proxy.
	public ref ParticleEmitterProxy GetParticleEmitterRef(ParticleEmitterProxyHandle handle)
	{
		return ref mParticleProxies.GetRef(handle.Handle);
	}

	/// Destroys a particle emitter proxy.
	/// CPU emitter buffers are deferred for deletion to avoid destroying
	/// GPU resources that may still be referenced by in-flight command buffers.
	public void DestroyParticleEmitter(ParticleEmitterProxyHandle handle)
	{
		if (mParticleProxies.TryGet(handle.Handle, let proxy))
		{
			if (proxy.CPUEmitter != null)
			{
				// Defer deletion until in-flight frames have completed
				var pending = PendingEmitterDeletion();
				pending.Emitter = proxy.CPUEmitter;
				pending.FramesRemaining = RenderConfig.FrameBufferCount + 1;
				mPendingEmitterDeletions.Add(pending);
				proxy.CPUEmitter = null;
			}
			proxy.Reset();
		}
		mParticleProxies.Free(handle.Handle);
		mParticlesDirty = true;
	}

	/// Sets particle emitter position.
	public void SetParticleEmitterPosition(ParticleEmitterProxyHandle handle, Vector3 position)
	{
		if (let proxy = mParticleProxies.Get(handle.Handle))
		{
			proxy.SetPosition(position);
			mParticlesDirty = true;
		}
	}

	/// Iterates over all active particle emitters.
	public void ForEachParticleEmitter(ProxyCallback<ParticleEmitterProxy> callback)
	{
		mParticleProxies.ForEach(callback);
	}
}

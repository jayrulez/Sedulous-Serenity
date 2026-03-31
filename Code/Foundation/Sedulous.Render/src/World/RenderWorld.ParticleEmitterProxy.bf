using Sedulous.Core.Mathematics;
namespace Sedulous.Render;

extension RenderWorld
{
	private ProxyPool<ParticleEmitterProxy> mParticleProxies = new .() ~ delete _;

	// ========================================================================
	// Particle API
	// ========================================================================

	/// Creates a new particle emitter proxy.
	/// CPUParticleEmitter is owned by ParticleFeature, not the proxy.
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
	/// CPUParticleEmitter cleanup is handled by ParticleFeature via stale handle detection.
	public void DestroyParticleEmitter(ParticleEmitterProxyHandle handle)
	{
		if (mParticleProxies.TryGet(handle.Handle, let proxy))
			proxy.Reset();
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

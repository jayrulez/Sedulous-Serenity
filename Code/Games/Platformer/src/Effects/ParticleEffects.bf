namespace Platformer.Effects;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Render;
using Sedulous.Logging.Abstractions;

/// Manages particle effects for the platformer game.
/// Creates one-shot burst effects for coin collect, dust, and enemy death.
class ParticleEffects
{
	private RenderWorld mWorld;
	private IDevice mDevice;
	private ILogger mLogger;

	// Active effect handles with timers
	private List<ParticleEmitterProxyHandle> mActiveHandles = new .() ~ delete _;
	private List<float> mEffectTimers = new .() ~ delete _;

	public this(RenderWorld world, IDevice device, ILogger logger)
	{
		mWorld = world;
		mDevice = device;
		mLogger = logger;
	}

	/// Spawn coin collect burst at position.
	public void SpawnCoinCollect(Vector3 position)
	{
		if (mWorld == null || mDevice == null)
		{
			mLogger?.LogWarning("Cannot spawn coin effect: world or device is null");
			return;
		}
		var emitter = CreateCoinCollectEmitter(position);
		SpawnEffect(emitter, 0.8f);
	}

	/// Spawn dust puff at position (landing/jumping).
	public void SpawnDust(Vector3 position)
	{
		if (mWorld == null || mDevice == null)
		{
			mLogger?.LogWarning("Cannot spawn dust effect: world or device is null");
			return;
		}
		var emitter = CreateDustEmitter(position);
		SpawnEffect(emitter, 0.6f);
	}

	/// Spawn enemy death effect at position.
	public void SpawnEnemyDeath(Vector3 position)
	{
		if (mWorld == null || mDevice == null)
		{
			mLogger?.LogWarning("Cannot spawn enemy death effect: world or device is null");
			return;
		}
		var emitter = CreateEnemyDeathEmitter(position);
		SpawnEffect(emitter, 0.8f);
	}

	/// Update particle systems and clean up expired effects.
	public void Update(float dt)
	{
		for (int i = mActiveHandles.Count - 1; i >= 0; i--)
		{
			mEffectTimers[i] -= dt;
			if (mEffectTimers[i] <= 0)
			{
				let handle = mActiveHandles[i];
				mWorld.DestroyParticleEmitter(handle);
				mActiveHandles.RemoveAt(i);
				mEffectTimers.RemoveAt(i);
			}
		}
	}

	/// Clean up emitters.
	public void Clear()
	{
		if (mActiveHandles.Count > 0)
			mLogger?.LogDebug("Clearing {} active particle effects", mActiveHandles.Count);

		for (let handle in mActiveHandles)
			mWorld.DestroyParticleEmitter(handle);
		mActiveHandles.Clear();
		mEffectTimers.Clear();
	}

	// === Effect creation ===

	private void SpawnEffect(ParticleEmitterProxy emitterConfig, float duration)
	{
		let maxParticles = Math.Max((int32)emitterConfig.BurstCount * 2, 60);
		let handle = mWorld.CreateParticleEmitter(mDevice, .CPU, maxParticles);

		if (let proxy = mWorld.GetParticleEmitter(handle))
		{
			let cpuEmitter = proxy.CPUEmitter;
			*proxy = emitterConfig;
			proxy.Backend = .CPU;
			proxy.MaxParticles = (uint32)maxParticles;
			proxy.CPUEmitter = cpuEmitter;
		}
		else
		{
			mLogger?.LogWarning("Failed to get particle emitter proxy after creation");
		}

		mActiveHandles.Add(handle);
		mEffectTimers.Add(duration);
	}

	private ParticleEmitterProxy CreateCoinCollectEmitter(Vector3 position)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 0;
		emitter.BurstCount = 15;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 1;
		emitter.ParticleLifetime = 0.6f;
		emitter.StartSize = .(0.05f, 0.1f);
		emitter.EndSize = .(0.01f, 0.02f);
		emitter.StartColor = .(1.0f, 0.85f, 0.2f, 1.0f);
		emitter.EndColor = .(1.0f, 0.6f, 0.0f, 0.0f);
		emitter.InitialVelocity = .(0, 3.0f, 0);
		emitter.VelocityRandomness = .(2.0f, 2.0f, 1.0f);
		emitter.GravityMultiplier = -0.5f;
		emitter.Drag = 1.5f;
		emitter.LifetimeVarianceMin = 0.3f;
		emitter.LifetimeVarianceMax = 1.0f;
		return emitter;
	}

	private ParticleEmitterProxy CreateDustEmitter(Vector3 position)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Alpha;
		emitter.SpawnRate = 0;
		emitter.BurstCount = 8;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 1;
		emitter.ParticleLifetime = 0.4f;
		emitter.StartSize = .(0.1f, 0.2f);
		emitter.EndSize = .(0.3f, 0.4f);
		emitter.StartColor = .(0.7f, 0.6f, 0.5f, 0.6f);
		emitter.EndColor = .(0.7f, 0.6f, 0.5f, 0.0f);
		emitter.InitialVelocity = .(0, 0.5f, 0);
		emitter.VelocityRandomness = .(1.5f, 0.5f, 0.5f);
		emitter.GravityMultiplier = 0;
		emitter.Drag = 3.0f;
		emitter.LifetimeVarianceMin = 0.3f;
		emitter.LifetimeVarianceMax = 1.0f;
		return emitter;
	}

	private ParticleEmitterProxy CreateEnemyDeathEmitter(Vector3 position)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 0;
		emitter.BurstCount = 20;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 1;
		emitter.ParticleLifetime = 0.5f;
		emitter.StartSize = .(0.08f, 0.15f);
		emitter.EndSize = .(0.02f, 0.04f);
		emitter.StartColor = .(1.0f, 0.3f, 0.2f, 1.0f);
		emitter.EndColor = .(0.8f, 0.1f, 0.0f, 0.0f);
		emitter.InitialVelocity = .(0, 2.0f, 0);
		emitter.VelocityRandomness = .(3.0f, 3.0f, 1.0f);
		emitter.GravityMultiplier = -0.3f;
		emitter.Drag = 1.5f;
		emitter.LifetimeVarianceMin = 0.4f;
		emitter.LifetimeVarianceMax = 1.0f;
		return emitter;
	}
}

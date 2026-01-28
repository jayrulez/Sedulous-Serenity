namespace TowerDefense.Effects;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Render;
using Sedulous.RHI;
using TowerDefense.Data;

/// Manages particle effects for the game.
/// Creates one-shot burst effects for tower firing, enemy death, and projectile impacts.
/// Ported to Sedulous.Render particle system.
class ParticleEffects
{
	private RenderWorld mRenderWorld;
	private IDevice mDevice;
	private int32 mEffectCounter = 0;

	// Pool of active effect handles with timers
	private List<ParticleEmitterProxyHandle> mActiveHandles = new .() ~ delete _;
	private List<float> mEffectTimers = new .() ~ delete _;

	public this(RenderWorld renderWorld, IDevice device)
	{
		mRenderWorld = renderWorld;
		mDevice = device;
	}

	/// Spawns a tower muzzle flash effect at the given position.
	public void SpawnTowerFire(StringView towerName, Vector3 position, Vector3 direction)
	{
		var emitter = CreateTowerFireEmitter(towerName, position);
		emitter.Position = position;
		SpawnEffect(emitter, 0.5f);
	}

	/// Spawns an enemy death explosion effect.
	public void SpawnEnemyDeath(Vector3 position, Vector4 enemyColor)
	{
		var emitter = CreateEnemyDeathEmitter(position, enemyColor);
		SpawnEffect(emitter, 1.0f);
	}

	/// Spawns a projectile impact effect.
	public void SpawnProjectileHit(Vector3 position, Vector4 projectileColor)
	{
		Console.WriteLine($"SpawnProjectileHit at {position}");
		var emitter = CreateImpactEmitter(position, projectileColor);
		SpawnEffect(emitter, 0.5f);
	}

	/// Updates active effects and cleans up expired ones.
	public void Update(float deltaTime)
	{
		// Update timers and remove expired effects
		for (int i = mActiveHandles.Count - 1; i >= 0; i--)
		{
			mEffectTimers[i] -= deltaTime;
			if (mEffectTimers[i] <= 0)
			{
				let handle = mActiveHandles[i];
				// RenderWorld handles deferred deletion of CPUEmitter
				mRenderWorld.DestroyParticleEmitter(handle);
				mActiveHandles.RemoveAt(i);
				mEffectTimers.RemoveAt(i);
			}
		}
	}

	/// Clears all active effects.
	public void Clear()
	{
		for (let handle in mActiveHandles)
			mRenderWorld.DestroyParticleEmitter(handle);
		mActiveHandles.Clear();
		mEffectTimers.Clear();
	}

	// ==================== Effect Creation ====================

	private void SpawnEffect(ParticleEmitterProxy emitterConfig, float duration)
	{
		mEffectCounter++;

		// Create the emitter in RenderWorld
		let handle = mRenderWorld.CreateParticleEmitter();

		// Create CPUEmitter for CPU-based particle simulation
		// Use max particles based on burst count with some headroom
		let maxParticles = Math.Max((int32)emitterConfig.BurstCount * 2, 100);
		let cpuEmitter = new CPUParticleEmitter(mDevice, maxParticles);

		// Apply the configuration to the proxy and set CPUEmitter
		// RenderWorld handles deferred deletion of CPUEmitter when DestroyParticleEmitter is called
		if (let proxy = mRenderWorld.GetParticleEmitter(handle))
		{
			*proxy = emitterConfig;
			proxy.Backend = .CPU;
			proxy.MaxParticles = (uint32)maxParticles;
			proxy.CPUEmitter = cpuEmitter;
		}

		mActiveHandles.Add(handle);
		mEffectTimers.Add(duration);
	}

	// ==================== Tower Fire Effects ====================

	private ParticleEmitterProxy CreateTowerFireEmitter(StringView towerName, Vector3 position)
	{
		switch (towerName)
		{
		case "Cannon":
			return CreateCannonFlash(position);
		case "Archer":
			return CreateArcherTrail(position);
		case "Frost":
			return CreateFrostBurst(position);
		case "Mortar":
			return CreateMortarBlast(position);
		case "SAM":
			return CreateSAMTrail(position);
		default:
			return CreateCannonFlash(position);
		}
	}

	private ParticleEmitterProxy CreateCannonFlash(Vector3 position)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 0; // Burst only
		emitter.BurstCount = 30;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 1;
		emitter.ParticleLifetime = 0.3f;
		emitter.StartSize = .(0.2f, 0.2f);
		emitter.EndSize = .(0.0f, 0.0f);
		emitter.StartColor = .(1.0f, 0.86f, 0.39f, 1.0f);  // Bright yellow-orange
		emitter.EndColor = .(1.0f, 0.39f, 0.0f, 0.0f);     // Fade to transparent orange
		emitter.InitialVelocity = .(0, 2.0f, 0);
		emitter.VelocityRandomness = .(2.0f, 3.0f, 2.0f);
		emitter.GravityMultiplier = 0.3f;
		emitter.Drag = 2.0f;
		emitter.LifetimeVarianceMin = 0.3f;
		emitter.LifetimeVarianceMax = 1.0f;
		return emitter;
	}

	private ParticleEmitterProxy CreateArcherTrail(Vector3 position)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 0;
		emitter.BurstCount = 15;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 1;
		emitter.ParticleLifetime = 0.2f;
		emitter.StartSize = .(0.05f, 0.05f);
		emitter.EndSize = .(0.02f, 0.02f);
		emitter.StartColor = .(0.78f, 1.0f, 0.78f, 0.78f);  // Light green
		emitter.EndColor = .(0.39f, 0.78f, 0.39f, 0.0f);
		emitter.InitialVelocity = .(0, 1.5f, 0);
		emitter.VelocityRandomness = .(1.0f, 0.5f, 1.0f);
		emitter.Drag = 3.0f;
		emitter.LifetimeVarianceMin = 0.5f;
		emitter.LifetimeVarianceMax = 1.0f;
		return emitter;
	}

	private ParticleEmitterProxy CreateFrostBurst(Vector3 position)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 0;
		emitter.BurstCount = 40;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 1;
		emitter.ParticleLifetime = 0.5f;
		emitter.StartSize = .(0.1f, 0.1f);
		emitter.EndSize = .(0.15f, 0.15f);
		emitter.StartColor = .(0.59f, 0.86f, 1.0f, 1.0f);  // Ice blue
		emitter.EndColor = .(0.39f, 0.71f, 1.0f, 0.0f);
		emitter.InitialVelocity = .(0, 1.0f, 0);
		emitter.VelocityRandomness = .(2.0f, 1.0f, 2.0f);
		emitter.GravityMultiplier = -0.15f;
		emitter.Drag = 1.5f;
		emitter.LifetimeVarianceMin = 0.4f;
		emitter.LifetimeVarianceMax = 1.0f;
		emitter.ForceModules.TurbulenceStrength = 0.5f;
		emitter.ForceModules.TurbulenceFrequency = 2.0f;
		return emitter;
	}

	private ParticleEmitterProxy CreateMortarBlast(Vector3 position)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 0;
		emitter.BurstCount = 50;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 1;
		emitter.ParticleLifetime = 0.5f;
		emitter.StartSize = .(0.3f, 0.3f);
		emitter.EndSize = .(0.6f, 0.6f);
		emitter.StartColor = .(1.0f, 0.78f, 0.2f, 1.0f);   // Bright orange
		emitter.EndColor = .(0.39f, 0.2f, 0.0f, 0.0f);     // Dark smoke fade
		emitter.InitialVelocity = .(0, 4.0f, 0);
		emitter.VelocityRandomness = .(4.0f, 4.0f, 4.0f);
		emitter.GravityMultiplier = 0.5f;
		emitter.Drag = 1.0f;
		emitter.LifetimeVarianceMin = 0.4f;
		emitter.LifetimeVarianceMax = 1.0f;
		return emitter;
	}

	private ParticleEmitterProxy CreateSAMTrail(Vector3 position)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 0;
		emitter.BurstCount = 25;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 1;
		emitter.ParticleLifetime = 0.35f;
		emitter.StartSize = .(0.1f, 0.1f);
		emitter.EndSize = .(0.05f, 0.05f);
		emitter.StartColor = .(1.0f, 1.0f, 1.0f, 1.0f);  // White hot
		emitter.EndColor = .(0.78f, 0.39f, 0.2f, 0.0f);  // Orange fade
		emitter.InitialVelocity = .(0, 3.0f, 0);
		emitter.VelocityRandomness = .(2.0f, 1.0f, 2.0f);
		emitter.GravityMultiplier = 1.0f;
		emitter.Drag = 2.0f;
		emitter.LifetimeVarianceMin = 0.4f;
		emitter.LifetimeVarianceMax = 1.0f;
		return emitter;
	}

	// ==================== Enemy Death Effect ====================

	private ParticleEmitterProxy CreateEnemyDeathEmitter(Vector3 position, Vector4 color)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 0;
		emitter.BurstCount = 40;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 1;
		emitter.ParticleLifetime = 0.8f;
		emitter.StartSize = .(0.15f, 0.15f);
		emitter.EndSize = .(0.05f, 0.05f);
		emitter.StartColor = color;
		emitter.EndColor = .(color.X * 0.78f, color.Y * 0.78f, color.Z * 0.78f, 0.0f);
		emitter.InitialVelocity = .Zero;
		emitter.VelocityRandomness = .(4.0f, 4.0f, 4.0f);
		emitter.GravityMultiplier = -0.8f;
		emitter.Drag = 1.5f;
		emitter.LifetimeVarianceMin = 0.4f;
		emitter.LifetimeVarianceMax = 1.0f;
		emitter.ForceModules.TurbulenceStrength = 1.0f;
		emitter.ForceModules.TurbulenceFrequency = 1.5f;
		return emitter;
	}

	// ==================== Projectile Impact Effect ====================

	private ParticleEmitterProxy CreateImpactEmitter(Vector3 position, Vector4 color)
	{
		var emitter = ParticlePresets.Sparks(position);
		emitter.BurstCount = 20;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 1;
		emitter.SpawnRate = 0;  // Burst only
		emitter.StartColor = color;
		emitter.EndColor = .(color.X, color.Y, color.Z, 0.0f);
		emitter.ParticleLifetime = 0.3f;
		emitter.LifetimeVarianceMin = 0.3f;
		emitter.LifetimeVarianceMax = 1.0f;
		return emitter;
	}
}

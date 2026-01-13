namespace TowerDefense.Effects;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Renderer;
using TowerDefense.Data;

/// Manages particle effects for the game.
/// Creates one-shot burst effects for tower firing, enemy death, and projectile impacts.
class ParticleEffects
{
	private Scene mScene;
	private int32 mEffectCounter = 0;

	// Pool of reusable effect entities (to avoid constant creation/destruction)
	private List<Entity> mActiveEffects = new .() ~ delete _;
	private List<float> mEffectTimers = new .() ~ delete _;

	public this(Scene scene)
	{
		mScene = scene;
	}

	/// Spawns a tower muzzle flash effect at the given position.
	public void SpawnTowerFire(StringView towerName, Vector3 position, Vector3 direction)
	{
		ParticleEmitterConfig config = null;

		switch (towerName)
		{
		case "Cannon":
			config = CreateCannonFlash();
		case "Archer":
			config = CreateArcherTrail();
		case "Frost":
			config = CreateFrostBurst();
		case "Mortar":
			config = CreateMortarBlast();
		case "SAM":
			config = CreateSAMTrail();
		default:
			config = CreateCannonFlash();
		}

		if (config != null)
			SpawnEffect(position, config, 0.5f);
	}

	/// Spawns an enemy death explosion effect.
	public void SpawnEnemyDeath(Vector3 position, Vector4 enemyColor)
	{
		let config = CreateEnemyDeathExplosion(enemyColor);
		SpawnEffect(position, config, 1.0f);
	}

	/// Spawns a projectile impact effect.
	public void SpawnProjectileHit(Vector3 position, Vector4 projectileColor)
	{
		let config = CreateImpactSparks(projectileColor);
		SpawnEffect(position, config, 0.5f);
	}

	/// Updates active effects and cleans up expired ones.
	public void Update(float deltaTime)
	{
		// Update timers and remove expired effects
		for (int i = mActiveEffects.Count - 1; i >= 0; i--)
		{
			mEffectTimers[i] -= deltaTime;
			if (mEffectTimers[i] <= 0)
			{
				let entity = mActiveEffects[i];
				mScene.DestroyEntity(entity.Id);
				mActiveEffects.RemoveAt(i);
				mEffectTimers.RemoveAt(i);
			}
		}
	}

	/// Clears all active effects.
	public void Clear()
	{
		for (let entity in mActiveEffects)
			mScene.DestroyEntity(entity.Id);
		mActiveEffects.Clear();
		mEffectTimers.Clear();
	}

	// ==================== Effect Creation ====================

	private void SpawnEffect(Vector3 position, ParticleEmitterConfig config, float duration)
	{
		mEffectCounter++;
		let entityName = scope $"Effect_{mEffectCounter}";
		let entity = mScene.CreateEntity(entityName);
		entity.Transform.SetPosition(position);

		let emitter = new ParticleEmitterComponent(config);
		entity.AddComponent(emitter);

		// Trigger burst and stop continuous emission
		emitter.Burst((int32)config.EmissionRate);

		mActiveEffects.Add(entity);
		mEffectTimers.Add(duration);
	}

	// ==================== Tower Fire Effects ====================

	private ParticleEmitterConfig CreateCannonFlash()
	{
		let config = new ParticleEmitterConfig();
		config.MaxParticles = 30;
		config.EmissionRate = 30;
		config.Lifetime = .(0.1f, 0.3f);
		config.InitialSpeed = .(2.0f, 5.0f);
		config.InitialSize = .(0.2f, 0.4f);
		config.SetConeEmission(25);
		config.BlendMode = .Additive;
		config.Gravity = .(0, 1, 0);
		config.Drag = 2.0f;
		config.SetColorOverLifetime(
			.(255, 220, 100, 255),  // Bright yellow-orange
			.(255, 100, 0, 0)       // Fade to transparent orange
		);
		config.SetSizeOverLifetime(1.0f, 0.0f);
		return config;
	}

	private ParticleEmitterConfig CreateArcherTrail()
	{
		let config = new ParticleEmitterConfig();
		config.MaxParticles = 15;
		config.EmissionRate = 15;
		config.Lifetime = .(0.1f, 0.2f);
		config.InitialSpeed = .(1.0f, 2.0f);
		config.InitialSize = .(0.05f, 0.1f);
		config.SetConeEmission(10);
		config.BlendMode = .Additive;
		config.Drag = 3.0f;
		config.SetColorOverLifetime(
			.(200, 255, 200, 200),  // Light green
			.(100, 200, 100, 0)     // Fade
		);
		return config;
	}

	private ParticleEmitterConfig CreateFrostBurst()
	{
		let config = new ParticleEmitterConfig();
		config.MaxParticles = 40;
		config.EmissionRate = 40;
		config.Lifetime = .(0.2f, 0.5f);
		config.InitialSpeed = .(1.0f, 3.0f);
		config.InitialSize = .(0.1f, 0.25f);
		config.SetSphereEmission(0.3f);
		config.BlendMode = .Additive;
		config.Gravity = .(0, -0.5f, 0);
		config.Drag = 1.5f;
		config.SetColorOverLifetime(
			.(150, 220, 255, 255),  // Ice blue
			.(100, 180, 255, 0)     // Fade to transparent
		);
		config.SetSizeOverLifetime(1.0f, 1.5f);
		config.AddTurbulence(0.5f, 2.0f);
		return config;
	}

	private ParticleEmitterConfig CreateMortarBlast()
	{
		let config = new ParticleEmitterConfig();
		config.MaxParticles = 50;
		config.EmissionRate = 50;
		config.Lifetime = .(0.2f, 0.5f);
		config.InitialSpeed = .(3.0f, 8.0f);
		config.InitialSize = .(0.3f, 0.6f);
		config.SetSphereEmission(0.2f);
		config.BlendMode = .Additive;
		config.Gravity = .(0, 2, 0);
		config.Drag = 1.0f;
		config.SetColorOverLifetime(
			.(255, 200, 50, 255),   // Bright orange
			.(100, 50, 0, 0)        // Dark smoke fade
		);
		config.SetSizeOverLifetime(1.0f, 2.0f);
		return config;
	}

	private ParticleEmitterConfig CreateSAMTrail()
	{
		let config = new ParticleEmitterConfig();
		config.MaxParticles = 25;
		config.EmissionRate = 25;
		config.Lifetime = .(0.15f, 0.35f);
		config.InitialSpeed = .(2.0f, 4.0f);
		config.InitialSize = .(0.1f, 0.2f);
		config.SetConeEmission(8);
		config.BlendMode = .Additive;
		config.Gravity = .(0, 3, 0);
		config.Drag = 2.0f;
		config.SetColorOverLifetime(
			.(255, 255, 255, 255),  // White hot
			.(200, 100, 50, 0)      // Orange fade
		);
		return config;
	}

	// ==================== Enemy Death Effect ====================

	private ParticleEmitterConfig CreateEnemyDeathExplosion(Vector4 color)
	{
		let config = new ParticleEmitterConfig();
		config.MaxParticles = 40;
		config.EmissionRate = 40;
		config.Lifetime = .(0.3f, 0.8f);
		config.InitialSpeed = .(2.0f, 6.0f);
		config.InitialSize = .(0.15f, 0.35f);
		config.SetSphereEmission(0.3f);
		config.BlendMode = .Additive;
		config.Gravity = .(0, -3, 0);
		config.Drag = 1.5f;

		// Use enemy color for the explosion
		let startColor = Color(
			(uint8)(color.X * 255),
			(uint8)(color.Y * 255),
			(uint8)(color.Z * 255),
			255
		);
		let endColor = Color(
			(uint8)(color.X * 200),
			(uint8)(color.Y * 200),
			(uint8)(color.Z * 200),
			0
		);
		config.SetColorOverLifetime(startColor, endColor);
		config.SetSizeOverLifetime(1.0f, 0.2f);
		config.AddTurbulence(1.0f, 1.5f);
		return config;
	}

	// ==================== Projectile Impact Effect ====================

	private ParticleEmitterConfig CreateImpactSparks(Vector4 color)
	{
		let config = new ParticleEmitterConfig();
		config.MaxParticles = 20;
		config.EmissionRate = 20;
		config.Lifetime = .(0.1f, 0.3f);
		config.InitialSpeed = .(3.0f, 8.0f);
		config.InitialSize = .(0.05f, 0.12f);
		config.SetSphereEmission(0.1f);
		config.BlendMode = .Additive;
		config.Gravity = .(0, -8, 0);
		config.Drag = 2.0f;

		// Use projectile color for sparks
		let startColor = Color(
			(uint8)(color.X * 255),
			(uint8)(color.Y * 255),
			(uint8)(color.Z * 255),
			255
		);
		let endColor = Color(
			(uint8)(color.X * 255),
			(uint8)(color.Y * 255),
			(uint8)(color.Z * 255),
			0
		);
		config.SetColorOverLifetime(startColor, endColor);
		config.SetSizeOverLifetime(1.0f, 0.0f);
		return config;
	}
}

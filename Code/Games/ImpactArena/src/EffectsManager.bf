namespace ImpactArena;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Render;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;

struct ActiveEffect
{
	public EntityId Entity;
	public float TimeRemaining;
}

class EffectsManager
{
	private Scene mScene;
	private RenderSceneModule mRenderModule;
	private List<ActiveEffect> mActiveEffects = new .() ~ delete _;

	public void Initialize(Scene scene, RenderSceneModule renderModule)
	{
		mScene = scene;
		mRenderModule = renderModule;
	}

	public void Update(float dt)
	{
		for (int32 i = (int32)mActiveEffects.Count - 1; i >= 0; i--)
		{
			var effect = ref mActiveEffects[i];
			effect.TimeRemaining -= dt;
			if (effect.TimeRemaining <= 0)
			{
				mScene.DestroyEntity(effect.Entity);
				mActiveEffects.RemoveAt(i);
			}
		}
	}

	public void SpawnDeathEffect(Vector3 position, EnemyType type)
	{
		switch (type)
		{
		case .Grunt:
			SpawnBurst(position, 40, .(1.0f, 0.5f, 0.1f, 1.0f), .(1.0f, 0.2f, 0.0f, 0.0f),
				.(2.0f, 2.0f, 2.0f), 1.5f, 1.0f);
		case .Brute:
			SpawnBurst(position, 80, .(0.3f, 1.0f, 0.3f, 1.0f), .(0.1f, 0.6f, 0.0f, 0.0f),
				.(3.0f, 3.0f, 3.0f), 2.0f, 1.5f);
		case .Dasher:
			SpawnBurst(position, 50, .(1.0f, 0.9f, 0.2f, 1.0f), .(0.8f, 0.5f, 0.0f, 0.0f),
				.(2.5f, 2.5f, 2.5f), 1.5f, 1.2f);
		}
	}

	public void SpawnHitEffect(Vector3 position)
	{
		SpawnBurst(position, 20, .(1.0f, 0.2f, 0.2f, 1.0f), .(1.0f, 0.0f, 0.0f, 0.0f),
			.(1.5f, 1.5f, 1.5f), 0.8f, 0.6f);
	}

	public void SpawnPickupEffect(Vector3 position, PowerUpType type)
	{
		Vector4 startColor;
		Vector4 endColor;

		switch (type)
		{
		case .HealthPack:
			startColor = .(0.2f, 1.0f, 0.4f, 1.0f);
			endColor = .(0.0f, 0.8f, 0.2f, 0.0f);
		case .SpeedBoost:
			startColor = .(0.2f, 0.9f, 1.0f, 1.0f);
			endColor = .(0.0f, 0.5f, 1.0f, 0.0f);
		case .Shockwave:
			startColor = .(0.8f, 0.3f, 1.0f, 1.0f);
			endColor = .(0.5f, 0.0f, 1.0f, 0.0f);
		case .EMP:
			startColor = .(1.0f, 1.0f, 0.4f, 1.0f);
			endColor = .(1.0f, 0.8f, 0.0f, 0.0f);
		}

		SpawnBurst(position, 60, startColor, endColor,
			.(3.0f, 3.0f, 3.0f), 1.2f, 1.0f);
	}

	public void SpawnShockwaveEffect(Vector3 position)
	{
		// Inner bright ring - fast expanding
		SpawnExpandingRing(position, 80,
			.(1.0f, 0.6f, 1.0f, 1.0f), .(0.8f, 0.2f, 1.0f, 0.0f),
			12.0f, 0.5f, .(0.4f, 0.4f), .(0.15f, 0.15f));

		// Outer softer ring - slower
		SpawnExpandingRing(position, 60,
			.(0.7f, 0.4f, 1.0f, 0.8f), .(0.4f, 0.1f, 0.8f, 0.0f),
			8.0f, 0.7f, .(0.3f, 0.3f), .(0.08f, 0.08f));

		// Central flash burst
		SpawnBurst(position, 30, .(1.0f, 1.0f, 1.0f, 1.0f), .(0.8f, 0.4f, 1.0f, 0.0f),
			.(2.0f, 3.0f, 2.0f), 0.4f, 0.5f);
	}

	public void SpawnEMPEffect(Vector3 position)
	{
		// Multiple expanding rings for EMP wave effect
		// Ring 1 - bright yellow core, fast
		SpawnExpandingRing(position, 100,
			.(1.0f, 1.0f, 0.5f, 1.0f), .(1.0f, 0.8f, 0.0f, 0.0f),
			18.0f, 0.6f, .(0.5f, 0.5f), .(0.2f, 0.2f));

		// Ring 2 - orange middle ring, medium speed
		SpawnExpandingRing(position, 80,
			.(1.0f, 0.7f, 0.3f, 0.9f), .(1.0f, 0.4f, 0.0f, 0.0f),
			14.0f, 0.8f, .(0.4f, 0.4f), .(0.12f, 0.12f));

		// Ring 3 - outer red ring, slower
		SpawnExpandingRing(position, 60,
			.(1.0f, 0.5f, 0.2f, 0.7f), .(0.8f, 0.2f, 0.0f, 0.0f),
			10.0f, 1.0f, .(0.35f, 0.35f), .(0.08f, 0.08f));

		// Central flash
		SpawnBurst(position, 40, .(1.0f, 1.0f, 1.0f, 1.0f), .(1.0f, 0.9f, 0.3f, 0.0f),
			.(3.0f, 4.0f, 3.0f), 0.5f, 0.6f);
	}

	public void SpawnPlayerDeathEffect(Vector3 position)
	{
		// Big blue explosion
		SpawnBurst(position, 120, .(0.3f, 0.6f, 1.0f, 1.0f), .(0.1f, 0.2f, 1.0f, 0.0f),
			.(5.0f, 4.0f, 5.0f), 2.0f, 2.0f);
		// Secondary white flash
		SpawnBurst(position, 40, .(1.0f, 1.0f, 1.0f, 1.0f), .(0.5f, 0.7f, 1.0f, 0.0f),
			.(2.0f, 3.0f, 2.0f), 1.0f, 1.5f);
	}

	private void SpawnBurst(Vector3 position, int32 count, Vector4 startColor, Vector4 endColor,
		Vector3 velocityRandomness, float lifetime, float effectDuration)
	{
		let entity = mScene.CreateEntity();
		var transform = mScene.GetTransform(entity);
		transform.Position = position;
		mScene.SetTransform(entity, transform);

		let handle = mRenderModule.CreateCPUParticleEmitter(entity, count + 10);
		if (handle.IsValid)
		{
			if (let proxy = mRenderModule.GetParticleEmitterProxy(entity))
			{
				proxy.BlendMode = .Additive;
				proxy.SpawnRate = 0;
				proxy.BurstCount = count;
				proxy.BurstInterval = 0;
				proxy.BurstCycles = 1;
				proxy.ParticleLifetime = lifetime;
				proxy.StartSize = .(0.06f, 0.06f);
				proxy.EndSize = .(0.01f, 0.01f);
				proxy.StartColor = startColor;
				proxy.EndColor = endColor;
				// Top-down game: burst mostly in XZ plane
				proxy.InitialVelocity = .(0, 0, 0);
				proxy.VelocityRandomness = .(velocityRandomness.X, velocityRandomness.Y * 0.2f, velocityRandomness.Z);
				proxy.GravityMultiplier = 0;
				proxy.Drag = 0.5f;
				proxy.LifetimeVarianceMin = 0.5f;
				proxy.LifetimeVarianceMax = 1.0f;
				// Horizontal billboard for top-down view
				proxy.RenderMode = .HorizontalBillboard;
				proxy.IsEnabled = true;
				proxy.IsEmitting = true;

				proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.5f);
			}
		}

		var effect = ActiveEffect();
		effect.Entity = entity;
		effect.TimeRemaining = lifetime + effectDuration;
		mActiveEffects.Add(effect);
	}

	/// Spawns an expanding ring of particles that move outward from the center.
	private void SpawnExpandingRing(Vector3 position, int32 count, Vector4 startColor, Vector4 endColor,
		float outwardSpeed, float lifetime, Vector2 startSize, Vector2 endSize)
	{
		let entity = mScene.CreateEntity();
		var transform = mScene.GetTransform(entity);
		transform.Position = position;
		mScene.SetTransform(entity, transform);

		let handle = mRenderModule.CreateCPUParticleEmitter(entity, count + 10);
		if (handle.IsValid)
		{
			if (let proxy = mRenderModule.GetParticleEmitterProxy(entity))
			{
				proxy.BlendMode = .Additive;
				proxy.SpawnRate = 0;
				proxy.BurstCount = count;
				proxy.BurstInterval = 0;
				proxy.BurstCycles = 1;
				proxy.ParticleLifetime = lifetime;
				proxy.StartSize = startSize;
				proxy.EndSize = endSize;
				proxy.StartColor = startColor;
				proxy.EndColor = endColor;

				// Top-down game: expand in XZ plane only
				proxy.InitialVelocity = .(0, 0, 0);
				proxy.VelocityRandomness = .(outwardSpeed * 0.5f, 0, outwardSpeed * 0.5f);

				// Use radial force module to push particles outward
				proxy.ForceModules.RadialForce = outwardSpeed * 3.0f;
				// Add turbulence for wavy effect
				proxy.ForceModules.TurbulenceStrength = outwardSpeed * 1.5f;
				proxy.ForceModules.TurbulenceFrequency = 3.0f;
				proxy.ForceModules.TurbulenceSpeed = 8.0f;

				proxy.GravityMultiplier = 0;
				proxy.Drag = 0.2f;
				proxy.LifetimeVarianceMin = 0.9f;
				proxy.LifetimeVarianceMax = 1.0f;
				// Horizontal billboard for top-down view (flat expanding ring)
				proxy.RenderMode = .HorizontalBillboard;
				proxy.IsEnabled = true;
				proxy.IsEmitting = true;
				proxy.AlphaOverLifetime = .FadeOut(0.8f, 0.2f);
			}
		}

		var effect = ActiveEffect();
		effect.Entity = entity;
		effect.TimeRemaining = lifetime + 0.5f;
		mActiveEffects.Add(effect);
	}

	public void ClearAll()
	{
		for (let effect in mActiveEffects)
			mScene.DestroyEntity(effect.Entity);
		mActiveEffects.Clear();
	}
}

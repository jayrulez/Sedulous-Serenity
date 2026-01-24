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
				proxy.InitialVelocity = .(0, 1.0f, 0);
				proxy.VelocityRandomness = velocityRandomness;
				proxy.GravityMultiplier = 0.8f;
				proxy.Drag = 0.5f;
				proxy.LifetimeVarianceMin = 0.5f;
				proxy.LifetimeVarianceMax = 1.0f;
				proxy.RenderMode = .StretchedBillboard;
				proxy.StretchFactor = 1.5f;
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

	public void ClearAll()
	{
		for (let effect in mActiveEffects)
			mScene.DestroyEntity(effect.Entity);
		mActiveEffects.Clear();
	}
}

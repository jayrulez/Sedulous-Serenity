namespace ImpactArena;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Resources;
using Sedulous.Materials;

enum PowerUpType
{
	HealthPack,
	SpeedBoost,
	Shockwave,
	EMP
}

struct ActivePowerUp
{
	public EntityId Entity;
	public PowerUpType Type;
	public float TimeRemaining;
	public float BobPhase;
	public Vector3 BasePosition;
}

class PowerUpManager
{
	private const float SpawnInterval = 15.0f;
	private const float DespawnTime = 10.0f;
	private const float BobSpeed = 3.0f;
	private const float BobHeight = 0.3f;
	private const float PickupRadius = 1.2f;

	private Scene mScene;
	private RenderSceneModule mRenderModule;
	private StaticMeshResource mSphereResource;
	private MaterialInstance mHealthMat;
	private MaterialInstance mSpeedMat;
	private MaterialInstance mShockMat;
	private MaterialInstance mEmpMat;
	private Random mRandom = new .() ~ delete _;

	private ActivePowerUp? mActivePowerUp = null;
	private float mSpawnTimer = 10.0f; // First spawn after 10s

	public void Initialize(Scene scene, RenderSceneModule renderModule, StaticMeshResource sphereResource,
		MaterialInstance healthMat, MaterialInstance speedMat, MaterialInstance shockMat, MaterialInstance empMat)
	{
		mScene = scene;
		mRenderModule = renderModule;
		mSphereResource = sphereResource;
		mHealthMat = healthMat;
		mSpeedMat = speedMat;
		mShockMat = shockMat;
		mEmpMat = empMat;
	}

	public void Update(float dt)
	{
		if (mActivePowerUp.HasValue)
		{
			var powerUp = mActivePowerUp.Value;
			powerUp.TimeRemaining -= dt;
			powerUp.BobPhase += dt * BobSpeed;

			// Bob animation
			let bobY = powerUp.BasePosition.Y + Math.Sin(powerUp.BobPhase) * BobHeight;
			var transform = mScene.GetTransform(powerUp.Entity);
			transform.Position = .(powerUp.BasePosition.X, bobY, powerUp.BasePosition.Z);
			mScene.SetTransform(powerUp.Entity, transform);

			if (powerUp.TimeRemaining <= 0)
			{
				DestroyPowerUp();
				return;
			}

			mActivePowerUp = powerUp;
		}
		else
		{
			mSpawnTimer -= dt;
			if (mSpawnTimer <= 0)
			{
				SpawnRandom();
				mSpawnTimer = SpawnInterval;
			}
		}
	}

	/// Checks if the player is close enough to pick up the power-up.
	/// canStoreMore indicates whether the player has room for storable pickups.
	/// Returns the type if picked up, null otherwise.
	public PowerUpType? CheckPickup(Vector3 playerPos, bool canStoreMore)
	{
		if (!mActivePowerUp.HasValue)
			return null;

		let powerUp = mActivePowerUp.Value;
		let toPlayer = playerPos - powerUp.BasePosition;
		let dist = Vector3(toPlayer.X, 0, toPlayer.Z).Length();

		if (dist < PickupRadius)
		{
			// Don't pick up storable items if inventory is full
			if (powerUp.Type != .HealthPack && !canStoreMore)
				return null;

			let type = powerUp.Type;
			DestroyPowerUp();
			return type;
		}

		return null;
	}

	private void SpawnRandom()
	{
		// Pick random type (EMP is rare)
		let roll = (float)mRandom.NextDouble();
		PowerUpType type;
		if (roll < 0.35f)
			type = .HealthPack;
		else if (roll < 0.6f)
			type = .SpeedBoost;
		else if (roll < 0.9f)
			type = .Shockwave;
		else
			type = .EMP;

		// Pick random position within arena (not too close to edges)
		let margin = 2.0f;
		let range = Arena.HalfSize - margin;
		let x = ((float)mRandom.NextDouble() - 0.5f) * 2.0f * range;
		let z = ((float)mRandom.NextDouble() - 0.5f) * 2.0f * range;
		let pos = Vector3(x, 0.5f, z);

		// Create entity
		let entity = mScene.CreateEntity();
		var transform = mScene.GetTransform(entity);
		transform.Position = pos;
		transform.Scale = .(0.6f, 0.6f, 0.6f);
		mScene.SetTransform(entity, transform);

		MaterialInstance mat;
		switch (type)
		{
		case .HealthPack: mat = mHealthMat;
		case .SpeedBoost: mat = mSpeedMat;
		case .Shockwave: mat = mShockMat;
		case .EMP: mat = mEmpMat;
		}

		mScene.SetComponent<MeshRendererComponent>(entity, .Default);
		var comp = mScene.GetComponent<MeshRendererComponent>(entity);
		comp.Mesh = ResourceHandle<StaticMeshResource>(mSphereResource);
		comp.Material = mat;

		// Ambient glow particles
		Vector4 glowColor;
		switch (type)
		{
		case .HealthPack: glowColor = .(0.2f, 1.0f, 0.4f, 1.0f);
		case .SpeedBoost: glowColor = .(0.2f, 0.9f, 1.0f, 1.0f);
		case .Shockwave: glowColor = .(0.8f, 0.3f, 1.0f, 1.0f);
		case .EMP: glowColor = .(1.0f, 1.0f, 0.3f, 1.0f);
		}

		let emitterHandle = mRenderModule.CreateCPUParticleEmitter(entity, 48);
		if (emitterHandle.IsValid)
		{
			if (let proxy = mRenderModule.GetParticleEmitterProxy(entity))
			{
				proxy.BlendMode = .Additive;
				proxy.SpawnRate = 20;
				proxy.ParticleLifetime = 1.5f;
				proxy.StartSize = .(0.4f, 0.4f);
				proxy.EndSize = .(0.1f, 0.1f);
				proxy.StartColor = glowColor;
				proxy.EndColor = .(glowColor.X * 0.5f, glowColor.Y * 0.5f, glowColor.Z * 0.5f, 0.0f);
				proxy.InitialVelocity = .(0, 0.5f, 0);
				proxy.VelocityRandomness = .(2.0f, 0.5f, 2.0f);
				proxy.GravityMultiplier = 0;
				proxy.Drag = 1.2f;
				proxy.LifetimeVarianceMin = 0.5f;
				proxy.LifetimeVarianceMax = 1.0f;
				proxy.IsEnabled = true;
				proxy.IsEmitting = true;
				proxy.AlphaOverLifetime = .FadeOut(1.0f, 0.3f);
			}
		}

		var powerUp = ActivePowerUp();
		powerUp.Entity = entity;
		powerUp.Type = type;
		powerUp.TimeRemaining = DespawnTime;
		powerUp.BobPhase = 0;
		powerUp.BasePosition = pos;
		mActivePowerUp = powerUp;
	}

	private void DestroyPowerUp()
	{
		if (mActivePowerUp.HasValue)
		{
			mScene.DestroyEntity(mActivePowerUp.Value.Entity);
			mActivePowerUp = null;
		}
	}

	public void ClearAll()
	{
		DestroyPowerUp();
		mSpawnTimer = 10.0f;
	}
}

namespace ImpactArena;

using System;
using Sedulous.Mathematics;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Physics;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;
using Sedulous.Physics;

class Player
{
	public const float Radius = 0.5f;
	public const float MoveForce = 3000.0f; // Scaled for dt multiplication (slightly boosted for responsiveness)
	public const float DashImpulse = 20.0f;
	public const float BaseDashCooldown = 1.5f;
	public const float MinDashCooldown = 0.8f; // Cap so player doesn't get too powerful
	public const float DashCooldownReductionPerWave = 0.05f;
	public const float DashSpeedThreshold = 8.0f;
	public const float MaxHealth = 100.0f;
	public const float DamagePerHit = 10.0f;
	public const float InvulnerabilityTime = 0.5f;

	private Scene mScene;
	private PhysicsSceneModule mPhysicsModule;
	private EntityId mEntity;

	private float mHealth = MaxHealth;
	private float mDashTimer = 0.0f;
	private float mInvulnTimer = 0.0f;
	private float mSpeedBoostTimer = 0.0f;
	private Vector3 mLastMoveDir = .(0, 0, 1);
	private bool mIsDashing = false;
	private int32 mCurrentWave = 1;

	public EntityId Entity => mEntity;
	public float Health => mHealth;
	public float HealthPercent => mHealth / MaxHealth;
	public float EffectiveDashCooldown => Math.Max(MinDashCooldown, BaseDashCooldown - (mCurrentWave - 1) * DashCooldownReductionPerWave);
	public float DashCooldownPercent => Math.Clamp(1.0f - mDashTimer / EffectiveDashCooldown, 0, 1);
	public bool IsDashing => mIsDashing;
	public bool IsAlive => mHealth > 0;
	public bool IsInvulnerable => mInvulnTimer > 0;
	public float InvulnTimer => mInvulnTimer;
	public bool HasSpeedBoost => mSpeedBoostTimer > 0;
	private float SpeedMultiplier => mSpeedBoostTimer > 0 ? 2.0f : 1.0f;

	public Vector3 Position
	{
		get => mScene.GetTransform(mEntity).Position;
	}

	public float Speed
	{
		get
		{
			let vel = mPhysicsModule.GetLinearVelocity(mEntity);
			return Vector3(vel.X, 0, vel.Z).Length();
		}
	}

	public void Initialize(Scene scene, RenderSceneModule renderModule, PhysicsSceneModule physicsModule,
		GPUMeshHandle sphereMesh, MaterialInstance mat)
	{
		mScene = scene;
		mPhysicsModule = physicsModule;

		mEntity = scene.CreateEntity();
		var transform = scene.GetTransform(mEntity);
		transform.Position = .(0, Radius, 0);
		scene.SetTransform(mEntity, transform);

		let meshHandle = renderModule.CreateMeshRenderer(mEntity);
		if (meshHandle.IsValid)
		{
			renderModule.SetMeshData(mEntity, sphereMesh, BoundingBox(.(-Radius), .(Radius)));
			renderModule.SetMeshMaterial(mEntity, mat);
		}

		// Create physics body constrained to XZ plane
		var descriptor = PhysicsBodyDescriptor();
		descriptor.BodyType = .Dynamic;
		descriptor.Mass = 1.0f;
		descriptor.LinearDamping = 3.0f;
		descriptor.AngularDamping = 10.0f;
		descriptor.Restitution = 0.5f;
		descriptor.GravityFactor = 0.0f;
		descriptor.AllowedDOFs = .TranslationX | .TranslationZ;
		physicsModule.CreateSphereBody(mEntity, Radius, descriptor);
	}

	public void Update(Vector2 moveInput, bool dashPressed, float dt)
	{
		if (!IsAlive) return;

		// Timers
		if (mDashTimer > 0) mDashTimer -= dt;
		if (mInvulnTimer > 0) mInvulnTimer -= dt;
		if (mSpeedBoostTimer > 0) mSpeedBoostTimer -= dt;

		// Movement: moveInput.X = left/right, moveInput.Y = forward/back
		Vector3 moveDir = .(moveInput.X, 0, -moveInput.Y);

		if (moveDir.LengthSquared() > 0.01f)
		{
			if (moveDir.LengthSquared() > 1.0f)
				moveDir = Vector3.Normalize(moveDir);
			mLastMoveDir = Vector3.Normalize(moveDir);
			// Scale force by dt for frame-rate independence
			mPhysicsModule.AddForce(mEntity, moveDir * MoveForce * SpeedMultiplier * dt);
		}

		// Dash
		if (dashPressed && mDashTimer <= 0)
		{
			mPhysicsModule.AddImpulse(mEntity, mLastMoveDir * DashImpulse);
			mDashTimer = EffectiveDashCooldown;
			mIsDashing = true;
		}

		// Update dash state based on speed
		mIsDashing = Speed > DashSpeedThreshold;
	}

	public void TakeDamage(float amount)
	{
		if (mInvulnTimer > 0) return;
		mHealth = Math.Max(0, mHealth - amount);
		mInvulnTimer = InvulnerabilityTime;
	}

	public void Heal(float amount)
	{
		mHealth = Math.Min(MaxHealth, mHealth + amount);
	}

	public void ApplySpeedBoost(float duration)
	{
		mSpeedBoostTimer = duration;
	}

	public void SetWave(int32 wave)
	{
		mCurrentWave = wave;
	}

	public void Reset()
	{
		mHealth = MaxHealth;
		mDashTimer = 0;
		mInvulnTimer = 0;
		mSpeedBoostTimer = 0;
		mIsDashing = false;
		mCurrentWave = 1;

		var transform = mScene.GetTransform(mEntity);
		transform.Position = .(0, Radius, 0);
		mScene.SetTransform(mEntity, transform);
		mPhysicsModule.SetLinearVelocity(mEntity, .Zero);
	}
}

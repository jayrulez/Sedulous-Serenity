namespace TowerDefense.Components;

using System;
using Sedulous.Engine.Core;
using Sedulous.Foundation.Core;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using TowerDefense.Data;

/// Component for projectile behavior.
class ProjectileComponent : IEntityComponent
{
	private Entity mEntity;

	/// Target entity to track.
	public Entity Target;

	/// Damage dealt on hit.
	public float Damage;

	/// Movement speed.
	public float Speed;

	/// Hit detection radius.
	public float HitRadius = 0.5f;

	/// Whether projectile tracks target (homing) or travels in a straight line.
	public bool IsHoming = true;

	/// Direction for non-homing projectiles.
	public Vector3 Direction = .Zero;

	/// Maximum lifetime before auto-destroy.
	public float MaxLifetime = 5.0f;

	/// Current lifetime.
	public float Lifetime = 0.0f;

	/// Whether this projectile has hit something.
	public bool HasHit = false;

	// Event accessor for hit
	private EventAccessor<ProjectileHitDelegate> mOnHit = new .() ~ delete _;

	/// Event fired when projectile hits a target.
	public EventAccessor<ProjectileHitDelegate> OnHit => mOnHit;

	/// Creates a new ProjectileComponent.
	public this()
	{
	}

	/// Creates a new ProjectileComponent with specified parameters.
	public this(Entity target, float damage, float speed)
	{
		Target = target;
		Damage = damage;
		Speed = speed;
	}

	// ==================== IEntityComponent Implementation ====================

	public void OnAttach(Entity entity)
	{
		mEntity = entity;
	}

	public void OnDetach()
	{
		mEntity = null;
		Target = null;
	}

	public void OnUpdate(float deltaTime)
	{
		if (mEntity == null || HasHit)
			return;

		// Update lifetime
		Lifetime += deltaTime;
		if (Lifetime >= MaxLifetime)
		{
			HasHit = true;  // Mark for destruction
			return;
		}

		// Get current position
		let currentPos = mEntity.Transform.WorldPosition;

		// Determine movement direction
		Vector3 moveDir;
		Vector3 targetPos;

		if (IsHoming && Target != null)
		{
			// Track target
			targetPos = Target.Transform.WorldPosition;
			moveDir = targetPos - currentPos;

			// Check if target is still valid
			let enemyComp = Target.GetComponent<EnemyComponent>();
			if (enemyComp == null || !enemyComp.IsActive)
			{
				// Target lost - continue in last direction or destroy
				if (Direction.LengthSquared() > 0.001f)
				{
					IsHoming = false;
				}
				else
				{
					HasHit = true;
					return;
				}
			}
		}
		else
		{
			// Non-homing - travel in fixed direction
			moveDir = Direction;
			targetPos = currentPos + Direction * 100.0f;
		}

		float distanceToTarget = moveDir.Length();

		// Check for hit
		if (distanceToTarget <= HitRadius)
		{
			if (Target != null)
			{
				HasHit = true;
				mOnHit.[Friend]Invoke(mEntity, Target);
			}
			return;
		}

		// Move toward target
		moveDir = Vector3.Normalize(moveDir);
		Direction = moveDir;  // Store for non-homing fallback

		float moveDistance = Speed * deltaTime;
		let newPos = currentPos + moveDir * moveDistance;
		mEntity.Transform.SetPosition(newPos);

		// Face movement direction
		if (moveDir.LengthSquared() > 0.001f)
		{
			float angle = Math.Atan2(moveDir.X, moveDir.Z);
			mEntity.Transform.SetRotation(Quaternion.CreateFromAxisAngle(.(0, 1, 0), angle));
		}
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		result = serializer.Float("damage", ref Damage);
		if (result != .Ok)
			return result;

		result = serializer.Float("speed", ref Speed);
		if (result != .Ok)
			return result;

		return .Ok;
	}
}

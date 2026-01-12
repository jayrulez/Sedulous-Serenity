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

	/// Target entity ID to track.
	public EntityId TargetId = .Invalid;

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

	/// Gets the target entity (may be null if deleted or invalid).
	public Entity Target
	{
		get
		{
			if (!TargetId.IsValid || mEntity == null)
				return null;
			return mEntity.Scene?.GetEntity(TargetId);
		}
		set
		{
			TargetId = value?.Id ?? .Invalid;
		}
	}

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
		TargetId = .Invalid;
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

		// Get target entity (lookup via EntityId - returns null if deleted)
		let target = Target;

		// Determine movement direction
		Vector3 moveDir;
		Vector3 targetPos;

		if (IsHoming && target != null)
		{
			// Check if target is still valid
			let enemyComp = target.GetComponent<EnemyComponent>();
			if (enemyComp == null || !enemyComp.IsActive)
			{
				// Target lost - continue in last direction or destroy
				TargetId = .Invalid;
				if (Direction.LengthSquared() > 0.001f)
				{
					IsHoming = false;
				}
				else
				{
					HasHit = true;
					return;
				}
				// Fall through to non-homing movement
				moveDir = Direction;
				targetPos = currentPos + Direction * 100.0f;
			}
			else
			{
				// Track target
				targetPos = target.Transform.WorldPosition;
				moveDir = targetPos - currentPos;
			}
		}
		else
		{
			// Non-homing - travel in fixed direction
			moveDir = Direction;
			targetPos = currentPos + Direction * 100.0f;
		}

		float distanceToTarget = moveDir.Length();

		// Check for hit (only if we still have a valid target)
		if (distanceToTarget <= HitRadius && target != null)
		{
			HasHit = true;
			mOnHit.[Friend]Invoke(mEntity, target);
			return;
		}

		// Move toward target
		if (distanceToTarget > 0.001f)
		{
			moveDir = Vector3.Normalize(moveDir);
			Direction = moveDir;  // Store for non-homing fallback

			float moveDistance = Speed * deltaTime;
			let newPos = currentPos + moveDir * moveDistance;
			mEntity.Transform.SetPosition(newPos);

			// Face movement direction
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

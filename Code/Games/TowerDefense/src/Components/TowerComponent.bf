namespace TowerDefense.Components;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Foundation.Core;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using TowerDefense.Data;

/// Component for tower behavior including targeting and firing.
class TowerComponent : IEntityComponent
{
	private Entity mEntity;

	/// The tower definition (stats).
	public TowerDefinition Definition;

	/// Current upgrade level (1 = base).
	public int32 Level = 1;

	/// Current target entity ID (use GetCurrentTarget() to get entity).
	public EntityId CurrentTargetId = .Invalid;

	/// Time until next shot is ready.
	public float FireCooldown = 0.0f;

	/// Grid position of this tower.
	public int32 GridX;
	public int32 GridY;

	// Event accessor for firing
	private EventAccessor<TowerFireDelegate> mOnFire = new .() ~ delete _;

	/// Event fired when tower shoots at a target.
	public EventAccessor<TowerFireDelegate> OnFire => mOnFire;

	/// Gets the current target entity (may be null if deleted or invalid).
	public Entity CurrentTarget
	{
		get
		{
			if (!CurrentTargetId.IsValid || mEntity == null)
				return null;
			return mEntity.Scene?.GetEntity(CurrentTargetId);
		}
		set
		{
			CurrentTargetId = value?.Id ?? .Invalid;
		}
	}

	/// Creates a new TowerComponent.
	public this()
	{
	}

	/// Creates a new TowerComponent with the given definition.
	public this(TowerDefinition definition)
	{
		Definition = definition;
	}

	/// Gets the effective damage (with level scaling).
	public float GetDamage()
	{
		return Definition.Damage * (1.0f + (Level - 1) * 0.25f);
	}

	/// Gets the effective range (with level scaling).
	public float GetRange()
	{
		return Definition.Range * (1.0f + (Level - 1) * 0.1f);
	}

	/// Gets the effective fire rate (with level scaling).
	public float GetFireRate()
	{
		return Definition.FireRate * (1.0f + (Level - 1) * 0.15f);
	}

	/// Checks if a target is valid (in range and correct type).
	public bool IsValidTarget(Entity target)
	{
		if (target == null || mEntity == null)
			return false;

		// Check if target has enemy component
		let enemyComp = target.GetComponent<EnemyComponent>();
		if (enemyComp == null || !enemyComp.IsActive)
			return false;

		// Check target type compatibility
		if (!Definition.TargetType.CanTarget(enemyComp.Definition.Type))
			return false;

		// Check range using horizontal distance (XZ plane) to match the visual range indicator
		let towerPos = mEntity.Transform.WorldPosition;
		let targetPos = target.Transform.WorldPosition;
		float dx = towerPos.X - targetPos.X;
		float dz = towerPos.Z - targetPos.Z;
		float horizontalDistance = Math.Sqrt(dx * dx + dz * dz);
		let range = GetRange();

		return horizontalDistance <= range;
	}

	/// Finds the best target from a list of enemies.
	/// Returns the enemy that has traveled the furthest (closest to exit).
	public Entity FindBestTarget(List<Entity> enemies)
	{
		if (mEntity == null)
			return null;

		Entity bestTarget = null;
		float bestDistance = -1.0f;

		for (let enemy in enemies)
		{
			if (!IsValidTarget(enemy))
				continue;

			let enemyComp = enemy.GetComponent<EnemyComponent>();
			if (enemyComp != null && enemyComp.DistanceTraveled > bestDistance)
			{
				bestDistance = enemyComp.DistanceTraveled;
				bestTarget = enemy;
			}
		}

		return bestTarget;
	}

	/// Tries to fire at the current target.
	/// Returns true if a shot was fired.
	public bool TryFire()
	{
		let target = CurrentTarget;
		if (FireCooldown > 0 || target == null || mEntity == null)
			return false;

		if (!IsValidTarget(target))
		{
			CurrentTargetId = .Invalid;
			return false;
		}

		// Fire!
		let fireRate = GetFireRate();
		FireCooldown = 1.0f / fireRate;

		// Get projectile spawn position (top of tower)
		let towerPos = mEntity.Transform.WorldPosition;
		let spawnPos = Vector3(towerPos.X, towerPos.Y + Definition.Scale, towerPos.Z);

		mOnFire.[Friend]Invoke(this, target, spawnPos);
		return true;
	}

	/// Rotates tower to face current target.
	private void FaceTarget(Entity target)
	{
		if (target == null || mEntity == null)
			return;

		let towerPos = mEntity.Transform.WorldPosition;
		let targetPos = target.Transform.WorldPosition;

		// Calculate direction (XZ plane only for Y-axis rotation)
		let direction = targetPos - towerPos;
		if (direction.LengthSquared() > 0.001f)
		{
			float angle = Math.Atan2(direction.X, direction.Z);
			mEntity.Transform.SetRotation(Quaternion.CreateFromAxisAngle(.(0, 1, 0), angle));
		}
	}

	// ==================== IEntityComponent Implementation ====================

	public void OnAttach(Entity entity)
	{
		mEntity = entity;
	}

	public void OnDetach()
	{
		mEntity = null;
		CurrentTargetId = .Invalid;
	}

	public void OnUpdate(float deltaTime)
	{
		// Update cooldown
		if (FireCooldown > 0)
			FireCooldown -= deltaTime;

		// Face target (lookup once via EntityId)
		let target = CurrentTarget;
		if (target != null)
			FaceTarget(target);
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		result = serializer.Int32("level", ref Level);
		if (result != .Ok)
			return result;

		result = serializer.Int32("gridX", ref GridX);
		if (result != .Ok)
			return result;

		result = serializer.Int32("gridY", ref GridY);
		if (result != .Ok)
			return result;

		return .Ok;
	}
}

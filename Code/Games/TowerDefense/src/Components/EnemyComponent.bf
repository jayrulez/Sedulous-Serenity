namespace TowerDefense.Components;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Foundation.Core;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using TowerDefense.Data;

/// Component for enemy behavior including waypoint-following movement.
class EnemyComponent : IEntityComponent
{
	private Entity mEntity;

	/// The enemy definition (stats).
	public EnemyDefinition Definition;

	/// Reference to the waypoint list.
	public List<Vector3> Waypoints;

	/// Current waypoint index.
	public int32 CurrentWaypointIndex = 0;

	/// Total distance traveled (for targeting priority - enemies further along are higher priority).
	public float DistanceTraveled = 0.0f;

	/// Whether this enemy has reached the exit.
	public bool HasReachedExit = false;

	/// Whether this enemy is dying (playing death animation).
	public bool IsDying = false;

	/// Timer for death animation.
	private float mDyingTimer = 0.0f;

	/// Duration of death animation.
	private const float DeathAnimDuration = 0.3f;

	/// Original scale (for death animation).
	private Vector3 mOriginalScale = .(1, 1, 1);

	/// Whether death animation is complete.
	public bool DeathAnimComplete = false;

	/// Whether this enemy is active (alive and hasn't exited).
	public bool IsActive => !HasReachedExit && !IsDying && mEntity != null;

	// Event accessor
	private EventAccessor<EnemyExitDelegate> mOnReachedExit = new .() ~ delete _;

	/// Event fired when this enemy reaches the exit.
	public EventAccessor<EnemyExitDelegate> OnReachedExit => mOnReachedExit;

	/// Creates a new EnemyComponent.
	public this()
	{
	}

	/// Creates a new EnemyComponent with the given definition and waypoints.
	public this(EnemyDefinition definition, List<Vector3> waypoints)
	{
		Definition = definition;
		Waypoints = waypoints;
	}

	/// Starts the death animation.
	public void StartDying()
	{
		if (IsDying)
			return;

		IsDying = true;
		mDyingTimer = 0.0f;
		if (mEntity != null)
			mOriginalScale = mEntity.Transform.Scale;
	}

	// ==================== IEntityComponent Implementation ====================

	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		// Position at first waypoint
		if (Waypoints != null && Waypoints.Count > 0)
		{
			let spawnPos = Waypoints[0];
			float yOffset = Definition.Type == .Air ? 2.0f : 0.5f;
			mEntity.Transform.SetPosition(.(spawnPos.X, yOffset, spawnPos.Z));
			CurrentWaypointIndex = 1;  // Start moving toward second waypoint
		}
	}

	public void OnDetach()
	{
		mEntity = null;
	}

	public void OnUpdate(float deltaTime)
	{
		if (mEntity == null)
			return;

		// Handle death animation
		if (IsDying)
		{
			mDyingTimer += deltaTime;
			float t = Math.Clamp(mDyingTimer / DeathAnimDuration, 0.0f, 1.0f);

			// Scale down from original to near-zero
			float scale = 1.0f - t;
			mEntity.Transform.SetScale(mOriginalScale * scale);

			// Animation complete
			if (t >= 1.0f)
				DeathAnimComplete = true;

			return;
		}

		if (Waypoints == null || HasReachedExit)
			return;

		// Check if we've reached the end
		if (CurrentWaypointIndex >= Waypoints.Count)
		{
			HasReachedExit = true;
			mOnReachedExit.[Friend]Invoke(this);
			return;
		}

		// Get current position and target
		let currentPos = mEntity.Transform.WorldPosition;
		let targetWaypoint = Waypoints[CurrentWaypointIndex];
		float yOffset = Definition.Type == .Air ? 2.0f : 0.5f;
		let target = Vector3(targetWaypoint.X, yOffset, targetWaypoint.Z);

		// Calculate direction and distance
		var direction = target - currentPos;
		float distanceToTarget = direction.Length();

		// Move toward waypoint
		float moveDistance = Definition.Speed * deltaTime;
		DistanceTraveled += moveDistance;

		if (moveDistance >= distanceToTarget)
		{
			// Reached waypoint - move to next
			mEntity.Transform.SetPosition(target);
			CurrentWaypointIndex++;
		}
		else
		{
			// Move toward target
			direction = Vector3.Normalize(direction);
			let newPos = currentPos + direction * moveDistance;
			mEntity.Transform.SetPosition(newPos);

			// Face movement direction (Y-axis rotation only for ground units)
			if (direction.LengthSquared() > 0.001f)
			{
				float angle = Math.Atan2(direction.X, direction.Z);
				mEntity.Transform.SetRotation(Quaternion.CreateFromAxisAngle(.(0, 1, 0), angle));
			}
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

		result = serializer.Int32("waypointIndex", ref CurrentWaypointIndex);
		if (result != .Ok)
			return result;

		result = serializer.Float("distanceTraveled", ref DistanceTraveled);
		if (result != .Ok)
			return result;

		return .Ok;
	}
}

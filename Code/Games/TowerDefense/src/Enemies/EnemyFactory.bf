namespace TowerDefense.Enemies;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Resources;
using Sedulous.Materials;
using Sedulous.Render;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Foundation.Core;
using TowerDefense.Data;
using TowerDefense.Components;

/// Delegate for enemy death events with position (for audio).
delegate void EnemyDeathAudioDelegate(Vector3 position);

/// Delegate for enemy killed events (with EntityId instead of Entity).
delegate void EnemyKilledFrameworkDelegate(EntityId entity, int32 reward);

/// Factory for creating enemy entities.
/// Ported to Sedulous.Framework architecture.
class EnemyFactory
{
	private Scene mScene;
	private RenderSceneModule mRenderModule;
	private RenderSystem mRenderSystem;
	private List<Vector3> mWaypoints;

	// Shared mesh for enemies
	private StaticMeshResource mEnemyMesh;

	// Material instances for different enemy types (keyed by color)
	private Dictionary<uint32, MaterialInstance> mMaterialCache = new .() ~ {
		for (let mat in _.Values)
			delete mat;
		delete _;
	};

	// Enemy data tracking (since we can't use IEntityComponent)
	private Dictionary<EntityId, EnemyData> mEnemyData = new .() ~ {
		for (let data in _.Values)
			delete data;
		delete _;
	};

	// Enemy tracking
	private List<EntityId> mActiveEnemies = new .() ~ delete _;
	private List<EntityId> mDyingEnemies = new .() ~ delete _;
	private int32 mEnemyCounter = 0;

	// Event accessors
	private EventAccessor<EnemyExitDelegate> mOnEnemyReachedExit = new .() ~ delete _;
	private EventAccessor<EnemyKilledFrameworkDelegate> mOnEnemyKilled = new .() ~ delete _;
	private EventAccessor<EnemyDeathAudioDelegate> mOnEnemyDeathAudio = new .() ~ delete _;

	/// Event fired when an enemy reaches the exit.
	public EventAccessor<EnemyExitDelegate> OnEnemyReachedExit => mOnEnemyReachedExit;

	/// Event fired when an enemy dies.
	public EventAccessor<EnemyKilledFrameworkDelegate> OnEnemyKilled => mOnEnemyKilled;

	/// Event fired when an enemy dies (with position for audio).
	public EventAccessor<EnemyDeathAudioDelegate> OnEnemyDeathAudio => mOnEnemyDeathAudio;

	/// Number of active enemies.
	public int32 ActiveEnemyCount => (.)mActiveEnemies.Count;

	/// Creates a new EnemyFactory.
	public this(Scene scene, RenderSceneModule renderModule, RenderSystem renderSystem, StaticMeshResource cubeMesh)
	{
		mScene = scene;
		mRenderModule = renderModule;
		mRenderSystem = renderSystem;
		mEnemyMesh = cubeMesh;
	}

	/// Sets the waypoints for enemy movement.
	public void SetWaypoints(List<Vector3> waypoints)
	{
		mWaypoints = waypoints;
	}

	/// Initializes materials for enemy rendering.
	public void InitializeMaterials()
	{
		Console.WriteLine("EnemyFactory: Materials initialized");
	}

	/// Creates a material instance for the given color.
	private MaterialInstance GetOrCreateMaterial(Vector4 color)
	{
		// Create a color key from RGBA bytes
		uint32 colorKey = ((uint32)(color.X * 255) << 24) |
		                  ((uint32)(color.Y * 255) << 16) |
		                  ((uint32)(color.Z * 255) << 8) |
		                  ((uint32)(color.W * 255));

		if (mMaterialCache.TryGetValue(colorKey, let existing))
			return existing;

		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
		if (baseMat == null)
			return null;

		let mat = new MaterialInstance(baseMat);
		mat.SetColor("BaseColor", color);
		mat.SetFloat("Metallic", 0.3f);
		mat.SetFloat("Roughness", 0.6f);

		mMaterialCache[colorKey] = mat;
		return mat;
	}

	/// Spawns a new enemy with the given definition.
	public EntityId SpawnEnemy(EnemyDefinition definition)
	{
		if (mWaypoints == null || mWaypoints.Count < 2)
		{
			Console.WriteLine("EnemyFactory: No waypoints set!");
			return .Invalid;
		}

		mEnemyCounter++;
		let entity = mScene.CreateEntity();

		// Set initial position and scale
		let spawnPos = mWaypoints[0];
		float yOffset = definition.Type == .Air ? 2.0f : 0.5f;

		var transform = mScene.GetTransform(entity);
		transform.Position = .(spawnPos.X, yOffset, spawnPos.Z);
		transform.Scale = .(definition.Scale, definition.Scale, definition.Scale);
		mScene.SetTransform(entity, transform);

		// Add mesh renderer component
		mScene.SetComponent<MeshRendererComponent>(entity, .Default);
		var meshComp = mScene.GetComponent<MeshRendererComponent>(entity);
		meshComp.Mesh = ResourceHandle<StaticMeshResource>(mEnemyMesh);
		meshComp.Material = GetOrCreateMaterial(definition.Color);

		// Create enemy data (replaces component)
		let enemyData = new EnemyData();
		enemyData.Definition = definition;
		enemyData.Waypoints = mWaypoints;
		enemyData.CurrentWaypointIndex = 1;  // Start moving toward second waypoint
		enemyData.Health = definition.MaxHealth;
		enemyData.MaxHealth = definition.MaxHealth;
		mEnemyData[entity] = enemyData;

		mActiveEnemies.Add(entity);
		return entity;
	}

	/// Gets the health percent of an enemy (0-1).
	public float GetEnemyHealthPercent(EntityId entity)
	{
		if (mEnemyData.TryGetValue(entity, let data))
			return data.Health / data.MaxHealth;
		return 0;
	}

	/// Gets enemy data for the given entity.
	public EnemyData GetEnemyData(EntityId entity)
	{
		if (mEnemyData.TryGetValue(entity, let data))
			return data;
		return null;
	}

	/// Damages an enemy. Returns true if killed.
	public bool DamageEnemy(EntityId entity, float damage)
	{
		if (!mEnemyData.TryGetValue(entity, let data))
			return false;

		data.Health -= damage;
		if (data.Health <= 0 && !data.IsDying)
		{
			OnEnemyDeath(entity, data.Definition.Reward);
			return true;
		}
		return false;
	}

	/// Called when an enemy dies.
	private void OnEnemyDeath(EntityId entity, int32 reward)
	{
		if (!mEnemyData.TryGetValue(entity, let data))
			return;

		// Capture position before starting death animation
		var transform = mScene.GetTransform(entity);
		let position = transform.Position;

		mOnEnemyKilled.[Friend]Invoke(entity, reward);
		mOnEnemyDeathAudio.[Friend]Invoke(position);

		// Start death animation
		data.IsDying = true;
		data.DyingTimer = 0.0f;
		data.OriginalScale = transform.Scale;

		mActiveEnemies.Remove(entity);
		mDyingEnemies.Add(entity);
	}

	/// Removes an enemy from tracking and destroys it.
	private void RemoveEnemy(EntityId entity)
	{
		mActiveEnemies.Remove(entity);
		if (mEnemyData.TryGetValue(entity, let data))
		{
			delete data;
			mEnemyData.Remove(entity);
		}
		mScene.DestroyEntity(entity);
	}

	/// Gets all active enemies.
	public void GetActiveEnemies(List<EntityId> outList)
	{
		outList.Clear();
		for (let enemy in mActiveEnemies)
			outList.Add(enemy);
	}

	/// Updates enemies and removes them when animation completes.
	public void Update(float deltaTime)
	{
		// Update active enemies (movement)
		for (let entity in mActiveEnemies)
		{
			if (!mEnemyData.TryGetValue(entity, let data))
				continue;

			UpdateEnemyMovement(entity, data, deltaTime);
		}

		// Check dying enemies for completed animations
		for (int i = mDyingEnemies.Count - 1; i >= 0; i--)
		{
			let entity = mDyingEnemies[i];
			if (!mEnemyData.TryGetValue(entity, let data))
			{
				mDyingEnemies.RemoveAt(i);
				mScene.DestroyEntity(entity);
				continue;
			}

			// Update death animation
			data.DyingTimer += deltaTime;
			float t = Math.Clamp(data.DyingTimer / EnemyData.DeathAnimDuration, 0.0f, 1.0f);

			// Scale down
			float scale = 1.0f - t;
			var transform = mScene.GetTransform(entity);
			transform.Scale = data.OriginalScale * scale;
			mScene.SetTransform(entity, transform);

			if (t >= 1.0f)
			{
				mDyingEnemies.RemoveAt(i);
				delete data;
				mEnemyData.Remove(entity);
				mScene.DestroyEntity(entity);
			}
		}
	}

	/// Updates enemy movement along waypoints.
	private void UpdateEnemyMovement(EntityId entity, EnemyData data, float deltaTime)
	{
		if (data.IsDying || data.HasReachedExit)
			return;

		if (data.Waypoints == null || data.CurrentWaypointIndex >= data.Waypoints.Count)
		{
			data.HasReachedExit = true;
			// Create temporary EnemyComponent for callback (legacy support)
			let tempComp = scope EnemyComponent();
			tempComp.Definition = data.Definition;
			mOnEnemyReachedExit.[Friend]Invoke(tempComp);
			RemoveEnemy(entity);
			return;
		}

		var transform = mScene.GetTransform(entity);
		let currentPos = transform.Position;
		let targetWaypoint = data.Waypoints[data.CurrentWaypointIndex];
		float yOffset = data.Definition.Type == .Air ? 2.0f : 0.5f;
		let target = Vector3(targetWaypoint.X, yOffset, targetWaypoint.Z);

		// Calculate direction and distance
		var direction = target - currentPos;
		float distanceToTarget = direction.Length();

		// Move toward waypoint
		float moveDistance = data.Definition.Speed * deltaTime;
		data.DistanceTraveled += moveDistance;

		if (moveDistance >= distanceToTarget)
		{
			// Reached waypoint - move to next
			transform.Position = target;
			data.CurrentWaypointIndex++;
		}
		else
		{
			// Move toward target
			direction = Vector3.Normalize(direction);
			transform.Position = currentPos + direction * moveDistance;

			// Face movement direction
			if (direction.LengthSquared() > 0.001f)
			{
				float angle = Math.Atan2(direction.X, direction.Z);
				transform.Rotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), angle);
			}
		}

		mScene.SetTransform(entity, transform);
	}

	public void ClearAllEnemies()
	{
		for (let entity in mActiveEnemies)
		{
			if (mEnemyData.TryGetValue(entity, let data))
				delete data;
			mScene.DestroyEntity(entity);
		}
		mActiveEnemies.Clear();
		mEnemyData.Clear();

		for (let entity in mDyingEnemies)
			mScene.DestroyEntity(entity);
		mDyingEnemies.Clear();
	}

	/// Cleans up materials.
	public void Cleanup()
	{
		ClearAllEnemies();
	}
}

/// Internal data for enemy tracking (replaces IEntityComponent).
class EnemyData
{
	public EnemyDefinition Definition;
	public List<Vector3> Waypoints;
	public int32 CurrentWaypointIndex = 0;
	public float DistanceTraveled = 0.0f;
	public bool HasReachedExit = false;
	public bool IsDying = false;
	public float DyingTimer = 0.0f;
	public Vector3 OriginalScale = .(1, 1, 1);
	public float Health;
	public float MaxHealth;

	public const float DeathAnimDuration = 0.3f;
}

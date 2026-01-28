namespace TowerDefense.Towers;

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
using TowerDefense.Audio;
using TowerDefense.Components;
using TowerDefense.Enemies;

/// Delegate for tower fire events (for audio/effects).
delegate void TowerFiredDelegate(TowerDefinition def, Vector3 position);

/// Delegate for projectile impact events (for particle effects).
delegate void ProjectileImpactDelegate(Vector3 position, Vector4 color);

/// Factory for creating and managing towers and projectiles.
/// Ported to Sedulous.Framework architecture.
class TowerFactory
{
	private Scene mScene;
	private RenderSceneModule mRenderModule;
	private RenderSystem mRenderSystem;
	private EnemyFactory mEnemyFactory;
	private GameAudio mGameAudio;

	// Events
	private EventAccessor<TowerFiredDelegate> mOnTowerFired = new .() ~ delete _;
	private EventAccessor<ProjectileImpactDelegate> mOnProjectileImpact = new .() ~ delete _;

	/// Event fired when any tower fires (for audio/effects).
	public EventAccessor<TowerFiredDelegate> OnTowerFired => mOnTowerFired;

	/// Event fired when a projectile hits a target (for particle effects).
	public EventAccessor<ProjectileImpactDelegate> OnProjectileImpact => mOnProjectileImpact;

	// Shared meshes
	private StaticMeshResource mTowerMesh;
	private StaticMeshResource mProjectileMesh;

	// Material instances (keyed by color)
	private Dictionary<uint32, MaterialInstance> mMaterialCache = new .() ~ {
		for (let mat in _.Values)
			delete mat;
		delete _;
	};

	// Tower tracking
	private List<EntityId> mTowers = new .() ~ delete _;
	private Dictionary<EntityId, TowerData> mTowerData = new .() ~ {
		for (let data in _.Values)
			delete data;
		delete _;
	};
	private Dictionary<int64, EntityId> mTowerGrid = new .() ~ delete _;  // GridKey -> Tower
	private int32 mTowerCounter = 0;

	// Projectile tracking
	private List<EntityId> mProjectiles = new .() ~ delete _;
	private Dictionary<EntityId, ProjectileData> mProjectileData = new .() ~ {
		for (let data in _.Values)
			delete data;
		delete _;
	};
	private List<EntityId> mProjectilesToRemove = new .() ~ delete _;
	private int32 mProjectileCounter = 0;

	// Temp list for enemy queries
	private List<EntityId> mTempEnemyList = new .() ~ delete _;

	/// Number of active towers.
	public int32 TowerCount => (.)mTowers.Count;

	/// Creates a new TowerFactory.
	public this(Scene scene, RenderSceneModule renderModule, RenderSystem renderSystem,
		StaticMeshResource towerMesh, StaticMeshResource projectileMesh,
		EnemyFactory enemyFactory, GameAudio gameAudio)
	{
		mScene = scene;
		mRenderModule = renderModule;
		mRenderSystem = renderSystem;
		mTowerMesh = towerMesh;
		mProjectileMesh = projectileMesh;
		mEnemyFactory = enemyFactory;
		mGameAudio = gameAudio;
	}

	/// Initializes materials for tower and projectile rendering.
	public void InitializeMaterials()
	{
		Console.WriteLine("TowerFactory: Materials initialized");
	}

	/// Creates a material instance for the given color.
	private MaterialInstance GetOrCreateMaterial(Vector4 color)
	{
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
		mat.SetFloat("Metallic", 0.5f);
		mat.SetFloat("Roughness", 0.4f);

		mMaterialCache[colorKey] = mat;
		return mat;
	}

	/// Creates a grid key from coordinates.
	private int64 GridKey(int32 x, int32 y)
	{
		return ((int64)x << 32) | (int64)(uint32)y;
	}

	/// Checks if a tower can be placed at the given grid position.
	public bool CanPlaceTower(int32 gridX, int32 gridY, TileType tileType)
	{
		// Must be buildable tile
		if (!tileType.IsBuildable)
			return false;

		// Must not already have a tower
		return !mTowerGrid.ContainsKey(GridKey(gridX, gridY));
	}

	/// Places a tower at the given world position.
	public EntityId PlaceTower(TowerDefinition definition, Vector3 worldPos, int32 gridX, int32 gridY)
	{
		// Check if position is occupied
		let gridKey = GridKey(gridX, gridY);
		if (mTowerGrid.ContainsKey(gridKey))
		{
			Console.WriteLine("TowerFactory: Position already occupied!");
			return .Invalid;
		}

		mTowerCounter++;
		let entity = mScene.CreateEntity();

		// Position tower
		float yPos = definition.Scale * 0.5f;  // Half height to sit on ground
		var transform = mScene.GetTransform(entity);
		transform.Position = .(worldPos.X, yPos, worldPos.Z);
		transform.Scale = .(definition.Scale * 0.8f, definition.Scale, definition.Scale * 0.8f);
		mScene.SetTransform(entity, transform);

		// Add mesh renderer component
		mScene.SetComponent<MeshRendererComponent>(entity, .Default);
		var meshComp = mScene.GetComponent<MeshRendererComponent>(entity);
		meshComp.Mesh = ResourceHandle<StaticMeshResource>(mTowerMesh);
		meshComp.Material = GetOrCreateMaterial(definition.Color);

		// Create tower data (replaces component)
		let towerData = new TowerData();
		towerData.Definition = definition;
		towerData.GridX = gridX;
		towerData.GridY = gridY;
		towerData.Level = 1;
		towerData.FireCooldown = 0.0f;
		mTowerData[entity] = towerData;

		mTowers.Add(entity);
		mTowerGrid[gridKey] = entity;

		Console.WriteLine($"Placed {definition.Name} tower at ({gridX}, {gridY})");
		return entity;
	}

	/// Removes a tower and returns partial refund (50% of total invested).
	public int32 SellTower(EntityId tower)
	{
		if (!mTowerData.TryGetValue(tower, let towerData))
			return 0;

		// Calculate refund (50% of total invested including upgrades)
		int32 refund = towerData.GetTotalInvested() / 2;

		// Remove from grid
		let gridKey = GridKey(towerData.GridX, towerData.GridY);
		mTowerGrid.Remove(gridKey);

		// Remove from list and destroy
		mTowers.Remove(tower);
		delete towerData;
		mTowerData.Remove(tower);
		mScene.DestroyEntity(tower);

		Console.WriteLine($"Sold tower for ${refund}");
		return refund;
	}

	/// Gets tower data for the given entity.
	public TowerData GetTowerData(EntityId entity)
	{
		if (mTowerData.TryGetValue(entity, let data))
			return data;
		return null;
	}

	/// Called when a tower fires.
	private void OnTowerFire(EntityId towerEntity, TowerData towerData, EntityId target, Vector3 origin)
	{
		SpawnProjectile(origin, target, towerData.GetDamage(), towerData.Definition.ProjectileSpeed, towerData.Definition.ProjectileColor);

		// Play fire sound via GameAudio (simplified - no AudioSourceComponent per tower)
		if (mGameAudio != null)
		{
			let clip = mGameAudio.GetTowerFireClip(towerData.Definition.Name);
			if (clip != null)
			{
				// Play at tower position
				var towerTransform = mScene.GetTransform(towerEntity);
				let towerPos = towerTransform.Position;
				mGameAudio.PlaySpatial(clip, towerPos);
			}
		}

		// Notify external listeners (for visual effects, etc.)
		mOnTowerFired.[Friend]Invoke(towerData.Definition, origin);
	}

	/// Spawns a projectile.
	private EntityId SpawnProjectile(Vector3 origin, EntityId target, float damage, float speed, Vector4 color)
	{
		mProjectileCounter++;
		let entity = mScene.CreateEntity();

		// Position projectile (tiny scale for projectiles)
		var transform = mScene.GetTransform(entity);
		transform.Position = origin;
		transform.Scale = .(0.15f, 0.15f, 0.15f);
		mScene.SetTransform(entity, transform);

		// Add mesh renderer component
		mScene.SetComponent<MeshRendererComponent>(entity, .Default);
		var meshComp = mScene.GetComponent<MeshRendererComponent>(entity);
		meshComp.Mesh = ResourceHandle<StaticMeshResource>(mProjectileMesh);
		meshComp.Material = GetOrCreateMaterial(color);

		// Create projectile data (replaces component)
		let projData = new ProjectileData();
		projData.TargetId = target;
		projData.Damage = damage;
		projData.Speed = speed;
		projData.Color = color;
		mProjectileData[entity] = projData;

		mProjectiles.Add(entity);
		return entity;
	}

	/// Called when a projectile hits a target.
	private void OnProjectileHit(EntityId projectile, ProjectileData projData, EntityId target)
	{
		// Apply damage to target via EnemyFactory
		mEnemyFactory.DamageEnemy(target, projData.Damage);

		// Fire event for particle effects at impact position
		var projTransform = mScene.GetTransform(projectile);
		let hitPosition = projTransform.Position;
		mOnProjectileImpact.[Friend]Invoke(hitPosition, projData.Color);
	}

	/// Updates all towers (targeting) and projectiles.
	public void Update(float deltaTime)
	{
		// Get current enemies
		mEnemyFactory.GetActiveEnemies(mTempEnemyList);

		// Update tower targeting and firing
		for (let tower in mTowers)
		{
			if (!mTowerData.TryGetValue(tower, let towerData))
				continue;

			// Update cooldown
			if (towerData.FireCooldown > 0)
				towerData.FireCooldown -= deltaTime;

			// Find new target if needed
			if (!towerData.CurrentTargetId.IsValid || !IsValidTarget(tower, towerData, towerData.CurrentTargetId))
			{
				towerData.CurrentTargetId = FindBestTarget(tower, towerData, mTempEnemyList);
			}

			// Try to fire
			if (TryFire(tower, towerData))
			{
				// Fire was successful
			}

			// Face target
			if (towerData.CurrentTargetId.IsValid)
				FaceTarget(tower, towerData.CurrentTargetId);
		}

		// Update projectiles
		for (let projectile in mProjectiles)
		{
			if (!mProjectileData.TryGetValue(projectile, let projData))
				continue;

			UpdateProjectile(projectile, projData, deltaTime);
		}

		// Clean up hit/expired projectiles
		mProjectilesToRemove.Clear();
		for (let projectile in mProjectiles)
		{
			if (mProjectileData.TryGetValue(projectile, let projData))
			{
				if (projData.HasHit)
					mProjectilesToRemove.Add(projectile);
			}
		}

		for (let projectile in mProjectilesToRemove)
		{
			mProjectiles.Remove(projectile);
			if (mProjectileData.TryGetValue(projectile, let projData))
			{
				delete projData;
				mProjectileData.Remove(projectile);
			}
			mScene.DestroyEntity(projectile);
		}
	}

	/// Updates a single projectile.
	private void UpdateProjectile(EntityId projectile, ProjectileData projData, float deltaTime)
	{
		if (projData.HasHit)
			return;

		// Update lifetime
		projData.Lifetime += deltaTime;
		if (projData.Lifetime >= projData.MaxLifetime)
		{
			projData.HasHit = true;
			return;
		}

		var transform = mScene.GetTransform(projectile);
		let currentPos = transform.Position;

		// Get target position
		Vector3 targetPos;
		Vector3 moveDir;
		bool hasTarget = false;

		if (projData.IsHoming && projData.TargetId.IsValid)
		{
			let enemyData = mEnemyFactory.GetEnemyData(projData.TargetId);
			if (enemyData != null && !enemyData.IsDying && !enemyData.HasReachedExit)
			{
				var targetTransform = mScene.GetTransform(projData.TargetId);
				targetPos = targetTransform.Position;
				moveDir = targetPos - currentPos;
				hasTarget = true;
			}
			else
			{
				// Target lost - continue in last direction or destroy
				projData.TargetId = .Invalid;
				if (projData.Direction.LengthSquared() > 0.001f)
				{
					projData.IsHoming = false;
					moveDir = projData.Direction;
					targetPos = currentPos + projData.Direction * 100.0f;
				}
				else
				{
					projData.HasHit = true;
					return;
				}
			}
		}
		else
		{
			// Non-homing - travel in fixed direction
			moveDir = projData.Direction;
			targetPos = currentPos + projData.Direction * 100.0f;
		}

		float distanceToTarget = moveDir.Length();

		// Check for hit (only if we still have a valid target)
		if (hasTarget && distanceToTarget <= projData.HitRadius)
		{
			projData.HasHit = true;
			OnProjectileHit(projectile, projData, projData.TargetId);
			return;
		}

		// Move toward target
		if (distanceToTarget > 0.001f)
		{
			moveDir = Vector3.Normalize(moveDir);
			projData.Direction = moveDir;  // Store for non-homing fallback

			float moveDistance = projData.Speed * deltaTime;
			transform.Position = currentPos + moveDir * moveDistance;

			// Face movement direction
			float angle = Math.Atan2(moveDir.X, moveDir.Z);
			transform.Rotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), angle);

			mScene.SetTransform(projectile, transform);
		}
	}

	/// Checks if a target is valid for the given tower.
	private bool IsValidTarget(EntityId tower, TowerData towerData, EntityId target)
	{
		if (!target.IsValid)
			return false;

		let enemyData = mEnemyFactory.GetEnemyData(target);
		if (enemyData == null || enemyData.IsDying || enemyData.HasReachedExit)
			return false;

		// Check target type compatibility
		if (!towerData.Definition.TargetType.CanTarget(enemyData.Definition.Type))
			return false;

		// Check range using horizontal distance
		var towerTransform = mScene.GetTransform(tower);
		var targetTransform = mScene.GetTransform(target);
		let towerPos = towerTransform.Position;
		let targetPos = targetTransform.Position;
		float dx = towerPos.X - targetPos.X;
		float dz = towerPos.Z - targetPos.Z;
		float horizontalDistance = Math.Sqrt(dx * dx + dz * dz);
		let range = towerData.GetRange();

		return horizontalDistance <= range;
	}

	/// Finds the best target from a list of enemies.
	private EntityId FindBestTarget(EntityId tower, TowerData towerData, List<EntityId> enemies)
	{
		EntityId bestTarget = .Invalid;
		float bestDistance = -1.0f;

		for (let enemy in enemies)
		{
			if (!IsValidTarget(tower, towerData, enemy))
				continue;

			let enemyData = mEnemyFactory.GetEnemyData(enemy);
			if (enemyData != null && enemyData.DistanceTraveled > bestDistance)
			{
				bestDistance = enemyData.DistanceTraveled;
				bestTarget = enemy;
			}
		}

		return bestTarget;
	}

	/// Tries to fire at the current target.
	private bool TryFire(EntityId tower, TowerData towerData)
	{
		if (towerData.FireCooldown > 0 || !towerData.CurrentTargetId.IsValid)
			return false;

		if (!IsValidTarget(tower, towerData, towerData.CurrentTargetId))
		{
			towerData.CurrentTargetId = .Invalid;
			return false;
		}

		// Fire!
		let fireRate = towerData.GetFireRate();
		towerData.FireCooldown = 1.0f / fireRate;

		// Get projectile spawn position (top of tower)
		var towerTransform = mScene.GetTransform(tower);
		let towerPos = towerTransform.Position;
		let spawnPos = Vector3(towerPos.X, towerPos.Y + towerData.Definition.Scale, towerPos.Z);

		OnTowerFire(tower, towerData, towerData.CurrentTargetId, spawnPos);
		return true;
	}

	/// Rotates tower to face current target.
	private void FaceTarget(EntityId tower, EntityId target)
	{
		if (!target.IsValid)
			return;

		var towerTransform = mScene.GetTransform(tower);
		var targetTransform = mScene.GetTransform(target);
		let targetPos = targetTransform.Position;

		// Calculate direction (XZ plane only for Y-axis rotation)
		let direction = targetPos - towerTransform.Position;
		if (direction.LengthSquared() > 0.001f)
		{
			float angle = Math.Atan2(direction.X, direction.Z);
			towerTransform.Rotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), angle);
			mScene.SetTransform(tower, towerTransform);
		}
	}

	/// Gets the tower at the given grid position, or null.
	public EntityId GetTowerAt(int32 gridX, int32 gridY)
	{
		let gridKey = GridKey(gridX, gridY);
		if (mTowerGrid.TryGetValue(gridKey, let tower))
			return tower;
		return .Invalid;
	}

	/// Gets the effective range of a tower.
	public float GetTowerRange(EntityId tower)
	{
		if (mTowerData.TryGetValue(tower, let data))
			return data.GetRange();
		return 0;
	}

	/// Upgrades a tower. Returns true if upgrade was successful.
	public bool UpgradeTower(EntityId tower)
	{
		if (!mTowerData.TryGetValue(tower, let towerData))
			return false;

		if (!towerData.CanUpgrade)
			return false;

		towerData.Level++;

		// Update visual scale (5% bigger per level)
		let levelScale = 1.0f + (towerData.Level - 1) * 0.05f;
		let baseScale = towerData.Definition.Scale;
		var transform = mScene.GetTransform(tower);
		transform.Scale = .(baseScale * 0.8f * levelScale, baseScale * levelScale, baseScale * 0.8f * levelScale);
		mScene.SetTransform(tower, transform);

		return true;
	}

	/// Destroys all towers and projectiles.
	public void ClearAll()
	{
		for (let tower in mTowers)
		{
			if (mTowerData.TryGetValue(tower, let data))
				delete data;
			mScene.DestroyEntity(tower);
		}
		mTowers.Clear();
		mTowerData.Clear();
		mTowerGrid.Clear();

		for (let projectile in mProjectiles)
		{
			if (mProjectileData.TryGetValue(projectile, let data))
				delete data;
			mScene.DestroyEntity(projectile);
		}
		mProjectiles.Clear();
		mProjectileData.Clear();
	}

	/// Cleans up materials.
	public void Cleanup()
	{
		ClearAll();
	}
}

/// Internal data for tower tracking (replaces IEntityComponent).
class TowerData
{
	/// Maximum upgrade level for towers.
	public const int32 MaxLevel = 3;

	public TowerDefinition Definition;
	public int32 Level = 1;
	public EntityId CurrentTargetId = .Invalid;
	public float FireCooldown = 0.0f;
	public int32 GridX;
	public int32 GridY;

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

	/// Returns true if this tower can be upgraded further.
	public bool CanUpgrade => Level < MaxLevel;

	/// Gets the cost to upgrade to the next level.
	public int32 GetUpgradeCost()
	{
		if (!CanUpgrade)
			return 0;
		return (int32)(Definition.UpgradeCost * (1.0f + (Level - 1) * 0.5f));
	}

	/// Gets the total value of this tower (for sell price calculation).
	public int32 GetTotalInvested()
	{
		int32 total = Definition.Cost;
		for (int32 lvl = 1; lvl < Level; lvl++)
		{
			total += (int32)(Definition.UpgradeCost * (1.0f + (lvl - 1) * 0.5f));
		}
		return total;
	}
}

/// Internal data for projectile tracking (replaces IEntityComponent).
class ProjectileData
{
	public EntityId TargetId = .Invalid;
	public float Damage;
	public float Speed;
	public Vector4 Color;
	public float HitRadius = 0.5f;
	public bool IsHoming = true;
	public Vector3 Direction = .Zero;
	public float MaxLifetime = 5.0f;
	public float Lifetime = 0.0f;
	public bool HasHit = false;
}

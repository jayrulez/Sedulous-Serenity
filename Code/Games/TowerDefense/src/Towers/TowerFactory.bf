namespace TowerDefense.Towers;

using System;
using System.Collections;
using Sedulous.Audio;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Engine.Core;
using Sedulous.Engine.Audio;
using Sedulous.Engine.Renderer;
using Sedulous.Foundation.Core;
using Sedulous.Renderer;
using TowerDefense.Data;
using TowerDefense.Audio;
using TowerDefense.Components;
using TowerDefense.Enemies;

/// Delegate for tower fire events (for audio/effects).
delegate void TowerFiredDelegate(TowerDefinition def, Vector3 position);

/// Factory for creating and managing towers and projectiles.
class TowerFactory
{
	private Scene mScene;
	private RendererService mRendererService;
	private EnemyFactory mEnemyFactory;
	private GameAudio mGameAudio;

	// Events
	private EventAccessor<TowerFiredDelegate> mOnTowerFired = new .() ~ delete _;

	/// Event fired when any tower fires (for audio/effects).
	public EventAccessor<TowerFiredDelegate> OnTowerFired => mOnTowerFired;

	// Shared meshes
	private StaticMesh mTowerMesh ~ delete _;
	private StaticMesh mProjectileMesh ~ delete _;

	// Base PBR material
	private MaterialHandle mPBRMaterial = .Invalid;

	// Material instances (keyed by color)
	private Dictionary<uint32, MaterialInstanceHandle> mMaterialCache = new .() ~ delete _;

	// Tower tracking
	private List<Entity> mTowers = new .() ~ delete _;
	private Dictionary<int64, Entity> mTowerGrid = new .() ~ delete _;  // GridKey -> Tower
	private int32 mTowerCounter = 0;

	// Projectile tracking
	private List<Entity> mProjectiles = new .() ~ delete _;
	private List<Entity> mProjectilesToRemove = new .() ~ delete _;
	private int32 mProjectileCounter = 0;

	// Temp list for enemy queries
	private List<Entity> mTempEnemyList = new .() ~ delete _;

	/// Number of active towers.
	public int32 TowerCount => (.)mTowers.Count;

	/// Creates a new TowerFactory.
	public this(Scene scene, RendererService rendererService, EnemyFactory enemyFactory, GameAudio gameAudio)
	{
		mScene = scene;
		mRendererService = rendererService;
		mEnemyFactory = enemyFactory;
		mGameAudio = gameAudio;
	}

	/// Initializes materials for tower and projectile rendering.
	public void InitializeMaterials()
	{
		let materialSystem = mRendererService.MaterialSystem;
		if (materialSystem == null)
			return;

		// Create tower mesh (tall cube)
		mTowerMesh = StaticMesh.CreateCube(1.0f);

		// Create projectile mesh (small cube)
		mProjectileMesh = StaticMesh.CreateCube(0.2f);

		// Create PBR material template
		let pbrMaterial = Material.CreatePBR("TowerMaterial");
		mPBRMaterial = materialSystem.RegisterMaterial(pbrMaterial);

		if (!mPBRMaterial.IsValid)
		{
			Console.WriteLine("TowerFactory: Failed to create PBR material");
			return;
		}

		Console.WriteLine("TowerFactory: Materials initialized");
	}

	/// Creates a material instance for the given color.
	private MaterialInstanceHandle GetOrCreateMaterial(Vector4 color)
	{
		uint32 colorKey = ((uint32)(color.X * 255) << 24) |
		                  ((uint32)(color.Y * 255) << 16) |
		                  ((uint32)(color.Z * 255) << 8) |
		                  ((uint32)(color.W * 255));

		if (mMaterialCache.TryGetValue(colorKey, let existing))
			return existing;

		let materialSystem = mRendererService.MaterialSystem;
		let handle = materialSystem.CreateInstance(mPBRMaterial);

		if (handle.IsValid)
		{
			let instance = materialSystem.GetInstance(handle);
			if (instance != null)
			{
				instance.SetFloat4("baseColor", color);
				instance.SetFloat("metallic", 0.5f);
				instance.SetFloat("roughness", 0.4f);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0, 0, 0, 1));
				materialSystem.UploadInstance(handle);
			}
			mMaterialCache[colorKey] = handle;
		}

		return handle;
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
	public Entity PlaceTower(TowerDefinition definition, Vector3 worldPos, int32 gridX, int32 gridY)
	{
		// Check if position is occupied
		let gridKey = GridKey(gridX, gridY);
		if (mTowerGrid.ContainsKey(gridKey))
		{
			Console.WriteLine("TowerFactory: Position already occupied!");
			return null;
		}

		mTowerCounter++;
		let entityName = scope $"Tower_{mTowerCounter}";
		let entity = mScene.CreateEntity(entityName);

		// Position tower
		float yPos = definition.Scale * 0.5f;  // Half height to sit on ground
		entity.Transform.SetPosition(.(worldPos.X, yPos, worldPos.Z));
		entity.Transform.SetScale(.(definition.Scale * 0.8f, definition.Scale, definition.Scale * 0.8f));

		// Add mesh component
		let meshComp = new StaticMeshComponent();
		entity.AddComponent(meshComp);
		meshComp.SetMesh(mTowerMesh);
		meshComp.SetMaterialInstance(0, GetOrCreateMaterial(definition.Color));

		// Add tower component
		let towerComp = new TowerComponent(definition);
		towerComp.GridX = gridX;
		towerComp.GridY = gridY;
		entity.AddComponent(towerComp);

		// Add audio source component for tower fire sounds
		let audioSource = new AudioSourceComponent();
		audioSource.Volume = mGameAudio?.SFXVolume ?? 0.1f;
		audioSource.MinDistance = 5.0f;   // Full volume within 5 units
		audioSource.MaxDistance = 50.0f;  // Fade out over 50 units
		entity.AddComponent(audioSource);

		// Subscribe to fire event
		towerComp.OnFire.Subscribe(new (tower, target, origin) =>
		{
			OnTowerFire(tower, target, origin, entity);
		});

		mTowers.Add(entity);
		mTowerGrid[gridKey] = entity;

		Console.WriteLine($"Placed {definition.Name} tower at ({gridX}, {gridY})");
		return entity;
	}

	/// Removes a tower and returns partial refund (50% of total invested).
	public int32 SellTower(Entity tower)
	{
		let towerComp = tower.GetComponent<TowerComponent>();
		if (towerComp == null)
			return 0;

		// Calculate refund (50% of total invested including upgrades)
		int32 refund = towerComp.GetTotalInvested() / 2;

		// Remove from grid
		let gridKey = GridKey(towerComp.GridX, towerComp.GridY);
		mTowerGrid.Remove(gridKey);

		// Remove from list and destroy
		mTowers.Remove(tower);
		mScene.DestroyEntity(tower.Id);

		Console.WriteLine($"Sold tower for ${refund}");
		return refund;
	}

	/// Called when a tower fires.
	private void OnTowerFire(TowerComponent tower, Entity target, Vector3 origin, Entity towerEntity)
	{
		SpawnProjectile(origin, target, tower.GetDamage(), tower.Definition.ProjectileSpeed, tower.Definition.ProjectileColor);

		// Play fire sound via tower's AudioSourceComponent
		if (mGameAudio != null)
		{
			let audioSource = towerEntity.GetComponent<AudioSourceComponent>();
			if (audioSource != null)
			{
				let clip = mGameAudio.GetTowerFireClip(tower.Definition.Name);
				if (clip != null)
					audioSource.Play(clip);
			}
		}

		// Notify external listeners (for visual effects, etc.)
		mOnTowerFired.[Friend]Invoke(tower.Definition, origin);
	}

	/// Spawns a projectile.
	private Entity SpawnProjectile(Vector3 origin, Entity target, float damage, float speed, Vector4 color)
	{
		mProjectileCounter++;
		let entityName = scope $"Projectile_{mProjectileCounter}";
		let entity = mScene.CreateEntity(entityName);

		// Position projectile
		entity.Transform.SetPosition(origin);
		entity.Transform.SetScale(.(1, 1, 1));

		// Add mesh component
		let meshComp = new StaticMeshComponent();
		entity.AddComponent(meshComp);
		meshComp.SetMesh(mProjectileMesh);
		meshComp.SetMaterialInstance(0, GetOrCreateMaterial(color));

		// Add projectile component
		let projComp = new ProjectileComponent(target, damage, speed);
		entity.AddComponent(projComp);

		// Subscribe to hit event
		projComp.OnHit.Subscribe(new (projectile, hitTarget) =>
		{
			OnProjectileHit(projectile, hitTarget, damage);
		});

		mProjectiles.Add(entity);
		return entity;
	}

	/// Called when a projectile hits a target.
	private void OnProjectileHit(Entity projectile, Entity target, float damage)
	{
		// Apply damage to target
		let healthComp = target.GetComponent<HealthComponent>();
		if (healthComp != null)
		{
			healthComp.TakeDamage(damage);
		}
	}

	/// Updates all towers (targeting) and projectiles.
	public void Update(float deltaTime)
	{
		// Get current enemies
		mEnemyFactory.GetActiveEnemies(mTempEnemyList);

		// Update tower targeting
		for (let tower in mTowers)
		{
			let towerComp = tower.GetComponent<TowerComponent>();
			if (towerComp == null)
				continue;

			// Find new target if needed
			if (towerComp.CurrentTarget == null || !towerComp.IsValidTarget(towerComp.CurrentTarget))
			{
				towerComp.CurrentTarget = towerComp.FindBestTarget(mTempEnemyList);
			}

			// Try to fire
			towerComp.TryFire();
		}

		// Clean up hit/expired projectiles
		mProjectilesToRemove.Clear();
		for (let projectile in mProjectiles)
		{
			let projComp = projectile.GetComponent<ProjectileComponent>();
			if (projComp != null && projComp.HasHit)
			{
				mProjectilesToRemove.Add(projectile);
			}
		}

		for (let projectile in mProjectilesToRemove)
		{
			mProjectiles.Remove(projectile);
			mScene.DestroyEntity(projectile.Id);
		}
	}

	/// Gets the tower at the given grid position, or null.
	public Entity GetTowerAt(int32 gridX, int32 gridY)
	{
		let gridKey = GridKey(gridX, gridY);
		if (mTowerGrid.TryGetValue(gridKey, let tower))
			return tower;
		return null;
	}

	/// Destroys all towers and projectiles.
	public void ClearAll()
	{
		for (let tower in mTowers)
			mScene.DestroyEntity(tower.Id);
		mTowers.Clear();
		mTowerGrid.Clear();

		for (let projectile in mProjectiles)
			mScene.DestroyEntity(projectile.Id);
		mProjectiles.Clear();
	}

	/// Cleans up materials.
	public void Cleanup()
	{
		ClearAll();

		let materialSystem = mRendererService?.MaterialSystem;
		if (materialSystem != null)
		{
			for (let handle in mMaterialCache.Values)
			{
				if (handle.IsValid)
					materialSystem.ReleaseInstance(handle);
			}
			mMaterialCache.Clear();

			if (mPBRMaterial.IsValid)
				materialSystem.ReleaseMaterial(mPBRMaterial);
		}

		mPBRMaterial = .Invalid;
	}
}

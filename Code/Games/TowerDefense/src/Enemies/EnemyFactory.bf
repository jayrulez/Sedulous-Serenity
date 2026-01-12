namespace TowerDefense.Enemies;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Foundation.Core;
using Sedulous.Renderer;
using TowerDefense.Data;
using TowerDefense.Components;

/// Delegate for enemy death events with position (for audio).
delegate void EnemyDeathAudioDelegate(Vector3 position);

/// Factory for creating enemy entities.
class EnemyFactory
{
	private Scene mScene;
	private RendererService mRendererService;
	private List<Vector3> mWaypoints;

	// Shared mesh for enemies (placeholder cube)
	private StaticMesh mEnemyMesh ~ delete _;

	// Base PBR material
	private MaterialHandle mPBRMaterial = .Invalid;

	// Material instances for different enemy types (keyed by color)
	private Dictionary<uint32, MaterialInstanceHandle> mMaterialCache = new .() ~ delete _;

	// Enemy tracking
	private List<Entity> mActiveEnemies = new .() ~ delete _;
	private int32 mEnemyCounter = 0;

	// Event accessors
	private EventAccessor<EnemyExitDelegate> mOnEnemyReachedExit = new .() ~ delete _;
	private EventAccessor<EnemyKilledDelegate> mOnEnemyKilled = new .() ~ delete _;
	private EventAccessor<EnemyDeathAudioDelegate> mOnEnemyDeathAudio = new .() ~ delete _;

	/// Event fired when an enemy reaches the exit.
	public EventAccessor<EnemyExitDelegate> OnEnemyReachedExit => mOnEnemyReachedExit;

	/// Event fired when an enemy dies.
	public EventAccessor<EnemyKilledDelegate> OnEnemyKilled => mOnEnemyKilled;

	/// Event fired when an enemy dies (with position for audio).
	public EventAccessor<EnemyDeathAudioDelegate> OnEnemyDeathAudio => mOnEnemyDeathAudio;

	/// Number of active enemies.
	public int32 ActiveEnemyCount => (.)mActiveEnemies.Count;

	/// Creates a new EnemyFactory.
	public this(Scene scene, RendererService rendererService)
	{
		mScene = scene;
		mRendererService = rendererService;
	}

	/// Sets the waypoints for enemy movement.
	public void SetWaypoints(List<Vector3> waypoints)
	{
		mWaypoints = waypoints;
	}

	/// Initializes materials for enemy rendering.
	public void InitializeMaterials()
	{
		let materialSystem = mRendererService.MaterialSystem;
		if (materialSystem == null)
			return;

		// Create placeholder enemy mesh (cube)
		mEnemyMesh = StaticMesh.CreateCube(1.0f);

		// Create PBR material template
		let pbrMaterial = Material.CreatePBR("EnemyMaterial");
		mPBRMaterial = materialSystem.RegisterMaterial(pbrMaterial);

		if (!mPBRMaterial.IsValid)
		{
			Console.WriteLine("EnemyFactory: Failed to create PBR material");
			return;
		}

		Console.WriteLine("EnemyFactory: Materials initialized");
	}

	/// Creates a material instance for the given color.
	private MaterialInstanceHandle GetOrCreateMaterial(Vector4 color)
	{
		// Create a color key from RGBA bytes
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
				instance.SetFloat("metallic", 0.3f);
				instance.SetFloat("roughness", 0.6f);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0, 0, 0, 1));
				materialSystem.UploadInstance(handle);
			}
			mMaterialCache[colorKey] = handle;
		}

		return handle;
	}

	/// Spawns a new enemy with the given definition.
	public Entity SpawnEnemy(EnemyDefinition definition)
	{
		if (mWaypoints == null || mWaypoints.Count < 2)
		{
			Console.WriteLine("EnemyFactory: No waypoints set!");
			return null;
		}

		mEnemyCounter++;
		let entityName = scope $"Enemy_{mEnemyCounter}";
		let entity = mScene.CreateEntity(entityName);

		// Set initial position and scale
		let spawnPos = mWaypoints[0];
		float yOffset = definition.Type == .Air ? 2.0f : 0.5f;
		entity.Transform.SetPosition(.(spawnPos.X, yOffset, spawnPos.Z));
		entity.Transform.SetScale(.(definition.Scale, definition.Scale, definition.Scale));

		// Add mesh component
		let meshComp = new StaticMeshComponent();
		entity.AddComponent(meshComp);
		meshComp.SetMesh(mEnemyMesh);
		meshComp.SetMaterialInstance(0, GetOrCreateMaterial(definition.Color));

		// Add health component
		let healthComp = new HealthComponent(definition.MaxHealth);
		entity.AddComponent(healthComp);

		// Subscribe to death event
		healthComp.OnDeath.Subscribe(new () =>
		{
			OnEnemyDeath(entity, definition.Reward);
		});

		// Add enemy component
		let enemyComp = new EnemyComponent(definition, mWaypoints);
		entity.AddComponent(enemyComp);

		// Subscribe to exit event
		enemyComp.OnReachedExit.Subscribe(new (enemy) =>
		{
			mOnEnemyReachedExit.[Friend]Invoke(enemy);
			RemoveEnemy(entity);
		});

		mActiveEnemies.Add(entity);
		return entity;
	}

	/// Called when an enemy dies.
	private void OnEnemyDeath(Entity entity, int32 reward)
	{
		// Capture position before removing enemy
		let position = entity.Transform.WorldPosition;

		mOnEnemyKilled.[Friend]Invoke(entity, reward);
		mOnEnemyDeathAudio.[Friend]Invoke(position);
		RemoveEnemy(entity);
	}

	/// Removes an enemy from tracking and destroys it.
	private void RemoveEnemy(Entity entity)
	{
		mActiveEnemies.Remove(entity);
		mScene.DestroyEntity(entity.Id);
	}

	/// Gets all active enemies.
	public void GetActiveEnemies(List<Entity> outList)
	{
		outList.Clear();
		for (let enemy in mActiveEnemies)
		{
			outList.Add(enemy);
		}
	}

	/// Destroys all active enemies.
	public void ClearAllEnemies()
	{
		for (let entity in mActiveEnemies)
		{
			mScene.DestroyEntity(entity.Id);
		}
		mActiveEnemies.Clear();
	}

	/// Cleans up materials.
	public void Cleanup()
	{
		ClearAllEnemies();

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

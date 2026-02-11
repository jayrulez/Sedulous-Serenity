namespace Platformer.Levels;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Resources;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Render;
using Sedulous.Logging.Abstractions;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Animation;
using Sedulous.Framework.Physics;
using Platformer.Data;
using Platformer.Components;
using Platformer.Assets;

/// Builds scene entities from a LevelDefinition.
class LevelBuilder
{
	private Scene mScene;
	private RenderSceneModule mRenderModule;
	private PhysicsSceneModule mPhysicsModule;
	private AssetLoader mAssetLoader;
	private ILogger mLogger;

	// Created entities for cleanup
	private List<EntityId> mLevelEntities = new .() ~ delete _;

	// Player entity
	private EntityId mPlayerEntity = .Invalid;
	private EntityId mGoalEntity = .Invalid;

	// Pickup/enemy/hazard entities for game logic
	private List<EntityId> mPickupEntities = new .() ~ delete _;
	private List<EntityId> mEnemyEntities = new .() ~ delete _;
	private List<EntityId> mHazardEntities = new .() ~ delete _;
	private List<EntityId> mMovingPlatformEntities = new .() ~ delete _;
	private List<EntityId> mDoorEntities = new .() ~ delete _;

	public EntityId PlayerEntity => mPlayerEntity;
	public EntityId GoalEntity => mGoalEntity;
	public List<EntityId> PickupEntities => mPickupEntities;
	public List<EntityId> EnemyEntities => mEnemyEntities;
	public List<EntityId> HazardEntities => mHazardEntities;
	public List<EntityId> MovingPlatformEntities => mMovingPlatformEntities;
	public List<EntityId> DoorEntities => mDoorEntities;

	public this(Scene scene, RenderSceneModule renderModule, PhysicsSceneModule physicsModule, AssetLoader assetLoader, ILogger logger)
	{
		mScene = scene;
		mRenderModule = renderModule;
		mPhysicsModule = physicsModule;
		mAssetLoader = assetLoader;
		mLogger = logger;
	}

	/// Builds the level from the given definition.
	public void BuildLevel(LevelDefinition level)
	{
		ClearLevel();

		mLogger?.LogInformation("Building '{}' ({}x{})", level.Name, level.Width, level.Height);

		if (mScene == null)
		{
			mLogger?.LogError("Scene is null, cannot build level");
			return;
		}
		if (mAssetLoader == null)
		{
			mLogger?.LogError("AssetLoader is null, cannot build level");
			return;
		}

		// Build tile entities
		int32 tileCount = 0;
		int32 tilePhysicsFails = 0;
		for (int32 y = 0; y < level.Height; y++)
		{
			for (int32 x = 0; x < level.Width; x++)
			{
				let tileType = level.GetTile(x, y);
				if (tileType == .Empty)
					continue;

				let worldPos = level.GridToWorld(x, y);
				CreateTileEntity(tileType, worldPos, level.TileSize, ref tilePhysicsFails);
				tileCount++;
			}
		}
		mLogger?.LogDebug("Created {} tile entities", tileCount);
		if (tilePhysicsFails > 0)
			mLogger?.LogWarning("{} tile physics bodies failed to create", tilePhysicsFails);

		// Create player
		let spawnPos = level.GridToWorld(level.SpawnX, level.SpawnY);
		CreatePlayerEntity(.(spawnPos.X, spawnPos.Y + 0.5f, 0));
		mLogger?.LogDebug("Player spawned at grid ({},{})", level.SpawnX, level.SpawnY);

		// Create goal flag
		let goalPos = level.GridToWorld(level.GoalX, level.GoalY);
		CreateGoalEntity(.(goalPos.X, goalPos.Y + 0.5f, 0));

		// Create enemies
		for (let enemy in level.Enemies)
		{
			let pos = level.GridToWorld(enemy.GridX, enemy.GridY);
			let patrolL = enemy.PatrolLeft >= 0 ? (float)(enemy.PatrolLeft) * level.TileSize : pos.X - 3.0f;
			let patrolR = enemy.PatrolRight >= 0 ? (float)(enemy.PatrolRight + 1) * level.TileSize : pos.X + 3.0f;
			CreateEnemyEntity(enemy.Type, .(pos.X, pos.Y + 0.5f, 0), patrolL, patrolR);
		}

		// Create moving platforms
		for (let mp in level.MovingPlatforms)
		{
			let startPos = level.GridToWorld(mp.StartX, mp.StartY);
			let endPos = level.GridToWorld(mp.EndX, mp.EndY);
			CreateMovingPlatformEntity(startPos, endPos, mp.Speed);
		}

		// Create moving hazards
		for (let hz in level.MovingHazards)
		{
			let startPos = level.GridToWorld(hz.StartX, hz.StartY);
			let endPos = level.GridToWorld(hz.EndX, hz.EndY);
			CreateMovingHazardEntity(hz.Type, startPos, endPos, hz.Speed);
		}

		// Add background clouds
		AddBackgroundClouds(level);

		mLogger?.LogInformation("Build complete - {} total entities ({} enemies, {} pickups, {} hazards, {} platforms, {} doors)",
			mLevelEntities.Count, mEnemyEntities.Count, mPickupEntities.Count,
			mHazardEntities.Count, mMovingPlatformEntities.Count, mDoorEntities.Count);
	}

	private void CreateTileEntity(TileType tileType, Vector3 worldPos, float tileSize, ref int32 physicsFails)
	{
		let entity = mScene.CreateEntity();

		var transform = mScene.GetTransform(entity);
		transform.Position = worldPos;
		transform.Scale = .(tileSize, tileSize, tileSize);
		mScene.SetTransform(entity, transform);

		// Get mesh key for this tile type
		StringView meshKey;
		switch (tileType)
		{
		case .Grass: meshKey = "cube_grass";
		case .Dirt: meshKey = "cube_dirt";
		case .Brick: meshKey = "cube_brick";
		case .Crate: meshKey = "cube_crate";
		case .Spike: meshKey = "cube_spike";
		case .Question: meshKey = "cube_question";
		case .Exclamation: meshKey = "cube_exclamation";
		default: meshKey = "cube_dirt";
		}

		SetMeshFromAsset(entity, meshKey);

		// Create physics body for solid tiles
		if (tileType.IsSolid && mPhysicsModule != null)
		{
			if (mPhysicsModule.CreateBoxBody(entity, .(tileSize * 0.5f, tileSize * 0.5f, tileSize * 0.5f), .Static) case .Err)
				physicsFails++;
		}

		// Spikes get a hazard component
		if (tileType.IsHazard)
		{
			mScene.SetComponent<HazardComponent>(entity, HazardComponent.CreateSpike());
			mHazardEntities.Add(entity);
		}

		mLevelEntities.Add(entity);
	}

	private void CreatePlayerEntity(Vector3 position)
	{
		mPlayerEntity = mScene.CreateEntity();
		mScene.SetName(mPlayerEntity, "Player");

		var transform = mScene.GetTransform(mPlayerEntity);
		transform.Position = position;
		transform.Scale = .(0.8f, 0.8f, 0.8f);
		// Rotate +90° around Y so model faces +X (right)
		transform.Rotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), Math.PI_f / 2.0f);
		mScene.SetTransform(mPlayerEntity, transform);

		SetSkinnedMeshFromAsset(mPlayerEntity, "character");

		mScene.SetComponent<PlayerComponent>(mPlayerEntity, PlayerComponent.Default);

		// Capsule collider for the player (center-origin, total height = 2*halfHeight + 2*radius = 1.0)
		if (mPhysicsModule != null)
		{
			if (mPhysicsModule.CreateCapsuleBody(mPlayerEntity, 0.25f, 0.25f, .Kinematic) case .Err)
				mLogger?.LogWarning("Failed to create player physics body");
		}

		mLevelEntities.Add(mPlayerEntity);
	}

	private void CreateGoalEntity(Vector3 position)
	{
		mGoalEntity = mScene.CreateEntity();
		mScene.SetName(mGoalEntity, "GoalFlag");

		var transform = mScene.GetTransform(mGoalEntity);
		transform.Position = position;
		transform.Scale = .(1.0f, 1.0f, 1.0f);
		mScene.SetTransform(mGoalEntity, transform);

		SetMeshFromAsset(mGoalEntity, "goal_flag");

		mLevelEntities.Add(mGoalEntity);
	}

	private void CreateEnemyEntity(EnemyType type, Vector3 position, float patrolLeft, float patrolRight)
	{
		let entity = mScene.CreateEntity();

		var transform = mScene.GetTransform(entity);
		transform.Position = position;
		transform.Scale = .(0.8f, 0.8f, 0.8f);
		mScene.SetTransform(entity, transform);

		StringView meshKey;
		switch (type)
		{
		case .Slime: meshKey = "enemy_slime";
		case .Bee: meshKey = "enemy_bee";
		case .Crab: meshKey = "enemy_crab";
		case .Skull: meshKey = "enemy_skull";
		}

		SetSkinnedMeshFromAsset(entity, meshKey);

		mScene.SetComponent<EnemyComponent>(entity, EnemyComponent.Create(type, patrolLeft, patrolRight, position.Y));

		if (mPhysicsModule != null)
		{
			if (mPhysicsModule.CreateBoxBody(entity, .(0.4f, 0.4f, 0.4f), .Kinematic) case .Err)
				mLogger?.LogWarning("Failed to create enemy physics body (type={})", type);
		}

		mEnemyEntities.Add(entity);
		mLevelEntities.Add(entity);
	}

	/// Creates a pickup entity at the given position.
	public void CreatePickupEntity(PickupType type, Vector3 position)
	{
		let entity = mScene.CreateEntity();

		var transform = mScene.GetTransform(entity);
		transform.Position = position;
		transform.Scale = .(0.5f, 0.5f, 0.5f);
		mScene.SetTransform(entity, transform);

		StringView meshKey;
		switch (type)
		{
		case .Coin: meshKey = "coin";
		case .GemBlue: meshKey = "gem_blue";
		case .GemGreen: meshKey = "gem_green";
		case .GemPink: meshKey = "gem_pink";
		case .Heart: meshKey = "heart";
		case .Key: meshKey = "key";
		case .Star: meshKey = "star";
		}

		SetMeshFromAsset(entity, meshKey);

		mScene.SetComponent<PickupComponent>(entity, PickupComponent.Create(type));

		mPickupEntities.Add(entity);
		mLevelEntities.Add(entity);
	}

	/// Creates a door entity at the given position.
	public void CreateDoorEntity(Vector3 position)
	{
		let entity = mScene.CreateEntity();

		var transform = mScene.GetTransform(entity);
		transform.Position = position;
		transform.Scale = .(1.0f, 1.5f, 1.0f);
		mScene.SetTransform(entity, transform);

		SetMeshFromAsset(entity, "door");

		if (mPhysicsModule != null)
		{
			if (mPhysicsModule.CreateBoxBody(entity, .(0.5f, 0.75f, 0.5f), .Static) case .Err)
				mLogger?.LogWarning("Failed to create door physics body");
		}

		mDoorEntities.Add(entity);
		mLevelEntities.Add(entity);
	}

	/// Creates a bouncer (spring pad) entity.
	public void CreateBouncerEntity(Vector3 position)
	{
		let entity = mScene.CreateEntity();

		var transform = mScene.GetTransform(entity);
		transform.Position = position;
		transform.Scale = .(0.8f, 0.5f, 0.8f);
		mScene.SetTransform(entity, transform);

		SetMeshFromAsset(entity, "bouncer");

		if (mPhysicsModule != null)
		{
			if (mPhysicsModule.CreateBoxBody(entity, .(0.4f, 0.25f, 0.4f), .Static) case .Err)
				mLogger?.LogWarning("Failed to create bouncer physics body");
		}

		// Mark as a special hazard type (bouncer) for collision handling
		var hazard = HazardComponent();
		hazard.Type = .Spike; // Will be identified by mesh/entity, not hazard type
		hazard.Damage = 0; // No damage, just bounce
		mScene.SetComponent<HazardComponent>(entity, hazard);

		mHazardEntities.Add(entity);
		mLevelEntities.Add(entity);
	}

	private void CreateMovingPlatformEntity(Vector3 startPos, Vector3 endPos, float speed)
	{
		let entity = mScene.CreateEntity();

		var transform = mScene.GetTransform(entity);
		transform.Position = startPos;
		transform.Scale = .(1.5f, 0.3f, 1.0f);
		mScene.SetTransform(entity, transform);

		SetMeshFromAsset(entity, "cube_grass");

		mScene.SetComponent<MovingPlatformComponent>(entity, MovingPlatformComponent.Create(startPos, endPos, speed));

		if (mPhysicsModule != null)
		{
			if (mPhysicsModule.CreateBoxBody(entity, .(0.75f, 0.15f, 0.5f), .Kinematic) case .Err)
				mLogger?.LogWarning("Failed to create moving platform physics body");
		}

		mMovingPlatformEntities.Add(entity);
		mLevelEntities.Add(entity);
	}

	private void CreateMovingHazardEntity(HazardType type, Vector3 startPos, Vector3 endPos, float speed)
	{
		let entity = mScene.CreateEntity();

		var transform = mScene.GetTransform(entity);
		transform.Position = startPos;
		transform.Scale = .(0.8f, 0.8f, 0.8f);
		mScene.SetTransform(entity, transform);

		StringView meshKey;
		switch (type)
		{
		case .Saw: meshKey = "saw";
		case .SpikyBall: meshKey = "spikyball";
		default: meshKey = "saw";
		}

		SetMeshFromAsset(entity, meshKey);

		var hazard = HazardComponent();
		hazard.Type = type;
		hazard.Damage = 1;
		hazard.Active = true;
		hazard.Speed = speed;
		hazard.StartPos = startPos;
		hazard.EndPos = endPos;
		hazard.Direction = 1.0f;
		mScene.SetComponent<HazardComponent>(entity, hazard);

		mHazardEntities.Add(entity);
		mLevelEntities.Add(entity);
	}

	/// Creates a decoration entity (tree, rock, etc) at the given position.
	public void CreateDecorationEntity(StringView meshKey, Vector3 position, Vector3 scale)
	{
		let entity = mScene.CreateEntity();

		var transform = mScene.GetTransform(entity);
		transform.Position = position;
		transform.Scale = scale;
		mScene.SetTransform(entity, transform);

		SetMeshFromAsset(entity, meshKey);

		mLevelEntities.Add(entity);
	}

	private void AddBackgroundClouds(LevelDefinition level)
	{
		// Place a few clouds in the background at various heights
		let levelWidth = level.Width * level.TileSize;
		let cloudY = level.Height * level.TileSize + 3.0f;
		let cloudZ = -8.0f; // Behind the play area

		String[3] cloudKeys = .("cloud1", "cloud2", "cloud3");
		float xStep = levelWidth / 5.0f;

		for (int i = 0; i < 5; i++)
		{
			let x = xStep * (i + 0.5f);
			let yOffset = (i % 3) * 1.5f;
			let cloudKey = cloudKeys[i % 3];
			CreateDecorationEntity(cloudKey, .(x, cloudY + yOffset, cloudZ), .(2.0f, 2.0f, 2.0f));
		}
	}

	private void SetSkinnedMeshFromAsset(EntityId entity, StringView meshKey)
	{
		ResourceRef meshRef;
		List<ResourceRef> materialRefs;
		ResourceRef skeletonRef;
		List<ResourceRef> animationRefs;
		if (mAssetLoader.GetSkinnedMeshRef(meshKey, out meshRef, out materialRefs, out skeletonRef, out animationRefs))
		{
			var comp = SkinnedMeshRendererComponent.Default;
			comp.MeshRef = meshRef;
			comp.Enabled = true;

			if (materialRefs != null && materialRefs.Count > 0)
			{
				comp.MaterialCount = (int32)Math.Min(materialRefs.Count, RenderConfig.MaxMaterialsPerMesh);
				for (int32 i = 0; i < comp.MaterialCount; i++)
					comp.MaterialRefs[i] = ResourceRef(materialRefs[i].Id, materialRefs[i].Path);
			}

			mScene.SetComponent<SkinnedMeshRendererComponent>(entity, comp);

			// Set up skeletal animation - use Idle animation by default
			if (skeletonRef.IsValid && animationRefs != null && animationRefs.Count > 0)
			{
				var animComp = SkeletalAnimationComponent.Default;
				animComp.SkeletonRef = skeletonRef;

				// Try to find "Idle" animation, fall back to first
				var defaultRef = ResourceRef();
				if (mAssetLoader.GetDefaultAnimationRef(meshKey, out defaultRef))
				{
					animComp.AnimationClipRef = defaultRef;
				}
				else
				{
					animComp.AnimationClipRef = ResourceRef(animationRefs[0].Id, animationRefs[0].Path);
				}

				animComp.Playing = true;
				animComp.Loop = true;
				mScene.SetComponent<SkeletalAnimationComponent>(entity, animComp);
			}
		}
		else
		{
			// Fallback to static mesh (e.g. placeholder mode uses cubes for all models)
			mLogger?.LogDebug("No skinned mesh for '{}', falling back to static mesh", meshKey);
			SetMeshFromAsset(entity, meshKey);
		}
	}

	private void SetMeshFromAsset(EntityId entity, StringView meshKey)
	{
		ResourceRef meshRef;
		List<ResourceRef> materialRefs;
		if (mAssetLoader.GetMeshRef(meshKey, out meshRef, out materialRefs))
		{
			var comp = MeshRendererComponent.Default;
			comp.MeshRef = meshRef;
			comp.Enabled = true;

			if (materialRefs != null && materialRefs.Count > 0)
			{
				comp.MaterialCount = (int32)Math.Min(materialRefs.Count, RenderConfig.MaxMaterialsPerMesh);
				for (int32 i = 0; i < comp.MaterialCount; i++)
					comp.MaterialRefs[i] = ResourceRef(materialRefs[i].Id, materialRefs[i].Path);
			}

			mScene.SetComponent<MeshRendererComponent>(entity, comp);
		}
		else
		{
			mLogger?.LogWarning("Failed to set mesh '{}' on entity", meshKey);
		}
	}

	/// Clears all level entities from the scene.
	public void ClearLevel()
	{
		if (mLevelEntities.Count > 0)
			mLogger?.LogDebug("Clearing {} level entities", mLevelEntities.Count);

		for (let entity in mLevelEntities)
			mScene.DestroyEntity(entity);

		mLevelEntities.Clear();
		mPickupEntities.Clear();
		mEnemyEntities.Clear();
		mHazardEntities.Clear();
		mMovingPlatformEntities.Clear();
		mDoorEntities.Clear();
		mPlayerEntity = .Invalid;
		mGoalEntity = .Invalid;
	}
}

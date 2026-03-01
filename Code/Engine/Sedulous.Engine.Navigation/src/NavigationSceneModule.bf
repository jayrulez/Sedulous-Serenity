namespace Sedulous.Engine.Navigation;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Engine.Render;
using Sedulous.Core.Mathematics;
using Sedulous.Render;
using recastnavigation_Beef;

/// Internal data for a navigation agent. All agent state is owned here.
public struct NavAgentInstanceData
{
	public EntityId Entity;
	public int32 AgentIndex;          // Index in CrowdManager (-1 if not yet created)
	public bool SyncToTransform;
	public float Radius;
	public float Height;
	public float MaxAcceleration;
	public float MaxSpeed;
	public float CollisionQueryRange;
	public float PathOptimizationRange;
	public float SeparationWeight;
	public uint8 ObstacleAvoidanceType;
	public bool Active;               // Slot in use
}

/// Internal data for a navigation obstacle.
public struct NavObstacleInstanceData
{
	public EntityId Entity;
	public int32 ObstacleId;          // ID in TileCache (-1 if not yet created)
	public float Radius;
	public float Height;
	public bool Active;               // Slot in use
}

/// Scene module that manages navigation agents and obstacles for entities.
/// Created automatically by NavigationSubsystem for each scene.
///
/// All navigation data is owned by this module in internal instance storage.
/// Components are thin handles into this storage.
class NavigationSceneModule : SceneModule
{
	private NavigationSubsystem mSubsystem;
	private NavWorld mNavWorld;
	private Scene mScene;

	// Agent instance storage
	private List<NavAgentInstanceData> mAgentInstances = new .() ~ delete _;
	private List<int32> mFreeAgentSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToAgent = new .() ~ delete _;

	// Obstacle instance storage
	private List<NavObstacleInstanceData> mObstacleInstances = new .() ~ delete _;
	private List<int32> mFreeObstacleSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToObstacle = new .() ~ delete _;

	// Debug drawing
	private bool mDebugDrawEnabled = false;
	private duDebugDrawHandle mDebugDraw;

	/// Creates a NavigationSceneModule with the given world.
	public this(NavigationSubsystem subsystem, NavWorld navWorld)
	{
		mSubsystem = subsystem;
		mNavWorld = navWorld;
	}

	public ~this()
	{
		if (mDebugDraw != null)
		{
			duDestroyDebugDraw(mDebugDraw);
			mDebugDraw = null;
		}
	}

	/// Gets the navigation subsystem.
	public NavigationSubsystem Subsystem => mSubsystem;

	/// Gets the NavWorld for this scene.
	public NavWorld NavWorld => mNavWorld;

	/// Gets or sets whether navigation debug drawing is enabled.
	public bool DebugDrawEnabled
	{
		get => mDebugDrawEnabled;
		set => mDebugDrawEnabled = value;
	}

	/// Provides read access to agent instances for serialization.
	public List<NavAgentInstanceData> AgentInstances => mAgentInstances;

	/// Provides read access to obstacle instances for serialization.
	public List<NavObstacleInstanceData> ObstacleInstances => mObstacleInstances;

	// ==================== Agent Management ====================

	/// Adds a navigation agent for an entity.
	/// Returns the agent index, or -1 on failure.
	public int32 AddAgent(EntityId entity, float[3] position, in CrowdAgentParams @params)
	{
		if (mScene == null || mNavWorld == null)
			return -1;

		int32 agentIndex = mNavWorld.AddAgent(position, @params);
		if (agentIndex < 0)
			return -1;

		// Allocate instance slot
		int32 slotIdx;
		if (mFreeAgentSlots.Count > 0)
		{
			slotIdx = mFreeAgentSlots.PopBack();
		}
		else
		{
			slotIdx = (int32)mAgentInstances.Count;
			mAgentInstances.Add(.());
		}

		var instance = ref mAgentInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.AgentIndex = agentIndex;
		instance.SyncToTransform = true;
		instance.Radius = @params.Radius;
		instance.Height = @params.Height;
		instance.MaxAcceleration = @params.MaxAcceleration;
		instance.MaxSpeed = @params.MaxSpeed;
		instance.CollisionQueryRange = @params.CollisionQueryRange;
		instance.PathOptimizationRange = @params.PathOptimizationRange;
		instance.SeparationWeight = @params.SeparationWeight;
		instance.ObstacleAvoidanceType = @params.ObstacleAvoidanceType;
		instance.Active = true;
		mEntityToAgent[entity] = slotIdx;

		// Set thin handle on entity
		var comp = mScene.GetComponent<NavAgentComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<NavAgentComponent>(entity, .());
			comp = mScene.GetComponent<NavAgentComponent>(entity);
		}
		comp.InternalHandle = slotIdx;

		return agentIndex;
	}

	/// Creates an agent instance from serialization data (deferred — agent not yet created in CrowdManager).
	public void CreateAgentFromData(EntityId entity, NavAgentComponentData data)
	{
		if (mScene == null)
			return;

		int32 slotIdx;
		if (mFreeAgentSlots.Count > 0)
		{
			slotIdx = mFreeAgentSlots.PopBack();
		}
		else
		{
			slotIdx = (int32)mAgentInstances.Count;
			mAgentInstances.Add(.());
		}

		var instance = ref mAgentInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.AgentIndex = -1; // Will be assigned during AutoCreateAgents
		instance.SyncToTransform = data.SyncToTransform;
		instance.Radius = data.Radius;
		instance.Height = data.Height;
		instance.MaxAcceleration = data.MaxAcceleration;
		instance.MaxSpeed = data.MaxSpeed;
		instance.CollisionQueryRange = data.CollisionQueryRange;
		instance.PathOptimizationRange = data.PathOptimizationRange;
		instance.SeparationWeight = data.SeparationWeight;
		instance.ObstacleAvoidanceType = data.ObstacleAvoidanceType;
		instance.Active = true;
		mEntityToAgent[entity] = slotIdx;

		// Set thin handle on entity
		var comp = mScene.GetComponent<NavAgentComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<NavAgentComponent>(entity, .());
			comp = mScene.GetComponent<NavAgentComponent>(entity);
		}
		comp.InternalHandle = slotIdx;
	}

	/// Removes the navigation agent for an entity.
	public void RemoveAgent(EntityId entity)
	{
		if (mScene == null || mNavWorld == null)
			return;

		if (!mEntityToAgent.TryGetValue(entity, let slotIdx))
			return;

		var instance = ref mAgentInstances[slotIdx];
		if (instance.Active)
		{
			if (instance.AgentIndex >= 0)
				mNavWorld.RemoveAgent(instance.AgentIndex);
			instance.Active = false;
			mFreeAgentSlots.Add(slotIdx);
		}
		mEntityToAgent.Remove(entity);

		if (let comp = mScene.GetComponent<NavAgentComponent>(entity))
			comp.InternalHandle = -1;
	}

	/// Gets the agent index (CrowdManager handle) for an entity.
	public int32 GetAgentIndex(EntityId entity)
	{
		if (!mEntityToAgent.TryGetValue(entity, let slotIdx))
			return -1;
		let instance = ref mAgentInstances[slotIdx];
		if (instance.Active)
			return instance.AgentIndex;
		return -1;
	}

	// ==================== Obstacle Management ====================

	/// Adds a dynamic obstacle for an entity.
	/// Returns the obstacle ID, or -1 on failure.
	public int32 AddObstacle(EntityId entity, float[3] position, float radius, float height)
	{
		if (mScene == null || mNavWorld == null)
			return -1;

		int32 obstacleId = mNavWorld.AddObstacle(position, radius, height);
		if (obstacleId < 0)
			return -1;

		int32 slotIdx;
		if (mFreeObstacleSlots.Count > 0)
		{
			slotIdx = mFreeObstacleSlots.PopBack();
		}
		else
		{
			slotIdx = (int32)mObstacleInstances.Count;
			mObstacleInstances.Add(.());
		}

		var instance = ref mObstacleInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.ObstacleId = obstacleId;
		instance.Radius = radius;
		instance.Height = height;
		instance.Active = true;
		mEntityToObstacle[entity] = slotIdx;

		// Set thin handle on entity
		var comp = mScene.GetComponent<NavObstacleComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<NavObstacleComponent>(entity, .());
			comp = mScene.GetComponent<NavObstacleComponent>(entity);
		}
		comp.InternalHandle = slotIdx;

		return obstacleId;
	}

	/// Creates an obstacle instance from serialization data (deferred).
	public void CreateObstacleFromData(EntityId entity, NavObstacleComponentData data)
	{
		if (mScene == null)
			return;

		int32 slotIdx;
		if (mFreeObstacleSlots.Count > 0)
		{
			slotIdx = mFreeObstacleSlots.PopBack();
		}
		else
		{
			slotIdx = (int32)mObstacleInstances.Count;
			mObstacleInstances.Add(.());
		}

		var instance = ref mObstacleInstances[slotIdx];
		instance = .();
		instance.Entity = entity;
		instance.ObstacleId = -1; // Will be created when navmesh is available
		instance.Radius = data.Radius;
		instance.Height = data.Height;
		instance.Active = true;
		mEntityToObstacle[entity] = slotIdx;

		var comp = mScene.GetComponent<NavObstacleComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<NavObstacleComponent>(entity, .());
			comp = mScene.GetComponent<NavObstacleComponent>(entity);
		}
		comp.InternalHandle = slotIdx;
	}

	/// Removes the dynamic obstacle for an entity.
	public void RemoveObstacle(EntityId entity)
	{
		if (mScene == null || mNavWorld == null)
			return;

		if (!mEntityToObstacle.TryGetValue(entity, let slotIdx))
			return;

		var instance = ref mObstacleInstances[slotIdx];
		if (instance.Active)
		{
			if (instance.ObstacleId >= 0)
				mNavWorld.RemoveObstacle(instance.ObstacleId);
			instance.Active = false;
			mFreeObstacleSlots.Add(slotIdx);
		}
		mEntityToObstacle.Remove(entity);

		if (let comp = mScene.GetComponent<NavObstacleComponent>(entity))
			comp.InternalHandle = -1;
	}

	/// Gets obstacle dimensions for an entity. Returns false if entity has no obstacle.
	public bool GetObstacleData(EntityId entity, out float radius, out float height)
	{
		radius = 0;
		height = 0;
		if (!mEntityToObstacle.TryGetValue(entity, let slotIdx))
			return false;
		let instance = ref mObstacleInstances[slotIdx];
		if (!instance.Active)
			return false;
		radius = instance.Radius;
		height = instance.Height;
		return true;
	}

	// ==================== High-Level Operations ====================

	/// Builds a navigation mesh from the provided geometry.
	public bool BuildNavMesh(IInputGeometryProvider geometry, in NavMeshBuildConfig config)
	{
		if (mNavWorld == null)
			return false;

		var tiledConfig = config;
		if (tiledConfig.TileSize <= 0)
			tiledConfig.TileSize = 48;

		let result = NavMeshBuilder.BuildTiled(geometry, tiledConfig);
		defer delete result;

		if (!result.Success || result.NavMesh == null)
		{
			if (result.ErrorMessage != null)
				Console.WriteLine(scope $"NavMesh build failed: {result.ErrorMessage}");
			else
				Console.WriteLine("NavMesh build failed: unknown error");
			return false;
		}

		Console.WriteLine(scope $"NavMesh built: {result.Stats.PolyCount} polys, {result.Stats.TileCount} tiles");
		mNavWorld.SetNavMeshWithTileCache(result.NavMesh, result.TileCache);
		result.NavMesh = null;
		result.TileCache = null;
		return true;
	}

	/// Builds a simple single-tile navigation mesh.
	public bool BuildNavMeshSimple(IInputGeometryProvider geometry, in NavMeshBuildConfig config)
	{
		if (mNavWorld == null)
			return false;

		let result = NavMeshBuilder.BuildSingle(geometry, config);
		defer delete result;

		if (!result.Success || result.NavMesh == null)
		{
			if (result.ErrorMessage != null)
				Console.WriteLine(scope $"NavMesh build failed: {result.ErrorMessage}");
			else
				Console.WriteLine("NavMesh build failed: unknown error");
			return false;
		}

		Console.WriteLine(scope $"NavMesh built: {result.Stats.PolyCount} polys, {result.Stats.VertexCount} verts");
		mNavWorld.SetNavMesh(result.NavMesh);
		result.NavMesh = null;
		return true;
	}

	/// Sets the move target for an entity's agent.
	public bool RequestMoveTarget(EntityId entity, float[3] targetPos)
	{
		if (mScene == null || mNavWorld == null)
			return false;

		if (!mEntityToAgent.TryGetValue(entity, let slotIdx))
			return false;

		let instance = ref mAgentInstances[slotIdx];
		if (instance.Active && instance.AgentIndex >= 0)
			return mNavWorld.RequestMoveTarget(instance.AgentIndex, targetPos);

		return false;
	}

	/// Finds a path between two world positions.
	public bool FindPath(float[3] start, float[3] end, List<float> outWaypoints)
	{
		if (mNavWorld == null)
			return false;
		return mNavWorld.FindPath(start, end, outWaypoints);
	}

	/// Gets the current position of an entity's crowd agent.
	public bool GetAgentPosition(EntityId entity, out float[3] position)
	{
		position = default;
		if (mScene == null || mNavWorld == null)
			return false;

		let crowd = mNavWorld.Crowd;
		if (crowd == null)
			return false;

		if (!mEntityToAgent.TryGetValue(entity, let slotIdx))
			return false;

		let instance = ref mAgentInstances[slotIdx];
		if (instance.Active && instance.AgentIndex >= 0 && crowd.IsAgentActive(instance.AgentIndex))
		{
			crowd.GetAgentPosition(instance.AgentIndex, out position);
			return true;
		}
		return false;
	}

	// ==================== SceneModule Lifecycle ====================

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;

		// Register custom serializers
		scene.RegisterComponentSerializer(new NavAgentComponentSerializer());
		scene.RegisterComponentSerializer(new NavObstacleComponentSerializer());
	}

	public override void OnSceneDestroy(Scene scene)
	{
		// Just clear instance tracking — the NavWorld is destroyed by
		// NavigationSubsystem.OnSceneDestroyed, so no need to remove
		// individual agents/obstacles (and the world may already be deleted).
		mAgentInstances.Clear();
		mFreeAgentSlots.Clear();
		mEntityToAgent.Clear();

		mObstacleInstances.Clear();
		mFreeObstacleSlots.Clear();
		mEntityToObstacle.Clear();

		mNavWorld = null;
		mScene = null;
	}

	public override void FixedUpdate(Scene scene, float fixedDeltaTime)
	{
		if (mNavWorld == null)
			return;

		mNavWorld.Update(fixedDeltaTime);
	}

	public override void Update(Scene scene, float deltaTime)
	{
		if (mNavWorld == null || mScene == null)
			return;

		AutoCreateAgents();
		SyncAgentTransforms();
	}

	public override void PostUpdate(Scene scene, float deltaTime)
	{
		if (!mDebugDrawEnabled || mNavWorld == null || mScene == null)
			return;

		DrawDebug();
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		// Clean up agent
		if (mEntityToAgent.TryGetValue(entity, let agentSlot))
		{
			var instance = ref mAgentInstances[agentSlot];
			if (instance.Active)
			{
				if (instance.AgentIndex >= 0 && mNavWorld != null)
					mNavWorld.RemoveAgent(instance.AgentIndex);
				instance.Active = false;
				mFreeAgentSlots.Add(agentSlot);
			}
			mEntityToAgent.Remove(entity);
		}

		// Clean up obstacle
		if (mEntityToObstacle.TryGetValue(entity, let obstacleSlot))
		{
			var instance = ref mObstacleInstances[obstacleSlot];
			if (instance.Active)
			{
				if (instance.ObstacleId >= 0 && mNavWorld != null)
					mNavWorld.RemoveObstacle(instance.ObstacleId);
				instance.Active = false;
				mFreeObstacleSlots.Add(obstacleSlot);
			}
			mEntityToObstacle.Remove(entity);
		}
	}

	// ==================== Private ====================

	private void AutoCreateAgents()
	{
		if (mNavWorld.NavMesh == null || mNavWorld.Crowd == null)
			return;

		for (var instance in ref mAgentInstances)
		{
			if (!instance.Active || instance.AgentIndex >= 0)
				continue; // Already has a crowd agent or inactive

			let transform = mScene.GetTransform(instance.Entity);
			float[3] pos = .(transform.Position.X, transform.Position.Y, transform.Position.Z);
			let @params = ToCrowdAgentParams(instance);
			int32 agentIndex = mNavWorld.AddAgent(pos, @params);
			if (agentIndex >= 0)
				instance.AgentIndex = agentIndex;
		}
	}

	private void SyncAgentTransforms()
	{
		let crowd = mNavWorld.Crowd;
		if (crowd == null)
			return;

		for (let instance in ref mAgentInstances)
		{
			if (!instance.Active || !instance.SyncToTransform || instance.AgentIndex < 0)
				continue;

			if (!crowd.IsAgentActive(instance.AgentIndex))
				continue;

			float[3] pos;
			crowd.GetAgentPosition(instance.AgentIndex, out pos);

			var transform = mScene.GetTransform(instance.Entity);
			transform.Position = Vector3(pos[0], pos[1], pos[2]);
			mScene.SetTransform(instance.Entity, transform);
		}
	}

	private static CrowdAgentParams ToCrowdAgentParams(NavAgentInstanceData instance) =>
		.() {
			Radius = instance.Radius,
			Height = instance.Height,
			MaxAcceleration = instance.MaxAcceleration,
			MaxSpeed = instance.MaxSpeed,
			CollisionQueryRange = instance.CollisionQueryRange,
			PathOptimizationRange = instance.PathOptimizationRange,
			SeparationWeight = instance.SeparationWeight,
			ObstacleAvoidanceType = instance.ObstacleAvoidanceType,
			UpdateFlags = (.)dtCrowdUpdateFlags.DT_CROWD_ANTICIPATE_TURNS |
						  (.)dtCrowdUpdateFlags.DT_CROWD_OBSTACLE_AVOIDANCE |
						  (.)dtCrowdUpdateFlags.DT_CROWD_SEPARATION,
			QueryFilterType = 0,
			UserData = null
		};

	private void DrawDebug()
	{
		let renderModule = mScene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return;

		let renderSystem = renderModule.Subsystem?.RenderSystem;
		if (renderSystem == null)
			return;

		let overlayFeature = renderSystem.GetFeature<OverlayRenderFeature>();
		if (overlayFeature == null)
			return;

		let navMesh = mNavWorld.NavMesh;
		if (navMesh == null)
			return;

		let crowd = mNavWorld.Crowd;
		if (crowd != null)
		{
			int32 agentCount = crowd.AgentCount;
			for (int32 i = 0; i < agentCount; i++)
			{
				if (!crowd.IsAgentActive(i))
					continue;

				float[3] pos;
				crowd.GetAgentPosition(i, out pos);

				let position = Vector3(pos[0], pos[1], pos[2]);
				let color = Color(0, 255, 0, 255);

				overlayFeature.AddLine(position - Vector3(0.3f, 0, 0), position + Vector3(0.3f, 0, 0), color);
				overlayFeature.AddLine(position - Vector3(0, 0, 0.3f), position + Vector3(0, 0, 0.3f), color);
				overlayFeature.AddLine(position, position + Vector3(0, 1.0f, 0), color);

				float[3] vel;
				crowd.GetAgentVelocity(i, out vel);
				let velEnd = position + Vector3(vel[0], vel[1], vel[2]) * 0.5f;
				overlayFeature.AddLine(position, velEnd, Color(255, 255, 0, 255));
			}
		}
	}
}

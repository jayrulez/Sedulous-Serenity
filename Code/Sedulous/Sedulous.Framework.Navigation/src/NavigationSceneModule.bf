namespace Sedulous.Framework.Navigation;

using System;
using System.Collections;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Mathematics;
using Sedulous.Render;
using recastnavigation_Beef;

/// Scene module that manages navigation agents and obstacles for entities.
/// Created automatically by NavigationSubsystem for each scene.
class NavigationSceneModule : SceneModule
{
	private NavigationSubsystem mSubsystem;
	private NavWorld mNavWorld;
	private Scene mScene;

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

		mScene.SetComponent<NavAgentComponent>(entity, .() {
			AgentIndex = agentIndex,
			SyncToTransform = true,
			Radius = @params.Radius,
			Height = @params.Height,
			MaxAcceleration = @params.MaxAcceleration,
			MaxSpeed = @params.MaxSpeed,
			CollisionQueryRange = @params.CollisionQueryRange,
			PathOptimizationRange = @params.PathOptimizationRange,
			SeparationWeight = @params.SeparationWeight,
			ObstacleAvoidanceType = @params.ObstacleAvoidanceType
		});

		return agentIndex;
	}

	/// Removes the navigation agent for an entity.
	public void RemoveAgent(EntityId entity)
	{
		if (mScene == null || mNavWorld == null)
			return;

		if (let agent = mScene.GetComponent<NavAgentComponent>(entity))
		{
			if (agent.AgentIndex >= 0)
			{
				mNavWorld.RemoveAgent(agent.AgentIndex);
				agent.AgentIndex = -1;
			}
		}
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

		mScene.SetComponent<NavObstacleComponent>(entity, .() {
			ObstacleId = obstacleId,
			Radius = radius,
			Height = height
		});

		return obstacleId;
	}

	/// Removes the dynamic obstacle for an entity.
	public void RemoveObstacle(EntityId entity)
	{
		if (mScene == null || mNavWorld == null)
			return;

		if (let obstacle = mScene.GetComponent<NavObstacleComponent>(entity))
		{
			if (obstacle.ObstacleId >= 0)
			{
				mNavWorld.RemoveObstacle(obstacle.ObstacleId);
				obstacle.ObstacleId = -1;
			}
		}
	}

	// ==================== High-Level Operations ====================

	/// Builds a navigation mesh from the provided geometry and applies it to this scene's NavWorld.
	/// Uses tiled building with TileCache for dynamic obstacle support.
	/// Returns true if the navmesh was built and set successfully.
	public bool BuildNavMesh(IInputGeometryProvider geometry, in NavMeshBuildConfig config)
	{
		if (mNavWorld == null)
			return false;

		// Use tiled builder for dynamic obstacle support
		var tiledConfig = config;
		if (tiledConfig.TileSize <= 0)
			tiledConfig.TileSize = 48; // Default tile size

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

		// Transfer ownership to NavWorld (with TileCache for dynamic obstacles)
		mNavWorld.SetNavMeshWithTileCache(result.NavMesh, result.TileCache);
		result.NavMesh = null;
		result.TileCache = null;

		return true;
	}

	/// Builds a simple single-tile navigation mesh (no dynamic obstacle support).
	/// Use BuildNavMesh for dynamic obstacle support.
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

		// Transfer ownership to NavWorld
		result.NavMesh = null;

		return true;
	}

	/// Sets the move target for an entity's agent to the given world position.
	/// Returns true if the target was set successfully.
	public bool RequestMoveTarget(EntityId entity, float[3] targetPos)
	{
		if (mScene == null || mNavWorld == null)
			return false;

		if (let agent = mScene.GetComponent<NavAgentComponent>(entity))
		{
			if (agent.AgentIndex >= 0)
				return mNavWorld.RequestMoveTarget(agent.AgentIndex, targetPos);
		}
		return false;
	}

	/// Finds a path between two world positions.
	/// Returns true if a path was found, with waypoints as [x,y,z,...] in outWaypoints.
	public bool FindPath(float[3] start, float[3] end, List<float> outWaypoints)
	{
		if (mNavWorld == null)
			return false;
		return mNavWorld.FindPath(start, end, outWaypoints);
	}

	/// Gets the current position of an entity's crowd agent.
	/// Returns true if the agent was found and position retrieved.
	public bool GetAgentPosition(EntityId entity, out float[3] position)
	{
		position = default;
		if (mScene == null || mNavWorld == null)
			return false;

		let crowd = mNavWorld.Crowd;
		if (crowd == null)
			return false;

		if (let agent = mScene.GetComponent<NavAgentComponent>(entity))
		{
			if (agent.AgentIndex >= 0)
			{
				if (crowd.IsAgentActive(agent.AgentIndex))
				{
					crowd.GetAgentPosition(agent.AgentIndex, out position);
					return true;
				}
			}
		}
		return false;
	}

	// ==================== SceneModule Lifecycle ====================

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;
		scene.RegisterComponentSerializer<NavAgentComponent>();
		scene.RegisterComponentSerializer<NavObstacleComponent>();
	}

	public override void OnSceneDestroy(Scene scene)
	{
		mScene = null;
	}

	public override void FixedUpdate(Scene scene, float fixedDeltaTime)
	{
		if (mNavWorld == null)
			return;

		// Step crowd simulation and process obstacle updates
		mNavWorld.Update(fixedDeltaTime);
	}

	public override void Update(Scene scene, float deltaTime)
	{
		if (mNavWorld == null || mScene == null)
			return;

		// Auto-create agents for deserialized components
		AutoCreateAgents(scene);

		// Sync agent positions to entity transforms
		SyncAgentTransforms(scene);
	}

	public override void PostUpdate(Scene scene, float deltaTime)
	{
		if (!mDebugDrawEnabled || mNavWorld == null || mScene == null)
			return;

		DrawDebug(scene);
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		if (mNavWorld == null)
			return;

		// Clean up agent
		if (let agent = scene.GetComponent<NavAgentComponent>(entity))
		{
			if (agent.AgentIndex >= 0)
			{
				mNavWorld.RemoveAgent(agent.AgentIndex);
				agent.AgentIndex = -1;
			}
		}

		// Clean up obstacle
		if (let obstacle = scene.GetComponent<NavObstacleComponent>(entity))
		{
			if (obstacle.ObstacleId >= 0)
			{
				mNavWorld.RemoveObstacle(obstacle.ObstacleId);
				obstacle.ObstacleId = -1;
			}
		}
	}

	// ==================== Private ====================

	private void AutoCreateAgents(Scene scene)
	{
		if (mNavWorld.NavMesh == null || mNavWorld.Crowd == null)
			return;

		for (let (entity, agent) in scene.Query<NavAgentComponent>())
		{
			if (agent.AgentIndex >= 0)
				continue; // Already has an agent

			let transform = scene.GetTransform(entity);
			float[3] pos = .(transform.Position.X, transform.Position.Y, transform.Position.Z);
			let @params = agent.ToCrowdAgentParams();
			int32 agentIndex = mNavWorld.AddAgent(pos, @params);
			if (agentIndex >= 0)
				agent.AgentIndex = agentIndex;
		}
	}

	private void SyncAgentTransforms(Scene scene)
	{
		let crowd = mNavWorld.Crowd;
		if (crowd == null)
			return;

		for (let (entity, agent) in scene.Query<NavAgentComponent>())
		{
			if (!agent.SyncToTransform || agent.AgentIndex < 0)
				continue;

			if (!crowd.IsAgentActive(agent.AgentIndex))
				continue;

			float[3] pos;
			crowd.GetAgentPosition(agent.AgentIndex, out pos);

			var transform = scene.GetTransform(entity);
			transform.Position = Vector3(pos[0], pos[1], pos[2]);
			scene.SetTransform(entity, transform);
		}
	}

	private void DrawDebug(Scene scene)
	{
		let renderModule = scene.GetModule<RenderSceneModule>();
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

		// Use recastnavigation debug draw functions
		// For now, just draw agent positions as crosses
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

				// Draw a cross at agent position
				overlayFeature.AddLine(position - Vector3(0.3f, 0, 0), position + Vector3(0.3f, 0, 0), color);
				overlayFeature.AddLine(position - Vector3(0, 0, 0.3f), position + Vector3(0, 0, 0.3f), color);
				overlayFeature.AddLine(position, position + Vector3(0, 1.0f, 0), color);

				// Draw velocity
				float[3] vel;
				crowd.GetAgentVelocity(i, out vel);
				let velEnd = position + Vector3(vel[0], vel[1], vel[2]) * 0.5f;
				overlayFeature.AddLine(position, velEnd, Color(255, 255, 0, 255));
			}
		}
	}
}

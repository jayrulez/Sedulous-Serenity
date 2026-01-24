namespace Sedulous.Framework.Navigation;

using System;
using System.Collections;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Mathematics;
using Sedulous.Navigation;
using Sedulous.Navigation.Detour;
using Sedulous.Navigation.Crowd;
using Sedulous.Render;

/// Scene module that manages navigation agents and obstacles for entities.
/// Created automatically by NavigationSubsystem for each scene.
class NavigationSceneModule : SceneModule
{
	private NavigationSubsystem mSubsystem;
	private NavWorld mNavWorld;
	private Scene mScene;

	// Debug drawing
	private bool mDebugDrawEnabled = false;
	private List<DebugDrawVertex> mDebugVertices = new .() ~ delete _;

	/// Creates a NavigationSceneModule with the given world.
	public this(NavigationSubsystem subsystem, NavWorld navWorld)
	{
		mSubsystem = subsystem;
		mNavWorld = navWorld;
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
			SyncToTransform = true
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

	// ==================== SceneModule Lifecycle ====================

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;
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

	private void SyncAgentTransforms(Scene scene)
	{
		let crowd = mNavWorld.Crowd;
		if (crowd == null)
			return;

		for (let (entity, agent) in scene.Query<NavAgentComponent>())
		{
			if (!agent.SyncToTransform || agent.AgentIndex < 0)
				continue;

			let crowdAgent = crowd.GetAgent(agent.AgentIndex);
			if (crowdAgent == null)
				continue;

			var transform = scene.GetTransform(entity);
			transform.Position = Vector3(crowdAgent.Position[0], crowdAgent.Position[1], crowdAgent.Position[2]);
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

		let debugFeature = renderSystem.GetFeature<DebugRenderFeature>();
		if (debugFeature == null)
			return;

		let navMesh = mNavWorld.NavMesh;
		if (navMesh == null)
			return;

		// Draw navmesh polygons
		mDebugVertices.Clear();
		NavMeshDebugDraw.DrawNavMesh(navMesh, mDebugVertices);
		for (int32 i = 0; i + 2 < (int32)mDebugVertices.Count; i += 3)
		{
			let v0 = mDebugVertices[i];
			let v1 = mDebugVertices[i + 1];
			let v2 = mDebugVertices[i + 2];
			debugFeature.AddTriangle(
				Vector3(v0.X, v0.Y, v0.Z),
				Vector3(v1.X, v1.Y, v1.Z),
				Vector3(v2.X, v2.Y, v2.Z),
				UnpackColor(v0.Color));
		}

		// Draw navmesh edges
		mDebugVertices.Clear();
		NavMeshDebugDraw.DrawNavMeshEdges(navMesh, mDebugVertices);
		for (int32 i = 0; i + 1 < (int32)mDebugVertices.Count; i += 2)
		{
			let v0 = mDebugVertices[i];
			let v1 = mDebugVertices[i + 1];
			debugFeature.AddLine(
				Vector3(v0.X, v0.Y, v0.Z),
				Vector3(v1.X, v1.Y, v1.Z),
				UnpackColor(v0.Color));
		}

		// Draw crowd agents
		let crowd = mNavWorld.Crowd;
		if (crowd != null)
		{
			mDebugVertices.Clear();
			NavMeshDebugDraw.DrawAgents(crowd, mDebugVertices);
			for (int32 i = 0; i + 1 < (int32)mDebugVertices.Count; i += 2)
			{
				let v0 = mDebugVertices[i];
				let v1 = mDebugVertices[i + 1];
				debugFeature.AddLine(
					Vector3(v0.X, v0.Y, v0.Z),
					Vector3(v1.X, v1.Y, v1.Z),
					UnpackColor(v0.Color));
			}
		}
	}

	/// Converts a packed ARGB uint32 color to a Color struct.
	private static Color UnpackColor(uint32 packed)
	{
		uint8 a = (uint8)((packed >> 24) & 0xFF);
		uint8 r = (uint8)((packed >> 16) & 0xFF);
		uint8 g = (uint8)((packed >> 8) & 0xFF);
		uint8 b = (uint8)(packed & 0xFF);
		return Color(r, g, b, a);
	}
}

namespace FrameworkNavigation;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Navigation;
using Sedulous.Framework.Runtime;
using Sedulous.Shell.Input;
using Sedulous.Render;
using Sedulous.Navigation;
using Sedulous.Navigation.Recast;
using Sedulous.Navigation.Crowd;

class NavigationDemo
{
	private Scene mScene;
	private NavigationSceneModule mNavModule;
	private DebugRenderFeature mDebugFeature;
	private float mArenaHalfSize;

	// Agent tracking
	private List<EntityId> mAgentEntities = new .() ~ delete _;

	// Obstacle tracking
	private List<EntityId> mObstacleEntities = new .() ~ delete _;

	// State
	private bool mObstacleMode = false;
	private bool mDrawNavMesh = true;
	private bool mDrawPaths = true;
	private bool mFlipProjection = false;
	private float[3] mLastClickTarget;
	private bool mHasTarget = false;

	// Path visualization
	private List<float> mPathWaypoints = new .() ~ delete _;

	// Random
	private Random mRandom = new .() ~ delete _;

	// Agent colors
	private static Color[8] sAgentColors = .(
		Color(50, 200, 50, 255),
		Color(50, 100, 255, 255),
		Color(255, 200, 50, 255),
		Color(200, 50, 200, 255),
		Color(255, 100, 50, 255),
		Color(50, 200, 200, 255),
		Color(200, 50, 50, 255),
		Color(200, 200, 200, 255)
	);

	// Properties for HUD
	public int32 AgentCount => (int32)mAgentEntities.Count;
	public int32 ObstacleCount => (int32)mObstacleEntities.Count;
	public bool IsObstacleMode => mObstacleMode;

	public void Initialize(Scene scene, NavigationSceneModule navModule, DebugRenderFeature debugFeature, float arenaHalfSize, bool flipProjection)
	{
		mScene = scene;
		mNavModule = navModule;
		mDebugFeature = debugFeature;
		mArenaHalfSize = arenaHalfSize;
		mFlipProjection = flipProjection;

		BuildNavMesh();
		SpawnInitialAgents();
	}

	private void BuildNavMesh()
	{
		// Build geometry from scene layout (same walls as FrameworkNavigationApp)
		let vertices = scope List<float>();
		let triangles = scope List<int32>();

		// Ground plane (thin box at Y=0)
		AddBoxGeometry(vertices, triangles, .(0, -0.05f, 0), .(mArenaHalfSize, 0.05f, mArenaHalfSize));

		// Walls (thicker than visual walls for reliable navmesh voxelization)
		AddBoxGeometry(vertices, triangles, .(-5, 1, -5), .(4, 1, 0.5f));
		AddBoxGeometry(vertices, triangles, .(5, 1, -5), .(0.5f, 1, 3));
		AddBoxGeometry(vertices, triangles, .(-3, 1, 3), .(5, 1, 0.5f));
		AddBoxGeometry(vertices, triangles, .(7, 1, 0), .(0.5f, 1, 5));
		AddBoxGeometry(vertices, triangles, .(-8, 1, -2), .(0.5f, 1, 4));

		// Raised platform
		AddBoxGeometry(vertices, triangles, .(11, 0.75f, 11), .(2.5f, 0.75f, 2.5f));

		// Create input geometry
		let geometry = scope InputGeometry(
			Span<float>(vertices.Ptr, vertices.Count),
			Span<int32>(triangles.Ptr, triangles.Count));

		// Configure navmesh build
		var config = NavMeshBuildConfig.Default;
		config.CellSize = 0.3f;
		config.CellHeight = 0.2f;
		config.WalkableRadius = 2;
		config.WalkableHeight = 10;
		config.WalkableClimb = 3;
		config.WalkableSlopeAngle = 45.0f;

		if (mNavModule.BuildNavMesh(geometry, config))
		{
			mNavModule.DebugDrawEnabled = mDrawNavMesh;
			Console.WriteLine("Navigation demo ready");
		}
		else
		{
			Console.WriteLine("WARNING: NavMesh build failed - navigation will not work");
		}
	}

	private void SpawnInitialAgents()
	{
		AddAgentAt(.(0, 0, 0));
		AddAgentAt(.(-3, 0, -8));
		AddAgentAt(.(5, 0, 7));
	}

	private void AddAgentAt(float[3] position)
	{
		let entity = mScene.CreateEntity();
		var agentParams = CrowdAgentParams.Default;
		agentParams.Radius = 0.5f;
		agentParams.Height = 1.8f;
		agentParams.MaxSpeed = 3.0f;
		agentParams.MaxAcceleration = 8.0f;

		let idx = mNavModule.AddAgent(entity, position, agentParams);
		if (idx >= 0)
			mAgentEntities.Add(entity);
		else
			mScene.DestroyEntity(entity);
	}

	public void AddAgentAtRandom()
	{
		float x = ((float)mRandom.NextDouble() - 0.5f) * mArenaHalfSize * 1.5f;
		float z = ((float)mRandom.NextDouble() - 0.5f) * mArenaHalfSize * 1.5f;
		AddAgentAt(.(x, 0, z));
	}

	public void RemoveLastAgent()
	{
		if (mAgentEntities.Count == 0) return;
		let entity = mAgentEntities.PopBack();
		mNavModule.RemoveAgent(entity);
		mScene.DestroyEntity(entity);
	}

	public void ToggleMode()
	{
		mObstacleMode = !mObstacleMode;
	}

	public void ClearObstacles()
	{
		for (let entity in mObstacleEntities)
		{
			mNavModule.RemoveObstacle(entity);
			mScene.DestroyEntity(entity);
		}
		mObstacleEntities.Clear();
	}

	public void ToggleNavMeshDraw()
	{
		mDrawNavMesh = !mDrawNavMesh;
		mNavModule.DebugDrawEnabled = mDrawNavMesh;
	}

	public void TogglePathDraw()
	{
		mDrawPaths = !mDrawPaths;
	}

	public void HandleInput(IKeyboard keyboard, IMouse mouse, OrbitFlyCamera camera, RenderView view, bool uiHovered)
	{
		if (keyboard.IsKeyPressed(.Num1))
			AddAgentAtRandom();
		if (keyboard.IsKeyPressed(.Num2))
			RemoveLastAgent();
		if (keyboard.IsKeyPressed(.Num3))
			ToggleMode();
		if (keyboard.IsKeyPressed(.Num4))
			ClearObstacles();
		if (keyboard.IsKeyPressed(.N))
			ToggleNavMeshDraw();
		if (keyboard.IsKeyPressed(.V))
			TogglePathDraw();

		// Left click: move agents or place obstacle (skip if UI is hovered or camera captured)
		if (mouse.IsButtonPressed(.Left) && !camera.MouseCaptured && !uiHovered)
		{
			float[3] groundPos;
			if (ScreenToGround(mouse.X, mouse.Y, view, out groundPos))
			{
				if (mObstacleMode)
					PlaceObstacle(groundPos);
				else
					MoveAgentsToTarget(groundPos);
			}
		}
	}

	private void MoveAgentsToTarget(float[3] target)
	{
		mLastClickTarget = target;
		mHasTarget = true;

		for (let entity in mAgentEntities)
			mNavModule.RequestMoveTarget(entity, target);

		// Update path visualization from first agent
		if (mAgentEntities.Count > 0 && mDrawPaths)
		{
			float[3] agentPos;
			if (mNavModule.GetAgentPosition(mAgentEntities[0], out agentPos))
				mNavModule.FindPath(agentPos, target, mPathWaypoints);
		}
	}

	private void PlaceObstacle(float[3] position)
	{
		let entity = mScene.CreateEntity();

		// Set entity transform so we can read position back for drawing
		var transform = mScene.GetTransform(entity);
		transform.Position = Vector3(position[0], position[1], position[2]);
		mScene.SetTransform(entity, transform);

		let obstacleId = mNavModule.AddObstacle(entity, position, 1.0f, 2.0f);
		if (obstacleId >= 0)
			mObstacleEntities.Add(entity);
		else
			mScene.DestroyEntity(entity);
	}

	private bool ScreenToGround(float screenX, float screenY, RenderView view, out float[3] groundPos)
	{
		groundPos = default;

		// NDC coordinates (Vulkan flips Y in projection, so NDC Y maps differently)
		float ndcX = (2.0f * screenX / (float)view.Width) - 1.0f;
		float ndcY = mFlipProjection
			? (2.0f * screenY / (float)view.Height) - 1.0f
			: 1.0f - (2.0f * screenY / (float)view.Height);

		// Inverse view-projection
		var invVP = Matrix.Identity;
		if (!Matrix.TryInvert(view.ViewProjectionMatrix, out invVP))
			return false;

		// Unproject near and far points
		let nearNDC = Vector4(ndcX, ndcY, 0.0f, 1.0f);
		let farNDC = Vector4(ndcX, ndcY, 1.0f, 1.0f);

		var nearWorld = Vector4.Transform(nearNDC, invVP);
		var farWorld = Vector4.Transform(farNDC, invVP);

		if (Math.Abs(nearWorld.W) < 0.0001f || Math.Abs(farWorld.W) < 0.0001f)
			return false;

		let nearPos = Vector3(nearWorld.X / nearWorld.W, nearWorld.Y / nearWorld.W, nearWorld.Z / nearWorld.W);
		let farPos = Vector3(farWorld.X / farWorld.W, farWorld.Y / farWorld.W, farWorld.Z / farWorld.W);

		// Ray-plane intersection with Y=0
		let rayDir = farPos - nearPos;
		if (Math.Abs(rayDir.Y) < 0.0001f)
			return false;

		let t = -nearPos.Y / rayDir.Y;
		if (t < 0)
			return false;

		let hitPos = nearPos + rayDir * t;

		// Clamp to arena bounds
		float clampedX = Math.Clamp(hitPos.X, -mArenaHalfSize, mArenaHalfSize);
		float clampedZ = Math.Clamp(hitPos.Z, -mArenaHalfSize, mArenaHalfSize);
		groundPos = .(clampedX, 0, clampedZ);
		return true;
	}

	public void DrawDebug(DebugRenderFeature debug, RenderView view)
	{
		DrawAgents(debug);

		if (mDrawPaths && mPathWaypoints.Count >= 6)
			DrawPath(debug);

		DrawObstacles(debug);

		if (mHasTarget)
			DrawTarget(debug);
	}

	private void DrawAgents(DebugRenderFeature debug)
	{
		let crowd = mNavModule.NavWorld?.Crowd;
		if (crowd == null) return;

		for (int32 i = 0; i < (int32)mAgentEntities.Count; i++)
		{
			float[3] pos;
			if (!mNavModule.GetAgentPosition(mAgentEntities[i], out pos))
				continue;

			let color = sAgentColors[i % 8];
			let center = Vector3(pos[0], pos[1] + 0.9f, pos[2]);

			// Agent body cylinder
			debug.AddCylinder(center, 0.5f, 1.8f, color, 12);

			// Velocity direction arrow
			if (let agentComp = mScene.GetComponent<NavAgentComponent>(mAgentEntities[i]))
			{
				let crowdAgent = crowd.GetAgent(agentComp.AgentIndex);
				if (crowdAgent != null)
				{
					let vel = crowdAgent.Velocity;
					float speed = Math.Sqrt(vel[0] * vel[0] + vel[2] * vel[2]);
					if (speed > 0.1f)
					{
						let arrowStart = Vector3(pos[0], pos[1] + 0.5f, pos[2]);
						let arrowEnd = Vector3(
							pos[0] + vel[0] * 0.5f,
							pos[1] + 0.5f,
							pos[2] + vel[2] * 0.5f);
						debug.AddArrow(arrowStart, arrowEnd, Color(255, 255, 0, 255), 0.15f);
					}
				}
			}
		}
	}

	private void DrawPath(DebugRenderFeature debug)
	{
		let pathColor = Color(0, 255, 100, 200);
		for (int32 i = 0; i + 5 < (int32)mPathWaypoints.Count; i += 3)
		{
			let from = Vector3(mPathWaypoints[i], mPathWaypoints[i + 1] + 0.1f, mPathWaypoints[i + 2]);
			let to = Vector3(mPathWaypoints[i + 3], mPathWaypoints[i + 4] + 0.1f, mPathWaypoints[i + 5]);
			debug.AddLine(from, to, pathColor);
			debug.AddCross(to, 0.15f, pathColor);
		}
	}

	private void DrawObstacles(DebugRenderFeature debug)
	{
		let obstColor = Color(255, 100, 50, 200);
		for (let entity in mObstacleEntities)
		{
			if (let obstacle = mScene.GetComponent<NavObstacleComponent>(entity))
			{
				let transform = mScene.GetTransform(entity);
				let pos = transform.Position;
				debug.AddCylinder(
					pos + Vector3(0, obstacle.Height * 0.5f, 0),
					obstacle.Radius, obstacle.Height, obstColor, 12);
			}
		}
	}

	private void DrawTarget(DebugRenderFeature debug)
	{
		let targetColor = Color(255, 255, 255, 180);
		let pos = Vector3(mLastClickTarget[0], 0.05f, mLastClickTarget[2]);
		debug.AddCircle(pos, 0.5f, .(0, 1, 0), targetColor, 24);
		debug.AddCross(pos, 0.3f, targetColor);
	}

	// ==================== Geometry Helpers ====================

	private static void AddBoxGeometry(List<float> vertices, List<int32> triangles, Vector3 center, Vector3 halfExtents)
	{
		let baseIndex = (int32)(vertices.Count / 3);
		let min = center - halfExtents;
		let max = center + halfExtents;

		// 8 vertices
		AddVertex(vertices, min.X, min.Y, min.Z); // 0
		AddVertex(vertices, max.X, min.Y, min.Z); // 1
		AddVertex(vertices, max.X, max.Y, min.Z); // 2
		AddVertex(vertices, min.X, max.Y, min.Z); // 3
		AddVertex(vertices, min.X, min.Y, max.Z); // 4
		AddVertex(vertices, max.X, min.Y, max.Z); // 5
		AddVertex(vertices, max.X, max.Y, max.Z); // 6
		AddVertex(vertices, min.X, max.Y, max.Z); // 7

		// 12 triangles (2 per face)
		// Front (z = min)
		AddTri(triangles, baseIndex + 0, baseIndex + 1, baseIndex + 2);
		AddTri(triangles, baseIndex + 0, baseIndex + 2, baseIndex + 3);
		// Back (z = max)
		AddTri(triangles, baseIndex + 5, baseIndex + 4, baseIndex + 7);
		AddTri(triangles, baseIndex + 5, baseIndex + 7, baseIndex + 6);
		// Top (y = max) - upward normal
		AddTri(triangles, baseIndex + 3, baseIndex + 6, baseIndex + 2);
		AddTri(triangles, baseIndex + 3, baseIndex + 7, baseIndex + 6);
		// Bottom (y = min) - downward normal
		AddTri(triangles, baseIndex + 4, baseIndex + 1, baseIndex + 5);
		AddTri(triangles, baseIndex + 4, baseIndex + 0, baseIndex + 1);
		// Right (x = max)
		AddTri(triangles, baseIndex + 1, baseIndex + 5, baseIndex + 6);
		AddTri(triangles, baseIndex + 1, baseIndex + 6, baseIndex + 2);
		// Left (x = min)
		AddTri(triangles, baseIndex + 4, baseIndex + 0, baseIndex + 3);
		AddTri(triangles, baseIndex + 4, baseIndex + 3, baseIndex + 7);
	}

	[Inline]
	private static void AddVertex(List<float> verts, float x, float y, float z)
	{
		verts.Add(x);
		verts.Add(y);
		verts.Add(z);
	}

	[Inline]
	private static void AddTri(List<int32> tris, int32 a, int32 b, int32 c)
	{
		tris.Add(a);
		tris.Add(b);
		tris.Add(c);
	}
}

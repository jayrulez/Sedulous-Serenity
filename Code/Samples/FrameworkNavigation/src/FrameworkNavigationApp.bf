namespace FrameworkNavigation;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Physics;
using Sedulous.Framework.Input;
using Sedulous.Framework.UI;
using Sedulous.Framework.Navigation;
using Sedulous.Fonts;
using Sedulous.UI;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Resources;
using Sedulous.Materials;
using Sedulous.Physics;
using Sedulous.Physics.Jolt;
using Sedulous.Profiler;
using Sedulous.Drawing.Fonts;

class FrameworkNavigationApp : Application
{
	private const float ArenaHalfSize = 15.0f;

	// Framework
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private UISubsystem mUISubsystem;
	private Scene mMainScene;

	private FontService mFontService;

	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderView mRenderView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private DebugRenderFeature mDebugFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Meshes
	private StaticMeshResource mPlaneResource ~ delete _;
	private StaticMeshResource mCubeResource ~ delete _;
	private MaterialInstance mFloorMaterial ~ delete _;
	private MaterialInstance mWallMaterial ~ delete _;

	// Camera
	private OrbitFlyCamera mCamera ~ delete _;

	// Entities
	private EntityId mFloorEntity;
	private EntityId mCameraEntity;
	private EntityId mSunEntity;

	// Navigation demo
	private NavigationDemo mNavDemo ~ delete _;

	// Timing
	private float mDeltaTime = 0.016f;
	private float mSmoothedFps = 60.0f;

	public this(IShell shell, IDevice device, IBackend backend) : base(shell, device, backend)
	{
		mCamera = new .();
		mCamera.OrbitalYaw = 0.5f;
		mCamera.OrbitalPitch = 0.6f;
		mCamera.OrbitalDistance = 30.0f;
		mCamera.OrbitalTarget = .(0, 0.5f, 0);
		mCamera.FlyPosition = .(0, 15.0f, 30.0f);
		mCamera.FlyPitch = -0.3f;
		mCamera.Update();
	}

	protected override void OnInitialize(Context context)
	{
		Console.WriteLine("=== Navigation Demo ===\n");

		InitializeRenderSystem();
		RegisterSubsystems(context);
	}

	protected override void OnContextStarted()
	{
		SProfiler.Initialize();

		CreateMainScene();
		CreateMeshes();
		CreateSceneObjects();

		// Initialize navigation demo after scene is set up
		mNavDemo = new NavigationDemo();
		let navModule = mMainScene.GetModule<NavigationSceneModule>();
		mNavDemo.Initialize(mMainScene, navModule, mDebugFeature, ArenaHalfSize, mDevice.FlipProjectionRequired);

		CreateUI();

		Console.WriteLine("\n=== Ready ===");
		Console.WriteLine("Controls:");
		Console.WriteLine("  Left Click: Move agents / Place obstacle");
		Console.WriteLine("  1: Add agent   2: Remove agent");
		Console.WriteLine("  3: Toggle mode (Move/Obstacle)");
		Console.WriteLine("  4: Clear obstacles");
		Console.WriteLine("  N: Toggle navmesh   V: Toggle paths");
		Console.WriteLine("  Tab/`: Camera mode   P: Profiler");
		Console.WriteLine("  ESC: Exit\n");
	}

	private void InitializeRenderSystem()
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope $"{AssetDirectory}/Render/Shaders", .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}

		mRenderView = new RenderView();
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.FieldOfView = Math.PI_f / 4.0f;
		mRenderView.NearPlane = 0.1f;
		mRenderView.FarPlane = 200.0f;

		// Register features
		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mDebugFeature = new DebugRenderFeature();
		mRenderSystem.RegisterFeature(mDebugFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void RegisterSubsystems(Context context)
	{
		// Scene
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);

		// Physics (for floor plane body)
		let physicsSubsystem = new PhysicsSubsystem(
			new (desc) => {
				switch (JoltPhysicsWorld.Create(desc))
				{
				case .Ok(let world): return .Ok(world);
				case .Err: return .Err;
				}
			}
		);
		context.RegisterSubsystem(physicsSubsystem);

		// Render
		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);

		// Input
		let inputSubsystem = new InputSubsystem();
		inputSubsystem.SetInputManager(mShell.InputManager);
		context.RegisterSubsystem(inputSubsystem);

		// UI
		mUISubsystem = new UISubsystem(mFontService);
		context.RegisterSubsystem(mUISubsystem);
		if (mUISubsystem.InitializeRendering(mDevice, .BGRA8UnormSrgb, 2, mShell, mRenderSystem) not case .Ok)
		{
			Console.WriteLine("  - UISubsystem (render init failed)");
		}

		// Navigation
		let navSubsystem = new NavigationSubsystem();
		context.RegisterSubsystem(navSubsystem);
	}

	private void CreateMainScene()
	{
		mMainScene = mSceneSubsystem.CreateScene("NavScene");
		mSceneSubsystem.SetActiveScene(mMainScene);
	}

	private void CreateMeshes()
	{
		mPlaneResource = StaticMeshResource.CreatePlane(ArenaHalfSize * 2, ArenaHalfSize * 2, 1, 1);
		mCubeResource = StaticMeshResource.CreateCube(1.0f);
	}

	private void CreateSceneObjects()
	{
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		if (renderModule == null) return;

		let physicsModule = mMainScene.GetModule<PhysicsSceneModule>();

		// Get default material
		let defaultMaterialInstance = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial;
		if (baseMaterial != null)
		{
			mFloorMaterial = new MaterialInstance(baseMaterial);
			mFloorMaterial.SetColor("BaseColor", .(0.35f, 0.35f, 0.32f, 1.0f));
			mFloorMaterial.SetFloat("Roughness", 0.9f);

			mWallMaterial = new MaterialInstance(baseMaterial);
			mWallMaterial.SetColor("BaseColor", .(0.5f, 0.45f, 0.4f, 1.0f));
			mWallMaterial.SetFloat("Roughness", 0.8f);
		}

		// Floor entity
		mFloorEntity = mMainScene.CreateEntity();
		{
			mMainScene.SetComponent<MeshRendererComponent>(mFloorEntity, .Default);
			var comp = mMainScene.GetComponent<MeshRendererComponent>(mFloorEntity);
			comp.Mesh = ResourceHandle<StaticMeshResource>(mPlaneResource);
			comp.Material = mFloorMaterial ?? defaultMaterialInstance;
			if (physicsModule != null)
				physicsModule.CreatePlaneBody(mFloorEntity, .(0, 1, 0), 0.0f);
		}

		// Wall entities (maze layout)
		CreateWall(renderModule, .(-5, 1, -5), .(4, 1, 0.3f));
		CreateWall(renderModule, .(5, 1, -5), .(0.3f, 1, 3));
		CreateWall(renderModule, .(-3, 1, 3), .(5, 1, 0.3f));
		CreateWall(renderModule, .(7, 1, 0), .(0.3f, 1, 5));
		CreateWall(renderModule, .(-8, 1, -2), .(0.3f, 1, 4));

		// Raised platform
		CreateWall(renderModule, .(11, 0.75f, 11), .(2.5f, 0.75f, 2.5f));

		// Camera entity
		mCameraEntity = mMainScene.CreateEntity();
		renderModule.CreatePerspectiveCamera(mCameraEntity, Math.PI_f / 4.0f, (float)mSwapChain.Width / mSwapChain.Height, 0.1f, 200.0f);
		renderModule.SetMainCamera(mCameraEntity);

		// Sun light (fixed direction)
		mSunEntity = mMainScene.CreateEntity();
		{
			renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.98f, 0.95f), 2.0f);
			var transform = mMainScene.GetTransform(mSunEntity);
			transform.Rotation = Quaternion.CreateFromYawPitchRoll(0.8f, 0.6f, 0);
			mMainScene.SetTransform(mSunEntity, transform);
		}
	}

	private void CreateWall(RenderSceneModule renderModule, Vector3 position, Vector3 halfExtents)
	{
		let entity = mMainScene.CreateEntity();
		var transform = mMainScene.GetTransform(entity);
		transform.Position = position;
		transform.Scale = halfExtents * 2.0f;
		mMainScene.SetTransform(entity, transform);

		mMainScene.SetComponent<MeshRendererComponent>(entity, .Default);
		var comp = mMainScene.GetComponent<MeshRendererComponent>(entity);
		comp.Mesh = ResourceHandle<StaticMeshResource>(mCubeResource);
		let defaultMat = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		comp.Material = mWallMaterial ?? defaultMat;
	}

	private void CreateUI()
	{
		if (mUISubsystem == null || !mUISubsystem.IsInitialized)
			return;

		let root = new Canvas();

		let panel = new StackPanel();
		panel.Background = Color(20, 20, 30, 200);
		panel.Padding = Thickness(10);
		panel.Spacing = 6;

		let title = new TextBlock();
		title.Text = "Navigation";
		title.Foreground = Color(200, 220, 255);
		title.FontSize = 14;
		panel.AddChild(title);

		// Add Agent button
		let addBtn = new Button();
		addBtn.ContentText = "Add Agent [1]";
		addBtn.Width = 160;
		addBtn.Click.Subscribe(new (btn) => { mNavDemo?.AddAgentAtRandom(); });
		panel.AddChild(addBtn);

		// Remove Agent button
		let removeBtn = new Button();
		removeBtn.ContentText = "Remove Agent [2]";
		removeBtn.Width = 160;
		removeBtn.Click.Subscribe(new (btn) => { mNavDemo?.RemoveLastAgent(); });
		panel.AddChild(removeBtn);

		// Toggle Mode button
		let modeBtn = new Button();
		modeBtn.ContentText = "Mode: Move [3]";
		modeBtn.Width = 160;
		modeBtn.Click.Subscribe(new (btn) => { mNavDemo?.ToggleMode(); });
		panel.AddChild(modeBtn);

		// Clear Obstacles button
		let clearBtn = new Button();
		clearBtn.ContentText = "Clear Obstacles [4]";
		clearBtn.Width = 160;
		clearBtn.Click.Subscribe(new (btn) => { mNavDemo?.ClearObstacles(); });
		panel.AddChild(clearBtn);

		// Toggle NavMesh button
		let navBtn = new Button();
		navBtn.ContentText = "Toggle NavMesh [N]";
		navBtn.Width = 160;
		navBtn.Click.Subscribe(new (btn) => { mNavDemo?.ToggleNavMeshDraw(); });
		panel.AddChild(navBtn);

		root.AddChild(panel);
		root.SetLeft(panel, 10);
		root.SetTop(panel, 150);
		mUISubsystem.UIContext.RootElement = root;
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		if (keyboard.IsKeyPressed(.P))
			PrintProfilerStats();

		// Navigation controls (block mouse clicks when over a UI control, not the root canvas)
		if (mNavDemo != null)
		{
			let hitElement = mUISubsystem?.UIContext?.HitTest(mouse.X, mouse.Y);
			bool uiHovered = hitElement != null && hitElement != mUISubsystem.UIContext.RootElement;
			mNavDemo.HandleInput(keyboard, mouse, mCamera, mRenderView, uiHovered);
		}

		// Camera (after nav input so nav can consume clicks first)
		mCamera.HandleInput(keyboard, mouse, mDeltaTime);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = (float)frame.DeltaTime;

		if (mDeltaTime > 0)
		{
			let instantFps = 1.0f / mDeltaTime;
			mSmoothedFps = mSmoothedFps * 0.95f + instantFps * 0.05f;
		}

		UpdateCamera();
	}

	private void UpdateCamera()
	{
		var transform = mMainScene.GetTransform(mCameraEntity);
		transform.Position = mCamera.Position;
		let yaw = Math.Atan2(mCamera.Forward.X, mCamera.Forward.Z);
		let pitch = Math.Asin(-mCamera.Forward.Y);
		transform.Rotation = Quaternion.CreateFromYawPitchRoll(yaw, pitch, 0);
		mMainScene.SetTransform(mCameraEntity, transform);

		mRenderView.CameraPosition = mCamera.Position;
		mRenderView.CameraForward = mCamera.Forward;
		mRenderView.CameraUp = .(0, 1, 0);
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		if (let renderModule = mMainScene?.GetModule<RenderSceneModule>())
		{
			if (let world = renderModule.World)
				mRenderSystem.SetActiveWorld(world);
		}

		// Navigation debug draw
		if (mNavDemo != null && mDebugFeature != null)
			mNavDemo.DrawDebug(mDebugFeature, mRenderView);

		// HUD
		DrawHUD();

		// Set camera and render
		mRenderSystem.SetCamera(
			mRenderView.CameraPosition,
			mRenderView.CameraForward,
			.(0, 1, 0),
			mRenderView.FieldOfView,
			mRenderView.AspectRatio,
			mRenderView.NearPlane,
			mRenderView.FarPlane,
			mRenderView.Width,
			mRenderView.Height
		);

		if (mRenderSystem.BuildRenderGraph(mRenderView) case .Ok)
			mRenderSystem.Execute(render.Encoder);

		if (mUISubsystem != null && mUISubsystem.IsInitialized)
		{
			mUISubsystem.RenderUI(render.Encoder, render.CurrentTextureView,
				mSwapChain.Width, mSwapChain.Height, render.Frame.FrameIndex);
		}

		mRenderSystem.EndFrame();
		return true;
	}

	private void DrawHUD()
	{
		if (mDebugFeature == null) return;

		let bgColor = Color(0, 0, 0, 180);
		let white = Color(255, 255, 255, 255);
		let brightYellow = Color(255, 255, 100, 255);
		let brightBlue = Color(100, 180, 255, 255);
		let brightCyan = Color(100, 255, 255, 255);
		let brightGreen = Color(100, 255, 100, 255);
		let brightOrange = Color(255, 180, 100, 255);

		// Top-left: Instructions
		mDebugFeature.AddRect2D(5, 5, 370, 120, bgColor);
		mDebugFeature.AddText2D("NAVIGATION DEMO", 15, 12, brightYellow, 1.5f);

		if (mCamera.CurrentMode == .Orbital)
			mDebugFeature.AddText2D("ORBITAL: WASD rotate, Q/E zoom, RMB drag", 15, 35, white, 1.0f);
		else
			mDebugFeature.AddText2D("FLY: WASD move, Q/E up/down, RMB look", 15, 35, white, 1.0f);

		mDebugFeature.AddText2D("LMB: Move agents / Place obstacle", 15, 52, white, 1.0f);
		mDebugFeature.AddText2D("1-4: Agents/Obstacles   N/V: Toggles", 15, 69, white, 1.0f);
		mDebugFeature.AddText2D("Tab: Camera   P: Profiler   ESC: Exit", 15, 86, white, 1.0f);

		// Top-right: Stats
		float panelX = (float)mRenderView.Width - 200;
		mDebugFeature.AddRect2D(panelX, 5, 195, 105, bgColor);

		let fpsText = scope String();
		((int32)Math.Round(mSmoothedFps)).ToString(fpsText);
		mDebugFeature.AddText2D("FPS:", panelX + 10, 12, brightBlue, 1.5f);
		mDebugFeature.AddText2DRight(fpsText, 10, 12, brightCyan, 1.5f);

		if (mNavDemo != null)
		{
			let agentText = scope String();
			mNavDemo.AgentCount.ToString(agentText);
			mDebugFeature.AddText2D("Agents:", panelX + 10, 35, brightBlue, 1.2f);
			mDebugFeature.AddText2DRight(agentText, 10, 35, brightCyan, 1.2f);

			let obstText = scope String();
			mNavDemo.ObstacleCount.ToString(obstText);
			mDebugFeature.AddText2D("Obstacles:", panelX + 10, 55, brightBlue, 1.2f);
			mDebugFeature.AddText2DRight(obstText, 10, 55, brightCyan, 1.2f);

			let modeText = mNavDemo.IsObstacleMode ? "OBSTACLE" : "MOVE";
			let modeColor = mNavDemo.IsObstacleMode ? brightOrange : brightGreen;
			mDebugFeature.AddText2D("Mode:", panelX + 10, 78, brightBlue, 1.2f);
			mDebugFeature.AddText2DRight(modeText, 10, 78, modeColor, 1.2f);
		}
	}

	private void PrintProfilerStats()
	{
		let frame = SProfiler.GetCompletedFrame();
		Console.WriteLine("\n=== Profiler Frame {} ===", frame.FrameNumber);
		Console.WriteLine("Total Frame Time: {0:F2}ms", frame.FrameDurationMs);

		if (frame.SampleCount > 0)
		{
			for (let sample in frame.Samples)
			{
				let indent = scope String();
				for (int i = 0; i < sample.Depth; i++)
					indent.Append("  ");
				Console.WriteLine("  {0}{1}: {2:F3}ms", indent, sample.Name, sample.DurationMs);
			}
		}
	}

	protected override void OnShutdown()
	{
		Profiler.Shutdown();

		if(mFontService != null)
		{
			delete mFontService;
		}

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();
	}
}

using System;
using Sedulous.Mathematics;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Animation;
using Sedulous.Framework.Physics;
using Sedulous.Framework.Audio;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;
using Sedulous.Physics;
using Sedulous.Physics.Jolt;
using Sedulous.Audio;
using Sedulous.Audio.SDL3;

namespace FrameworkSandbox;

/// Demonstrates the Sedulous Framework with Context, Subsystems, Scenes, and Entities.
class FrameworkSandboxApp : Application
{
	// Framework core
	private Context mContext ~ delete _;
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private Scene mMainScene;

	// Render system (needed by RenderSubsystem)
	private RenderSystem mRenderSystem ~ delete _;
	private RenderView mRenderView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Test objects
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;
	private MaterialInstance mCubeMaterial ~ delete _;
	private MaterialInstance mFloorMaterial ~ delete _;

	// Entities
	private EntityId mFloorEntity;
	private EntityId mCubeEntity;
	private EntityId mCameraEntity;
	private EntityId mSunEntity;

	// Camera control
	private float mCameraYaw = 0.5f;
	private float mCameraPitch = 0.4f;
	private float mCameraDistance = 8.0f;
	private Vector3 mCameraTarget = .(0, 0.5f, 0);

	// Timing
	private float mDeltaTime = 0.016f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize()
	{
		Console.WriteLine("=== Framework Sandbox ===");
		Console.WriteLine("Demonstrating Sedulous Framework\n");

		// Initialize render system first (before subsystems that depend on it)
		InitializeRenderSystem();

		// Create framework context
		mContext = new Context();

		// Create and register subsystems
		RegisterSubsystems();

		// Start up the context (initializes all subsystems)
		mContext.Startup();

		// Create the main scene
		CreateMainScene();

		// Create scene objects
		CreateSceneObjects();

		Console.WriteLine("\n=== Initialization Complete ===");
		Console.WriteLine("Controls:");
		Console.WriteLine("  WASD: Rotate camera");
		Console.WriteLine("  Q/E: Zoom in/out");
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
		Console.WriteLine("RenderSystem initialized");

		// Create render view
		mRenderView = new RenderView();
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.FieldOfView = Math.PI_f / 4.0f;
		mRenderView.NearPlane = 0.1f;
		mRenderView.FarPlane = 100.0f;

		// Register render features
		RegisterRenderFeatures();
	}

	private void RegisterRenderFeatures()
	{
		// Depth prepass
		mDepthFeature = new DepthPrepassFeature();
		if (mRenderSystem.RegisterFeature(mDepthFeature) case .Ok)
			Console.WriteLine("Registered: DepthPrepassFeature");

		// Forward opaque
		mForwardFeature = new ForwardOpaqueFeature();
		if (mRenderSystem.RegisterFeature(mForwardFeature) case .Ok)
			Console.WriteLine("Registered: ForwardOpaqueFeature");

		// Sky
		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Ok)
			Console.WriteLine("Registered: SkyFeature");

		// Final output
		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Ok)
			Console.WriteLine("Registered: FinalOutputFeature");
	}

	private void RegisterSubsystems()
	{
		Console.WriteLine("\nRegistering subsystems...");

		// Scene subsystem (manages scenes)
		mSceneSubsystem = new SceneSubsystem();
		mContext.RegisterSubsystem(mSceneSubsystem);
		Console.WriteLine("  - SceneSubsystem (manages scene lifecycle)");

		// Animation subsystem
		let animSubsystem = new AnimationSubsystem();
		mContext.RegisterSubsystem(animSubsystem);
		Console.WriteLine("  - AnimationSubsystem (skeletal animation)");

		// Audio subsystem
		let audioSystem = new SDL3AudioSystem();
		if (audioSystem.IsInitialized)
		{
			let audioSubsystem = new AudioSubsystem(audioSystem, takeOwnership: true);
			mContext.RegisterSubsystem(audioSubsystem);
			Console.WriteLine("  - AudioSubsystem (SDL3 backend)");
		}
		else
		{
			delete audioSystem;
			Console.WriteLine("  - AudioSubsystem SKIPPED (failed to initialize)");
		}

		// Physics subsystem
		let physicsSubsystem = new PhysicsSubsystem(
			new (desc) => {
				switch (JoltPhysicsWorld.Create(desc))
				{
				case .Ok(let world): return .Ok(world);
				case .Err: return .Err;
				}
			}
		);
		mContext.RegisterSubsystem(physicsSubsystem);
		Console.WriteLine("  - PhysicsSubsystem (Jolt backend)");

		// Render subsystem
		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		mContext.RegisterSubsystem(mRenderSubsystem);
		Console.WriteLine("  - RenderSubsystem");
	}

	private void CreateMainScene()
	{
		Console.WriteLine("\nCreating main scene...");

		// Create scene through SceneSubsystem (notifies ISceneAware subsystems)
		mMainScene = mSceneSubsystem.CreateScene("MainScene");
		mSceneSubsystem.SetActiveScene(mMainScene);

		// Add our custom gameplay module
		let gameplayModule = new GameplaySceneModule();
		mMainScene.AddModule(gameplayModule);

		Console.WriteLine("Scene created with modules:");
		// List modules that were auto-added by ISceneAware subsystems
		Console.WriteLine("  - GameplaySceneModule (custom)");
		Console.WriteLine("  - AnimationSceneModule (from AnimationSubsystem)");
		Console.WriteLine("  - AudioSceneModule (from AudioSubsystem)");
		Console.WriteLine("  - PhysicsSceneModule (from PhysicsSubsystem)");
		Console.WriteLine("  - RenderSceneModule (from RenderSubsystem)");
	}

	private void CreateSceneObjects()
	{
		Console.WriteLine("\nCreating scene objects...");

		// Get render module for creating render components
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		if (renderModule == null)
		{
			Console.WriteLine("ERROR: RenderSceneModule not found!");
			return;
		}

		// Create meshes
		CreateMeshes();

		// Get default material
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Create cube material (blue)
		if (let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			mCubeMaterial = new MaterialInstance(baseMaterial);
			mCubeMaterial.SetColor("BaseColor", .(0.2f, 0.6f, 0.9f, 1.0f));

			mFloorMaterial = new MaterialInstance(baseMaterial);
			mFloorMaterial.SetColor("BaseColor", .(0.8f, 0.8f, 0.8f, 1.0f));
		}

		// Create floor entity
		mFloorEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFloorEntity);
			transform.Position = .(0, 0, 0);
			mMainScene.SetTransform(mFloorEntity, transform);

			let handle = renderModule.CreateMeshRenderer(mFloorEntity);
			if (handle.IsValid)
			{
				renderModule.SetMeshData(mFloorEntity, mPlaneMeshHandle, BoundingBox(Vector3(-5, 0, -5), Vector3(5, 0.01f, 5)));
				renderModule.SetMeshMaterial(mFloorEntity, mFloorMaterial ?? defaultMaterial);
			}
		}
		Console.WriteLine("  Created floor entity");

		// Create spinning cube entity
		mCubeEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mCubeEntity);
			transform.Position = .(0, 0.5f, 0);
			mMainScene.SetTransform(mCubeEntity, transform);

			// Add custom components
			mMainScene.SetComponent<SpinComponent>(mCubeEntity, SpinComponent() { Speed = 1.0f, CurrentAngle = 0 });
			mMainScene.SetComponent<BobComponent>(mCubeEntity, BobComponent() { Speed = 2.0f, Amplitude = 0.2f, BaseY = 0.5f, Phase = 0 });

			let handle = renderModule.CreateMeshRenderer(mCubeEntity);
			if (handle.IsValid)
			{
				renderModule.SetMeshData(mCubeEntity, mCubeMeshHandle, BoundingBox(Vector3(-0.5f), Vector3(0.5f)));
				renderModule.SetMeshMaterial(mCubeEntity, mCubeMaterial ?? defaultMaterial);
			}
		}
		Console.WriteLine("  Created spinning cube entity with SpinComponent and BobComponent");

		// Create camera entity
		mCameraEntity = mMainScene.CreateEntity();
		{
			renderModule.CreatePerspectiveCamera(mCameraEntity, Math.PI_f / 4.0f, (float)mSwapChain.Width / mSwapChain.Height, 0.1f, 100.0f);
			renderModule.SetMainCamera(mCameraEntity);
		}
		Console.WriteLine("  Created camera entity");

		// Create sun light entity
		mSunEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSunEntity);
			// Point light direction via transform forward
			transform.Rotation = Quaternion.CreateFromAxisAngle(.(1, 0, 0), -0.8f) * Quaternion.CreateFromAxisAngle(.(0, 1, 0), 0.5f);
			mMainScene.SetTransform(mSunEntity, transform);

			renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.98f, 0.95f), 2.0f);
		}
		Console.WriteLine("  Created sun light entity");

		// Set world ambient
		if (let world = renderModule.World)
		{
			world.AmbientColor = .(0.05f, 0.05f, 0.08f);
			world.AmbientIntensity = 1.0f;
		}

		Console.WriteLine("\nEntity count: {}", mMainScene.EntityCount);
	}

	private void CreateMeshes()
	{
		// Create cube mesh
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let cubeHandle))
			mCubeMeshHandle = cubeHandle;
		delete cubeMesh;

		// Create floor plane mesh
		let planeMesh = StaticMesh.CreatePlane(10.0f, 10.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let planeHandle))
			mPlaneMeshHandle = planeHandle;
		delete planeMesh;
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		// Camera rotation
		float rotSpeed = 0.02f;
		if (keyboard.IsKeyDown(.A))
			mCameraYaw -= rotSpeed;
		if (keyboard.IsKeyDown(.D))
			mCameraYaw += rotSpeed;
		if (keyboard.IsKeyDown(.W))
			mCameraPitch = Math.Clamp(mCameraPitch + rotSpeed, -1.4f, 1.4f);
		if (keyboard.IsKeyDown(.S))
			mCameraPitch = Math.Clamp(mCameraPitch - rotSpeed, -1.4f, 1.4f);

		// Camera zoom
		if (keyboard.IsKeyDown(.Q))
			mCameraDistance = Math.Clamp(mCameraDistance - 0.1f, 2.0f, 20.0f);
		if (keyboard.IsKeyDown(.E))
			mCameraDistance = Math.Clamp(mCameraDistance + 0.1f, 2.0f, 20.0f);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = (float)frame.DeltaTime;

		// Update framework context (updates all subsystems and scenes)
		mContext.BeginFrame(mDeltaTime);
		mContext.Update(mDeltaTime);
		mContext.EndFrame();

		// Update camera transform
		UpdateCamera();
	}

	private void UpdateCamera()
	{
		// Calculate orbital camera position
		float x = mCameraDistance * Math.Cos(mCameraPitch) * Math.Sin(mCameraYaw);
		float y = mCameraDistance * Math.Sin(mCameraPitch);
		float z = mCameraDistance * Math.Cos(mCameraPitch) * Math.Cos(mCameraYaw);

		let cameraPos = mCameraTarget + Vector3(x, y, z);
		let cameraForward = Vector3.Normalize(mCameraTarget - cameraPos);

		// Update camera entity transform
		var transform = mMainScene.GetTransform(mCameraEntity);
		transform.Position = cameraPos;
		// Calculate rotation from forward vector
		let yaw = Math.Atan2(cameraForward.X, cameraForward.Z);
		let pitch = Math.Asin(-cameraForward.Y);
		transform.Rotation = Quaternion.CreateFromYawPitchRoll(yaw, pitch, 0);
		mMainScene.SetTransform(mCameraEntity, transform);

		// Also update render view for rendering
		mRenderView.CameraPosition = cameraPos;
		mRenderView.CameraForward = cameraForward;
		mRenderView.CameraUp = .(0, 1, 0);
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		// Begin frame
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		// Set swapchain for final output
		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		// Set the active world from the scene's render module
		if (let renderModule = mMainScene?.GetModule<RenderSceneModule>())
		{
			if (let world = renderModule.World)
				mRenderSystem.SetActiveWorld(world);
		}

		// Set camera
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

		// Build and execute render graph
		if (mRenderSystem.BuildRenderGraph(mRenderView) case .Ok)
		{
			mRenderSystem.Execute(render.Encoder);
		}

		// End frame
		mRenderSystem.EndFrame();

		return true;
	}

	protected override void OnShutdown()
	{
		Console.WriteLine("\n=== Shutting Down ===");

		// Release mesh handles before render system shutdown
		if (mCubeMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
		if (mPlaneMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);

		// Context destructor will dispose all subsystems automatically via ~ delete _

		// Shutdown render system (not owned by context)
		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Shutdown complete");
	}
}

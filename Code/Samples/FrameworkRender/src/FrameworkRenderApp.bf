using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;
using Sedulous.Profiler;

namespace FrameworkRender;

/// Demonstrates render performance with massive object counts.
/// Tests the rendering pipeline with tens of thousands of spheres.
class FrameworkRenderApp : Application
{
	// Framework core
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private Scene mMainScene;

	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderView mRenderView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private DebugRenderFeature mDebugFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Meshes
	private GPUMeshHandle mSphereMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;

	// Materials
	private MaterialInstance mFloorMaterial ~ delete _;
	private MaterialInstance mSharedSphereMaterial ~ delete _;
	private List<MaterialInstance> mUniqueMaterials = new .() ~ DeleteContainerAndItems!(_);

	// Entities
	private EntityId mFloorEntity;
	private EntityId mCameraEntity;
	private EntityId mSunEntity;
	private List<EntityId> mSphereEntities = new .() ~ delete _;

	// Camera control
	private OrbitFlyCamera mCamera ~ delete _;

	// Shared camera state
	private Vector3 mCameraPosition;
	private Vector3 mCameraForward;

	// Timing and FPS
	private float mDeltaTime = 0.016f;
	private float mSmoothedFps = 60.0f;
	private float mFrameTimeMs = 16.67f;

	// Sphere grid settings
	private const int32 SpheresPerBatch = 8000;
	private const float SphereRadius = 0.5f;
	private const float SphereSpacing = 1.5f;
	private int32 mCurrentBatchCount = 0;
	private int32 mGridSize = 0;

	// Material mode
	private bool mUseUniqueMaterials = false;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
		mCamera = new .();
		mCamera.OrbitalYaw = 0.0f;
		mCamera.OrbitalPitch = 0.6f;
		mCamera.OrbitalDistance = 200.0f;
		mCamera.MoveSpeed = 100.0f;
		mCamera.MinDistance = 10.0f;
		mCamera.MaxDistance = 2000.0f;
		mCamera.ProportionalZoom = true;
		mCamera.FlyPosition = .(0, 50, 200);
		mCamera.Update();
	}

	protected override void OnInitialize(Context context)
	{
		Console.WriteLine("=== Framework Render - Sphere Stress Test ===\n");

		// Initialize render system
		InitializeRenderSystem();

		// Register subsystems
		RegisterSubsystems(context);
	}

	protected override void OnContextStarted()
	{
		SProfiler.Initialize();

		// Create the main scene
		CreateMainScene();

		// Create initial scene objects
		CreateSceneObjects();

		// Add first batch of spheres
		AddSphereBatch();

		Console.WriteLine("\n=== Initialization Complete ===");
		Console.WriteLine("Controls:");
		Console.WriteLine("  Tab: Toggle camera mode (Orbital/Flythrough)");
		Console.WriteLine("  `: Return to orbital mode");
		Console.WriteLine("  Orbital: WASD rotate, Q/E zoom");
		Console.WriteLine("  Flythrough: WASD move, Q/E up/down, Mouse look, Shift=fast");
		Console.WriteLine("  Space: Add 8,000 spheres");
		Console.WriteLine("  M: Toggle unique materials");
		Console.WriteLine("  P: Print profiler stats");
		Console.WriteLine("  ESC: Release mouse / Exit\n");
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
		mRenderView.FarPlane = 1000.0f;

		// Register render features
		RegisterRenderFeatures();
	}

	private void RegisterRenderFeatures()
	{
		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		mDebugFeature = new DebugRenderFeature();
		mRenderSystem.RegisterFeature(mDebugFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void RegisterSubsystems(Context context)
	{
		Console.WriteLine("\nRegistering subsystems...");

		// Scene subsystem
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);
		Console.WriteLine("  - SceneSubsystem");

		// Render subsystem
		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);
		Console.WriteLine("  - RenderSubsystem");
	}

	private void CreateMainScene()
	{
		Console.WriteLine("\nCreating main scene...");

		mMainScene = mSceneSubsystem.CreateScene("MainScene");
		mSceneSubsystem.SetActiveScene(mMainScene);
	}

	private void CreateSceneObjects()
	{
		Console.WriteLine("Creating scene objects...");

		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		if (renderModule == null)
		{
			Console.WriteLine("ERROR: RenderSceneModule not found!");
			return;
		}

		// Create meshes
		CreateMeshes();

		// Create materials
		CreateMaterials();

		// Create floor
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		mFloorEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mFloorEntity);
			transform.Position = .(0, -1.0f, 0);
			mMainScene.SetTransform(mFloorEntity, transform);

			let handle = renderModule.CreateMeshRenderer(mFloorEntity);
			if (handle.IsValid)
			{
				renderModule.SetMeshData(mFloorEntity, mPlaneMeshHandle, BoundingBox(Vector3(-500, 0, -500), Vector3(500, 0.01f, 500)));
				renderModule.SetMeshMaterial(mFloorEntity, mFloorMaterial ?? defaultMaterial);
			}
		}

		// Create camera
		mCameraEntity = mMainScene.CreateEntity();
		{
			renderModule.CreatePerspectiveCamera(mCameraEntity, Math.PI_f / 4.0f, (float)mSwapChain.Width / mSwapChain.Height, 0.1f, 1000.0f);
			renderModule.SetMainCamera(mCameraEntity);
		}

		// Create sun light
		mSunEntity = mMainScene.CreateEntity();
		{
			var transform = mMainScene.GetTransform(mSunEntity);
			transform.Rotation = Quaternion.CreateFromAxisAngle(.(1, 0, 0), -0.7f) * Quaternion.CreateFromAxisAngle(.(0, 1, 0), 0.3f);
			mMainScene.SetTransform(mSunEntity, transform);

			renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.98f, 0.95f), 2.5f);
		}

		// Set world ambient
		if (let world = renderModule.World)
		{
			world.AmbientColor = .(0.1f, 0.1f, 0.15f);
			world.AmbientIntensity = 1.0f;
		}
	}

	private void CreateMeshes()
	{
		// Create sphere mesh
		let sphereMesh = StaticMesh.CreateSphere(SphereRadius, 12, 8);
		if (mRenderSystem.ResourceManager.UploadMesh(sphereMesh) case .Ok(let sphereHandle))
			mSphereMeshHandle = sphereHandle;
		delete sphereMesh;

		// Create floor plane
		let planeMesh = StaticMesh.CreatePlane(1000, 1000, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let planeHandle))
			mPlaneMeshHandle = planeHandle;
		delete planeMesh;
	}

	private void CreateMaterials()
	{
		if (let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			mFloorMaterial = new MaterialInstance(baseMaterial);
			mFloorMaterial.SetColor("BaseColor", .(0.15f, 0.15f, 0.15f, 1.0f));

			mSharedSphereMaterial = new MaterialInstance(baseMaterial);
			mSharedSphereMaterial.SetColor("BaseColor", .(0.8f, 0.3f, 0.2f, 1.0f));
		}
	}

	private void AddSphereBatch()
	{
		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return;

		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial;

		// Calculate grid dimensions for the new batch
		// We want a square grid, so find the side length
		int32 newTotal = (mCurrentBatchCount + 1) * SpheresPerBatch;
		mGridSize = (int32)Math.Ceiling(Math.Sqrt((float)newTotal));

		// Calculate grid extent
		float gridExtent = (float)mGridSize * SphereSpacing * 0.5f;

		// Starting index for this batch
		int32 startIndex = mCurrentBatchCount * SpheresPerBatch;

		Console.WriteLine("Adding sphere batch {} ({} spheres, grid size {}x{})...", mCurrentBatchCount + 1, SpheresPerBatch, mGridSize, mGridSize);

		for (int32 i = 0; i < SpheresPerBatch; i++)
		{
			int32 index = startIndex + i;

			// Convert linear index to grid position
			int32 gridX = index % mGridSize;
			int32 gridZ = index / mGridSize;

			// Calculate world position (centered at origin)
			float x = ((float)gridX - (float)mGridSize * 0.5f) * SphereSpacing;
			float z = ((float)gridZ - (float)mGridSize * 0.5f) * SphereSpacing;
			float y = 0.0f;

			let entity = mMainScene.CreateEntity();
			mSphereEntities.Add(entity);

			var transform = mMainScene.GetTransform(entity);
			transform.Position = .(x, y, z);
			mMainScene.SetTransform(entity, transform);

			let handle = renderModule.CreateMeshRenderer(entity);
			if (handle.IsValid)
			{
				renderModule.SetMeshData(entity, mSphereMeshHandle, BoundingBox(Vector3(-SphereRadius), Vector3(SphereRadius)));

				// Use shared or unique material based on mode
				if (mUseUniqueMaterials && baseMaterial != null)
				{
					// Create unique material with color based on position
					let uniqueMat = new MaterialInstance(baseMaterial);
					let hue = (float)(index % 360) / 360.0f;
					let color = HSVtoRGB(hue, 0.8f, 0.9f);
					uniqueMat.SetColor("BaseColor", .(color.X, color.Y, color.Z, 1.0f));
					mUniqueMaterials.Add(uniqueMat);
					renderModule.SetMeshMaterial(entity, uniqueMat);
				}
				else
				{
					renderModule.SetMeshMaterial(entity, mSharedSphereMaterial ?? defaultMaterial);
				}
			}
		}

		mCurrentBatchCount++;

		// Update camera distance based on grid size
		mCamera.OrbitalDistance = Math.Max(50.0f, gridExtent * 1.5f);
		mCamera.OrbitalTarget = .(0, 0, 0);

		Console.WriteLine("Total spheres: {}", mSphereEntities.Count);
	}

	private void ToggleUniqueMaterials()
	{
		mUseUniqueMaterials = !mUseUniqueMaterials;

		let renderModule = mMainScene.GetModule<RenderSceneModule>();
		if (renderModule == null)
			return;

		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial;

		Console.WriteLine("Switching to {} materials...", mUseUniqueMaterials ? "unique" : "shared");

		// Clear existing unique materials
		DeleteContainerAndItems!(mUniqueMaterials);
		mUniqueMaterials = new .();

		// Update all sphere materials
		for (int32 i = 0; i < mSphereEntities.Count; i++)
		{
			let entity = mSphereEntities[i];

			if (mUseUniqueMaterials && baseMaterial != null)
			{
				let uniqueMat = new MaterialInstance(baseMaterial);
				let hue = (float)(i % 360) / 360.0f;
				let color = HSVtoRGB(hue, 0.8f, 0.9f);
				uniqueMat.SetColor("BaseColor", .(color.X, color.Y, color.Z, 1.0f));
				mUniqueMaterials.Add(uniqueMat);
				renderModule.SetMeshMaterial(entity, uniqueMat);
			}
			else
			{
				renderModule.SetMeshMaterial(entity, mSharedSphereMaterial ?? defaultMaterial);
			}
		}

		Console.WriteLine("Material switch complete. {} materials active.", mUseUniqueMaterials ? mUniqueMaterials.Count : 1);
	}

	private Vector3 HSVtoRGB(float h, float s, float v)
	{
		float c = v * s;
		float x = c * (1.0f - Math.Abs(Math.IEEERemainder(h * 6.0f, 2.0f) - 1.0f));
		float m = v - c;

		float r, g, b;
		if (h < 1.0f/6.0f) { r = c; g = x; b = 0; }
		else if (h < 2.0f/6.0f) { r = x; g = c; b = 0; }
		else if (h < 3.0f/6.0f) { r = 0; g = c; b = x; }
		else if (h < 4.0f/6.0f) { r = 0; g = x; b = c; }
		else if (h < 5.0f/6.0f) { r = x; g = 0; b = c; }
		else { r = c; g = 0; b = x; }

		return .(r + m, g + m, b + m);
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		// Add more spheres
		if (keyboard.IsKeyPressed(.Space))
			AddSphereBatch();

		// Toggle unique materials
		if (keyboard.IsKeyPressed(.M))
			ToggleUniqueMaterials();

		// Print profiler stats
		if (keyboard.IsKeyPressed(.P))
			PrintProfilerStats();

		// Camera input
		mCamera.HandleInput(keyboard, mouse, mDeltaTime);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = (float)frame.DeltaTime;

		// Update smoothed FPS
		if (mDeltaTime > 0)
		{
			let instantFps = 1.0f / mDeltaTime;
			mSmoothedFps = mSmoothedFps * 0.95f + instantFps * 0.05f;
			mFrameTimeMs = mFrameTimeMs * 0.95f + (mDeltaTime * 1000.0f) * 0.05f;
		}

		// Update camera
		UpdateCamera();
	}

	private void UpdateCamera()
	{
		mCameraPosition = mCamera.Position;
		mCameraForward = mCamera.Forward;

		// Apply to scene entity
		var transform = mMainScene.GetTransform(mCameraEntity);
		transform.Position = mCameraPosition;
		let yaw = Math.Atan2(mCameraForward.X, mCameraForward.Z);
		let pitch = Math.Asin(-mCameraForward.Y);
		transform.Rotation = Quaternion.CreateFromYawPitchRoll(yaw, pitch, 0);
		mMainScene.SetTransform(mCameraEntity, transform);

		// Update render view
		mRenderView.CameraPosition = mCameraPosition;
		mRenderView.CameraForward = mCameraForward;
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

		// Draw debug HUD
		DrawDebugHUD();

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

		mRenderSystem.EndFrame();

		return true;
	}

	private void DrawDebugHUD()
	{
		if (mDebugFeature == null)
			return;

		let bgColor = Color(0, 0, 0, 200);
		let white = Color(255, 255, 255, 255);
		let brightBlue = Color(100, 180, 255, 255);
		let brightCyan = Color(100, 255, 255, 255);
		let brightGreen = Color(100, 255, 100, 255);
		let brightYellow = Color(255, 255, 100, 255);
		let brightOrange = Color(255, 180, 100, 255);

		// ===== TOP LEFT: Instructions =====
		mDebugFeature.AddRect2D(5, 5, 400, 120, bgColor);
		mDebugFeature.AddText2D("SPHERE STRESS TEST", 15, 12, brightYellow, 1.5f);

		if (mCamera.CurrentMode == .Orbital)
		{
			mDebugFeature.AddText2D("ORBITAL: WASD rotate, Q/E zoom", 15, 35, white, 1.0f);
		}
		else
		{
			mDebugFeature.AddText2D("FLY: WASD move, Q/E up/down, Mouse look", 15, 35, white, 1.0f);
		}

		mDebugFeature.AddText2D("Tab: Toggle camera    `: Back to orbital", 15, 52, white, 1.0f);
		mDebugFeature.AddText2D("Space: Add 8,000 spheres", 15, 69, white, 1.0f);
		mDebugFeature.AddText2D("M: Toggle materials   P: Profiler", 15, 86, white, 1.0f);
		mDebugFeature.AddText2D("ESC: Release mouse / Exit", 15, 103, white, 1.0f);

		// ===== TOP RIGHT: Stats =====
		float panelX = (float)mRenderView.Width - 220;
		mDebugFeature.AddRect2D(panelX, 5, 215, 135, bgColor);

		// FPS
		let fpsText = scope String();
		((int32)Math.Round(mSmoothedFps)).ToString(fpsText);
		mDebugFeature.AddText2D("FPS:", panelX + 10, 12, brightBlue, 1.5f);
		mDebugFeature.AddText2DRight(fpsText, 10, 12, brightCyan, 1.5f);

		// Frame time
		let frameTimeText = scope String();
		frameTimeText.AppendF("{0:F2} ms", mFrameTimeMs);
		mDebugFeature.AddText2D("Frame:", panelX + 10, 35, brightBlue, 1.5f);
		mDebugFeature.AddText2DRight(frameTimeText, 10, 35, brightCyan, 1.5f);

		// Object count
		let countText = scope String();
		mSphereEntities.Count.ToString(countText);
		mDebugFeature.AddText2D("Spheres:", panelX + 10, 58, brightBlue, 1.5f);
		mDebugFeature.AddText2DRight(countText, 10, 58, brightCyan, 1.5f);

		// Material mode
		let matMode = mUseUniqueMaterials ? "UNIQUE" : "SHARED";
		let matColor = mUseUniqueMaterials ? brightYellow : brightGreen;
		mDebugFeature.AddText2D("Materials:", panelX + 10, 81, brightBlue, 1.5f);
		mDebugFeature.AddText2DRight(matMode, 10, 81, matColor, 1.5f);

		// Material count
		let matCountText = scope String();
		if (mUseUniqueMaterials)
			mUniqueMaterials.Count.ToString(matCountText);
		else
			matCountText.Set("1");
		mDebugFeature.AddText2D("Mat Count:", panelX + 10, 98, brightBlue, 1.2f);
		mDebugFeature.AddText2DRight(matCountText, 10, 98, brightCyan, 1.2f);

		// Camera mode
		let camMode = (mCamera.CurrentMode == .Orbital) ? "ORBITAL" : "FLYTHROUGH";
		let camColor = (mCamera.CurrentMode == .Orbital) ? brightGreen : brightOrange;
		mDebugFeature.AddText2D("Camera:", panelX + 10, 118, brightBlue, 1.2f);
		mDebugFeature.AddText2DRight(camMode, 10, 118, camColor, 1.2f);
	}

	private void PrintProfilerStats()
	{
		let frame = SProfiler.GetCompletedFrame();
		Console.WriteLine("\n=== Profiler Frame {} ===", frame.FrameNumber);
		Console.WriteLine("Total Frame Time: {0:F2}ms", frame.FrameDurationMs);
		Console.WriteLine("Samples: {}", frame.SampleCount);

		if (frame.SampleCount > 0)
		{
			Console.WriteLine("\nBreakdown:");
			for (let sample in frame.Samples)
			{
				let indent = scope String();
				for (int i = 0; i < sample.Depth; i++)
					indent.Append("  ");
				Console.WriteLine("  {0}{1}: {2:F3}ms", indent, sample.Name, sample.DurationMs);
			}
		}
		Console.WriteLine("");
	}

	protected override void OnShutdown()
	{
		Profiler.Shutdown();

		Console.WriteLine("\n=== Shutting Down ===");

		if (mSphereMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mSphereMeshHandle, mRenderSystem.FrameNumber);
		if (mPlaneMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Shutdown complete");
	}
}

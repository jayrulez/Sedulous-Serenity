namespace TowerDefense;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Engine.Audio;
using Sedulous.Renderer;
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Audio.Decoders;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Debug;
using SampleFramework;

/// Tower Defense game main class.
/// Phase 1: Foundation - Context/Scene/Entity setup with rendering and audio.
class TowerDefenseGame : RHISampleApp
{
	// Engine Core
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;  // Owned by SceneManager

	// Services
	private RendererService mRendererService;
	private AudioService mAudioService;
	private RenderSceneComponent mRenderSceneComponent;

	// Audio backend
	private SDL3AudioSystem mAudioSystem;
	private AudioDecoderFactory mDecoderFactory ~ delete _;

	// Materials
	private MaterialHandle mPBRMaterial = .Invalid;
	private MaterialInstanceHandle mGroundMaterial = .Invalid;
	private MaterialInstanceHandle mCubeMaterial = .Invalid;

	// Entities
	private Entity mCameraEntity;
	private Entity mTestCubeEntity;

	// Camera control (top-down)
	private float mCameraHeight = 30.0f;
	private float mCameraTargetX = 0.0f;
	private float mCameraTargetZ = 0.0f;
	private float mCameraMoveSpeed = 20.0f;

	// Current frame
	private int32 mCurrentFrameIndex = 0;

	public this() : base(.()
		{
			Title = "Tower Defense",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.2f, 0.3f, 0.2f, 1.0f),  // Grass-like green
			EnableDepth = true
		})
	{
	}

	protected override bool OnInitialize()
	{
		Console.WriteLine("=== Tower Defense - Phase 1: Foundation ===");

		// Create logger
		mLogger = new DebugLogger(.Information);

		// Create engine context
		mContext = new Context(mLogger, 4);

		// Initialize renderer service
		if (!InitializeRenderer())
			return false;

		// Initialize audio service
		if (!InitializeAudio())
			return false;

		// Start context (enables automatic component creation)
		mContext.Startup();

		// Create game scene
		mScene = mContext.SceneManager.CreateScene("GameScene");
		mRenderSceneComponent = mScene.GetSceneComponent<RenderSceneComponent>();
		mContext.SceneManager.SetActiveScene(mScene);

		// Create materials
		CreateMaterials();

		// Create entities
		CreateEntities();

		Console.WriteLine("Initialization complete!");
		Console.WriteLine("Controls: WASD=Pan camera, QE=Zoom, Escape=Exit");

		return true;
	}

	private bool InitializeRenderer()
	{
		Console.WriteLine("Initializing renderer service...");

		mRendererService = new RendererService();
		mRendererService.SetFormats(SwapChain.Format, .Depth24PlusStencil8);

		let shaderPath = GetAssetPath("framework/shaders", .. scope .());
		if (mRendererService.Initialize(Device, shaderPath) case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}

		mContext.RegisterService<RendererService>(mRendererService);
		Console.WriteLine("Renderer service initialized");
		return true;
	}

	private bool InitializeAudio()
	{
		Console.WriteLine("Initializing audio service...");

		// Create SDL3 audio backend
		mAudioSystem = new SDL3AudioSystem();
		if (!mAudioSystem.IsInitialized)
		{
			Console.WriteLine("WARNING: Audio system failed to initialize");
			delete mAudioSystem;
			mAudioSystem = null;
			return true;  // Continue without audio
		}

		// Create decoder factory
		mDecoderFactory = new AudioDecoderFactory();
		mDecoderFactory.RegisterDefaultDecoders();

		// Create and register audio service
		mAudioService = new AudioService();
		if (mAudioService.Initialize(mAudioSystem) case .Err)
		{
			Console.WriteLine("WARNING: AudioService failed to initialize");
			delete mAudioService;
			mAudioService = null;
			return true;
		}

		mContext.RegisterService<AudioService>(mAudioService);
		Console.WriteLine($"Audio service initialized. Decoders: {mDecoderFactory.DecoderCount}");
		return true;
	}

	private void CreateMaterials()
	{
		let materialSystem = mRendererService.MaterialSystem;
		if (materialSystem == null)
			return;

		// Create PBR material
		let pbrMaterial = Material.CreatePBR("PBRMaterial");
		mPBRMaterial = materialSystem.RegisterMaterial(pbrMaterial);

		if (!mPBRMaterial.IsValid)
		{
			Console.WriteLine("Failed to register PBR material");
			return;
		}

		// Ground material (gray)
		mGroundMaterial = materialSystem.CreateInstance(mPBRMaterial);
		if (mGroundMaterial.IsValid)
		{
			let instance = materialSystem.GetInstance(mGroundMaterial);
			if (instance != null)
			{
				instance.SetFloat4("baseColor", .(0.3f, 0.5f, 0.3f, 1.0f));  // Grass green
				instance.SetFloat("metallic", 0.0f);
				instance.SetFloat("roughness", 0.9f);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0, 0, 0, 1));
				materialSystem.UploadInstance(mGroundMaterial);
			}
		}

		// Test cube material (orange)
		mCubeMaterial = materialSystem.CreateInstance(mPBRMaterial);
		if (mCubeMaterial.IsValid)
		{
			let instance = materialSystem.GetInstance(mCubeMaterial);
			if (instance != null)
			{
				instance.SetFloat4("baseColor", .(0.9f, 0.5f, 0.2f, 1.0f));  // Orange
				instance.SetFloat("metallic", 0.2f);
				instance.SetFloat("roughness", 0.5f);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0, 0, 0, 1));
				materialSystem.UploadInstance(mCubeMaterial);
			}
		}

		Console.WriteLine("Materials created");
	}

	private void CreateEntities()
	{
		// Create shared cube mesh
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		defer delete cubeMesh;

		// Create ground plane (large flat cube)
		{
			let ground = mScene.CreateEntity("Ground");
			ground.Transform.SetPosition(.(0, -0.5f, 0));
			ground.Transform.SetScale(.(30.0f, 1.0f, 30.0f));

			let meshComp = new StaticMeshComponent();
			ground.AddComponent(meshComp);
			meshComp.SetMesh(cubeMesh);
			meshComp.SetMaterialInstance(0, mGroundMaterial);
		}

		// Create test cube at origin
		{
			mTestCubeEntity = mScene.CreateEntity("TestCube");
			mTestCubeEntity.Transform.SetPosition(.(0, 1.0f, 0));

			let meshComp = new StaticMeshComponent();
			mTestCubeEntity.AddComponent(meshComp);
			meshComp.SetMesh(cubeMesh);
			meshComp.SetMaterialInstance(0, mCubeMaterial);
		}

		// Create directional light (sun)
		{
			let sunLight = mScene.CreateEntity("SunLight");
			sunLight.Transform.LookAt(.(-0.5f, -1.0f, -0.3f));

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.95f, 0.8f), 1.0f, true);
			sunLight.AddComponent(lightComp);
		}

		// Create top-down camera
		{
			mCameraEntity = mScene.CreateEntity("MainCamera");
			UpdateCameraTransform();

			let cameraComp = new CameraComponent(Math.PI_f / 4.0f, 0.1f, 500.0f, true);
			cameraComp.UseReverseZ = false;
			cameraComp.SetViewport(SwapChain.Width, SwapChain.Height);
			mCameraEntity.AddComponent(cameraComp);
		}

		Console.WriteLine("Entities created");
	}

	private void UpdateCameraTransform()
	{
		if (mCameraEntity == null)
			return;

		// Position camera above target, looking down
		mCameraEntity.Transform.SetPosition(.(mCameraTargetX, mCameraHeight, mCameraTargetZ + 0.1f));

		// Look at target point
		let target = Vector3(mCameraTargetX, 0, mCameraTargetZ);
		mCameraEntity.Transform.LookAt(target);
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		if (let cameraComp = mCameraEntity?.GetComponent<CameraComponent>())
		{
			cameraComp.SetViewport(width, height);
		}
	}

	protected override void OnInput()
	{
		let keyboard = Shell.InputManager.Keyboard;

		// Camera panning with WASD
		float panSpeed = mCameraMoveSpeed * DeltaTime;

		if (keyboard.IsKeyDown(.W))
			mCameraTargetZ -= panSpeed;
		if (keyboard.IsKeyDown(.S))
			mCameraTargetZ += panSpeed;
		if (keyboard.IsKeyDown(.A))
			mCameraTargetX -= panSpeed;
		if (keyboard.IsKeyDown(.D))
			mCameraTargetX += panSpeed;

		// Zoom with Q/E
		float zoomSpeed = 20.0f * DeltaTime;
		if (keyboard.IsKeyDown(.Q))
			mCameraHeight = Math.Max(10.0f, mCameraHeight - zoomSpeed);
		if (keyboard.IsKeyDown(.E))
			mCameraHeight = Math.Min(100.0f, mCameraHeight + zoomSpeed);

		UpdateCameraTransform();
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Rotate test cube
		if (mTestCubeEntity != null)
		{
			let rotation = Quaternion.CreateFromYawPitchRoll(totalTime * 0.5f, 0, 0);
			mTestCubeEntity.Transform.SetRotation(rotation);
		}

		// Update engine context (handles entity sync, visibility culling, etc.)
		mContext.Update(deltaTime);
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		mCurrentFrameIndex = frameIndex;

		// Begin render graph frame
		mRendererService.BeginFrame(
			(uint32)frameIndex, DeltaTime, TotalTime,
			SwapChain.CurrentTexture, SwapChain.CurrentTextureView,
			mDepthTexture, DepthTextureView);
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Execute all render passes
		mRendererService.ExecuteFrame(encoder);
		return true;
	}

	protected override void OnCleanup()
	{
		Console.WriteLine("Cleaning up...");

		// Shutdown context
		mContext?.Shutdown();

		// Wait for GPU
		Device.WaitIdle();

		// Clean up materials
		if (mRendererService?.MaterialSystem != null)
		{
			let materialSystem = mRendererService.MaterialSystem;

			if (mCubeMaterial.IsValid)
				materialSystem.ReleaseInstance(mCubeMaterial);
			if (mGroundMaterial.IsValid)
				materialSystem.ReleaseInstance(mGroundMaterial);
			if (mPBRMaterial.IsValid)
				materialSystem.ReleaseMaterial(mPBRMaterial);
		}

		// Delete services (in reverse order)
		delete mAudioService;
		delete mRendererService;

		// Audio system is owned by AudioService if takeOwnership=true (default)
		// But we created it ourselves, so if AudioService didn't take it, clean up
		if (mAudioSystem != null && mAudioService == null)
			delete mAudioSystem;

		Console.WriteLine("Cleanup complete");
	}
}

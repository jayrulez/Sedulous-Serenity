namespace SceneUI;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Shell.Input;
using Sedulous.UI;
using Sedulous.Fonts;
using Sedulous.Drawing.Fonts;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Animation;
using Sedulous.Framework.UI;
using Sedulous.Framework.Input;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Resources;
using Sedulous.Geometry.Tooling;
using Sedulous.Resources;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Textures.Resources;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Imaging;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Profiler;

/// Scene UI sample demonstrating Sedulous.Framework.UI integration with 3D rendering.
/// Features:
/// - Screen-space overlay UI with animation controls
/// - Animated Fox model with switchable animations
class SceneUISample : Application
{
	// Asset paths
	private const StringView GLTF_REL_PATH = "samples/models/Fox/glTF/Fox.gltf";
	private const StringView GLTF_BASE_REL_PATH = "samples/models/Fox/glTF";

	// Framework subsystems
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private UISubsystem mUISubsystem;
	private Scene mScene;

	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderView mRenderView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private ForwardTransparentFeature mTransparentFeature;
	private ParticleFeature mParticleFeature;
	private SpriteFeature mSpriteFeature;
	private SkyFeature mSkyFeature;
	private DebugRenderFeature mDebugFeature;
	private GPUSkinningFeature mSkinningFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Font service
	private FontService mFontService;

	// Fox resources (deleted in OnShutdown before RenderSystem)
	private SkinnedMeshResource mFoxResource;
	private Sedulous.Materials.Resources.MaterialResource mFoxMaterialResource;

	// Materials (deleted in OnShutdown before RenderSystem)
	private MaterialInstance mFoxMaterialInstance;
	private MaterialInstance mGroundMaterialInstance;

	// Entities
	private EntityId mFoxEntity;
	private EntityId mGroundEntity;
	private EntityId mCameraEntity;
	private EntityId mSunEntity;

	// GPU texture handle for fox
	private GPUTextureHandle mFoxTextureHandle;

	// Mesh resources (deleted in OnShutdown before RenderSystem)
	private StaticMeshResource mPlaneResource;

	// Camera control
	private OrbitFlyCamera mCamera ~ delete _;

	// UI roots
	private Canvas mUIRoot ~ delete _;

	// UI elements
	private TextBlock mFpsLabel;
	private TextBlock mStatusLabel;
	private TextBlock mAnimationLabel;
	private StackPanel mAnimationButtonPanel;

	// FPS tracking
	private int mFrameCount = 0;
	private float mFpsTimer = 0;
	private int mCurrentFps = 0;
	private float mDeltaTime = 0.016f;

	// Current animation index
	private int mCurrentAnimIndex = 0;

	// Sun light control (spherical coordinates, matching FrameworkSandbox)
	private float mSunYaw = 0.5f;
	private float mSunPitch = -1.0f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
		mCamera = new .();
		mCamera.OrbitalYaw = 0.0f;
		mCamera.OrbitalPitch = 0.3f;
		mCamera.OrbitalDistance = 200.0f;
		mCamera.OrbitalTarget = .(0, 50.0f, 0);
		mCamera.MinDistance = 50.0f;
		mCamera.MaxDistance = 500.0f;
		mCamera.Update();
	}

	protected override void OnInitialize(Context context)
	{
		Console.WriteLine("=== Scene UI Sample (Framework) ===");
		Console.WriteLine("Fox Animation Demo with Screen UI\n");

		// Initialize render system first
		InitializeRenderSystem();

		// Initialize font service
		InitializeFonts();

		// Register subsystems
		RegisterSubsystems(context);
	}

	protected override void OnContextStarted()
	{
		// Initialize profiler
		Profiler.Initialize();

		// Create the main scene
		CreateMainScene();

		// Create scene objects
		CreateSceneObjects();

		// Create UI overlay
		CreateUI();

		Console.WriteLine("\n=== Initialization Complete ===");
		Console.WriteLine("Controls:");
		Console.WriteLine("  Tab: Toggle orbital/fly camera");
		Console.WriteLine("  WASD/QE: Move camera");
		Console.WriteLine("  Right-click + drag: Look around");
		Console.WriteLine("  Arrow keys: Rotate sun light");
		Console.WriteLine("  1-3: Switch animations");
		Console.WriteLine("  P: Toggle profiler");
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
		mRenderView.NearPlane = 1.0f;
		mRenderView.FarPlane = 1000.0f;

		// Register render features
		RegisterRenderFeatures();
	}

	private void RegisterRenderFeatures()
	{
		// GPU Skinning (runs first to prepare skinned vertex buffers)
		mSkinningFeature = new GPUSkinningFeature();
		if (mRenderSystem.RegisterFeature(mSkinningFeature) case .Err)
			Console.WriteLine("Warning: Failed to register GPUSkinningFeature");
		else
			Console.WriteLine("Registered: GPUSkinningFeature");

		// Depth prepass
		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		// Forward opaque
		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		// Forward transparent
		mTransparentFeature = new ForwardTransparentFeature();
		if (mRenderSystem.RegisterFeature(mTransparentFeature) case .Ok)
			Console.WriteLine("Registered: ForwardTransparentFeature");
		
		// Particles
		mParticleFeature = new ParticleFeature();
		if (mRenderSystem.RegisterFeature(mParticleFeature) case .Ok)
			Console.WriteLine("Registered: ParticleFeature");

		// Sprites
		mSpriteFeature = new SpriteFeature();
		if (mRenderSystem.RegisterFeature(mSpriteFeature) case .Ok)
			Console.WriteLine("Registered: SpriteFeature");

		// Sky
		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		// Create gradient sky
		let topColor = Color(70, 130, 200, 255);
		let horizonColor = Color(180, 210, 240, 255);
		mSkyFeature.CreateGradientSky(topColor, horizonColor, 32);

		// Debug rendering
		mDebugFeature = new DebugRenderFeature();
		mRenderSystem.RegisterFeature(mDebugFeature);

		// Final output
		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);

		Console.WriteLine("Render features registered");
	}

	private bool InitializeFonts()
	{
		Console.WriteLine("Initializing fonts...");

		mFontService = new FontService();

		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = 16;

		if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
		{
			Console.WriteLine($"Failed to load font: {fontPath}");
			return false;
		}

		Console.WriteLine("Font loaded successfully");
		return true;
	}

	private void RegisterSubsystems(Context context)
	{
		Console.WriteLine("\nRegistering subsystems...");

		// Scene subsystem
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);
		Console.WriteLine("  - SceneSubsystem");

		// Animation subsystem
		let animSubsystem = new AnimationSubsystem();
		context.RegisterSubsystem(animSubsystem);
		Console.WriteLine("  - AnimationSubsystem");

		// Render subsystem
		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);
		Console.WriteLine("  - RenderSubsystem");

		// Input subsystem
		let inputSubsystem = new InputSubsystem();
		inputSubsystem.SetInputManager(mShell.InputManager);
		context.RegisterSubsystem(inputSubsystem);
		Console.WriteLine("  - InputSubsystem");

		// UI subsystem
		mUISubsystem = new UISubsystem(mFontService);
		context.RegisterSubsystem(mUISubsystem);
		if (mUISubsystem.InitializeRendering(mDevice, .BGRA8UnormSrgb, 2, mShell, mRenderSystem) case .Ok)
			Console.WriteLine("  - UISubsystem");
		else
			Console.WriteLine("  - UISubsystem (render init FAILED)");
	}

	private void CreateMainScene()
	{
		Console.WriteLine("\nCreating main scene...");

		mScene = mSceneSubsystem.CreateScene("MainScene");
		mSceneSubsystem.SetActiveScene(mScene);

		Console.WriteLine("Scene created with modules");
	}

	private void CreateSceneObjects()
	{
		Console.WriteLine("\nCreating scene objects...");

		let renderModule = mScene.GetModule<RenderSceneModule>();
		let animModule = mScene.GetModule<AnimationSceneModule>();
		if (renderModule == null)
		{
			Console.WriteLine("ERROR: RenderSceneModule not found");
			return;
		}

		// Create ground plane
		CreateGroundPlane(renderModule);

		// Load and create fox
		LoadFoxModel(renderModule, animModule);

		// Create camera
		CreateCamera(renderModule);

		// Create sun light
		CreateSunLight(renderModule);

		Console.WriteLine("Scene objects created");
	}

	private void CreateGroundPlane(RenderSceneModule renderModule)
	{
		// Create ground mesh
		let planeMesh = StaticMesh.CreatePlane(500.0f, 500.0f, 10, 10);
		mPlaneResource = new StaticMeshResource(planeMesh, true);

		// Get default material
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Create ground material
		if (let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			mGroundMaterialInstance = new MaterialInstance(baseMaterial);
			mGroundMaterialInstance.SetColor("BaseColor", .(0.3f, 0.5f, 0.3f, 1.0f));
			mGroundMaterialInstance.SetFloat("Metallic", 0.0f);
			mGroundMaterialInstance.SetFloat("Roughness", 0.8f);
		}

		// Create entity
		mGroundEntity = mScene.CreateEntity();

		// Set mesh component - framework handles proxy creation and GPU upload
		mScene.SetComponent<MeshRendererComponent>(mGroundEntity, .Default);
		var comp = mScene.GetComponent<MeshRendererComponent>(mGroundEntity);
		comp.Mesh = ResourceHandle<StaticMeshResource>(mPlaneResource);
		comp.Material = mGroundMaterialInstance ?? defaultMaterial;

		Console.WriteLine("  Created ground plane");
	}

	private void LoadFoxModel(RenderSceneModule renderModule, AnimationSceneModule animModule)
	{
		// Always load from GLTF to get all resources including materials
		Console.WriteLine("Loading Fox model from GLTF...");

		String gltfPath = scope .();
		GetAssetPath(GLTF_REL_PATH, gltfPath);

		String basePath = scope .();
		GetAssetPath(GLTF_BASE_REL_PATH, basePath);

		let model = new Model();
		let loader = scope GltfLoader();
		if (loader.Load(gltfPath, model) == .Ok)
		{
			defer delete model;

			let imageLoader = scope SDLImageLoader();
			let importOptions = new ModelImportOptions();
			importOptions.BasePath.Set(basePath);
			importOptions.Flags = .SkinnedMeshes | .Animations | .Materials | .Textures;

			let importer = scope ModelImporter(importOptions, imageLoader);
			let result = importer.Import(model);
			defer delete result;

			if (result.SkinnedMeshes.Count > 0)
			{
				mFoxResource = result.SkinnedMeshes[0];
				result.SkinnedMeshes.RemoveAt(0); // Take ownership

				Console.WriteLine($"  Imported: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton?.BoneCount ?? 0} bones, {mFoxResource.Animations?.Count ?? 0} animations");
			}

			// Get material resource if available
			if (result.NewMaterials.Count > 0)
			{
				mFoxMaterialResource = result.NewMaterials[0];
				result.NewMaterials.RemoveAt(0);
				Console.WriteLine($"  Imported material: {mFoxMaterialResource.Name}");
			}
		}
		else
		{
			Console.WriteLine("ERROR: Failed to load Fox GLTF");
			return;
		}

		if (mFoxResource == null)
			return;

		// Get default material as fallback
		let material = mFoxMaterialResource?.Material ?? mRenderSystem.MaterialSystem?.DefaultMaterial;

		// Create fox material instance
		// If we have imported material, use its properties; otherwise use defaults
		if (let foxMaterial = material)
		{
			mFoxMaterialInstance = new MaterialInstance(foxMaterial);

			// Copy material properties from imported material if available
			/*if (mFoxMaterialResource?.Material != null)
			{
				let importedMat = mFoxMaterialResource.Material;

				// Try to get BaseColor from imported material's uniform data
				// The imported material stores values in its DefaultUniformData
				// For now, set reasonable defaults for a textured model
				mFoxMaterialInstance.SetColor("BaseColor", .(1.0f, 1.0f, 1.0f, 1.0f)); // White to not tint texture
				mFoxMaterialInstance.SetFloat("Metallic", 0.0f);
				mFoxMaterialInstance.SetFloat("Roughness", 0.5f);
			}
			else
			{
				// Fallback to orange fox color
				mFoxMaterialInstance.SetColor("BaseColor", .(1.0f, 0.6f, 0.2f, 1.0f));
				mFoxMaterialInstance.SetFloat("Metallic", 0.0f);
				mFoxMaterialInstance.SetFloat("Roughness", 0.7f);
			}*/
		}

		// Load textures from imported material
		if (mFoxMaterialResource != null)
		{
			// Try to load albedo/base color texture
			LoadAndSetTexture("AlbedoMap", basePath);
			LoadAndSetTexture("BaseColorMap", basePath);
		}

		// Create entity
		mFoxEntity = mScene.CreateEntity();

		// Set skinned mesh component - framework handles proxy creation and GPU upload
		mScene.SetComponent<SkinnedMeshRendererComponent>(mFoxEntity, .Default);
		var comp = mScene.GetComponent<SkinnedMeshRendererComponent>(mFoxEntity);
		comp.Mesh = ResourceHandle<SkinnedMeshResource>(mFoxResource);
		comp.Material = mFoxMaterialInstance ?? mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Setup animation
		if (animModule != null && mFoxResource.Skeleton != null)
		{
			let player = animModule.SetupAnimation(mFoxEntity, mFoxResource.Skeleton);
			if (player != null && mFoxResource.Animations != null && mFoxResource.Animations.Count > 0)
			{
				// Play first animation
				animModule.Play(mFoxEntity, mFoxResource.Animations[0], true);
				Console.WriteLine("  Playing animation 0");
			}
		}

		Console.WriteLine("  Created Fox entity");
	}

	private void LoadAndSetTexture(StringView slotName, StringView basePath)
	{
		if (mFoxMaterialResource == null || mFoxMaterialInstance == null)
			return;

		let texPath = mFoxMaterialResource.GetTexturePath(slotName);
		if (texPath.IsEmpty)
			return;

		String fullTexPath = scope .();
		fullTexPath.Append(basePath);
		fullTexPath.Append("/");
		fullTexPath.Append(texPath);

		let imageLoader = scope SDLImageLoader();
		if (imageLoader.LoadFromFile(fullTexPath) case .Ok(let loadInfo))
		{
			defer { var li = loadInfo; li.Dispose(); }

			// Convert to texture data
			let format = ConvertPixelFormat(loadInfo.Format);
			let texData = TextureData.Create2D(loadInfo.Data.Ptr, (uint64)loadInfo.Data.Count, loadInfo.Width, loadInfo.Height, format);

			if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let texHandle))
			{
				mFoxTextureHandle = texHandle;
				let view = mRenderSystem.ResourceManager.GetTextureView(texHandle);
				if (view != null)
				{
					mFoxMaterialInstance.SetTexture("AlbedoMap", view);
					Console.WriteLine($"  Loaded texture '{slotName}': {texPath}");
				}
			}
		}
	}

	private static TextureFormat ConvertPixelFormat(Sedulous.Imaging.Image.PixelFormat format)
	{
		switch (format)
		{
		case .R8:       return .R8Unorm;
		case .RG8:      return .RG8Unorm;
		case .RGB8:     return .RGBA8Unorm;
		case .RGBA8:    return .RGBA8Unorm;
		case .BGR8:     return .BGRA8Unorm;
		case .BGRA8:    return .BGRA8Unorm;
		case .R16F:     return .R16Float;
		case .RG16F:    return .RG16Float;
		case .RGB16F:   return .RGBA16Float;
		case .RGBA16F:  return .RGBA16Float;
		case .R32F:     return .R32Float;
		case .RG32F:    return .RG32Float;
		case .RGB32F:   return .RGBA32Float;
		case .RGBA32F:  return .RGBA32Float;
		default:        return .RGBA8Unorm;
		}
	}

	private void CreateCamera(RenderSceneModule renderModule)
	{
		mCameraEntity = mScene.CreateEntity();

		let aspectRatio = (float)mSwapChain.Width / mSwapChain.Height;
		renderModule.CreatePerspectiveCamera(mCameraEntity, Math.PI_f / 4.0f, aspectRatio, 1.0f, 1000.0f);
		renderModule.SetMainCamera(mCameraEntity);

		// Update camera position
		var transform = mScene.GetTransform(mCameraEntity);
		transform.Position = mCamera.Position;
		mScene.SetTransform(mCameraEntity, transform);

		Console.WriteLine("  Created camera entity");
	}

	private void CreateSunLight(RenderSceneModule renderModule)
	{
		mSunEntity = mScene.CreateEntity();

		// Direction computed from mSunYaw/mSunPitch (same as FrameworkSandbox)
		let sunHandle = renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.98f, 0.95f), 2.0f);
		if (sunHandle.IsValid)
			UpdateSunLight();

		// Enable shadow casting on the sun
		if (let proxy = renderModule.GetLightProxy(mSunEntity))
			proxy.CastsShadows = true;

		Console.WriteLine("  Created sun light entity");
	}

	private void UpdateSunLight()
	{
		// Update entity transform rotation so RenderSceneModule syncs the direction
		var transform = mScene.GetTransform(mSunEntity);
		transform.Rotation = Quaternion.CreateFromYawPitchRoll(mSunYaw, -mSunPitch, 0);
		mScene.SetTransform(mSunEntity, transform);

		// Update procedural sky sun direction (opposite of light travel direction)
		if (mSkyFeature != null)
		{
			float x = Math.Cos(mSunPitch) * Math.Sin(mSunYaw);
			float y = Math.Sin(mSunPitch);
			float z = Math.Cos(mSunPitch) * Math.Cos(mSunYaw);
			mSkyFeature.SkyParams.SunDirection = Vector3.Normalize(.(-x, -y, -z));
		}
	}

	private void DrawDebugGizmos()
	{
		if (mDebugFeature == null)
			return;

		// Draw directional light direction
		let renderModule = mScene?.GetModule<RenderSceneModule>();
		if (renderModule != null)
		{
			if (let light = renderModule.GetLightProxy(mSunEntity))
			{
				Vector3 sunOrigin = .(0, 80, 0);
				Vector3 sunEnd = sunOrigin + light.Direction * 30.0f;
				mDebugFeature.AddArrow(sunOrigin, sunEnd, Color.Yellow, 2.0f, .Overlay);
				mDebugFeature.AddSphere(sunOrigin, 2.0f, Color.Yellow, 8, .Overlay);
			}
		}

		// Draw HUD text
		let white = Color(255, 255, 255, 255);
		mDebugFeature.AddText2D("Arrow keys: Rotate sun light", 15, mSwapChain.Height - 30, white, 1.0f);
	}

	private void CreateUI()
	{
		Console.WriteLine("\nCreating UI...");

		// Create main canvas
		mUIRoot = new Canvas();
		mUIRoot.Background = null;

		// Create info panel in top-left
		let infoPanel = new StackPanel();
		infoPanel.Orientation = .Vertical;
		infoPanel.Margin = .(10, 10, 0, 0);
		infoPanel.HorizontalAlignment = .Left;
		infoPanel.VerticalAlignment = .Top;

		// Title
		let titleLabel = new TextBlock("Fox Animation Demo");
		titleLabel.Foreground = .(1, 1, 1, 1);
		titleLabel.Margin = .(0, 0, 0, 5);
		infoPanel.AddChild(titleLabel);

		// FPS label
		mFpsLabel = new TextBlock("FPS: --");
		mFpsLabel.Foreground = .(1, 1, 0, 1);
		infoPanel.AddChild(mFpsLabel);

		// Status label
		mStatusLabel = new TextBlock("Status: Ready");
		mStatusLabel.Foreground = .(0.8f, 0.8f, 0.8f, 1);
		infoPanel.AddChild(mStatusLabel);

		// Animation label
		mAnimationLabel = new TextBlock("Animation: 0");
		mAnimationLabel.Foreground = .(0.5f, 1, 0.5f, 1);
		mAnimationLabel.Margin = .(0, 10, 0, 0);
		infoPanel.AddChild(mAnimationLabel);

		// Animation buttons (based on actual animation count)
		mAnimationButtonPanel = new StackPanel();
		mAnimationButtonPanel.Orientation = .Horizontal;
		mAnimationButtonPanel.Margin = .(0, 5, 0, 0);

		let animCount = mFoxResource?.Animations?.Count ?? 0;
		for (int i = 0; i < animCount; i++)
		{
			let btn = new Button(scope $"Anim {i}");
			btn.Margin = .(0, 0, 5, 0);
			btn.Padding = .(8, 4, 8, 4);

			let animIndex = i;
			btn.Click.Subscribe(new [=](b) => {
				PlayAnimation(animIndex);
			});

			mAnimationButtonPanel.AddChild(btn);
		}
		infoPanel.AddChild(mAnimationButtonPanel);

		mUIRoot.AddChild(infoPanel);

		// Set UI root
		mUISubsystem.UIContext.RootElement = mUIRoot;

		Console.WriteLine("UI created");
	}

	private void PlayAnimation(int index)
	{
		let animModule = mScene?.GetModule<AnimationSceneModule>();
		if (animModule != null && mFoxEntity.IsValid && mFoxResource?.Animations != null)
		{
			let animCount = mFoxResource.Animations.Count;
			if (index >= 0 && index < animCount)
			{
				animModule.Play(mFoxEntity, mFoxResource.Animations[index], true);
				mCurrentAnimIndex = index;
				mAnimationLabel.Text = scope $"Animation: {index}";
			}
		}
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		// Camera control
		mCamera.HandleInput(keyboard, mouse, mDeltaTime);

		// Update camera entity position
		if (mCameraEntity.IsValid)
		{
			var transform = mScene.GetTransform(mCameraEntity);
			transform.Position = mCamera.Position;
			let yaw = Math.Atan2(mCamera.Forward.X, mCamera.Forward.Z);
			let pitch = Math.Asin(-mCamera.Forward.Y);
			transform.Rotation = Quaternion.CreateFromYawPitchRoll(yaw, pitch, 0);
			mScene.SetTransform(mCameraEntity, transform);

			// Update camera proxy via RenderSceneModule
			let renderModule = mScene?.GetModule<RenderSceneModule>();
			if (renderModule != null)
			{
				if (let proxy = renderModule.GetCameraProxy(mCameraEntity))
				{
					proxy.Position = mCamera.Position;
					proxy.Forward = mCamera.Forward;
				}
			}
		}

		// Animation shortcuts
		if (keyboard.IsKeyPressed(.Num1) || keyboard.IsKeyPressed(.Keypad1))
			PlayAnimation(0);
		else if (keyboard.IsKeyPressed(.Num2) || keyboard.IsKeyPressed(.Keypad2))
			PlayAnimation(1);
		else if (keyboard.IsKeyPressed(.Num3) || keyboard.IsKeyPressed(.Keypad3))
			PlayAnimation(2);

		// Sun light rotation (Arrow keys)
		{
			float lightRotSpeed = 0.03f;
			bool sunChanged = false;
			if (keyboard.IsKeyDown(.Left))
			{
				mSunYaw -= lightRotSpeed;
				sunChanged = true;
			}
			if (keyboard.IsKeyDown(.Right))
			{
				mSunYaw += lightRotSpeed;
				sunChanged = true;
			}
			if (keyboard.IsKeyDown(.Up))
			{
				mSunPitch = Math.Clamp(mSunPitch + lightRotSpeed, -1.5f, -0.1f);
				sunChanged = true;
			}
			if (keyboard.IsKeyDown(.Down))
			{
				mSunPitch = Math.Clamp(mSunPitch - lightRotSpeed, -1.5f, -0.1f);
				sunChanged = true;
			}
			if (sunChanged)
				UpdateSunLight();
		}

		// Profiler toggle
		if (keyboard.IsKeyPressed(.P))
			PrintProfilerStats();

		// Exit
		if (keyboard.IsKeyPressed(.Escape))
			Exit();
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = frame.DeltaTime;

		// Update FPS
		mFrameCount++;
		mFpsTimer += frame.DeltaTime;
		if (mFpsTimer >= 1.0f)
		{
			mCurrentFps = mFrameCount;
			mFrameCount = 0;
			mFpsTimer = 0;

			if (mFpsLabel != null)
				mFpsLabel.Text = scope:: $"FPS: {mCurrentFps}";
		}
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		// Begin frame
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		// Set swapchain for final output
		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		// Set the active world from the scene's render module
		if (let renderModule = mScene?.GetModule<RenderSceneModule>())
		{
			if (let world = renderModule.World)
				mRenderSystem.SetActiveWorld(world);
		}

		// Update render view from camera
		mRenderView.CameraPosition = mCamera.Position;
		mRenderView.CameraForward = mCamera.Forward;
		mRenderView.CameraUp = .(0, 1, 0);
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;
		mRenderView.UpdateMatrices(mDevice.FlipProjectionRequired);

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

		// Draw debug gizmos
		DrawDebugGizmos();

		// Build and execute render graph
		if (mRenderSystem.BuildRenderGraph(mRenderView) case .Ok)
		{
			mRenderSystem.Execute(render.Encoder);
		}

		// Render UI overlay (after 3D scene, before present)
		if (mUISubsystem != null && mUISubsystem.IsInitialized)
		{
			mUISubsystem.RenderUI(render.Encoder, render.CurrentTextureView,
				mSwapChain.Width, mSwapChain.Height, render.Frame.FrameIndex);
		}

		// End frame
		mRenderSystem.EndFrame();

		return true;
	}

	protected override void OnResize(int32 width, int32 height)
	{
		if (mRenderView != null)
		{
			mRenderView.Width = (uint32)width;
			mRenderView.Height = (uint32)height;
		}
	}

	protected override void OnShutdown()
	{
		Console.WriteLine("\nShutting down...");

		// Wait for GPU to finish before releasing resources
		mDevice.WaitIdle();

		// Release GPU texture handle before RenderSystem cleanup
		if (mFoxTextureHandle.IsValid && mRenderSystem?.ResourceManager != null)
		{
			mRenderSystem.ResourceManager.ReleaseTexture(mFoxTextureHandle, mRenderSystem.FrameNumber);
			mFoxTextureHandle = .Invalid;
		}

		// Delete material instances before RenderSystem (they reference GPU resources)
		if (mFoxMaterialInstance != null)
		{
			delete mFoxMaterialInstance;
			mFoxMaterialInstance = null;
		}
		if (mGroundMaterialInstance != null)
		{
			delete mGroundMaterialInstance;
			mGroundMaterialInstance = null;
		}

		// Delete material resource
		if (mFoxMaterialResource != null)
		{
			delete mFoxMaterialResource;
			mFoxMaterialResource = null;
		}

		if(mFontService != null)
		{
			delete mFontService;
		}

		
		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		// Shutdown profiler
		Profiler.Shutdown();

		// Note: RenderSystem, RenderView, FontService, OrbitFlyCamera, UIRoot are
		// deleted automatically via ~ delete _ field annotations after this method returns
		// Context shutdown happens after OnShutdown, which cleans up subsystems and scenes
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
}

class Program
{
	public static int Main(String[] args)
	{
		// Create shell
		let shell = new SDL3Shell();
		defer { shell.Shutdown(); delete shell; }

		if (shell.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shell");
			return 1;
		}

		// Create Vulkan backend
		let backend = new VulkanBackend(enableValidation: true);
		defer delete backend;

		if (!backend.IsInitialized)
		{
			Console.WriteLine("Failed to initialize Vulkan backend");
			return 1;
		}

		// Enumerate adapters
		List<IAdapter> adapters = scope .();
		backend.EnumerateAdapters(adapters);

		if (adapters.Count == 0)
		{
			Console.WriteLine("No GPU adapters found");
			return 1;
		}

		Console.WriteLine("Using adapter: {0}", adapters[0].Info.Name);

		// Create device
		let device = adapters[0].CreateDevice().GetValueOrDefault();
		if (device == null)
		{
			Console.WriteLine("Failed to create device");
			return 1;
		}
		defer delete device;

		// Run sample
		let settings = ApplicationSettings()
		{
			Title = "Scene UI - Fox Animation Demo",
			Width = 1280,
			Height = 720,
			EnableDepth = true,
			PresentMode = .Mailbox,
			ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f)
		};

		let sample = scope SceneUISample(shell, device, backend);
		return sample.Run(settings);
	}
}

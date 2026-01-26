namespace SceneUI;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using SampleFramework;
using Sedulous.Drawing;
using Sedulous.UI;
using Sedulous.Drawing.Fonts;
using Sedulous.Drawing.Renderer;
using Sedulous.Engine.Core;
using Sedulous.Engine.Input;
using Sedulous.Engine.UI;
using Sedulous.Engine.Renderer;
using Sedulous.Renderer;
using Sedulous.Geometry;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Imaging;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Debug;
using Sedulous.Geometry.Tooling;
using Sedulous.Shell.SDL3;
using Sedulous.Geometry.Resources;
using Sedulous.UI.Shell;
using Sedulous.Fonts;
using Sedulous.Shaders;

/// Scene UI sample demonstrating Sedulous.Engine.UI integration with 3D rendering.
/// Features:
/// - Screen-space overlay UI with animation controls
/// - Animated Fox model with switchable animations
/// - World-space UI panel with button
class SceneUISample : RHISampleApp
{
	// Asset paths
	private const StringView CACHE_REL_DIR = "cache";
	private const StringView CACHE_REL_PATH = "cache/fox1.skinnedmesh";
	private const StringView GLTF_REL_PATH = "samples/models/Fox/glTF/Fox.gltf";
	private const StringView GLTF_BASE_REL_PATH = "samples/models/Fox/glTF";
	private const StringView TEXTURE_REL_PATH = "samples/models/Fox/glTF/Texture.png";
	private const StringView SHADER_REL_PATH = "framework/shaders";

	// Framework.Core components
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;
	private ComponentRegistry mComponentRegistry;

	// Renderer components
	private RendererService mRendererService;
	private RenderSceneComponent mRenderSceneComponent;

	// Input components
	private InputService mInputService;

	// UI components
	private UIService mUIService;
	private UISceneComponent mUIScene;

	// Services for UI
	private ShellClipboardAdapter mClipboard;
	private FontService mFontService;
	private TooltipService mTooltipService;
	private NewShaderSystem mShaderSystem;

	// Fox resources
	private SkinnedMeshResource mFoxResource ~ delete _;
	private MaterialResource mFoxMaterialResource ~ delete _;
	private GPUTextureHandle mFoxTexture = .Invalid;
	private MaterialHandle mPBRMaterial = .Invalid;
	private MaterialInstanceHandle mFoxMaterial = .Invalid;
	private MaterialInstanceHandle mGroundMaterial = .Invalid;

	// Fox entity reference
	private Entity mFoxEntity;
	private SkinnedMeshComponent mFoxMeshComponent;

	// World-space UI entity
	private Entity mWorldUIEntity;
	private UIComponent mWorldUIComponent;
	private SpriteComponent mWorldUISprite;

	// Camera entity and control
	private Entity mCameraEntity;
	private float mCameraYaw = Math.PI_f;
	private float mCameraPitch = -0.2f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 10.0f;
	private float mCameraLookSpeed = 0.003f;

	// UI elements
	private TextBlock mFpsLabel;
	private TextBlock mStatusLabel;
	private TextBlock mAnimationLabel;
	private StackPanel mAnimationButtonPanel;

	// FPS tracking
	private int mFrameCount = 0;
	private float mFpsTimer = 0;
	private int mCurrentFps = 0;


	// Click counter
	private int mClickCount = 0;
	private int mWorldClickCount = 0;

	public this() : base(.()
		{
			Title = "Scene UI - Fox Animation Demo",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.08f, 0.1f, 0.12f, 1.0f),
			EnableDepth = true
		})
	{
	}

	protected override bool OnInitialize()
	{
		// Initialize font service (needed for UI)
		if (!InitializeFonts())
			return false;

		// Create logger
		mLogger = new DebugLogger(.Information);

		// Initialize Framework.Core context
		mContext = new Context(mLogger, 4);

		// Create and register RendererService
		mRendererService = new RendererService();
		mRendererService.SetFormats(SwapChain.Format, .Depth24PlusStencil8);
		let shaderPath = GetAssetPath(SHADER_REL_PATH, .. scope .());
		if (mRendererService.Initialize(Device, shaderPath) case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}
		mContext.RegisterService<RendererService>(mRendererService);

		// Create and register InputService
		mInputService = new InputService(Shell.InputManager);
		mContext.RegisterService<InputService>(mInputService);

		// Initialize shader system for UI rendering
		mShaderSystem = new NewShaderSystem();
		let uiShaderPath = GetAssetPath("Render/shaders", .. scope .());
		if (mShaderSystem.Initialize(Device, uiShaderPath) case .Err)
		{
			Console.WriteLine("Failed to initialize shader system for UI");
			return false;
		}

		// Create and configure UIService
		mUIService = new UIService();
		mUIService.SetShaderSystem(mShaderSystem);
		ConfigureUIServices();  // Sets up font service, theme, clipboard on UIService
		let (wu, wv) = mFontService.WhitePixelUV;
		mUIService.SetAtlasTexture(mFontService.AtlasTextureView, .(wu, wv));
		mContext.RegisterService<UIService>(mUIService);

		// Start context before creating scenes (enables automatic component creation)
		mContext.Startup();

		// Create scene - components added automatically by services
		mScene = mContext.SceneManager.CreateScene("SceneUI");
		mRenderSceneComponent = mScene.GetSceneComponent<RenderSceneComponent>();
		mUIScene = mScene.GetSceneComponent<UISceneComponent>();
		mUIScene.SetViewportSize(SwapChain.Width, SwapChain.Height);
		mContext.SceneManager.SetActiveScene(mScene);

		// Register additional UI services on the scene's UIContext
		ConfigureSceneUIServices();

		// Load Fox model
		if (!LoadFoxModel())
		{
			Console.WriteLine("Failed to load Fox model");
			return false;
		}

		// Create materials
		CreateMaterials();

		// Create entities
		CreateEntities();

		// Build UI
		BuildUI();

		Console.WriteLine("Scene UI sample initialized with Fox model.");
		return true;
	}

	private bool InitializeFonts()
	{
		mFontService = new FontService(Device);

		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = 16;

		if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
		{
			Console.WriteLine(scope $"Failed to load font: {fontPath}");
			return false;
		}

		return true;
	}

	private void ConfigureUIServices()
	{
		// Configure UIService (before scene creation)
		// These services will be automatically registered on UISceneComponent.UIContext

		// Register clipboard
		mClipboard = new ShellClipboardAdapter(Shell.Clipboard);
		mUIService.SetClipboard(mClipboard);

		// Register font service
		mUIService.SetFontService(mFontService);

		// Register theme
		mUIService.SetTheme(new DarkTheme());
	}

	private void ConfigureSceneUIServices()
	{
		// Register additional services directly on UIContext (after scene creation)
		let uiContext = mUIScene.UIContext;

		// Register tooltip service
		mTooltipService = new TooltipService();
		uiContext.RegisterService<ITooltipService>(mTooltipService);
	}

	private bool LoadFoxModel()
	{
		let cachePath = GetAssetPath(CACHE_REL_PATH, .. scope .());
		let gltfPath = GetAssetPath(GLTF_REL_PATH, .. scope .());
		let gltfBasePath = GetAssetPath(GLTF_BASE_REL_PATH, .. scope .());
		let cacheDir = GetAssetPath(CACHE_REL_DIR, .. scope .());

		// Try to load from cache first
		if (File.Exists(cachePath))
		{
			if (ResourceSerializer.LoadSkinnedMeshBundle(cachePath) case .Ok(let resource))
			{
				mFoxResource = resource;
				Console.WriteLine($"Fox loaded from cache: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.AnimationCount} animations");
				return true;
			}
		}

		// Import from GLTF
		let foxModel = new Model();
		defer delete foxModel;

		let loader = scope GltfLoader();
		if (loader.Load(gltfPath, foxModel) != .Ok)
		{
			Console.WriteLine("Failed to load Fox GLTF");
			return false;
		}

		let importOptions = new ModelImportOptions();
		importOptions.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Textures | .Materials;
		importOptions.BasePath.Set(gltfBasePath);

		let imageLoader = scope SDLImageLoader();
		let importer = scope ModelImporter(importOptions, imageLoader);
		let importResult = importer.Import(foxModel);
		defer delete importResult;

		if (!importResult.Success || importResult.SkinnedMeshes.Count == 0)
		{
			Console.WriteLine("Failed to import Fox model");
			return false;
		}

		// Save to cache
		if (!Directory.Exists(cacheDir))
			Directory.CreateDirectory(cacheDir);
		ResourceSerializer.SaveImportResult(importResult, cacheDir);

		mFoxResource = importResult.TakeSkinnedMesh(0);
		if (importResult.Materials.Count > 0)
		{
			mFoxMaterialResource = importResult.Materials[0];
			importResult.Materials.RemoveAt(0);
		}

		Console.WriteLine($"Fox imported: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.AnimationCount} animations");
		return true;
	}

	private void CreateMaterials()
	{
		let materialSystem = mRendererService.MaterialSystem;
		if (materialSystem == null) return;

		// Create PBR material template
		let pbrMaterial = Material.CreatePBR("PBRMaterial");
		mPBRMaterial = materialSystem.RegisterMaterial(pbrMaterial);

		// Create fox material instance
		mFoxMaterial = materialSystem.CreateInstance(mPBRMaterial);
		if (mFoxMaterial.IsValid)
		{
			let inst = materialSystem.GetInstance(mFoxMaterial);
			if (inst != null)
			{
				if (mFoxMaterialResource != null)
				{
					inst.SetFloat4("baseColor", mFoxMaterialResource.BaseColor);
					inst.SetFloat("metallic", mFoxMaterialResource.Metallic);
					inst.SetFloat("roughness", mFoxMaterialResource.Roughness);
					inst.SetFloat("ao", mFoxMaterialResource.AO);
					inst.SetFloat4("emissive", mFoxMaterialResource.Emissive);

					// Load texture
					if (mFoxMaterialResource.HasTexture("albedoMap"))
					{
						let textureName = mFoxMaterialResource.GetTexture("albedoMap");
						let cachedTexturePath = GetAssetPath(scope $"{CACHE_REL_DIR}/{textureName}.texture", .. scope .());
						let originalTexturePath = GetAssetPath(scope $"{GLTF_BASE_REL_PATH}/{textureName}", .. scope .());

						if (File.Exists(cachedTexturePath))
						{
							if (ResourceSerializer.LoadTexture(cachedTexturePath) case .Ok(let texResource))
							{
								let img = texResource.Image;
								mFoxTexture = mRendererService.ResourceManager.CreateTextureFromData(
									img.Width, img.Height, .RGBA8Unorm, img.Data);
								delete texResource;
								if (mFoxTexture.IsValid)
									inst.SetTexture("albedoMap", mFoxTexture);
							}
						}
						else
						{
							let imageLoader = scope SDLImageLoader();
							if (imageLoader.LoadFromFile(originalTexturePath) case .Ok(var loadInfo))
							{
								defer loadInfo.Dispose();
								mFoxTexture = mRendererService.ResourceManager.CreateTextureFromData(
									loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .(loadInfo.Data.Ptr, loadInfo.Data.Count));
								if (mFoxTexture.IsValid)
									inst.SetTexture("albedoMap", mFoxTexture);
							}
						}
					}
				}
				else
				{
					// Default values
					inst.SetFloat4("baseColor", .(1.0f, 1.0f, 1.0f, 1.0f));
					inst.SetFloat("metallic", 0.0f);
					inst.SetFloat("roughness", 0.6f);
					inst.SetFloat("ao", 1.0f);
					inst.SetFloat4("emissive", .(0, 0, 0, 1));

					// Load texture from original path
					let originalTexturePath = GetAssetPath(TEXTURE_REL_PATH, .. scope .());
					let imageLoader = scope SDLImageLoader();
					if (imageLoader.LoadFromFile(originalTexturePath) case .Ok(var loadInfo))
					{
						defer loadInfo.Dispose();
						mFoxTexture = mRendererService.ResourceManager.CreateTextureFromData(
							loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .(loadInfo.Data.Ptr, loadInfo.Data.Count));
						if (mFoxTexture.IsValid)
							inst.SetTexture("albedoMap", mFoxTexture);
					}
				}
				materialSystem.UploadInstance(mFoxMaterial);
			}
		}

		// Create ground material
		mGroundMaterial = materialSystem.CreateInstance(mPBRMaterial);
		if (mGroundMaterial.IsValid)
		{
			let inst = materialSystem.GetInstance(mGroundMaterial);
			if (inst != null)
			{
				inst.SetFloat4("baseColor", .(0.3f, 0.3f, 0.3f, 1.0f));
				inst.SetFloat("metallic", 0.0f);
				inst.SetFloat("roughness", 0.9f);
				inst.SetFloat("ao", 1.0f);
				inst.SetFloat4("emissive", .(0, 0, 0, 1));
				materialSystem.UploadInstance(mGroundMaterial);
			}
		}
	}

	private void CreateEntities()
	{
		// Create cube mesh for ground
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		defer delete cubeMesh;

		// Create ground plane
		{
			let groundEntity = mScene.CreateEntity("Ground");
			groundEntity.Transform.SetPosition(.(0, -1.5f, 0));
			groundEntity.Transform.SetScale(.(30.0f, 0.2f, 30.0f));

			let staticMeshComponent = new StaticMeshComponent();
			groundEntity.AddComponent(staticMeshComponent);
			staticMeshComponent.SetMesh(cubeMesh);
			staticMeshComponent.SetMaterialInstance(0, mGroundMaterial);
		}

		// Create directional light
		{
			let sunLight = mScene.CreateEntity("SunLight");
			sunLight.Transform.LookAt(Vector3.Normalize(.(0.5f, -0.7f, 0.3f)));

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.98f, 0.9f), 2.0f, true);
			sunLight.AddComponent(lightComp);
		}

		// Create camera
		{
			mCameraEntity = mScene.CreateEntity("MainCamera");
			mCameraEntity.Transform.SetPosition(.(0, 3, 8));
			UpdateCameraDirection();

			let cameraComp = new CameraComponent(Math.PI_f / 4.0f, 0.1f, 500.0f, true);
			cameraComp.UseReverseZ = false;
			cameraComp.SetViewport(SwapChain.Width, SwapChain.Height);
			mCameraEntity.AddComponent(cameraComp);
		}

		// Create fox entity
		if (mFoxResource != null)
		{
			mFoxEntity = mScene.CreateEntity("Fox");
			mFoxEntity.Transform.SetPosition(.(0, -1.4f, 0));
			mFoxEntity.Transform.SetScale(Vector3(0.04f));
			mFoxEntity.Transform.SetRotation(Quaternion.CreateFromYawPitchRoll(Math.PI_f, 0, 0));

			mFoxMeshComponent = new SkinnedMeshComponent();
			mFoxEntity.AddComponent(mFoxMeshComponent);

			if (mFoxResource.Skeleton != null)
				mFoxMeshComponent.SetSkeleton(mFoxResource.Skeleton, false);

			for (let clip in mFoxResource.Animations)
				mFoxMeshComponent.AddAnimationClip(clip);

			mFoxMeshComponent.SetMesh(mFoxResource.Mesh);
			mFoxMeshComponent.SetMaterial(mFoxMaterial);

			// Start with first animation
			if (mFoxMeshComponent.AnimationClips.Count > 0)
				mFoxMeshComponent.PlayAnimation(0, true);
		}

		// Create world-space UI entity with sprite for display
		{
			mWorldUIEntity = mScene.CreateEntity("WorldUI");
			mWorldUIEntity.Transform.SetPosition(.(3.0f, 1.0f, 0));

			mWorldUIComponent = new UIComponent(256, 128);
			mWorldUIComponent.WorldSize = .(2.0f, 1.0f);
			mWorldUIComponent.Orientation = .Billboard;
			mWorldUIEntity.AddComponent(mWorldUIComponent);

			// Initialize world UI rendering
			if (mWorldUIComponent.InitializeRendering(Device, SwapChain.Format, MAX_FRAMES_IN_FLIGHT, mShaderSystem) case .Err)
			{
				Console.WriteLine("Failed to initialize world UI rendering");
			}
			else
			{
				// Set white pixel UV for solid color rendering
				let (wwu, wwv) = mFontService.WhitePixelUV;
				mWorldUIComponent.SetWhitePixelUV(.(wwu, wwv));

				// Register shared font service and theme for world UI context
				let worldUIContext = mWorldUIComponent.UIContext;
				worldUIContext.RegisterService<IFontService>(mFontService);
				let worldTheme = new DarkTheme();
				worldUIContext.RegisterService<ITheme>(worldTheme);

				// Build world-space UI
				BuildWorldUI();

				// Create sprite to display the UI texture in 3D
				mWorldUISprite = new SpriteComponent(mWorldUIComponent.WorldSize);
				mWorldUISprite.Texture = mWorldUIComponent.RenderTextureView;
				mWorldUIEntity.AddComponent(mWorldUISprite);
			}
		}
	}

	private void BuildUI()
	{
		// Create root layout - DockPanel with side panel
		let root = new DockPanel();
		root.Background = Color.Transparent;

		// === Right Side Panel (Controls) ===
		let sidePanel = new Border();
		sidePanel.Background = Color(25, 28, 32, 230);
		sidePanel.Width = 280;
		sidePanel.Padding = Thickness(15, 10, 15, 10);
		root.SetDock(sidePanel, .Right);

		let sidePanelContent = new StackPanel();
		sidePanelContent.Orientation = .Vertical;
		sidePanelContent.Spacing = 15;
		sidePanel.Child = sidePanelContent;

		// Header
		{
			let header = new StackPanel();
			header.Orientation = .Horizontal;
			header.Spacing = 10;

			let title = new TextBlock();
			title.Text = "Fox Animation";
			title.Foreground = Color(220, 225, 230);
			header.AddChild(title);

			mFpsLabel = new TextBlock();
			mFpsLabel.Text = "FPS: --";
			mFpsLabel.Foreground = Color(150, 200, 150);
			mFpsLabel.HorizontalAlignment = .Right;
			header.AddChild(mFpsLabel);

			sidePanelContent.AddChild(header);
		}

		// Current animation label
		{
			mAnimationLabel = new TextBlock();
			mAnimationLabel.Text = "Animation: ---";
			mAnimationLabel.Foreground = Color(180, 185, 190);
			sidePanelContent.AddChild(mAnimationLabel);
		}

		// Animation buttons section
		{
			let sectionLabel = new TextBlock();
			sectionLabel.Text = "Animations:";
			sectionLabel.Foreground = Color(100, 180, 255);
			sidePanelContent.AddChild(sectionLabel);

			mAnimationButtonPanel = new StackPanel();
			mAnimationButtonPanel.Orientation = .Vertical;
			mAnimationButtonPanel.Spacing = 5;
			mAnimationButtonPanel.Margin = Thickness(10, 0, 0, 0);
			sidePanelContent.AddChild(mAnimationButtonPanel);

			// Create buttons for each animation
			if (mFoxMeshComponent != null)
			{
				for (int i = 0; i < mFoxMeshComponent.AnimationClips.Count; i++)
				{
					let clip = mFoxMeshComponent.AnimationClips[i];
					let animIndex = (int32)i;

					let btn = new Button();
					btn.ContentText = clip.Name;
					btn.Padding = Thickness(10, 6, 10, 6);
					btn.HorizontalAlignment = .Stretch;
					btn.Click.Subscribe(new [=](sender) => {
						PlayAnimation(animIndex);
					});
					mAnimationButtonPanel.AddChild(btn);
				}
			}
		}

		// Playback controls
		{
			let controlsLabel = new TextBlock();
			controlsLabel.Text = "Playback:";
			controlsLabel.Foreground = Color(100, 180, 255);
			controlsLabel.Margin = Thickness(0, 10, 0, 0);
			sidePanelContent.AddChild(controlsLabel);

			let controlsRow = new StackPanel();
			controlsRow.Orientation = .Horizontal;
			controlsRow.Spacing = 5;
			controlsRow.Margin = Thickness(10, 0, 0, 0);

			let pauseBtn = new Button();
			pauseBtn.ContentText = "Pause";
			pauseBtn.Padding = Thickness(10, 6, 10, 6);
			pauseBtn.Click.Subscribe(new (sender) => {
				mFoxMeshComponent?.PauseAnimation();
				mStatusLabel.Text = "Animation paused";
			});
			controlsRow.AddChild(pauseBtn);

			let resumeBtn = new Button();
			resumeBtn.ContentText = "Resume";
			resumeBtn.Padding = Thickness(10, 6, 10, 6);
			resumeBtn.Click.Subscribe(new (sender) => {
				mFoxMeshComponent?.ResumeAnimation();
				mStatusLabel.Text = "Animation resumed";
			});
			controlsRow.AddChild(resumeBtn);

			sidePanelContent.AddChild(controlsRow);
		}

		// Status bar at bottom of side panel
		{
			mStatusLabel = new TextBlock();
			mStatusLabel.Text = "Click animation buttons to switch";
			mStatusLabel.Foreground = Color(140, 145, 150);
			mStatusLabel.Margin = Thickness(0, 15, 0, 0);
			sidePanelContent.AddChild(mStatusLabel);
		}

		// Instructions
		{
			let instructions = new TextBlock();
			instructions.Text = "Controls:\nWASD - Move camera\nQ/E - Up/Down\nTab - Capture mouse\nMouse - Look around";
			instructions.Foreground = Color(100, 105, 110);
			instructions.Margin = Thickness(0, 10, 0, 0);
			sidePanelContent.AddChild(instructions);
		}

		root.AddChild(sidePanel);

		// Set root element via UISceneComponent
		mUIScene.RootElement = root;
	}

	private void BuildWorldUI()
	{
		let root = new Border();
		root.Background = Color(40, 45, 55, 220);
		root.Padding = Thickness(10);
		root.CornerRadius = 8;

		let content = new StackPanel();
		content.Orientation = .Vertical;
		content.Spacing = 8;
		content.HorizontalAlignment = .Center;
		root.Child = content;

		let label = new TextBlock();
		label.Text = "World UI";
		label.Foreground = Color(200, 205, 210);
		label.HorizontalAlignment = .Center;
		content.AddChild(label);

		let clickLabel = new TextBlock();
		clickLabel.Text = "Clicks: 0";
		clickLabel.Foreground = Color(150, 200, 150);
		clickLabel.HorizontalAlignment = .Center;
		content.AddChild(clickLabel);

		let btn = new Button();
		btn.ContentText = "Click Me!";
		btn.Padding = Thickness(15, 8, 15, 8);
		btn.HorizontalAlignment = .Center;
		btn.Click.Subscribe(new [=](sender) => {
			mWorldClickCount++;
			clickLabel.Text = scope:: $"Clicks: {mWorldClickCount}";
		});
		content.AddChild(btn);

		mWorldUIComponent.RootElement = root;
	}

	private void PlayAnimation(int32 index)
	{
		if (mFoxMeshComponent == null) return;

		mFoxMeshComponent.PlayAnimation(index, true);

		let clip = mFoxMeshComponent.GetAnimationClip(index);
		if (clip != null)
		{
			mAnimationLabel.Text = scope:: $"Animation: {clip.Name}";
			mStatusLabel.Text = scope:: $"Playing: {clip.Name}";
		}
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		mUIScene?.SetViewportSize(width, height);
		if (let cameraComp = mCameraEntity?.GetComponent<CameraComponent>())
			cameraComp.SetViewport(width, height);
	}

	protected override void OnInput()
	{
		if (mCameraEntity == null)
			return;

		let keyboard = Shell.InputManager.Keyboard;
		let mouse = Shell.InputManager.Mouse;

		// Toggle mouse capture
		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		// Mouse look (when captured or right-click held)
		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mCameraYaw -= mouse.DeltaX * mCameraLookSpeed;
			mCameraPitch -= mouse.DeltaY * mCameraLookSpeed;
			mCameraPitch = Math.Clamp(mCameraPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
			UpdateCameraDirection();
		}

		// WASD movement
		let forward = mCameraEntity.Transform.Forward;
		let right = mCameraEntity.Transform.Right;
		let up = Vector3(0, 1, 0);
		float speed = mCameraMoveSpeed * DeltaTime;

		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
			speed *= 2.0f;

		var pos = mCameraEntity.Transform.Position;
		if (keyboard.IsKeyDown(.W)) pos = pos + forward * speed;
		if (keyboard.IsKeyDown(.S)) pos = pos - forward * speed;
		if (keyboard.IsKeyDown(.A)) pos = pos - right * speed;
		if (keyboard.IsKeyDown(.D)) pos = pos + right * speed;
		if (keyboard.IsKeyDown(.Q)) pos = pos - up * speed;
		if (keyboard.IsKeyDown(.E)) pos = pos + up * speed;
		mCameraEntity.Transform.SetPosition(pos);
	}

	private void UpdateCameraDirection()
	{
		if (mCameraEntity == null)
			return;

		float cosP = Math.Cos(mCameraPitch);
		let forward = Vector3.Normalize(.(
			Math.Sin(mCameraYaw) * cosP,
			Math.Sin(mCameraPitch),
			Math.Cos(mCameraYaw) * cosP
		));

		let target = mCameraEntity.Transform.Position + forward;
		mCameraEntity.Transform.LookAt(target);
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// FPS calculation
		mFrameCount++;
		mFpsTimer += deltaTime;
		if (mFpsTimer >= 1.0f)
		{
			mCurrentFps = mFrameCount;
			mFrameCount = 0;
			mFpsTimer -= 1.0f;

			if (mFpsLabel != null)
				mFpsLabel.Text = scope:: $"FPS: {mCurrentFps}";
		}

		// Update current animation label
		if (mAnimationLabel != null && mFoxMeshComponent != null)
		{
			let animName = mFoxMeshComponent.CurrentAnimationName;
			if (!animName.IsEmpty)
				mAnimationLabel.Text = scope:: $"Animation: {animName}";
		}

		// Update context (handles scene, components, and automatic UI input routing)
		mContext.Update(deltaTime);

		// Update tooltip system
		mTooltipService?.Update(mUIScene.UIContext, deltaTime);
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		// Begin render graph frame - this adds shadow cascades and Scene3D passes
		// Note: World UI PrepareGPU is called automatically by UISceneComponent.AddUIPass
		mRendererService.BeginFrame(
			(uint32)frameIndex, DeltaTime, TotalTime,
			SwapChain.CurrentTexture, SwapChain.CurrentTextureView,
			mDepthTexture, DepthTextureView);

		// Add world UI render-to-texture passes (before Scene3D which samples them)
		mUIScene.AddWorldUIPasses(mRendererService.RenderGraph, frameIndex);

		// Add UI overlay pass to the render graph
		mUIScene.AddUIPass(mRendererService.RenderGraph, mRendererService.SwapChainHandle, frameIndex);
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Execute all render graph passes (world UI, shadow cascades, Scene3D, UI overlay)
		mRendererService.ExecuteFrame(encoder);

		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - OnRenderFrame handles rendering
	}

	protected override void OnCleanup()
	{
		Console.WriteLine("SceneUISample.OnCleanup() called");

		// Clean up UI services BEFORE context shutdown (scene components get deleted during shutdown)
		if (mUIScene?.UIContext != null)
		{
			if (mUIScene.UIContext.GetService<ITheme>() case .Ok(let theme))
				delete theme;
		}
		if (mTooltipService != null) { delete mTooltipService; mTooltipService = null; }
		if (mClipboard != null) { delete mClipboard; mClipboard = null; }

		// Clean up world UI services (font service is shared, only delete theme)
		if (mWorldUIComponent?.UIContext != null)
		{
			if (mWorldUIComponent.UIContext.GetService<ITheme>() case .Ok(let theme))
				delete theme;
		}

		// Shutdown context (deletes scene components including mUIScene and mWorldUIComponent)
		mContext?.Shutdown();

		delete mUIService;
		delete mInputService;

		Device.WaitIdle();

		// Clean up materials
		if (mRendererService?.MaterialSystem != null)
		{
			let materialSystem = mRendererService.MaterialSystem;
			if (mFoxMaterial.IsValid)
				materialSystem.ReleaseInstance(mFoxMaterial);
			if (mGroundMaterial.IsValid)
				materialSystem.ReleaseInstance(mGroundMaterial);
			if (mPBRMaterial.IsValid)
				materialSystem.ReleaseMaterial(mPBRMaterial);
		}

		// Clean up fox texture
		if (mFoxTexture.IsValid && mRendererService?.ResourceManager != null)
			mRendererService.ResourceManager.ReleaseTexture(mFoxTexture);

		delete mRendererService;

		// Clean up font service (owns GPU atlas texture resources)
		if (mFontService != null) { delete mFontService; mFontService = null; }

		// Clean up shader system
		if (mShaderSystem != null)
		{
			mShaderSystem.Dispose();
			delete mShaderSystem;
			mShaderSystem = null;
		}

		Console.WriteLine("Scene UI sample cleaned up.");
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let sample = scope SceneUISample();
		return sample.Run();
	}
}

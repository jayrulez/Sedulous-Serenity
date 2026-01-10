namespace RendererMultiView;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Renderer;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Debug;
using SampleFramework;

/// Demonstrates multi-view rendering with split-screen cameras.
///
/// This sample shows how to render the same scene from multiple viewpoints
/// simultaneously, useful for:
/// - Split-screen multiplayer games
/// - Picture-in-picture displays
/// - Security camera views
/// - Debug/editor cameras
class MultiViewSample : RHISampleApp
{
	// Grid configuration
	private const int32 GRID_SIZE = 5;  // 5x5 = 25 cubes

	// Framework.Core components
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;  // Owned by SceneManager

	// Renderer components
	private RendererService mRendererService;
	private RenderSceneComponent mRenderSceneComponent;

	// Material handles
	private MaterialHandle mPBRMaterial = .Invalid;
	private MaterialInstanceHandle mGroundMaterial = .Invalid;
	private MaterialInstanceHandle[8] mCubeMaterials;

	// Camera entities
	private Entity mPlayerCamera;    // Player-controlled camera (left view)
	private Entity mOrbitCamera;     // Auto-orbiting camera (right view)
	private ProxyHandle mPlayerCameraProxy = .Invalid;
	private ProxyHandle mOrbitCameraProxy = .Invalid;

	// Camera control state
	private float mCameraYaw = Math.PI_f;
	private float mCameraPitch = -0.3f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 15.0f;
	private float mCameraLookSpeed = 0.003f;

	// Orbit camera state
	private float mOrbitAngle = 0.0f;
	private float mOrbitRadius = 20.0f;
	private float mOrbitHeight = 10.0f;
	private float mOrbitSpeed = 0.5f;

	// Light entity
	private Entity mSunLightEntity;

	// Current frame index
	private int32 mCurrentFrameIndex = 0;

	// Split screen mode
	private bool mHorizontalSplit = true;  // true = side-by-side, false = top-bottom

	public this() : base(.()
	{
		Title = "Multi-View Rendering (Split Screen)",
		Width = 1280,
		Height = 720,
		ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f),
		EnableDepth = true
	})
	{
	}

	protected override bool OnInitialize()
	{
		// Create logger
		mLogger = new DebugLogger(.Information);

		// Initialize Framework.Core context
		mContext = new Context(mLogger, 4);

		// Create and register RendererService
		mRendererService = new RendererService();
		mRendererService.SetFormats(SwapChain.Format, .Depth24PlusStencil8);
		let shaderPath = GetAssetPath("framework/shaders", .. scope .());
		if (mRendererService.Initialize(Device, shaderPath) case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}
		mContext.RegisterService<RendererService>(mRendererService);

		// Create scene with RenderSceneComponent
		mScene = mContext.SceneManager.CreateScene("MainScene");
		mRenderSceneComponent = mScene.AddSceneComponent(new RenderSceneComponent(mRendererService));

		// Initialize rendering
		if (mRenderSceneComponent.InitializeRendering(SwapChain.Format, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("Failed to initialize scene rendering");
			return false;
		}

		// Create materials
		CreateMaterials();

		// Create scene content
		CreateEntities();

		// Set active scene and start
		mContext.SceneManager.SetActiveScene(mScene);
		mContext.Startup();

		Console.WriteLine("Multi-View Rendering Sample initialized");
		Console.WriteLine($"Created {GRID_SIZE * GRID_SIZE} cubes, 2 cameras (split-screen)");
		Console.WriteLine("");
		Console.WriteLine("Controls:");
		Console.WriteLine("  WASD     = Move player camera");
		Console.WriteLine("  QE       = Up/Down");
		Console.WriteLine("  Tab      = Toggle mouse capture");
		Console.WriteLine("  Shift    = Fast movement");
		Console.WriteLine("  Space    = Toggle horizontal/vertical split");
		Console.WriteLine("  +/-      = Orbit speed");

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

		// Create ground material
		mGroundMaterial = materialSystem.CreateInstance(mPBRMaterial);
		if (mGroundMaterial.IsValid)
		{
			let instance = materialSystem.GetInstance(mGroundMaterial);
			if (instance != null)
			{
				instance.SetFloat4("baseColor", .(0.3f, 0.3f, 0.35f, 1.0f));
				instance.SetFloat("metallic", 0.0f);
				instance.SetFloat("roughness", 0.9f);
				instance.SetFloat("ao", 1.0f);
				instance.SetFloat4("emissive", .(0, 0, 0, 1));
				materialSystem.UploadInstance(mGroundMaterial);
			}
		}

		// Create cube materials with different colors
		Vector4[8] cubeColors = .(
			.(1.0f, 0.3f, 0.3f, 1.0f),  // Red
			.(0.3f, 1.0f, 0.3f, 1.0f),  // Green
			.(0.3f, 0.3f, 1.0f, 1.0f),  // Blue
			.(1.0f, 1.0f, 0.3f, 1.0f),  // Yellow
			.(1.0f, 0.3f, 1.0f, 1.0f),  // Magenta
			.(0.3f, 1.0f, 1.0f, 1.0f),  // Cyan
			.(1.0f, 0.6f, 0.3f, 1.0f),  // Orange
			.(0.6f, 0.3f, 1.0f, 1.0f)   // Purple
		);

		for (int32 i = 0; i < 8; i++)
		{
			mCubeMaterials[i] = materialSystem.CreateInstance(mPBRMaterial);
			if (mCubeMaterials[i].IsValid)
			{
				let instance = materialSystem.GetInstance(mCubeMaterials[i]);
				if (instance != null)
				{
					instance.SetFloat4("baseColor", cubeColors[i]);
					instance.SetFloat("metallic", 0.2f);
					instance.SetFloat("roughness", 0.5f);
					instance.SetFloat("ao", 1.0f);
					instance.SetFloat4("emissive", .(0, 0, 0, 1));
					materialSystem.UploadInstance(mCubeMaterials[i]);
				}
			}
		}
	}

	private void CreateEntities()
	{
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		defer delete cubeMesh;

		// Create ground plane
		{
			let groundEntity = mScene.CreateEntity("Ground");
			groundEntity.Transform.SetPosition(.(0, -0.5f, 0));
			groundEntity.Transform.SetScale(.(40.0f, 1.0f, 40.0f));

			let meshComponent = new StaticMeshComponent();
			groundEntity.AddComponent(meshComponent);
			meshComponent.SetMesh(cubeMesh);
			meshComponent.SetMaterialInstance(0, mGroundMaterial);
		}

		// Create grid of cubes
		float spacing = 3.0f;
		float startOffset = -(GRID_SIZE * spacing) / 2.0f;

		for (int32 x = 0; x < GRID_SIZE; x++)
		{
			for (int32 z = 0; z < GRID_SIZE; z++)
			{
				float posX = startOffset + x * spacing;
				float posZ = startOffset + z * spacing;

				let entity = mScene.CreateEntity(scope $"Cube_{x}_{z}");
				entity.Transform.SetPosition(.(posX, 0.5f, posZ));

				let meshComponent = new StaticMeshComponent();
				entity.AddComponent(meshComponent);
				meshComponent.SetMesh(cubeMesh);
				meshComponent.SetMaterialInstance(0, mCubeMaterials[(x + z) % 8]);
			}
		}

		// Create central tower
		for (int32 y = 0; y < 5; y++)
		{
			let entity = mScene.CreateEntity(scope $"Tower_{y}");
			entity.Transform.SetPosition(.(0, (float)y * 1.5f + 1.0f, 0));
			entity.Transform.SetScale(.(0.8f, 1.5f, 0.8f));

			let meshComponent = new StaticMeshComponent();
			entity.AddComponent(meshComponent);
			meshComponent.SetMesh(cubeMesh);
			meshComponent.SetMaterialInstance(0, mCubeMaterials[y % 8]);
		}

		// Create directional light with shadows
		{
			mSunLightEntity = mScene.CreateEntity("SunLight");
			mSunLightEntity.Transform.LookAt(Vector3.Normalize(.(0.5f, -0.7f, 0.3f)));

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.95f, 0.8f), 1.2f, true);
			mSunLightEntity.AddComponent(lightComp);
		}

		// Create point lights around the scene
		Vector3[4] lightPositions = .(
			.(-8, 4, -8),
			.(8, 4, -8),
			.(-8, 4, 8),
			.(8, 4, 8)
		);
		Vector3[4] lightColors = .(
			.(1.0f, 0.5f, 0.5f),
			.(0.5f, 1.0f, 0.5f),
			.(0.5f, 0.5f, 1.0f),
			.(1.0f, 1.0f, 0.5f)
		);

		for (int i = 0; i < 4; i++)
		{
			let lightEntity = mScene.CreateEntity(scope $"PointLight_{i}");
			lightEntity.Transform.SetPosition(lightPositions[i]);

			let lightComp = LightComponent.CreatePoint(lightColors[i], 3.0f, 15.0f);
			lightEntity.AddComponent(lightComp);
		}

		// Create PLAYER camera (left/top view)
		{
			mPlayerCamera = mScene.CreateEntity("PlayerCamera");
			mPlayerCamera.Transform.SetPosition(.(0, 10, 25));
			UpdatePlayerCameraDirection();

			// Create camera component but mark as NOT main - we'll handle view setup manually
			let cameraComp = new CameraComponent(Math.PI_f / 4.0f, 0.1f, 1000.0f, false);
			cameraComp.UseReverseZ = false;
			cameraComp.SetViewport(SwapChain.Width / 2, SwapChain.Height);
			mPlayerCamera.AddComponent(cameraComp);
		}

		// Create ORBIT camera (right/bottom view)
		{
			mOrbitCamera = mScene.CreateEntity("OrbitCamera");
			UpdateOrbitCameraPosition();

			let cameraComp = new CameraComponent(Math.PI_f / 4.0f, 0.1f, 1000.0f, false);
			cameraComp.UseReverseZ = false;
			cameraComp.SetViewport(SwapChain.Width / 2, SwapChain.Height);
			mOrbitCamera.AddComponent(cameraComp);
		}
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		// Update camera viewports based on split mode
		UpdateCameraViewports();
	}

	private void UpdateCameraViewports()
	{
		uint32 w = SwapChain.Width;
		uint32 h = SwapChain.Height;

		if (mHorizontalSplit)
		{
			// Side-by-side: each camera gets half width
			if (let cameraComp = mPlayerCamera?.GetComponent<CameraComponent>())
				cameraComp.SetViewport(w / 2, h);
			if (let cameraComp = mOrbitCamera?.GetComponent<CameraComponent>())
				cameraComp.SetViewport(w / 2, h);
		}
		else
		{
			// Top-bottom: each camera gets half height
			if (let cameraComp = mPlayerCamera?.GetComponent<CameraComponent>())
				cameraComp.SetViewport(w, h / 2);
			if (let cameraComp = mOrbitCamera?.GetComponent<CameraComponent>())
				cameraComp.SetViewport(w, h / 2);
		}
	}

	protected override void OnInput()
	{
		let keyboard = Shell.InputManager.Keyboard;
		let mouse = Shell.InputManager.Mouse;

		// Toggle mouse capture
		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		// Toggle split screen mode
		if (keyboard.IsKeyPressed(.Space))
		{
			mHorizontalSplit = !mHorizontalSplit;
			UpdateCameraViewports();
			Console.WriteLine($"Split mode: {mHorizontalSplit ? "Horizontal (side-by-side)" : "Vertical (top-bottom)"}");
		}

		// Adjust orbit speed
		if (keyboard.IsKeyPressed(.Equals) || keyboard.IsKeyPressed(.KeypadPlus))
		{
			mOrbitSpeed = Math.Min(mOrbitSpeed + 0.1f, 3.0f);
			Console.WriteLine($"Orbit speed: {mOrbitSpeed:F1}");
		}
		if (keyboard.IsKeyPressed(.Minus) || keyboard.IsKeyPressed(.KeypadMinus))
		{
			mOrbitSpeed = Math.Max(mOrbitSpeed - 0.1f, 0.0f);
			Console.WriteLine($"Orbit speed: {mOrbitSpeed:F1}");
		}

		// Mouse look for player camera
		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mCameraYaw -= mouse.DeltaX * mCameraLookSpeed;
			mCameraPitch -= mouse.DeltaY * mCameraLookSpeed;
			mCameraPitch = Math.Clamp(mCameraPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
			UpdatePlayerCameraDirection();
		}

		// WASD movement for player camera
		if (mPlayerCamera != null)
		{
			let forward = mPlayerCamera.Transform.Forward;
			let right = mPlayerCamera.Transform.Right;
			let up = Vector3(0, 1, 0);
			float speed = mCameraMoveSpeed * DeltaTime;

			if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
				speed *= 2.0f;

			var pos = mPlayerCamera.Transform.Position;
			if (keyboard.IsKeyDown(.W)) pos = pos + forward * speed;
			if (keyboard.IsKeyDown(.S)) pos = pos - forward * speed;
			if (keyboard.IsKeyDown(.A)) pos = pos - right * speed;
			if (keyboard.IsKeyDown(.D)) pos = pos + right * speed;
			if (keyboard.IsKeyDown(.Q)) pos = pos - up * speed;
			if (keyboard.IsKeyDown(.E)) pos = pos + up * speed;
			mPlayerCamera.Transform.SetPosition(pos);
		}
	}

	private void UpdatePlayerCameraDirection()
	{
		if (mPlayerCamera == null)
			return;

		float cosP = Math.Cos(mCameraPitch);
		let forward = Vector3.Normalize(.(
			Math.Sin(mCameraYaw) * cosP,
			Math.Sin(mCameraPitch),
			Math.Cos(mCameraYaw) * cosP
		));

		let target = mPlayerCamera.Transform.Position + forward;
		mPlayerCamera.Transform.LookAt(target);
	}

	private void UpdateOrbitCameraPosition()
	{
		if (mOrbitCamera == null)
			return;

		// Calculate orbit position
		let x = Math.Cos(mOrbitAngle) * mOrbitRadius;
		let z = Math.Sin(mOrbitAngle) * mOrbitRadius;

		mOrbitCamera.Transform.SetPosition(.(x, mOrbitHeight, z));

		// Look at center (top of tower)
		let target = Vector3(0, 4, 0);
		mOrbitCamera.Transform.LookAt(target);
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Update orbit camera
		mOrbitAngle += mOrbitSpeed * deltaTime;
		if (mOrbitAngle > Math.PI_f * 2.0f)
			mOrbitAngle -= Math.PI_f * 2.0f;
		UpdateOrbitCameraPosition();

		// Update context (handles proxy sync)
		mContext.Update(deltaTime);
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		mCurrentFrameIndex = frameIndex;

		// Get camera proxy handles
		mPlayerCameraProxy = mRenderSceneComponent.GetCameraProxy(mPlayerCamera.Id);
		mOrbitCameraProxy = mRenderSceneComponent.GetCameraProxy(mOrbitCamera.Id);

		// Custom multi-view setup: We need to manually set up split-screen views
		// because the default PrepareGPU only adds one main camera view
		PrepareMultiViewGPU(frameIndex);
	}

	private void PrepareMultiViewGPU(int32 frameIndex)
	{
		let context = mRenderSceneComponent.Context;
		let pipeline = mRendererService.Pipeline;
		if (context == null || pipeline == null)
			return;

		// Begin frame
		context.BeginFrame(frameIndex);

		// Get render targets
		var colorTarget = SwapChain.CurrentTextureView;
		var depthTarget = DepthTextureView;

		// Add split-screen views using the context's helper
		context.AddTwoPlayerSplitScreen(
			mPlayerCameraProxy,
			mOrbitCameraProxy,
			&colorTarget,
			&depthTarget,
			SwapChain.Width,
			SwapChain.Height,
			mHorizontalSplit
		);

		// Add shadow cascade views
		context.AddShadowCascadeViews();

		// PrepareVisibility auto-detects multi-view and unions visibility from all cameras
		// PrepareGPU uploads camera uniforms for all views to separate buffer slots
		// and creates per-view bind groups automatically
		pipeline.PrepareVisibility(context);
		pipeline.PrepareGPU(context);
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		let context = mRenderSceneComponent.Context;
		let pipeline = mRendererService.Pipeline;

		if (context == null || pipeline == null)
			return false;

		// Render shadow passes
		pipeline.RenderShadows(context, encoder);

		let textureView = SwapChain.CurrentTextureView;
		if (textureView == null) return true;

		// For split-screen, we need separate render passes for each view
		// because they share the same render target with different viewports
		List<RenderView*> cameraViews = scope .();
		context.GetEnabledSortedViews(cameraViews);

		// Filter to just camera views
		for (int i = cameraViews.Count - 1; i >= 0; i--)
		{
			let viewType = cameraViews[i].Type;
			if (viewType != .MainCamera && viewType != .SecondaryCamera)
				cameraViews.RemoveAtFast(i);
		}

		// Render each camera view in its own render pass
		bool firstView = true;
		int32 viewSlot = 0;
		for (let view in cameraViews)
		{
			// Skip views with invalid dimensions
			if (view.ViewportWidth == 0 || view.ViewportHeight == 0)
				continue;

			// Create render pass - clear on first view, load on subsequent
			RenderPassColorAttachment[1] colorAttachments = .(.()
			{
				View = textureView,
				ResolveTarget = null,
				LoadOp = firstView ? .Clear : .Load,
				StoreOp = .Store,
				ClearValue = .(0.1f, 0.1f, 0.15f, 1.0f)
			});

			RenderPassDescriptor renderPassDesc = .(colorAttachments);
			RenderPassDepthStencilAttachment depthAttachment = .()
			{
				View = DepthTextureView,
				DepthLoadOp = firstView ? .Clear : .Load,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f,
				StencilLoadOp = firstView ? .Clear : .Load,
				StencilStoreOp = .Discard,
				StencilClearValue = 0
			};
			renderPassDesc.DepthStencilAttachment = depthAttachment;

			let renderPass = encoder.BeginRenderPass(&renderPassDesc);
			if (renderPass == null)
				continue;

			// Render this view - pipeline.RenderView automatically uses the correct bind group
			pipeline.RenderView(context, view, renderPass, viewSlot);

			renderPass.End();
			delete renderPass;

			firstView = false;
			viewSlot++;
		}

		// End frame
		context.EndFrame();

		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - we override OnRenderFrame
	}

	protected override void OnCleanup()
	{
		mContext?.Shutdown();
		Device.WaitIdle();

		// Clean up materials
		if (mRendererService?.MaterialSystem != null)
		{
			let materialSystem = mRendererService.MaterialSystem;

			for (let cubeMat in mCubeMaterials)
			{
				if (cubeMat.IsValid)
					materialSystem.ReleaseInstance(cubeMat);
			}

			if (mGroundMaterial.IsValid)
				materialSystem.ReleaseInstance(mGroundMaterial);

			if (mPBRMaterial.IsValid)
				materialSystem.ReleaseMaterial(mPBRMaterial);
		}

		delete mRendererService;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let sample = scope MultiViewSample();
		return sample.Run();
	}
}

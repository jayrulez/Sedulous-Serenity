namespace RendererIntegrated;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Framework.Core;
using Sedulous.Framework.Renderer;
using Sedulous.Logging.Abstractions;
using Sedulous.Logging.Console;
using SampleFramework;
using Sedulous.Logging.Debug;

/// Demonstrates Framework.Core integration with Framework.Renderer.
/// Uses entities with MeshRendererComponent and LightComponent.
/// Camera is controlled directly (like RendererShadow) to verify math is correct.
class RendererIntegratedSample : RHISampleApp
{
	// Grid size
	private const int32 GRID_SIZE = 8;  // 8x8 = 64 cubes

	// Framework.Core components
	private ILogger mLogger ~ delete _;
	private Context mContext ~ delete _;
	private Scene mScene;  // Owned by SceneManager

	// Renderer components
	private RendererService mRendererService;
	private RenderSceneComponent mRenderSceneComponent;

	// Direct camera control (like RendererShadow sample)
	// We bypass CameraComponent to test the raw camera math
	private Camera mCamera;
	private ProxyHandle mCameraProxyHandle = .Invalid;
	private float mCameraYaw = Math.PI_f;
	private float mCameraPitch = -0.3f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 15.0f;
	private float mCameraLookSpeed = 0.003f;

	// Current frame index for rendering
	private int32 mCurrentFrameIndex = 0;

	public this() : base(.()
	{
		Title = "Framework.Core + Renderer Integration",
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
		if (mRendererService.Initialize(Device, "../../Sedulous/Sedulous.Framework.Renderer/shaders") case .Err)
		{
			Console.WriteLine("Failed to initialize RendererService");
			return false;
		}
		mContext.RegisterService<RendererService>(mRendererService);

		// Create scene with RenderSceneComponent
		mScene = mContext.SceneManager.CreateScene("MainScene");
		mRenderSceneComponent = mScene.AddSceneComponent(new RenderSceneComponent(mRendererService));

		// Initialize rendering with output formats
		if (mRenderSceneComponent.InitializeRendering(SwapChain.Format, .Depth24PlusStencil8, Device.FlipProjectionRequired) case .Err)
		{
			Console.WriteLine("Failed to initialize scene rendering");
			return false;
		}

		// Create all entities (cubes, lights, camera)
		CreateEntities();

		// Set active scene and start context
		mContext.SceneManager.SetActiveScene(mScene);
		mContext.Startup();

		Console.WriteLine("Framework.Core + Renderer integration sample initialized");
		Console.WriteLine($"Created {GRID_SIZE * GRID_SIZE} cube entities with MeshRendererComponent");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Tab=Toggle mouse capture, Shift=Fast");

		// Debug: initial state
		Console.WriteLine($"[INIT DEBUG] MeshCount={mRenderSceneComponent.MeshCount}, HasCamera={mRenderSceneComponent.GetMainCameraProxy() != null}");

		return true;
	}

	private void CreateEntities()
	{
		// Create shared CPU mesh - uploaded to GPU automatically by MeshRendererComponent
		let cubeMesh = Mesh.CreateCube(1.0f);
		defer delete cubeMesh;

		// Create ground plane (large flat cube)
		{
			let groundEntity = mScene.CreateEntity("Ground");
			groundEntity.Transform.SetPosition(.(0, -0.5f, 0));
			groundEntity.Transform.SetScale(.(50.0f, 1.0f, 50.0f));

			let meshRenderer = new MeshRendererComponent();
			meshRenderer.MaterialIds[0] = 7;  // Use a neutral color
			meshRenderer.MaterialCount = 1;
			groundEntity.AddComponent(meshRenderer);
			meshRenderer.SetMesh(cubeMesh);
		}

		float spacing = 3.0f;
		float startOffset = -(GRID_SIZE * spacing) / 2.0f;

		// Create grid of cube entities
		for (int32 x = 0; x < GRID_SIZE; x++)
		{
			for (int32 z = 0; z < GRID_SIZE; z++)
			{
				float posX = startOffset + x * spacing;
				float posZ = startOffset + z * spacing;

				// Create entity with transform
				let entity = mScene.CreateEntity(scope $"Cube_{x}_{z}");
				entity.Transform.SetPosition(.(posX, 0.5f, posZ));  // Raise cubes to sit on ground

				// Add MeshRendererComponent first, then set mesh
				// (SetMesh needs access to RendererService via entity's scene)
				let meshRenderer = new MeshRendererComponent();
				meshRenderer.MaterialIds[0] = (uint32)((x + z) % 8);  // Vary colors
				meshRenderer.MaterialCount = 1;
				entity.AddComponent(meshRenderer);

				// Now set the mesh - GPU upload happens automatically
				meshRenderer.SetMesh(cubeMesh);
			}
		}

		// Create directional light entity
		{
			let lightEntity = mScene.CreateEntity("SunLight");
			lightEntity.Transform.LookAt(.(-0.5f, -1.0f, -0.3f));

			let lightComp = LightComponent.CreateDirectional(.(1.0f, 0.95f, 0.8f), 1.0f);
			lightEntity.AddComponent(lightComp);
		}

		// Create point lights
		Random rng = scope .();
		for (int i = 0; i < 8; i++)
		{
			float px = ((float)rng.NextDouble() - 0.5f) * 30.0f;
			float py = (float)rng.NextDouble() * 5.0f + 2.0f;
			float pz = ((float)rng.NextDouble() - 0.5f) * 30.0f;

			let lightEntity = mScene.CreateEntity(scope $"PointLight_{i}");
			lightEntity.Transform.SetPosition(.(px, py, pz));

			Vector3 color = .(
				(float)rng.NextDouble() * 0.5f + 0.5f,
				(float)rng.NextDouble() * 0.5f + 0.5f,
				(float)rng.NextDouble() * 0.5f + 0.5f
			);

			let lightComp = LightComponent.CreatePoint(color, 5.0f, 15.0f);
			lightEntity.AddComponent(lightComp);
		}

		// Initialize camera directly (bypassing CameraComponent to test raw math)
		// This is the same approach used in RendererShadow sample
		mCamera = .();
		mCamera.Position = .(0, 10, 30);
		mCamera.Up = .(0, 1, 0);
		mCamera.FieldOfView = Math.PI_f / 4.0f;
		mCamera.NearPlane = 0.1f;
		mCamera.FarPlane = 1000.0f;
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);
		UpdateCameraDirection();

		// Create camera proxy directly on RenderWorld
		mCameraProxyHandle = mRenderSceneComponent.RenderWorld.CreateCamera(
			mCamera, SwapChain.Width, SwapChain.Height, isMain: true);
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		// Update camera aspect ratio
		mCamera.SetAspectRatio(width, height);

		// Update the camera proxy viewport
		if (let proxy = mRenderSceneComponent.RenderWorld.GetCameraProxy(mCameraProxyHandle))
		{
			proxy.ViewportWidth = width;
			proxy.ViewportHeight = height;
			proxy.AspectRatio = mCamera.AspectRatio;
			proxy.UpdateMatrices();
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

		// Mouse look
		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mCameraYaw -= mouse.DeltaX * mCameraLookSpeed;
			mCameraPitch -= mouse.DeltaY * mCameraLookSpeed;
			mCameraPitch = Math.Clamp(mCameraPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
			UpdateCameraDirection();
		}

		// WASD movement - use Camera.Forward/Right directly (like RendererShadow)
		let forward = mCamera.Forward;
		let right = mCamera.Right;
		let up = Vector3(0, 1, 0);
		float speed = mCameraMoveSpeed * DeltaTime;

		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
			speed *= 2.0f;

		if (keyboard.IsKeyDown(.W)) mCamera.Position = mCamera.Position + forward * speed;
		if (keyboard.IsKeyDown(.S)) mCamera.Position = mCamera.Position - forward * speed;
		if (keyboard.IsKeyDown(.A)) mCamera.Position = mCamera.Position - right * speed;
		if (keyboard.IsKeyDown(.D)) mCamera.Position = mCamera.Position + right * speed;
		if (keyboard.IsKeyDown(.Q)) mCamera.Position = mCamera.Position - up * speed;
		if (keyboard.IsKeyDown(.E)) mCamera.Position = mCamera.Position + up * speed;
	}

	private void UpdateCameraDirection()
	{
		// Compute forward from yaw/pitch (same as RendererShadow)
		float cosP = Math.Cos(mCameraPitch);
		mCamera.Forward = Vector3.Normalize(.(
			Math.Sin(mCameraYaw) * cosP,
			Math.Sin(mCameraPitch),
			Math.Cos(mCameraYaw) * cosP
		));
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Sync Camera struct to camera proxy (same as RendererShadow pattern)
		if (let proxy = mRenderSceneComponent.RenderWorld.GetCameraProxy(mCameraProxyHandle))
		{
			proxy.Position = mCamera.Position;
			proxy.Forward = mCamera.Forward;
			proxy.Up = mCamera.Up;
			proxy.Right = Vector3.Normalize(Vector3.Cross(mCamera.Forward, mCamera.Up));
			proxy.UpdateMatrices();
		}

		// Update the context for entity/mesh proxy sync
		mContext.Update(deltaTime);
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		// Debug: print stats on first few frames
		static int32 debugFrameCount = 0;
		if (debugFrameCount < 5)
		{
			debugFrameCount++;
			Console.WriteLine($"[DEBUG] Frame {debugFrameCount}: Meshes={mRenderSceneComponent.MeshCount}, Visible={mRenderSceneComponent.VisibleInstanceCount}, HasCamera={mRenderSceneComponent.GetMainCameraProxy() != null}");
		}

		// Upload GPU data - this is called after fence wait, safe to write buffers
		mCurrentFrameIndex = frameIndex;
		mRenderSceneComponent.PrepareGPU(frameIndex);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Render the scene - all GPU details handled by RenderSceneComponent
		mRenderSceneComponent.Render(renderPass, SwapChain.Width, SwapChain.Height);
	}

	protected override void OnCleanup()
	{
		mContext?.Shutdown();
		delete mRendererService;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let sample = scope RendererIntegratedSample();
		return sample.Run();
	}
}

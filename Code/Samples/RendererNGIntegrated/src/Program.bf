namespace RendererNGIntegrated;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Shell.Input;
using Sedulous.Engine.Runtime;
using Sedulous.RendererNG;

/// Integrated sample demonstrating the full RendererNG pipeline.
/// This sample shows how to use all RendererNG systems together.
class RendererNGIntegratedApp : Application
{
	// Core renderer (explicitly deleted in OnShutdown before device is destroyed)
	private Renderer mRenderer;
	private RenderWorld mRenderWorld;

	// Mesh system (explicitly deleted in OnShutdown before device is destroyed)
	private MeshPool mMeshPool;
	private MeshUploader mMeshUploader;

	// Scene data
	private MeshHandle mCubeMesh;
	private MeshHandle mPlaneMesh;
	private ProxyHandle<StaticMeshProxy> mCubeProxy;
	private ProxyHandle<StaticMeshProxy> mPlaneProxy;
	private ProxyHandle<LightProxy> mSunLight;
	private ProxyHandle<CameraProxy> mCamera;

	// Camera control
	private float mCameraYaw = 0;
	private float mCameraPitch = 0.3f;
	private float mCameraDistance = 5.0f;
	private Vector3 mCameraTarget = .Zero;

	// Animation
	private float mRotation = 0;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize()
	{
		Console.WriteLine("=== RendererNG Integrated Sample ===");
		Console.WriteLine("Demonstrating full renderer pipeline\n");

		// Initialize the renderer with shader path from asset directory
		mRenderer = new Renderer();
		let shaderPath = GetAssetPath("shaders", .. scope .());
		Console.WriteLine("Shader path: {}", shaderPath);

		if (mRenderer.Initialize(Device, shaderPath) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize renderer");
			Exit();
			return;
		}

		// Create a render world
		mRenderWorld = mRenderer.CreateRenderWorld();

		// Initialize mesh system
		mMeshPool = new MeshPool();
		mMeshPool.Initialize(Device);

		mMeshUploader = new MeshUploader();
		mMeshUploader.Initialize(Device, mMeshPool);

		// Wire mesh pool to renderer's draw system
		mRenderer.InitializeMeshSystem(mMeshPool);

		// Create scene
		if (!CreateScene())
		{
			Exit();
			return;
		}

		Console.WriteLine("\n=== Initialization Complete ===");
		Console.WriteLine("Controls: WASD/Arrow keys to rotate camera, Q/E to zoom");
		Console.WriteLine("Press R for render stats");
		Console.WriteLine("Press ESC to exit\n");
	}

	private bool CreateScene()
	{
		// Create a cube mesh
		let cubeMesh = MeshPrimitives.CreateCube("Cube");
		defer delete cubeMesh;

		if (mMeshUploader.Upload(cubeMesh) case .Ok(let handle))
		{
			mCubeMesh = handle;
			Console.WriteLine("Cube mesh created: {} vertices, {} indices",
				cubeMesh.VertexCount, cubeMesh.IndexCount);
		}
		else
		{
			Console.WriteLine("ERROR: Failed to upload cube mesh");
			return false;
		}

		// Create a ground plane
		let planeMesh = MeshPrimitives.CreatePlane(10.0f, 10.0f, "GroundPlane");
		defer delete planeMesh;

		if (mMeshUploader.Upload(planeMesh) case .Ok(let planeHandle))
		{
			mPlaneMesh = planeHandle;
			Console.WriteLine("Plane mesh created: {} vertices, {} indices",
				planeMesh.VertexCount, planeMesh.IndexCount);
		}
		else
		{
			Console.WriteLine("ERROR: Failed to upload plane mesh");
			return false;
		}

		// Create proxies for rendering
		mCubeProxy = mRenderWorld.CreateStaticMesh(.()
		{
			Transform = Matrix.CreateTranslation(0, 0.5f, 0),
			Bounds = cubeMesh.Bounds,
			MeshHandle = mCubeMesh.Index,
			Flags = .Visible | .CastShadow | .ReceiveShadow
		});
		Console.WriteLine("Cube proxy created: handle index {}", mCubeProxy.Index);

		mPlaneProxy = mRenderWorld.CreateStaticMesh(.()
		{
			Transform = Matrix.Identity,
			Bounds = planeMesh.Bounds,
			MeshHandle = mPlaneMesh.Index,
			Flags = .Visible | .ReceiveShadow
		});
		Console.WriteLine("Plane proxy created: handle index {}", mPlaneProxy.Index);

		// Create a directional light (sun)
		mSunLight = mRenderWorld.CreateLight(.DefaultDirectional);
		if (let light = mRenderWorld.GetLight(mSunLight))
		{
			light.Direction = Vector3.Normalize(.(0.5f, -1.0f, 0.3f));
			light.Color = .(1.0f, 0.95f, 0.9f);
			light.Intensity = 1.0f;
			light.Flags = .Enabled | .CastShadow;
			Console.WriteLine("Directional light created");
		}

		// Create camera
		mCamera = mRenderWorld.CreateCamera(.DefaultPerspective);
		UpdateCamera();
		Console.WriteLine("Camera created");

		Console.WriteLine("\nScene created: {} static meshes, {} lights, {} cameras",
			mRenderWorld.StaticMeshCount, mRenderWorld.LightCount, mRenderWorld.CameraCount);
		return true;
	}

	private void UpdateCamera()
	{
		if (!mCamera.HasValidIndex)
			return;

		// Calculate camera position from spherical coordinates
		float x = mCameraDistance * Math.Cos(mCameraPitch) * Math.Sin(mCameraYaw);
		float y = mCameraDistance * Math.Sin(mCameraPitch);
		float z = mCameraDistance * Math.Cos(mCameraPitch) * Math.Cos(mCameraYaw);

		let position = mCameraTarget + Vector3(x, y, z);
		let forward = Vector3.Normalize(mCameraTarget - position);

		if (let camera = mRenderWorld.GetCamera(mCamera))
		{
			camera.Position = position;
			camera.Forward = forward;
			camera.Up = .UnitY;
			camera.Right = Vector3.Cross(forward, camera.Up);
			camera.AspectRatio = (float)mWindow.Width / (float)mWindow.Height;
			camera.NearPlane = 0.1f;
			camera.FarPlane = 100.0f;
		}
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		// Camera rotation
		float rotSpeed = 0.02f;
		if (keyboard.IsKeyDown(.Left) || keyboard.IsKeyDown(.A))
			mCameraYaw -= rotSpeed;
		if (keyboard.IsKeyDown(.Right) || keyboard.IsKeyDown(.D))
			mCameraYaw += rotSpeed;
		if (keyboard.IsKeyDown(.Up) || keyboard.IsKeyDown(.W))
			mCameraPitch = Math.Clamp(mCameraPitch + rotSpeed, -1.4f, 1.4f);
		if (keyboard.IsKeyDown(.Down) || keyboard.IsKeyDown(.S))
			mCameraPitch = Math.Clamp(mCameraPitch - rotSpeed, -1.4f, 1.4f);

		// Camera zoom
		if (keyboard.IsKeyDown(.Q))
			mCameraDistance = Math.Clamp(mCameraDistance - 0.1f, 2.0f, 20.0f);
		if (keyboard.IsKeyDown(.E))
			mCameraDistance = Math.Clamp(mCameraDistance + 0.1f, 2.0f, 20.0f);

		// Stats
		if (keyboard.IsKeyPressed(.R))
			PrintStats();
	}

	private void PrintStats()
	{
		Console.WriteLine("\n=== Render Stats ===");
		Console.WriteLine("Frame: {}", mRenderer.FrameNumber);

		let stats = mRenderer.Stats;
		Console.WriteLine("Draw Calls: {}", stats.DrawCalls);
		Console.WriteLine("Triangles: {}", stats.Triangles);

		Console.WriteLine("\n=== Scene Stats ===");
		Console.WriteLine("Static Meshes: {}", mRenderWorld.StaticMeshCount);
		Console.WriteLine("Lights: {}", mRenderWorld.LightCount);
		Console.WriteLine("Cameras: {}", mRenderWorld.CameraCount);

		Console.WriteLine("\n=== Mesh Pool ===");
		Console.WriteLine("Active meshes: {}", mMeshPool.ActiveCount);
		Console.WriteLine("Total slots: {}", mMeshPool.TotalCount);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		// Animate the cube
		mRotation += frame.DeltaTime;
		if (mCubeProxy.HasValidIndex)
		{
			if (let proxy = mRenderWorld.GetStaticMesh(mCubeProxy))
			{
				proxy.Transform = Matrix.CreateRotationY(mRotation) * Matrix.CreateTranslation(0, 0.5f, 0);
			}
		}

		// Update camera
		UpdateCamera();

		// Begin renderer frame
		mRenderer.BeginFrame((uint32)frame.FrameIndex, frame.DeltaTime, frame.TotalTime);
		mRenderWorld.BeginFrame();

		// Prepare scene uniforms from camera
		if (let camera = mRenderWorld.GetCamera(mCamera))
		{
			mRenderer.PrepareFrame(camera, frame.TotalTime, frame.DeltaTime,
				(uint32)mWindow.Width, (uint32)mWindow.Height);
		}

		// Prepare lighting uniforms
		mRenderer.PrepareLighting(mRenderWorld);
	}

	protected override void OnRender(IRenderPassEncoder renderPass, FrameContext frame)
	{
		// Render all meshes from the render world
		mRenderer.RenderMeshes(renderPass, mRenderWorld, mMeshPool);
	}

	protected override void OnFrameEnd()
	{
		// End renderer frame
		mRenderWorld.EndFrame();
		mRenderer.EndFrame();
	}

	protected override void OnShutdown()
	{
		Console.WriteLine("\n=== Shutting Down ===");

		// Destroy scene objects
		if (mRenderWorld != null)
		{
			mRenderWorld.DestroyStaticMesh(mCubeProxy);
			mRenderWorld.DestroyStaticMesh(mPlaneProxy);
			mRenderWorld.DestroyLight(mSunLight);
			mRenderWorld.DestroyCamera(mCamera);
		}

		// Release meshes
		if (mMeshPool != null)
		{
			mMeshPool.Release(mCubeMesh);
			mMeshPool.Release(mPlaneMesh);
		}

		// Shutdown and delete renderer systems (must happen before device is deleted)
		if (mRenderer != null)
			mRenderer.Shutdown();

		delete mMeshUploader;
		mMeshUploader = null;

		delete mMeshPool;
		mMeshPool = null;

		delete mRenderWorld;
		mRenderWorld = null;

		delete mRenderer;
		mRenderer = null;

		Console.WriteLine("Shutdown complete");
	}
}

class Program
{
	public static int Main(String[] args)
	{
		// Create and initialize shell
		let shell = new SDL3Shell();
		defer { shell.Shutdown(); delete shell; }

		if (shell.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shell");
			return -1;
		}

		// Create Vulkan backend
		let backend = new VulkanBackend(enableValidation: true);
		defer delete backend;

		if (!backend.IsInitialized)
		{
			Console.WriteLine("Failed to initialize Vulkan backend");
			return -1;
		}

		// Enumerate adapters and create device
		List<IAdapter> adapters = scope .();
		backend.EnumerateAdapters(adapters);

		if (adapters.Count == 0)
		{
			Console.WriteLine("No GPU adapters found");
			return -1;
		}

		Console.WriteLine("Using adapter: {0}", adapters[0].Info.Name);

		let device = adapters[0].CreateDevice().GetValueOrDefault();
		if (device == null)
		{
			Console.WriteLine("Failed to create device");
			return -1;
		}
		defer delete device;

		// Create and run application
		let settings = ApplicationSettings()
		{
			Title = "RendererNG Integrated",
			Width = 1280,
			Height = 720,
			EnableDepth = true,
			ClearColor = .(0.2f, 0.3f, 0.4f, 1.0f)
		};

		let app = scope RendererNGIntegratedApp(shell, device, backend);
		return app.Run(settings);
	}
}

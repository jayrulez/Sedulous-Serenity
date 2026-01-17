using Sedulous.Mathematics;
using Sedulous.Runtime;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using Sedulous.Geometry;
using System;

namespace RenderSandbox;

/// Integrated sample demonstrating the new Sedulous.Render pipeline.
class RenderIntegratedApp : Application
{
	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Test objects
	private GPUMeshHandle mCubeMeshHandle;
	private MeshProxyHandle mCubeProxy;
	private LightProxyHandle mSunLight;
	private LightProxyHandle mPointLight;

	// Camera control
	private float mCameraYaw = 0;
	private float mCameraPitch = 0.3f;
	private float mCameraDistance = 5.0f;
	private Vector3 mCameraTarget = .Zero;
	private Vector3 mCameraPosition;
	private Vector3 mCameraForward;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize()
	{
		Console.WriteLine("=== Sedulous.Render Sandbox ===");
		Console.WriteLine("Testing new renderer infrastructure\n");

		// Initialize render system
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope $"{AssetDirectory}/Render/Shaders", .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}
		Console.WriteLine("RenderSystem initialized");

		// Create render world
		mWorld = mRenderSystem.CreateWorld();
		mRenderSystem.SetActiveWorld(mWorld);
		Console.WriteLine("RenderWorld created");

		// Create render view
		mView = new RenderView();
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 100.0f;
		Console.WriteLine("RenderView created");

		// Create test mesh
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let handle))
		{
			mCubeMeshHandle = handle;
			Console.WriteLine("Cube mesh uploaded to GPU");
		}
		else
		{
			Console.WriteLine("ERROR: Failed to upload cube mesh");
		}
		delete cubeMesh;

		// Create cube proxy
		mCubeProxy = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(mCubeProxy))
		{
			proxy.MeshHandle = mCubeMeshHandle;
			proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}
		Console.WriteLine("Cube proxy created");

		// Create sun light
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -1.0f, 0.3f)),
			.(1.0f, 0.95f, 0.9f),
			1.0f
		);
		Console.WriteLine("Sun light created");

		// Create point light
		mPointLight = mWorld.CreatePointLight(
			.(2.0f, 1.0f, 2.0f),
			.(1.0f, 0.5f, 0.2f),
			10.0f,
			5.0f
		);
		Console.WriteLine("Point light created");

		Console.WriteLine("\n=== Initialization Complete ===");
		Console.WriteLine("Objects in world:");
		Console.WriteLine("  Meshes: {}", mWorld.MeshCount);
		Console.WriteLine("  Lights: {}", mWorld.LightCount);
		Console.WriteLine("\nControls:");
		Console.WriteLine("  WASD/Arrow keys: rotate camera");
		Console.WriteLine("  Q/E: zoom in/out");
		Console.WriteLine("  R: print render stats");
		Console.WriteLine("  ESC: exit\n");
	}

	private void UpdateCamera()
	{
		// Calculate camera position from spherical coordinates
		float x = mCameraDistance * Math.Cos(mCameraPitch) * Math.Sin(mCameraYaw);
		float y = mCameraDistance * Math.Sin(mCameraPitch);
		float z = mCameraDistance * Math.Cos(mCameraPitch) * Math.Cos(mCameraYaw);

		mCameraPosition = mCameraTarget + Vector3(x, y, z);
		mCameraForward = Vector3.Normalize(mCameraTarget - mCameraPosition);

		// Update view
		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = mCameraForward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices(mDevice.FlipProjectionRequired);
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
		Console.WriteLine("Frame: {}", mRenderSystem.FrameNumber);
		Console.WriteLine("Draw Calls: {}", mRenderSystem.Stats.DrawCalls);
		Console.WriteLine("Visible Meshes: {}", mRenderSystem.Stats.VisibleMeshes);
		Console.WriteLine("Culled Meshes: {}", mRenderSystem.Stats.CulledMeshes);
		Console.WriteLine("World Meshes: {}", mWorld.MeshCount);
		Console.WriteLine("World Lights: {}", mWorld.LightCount);
		Console.WriteLine("");
	}

	protected override void OnUpdate(FrameContext frame)
	{
		// Update camera
		UpdateCamera();

		// Rotate the cube slowly
		if (let proxy = mWorld.GetMesh(mCubeProxy))
		{
			float angle = (float)frame.TotalTime * 0.5f;
			let rotation = Matrix.CreateRotationY(angle);
			proxy.SetTransform(rotation);
		}

		// Move point light in a circle
		if (let light = mWorld.GetLight(mPointLight))
		{
			float angle = (float)frame.TotalTime;
			light.Position = .(
				Math.Cos(angle) * 2.0f,
				1.0f + Math.Sin(angle * 0.5f) * 0.5f,
				Math.Sin(angle) * 2.0f
			);
		}
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		// Begin frame
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		// Set camera
		mRenderSystem.SetCamera(
			mCameraPosition,
			mCameraForward,
			.(0, 1, 0),
			mView.FieldOfView,
			mView.AspectRatio,
			mView.NearPlane,
			mView.FarPlane,
			mView.Width,
			mView.Height
		);

		// For now, just render a simple pass without the full feature system
		// (features will be added later)

		// Create main render pass
		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = render.CurrentTextureView,
			ResolveTarget = null,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = .(0.1f, 0.1f, 0.15f, 1.0f)
		});

		RenderPassDescriptor mainDesc = .(colorAttachments);
		if (render.DepthTextureView != null)
		{
			mainDesc.DepthStencilAttachment = .()
			{
				View = render.DepthTextureView,
				DepthLoadOp = .Clear,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f,
				StencilLoadOp = .Clear,
				StencilStoreOp = .Store,
				StencilClearValue = 0
			};
		}

		let renderPass = render.Encoder.BeginRenderPass(&mainDesc);
		renderPass.SetViewport(0, 0, render.SwapChain.Width, render.SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, render.SwapChain.Width, render.SwapChain.Height);

		// TODO: Once render features are implemented, this will use:
		// mRenderSystem.BuildRenderGraph(mView);
		// mRenderSystem.Execute(render.Encoder);

		renderPass.End();
		delete renderPass;

		// End frame
		mRenderSystem.EndFrame();

		return true;
	}

	protected override void OnFrameEnd()
	{
	}

	protected override void OnShutdown()
	{
		Console.WriteLine("\n=== Shutting Down ===");

		// Release mesh handle
		if (mCubeMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);

		// Shutdown render system
		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Shutdown complete");
	}
}

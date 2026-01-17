using Sedulous.Mathematics;
using Sedulous.Runtime;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;
using System;
using System.Collections;

namespace RenderSandbox;

/// Integrated sample demonstrating the new Sedulous.Render pipeline.
class RenderIntegratedApp : Application
{
	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Render features (owned by RenderSystem after registration)
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;

	// Test objects
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;
	private List<MeshProxyHandle> mCubeProxies = new .() ~ delete _;
	private MeshProxyHandle mFloorProxy;
	private LightProxyHandle mSunLight;
	private List<LightProxyHandle> mPointLights = new .() ~ delete _;

	// Camera control
	private float mCameraYaw = 0.5f;
	private float mCameraPitch = 0.4f;
	private float mCameraDistance = 8.0f;
	private Vector3 mCameraTarget = .(0, 0.5f, 0);
	private Vector3 mCameraPosition;
	private Vector3 mCameraForward;

	// Stats display
	private float mStatsTimer = 0;
	private const float StatsInterval = 2.0f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize()
	{
		Console.WriteLine("=== Sedulous.Render Sandbox ===");
		Console.WriteLine("Testing render feature infrastructure\n");

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

		// Register render features
		RegisterFeatures();

		// Create test meshes
		CreateMeshes();

		// Create scene objects
		CreateSceneObjects();

		// Create lights
		CreateLights();

		Console.WriteLine("\n=== Initialization Complete ===");
		Console.WriteLine("Objects in world:");
		Console.WriteLine("  Meshes: {}", mWorld.MeshCount);
		Console.WriteLine("  Lights: {}", mWorld.LightCount);
		Console.WriteLine("\nControls:");
		Console.WriteLine("  WASD/Arrow keys: rotate camera");
		Console.WriteLine("  Q/E: zoom in/out");
		Console.WriteLine("  R: print render stats");
		Console.WriteLine("  H: toggle Hi-Z culling");
		Console.WriteLine("  ESC: exit\n");
	}

	private void RegisterFeatures()
	{
		// Depth prepass (runs first, generates depth buffer for Hi-Z)
		mDepthFeature = new DepthPrepassFeature();
		if (mRenderSystem.RegisterFeature(mDepthFeature) case .Err)
			Console.WriteLine("Warning: Failed to register DepthPrepassFeature");
		else
			Console.WriteLine("Registered: DepthPrepassFeature");

		// Forward opaque (main scene rendering with PBR and lighting)
		mForwardFeature = new ForwardOpaqueFeature();
		if (mRenderSystem.RegisterFeature(mForwardFeature) case .Err)
			Console.WriteLine("Warning: Failed to register ForwardOpaqueFeature");
		else
			Console.WriteLine("Registered: ForwardOpaqueFeature");

		// Sky (procedural sky and IBL)
		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");
		else
			Console.WriteLine("Registered: SkyFeature");
	}

	private void CreateMeshes()
	{
		// Create cube mesh
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

		// Create floor plane mesh
		let planeMesh = StaticMesh.CreatePlane(10.0f, 10.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let planeHandle))
		{
			mPlaneMeshHandle = planeHandle;
			Console.WriteLine("Plane mesh uploaded to GPU");
		}
		else
		{
			Console.WriteLine("ERROR: Failed to upload plane mesh");
		}
		delete planeMesh;
	}

	private void CreateSceneObjects()
	{
		// Get default material
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Create floor
		mFloorProxy = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(mFloorProxy))
		{
			proxy.MeshHandle = mPlaneMeshHandle;
			proxy.Material = defaultMaterial;
			proxy.SetLocalBounds(BoundingBox(Vector3(-5, 0, -5), Vector3(5, 0.01f, 5)));
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}

		// Create grid of cubes
		let gridSize = 3;
		let spacing = 2.0f;
		let offset = (gridSize - 1) * spacing * 0.5f;

		for (int z = 0; z < gridSize; z++)
		{
			for (int x = 0; x < gridSize; x++)
			{
				let cubeProxy = mWorld.CreateMesh();
				if (let proxy = mWorld.GetMesh(cubeProxy))
				{
					proxy.MeshHandle = mCubeMeshHandle;
					proxy.Material = defaultMaterial;
					proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));

					let position = Vector3(
						x * spacing - offset,
						0.5f,
						z * spacing - offset
					);
					proxy.SetTransformImmediate(Matrix.CreateTranslation(position));
					proxy.Flags = .DefaultOpaque;
				}
				mCubeProxies.Add(cubeProxy);
			}
		}

		Console.WriteLine("Created {} cubes and 1 floor", mCubeProxies.Count);
	}

	private void CreateLights()
	{
		// Create sun light (directional)
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -1.0f, 0.3f)),
			.(1.0f, 0.98f, 0.95f),
			1.5f
		);

		// Mark sun as shadow caster
		if (let light = mWorld.GetLight(mSunLight))
		{
			light.CastsShadows = true;
		}
		Console.WriteLine("Sun light created");

		// Create colored point lights
		Color[4] lightColors = .(
			.(1.0f, 0.3f, 0.2f, 1.0f),  // Red-orange
			.(0.2f, 1.0f, 0.3f, 1.0f),  // Green
			.(0.2f, 0.3f, 1.0f, 1.0f),  // Blue
			.(1.0f, 0.9f, 0.3f, 1.0f)   // Yellow
		);

		float radius = 4.0f;
		for (int i = 0; i < 4; i++)
		{
			float angle = i * (Math.PI_f * 0.5f);
			Vector3 position = .(
				Math.Cos(angle) * radius,
				1.5f,
				Math.Sin(angle) * radius
			);

			let pointLight = mWorld.CreatePointLight(
				position,
				.(lightColors[i].R, lightColors[i].G, lightColors[i].B),
				5.0f,  // Intensity
				6.0f   // Range
			);
			mPointLights.Add(pointLight);
		}
		Console.WriteLine("Created {} point lights", mPointLights.Count);
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
			mCameraDistance = Math.Clamp(mCameraDistance - 0.1f, 2.0f, 25.0f);
		if (keyboard.IsKeyDown(.E))
			mCameraDistance = Math.Clamp(mCameraDistance + 0.1f, 2.0f, 25.0f);

		// Toggle Hi-Z
		if (keyboard.IsKeyPressed(.H))
		{
			if (mDepthFeature != null)
			{
				mDepthFeature.EnableHiZ = !mDepthFeature.EnableHiZ;
				Console.WriteLine("Hi-Z Occlusion Culling: {}", mDepthFeature.EnableHiZ ? "ON" : "OFF");
			}
		}

		// Stats
		if (keyboard.IsKeyPressed(.R))
			PrintStats();
	}

	private void PrintStats()
	{
		Console.WriteLine("\n=== Render Stats ===");
		Console.WriteLine("Frame: {}", mRenderSystem.FrameNumber);
		Console.WriteLine("Draw Calls: {}", mRenderSystem.Stats.DrawCalls);
		Console.WriteLine("Shadow Draws: {}", mRenderSystem.Stats.ShadowDrawCalls);
		Console.WriteLine("Compute Dispatches: {}", mRenderSystem.Stats.ComputeDispatches);
		Console.WriteLine("Visible Meshes: {}", mRenderSystem.Stats.VisibleMeshes);
		Console.WriteLine("Culled Meshes: {}", mRenderSystem.Stats.CulledMeshes);
		Console.WriteLine("World Meshes: {}", mWorld.MeshCount);
		Console.WriteLine("World Lights: {}", mWorld.LightCount);
		if (mDepthFeature != null)
			Console.WriteLine("Hi-Z Culling: {}", mDepthFeature.EnableHiZ ? "ON" : "OFF");
		Console.WriteLine("");
	}

	protected override void OnUpdate(FrameContext frame)
	{
		// Update camera
		UpdateCamera();

		// Animate cubes (gentle bobbing and rotation)
		float time = (float)frame.TotalTime;
		for (int i < mCubeProxies.Count)
		{
			if (let proxy = mWorld.GetMesh(mCubeProxies[i]))
			{
				let gridX = i % 3;
				let gridZ = i / 3;
				let spacing = 2.0f;
				let offset = 2.0f;

				// Phase offset per cube
				let phase = (gridX + gridZ) * 0.5f;

				// Position with bobbing
				let baseY = 0.5f + Math.Sin(time * 2.0f + phase) * 0.15f;
				let position = Vector3(
					gridX * spacing - offset,
					baseY,
					gridZ * spacing - offset
				);

				// Rotation
				let rotY = time * (0.3f + i * 0.1f);
				let rotation = Matrix.CreateRotationY(rotY);
				let translation = Matrix.CreateTranslation(position);

				proxy.SetTransform(rotation * translation);
			}
		}

		// Animate point lights (orbit around center)
		for (int i < mPointLights.Count)
		{
			if (let light = mWorld.GetLight(mPointLights[i]))
			{
				float baseAngle = i * (Math.PI_f * 0.5f);
				float angle = baseAngle + time * 0.5f;
				float radius = 4.0f;

				light.Position = .(
					Math.Cos(angle) * radius,
					1.5f + Math.Sin(time * 2.0f + i) * 0.3f,
					Math.Sin(angle) * radius
				);
			}
		}

		// Periodic stats display
		mStatsTimer += (float)frame.DeltaTime;
		if (mStatsTimer >= StatsInterval)
		{
			mStatsTimer = 0;
			// Uncomment to see periodic stats:
			// PrintStats();
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

		// Build render graph using registered features
		if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
		{
			// Execute the render graph
			mRenderSystem.Execute(render.Encoder);
		}
		else
		{
			// Fallback: render a simple clear pass if render graph fails
			RenderFallback(render);
		}

		// End frame
		mRenderSystem.EndFrame();

		return true;
	}

	private void RenderFallback(RenderContext render)
	{
		// Simple fallback rendering when render graph isn't ready
		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = render.CurrentTextureView,
			ResolveTarget = null,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = .(0.1f, 0.12f, 0.18f, 1.0f)
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
		renderPass.End();
		delete renderPass;
	}

	protected override void OnFrameEnd()
	{
	}

	protected override void OnShutdown()
	{
		Console.WriteLine("\n=== Shutting Down ===");

		// Release mesh handles
		if (mCubeMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
		if (mPlaneMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);

		// Shutdown render system (handles feature cleanup)
		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Shutdown complete");
	}
}

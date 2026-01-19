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
	private ForwardTransparentFeature mTransparentFeature;
	private SkyFeature mSkyFeature;
	private ParticleFeature mParticleFeature;
	private DebugRenderFeature mDebugFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Particle emitters
	private ParticleEmitterProxyHandle mSmokeEmitter;
	private ParticleEmitterProxyHandle mFireEmitter;

	// Test objects
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;
	private List<MeshProxyHandle> mCubeProxies = new .() ~ delete _;
	private MeshProxyHandle mFloorProxy;
	private LightProxyHandle mSunLight;
	private List<LightProxyHandle> mPointLights = new .() ~ delete _;

	// Materials
	private MaterialInstance mCubeMaterial ~ delete _;
	private MaterialInstance mTransparentMaterial ~ delete _;

	// Camera mode
	private enum CameraMode { Orbital, Flythrough }
	private CameraMode mCameraMode = .Orbital;

	// Orbital camera control
	private float mOrbitalYaw = 0.5f;
	private float mOrbitalPitch = 0.4f;
	private float mOrbitalDistance = 12.0f;
	private Vector3 mOrbitalTarget = .(0, 0.5f, 0);

	// Flythrough camera control
	private Vector3 mFlyPosition = .(0, 5, 15);
	private float mFlyYaw = Math.PI_f;        // Start looking toward -Z (toward origin)
	private float mFlyPitch = -0.3f;          // Slightly looking down
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 15.0f;
	private float mCameraLookSpeed = 0.003f;

	// Shared camera state
	private Vector3 mCameraPosition;
	private Vector3 mCameraForward;

	// Sun light control
	private float mSunYaw = 0.5f;
	private float mSunPitch = -1.0f; // Pointing downward

	// Timing
	private float mDeltaTime = 0.016f;  // Cache delta time for input handling

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
		mView.FarPlane = 30.0f; // Reduced for better shadow map utilization
		Console.WriteLine("RenderView created");

		// Register render features
		RegisterFeatures();

		// Create test meshes
		CreateMeshes();

		// Create scene objects
		CreateSceneObjects();

		// Create lights
		CreateLights();

		// Create particle systems
		CreateParticles();

		// Set environment lighting
		mWorld.AmbientColor = .(0.02f, 0.02f, 0.03f);  // Slight blue tint
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("\n=== Initialization Complete ===");
		Console.WriteLine("Objects in world:");
		Console.WriteLine("  Meshes: {}", mWorld.MeshCount);
		Console.WriteLine("  Lights: {}", mWorld.LightCount);
		Console.WriteLine("  Particles: {}", mWorld.ParticleEmitterCount);
		Console.WriteLine("\nControls:");
		Console.WriteLine("  Tab: toggle camera mode (Orbital/Flythrough)");
		Console.WriteLine("  Arrow keys: rotate sun light");
		Console.WriteLine("  R: print render stats");
		Console.WriteLine("  C: print detailed culling info");
		Console.WriteLine("  H: toggle Hi-Z culling");
		Console.WriteLine("  K: toggle sky mode (Procedural/Solid Color)");
		Console.WriteLine("  P: toggle particle systems");
		Console.WriteLine("  ESC: exit");
		Console.WriteLine("\nOrbital Camera (default):");
		Console.WriteLine("  WASD: rotate around target");
		Console.WriteLine("  Q/E: zoom in/out");
		Console.WriteLine("\nFlythrough Camera:");
		Console.WriteLine("  Tab: toggle mouse capture");
		Console.WriteLine("  ` (backtick): return to Orbital mode");
		Console.WriteLine("  WASD: move forward/back/strafe");
		Console.WriteLine("  Q/E: move down/up");
		Console.WriteLine("  Mouse capture or Right-click + drag: look around");
		Console.WriteLine("  Shift: move faster\n");
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

		// Forward transparent (alpha-blended geometry)
		mTransparentFeature = new ForwardTransparentFeature();
		if (mRenderSystem.RegisterFeature(mTransparentFeature) case .Err)
			Console.WriteLine("Warning: Failed to register ForwardTransparentFeature");
		else
			Console.WriteLine("Registered: ForwardTransparentFeature");

		// Sky (procedural sky and IBL)
		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");
		else
			Console.WriteLine("Registered: SkyFeature");

		// Particles (GPU compute-driven particle systems)
		mParticleFeature = new ParticleFeature();
		if (mRenderSystem.RegisterFeature(mParticleFeature) case .Err)
			Console.WriteLine("Warning: Failed to register ParticleFeature");
		else
			Console.WriteLine("Registered: ParticleFeature");

		// Debug rendering (lines, shapes, text)
		mDebugFeature = new DebugRenderFeature();
		if (mRenderSystem.RegisterFeature(mDebugFeature) case .Err)
			Console.WriteLine("Warning: Failed to register DebugRenderFeature");
		else
			Console.WriteLine("Registered: DebugRenderFeature");

		// Final output (blits scene to swapchain)
		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");
		else
			Console.WriteLine("Registered: FinalOutputFeature");
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
		// Get default material for floor
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Create a colored material for cubes
		if (let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			mCubeMaterial = new MaterialInstance(baseMaterial);
			mCubeMaterial.SetColor("BaseColor", .(0.2f, 0.6f, 0.9f, 1.0f)); // Blue color

			// Create transparent material (red with 50% alpha)
			mTransparentMaterial = new MaterialInstance(baseMaterial);
			mTransparentMaterial.SetColor("BaseColor", .(0.9f, 0.2f, 0.2f, 0.5f)); // Red, 50% transparent
			mTransparentMaterial.BlendMode = .AlphaBlend;
		}

		// Create floor (white/default)
		mFloorProxy = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(mFloorProxy))
		{
			proxy.MeshHandle = mPlaneMeshHandle;
			proxy.Material = defaultMaterial;
			proxy.SetLocalBounds(BoundingBox(Vector3(-5, 0, -5), Vector3(5, 0.01f, 5)));
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}

		// Grid of cubes (commented out for shadow testing)
		/*
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
					proxy.Material = mCubeMaterial ?? defaultMaterial;
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
		*/

		// Single opaque cube at the center, sitting on the floor
		{
			let cubeProxy = mWorld.CreateMesh();
			if (let proxy = mWorld.GetMesh(cubeProxy))
			{
				proxy.MeshHandle = mCubeMeshHandle;
				proxy.Material = mCubeMaterial ?? defaultMaterial;
				proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));

				// Position cube at center, on the floor (Y=0.5 so bottom touches Y=0 floor)
				let position = Vector3(0, 0.5f, 0);
				proxy.SetTransformImmediate(Matrix.CreateTranslation(position));
				proxy.Flags = .DefaultOpaque;
			}
			mCubeProxies.Add(cubeProxy);
		}

		// Transparent cube next to the opaque cube
		{
			let transparentProxy = mWorld.CreateMesh();
			if (let proxy = mWorld.GetMesh(transparentProxy))
			{
				proxy.MeshHandle = mCubeMeshHandle;
				proxy.Material = mTransparentMaterial;
				proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));

				// Position slightly to the right and behind the opaque cube to test transparency
				let position = Vector3(1.5f, 0.5f, -1.0f);
				proxy.SetTransformImmediate(Matrix.CreateTranslation(position));
				proxy.Flags = .DefaultTransparent;
			}
			mCubeProxies.Add(transparentProxy);
		}

		Console.WriteLine("Created {} cube(s) (1 opaque, 1 transparent) and 1 floor", mCubeProxies.Count);
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
			light.Intensity = 2.0f;
		}
		Console.WriteLine("Sun light created");

		// Disable shadow rendering to isolate crash
		if (mForwardFeature?.ShadowRenderer != null)
		{
			mForwardFeature.ShadowRenderer.EnableShadows = true;
			Console.WriteLine("Shadow rendering DISABLED for crash isolation");
		}

		// Create colored point lights
		// Use Vector3 for normalized (0-1) color values
		Vector3[4] lightColors = .(
			.(1.0f, 0.3f, 0.2f),  // Red-orange
			.(0.2f, 1.0f, 0.3f),  // Green
			.(0.2f, 0.3f, 1.0f),  // Blue
			.(1.0f, 0.9f, 0.3f)   // Yellow
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
				lightColors[i],
				10.0f,  // Intensity
				4.0f   // Range
			);
			mPointLights.Add(pointLight);
		}
		Console.WriteLine("Created {} point lights", mPointLights.Count);
	}

	private void CreateParticles()
	{
		// Create smoke emitter (grey, rising slowly, fading out)
		mSmokeEmitter = mWorld.CreateParticleEmitter();
		if (let smoke = mWorld.GetParticleEmitter(mSmokeEmitter))
		{
			smoke.Position = .(-2.0f, 0.0f, 0.0f); // Left side of scene
			smoke.MaxParticles = 500;
			smoke.SpawnRate = 30.0f;
			smoke.ParticleLifetime = 4.0f;
			smoke.StartSize = .(0.2f, 0.2f);
			smoke.EndSize = .(0.8f, 0.8f);
			smoke.StartColor = .(0.5f, 0.5f, 0.5f, 0.6f); // Grey, semi-transparent
			smoke.EndColor = .(0.3f, 0.3f, 0.3f, 0.0f);   // Fade out
			smoke.InitialVelocity = .(0.0f, 1.5f, 0.0f);  // Rise slowly
			smoke.VelocityRandomness = .(0.3f, 0.2f, 0.3f);
			smoke.GravityMultiplier = -0.2f; // Slight upward drift
			smoke.Drag = 0.5f;
			smoke.BlendMode = .Alpha;
			smoke.IsEnabled = true;
			smoke.IsEmitting = true;
		}
		Console.WriteLine("Created smoke particle emitter");

		// Create fire emitter (orange/yellow, rising fast, bright)
		mFireEmitter = mWorld.CreateParticleEmitter();
		if (let fire = mWorld.GetParticleEmitter(mFireEmitter))
		{
			fire.Position = .(2.0f, 0.0f, 0.0f); // Right side of scene
			fire.MaxParticles = 300;
			fire.SpawnRate = 50.0f;
			fire.ParticleLifetime = 1.5f;
			fire.StartSize = .(0.15f, 0.15f);
			fire.EndSize = .(0.4f, 0.4f);
			fire.StartColor = .(1.0f, 0.8f, 0.2f, 1.0f);  // Bright yellow-orange
			fire.EndColor = .(1.0f, 0.2f, 0.0f, 0.0f);    // Red, fade out
			fire.InitialVelocity = .(0.0f, 3.0f, 0.0f);   // Rise quickly
			fire.VelocityRandomness = .(0.5f, 0.5f, 0.5f);
			fire.GravityMultiplier = -0.5f; // Strong upward
			fire.Drag = 0.3f;
			fire.BlendMode = .Additive;
			fire.IsEnabled = true;
			fire.IsEmitting = true;
		}
		Console.WriteLine("Created fire particle emitter");
	}

	private void UpdateCamera()
	{
		switch (mCameraMode)
		{
		case .Orbital:
			UpdateOrbitalCamera();
		case .Flythrough:
			UpdateFlythroughCamera();
		}

		// Update view
		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = mCameraForward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	private void UpdateOrbitalCamera()
	{
		// Calculate camera position from spherical coordinates around target
		float x = mOrbitalDistance * Math.Cos(mOrbitalPitch) * Math.Sin(mOrbitalYaw);
		float y = mOrbitalDistance * Math.Sin(mOrbitalPitch);
		float z = mOrbitalDistance * Math.Cos(mOrbitalPitch) * Math.Cos(mOrbitalYaw);

		mCameraPosition = mOrbitalTarget + Vector3(x, y, z);
		mCameraForward = Vector3.Normalize(mOrbitalTarget - mCameraPosition);
	}

	private void UpdateFlythroughCamera()
	{
		// Calculate forward direction from yaw/pitch
		float cosP = Math.Cos(mFlyPitch);
		mCameraForward = Vector3.Normalize(.(
			cosP * Math.Sin(mFlyYaw),
			Math.Sin(mFlyPitch),
			cosP * Math.Cos(mFlyYaw)
		));
		mCameraPosition = mFlyPosition;
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		// Tab toggles different things depending on mode
		if (keyboard.IsKeyPressed(.Tab))
		{
			if (mCameraMode == .Orbital)
			{
				// In orbital mode, Tab switches to flythrough
				mCameraMode = .Flythrough;
				Console.WriteLine("Camera Mode: Flythrough");
			}
			else
			{
				// In flythrough mode, Tab toggles mouse capture
				mMouseCaptured = !mMouseCaptured;
				mouse.RelativeMode = mMouseCaptured;
				mouse.Visible = !mMouseCaptured;
				Console.WriteLine("Mouse Capture: {}", mMouseCaptured ? "ON" : "OFF");
			}
		}

		// Backtick (`) to return to orbital mode from flythrough
		if (keyboard.IsKeyPressed(.Grave) && mCameraMode == .Flythrough)
		{
			mCameraMode = .Orbital;
			// Release mouse capture when switching modes
			if (mMouseCaptured)
			{
				mMouseCaptured = false;
				mouse.RelativeMode = false;
				mouse.Visible = true;
			}
			Console.WriteLine("Camera Mode: Orbital");
		}

		// Camera controls depend on mode
		switch (mCameraMode)
		{
		case .Orbital:
			HandleOrbitalInput(keyboard);
		case .Flythrough:
			HandleFlythroughInput(keyboard, mouse);
		}

		// Sun light rotation (Arrow keys)
		float lightRotSpeed = 0.03f;
		if (keyboard.IsKeyDown(.Left))
			mSunYaw -= lightRotSpeed;
		if (keyboard.IsKeyDown(.Right))
			mSunYaw += lightRotSpeed;
		if (keyboard.IsKeyDown(.Up))
			mSunPitch = Math.Clamp(mSunPitch + lightRotSpeed, -1.5f, -0.1f);
		if (keyboard.IsKeyDown(.Down))
			mSunPitch = Math.Clamp(mSunPitch - lightRotSpeed, -1.5f, -0.1f);

		// Toggle Hi-Z
		if (keyboard.IsKeyPressed(.H))
		{
			if (mDepthFeature != null)
			{
				mDepthFeature.EnableHiZ = !mDepthFeature.EnableHiZ;
				Console.WriteLine("Hi-Z Occlusion Culling: {}", mDepthFeature.EnableHiZ ? "ON" : "OFF");
			}
		}

		// Toggle sky mode (procedural vs solid color)
		if (keyboard.IsKeyPressed(.K))
		{
			if (mSkyFeature != null)
			{
				if (mSkyFeature.Mode == .Procedural)
				{
					mSkyFeature.Mode = .SolidColor;
					mSkyFeature.SolidColor = .(0.529f, 0.808f, 0.922f); // Sky blue
					Console.WriteLine("Sky Mode: Solid Color (Sky Blue)");
				}
				else
				{
					mSkyFeature.Mode = .Procedural;
					Console.WriteLine("Sky Mode: Procedural");
				}
			}
		}

		// Toggle particle systems
		if (keyboard.IsKeyPressed(.P))
		{
			// Toggle smoke emitter
			if (let smoke = mWorld.GetParticleEmitter(mSmokeEmitter))
			{
				smoke.IsEmitting = !smoke.IsEmitting;
			}
			// Toggle fire emitter
			if (let fire = mWorld.GetParticleEmitter(mFireEmitter))
			{
				fire.IsEmitting = !fire.IsEmitting;
			}
			let isEmitting = mWorld.GetParticleEmitter(mSmokeEmitter)?.IsEmitting ?? false;
			Console.WriteLine("Particle Systems: {}", isEmitting ? "ON" : "OFF");
		}

		// Stats
		if (keyboard.IsKeyPressed(.R))
			PrintStats();

		// Detailed culling info
		if (keyboard.IsKeyPressed(.C))
			PrintDetailedCulling();
	}

	private void HandleOrbitalInput(Sedulous.Shell.Input.IKeyboard keyboard)
	{
		// Camera rotation (WASD)
		float rotSpeed = 0.02f;
		if (keyboard.IsKeyDown(.A))
			mOrbitalYaw -= rotSpeed;
		if (keyboard.IsKeyDown(.D))
			mOrbitalYaw += rotSpeed;
		if (keyboard.IsKeyDown(.W))
			mOrbitalPitch = Math.Clamp(mOrbitalPitch + rotSpeed, -1.4f, 1.4f);
		if (keyboard.IsKeyDown(.S))
			mOrbitalPitch = Math.Clamp(mOrbitalPitch - rotSpeed, -1.4f, 1.4f);

		// Camera zoom (Q/E)
		if (keyboard.IsKeyDown(.Q))
			mOrbitalDistance = Math.Clamp(mOrbitalDistance - 0.1f, 2.0f, 25.0f);
		if (keyboard.IsKeyDown(.E))
			mOrbitalDistance = Math.Clamp(mOrbitalDistance + 0.1f, 2.0f, 25.0f);
	}

	private void HandleFlythroughInput(Sedulous.Shell.Input.IKeyboard keyboard, Sedulous.Shell.Input.IMouse mouse)
	{
		// Mouse look (when captured or right-click held)
		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mFlyYaw -= mouse.DeltaX * mCameraLookSpeed;
			mFlyPitch -= mouse.DeltaY * mCameraLookSpeed;
			mFlyPitch = Math.Clamp(mFlyPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
		}

		// Calculate movement vectors
		Vector3 forward = mCameraForward;
		Vector3 right = Vector3.Normalize(Vector3.Cross(forward, .(0, 1, 0)));
		Vector3 up = .(0, 1, 0);

		float speed = mCameraMoveSpeed * mDeltaTime;

		// Shift doubles speed
		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
			speed *= 2.0f;

		// WASD movement
		if (keyboard.IsKeyDown(.W))
			mFlyPosition = mFlyPosition + forward * speed;
		if (keyboard.IsKeyDown(.S))
			mFlyPosition = mFlyPosition - forward * speed;
		if (keyboard.IsKeyDown(.A))
			mFlyPosition = mFlyPosition - right * speed;
		if (keyboard.IsKeyDown(.D))
			mFlyPosition = mFlyPosition + right * speed;

		// Q/E for up/down
		if (keyboard.IsKeyDown(.Q))
			mFlyPosition = mFlyPosition - up * speed;
		if (keyboard.IsKeyDown(.E))
			mFlyPosition = mFlyPosition + up * speed;
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
		{
			Console.WriteLine("Hi-Z Culling: {}", mDepthFeature.EnableHiZ ? "ON" : "OFF");

			// Print visibility stats
			let visStats = mDepthFeature.Visibility.Stats;
			Console.WriteLine("\n--- Visibility Stats ---");
			Console.WriteLine("Visible Meshes: {} / {}", visStats.VisibleMeshCount, visStats.TotalMeshCount);
			Console.WriteLine("Cull Percentage: {:.1}%", visStats.MeshCullPercentage);
			Console.WriteLine("Frustum Tests: {}", visStats.CullStats.TotalTests);
			Console.WriteLine("Frustum Passed: {}", visStats.CullStats.VisibleCount);
			Console.WriteLine("Frustum Culled: {}", visStats.CullStats.CulledCount);
		}
		Console.WriteLine("");
	}

	private void PrintDetailedCulling()
	{
		Console.WriteLine("\n=== Per-Mesh Culling Details ===");

		// Get the culler from depth feature
		if (mDepthFeature == null)
			return;

		let culler = mDepthFeature.Visibility.Culler;

		// Manually test each mesh and report
		Console.WriteLine("Testing {} meshes against frustum:", mWorld.MeshCount);
		Console.WriteLine("Camera pos: ({}, {}, {})", mCameraPosition.X, mCameraPosition.Y, mCameraPosition.Z);

		int visibleCount = 0;
		int culledCount = 0;

		// Test floor
		if (let proxy = mWorld.GetMesh(mFloorProxy))
		{
			let bounds = proxy.WorldBounds;
			let local = proxy.LocalBounds;
			let isVisible = culler.IsVisible(bounds);
			Console.WriteLine("  Floor:");
			Console.WriteLine("    Local:  min=({}, {}, {}) max=({}, {}, {})",
				local.Min.X, local.Min.Y, local.Min.Z,
				local.Max.X, local.Max.Y, local.Max.Z);
			Console.WriteLine("    World:  min=({}, {}, {}) max=({}, {}, {})",
				bounds.Min.X, bounds.Min.Y, bounds.Min.Z,
				bounds.Max.X, bounds.Max.Y, bounds.Max.Z);
			Console.WriteLine("    Visible: {}", isVisible);
			if (isVisible) visibleCount++; else culledCount++;
		}

		// Test cubes
		for (int i < mCubeProxies.Count)
		{
			if (let proxy = mWorld.GetMesh(mCubeProxies[i]))
			{
				let bounds = proxy.WorldBounds;
				let local = proxy.LocalBounds;
				let worldPos = proxy.WorldMatrix.Translation;
				let isVisible = culler.IsVisible(bounds);
				Console.WriteLine("  Cube {}:", i);
				Console.WriteLine("    Pos:    ({}, {}, {})", worldPos.X, worldPos.Y, worldPos.Z);
				Console.WriteLine("    Local:  min=({}, {}, {}) max=({}, {}, {})",
					local.Min.X, local.Min.Y, local.Min.Z,
					local.Max.X, local.Max.Y, local.Max.Z);
				Console.WriteLine("    World:  min=({}, {}, {}) max=({}, {}, {})",
					bounds.Min.X, bounds.Min.Y, bounds.Min.Z,
					bounds.Max.X, bounds.Max.Y, bounds.Max.Z);
				Console.WriteLine("    Visible: {}", isVisible);
				if (isVisible) visibleCount++; else culledCount++;
			}
		}

		Console.WriteLine("Total: {} visible, {} culled", visibleCount, culledCount);
		Console.WriteLine("");
	}

	private void UpdateSunLight()
	{
		if (let light = mWorld.GetLight(mSunLight))
		{
			// Calculate sun direction from spherical coordinates
			float x = Math.Cos(mSunPitch) * Math.Sin(mSunYaw);
			float y = Math.Sin(mSunPitch);
			float z = Math.Cos(mSunPitch) * Math.Cos(mSunYaw);
			light.Direction = Vector3.Normalize(.(x, y, z));
		}
	}

	private void DrawDebugLights()
	{
		if (mDebugFeature == null)
			return;

		// Clear previous frame's debug primitives
		mDebugFeature.BeginFrame();

		// Draw directional light direction
		if (let light = mWorld.GetLight(mSunLight))
		{
			// Draw from a point above the scene, showing the light direction
			Vector3 sunOrigin = .(0, 8, 0);
			Vector3 sunEnd = sunOrigin + light.Direction * 5.0f;

			// Arrow showing light direction (yellow)
			mDebugFeature.AddArrow(sunOrigin, sunEnd, Color.Yellow, 0.3f, .Overlay);

			// Add a small sun icon (circle)
			mDebugFeature.AddSphere(sunOrigin, 0.3f, Color.Yellow, 8, .Overlay);
		}

		// Draw point light positions
		Color[4] lightColors = .(
			.(255, 77, 51, 255),   // Red-orange
			.(51, 255, 77, 255),   // Green
			.(51, 77, 255, 255),   // Blue
			.(255, 230, 77, 255)   // Yellow
		);

		for (int i < mPointLights.Count)
		{
			if (let light = mWorld.GetLight(mPointLights[i]))
			{
				// Draw sphere at light position showing its range
				mDebugFeature.AddSphere(light.Position, 0.2f, lightColors[i], 8, .Overlay);

				// Draw cross at light position
				mDebugFeature.AddCross(light.Position, 0.5f, lightColors[i], .Overlay);

				// Draw range indicator (faint circle on XZ plane)
				mDebugFeature.AddCircle(
					.(light.Position.X, 0.01f, light.Position.Z),
					light.Range,
					.(0, 1, 0),
					Color(lightColors[i].R, lightColors[i].G, lightColors[i].B, 64),
					24,
					.DepthTest
				);
			}
		}

		// Draw coordinate axes at origin
		mDebugFeature.AddAxes(.(0, 0.01f, 0), 1.0f, .DepthTest);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		// Cache delta time for input handling
		mDeltaTime = (float)frame.DeltaTime;

		// Update camera
		UpdateCamera();

		// Update sun light direction
		UpdateSunLight();
		float time = (float)frame.TotalTime;

		// Cube animation disabled - static single cube for shadow testing
		/*
		// Animate cubes (gentle bobbing and rotation)
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
		*/

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

		// Draw debug visualization for lights
		DrawDebugLights();
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		// Begin frame
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		// Set swapchain for final output (FinalOutputFeature will use this in AddPasses)
		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

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

		// Build and execute render graph
		// FinalOutput pass is now integrated - automatic barriers handle all transitions
		if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
		{
			mRenderSystem.Execute(render.Encoder);
		}

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

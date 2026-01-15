namespace RendererNGSandbox;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RHI.Vulkan;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Engine.Runtime;
using Sedulous.RendererNG;
using SampleFramework;

/// Test uniform data structure for transient buffer tests.
struct TestUniformData
{
	public float[16] Matrix;
	public float[4] Color;
}

/// Sandbox application for testing Sedulous.RendererNG features.
/// This project is used to validate renderer features as they are developed.
class RendererNGSandboxApp : Application
{
	// RendererNG systems
	private Renderer mRenderer ~ delete _;
	private RenderWorld mRenderWorld ~ delete _;

	// Test resources (will grow as we implement more features)
	private bool mInitialized = false;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize()
	{
		Console.WriteLine("=== RendererNG Sandbox ===");
		Console.WriteLine("Testing Sedulous.RendererNG features\n");

		// Initialize the renderer
		mRenderer = new Renderer();
		if (mRenderer.Initialize(Device, "shaders") case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize renderer");
			Exit();
			return;
		}
		Console.WriteLine("Renderer initialized");

		// Create a render world
		mRenderWorld = mRenderer.CreateRenderWorld();
		Console.WriteLine("RenderWorld created");

		// Run tests for implemented features
		TestResourcePools();
		TestTransientBuffers();
		TestProxySystem();
		TestRenderFrameAndViews();

		mInitialized = true;
		Console.WriteLine("\n=== Initialization Complete ===\n");
	}

	/// Tests the resource pool system (Phase 1.2)
	private void TestResourcePools()
	{
		Console.WriteLine("\n--- Testing Resource Pools ---");

		let resources = mRenderer.Resources;

		// Test buffer creation
		Console.WriteLine("Creating test buffer...");
		let bufferHandle = resources.CreateBuffer(1024, .Vertex | .CopyDst, "TestVertexBuffer");
		if (bufferHandle.HasValidIndex)
		{
			Console.WriteLine("  Buffer created: index={0}, gen={1}", bufferHandle.Index, bufferHandle.Generation);
			Console.WriteLine("  Size: {0} bytes", resources.Buffers.GetSize(bufferHandle));
			Console.WriteLine("  IsValid: {0}", resources.Buffers.IsValid(bufferHandle));
		}
		else
		{
			Console.WriteLine("  ERROR: Failed to create buffer");
		}

		// Test texture creation
		Console.WriteLine("Creating test texture...");
		let textureHandle = resources.CreateTexture2D(256, 256, .RGBA8Unorm, .Sampled | .CopyDst, 1, "TestTexture");
		if (textureHandle.HasValidIndex)
		{
			Console.WriteLine("  Texture created: index={0}, gen={1}", textureHandle.Index, textureHandle.Generation);
			let (w, h, d) = resources.Textures.GetDimensions(textureHandle);
			Console.WriteLine("  Dimensions: {0}x{1}", w, h);
			Console.WriteLine("  Format: {0}", resources.Textures.GetFormat(textureHandle));
			Console.WriteLine("  IsValid: {0}", resources.Textures.IsValid(textureHandle));
		}
		else
		{
			Console.WriteLine("  ERROR: Failed to create texture");
		}

		// Print pool stats
		let stats = resources.GetStats();
		Console.WriteLine("\nResource Pool Stats:");
		Console.WriteLine("  Buffers: {0} allocated, {1} slots, {2} free", stats.AllocatedBuffers, stats.TotalBufferSlots, stats.FreeBufferSlots);
		Console.WriteLine("  Textures: {0} allocated, {1} slots, {2} free", stats.AllocatedTextures, stats.TotalTextureSlots, stats.FreeTextureSlots);

		// Test handle release
		Console.WriteLine("\nTesting handle release...");
		resources.ReleaseBuffer(bufferHandle);
		Console.WriteLine("  Buffer released, IsValid after release: {0}", resources.Buffers.IsValid(bufferHandle));

		resources.ReleaseTexture(textureHandle);
		Console.WriteLine("  Texture released, IsValid after release: {0}", resources.Textures.IsValid(textureHandle));

		// Stats after release
		let statsAfter = resources.GetStats();
		Console.WriteLine("\nStats after release:");
		Console.WriteLine("  Buffers: {0} allocated, {1} free, {2} pending deletions",
			statsAfter.AllocatedBuffers, statsAfter.FreeBufferSlots, statsAfter.PendingDeletions);
		Console.WriteLine("  Textures: {0} allocated, {1} free",
			statsAfter.AllocatedTextures, statsAfter.FreeTextureSlots);

		Console.WriteLine("\nResource Pool tests complete!");
	}

	/// Tests the transient buffer pool system (Phase 1.3)
	private void TestTransientBuffers()
	{
		Console.WriteLine("\n--- Testing Transient Buffer Pool ---");

		let transient = mRenderer.TransientBuffers;

		// Simulate a frame begin (frame 0)
		transient.BeginFrame(0);
		Console.WriteLine("Frame 0 started");

		// Test vertex allocation
		Console.WriteLine("\nTesting vertex allocation...");
		float[12] vertices = .(
			-0.5f, -0.5f, 0.0f,
			 0.5f, -0.5f, 0.0f,
			 0.5f,  0.5f, 0.0f,
			-0.5f,  0.5f, 0.0f
		);
		let vertexAlloc = transient.AllocateVertices<float>(vertices);
		if (vertexAlloc.IsValid)
		{
			Console.WriteLine("  Vertex allocation: offset={0}, size={1}", vertexAlloc.Offset, vertexAlloc.Size);
			Console.WriteLine("  Buffer valid: {0}", vertexAlloc.Buffer != null);
		}
		else
		{
			Console.WriteLine("  ERROR: Vertex allocation failed");
		}

		// Test index allocation
		Console.WriteLine("\nTesting index allocation...");
		uint16[6] indices = .(0, 1, 2, 2, 3, 0);
		let indexAlloc = transient.AllocateIndices<uint16>(indices);
		if (indexAlloc.IsValid)
		{
			Console.WriteLine("  Index allocation: offset={0}, size={1}", indexAlloc.Offset, indexAlloc.Size);
		}
		else
		{
			Console.WriteLine("  ERROR: Index allocation failed");
		}

		// Test uniform allocation
		Console.WriteLine("\nTesting uniform allocation...");
		let uniformAlloc = transient.AllocateUniform<TestUniformData>();
		if (uniformAlloc.IsValid)
		{
			Console.WriteLine("  Uniform allocation: offset={0}, size={1}", uniformAlloc.Offset, uniformAlloc.Size);
			Console.WriteLine("  Offset aligned to 256: {0}", (uniformAlloc.Offset % 256) == 0);
		}
		else
		{
			Console.WriteLine("  ERROR: Uniform allocation failed");
		}

		// Print stats
		let stats = transient.GetStats();
		Console.WriteLine("\nTransient Buffer Stats (Frame 0):");
		Console.WriteLine("  Vertex: {0}/{1} bytes ({2:F1}%)", stats.VertexBytesUsed, stats.VertexBytesTotal, stats.VertexUsagePercent);
		Console.WriteLine("  Index: {0}/{1} bytes ({2:F1}%)", stats.IndexBytesUsed, stats.IndexBytesTotal, stats.IndexUsagePercent);
		Console.WriteLine("  Uniform: {0}/{1} bytes ({2:F1}%)", stats.UniformBytesUsed, stats.UniformBytesTotal, stats.UniformUsagePercent);

		// Test frame reset
		Console.WriteLine("\nTesting frame reset (Frame 1)...");
		transient.BeginFrame(1);
		let statsAfterReset = transient.GetStats();
		Console.WriteLine("  Vertex after reset: {0} bytes", statsAfterReset.VertexBytesUsed);
		Console.WriteLine("  Index after reset: {0} bytes", statsAfterReset.IndexBytesUsed);
		Console.WriteLine("  Uniform after reset: {0} bytes", statsAfterReset.UniformBytesUsed);

		// Verify all are zero
		let allReset = statsAfterReset.VertexBytesUsed == 0 &&
					   statsAfterReset.IndexBytesUsed == 0 &&
					   statsAfterReset.UniformBytesUsed == 0;
		Console.WriteLine("  All buffers reset: {0}", allReset);

		Console.WriteLine("\nTransient Buffer Pool tests complete!");
	}

	/// Tests the proxy system (Phase 1.4)
	private void TestProxySystem()
	{
		Console.WriteLine("\n--- Testing Proxy System ---");

		// Test ProxyHandle basics
		Console.WriteLine("\nTesting ProxyHandle<T>...");
		let invalidHandle = ProxyHandle<StaticMeshProxy>.Invalid;
		Console.WriteLine("  Invalid handle: index={0}, gen={1}, HasValidIndex={2}",
			invalidHandle.Index, invalidHandle.Generation, invalidHandle.HasValidIndex);

		// Test RenderWorld static mesh proxies
		Console.WriteLine("\nTesting StaticMeshProxy...");
		let meshHandle1 = mRenderWorld.CreateStaticMesh();
		Console.WriteLine("  Created mesh1: index={0}, gen={1}", meshHandle1.Index, meshHandle1.Generation);

		if (let mesh1 = mRenderWorld.GetStaticMesh(meshHandle1))
		{
			mesh1.Transform = Matrix.CreateTranslation(1.0f, 0.0f, 0.0f);
			mesh1.Flags = .Visible | .CastShadow;
			Console.WriteLine("  Modified mesh1: Position=({0}, {1}, {2})",
				mesh1.Transform.M14, mesh1.Transform.M24, mesh1.Transform.M34);
		}

		// Create second mesh with initial data
		var initialMesh = StaticMeshProxy.Default;
		initialMesh.Transform = Matrix.CreateTranslation(5.0f, 0.0f, 0.0f);
		let meshHandle2 = mRenderWorld.CreateStaticMesh(initialMesh);
		Console.WriteLine("  Created mesh2 with initial data: index={0}", meshHandle2.Index);

		Console.WriteLine("  Static mesh count: {0}", mRenderWorld.StaticMeshCount);

		// Test ForEach iteration
		Console.WriteLine("\nTesting ForEach iteration...");
		int32 meshCount = 0;
		mRenderWorld.ForEachStaticMesh(scope [&meshCount](handle, proxy) => {
			Console.WriteLine("  Iterating mesh: index={0}, visible={1}",
				handle.Index, (proxy.Flags & .Visible) != 0);
			meshCount++;
		});
		Console.WriteLine("  Iterated {0} meshes", meshCount);

		// Test light proxies
		Console.WriteLine("\nTesting LightProxy...");
		let lightHandle = mRenderWorld.CreateLight(LightProxy.DefaultDirectional);
		if (let light = mRenderWorld.GetLight(lightHandle))
		{
			light.Color = .(1.0f, 0.9f, 0.8f);
			light.Intensity = 2.5f;
			Console.WriteLine("  Created directional light: color=({0}, {1}, {2}), intensity={3}",
				light.Color.X, light.Color.Y, light.Color.Z, light.Intensity);
		}

		let pointLightHandle = mRenderWorld.CreateLight(LightProxy.DefaultPoint);
		if (let pointLight = mRenderWorld.GetLight(pointLightHandle))
		{
			pointLight.Position = .(3.0f, 2.0f, 0.0f);
			pointLight.Range = 15.0f;
			Console.WriteLine("  Created point light: range={0}", pointLight.Range);
		}
		Console.WriteLine("  Light count: {0}", mRenderWorld.LightCount);

		// Test camera proxies
		Console.WriteLine("\nTesting CameraProxy...");
		let cameraHandle = mRenderWorld.CreateCamera(CameraProxy.DefaultPerspective);
		if (let camera = mRenderWorld.GetCamera(cameraHandle))
		{
			camera.Position = .(0, 5, 10);
			camera.Forward = Vector3.Normalize(.(0, -0.5f, -1.0f));
			Console.WriteLine("  Created camera: pos=({0}, {1}, {2}), fov={3}",
				camera.Position.X, camera.Position.Y, camera.Position.Z,
				camera.FieldOfView * (180.0f / Math.PI_f));
		}
		Console.WriteLine("  Camera count: {0}", mRenderWorld.CameraCount);

		// Test handle destruction and reuse
		Console.WriteLine("\nTesting handle destruction and generation...");
		let gen1 = meshHandle1.Generation;
		mRenderWorld.DestroyStaticMesh(meshHandle1);
		Console.WriteLine("  Destroyed mesh1, count now: {0}", mRenderWorld.StaticMeshCount);

		// Verify old handle is now invalid
		let oldMesh = mRenderWorld.GetStaticMesh(meshHandle1);
		Console.WriteLine("  Old handle valid: {0}", oldMesh != null);

		// Create new mesh - should reuse slot but with new generation
		let meshHandle3 = mRenderWorld.CreateStaticMesh();
		Console.WriteLine("  Created mesh3: index={0}, gen={1}", meshHandle3.Index, meshHandle3.Generation);
		Console.WriteLine("  Slot reused: {0}, generation incremented: {1}",
			meshHandle3.Index == meshHandle1.Index,
			meshHandle3.Generation > gen1);

		// Test particle emitter proxy
		Console.WriteLine("\nTesting ParticleEmitterProxy...");
		let emitterHandle = mRenderWorld.CreateParticleEmitter(ParticleEmitterProxy.Default);
		if (let emitter = mRenderWorld.GetParticleEmitter(emitterHandle))
		{
			emitter.EmissionRate = 500.0f;
			emitter.MaxParticles = 5000;
			Console.WriteLine("  Created emitter: rate={0}, max={1}", emitter.EmissionRate, emitter.MaxParticles);
		}
		Console.WriteLine("  Particle emitter count: {0}", mRenderWorld.ParticleEmitterCount);

		// Test sprite proxy
		Console.WriteLine("\nTesting SpriteProxy...");
		let spriteHandle = mRenderWorld.CreateSprite(SpriteProxy.Default);
		if (let sprite = mRenderWorld.GetSprite(spriteHandle))
		{
			sprite.Position = .(2.0f, 1.0f, 0.0f);
			sprite.Size = .(1.5f, 1.5f);
			Console.WriteLine("  Created sprite: pos=({0}, {1}, {2}), size=({3}, {4})",
				sprite.Position.X, sprite.Position.Y, sprite.Position.Z,
				sprite.Size.X, sprite.Size.Y);
		}
		Console.WriteLine("  Sprite count: {0}", mRenderWorld.SpriteCount);

		// Test force field proxy
		Console.WriteLine("\nTesting ForceFieldProxy...");
		let windHandle = mRenderWorld.CreateForceField(ForceFieldProxy.DefaultWind);
		if (let wind = mRenderWorld.GetForceField(windHandle))
		{
			wind.Strength = 10.0f;
			wind.Direction = .(1, 0, 0);
			Console.WriteLine("  Created wind force: strength={0}, dir=({1}, {2}, {3})",
				wind.Strength, wind.Direction.X, wind.Direction.Y, wind.Direction.Z);
		}
		Console.WriteLine("  Force field count: {0}", mRenderWorld.ForceFieldCount);

		// Summary
		Console.WriteLine("\nRenderWorld Summary:");
		Console.WriteLine("  Static Meshes: {0}", mRenderWorld.StaticMeshCount);
		Console.WriteLine("  Skinned Meshes: {0}", mRenderWorld.SkinnedMeshCount);
		Console.WriteLine("  Lights: {0}", mRenderWorld.LightCount);
		Console.WriteLine("  Cameras: {0}", mRenderWorld.CameraCount);
		Console.WriteLine("  Particle Emitters: {0}", mRenderWorld.ParticleEmitterCount);
		Console.WriteLine("  Sprites: {0}", mRenderWorld.SpriteCount);
		Console.WriteLine("  Force Fields: {0}", mRenderWorld.ForceFieldCount);

		Console.WriteLine("\nProxy System tests complete!");
	}

	/// Tests the RenderFrame and RenderView system (Phase 1.5)
	private void TestRenderFrameAndViews()
	{
		Console.WriteLine("\n--- Testing RenderFrame and RenderView ---");

		// Create a RenderFrame
		let frame = new RenderFrame();
		defer delete frame;

		// Test frame initialization
		Console.WriteLine("\nTesting RenderFrame...");
		frame.Begin(0, 0.016f, 1.5f);
		Console.WriteLine("  Frame initialized: index={0}, deltaTime={1}, totalTime={2}",
			frame.FrameIndex, frame.DeltaTime, frame.TotalTime);

		// Test creating camera views using factory methods
		Console.WriteLine("\nTesting RenderView factory methods...");

		// Create a perspective camera view
		let mainCamera = RenderView.CreateCamera(
			"MainCamera",
			.(0, 5, 10),           // position
			.(0, -0.3f, -1),       // forward (looking slightly down)
			.(0, 1, 0),            // up
			Math.PI_f / 4.0f,      // 45 degree FOV
			16.0f / 9.0f,          // aspect ratio
			0.1f,                  // near
			1000.0f,               // far
			1920, 1080             // viewport
		);
		defer delete mainCamera;

		Console.WriteLine("  Created MainCamera:");
		Console.WriteLine("    Position: ({0}, {1}, {2})",
			mainCamera.Position.X, mainCamera.Position.Y, mainCamera.Position.Z);
		Console.WriteLine("    Forward: ({0:F2}, {1:F2}, {2:F2})",
			mainCamera.Forward.X, mainCamera.Forward.Y, mainCamera.Forward.Z);
		Console.WriteLine("    Viewport: {0}x{1}", mainCamera.ViewportWidth, mainCamera.ViewportHeight);
		Console.WriteLine("    IsEnabled: {0}", mainCamera.IsEnabled);

		// Check matrices are computed
		let vp = mainCamera.ViewProjectionMatrix;
		Console.WriteLine("    ViewProjection computed: {0}", vp.M11 != 0 || vp.M22 != 0);

		// Add view to frame
		let slot = frame.AddView(mainCamera);
		Console.WriteLine("    Added to frame at slot: {0}", slot);
		Console.WriteLine("    Frame view count: {0}", frame.ViewCount);
		Console.WriteLine("    MainView matches: {0}", frame.MainView == mainCamera);

		// Test creating view from CameraProxy
		Console.WriteLine("\nTesting RenderView from CameraProxy...");
		let cameraHandle = mRenderWorld.CreateCamera(CameraProxy.DefaultPerspective);
		if (let cameraProxy = mRenderWorld.GetCamera(cameraHandle))
		{
			cameraProxy.Position = .(5, 3, 8);
			cameraProxy.Forward = Vector3.Normalize(.(-1, -0.2f, -1));
			cameraProxy.Up = .(0, 1, 0);
			cameraProxy.Right = Vector3.Normalize(Vector3.Cross(cameraProxy.Forward, cameraProxy.Up));

			let proxyView = RenderView.CreateFromCameraProxy(cameraProxy, 1920, 1080);
			defer delete proxyView;

			Console.WriteLine("  Created view from CameraProxy:");
			Console.WriteLine("    Position: ({0}, {1}, {2})",
				proxyView.Position.X, proxyView.Position.Y, proxyView.Position.Z);
			Console.WriteLine("    Type: {0}", proxyView.Type);

			let slot2 = frame.AddView(proxyView);
			Console.WriteLine("    Added to frame at slot: {0}", slot2);
		}

		// Test frustum planes
		Console.WriteLine("\nTesting frustum plane extraction...");
		Console.WriteLine("  Frustum planes extracted (6 planes):");
		for (int i = 0; i < 6; i++)
		{
			let plane = mainCamera.FrustumPlanes[i];
			String[6] planeNames = .("Left", "Right", "Bottom", "Top", "Near", "Far");
			Console.WriteLine("    {0}: normal=({1:F2}, {2:F2}, {3:F2}), d={4:F2}",
				planeNames[i], plane.Normal.X, plane.Normal.Y, plane.Normal.Z, plane.D);
		}

		// Test shadow cascade view
		Console.WriteLine("\nTesting shadow cascade view...");
		let lightDir = Vector3.Normalize(.(0.5f, -1, 0.3f));
		let shadowViewMat = Matrix.CreateLookAt(.(0, 100, 0), .(0, 0, 0), .(0, 0, 1));
		let shadowProjMat = Matrix.CreateOrthographic(100, 100, 0.1f, 200);

		let shadowView = RenderView.CreateShadowCascade(0, lightDir, shadowViewMat, shadowProjMat, 2048);
		defer delete shadowView;

		Console.WriteLine("  Created shadow cascade view:");
		Console.WriteLine("    Type: {0}", shadowView.Type);
		Console.WriteLine("    CascadeIndex: {0}", shadowView.CascadeIndex);
		Console.WriteLine("    Priority: {0}", shadowView.Priority);
		Console.WriteLine("    IsDepthOnly: {0}", shadowView.IsDepthOnly);
		Console.WriteLine("    Resolution: {0}x{1}", shadowView.ViewportWidth, shadowView.ViewportHeight);

		let shadowSlot = frame.AddShadowView(shadowView);
		Console.WriteLine("    Added as shadow view at slot: {0}", shadowSlot);
		Console.WriteLine("    Frame shadow view count: {0}", frame.ShadowViewCount);

		// Test previous transform saving
		Console.WriteLine("\nTesting motion vector support...");
		mainCamera.SavePreviousTransform();
		let prevVP = mainCamera.PreviousViewProjectionMatrix;
		Console.WriteLine("  PreviousViewProjection saved: {0}", prevVP.M11 != 0 || prevVP.M22 != 0);

		// Test frame end and reset
		Console.WriteLine("\nTesting frame lifecycle...");
		frame.End();
		Console.WriteLine("  Frame ended");

		// Begin new frame
		frame.Begin(1, 0.016f, 1.516f);
		Console.WriteLine("  New frame started: index={0}, views cleared: {1}",
			frame.FrameIndex, frame.ViewCount == 0);

		Console.WriteLine("\nRenderFrame and RenderView tests complete!");
	}

	protected override void OnInput()
	{
		if (Shell.InputManager.Keyboard.IsKeyPressed(.Escape))
			Exit();

		// R key to print render stats
		if (Shell.InputManager.Keyboard.IsKeyPressed(.R))
		{
			let stats = mRenderer.Stats;
			Console.WriteLine("=== Render Stats ===");
			Console.WriteLine("Draw Calls: {0}", stats.DrawCalls);
			Console.WriteLine("Triangles: {0}", stats.Triangles);
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		if (!mInitialized)
			return;

		// Begin renderer frame
		mRenderer.BeginFrame((uint32)frame.FrameIndex, frame.DeltaTime, frame.TotalTime);
	}

	protected override void OnRender(IRenderPassEncoder renderPass, FrameContext frame)
	{
		if (!mInitialized)
			return;

		// For now, just clear the screen
		// As we implement more features, we'll add actual rendering here
	}

	protected override void OnFrameEnd()
	{
		if (!mInitialized)
			return;

		// End renderer frame
		mRenderer.EndFrame();
	}

	protected override void OnShutdown()
	{
		Console.WriteLine("\n=== Shutting Down ===");

		if (mRenderer != null)
			mRenderer.Shutdown();

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
			Title = "RendererNG Sandbox",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f)
		};

		let app = scope RendererNGSandboxApp(shell, device, backend);
		return app.Run(settings);
	}
}

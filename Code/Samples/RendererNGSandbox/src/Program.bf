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

namespace RendererSandbox;

using System;
using System.Diagnostics;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Runtime.Client;
using Sedulous.Renderer;
using Sedulous.Profiler;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;

/// Renderer sandbox — grows with each migration phase.
/// Phase 2: Depth prepass with mesh scene.
/// WASD/QE: move, Right-click: look, P: profiling stats, ESC: exit
class RendererSandboxApp : Application
{
	private RenderSystem mRenderSystem;
	private RenderWorld mWorld;
	private RenderView mView;

	// Mesh handles
	private GPUMeshHandle mSphereMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;

	// Camera
	private Vector3 mCameraPosition = .(0, 2, 8);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.15f;
	private bool mMouseCaptured = false;

	// Init timing
	private double mInitTimeMs;
	private bool mInitTimeCaptured;

	// Frame stats
	private float[60] mFrameTimes;
	private int32 mFrameTimeIndex;

	public this() : base()
	{
	}

	protected override void OnInitialize(Sedulous.Runtime.Context context)
	{
		let timer = scope Stopwatch();
		timer.Start();

		mRenderSystem = new RenderSystem();

		// Register features
		mRenderSystem.RegisterFeature(new DepthPrepassFeature());
		mRenderSystem.RegisterFeature(new ForwardOpaqueFeature());

		if (mRenderSystem.Initialize(mDevice,
			scope StringView[](scope $"{AssetDirectory}/Render/Shaders")) case .Err)
		{
			Console.WriteLine("ERROR: RenderSystem.Initialize failed");
			return;
		}

		// Create world and set it active
		mWorld = new RenderWorld();
		mRenderSystem.SetActiveWorld(mWorld);

		// Create view
		mView = new RenderView();
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 100.0f;

		// Create scene
		CreateScene();

		timer.Stop();
		mInitTimeMs = timer.ElapsedMilliseconds;
		mInitTimeCaptured = true;

		Console.WriteLine("Renderer Sandbox initialized in {:.1}ms", mInitTimeMs);
		Console.WriteLine("  WASD/QE: move, Right-click+drag: look");
		Console.WriteLine("  P: profiling stats, ESC: exit");
	}

	private void CreateScene()
	{
		let defaultMat = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Create a sphere mesh
		let sphereMesh = MeshBuilder.CreateSphere(0.5f, 32, 16);
		if (mRenderSystem.ResourceManager.UploadMesh(sphereMesh) case .Ok(let handle))
			mSphereMeshHandle = handle;
		delete sphereMesh;

		// Create a ground plane
		let planeMesh = MeshBuilder.CreatePlane(20.0f, 20.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let planeHandle))
			mPlaneMeshHandle = planeHandle;
		delete planeMesh;

		// Add ground plane
		let floor = mWorld.CreateStaticMesh();
		if (let proxy = mWorld.GetStaticMesh(floor))
		{
			proxy.MeshHandle = mPlaneMeshHandle;
			proxy.Materials[0] = defaultMat;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-10, 0, -10), Vector3(10, 0.01f, 10)));
			proxy.SetTransformImmediate(Matrix.CreateTranslation(.(0, -0.5f, 0)));
			proxy.Flags = .DefaultOpaque;
		}

		// Add a grid of spheres
		let gridSize = 5;
		let spacing = 1.5f;
		let offset = (gridSize - 1) * spacing * 0.5f;

		for (int row = 0; row < gridSize; row++)
		{
			for (int col = 0; col < gridSize; col++)
			{
				let sphere = mWorld.CreateStaticMesh();
				if (let proxy = mWorld.GetStaticMesh(sphere))
				{
					proxy.MeshHandle = mSphereMeshHandle;
					proxy.Materials[0] = defaultMat;
					proxy.MaterialCount = 1;
					proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f), Vector3(0.5f)));
					let pos = Vector3(col * spacing - offset, 0.5f, row * spacing - offset);
					proxy.SetTransformImmediate(Matrix.CreateTranslation(pos));
					proxy.Flags = .DefaultOpaque;
				}
			}
		}

		// Add a directional light
		mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -0.7f, 0.3f)),
			.(1, 1, 1), 2.0f);
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape)) Exit();
		if (keyboard.IsKeyPressed(.P)) PrintStats();
		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mYaw += mouse.DeltaX * 0.003f;
			mPitch -= mouse.DeltaY * 0.003f;
			mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
		}
	}

	protected override void OnUpdate(Sedulous.Runtime.Client.FrameContext frame)
	{
		float dt = frame.DeltaTime;
		mFrameTimes[mFrameTimeIndex % 60] = dt * 1000.0f;
		mFrameTimeIndex++;

		if (mView == null)
			return;

		// Camera movement
		let keyboard = mShell.InputManager.Keyboard;
		float speed = keyboard.IsKeyDown(.LeftShift) ? 10.0f : 5.0f;
		float cosP = Math.Cos(mPitch);
		Vector3 forward = .(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw));
		Vector3 right = Vector3.Normalize(Vector3.Cross(forward, .(0, 1, 0)));
		Vector3 move = .Zero;
		if (keyboard.IsKeyDown(.W)) move += forward;
		if (keyboard.IsKeyDown(.S)) move -= forward;
		if (keyboard.IsKeyDown(.D)) move += right;
		if (keyboard.IsKeyDown(.A)) move -= right;
		if (keyboard.IsKeyDown(.E)) move += .(0, 1, 0);
		if (keyboard.IsKeyDown(.Q)) move -= .(0, 1, 0);
		if (move.LengthSquared() > 0) mCameraPosition += Vector3.Normalize(move) * speed * dt;

		// Update view
		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = forward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices();
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		if (mRenderSystem == null || mView == null)
			return true;

		mRenderSystem.BeginFrame(render.Frame.FrameIndex, render.Frame.TotalTime, render.Frame.DeltaTime);

		// Prepare view — uploads uniforms, rebuilds bind groups
		mRenderSystem.PrepareView(mView, mWorld);

		// Import swapchain with Present final state
		let backbuffer = mRenderSystem.RenderGraph.ImportTarget(
			"Backbuffer",
			render.SwapChain.CurrentTexture,
			render.SwapChain.CurrentTextureView,
			finalState: .Present);

		// Build graph — features add their passes (depth prepass + forward opaque)
		mRenderSystem.BuildGraph();

		// Blit SceneColor to backbuffer (temporary — will be replaced by FinalOutput/tonemap in Phase 6)
		let forwardFeature = mRenderSystem.GetFeature<ForwardOpaqueFeature>();
		if (forwardFeature != null && forwardFeature.ColorHandle.IsValid)
		{
			let colorHandle = forwardFeature.ColorHandle;
			let graph = mRenderSystem.RenderGraph;

			graph.AddCopyPass("BlitToScreen", scope (builder) =>
			{
				builder.CopySrc(colorHandle);
				builder.CopyDst(backbuffer);
				builder.NeverCull();
				builder.SetCopyExecute(new [=](encoder) => {
					let srcTex = graph.GetTexture(colorHandle);
					let dstTex = graph.GetTexture(backbuffer);
					if (srcTex != null && dstTex != null)
						encoder.Blit(srcTex, dstTex);
				});
			});
		}
		else
		{
			// Fallback clear if forward pass didn't run
			let clearColor = ClearColor(0.08f, 0.08f, 0.1f, 1.0f);
			mRenderSystem.RenderGraph.AddRenderPass("Clear", scope (builder) =>
			{
				builder.SetColorTarget(0, backbuffer, .Clear, .Store, clearColor);
				builder.NeverCull();
			});
		}

		// Execute
		mRenderSystem.Execute(render.Encoder);
		mRenderSystem.EndFrame();

		return true;
	}

	protected override void OnResize(int32 width, int32 height)
	{
		if (mView != null)
		{
			mView.Width = (uint32)width;
			mView.Height = (uint32)height;
		}
	}

	protected override void OnShutdown()
	{
		if (mRenderSystem != null)
		{
			if (mSphereMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mSphereMeshHandle, (uint64)mRenderSystem.FrameIndex);
			if (mPlaneMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, (uint64)mRenderSystem.FrameIndex);

			mRenderSystem.SetActiveWorld(null);
			mRenderSystem.Shutdown();
			delete mRenderSystem;
			mRenderSystem = null;
		}

		if (mWorld != null)
		{
			mWorld.Dispose();
			delete mWorld;
			mWorld = null;
		}

		delete mView;
		Console.WriteLine("Renderer Sandbox shutting down");
	}

	private void PrintStats()
	{
		Console.WriteLine("\n=== Init Stats ===");
		if (mInitTimeCaptured)
			Console.WriteLine("  Total init: {:.1}ms", mInitTimeMs);

		// Render stats
		let stats = mRenderSystem.Stats;
		Console.WriteLine("\n=== Render Stats ===");
		Console.WriteLine("  Draw calls: {}", stats.DrawCalls);
		Console.WriteLine("  Instances: {}", stats.InstanceCount);
		Console.WriteLine("  Visible meshes: {}", stats.VisibleStaticMeshes);
		Console.WriteLine("  Batches: {}", stats.BatchCount);

		// Profiler data
		let frame = SProfiler.GetCompletedFrame();
		if (frame.Samples.Count > 0)
		{
			Console.WriteLine("\n=== Frame Profiling ===");
			Console.WriteLine("  Frame: {:.2}ms", (float)frame.FrameDurationUs / 1000.0f);
			for (let sample in frame.Samples)
			{
				let indent = scope String();
				for (int i = 0; i < sample.Depth; i++)
					indent.Append("  ");
				Console.WriteLine("  {}{}: {:.3}ms", indent, sample.Name, (float)sample.DurationUs / 1000.0f);
			}
		}

		// Average frame time
		float totalMs = 0;
		let count = Math.Min(mFrameTimeIndex, 60);
		for (int i = 0; i < count; i++)
			totalMs += mFrameTimes[i];
		if (count > 0)
		{
			let avgMs = totalMs / count;
			Console.WriteLine("\n  Avg frame: {:.2}ms ({:.0} FPS)", avgMs, 1000.0f / avgMs);
		}

		Console.WriteLine("");
	}
}

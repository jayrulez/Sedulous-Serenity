namespace RenderParticles;

using System;
using System.Collections;
using System.Diagnostics;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Runtime.Client;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Profiler;

/// Particle system sample demonstrating GPU particle effects
/// with configurable emitters via the Sedulous.Render pipeline.
class RenderParticlesApp : Application
{
	// Render system (cleaned up in OnShutdown before device destruction)
	private RenderSystem mRenderSystem;
	private RenderWorld mWorld;
	private RenderView mView;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private ForwardTransparentFeature mTransparentFeature;
	private ParticleFeature mParticleFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Floor
	private GPUMeshHandle mFloorMeshHandle;

	// Particle emitters
	private ParticleEmitterProxyHandle mFountainEmitter;
	private ParticleEmitterProxyHandle mFountainEmitterGPU;
	private ParticleEmitterProxyHandle mFireEmitter;
	private ParticleEmitterProxyHandle mFireEmitterGPU;
	private ParticleEmitterProxyHandle mSmokeEmitter;
	private ParticleEmitterProxyHandle mSmokeEmitterGPU;

	// Lights
	private LightProxyHandle mSunLight = .Invalid;

	// Startup timing
	private bool mFirstFrame = true;

	// Camera
	private Vector3 mCameraPosition = .(0, 3, 8);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.1f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 5.0f;
	private const float LookSpeed = 0.003f;

	public this() : base()
	{
	}

	protected override void OnInitialize(Sedulous.Runtime.Context context)
	{
		let totalSw = scope Stopwatch()..Start();
		let sw = scope Stopwatch();

		Console.WriteLine("\n=== Startup Timing ===");

		sw.Restart();
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, mSwapChain.Width, mSwapChain.Height, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), scope $"{AssetCacheDirectory}/Shaders", .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}
		Console.WriteLine($"  RenderSystem.Initialize: {sw.Elapsed.TotalMilliseconds:F2}ms");

		mWorld = mRenderSystem.CreateWorld();
		mRenderSystem.SetActiveWorld(mWorld);

		mView = new RenderView();
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 100.0f;

		sw.Restart();
		RegisterFeatures();
		Console.WriteLine($"  RegisterFeatures:        {sw.Elapsed.TotalMilliseconds:F2}ms");

		sw.Restart();
		CreateFloor();
		Console.WriteLine($"  CreateFloor:             {sw.Elapsed.TotalMilliseconds:F2}ms");

		sw.Restart();
		CreateEmitters();
		Console.WriteLine($"  CreateEmitters:          {sw.Elapsed.TotalMilliseconds:F2}ms");

		sw.Restart();
		CreateLights();
		Console.WriteLine($"  CreateLights:            {sw.Elapsed.TotalMilliseconds:F2}ms");

		mWorld.AmbientColor = .(0.03f, 0.03f, 0.05f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine($"  Total init:              {totalSw.Elapsed.TotalMilliseconds:F2}ms");
		Console.WriteLine("======================\n");

		SProfiler.Initialize();

		Console.WriteLine("Render Particles initialized");
		Console.WriteLine("  WASD/QE: move, Right-click: look, Tab: capture");
		Console.WriteLine("  P: print profiler stats");
		Console.WriteLine("  ESC: exit");
	}

	private void RegisterFeatures()
	{
		mDepthFeature = new DepthPrepassFeature();
		if (mRenderSystem.RegisterFeature(mDepthFeature) case .Err)
			Console.WriteLine("Warning: Failed to register DepthPrepassFeature");

		mForwardFeature = new ForwardOpaqueFeature();
		if (mRenderSystem.RegisterFeature(mForwardFeature) case .Err)
			Console.WriteLine("Warning: Failed to register ForwardOpaqueFeature");

		mTransparentFeature = new ForwardTransparentFeature();
		if (mRenderSystem.RegisterFeature(mTransparentFeature) case .Err)
			Console.WriteLine("Warning: Failed to register ForwardTransparentFeature");

		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");

		mParticleFeature = new ParticleFeature();
		if (mRenderSystem.RegisterFeature(mParticleFeature) case .Err)
			Console.WriteLine("Warning: Failed to register ParticleFeature");

		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");
	}

	private void CreateFloor()
	{
		let planeMesh = MeshBuilder.CreatePlane(20.0f, 20.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let handle))
			mFloorMeshHandle = handle;
		delete planeMesh;

		let floor = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(floor))
		{
			proxy.MeshHandle = mFloorMeshHandle;
			proxy.Materials[0] = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-10, 0, -10), Vector3(10, 0.01f, 10)));
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}
	}

	private void CreateEmitters()
	{
		// Fountain (center, white/blue, upward)
		mFountainEmitter = mWorld.CreateParticleEmitter();
		if (let emitter = mWorld.GetParticleEmitter(mFountainEmitter))
		{
			emitter.Position = .(-4, 0, 0);
			emitter.MaxParticles = 1000;
			emitter.SpawnRate = 100.0f;
			emitter.ParticleLifetime = 3.0f;
			emitter.StartSize = .(0.1f, 0.1f);
			emitter.EndSize = .(0.05f, 0.05f);
			emitter.StartColor = .(0.8f, 0.9f, 1.0f, 1.0f);
			emitter.EndColor = .(0.4f, 0.6f, 1.0f, 0.0f);
			emitter.InitialVelocity = .(0, 5.0f, 0);
			emitter.VelocityRandomness = .(1.0f, 0.5f, 1.0f);
			emitter.GravityMultiplier = 1.0f;
			emitter.IsEmitting = true;
		}

		// Fire (left, red/orange)
		mFireEmitter = mWorld.CreateParticleEmitter();
		if (let emitter = mWorld.GetParticleEmitter(mFireEmitter))
		{
			emitter.Position = .(-2.0f, 0, 0);
			emitter.MaxParticles = 500;
			emitter.SpawnRate = 80.0f;
			emitter.ParticleLifetime = 1.5f;
			emitter.StartSize = .(0.3f, 0.3f);
			emitter.EndSize = .(0.6f, 0.6f);
			emitter.StartColor = .(1.0f, 0.6f, 0.1f, 0.8f);
			emitter.EndColor = .(0.8f, 0.1f, 0.0f, 0.0f);
			emitter.InitialVelocity = .(0, 2.0f, 0);
			emitter.VelocityRandomness = .(0.5f, 0.3f, 0.5f);
			emitter.GravityMultiplier = -0.2f;
			emitter.IsEmitting = true;
		}

		// Smoke (right, grey, slow rising)
		mSmokeEmitter = mWorld.CreateParticleEmitter();
		if (let emitter = mWorld.GetParticleEmitter(mSmokeEmitter))
		{
			emitter.Position = .(0.0f, 0, 0);
			emitter.MaxParticles = 300;
			emitter.SpawnRate = 30.0f;
			emitter.ParticleLifetime = 5.0f;
			emitter.StartSize = .(0.2f, 0.2f);
			emitter.EndSize = .(1.0f, 1.0f);
			emitter.StartColor = .(0.5f, 0.5f, 0.5f, 0.6f);
			emitter.EndColor = .(0.3f, 0.3f, 0.3f, 0.0f);
			emitter.InitialVelocity = .(0, 1.0f, 0);
			emitter.VelocityRandomness = .(0.3f, 0.2f, 0.3f);
			emitter.GravityMultiplier = -0.1f;
			emitter.Drag = 0.5f;
			emitter.IsEmitting = true;
		}

		

		// Fountain (center, white/blue, upward)
		mFountainEmitterGPU = mWorld.CreateParticleEmitter(.GPU);
		if (let emitter = mWorld.GetParticleEmitter(mFountainEmitterGPU))
		{
			emitter.Position = .(2, 0, 0);
			emitter.MaxParticles = 1000;
			emitter.SpawnRate = 100.0f;
			emitter.ParticleLifetime = 3.0f;
			emitter.StartSize = .(0.1f, 0.1f);
			emitter.EndSize = .(0.05f, 0.05f);
			emitter.StartColor = .(0.8f, 0.9f, 1.0f, 1.0f);
			emitter.EndColor = .(0.4f, 0.6f, 1.0f, 0.0f);
			emitter.InitialVelocity = .(0, 5.0f, 0);
			emitter.VelocityRandomness = .(1.0f, 0.5f, 1.0f);
			emitter.GravityMultiplier = 1.0f;
			emitter.IsEmitting = true;
		}

		// Fire (left, red/orange)
		mFireEmitterGPU = mWorld.CreateParticleEmitter(.GPU);
		if (let emitter = mWorld.GetParticleEmitter(mFireEmitterGPU))
		{
			emitter.Position = .(4.0f, 0, 0);
			emitter.MaxParticles = 500;
			emitter.SpawnRate = 80.0f;
			emitter.ParticleLifetime = 1.5f;
			emitter.StartSize = .(0.3f, 0.3f);
			emitter.EndSize = .(0.6f, 0.6f);
			emitter.StartColor = .(1.0f, 0.6f, 0.1f, 0.8f);
			emitter.EndColor = .(0.8f, 0.1f, 0.0f, 0.0f);
			emitter.InitialVelocity = .(0, 2.0f, 0);
			emitter.VelocityRandomness = .(0.5f, 0.3f, 0.5f);
			emitter.GravityMultiplier = -0.2f;
			emitter.IsEmitting = true;
		}

		// Smoke (right, grey, slow rising)
		mSmokeEmitterGPU = mWorld.CreateParticleEmitter(.GPU);
		if (let emitter = mWorld.GetParticleEmitter(mSmokeEmitterGPU))
		{
			emitter.Position = .(6.0f, 0, 0);
			emitter.MaxParticles = 300;
			emitter.SpawnRate = 30.0f;
			emitter.ParticleLifetime = 5.0f;
			emitter.StartSize = .(0.2f, 0.2f);
			emitter.EndSize = .(1.0f, 1.0f);
			emitter.StartColor = .(0.5f, 0.5f, 0.5f, 0.6f);
			emitter.EndColor = .(0.3f, 0.3f, 0.3f, 0.0f);
			emitter.InitialVelocity = .(0, 1.0f, 0);
			emitter.VelocityRandomness = .(0.3f, 0.2f, 0.3f);
			emitter.GravityMultiplier = -0.1f;
			emitter.Drag = 0.5f;
			emitter.IsEmitting = true;
		}
	}

	private void CreateLights()
	{
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -1.0f, 0.3f)),
			.(1.0f, 1.0f, 0.95f),
			1.5f
		);

		// Point light near fire
		mWorld.CreatePointLight(.(-3.0f, 1.5f, 0), .(1.0f, 0.4f, 0.1f), 5.0f, 6.0f);
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		if (keyboard.IsKeyPressed(.P))
			PrintProfilerStats();

		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mYaw += mouse.DeltaX * LookSpeed;
			mPitch -= mouse.DeltaY * LookSpeed;
			mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;

		let keyboard = mShell.InputManager.Keyboard;
		float speed = keyboard.IsKeyDown(.LeftShift) ? MoveSpeed * 2 : MoveSpeed;

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

		if (move.LengthSquared() > 0)
			mCameraPosition += Vector3.Normalize(move) * speed * dt;

		mCameraForward = Vector3.Normalize(.(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw)));

		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = mCameraForward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	protected override void OnResize(int32 width, int32 height)
	{
		mRenderSystem?.SetViewportSize((uint32)width, (uint32)height);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		if (mFirstFrame)
		{
			let sw = scope Stopwatch()..Start();
			mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);
			Console.WriteLine($"  First BeginFrame (batch flush): {sw.Elapsed.TotalMilliseconds:F2}ms");
			mFirstFrame = false;
		}
		else
		{
			mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);
		}

		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		mRenderSystem.SetCamera(
			mCameraPosition, mCameraForward, .(0, 1, 0),
			mView.FieldOfView, mView.AspectRatio,
			mView.NearPlane, mView.FarPlane,
			mView.Width, mView.Height
		);

		if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
			mRenderSystem.Execute(render.Encoder);

		mRenderSystem.EndFrame();
		return true;
	}

	private void PrintProfilerStats()
	{
		let frame = SProfiler.GetCompletedFrame();
		if (frame == null || frame.SampleCount == 0)
		{
			Console.WriteLine("No profiler data available");
			return;
		}

		Console.WriteLine($"\n=== Frame {frame.FrameNumber} : {frame.FrameDurationMs:F2}ms ({frame.SampleCount} samples) ===");
		for (let sample in frame.Samples)
		{
			let indent = scope String();
			for (int i = 0; i < sample.Depth; i++)
				indent.Append("  ");
			Console.WriteLine($"  {indent}{sample.Name}: {sample.DurationMs:F3}ms");
		}
		Console.WriteLine();
	}

	protected override void OnShutdown()
	{
		// Dispose world first — cleans up owned CPUParticleEmitters (which have RHI buffers)
		mWorld?.Dispose();

		if (mRenderSystem != null)
		{
			if (mFloorMeshHandle.IsValid)
				mRenderSystem.ResourceManager.ReleaseMesh(mFloorMeshHandle, mRenderSystem.FrameNumber);

			mRenderSystem.Shutdown();
			delete mRenderSystem;
			mRenderSystem = null;
		}
		delete mWorld;
		delete mView;

		Console.WriteLine("Render Particles shutting down");
	}
}

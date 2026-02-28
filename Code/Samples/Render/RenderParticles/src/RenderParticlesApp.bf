namespace RenderParticles;

using System;
using System.Collections;
using Sedulous.Foundation.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Engine.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;

/// Particle system sample demonstrating GPU particle effects
/// with configurable emitters via the Sedulous.Render pipeline.
class RenderParticlesApp : Application
{
	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

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
	private ParticleEmitterProxyHandle mFireEmitter;
	private ParticleEmitterProxyHandle mSmokeEmitter;

	// Lights
	private LightProxyHandle mSunLight = .Invalid;

	// Camera
	private Vector3 mCameraPosition = .(0, 3, 8);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.1f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 5.0f;
	private const float LookSpeed = 0.003f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Engine.Core.Context context)
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), null, .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}

		mWorld = mRenderSystem.CreateWorld();
		mRenderSystem.SetActiveWorld(mWorld);

		mView = new RenderView();
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 100.0f;

		RegisterFeatures();
		CreateFloor();
		CreateEmitters();
		CreateLights();

		mWorld.AmbientColor = .(0.03f, 0.03f, 0.05f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Particles initialized");
		Console.WriteLine("  WASD/QE: move, Right-click: look, Tab: capture");
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
		let planeMesh = StaticMesh.CreatePlane(20.0f, 20.0f, 1, 1);
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
		mFountainEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let emitter = mWorld.GetParticleEmitter(mFountainEmitter))
		{
			emitter.Position = .(0, 0, 0);
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
		mFireEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let emitter = mWorld.GetParticleEmitter(mFireEmitter))
		{
			emitter.Position = .(-3.0f, 0, 0);
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
		mSmokeEmitter = mWorld.CreateParticleEmitter(mDevice);
		if (let emitter = mWorld.GetParticleEmitter(mSmokeEmitter))
		{
			emitter.Position = .(3.0f, 0, 0);
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

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

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

	protected override void OnShutdown()
	{
		mWorld?.Dispose();

		if (mFloorMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mFloorMeshHandle, mRenderSystem.FrameNumber);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Render Particles shutting down");
	}
}

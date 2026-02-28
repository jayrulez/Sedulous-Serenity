namespace RenderPBR;

using System;
using Sedulous.Foundation.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Engine.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;

/// PBR sample demonstrating physically-based rendering with a sphere
/// and varying material parameters via the Sedulous.Render pipeline.
class RenderPBRApp : Application
{
	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Meshes
	private GPUMeshHandle mSphereMeshHandle;
	private MeshProxyHandle mSphereProxy;

	// Materials
	private MaterialInstance mSphereMaterial ~ _?.ReleaseRef();

	// Lights
	private LightProxyHandle mSunLight = .Invalid;

	// Camera
	private Vector3 mCameraPosition = .(0, 0, 4);
	private float mYaw = Math.PI_f;
	private float mPitch = 0;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 5.0f;
	private const float LookSpeed = 0.003f;

	// Animation
	private float mSphereRotation = 0;

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
		CreateScene();
		CreateLights();

		mWorld.AmbientColor = .(0.03f, 0.03f, 0.03f);
		mWorld.AmbientIntensity = 1.0f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render PBR initialized");
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

		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");

		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");
	}

	private void CreateScene()
	{
		let sphereMesh = StaticMesh.CreateSphere(0.8f, 48, 24);
		if (mRenderSystem.ResourceManager.UploadMesh(sphereMesh) case .Ok(let handle))
			mSphereMeshHandle = handle;
		delete sphereMesh;

		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		if (let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			mSphereMaterial = new MaterialInstance(baseMat);
			mSphereMaterial.SetColor("BaseColor", .(0.86f, 0.86f, 0.88f, 1.0f));
			mSphereMaterial.SetFloat("Metallic", 0.0f);
			mSphereMaterial.SetFloat("Roughness", 0.4f);
		}

		mSphereProxy = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(mSphereProxy))
		{
			proxy.MeshHandle = mSphereMeshHandle;
			proxy.Materials[0] = mSphereMaterial ?? defaultMaterial;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-0.8f, -0.8f, -0.8f), Vector3(0.8f, 0.8f, 0.8f)));
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}
	}

	private void CreateLights()
	{
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(1.0f, -1.0f, 0.5f)),
			.(1.0f, 1.0f, 1.0f),
			3.0f
		);
		if (let light = mWorld.GetLight(mSunLight))
			light.CastsShadows = true;
		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;
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

		// Rotate sphere
		mSphereRotation += dt * 0.5f;
		if (let proxy = mWorld.GetMesh(mSphereProxy))
			proxy.SetTransformImmediate(Matrix.CreateRotationY(mSphereRotation));

		// Update camera
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
		if (mSphereMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mSphereMeshHandle, mRenderSystem.FrameNumber);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Render PBR shutting down");
	}
}

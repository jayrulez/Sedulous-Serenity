namespace RenderGeometry;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Engine.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;

/// Geometry sample demonstrating procedural cube meshes, camera control,
/// skybox, and PBR lighting via the Sedulous.Render pipeline.
class RenderGeometryApp : Application
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

	// Mesh resources
	private GPUMeshHandle mCubeMeshHandle;
	private MeshProxyHandle mRedCubeProxy;
	private MeshProxyHandle mBlueCubeProxy;

	// Materials
	private MaterialInstance mRedMaterial ~ _?.ReleaseRef();
	private MaterialInstance mBlueMaterial ~ _?.ReleaseRef();

	// Lighting
	private LightProxyHandle mSunLight = .Invalid;

	// Camera
	private Vector3 mCameraPosition = .(0, 2, 8);
	private float mYaw = Math.PI_f; // Looking toward -Z (toward origin)
	private float mPitch = -0.2f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 5.0f;
	private const float FastMoveSpeed = 10.0f;
	private const float LookSpeed = 0.003f;

	// Animation
	private float mCubeRotation = 0;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Engine.Core.Context context)
	{
		// Initialize render system
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), null, .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}

		// Create render world
		mWorld = mRenderSystem.CreateWorld();
		mRenderSystem.SetActiveWorld(mWorld);

		// Create render view
		mView = new RenderView();
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 100.0f;

		// Register render features
		RegisterFeatures();

		// Create scene
		CreateMeshes();
		CreateSceneObjects();
		CreateLights();

		// Environment
		mWorld.AmbientColor = .(0.05f, 0.05f, 0.08f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Geometry initialized");
		Console.WriteLine("  WASD: move camera");
		Console.WriteLine("  Q/E: move down/up");
		Console.WriteLine("  Right-click + drag: look around");
		Console.WriteLine("  Tab: toggle mouse capture");
		Console.WriteLine("  Shift: move faster");
		Console.WriteLine("  ESC: exit");
	}

	private void RegisterFeatures()
	{
		// Depth prepass
		mDepthFeature = new DepthPrepassFeature();
		if (mRenderSystem.RegisterFeature(mDepthFeature) case .Err)
			Console.WriteLine("Warning: Failed to register DepthPrepassFeature");

		// Forward opaque (PBR lighting)
		mForwardFeature = new ForwardOpaqueFeature();
		if (mRenderSystem.RegisterFeature(mForwardFeature) case .Err)
			Console.WriteLine("Warning: Failed to register ForwardOpaqueFeature");

		// Sky
		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");

		// Final output
		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");
	}

	private void CreateMeshes()
	{
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let handle))
			mCubeMeshHandle = handle;
		else
			Console.WriteLine("ERROR: Failed to upload cube mesh");
		delete cubeMesh;
	}

	private void CreateSceneObjects()
	{
		if (let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			// Red material
			mRedMaterial = new MaterialInstance(baseMaterial);
			mRedMaterial.SetColor("BaseColor", .(1.0f, 0.2f, 0.2f, 1.0f));
			mRedMaterial.SetFloat("Roughness", 0.4f);

			// Blue material
			mBlueMaterial = new MaterialInstance(baseMaterial);
			mBlueMaterial.SetColor("BaseColor", .(0.2f, 0.2f, 1.0f, 1.0f));
			mBlueMaterial.SetFloat("Roughness", 0.4f);
		}

		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Red cube at (2, 0.5, 0)
		mRedCubeProxy = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(mRedCubeProxy))
		{
			proxy.MeshHandle = mCubeMeshHandle;
			proxy.Materials[0] = mRedMaterial ?? defaultMaterial;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
			proxy.SetTransformImmediate(Matrix.CreateTranslation(.(2.0f, 0.5f, 0)));
			proxy.Flags = .DefaultOpaque;
		}

		// Blue cube at (-2, 0.5, 0)
		mBlueCubeProxy = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(mBlueCubeProxy))
		{
			proxy.MeshHandle = mCubeMeshHandle;
			proxy.Materials[0] = mBlueMaterial ?? defaultMaterial;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
			proxy.SetTransformImmediate(Matrix.CreateTranslation(.(-2.0f, 0.5f, 0)));
			proxy.Flags = .DefaultOpaque;
		}
	}

	private void CreateLights()
	{
		// Directional sun light (similar direction to old sample's hard-coded light)
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(1.0f, -1.0f, 0.5f)),
			.(1.0f, 1.0f, 0.95f),
			2.0f
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

		// Toggle mouse capture
		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		// Camera look (right-click drag or mouse capture)
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

		// Camera movement
		let keyboard = mShell.InputManager.Keyboard;
		float speed = keyboard.IsKeyDown(.LeftShift) ? FastMoveSpeed : MoveSpeed;

		float cosP = Math.Cos(mPitch);
		Vector3 forward = .(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw));
		Vector3 right = Vector3.Normalize(Vector3.Cross(forward, .(0, 1, 0)));
		Vector3 up = .(0, 1, 0);

		Vector3 move = .Zero;
		if (keyboard.IsKeyDown(.W)) move += forward;
		if (keyboard.IsKeyDown(.S)) move -= forward;
		if (keyboard.IsKeyDown(.D)) move += right;
		if (keyboard.IsKeyDown(.A)) move -= right;
		if (keyboard.IsKeyDown(.E)) move += up;
		if (keyboard.IsKeyDown(.Q)) move -= up;

		if (move.LengthSquared() > 0)
			mCameraPosition += Vector3.Normalize(move) * speed * dt;

		// Animate cubes
		mCubeRotation += dt * 0.5f;

		// Red cube rotates CCW
		if (let proxy = mWorld.GetMesh(mRedCubeProxy))
		{
			let transform = Matrix.CreateRotationY(mCubeRotation) * Matrix.CreateTranslation(.(2.0f, 0.5f, 0));
			proxy.SetTransformImmediate(transform);
		}

		// Blue cube rotates CW
		if (let proxy = mWorld.GetMesh(mBlueCubeProxy))
		{
			let transform = Matrix.CreateRotationY(-mCubeRotation) * Matrix.CreateTranslation(.(-2.0f, 0.5f, 0));
			proxy.SetTransformImmediate(transform);
		}

		// Update camera
		let cosP2 = Math.Cos(mPitch);
		mCameraForward = Vector3.Normalize(.(cosP2 * Math.Sin(mYaw), Math.Sin(mPitch), cosP2 * Math.Cos(mYaw)));

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

		if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
			mRenderSystem.Execute(render.Encoder);

		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnShutdown()
	{
		if (mCubeMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Render Geometry shutting down");
	}
}

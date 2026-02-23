namespace RenderShadow;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Framework.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;

/// Shadow mapping sample demonstrating directional light shadows
/// with interactive light direction control via the Sedulous.Render pipeline.
class RenderShadowApp : Application
{
	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private OverlayRenderFeature mOverlayFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Meshes
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;

	// Lights
	private LightProxyHandle mSunLight = .Invalid;
	private float mLightYaw = 0.5f;
	private float mLightPitch = -0.7f;

	// Materials
	private MaterialInstance mRedMaterial ~ _?.ReleaseRef();
	private MaterialInstance mBlueMaterial ~ _?.ReleaseRef();
	private MaterialInstance mFloorMaterial ~ _?.ReleaseRef();

	// Camera
	private Vector3 mCameraPosition = .(0, 8, 12);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.4f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 8.0f;
	private const float LookSpeed = 0.003f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Framework.Core.Context context)
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

		mWorld.AmbientColor = .(0.05f, 0.05f, 0.08f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Shadow initialized");
		Console.WriteLine("  Arrow keys: adjust light direction");
		Console.WriteLine("  WASD/QE: move camera, Right-click: look");
		Console.WriteLine("  Tab: capture mouse, ESC: exit");
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

		mOverlayFeature = new OverlayRenderFeature();
		if (mRenderSystem.RegisterFeature(mOverlayFeature) case .Err)
			Console.WriteLine("Warning: Failed to register OverlayRenderFeature");

		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");
	}

	private void CreateScene()
	{
		// Create meshes
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let handle))
			mCubeMeshHandle = handle;
		delete cubeMesh;

		let planeMesh = StaticMesh.CreatePlane(20.0f, 20.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let handle2))
			mPlaneMeshHandle = handle2;
		delete planeMesh;

		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		if (let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			mRedMaterial = new MaterialInstance(baseMat);
			mRedMaterial.SetColor("BaseColor", .(0.8f, 0.3f, 0.3f, 1.0f));

			mBlueMaterial = new MaterialInstance(baseMat);
			mBlueMaterial.SetColor("BaseColor", .(0.3f, 0.3f, 0.8f, 1.0f));

			mFloorMaterial = new MaterialInstance(baseMat);
			mFloorMaterial.SetColor("BaseColor", .(0.7f, 0.7f, 0.7f, 1.0f));
			mFloorMaterial.SetFloat("Roughness", 0.8f);
		}

		// Floor
		let floor = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(floor))
		{
			proxy.MeshHandle = mPlaneMeshHandle;
			proxy.Materials[0] = mFloorMaterial ?? defaultMaterial;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-10, 0, -10), Vector3(10, 0.01f, 10)));
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}

		// Red cube
		let redCube = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(redCube))
		{
			proxy.MeshHandle = mCubeMeshHandle;
			proxy.Materials[0] = mRedMaterial ?? defaultMaterial;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
			proxy.SetTransformImmediate(Matrix.CreateTranslation(.(-2.0f, 0.5f, 0)));
			proxy.Flags = .DefaultOpaque;
		}

		// Blue cube
		let blueCube = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(blueCube))
		{
			proxy.MeshHandle = mCubeMeshHandle;
			proxy.Materials[0] = mBlueMaterial ?? defaultMaterial;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
			proxy.SetTransformImmediate(Matrix.CreateTranslation(.(2.0f, 0.5f, 0)));
			proxy.Flags = .DefaultOpaque;
		}
	}

	private void CreateLights()
	{
		UpdateLightDirection();
	}

	private void UpdateLightDirection()
	{
		Vector3 dir = Vector3.Normalize(.(
			Math.Cos(mLightPitch) * Math.Sin(mLightYaw),
			Math.Sin(mLightPitch),
			Math.Cos(mLightPitch) * Math.Cos(mLightYaw)
		));

		if (!mSunLight.IsValid)
		{
			mSunLight = mWorld.CreateDirectionalLight(dir, .(1.0f, 0.95f, 0.9f), 2.0f);
			if (let light = mWorld.GetLight(mSunLight))
				light.CastsShadows = true;
			if (mForwardFeature?.ShadowRenderer != null)
				mForwardFeature.ShadowRenderer.EnableShadows = true;
		}
		else if (let light = mWorld.GetLight(mSunLight))
		{
			light.Direction = dir;
		}
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

	private void UpdateDebugDrawing()
	{
		if (mOverlayFeature == null)
			return;

		let lightDir = Vector3.Normalize(.(
			Math.Cos(mLightPitch) * Math.Sin(mLightYaw),
			Math.Sin(mLightPitch),
			Math.Cos(mLightPitch) * Math.Cos(mLightYaw)
		));
		let lightStart = Vector3(0, 5, 0);

		// XYZ axes at gizmo origin
		let axisLength = 1.5f;
		mOverlayFeature.AddLine(lightStart, lightStart + Vector3(axisLength, 0, 0), .(255, 0, 0, 255), .Overlay);
		mOverlayFeature.AddLine(lightStart, lightStart + Vector3(0, axisLength, 0), .(0, 255, 0, 255), .Overlay);
		mOverlayFeature.AddLine(lightStart, lightStart + Vector3(0, 0, axisLength), .(0, 0, 255, 255), .Overlay);

		// Yellow line for light direction
		let lightEnd = lightStart + lightDir * 5.0f;
		let arrowColor = Color(255, 255, 0, 255);
		mOverlayFeature.AddLine(lightStart, lightEnd, arrowColor, .Overlay);

		// Arrow head
		let right = Vector3.Normalize(Vector3.Cross(lightDir, Vector3.Up));
		let up = Vector3.Normalize(Vector3.Cross(right, lightDir));
		let arrowSize = 0.3f;
		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize + right * arrowSize * 0.5f, arrowColor, .Overlay);
		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize - right * arrowSize * 0.5f, arrowColor, .Overlay);
		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize + up * arrowSize * 0.5f, arrowColor, .Overlay);
		mOverlayFeature.AddLine(lightEnd, lightEnd - lightDir * arrowSize - up * arrowSize * 0.5f, arrowColor, .Overlay);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;

		// Light direction control
		let keyboard = mShell.InputManager.Keyboard;
		bool lightChanged = false;
		if (keyboard.IsKeyDown(.Up)) { mLightPitch -= dt; lightChanged = true; }
		if (keyboard.IsKeyDown(.Down)) { mLightPitch += dt; lightChanged = true; }
		if (keyboard.IsKeyDown(.Left)) { mLightYaw -= dt; lightChanged = true; }
		if (keyboard.IsKeyDown(.Right)) { mLightYaw += dt; lightChanged = true; }
		mLightPitch = Math.Clamp(mLightPitch, -Math.PI_f * 0.45f, -0.1f);
		if (lightChanged)
			UpdateLightDirection();

		UpdateDebugDrawing();

		// Camera
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
		if (mCubeMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
		if (mPlaneMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Render Shadow shutting down");
	}
}

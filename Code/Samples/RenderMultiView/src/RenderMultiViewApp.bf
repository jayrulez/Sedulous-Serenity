namespace RenderMultiView;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Framework.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;

/// Multi-view demo demonstrating multiple camera viewpoints.
/// Switches between a player-controlled camera and an auto-orbiting camera.
/// Note: True split-screen rendering requires multi-view render graph support
/// which is planned for a future update. This sample demonstrates camera
/// management and switching as a foundation for that feature.
class RenderMultiViewApp : Application
{
	private const int32 GRID_SIZE = 5;

	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Mesh handles
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mFloorMeshHandle;

	// Materials
	private List<MaterialInstance> mMaterials = new .() ~ { for (let m in _) m?.ReleaseRef(); delete _; };

	// Lights
	private LightProxyHandle mSunLight;

	// Player camera state
	private Vector3 mPlayerPosition = .(0, 10, 25);
	private float mPlayerYaw = Math.PI_f;
	private float mPlayerPitch = -0.3f;
	private bool mMouseCaptured = false;

	// Orbit camera state
	private float mOrbitAngle = 0.0f;
	private float mOrbitRadius = 20.0f;
	private float mOrbitHeight = 10.0f;
	private float mOrbitSpeed = 0.5f;

	// Current active camera
	private bool mUseOrbitCamera = false;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Framework.Core.Context context)
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
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
		mView.FarPlane = 500.0f;

		RegisterFeatures();
		CreateMeshes();
		CreateScene();
		CreateLights();

		mWorld.AmbientColor = .(0.05f, 0.05f, 0.08f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Multi-View initialized");
		Console.WriteLine("  Camera switching demo (split-screen planned for future)");
		Console.WriteLine("  Space: toggle Player/Orbit camera");
		Console.WriteLine("  WASD/QE: move (player cam), +/-: orbit speed");
		Console.WriteLine("  Tab: capture mouse, Shift: fast, ESC: exit");
	}

	private void RegisterFeatures()
	{
		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void CreateMeshes()
	{
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let h))
			mCubeMeshHandle = h;
		delete cubeMesh;

		let planeMesh = StaticMesh.CreatePlane(40.0f, 40.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let h2))
			mFloorMeshHandle = h2;
		delete planeMesh;
	}

	private void CreateScene()
	{
		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;
		let defaultMat = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Floor
		let floor = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(floor))
		{
			proxy.MeshHandle = mFloorMeshHandle;
			proxy.Materials[0] = defaultMat;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-20, 0, -20), Vector3(20, 0.01f, 20)));
			proxy.SetTransformImmediate(Matrix.CreateTranslation(.(0, -0.5f, 0)));
			proxy.Flags = .DefaultOpaque;
		}

		if (baseMat == null) return;

		// 8 cube colors
		Vector4[8] cubeColors = .(
			.(1.0f, 0.3f, 0.3f, 1.0f),
			.(0.3f, 1.0f, 0.3f, 1.0f),
			.(0.3f, 0.3f, 1.0f, 1.0f),
			.(1.0f, 1.0f, 0.3f, 1.0f),
			.(1.0f, 0.3f, 1.0f, 1.0f),
			.(0.3f, 1.0f, 1.0f, 1.0f),
			.(1.0f, 0.6f, 0.3f, 1.0f),
			.(0.6f, 0.3f, 1.0f, 1.0f)
		);

		for (int i = 0; i < 8; i++)
		{
			let mat = new MaterialInstance(baseMat);
			mat.SetColor("BaseColor", cubeColors[i]);
			mat.SetFloat("Metallic", 0.2f);
			mat.SetFloat("Roughness", 0.5f);
			mMaterials.Add(mat);
		}

		// Grid of cubes
		float spacing = 3.0f;
		float startOffset = -(GRID_SIZE * spacing) / 2.0f;

		for (int32 x = 0; x < GRID_SIZE; x++)
		{
			for (int32 z = 0; z < GRID_SIZE; z++)
			{
				float posX = startOffset + x * spacing;
				float posZ = startOffset + z * spacing;

				let cube = mWorld.CreateMesh();
				if (let proxy = mWorld.GetMesh(cube))
				{
					proxy.MeshHandle = mCubeMeshHandle;
					proxy.Materials[0] = mMaterials[(x + z) % 8];
					proxy.MaterialCount = 1;
					proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
					proxy.SetTransformImmediate(Matrix.CreateTranslation(.(posX, 0.5f, posZ)));
					proxy.Flags = .DefaultOpaque;
				}
			}
		}

		// Central tower
		for (int32 y = 0; y < 5; y++)
		{
			let tower = mWorld.CreateMesh();
			if (let proxy = mWorld.GetMesh(tower))
			{
				proxy.MeshHandle = mCubeMeshHandle;
				proxy.Materials[0] = mMaterials[y % 8];
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(BoundingBox(Vector3(-0.4f, -0.75f, -0.4f), Vector3(0.4f, 0.75f, 0.4f)));
				proxy.SetTransformImmediate(
					Matrix.CreateScale(.(0.8f, 1.5f, 0.8f)) *
					Matrix.CreateTranslation(.(0, (float)y * 1.5f + 1.0f, 0)));
				proxy.Flags = .DefaultOpaque;
			}
		}
	}

	private void CreateLights()
	{
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -0.7f, 0.3f)),
			.(1.0f, 0.95f, 0.8f), 1.2f);
		if (let light = mWorld.GetLight(mSunLight))
			light.CastsShadows = true;
		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;

		// 4 corner point lights
		Vector3[4] lightPos = .(.(-8, 4, -8), .(8, 4, -8), .(-8, 4, 8), .(8, 4, 8));
		Vector3[4] lightCol = .(.(1.0f, 0.5f, 0.5f), .(0.5f, 1.0f, 0.5f), .(0.5f, 0.5f, 1.0f), .(1.0f, 1.0f, 0.5f));
		for (int i = 0; i < 4; i++)
			mWorld.CreatePointLight(lightPos[i], lightCol[i], 3.0f, 15.0f);
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;
		if (keyboard.IsKeyPressed(.Escape)) Exit();

		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		// Toggle camera
		if (keyboard.IsKeyPressed(.Space))
		{
			mUseOrbitCamera = !mUseOrbitCamera;
			Console.WriteLine(mUseOrbitCamera ? "Orbit camera active" : "Player camera active");
		}

		// Orbit speed control
		if (keyboard.IsKeyPressed(.Equals) || keyboard.IsKeyPressed(.KeypadPlus))
		{
			mOrbitSpeed = Math.Min(mOrbitSpeed + 0.1f, 3.0f);
			Console.WriteLine($"Orbit speed: {mOrbitSpeed}");
		}
		if (keyboard.IsKeyPressed(.Minus) || keyboard.IsKeyPressed(.KeypadMinus))
		{
			mOrbitSpeed = Math.Max(mOrbitSpeed - 0.1f, 0.0f);
			Console.WriteLine($"Orbit speed: {mOrbitSpeed}");
		}

		// Player camera look
		if (!mUseOrbitCamera && (mMouseCaptured || mouse.IsButtonDown(.Right)))
		{
			mPlayerYaw += mouse.DeltaX * 0.003f;
			mPlayerPitch -= mouse.DeltaY * 0.003f;
			mPlayerPitch = Math.Clamp(mPlayerPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;
		let keyboard = mShell.InputManager.Keyboard;

		// Update orbit
		mOrbitAngle += mOrbitSpeed * dt;
		if (mOrbitAngle > Math.PI_f * 2.0f)
			mOrbitAngle -= Math.PI_f * 2.0f;

		// Player camera movement
		if (!mUseOrbitCamera)
		{
			float speed = (keyboard.IsKeyDown(.LeftShift) ? 30.0f : 15.0f) * dt;
			float cosP = Math.Cos(mPlayerPitch);
			Vector3 forward = .(cosP * Math.Sin(mPlayerYaw), Math.Sin(mPlayerPitch), cosP * Math.Cos(mPlayerYaw));
			Vector3 right = Vector3.Normalize(Vector3.Cross(forward, .(0, 1, 0)));
			Vector3 move = .Zero;
			if (keyboard.IsKeyDown(.W)) move += forward;
			if (keyboard.IsKeyDown(.S)) move -= forward;
			if (keyboard.IsKeyDown(.D)) move += right;
			if (keyboard.IsKeyDown(.A)) move -= right;
			if (keyboard.IsKeyDown(.E)) move += .(0, 1, 0);
			if (keyboard.IsKeyDown(.Q)) move -= .(0, 1, 0);
			if (move.LengthSquared() > 0) mPlayerPosition += Vector3.Normalize(move) * speed;
		}

		// Set view based on active camera
		if (mUseOrbitCamera)
		{
			let orbitX = Math.Cos(mOrbitAngle) * mOrbitRadius;
			let orbitZ = Math.Sin(mOrbitAngle) * mOrbitRadius;
			let orbitPos = Vector3(orbitX, mOrbitHeight, orbitZ);
			let lookTarget = Vector3(0, 4, 0);
			let orbitForward = Vector3.Normalize(lookTarget - orbitPos);

			mView.CameraPosition = orbitPos;
			mView.CameraForward = orbitForward;
		}
		else
		{
			float cosP = Math.Cos(mPlayerPitch);
			let playerForward = Vector3.Normalize(.(cosP * Math.Sin(mPlayerYaw), Math.Sin(mPlayerPitch), cosP * Math.Cos(mPlayerYaw)));
			mView.CameraPosition = mPlayerPosition;
			mView.CameraForward = playerForward;
		}

		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);
		if (mFinalOutputFeature != null) mFinalOutputFeature.SetSwapChain(render.SwapChain);
		mRenderSystem.SetCamera(mView.CameraPosition, mView.CameraForward, .(0, 1, 0),
			mView.FieldOfView, mView.AspectRatio, mView.NearPlane, mView.FarPlane, mView.Width, mView.Height);
		if (mRenderSystem.BuildRenderGraph(mView) case .Ok) mRenderSystem.Execute(render.Encoder);
		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnShutdown()
	{
		if (mCubeMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
		if (mFloorMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mFloorMeshHandle, mRenderSystem.FrameNumber);
		mRenderSystem?.Shutdown();
		Console.WriteLine("Render Multi-View shutting down");
	}
}

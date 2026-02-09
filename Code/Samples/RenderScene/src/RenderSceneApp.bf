namespace RenderScene;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Framework.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;

/// Scene management sample demonstrating large-scale rendering with 1200+ objects,
/// frustum culling, multiple lights, and PBR materials via the Sedulous.Render pipeline.
class RenderSceneApp : Application
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
	private GPUMeshHandle mCubeMeshHandle;

	// Materials
	private MaterialInstance[5] mCubeMaterials;

	// Lights
	private LightProxyHandle mSunLight = .Invalid;
	private List<LightProxyHandle> mPointLights = new .() ~ delete _;

	// Camera
	private Vector3 mCameraPosition = .(0, 15, 40);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.3f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 20.0f;
	private const float FastMoveSpeed = 40.0f;
	private const float LookSpeed = 0.003f;

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
		mView.FarPlane = 200.0f;

		RegisterFeatures();
		CreateMeshes();
		CreateMaterials();
		CreateScene();
		CreateLights();

		mWorld.AmbientColor = .(0.02f, 0.02f, 0.03f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Scene initialized");
		Console.WriteLine("  {} objects in world", mWorld.MeshCount);
		Console.WriteLine("  WASD/QE: move, Right-click: look, Tab: capture, Shift: fast");
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

	private void CreateMeshes()
	{
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let handle))
			mCubeMeshHandle = handle;
		delete cubeMesh;
	}

	private void CreateMaterials()
	{
		if (let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			// 5 distinct colors
			Vector4[5] colors = .(
				.(0.9f, 0.2f, 0.2f, 1.0f),  // Red
				.(0.2f, 0.9f, 0.2f, 1.0f),  // Green
				.(0.2f, 0.2f, 0.9f, 1.0f),  // Blue
				.(0.9f, 0.9f, 0.2f, 1.0f),  // Yellow
				.(0.9f, 0.2f, 0.9f, 1.0f)   // Magenta
			);

			for (int i = 0; i < 5; i++)
			{
				let mat = new MaterialInstance(baseMat);
				mat.SetColor("BaseColor", colors[i]);
				mat.SetFloat("Roughness", 0.5f);
				mCubeMaterials[i] = mat;
			}
		}
	}

	private void CreateScene()
	{
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// 20x20x3 grid = 1200 cubes
		let gridW = 20;
		let gridD = 20;
		let layers = 3;
		let spacing = 3.0f;
		let offsetX = (gridW - 1) * spacing * 0.5f;
		let offsetZ = (gridD - 1) * spacing * 0.5f;

		for (int layer = 0; layer < layers; layer++)
		{
			for (int z = 0; z < gridD; z++)
			{
				for (int x = 0; x < gridW; x++)
				{
					let matIndex = (x + z + layer) % 5;
					let material = mCubeMaterials[matIndex] ?? defaultMaterial;

					let cubeProxy = mWorld.CreateMesh();
					if (let proxy = mWorld.GetMesh(cubeProxy))
					{
						proxy.MeshHandle = mCubeMeshHandle;
						proxy.Materials[0] = material;
						proxy.MaterialCount = 1;
						proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));

						let position = Vector3(
							x * spacing - offsetX,
							0.5f + layer * 2.0f,
							z * spacing - offsetZ
						);
						proxy.SetTransformImmediate(Matrix.CreateTranslation(position));
						proxy.Flags = .DefaultOpaque;
					}
				}
			}
		}
	}

	private void CreateLights()
	{
		// Directional sun
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(-0.5f, -1.0f, -0.3f)),
			.(1.0f, 0.95f, 0.8f),
			2.0f
		);
		if (let light = mWorld.GetLight(mSunLight))
			light.CastsShadows = true;
		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;

		// 16 scattered point lights
		for (int i = 0; i < 16; i++)
		{
			float angle = i * (Math.PI_f * 2.0f / 16.0f);
			float radius = 15.0f + (i % 3) * 5.0f;
			Vector3 pos = .(Math.Cos(angle) * radius, 2.0f + (i % 4), Math.Sin(angle) * radius);

			// Varied colors
			float hue = (float)i / 16.0f * Math.PI_f * 2.0f;
			Vector3 color = .(
				Math.Max(0, Math.Cos(hue)),
				Math.Max(0, Math.Cos(hue - Math.PI_f * 2.0f / 3.0f)),
				Math.Max(0, Math.Cos(hue - Math.PI_f * 4.0f / 3.0f))
			);
			// Ensure minimum brightness
			color += .(0.2f, 0.2f, 0.2f);

			mPointLights.Add(mWorld.CreatePointLight(pos, color, 8.0f, 12.0f));
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

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;

		let keyboard = mShell.InputManager.Keyboard;
		float speed = keyboard.IsKeyDown(.LeftShift) ? FastMoveSpeed : MoveSpeed;

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
		for (let mat in mCubeMaterials)
			mat?.ReleaseRef();

		if (mCubeMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Render Scene shutting down");
	}
}

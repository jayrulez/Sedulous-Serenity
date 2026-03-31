namespace RenderLighting;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Runtime.Client;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;

/// Lighting sample demonstrating directional light, 7 point lights, shadows,
/// and PBR materials with varying metallic/roughness via the Sedulous.Render pipeline.
class RenderLightingApp : Application
{
	// Render system
	private RenderSystem mRenderSystem;
	private RenderWorld mWorld;
	private RenderView mView;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Meshes
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;
	private List<MeshProxyHandle> mCubeProxies = new .() ~ delete _;
	private MeshProxyHandle mFloorProxy;

	// Lights
	private LightProxyHandle mSunLight = .Invalid;
	private List<LightProxyHandle> mPointLights = new .() ~ delete _;

	// Materials
	private List<MaterialInstance> mMaterials = new .() ~ { for (let m in _) m?.ReleaseRef(); delete _; };

	// Camera
	private Vector3 mCameraPosition = .(0, 5, 15);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.2f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 8.0f;
	private const float FastMoveSpeed = 16.0f;
	private const float LookSpeed = 0.003f;

	public this() : base()
	{
	}

	protected override void OnInitialize(Sedulous.Runtime.Context context)
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, mSwapChain.Width, mSwapChain.Height, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), null, .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
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
		CreateMeshes();
		CreateSceneObjects();
		CreateLights();

		mWorld.AmbientColor = .(0.02f, 0.02f, 0.03f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Lighting initialized");
		Console.WriteLine("  {} cubes, 1 floor, {} lights", mCubeProxies.Count, 1 + mPointLights.Count);
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
		let cubeMesh = MeshBuilder.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let handle))
			mCubeMeshHandle = handle;
		delete cubeMesh;

		let planeMesh = MeshBuilder.CreatePlane(40.0f, 40.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let handle2))
			mPlaneMeshHandle = handle2;
		delete planeMesh;
	}

	private void CreateSceneObjects()
	{
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial;

		// Floor
		MaterialInstance floorMat = null;
		if (baseMaterial != null)
		{
			floorMat = new MaterialInstance(baseMaterial);
			floorMat.SetColor("BaseColor", .(0.6f, 0.6f, 0.6f, 1.0f));
			floorMat.SetFloat("Roughness", 0.8f);
			floorMat.SetFloat("Metallic", 0.0f);
			mMaterials.Add(floorMat);
		}

		mFloorProxy = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(mFloorProxy))
		{
			proxy.MeshHandle = mPlaneMeshHandle;
			proxy.Materials[0] = floorMat ?? defaultMaterial;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-20, 0, -20), Vector3(20, 0.01f, 20)));
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}

		// 11x11 grid of cubes with varying material
		let gridSize = 11;
		let spacing = 2.5f;
		let offset = (gridSize - 1) * spacing * 0.5f;

		for (int z = 0; z < gridSize; z++)
		{
			for (int x = 0; x < gridSize; x++)
			{
				float metallic = (float)x / (float)(gridSize - 1);
				float roughness = Math.Max(0.1f, (float)z / (float)(gridSize - 1));

				MaterialInstance cubeMat = null;
				if (baseMaterial != null)
				{
					cubeMat = new MaterialInstance(baseMaterial);
					cubeMat.SetColor("BaseColor", .(0.8f, 0.3f, 0.3f, 1.0f));
					cubeMat.SetFloat("Metallic", metallic);
					cubeMat.SetFloat("Roughness", roughness);
					mMaterials.Add(cubeMat);
				}

				let cubeProxy = mWorld.CreateMesh();
				if (let proxy = mWorld.GetMesh(cubeProxy))
				{
					proxy.MeshHandle = mCubeMeshHandle;
					proxy.Materials[0] = cubeMat ?? defaultMaterial;
					proxy.MaterialCount = 1;
					proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));

					let position = Vector3(x * spacing - offset, 0.5f, z * spacing - offset);
					proxy.SetTransformImmediate(Matrix.CreateTranslation(position));
					proxy.Flags = .DefaultOpaque;
				}
				mCubeProxies.Add(cubeProxy);
			}
		}

		// 4 corner pillars (4 cubes stacked each)
		float[2] pillarPositions = .(-8.0f, 8.0f);
		for (let px in pillarPositions)
		{
			for (let pz in pillarPositions)
			{
				MaterialInstance pillarMat = null;
				if (baseMaterial != null)
				{
					pillarMat = new MaterialInstance(baseMaterial);
					pillarMat.SetColor("BaseColor", .(0.7f, 0.7f, 0.7f, 1.0f));
					pillarMat.SetFloat("Roughness", 0.3f);
					pillarMat.SetFloat("Metallic", 0.0f);
					mMaterials.Add(pillarMat);
				}

				for (int h = 0; h < 4; h++)
				{
					let cubeProxy = mWorld.CreateMesh();
					if (let proxy = mWorld.GetMesh(cubeProxy))
					{
						proxy.MeshHandle = mCubeMeshHandle;
						proxy.Materials[0] = pillarMat ?? defaultMaterial;
						proxy.MaterialCount = 1;
						proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
						proxy.SetTransformImmediate(Matrix.CreateTranslation(.(px, 0.5f + h, pz)));
						proxy.Flags = .DefaultOpaque;
					}
					mCubeProxies.Add(cubeProxy);
				}
			}
		}
	}

	private void CreateLights()
	{
		// Dim directional light so point lights are more visible
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -1.0f, 0.3f)),
			.(1.0f, 0.98f, 0.95f),
			0.3f
		);
		if (let light = mWorld.GetLight(mSunLight))
		{
			light.CastsShadows = false;
			light.Intensity = 0.3f; // Low intensity to make point lights visible
		}

		// Bright colored point lights
		Vector3 position; Vector3 color;

		position = .(-3, 2, 3); color = .(1.0f, 0.0f, 0.0f);   // Pure Red
		mPointLights.Add(mWorld.CreatePointLight(position, color, 8.0f, 12.0f));

		position = .(3, 2, 3); color = .(0.0f, 1.0f, 0.0f);    // Pure Green
		mPointLights.Add(mWorld.CreatePointLight(position, color, 8.0f, 12.0f));

		position = .(-3, 2, -3); color = .(0.0f, 0.0f, 1.0f);  // Pure Blue
		mPointLights.Add(mWorld.CreatePointLight(position, color, 8.0f, 12.0f));

		position = .(3, 2, -3); color = .(1.0f, 1.0f, 0.0f);   // Yellow
		mPointLights.Add(mWorld.CreatePointLight(position, color, 8.0f, 12.0f));

		position = .(0, 3, 0); color = .(1.0f, 1.0f, 1.0f);    // White center
		mPointLights.Add(mWorld.CreatePointLight(position, color, 10.0f, 15.0f));

		position = .(-6, 2, 0); color = .(1.0f, 0.0f, 1.0f);   // Magenta
		mPointLights.Add(mWorld.CreatePointLight(position, color, 8.0f, 12.0f));

		position = .(6, 2, 0); color = .(0.0f, 1.0f, 1.0f);    // Cyan
		mPointLights.Add(mWorld.CreatePointLight(position, color, 8.0f, 12.0f));
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

	protected override void OnResize(int32 width, int32 height)
	{
		mRenderSystem?.SetViewportSize((uint32)width, (uint32)height);
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

		if (mRenderSystem != null)
		{
			if (mCubeMeshHandle.IsValid)
				mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
			if (mPlaneMeshHandle.IsValid)
				mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);

			mRenderSystem.Shutdown();
			delete mRenderSystem;
			mRenderSystem = null;
		}
		delete mWorld;
		delete mView;

		Console.WriteLine("Render Lighting shutting down");
	}
}

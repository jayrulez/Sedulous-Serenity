namespace RenderScene;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Runtime.Client;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;

/// Scene management sample demonstrating large-scale rendering with 5000+ objects,
/// GPU instancing, LOD system, curve decals, and performance statistics.
class RenderSceneApp : Application
{
	// Render system (cleaned up in OnShutdown before device destruction)
	private RenderSystem mRenderSystem;
	private RenderWorld mWorld;
	private RenderView mView;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private DecalFeature mDecalFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Meshes
	private GPUMeshHandle mCubeMeshHandle;

	// Materials
	private MaterialInstance[5] mCubeMaterials;

	// Lights
	private LightRenderHandle mSunLight = .Invalid;
	private List<LightRenderHandle> mPointLights = new .() ~ delete _;

	// Curve decal
	private CurveDecalRenderHandle mCurveDecal = .Invalid;

	// Camera
	private Vector3 mCameraPosition = .(0, 25, 60);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.3f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 20.0f;
	private const float FastMoveSpeed = 60.0f;
	private const float LookSpeed = 0.003f;

	// LOD bias cycling
	private int32 mLODBiasIndex = 1; // Default: 1.0
	private static float[3] sLODBiases = .(0.5f, 1.0f, 2.0f);

	// Stats display
	private float mStatsTimer = 0.0f;
	private int32 mLastDrawCalls = 0;
	private int32 mLastShadowDrawCalls = 0;
	private int32 mLastTriangleCount = 0;

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
		mView.FarPlane = 300.0f;

		RegisterFeatures();
		CreateMeshes();
		CreateMaterials();
		CreateScene();
		CreateLights();
		CreateCurveDecal();

		mWorld.AmbientColor = .(0.02f, 0.02f, 0.03f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Scene initialized (Phase 6 demo)");
		Console.WriteLine("  {} objects in world", mWorld.MeshCount);
		Console.WriteLine("  WASD/QE: move, Right-click: look, Tab: capture, Shift: fast");
		Console.WriteLine("  I: toggle instancing, L: cycle LOD bias");
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

		mDecalFeature = new DecalFeature();
		if (mRenderSystem.RegisterFeature(mDecalFeature) case .Err)
			Console.WriteLine("Warning: Failed to register DecalFeature");

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
	}

	private void CreateMaterials()
	{
		if (let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
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

		// 25x25x8 grid = 5000 cubes
		let gridW = 25;
		let gridD = 25;
		let layers = 8;
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
							0.5f + layer * 2.5f,
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
			float radius = 20.0f + (i % 3) * 8.0f;
			Vector3 pos = .(Math.Cos(angle) * radius, 3.0f + (i % 4) * 2, Math.Sin(angle) * radius);

			float hue = (float)i / 16.0f * Math.PI_f * 2.0f;
			Vector3 color = .(
				Math.Max(0, Math.Cos(hue)),
				Math.Max(0, Math.Cos(hue - Math.PI_f * 2.0f / 3.0f)),
				Math.Max(0, Math.Cos(hue - Math.PI_f * 4.0f / 3.0f))
			);
			color += .(0.2f, 0.2f, 0.2f);

			mPointLights.Add(mWorld.CreatePointLight(pos, color, 8.0f, 15.0f));
		}
	}

	private void CreateCurveDecal()
	{
		mCurveDecal = mWorld.CreateCurveDecal();
		if (let proxy = mWorld.GetCurveDecal(mCurveDecal))
		{
			// Create a sinusoidal curve through the scene at ground level
			let pointCount = 20;
			proxy.PointCount = (int32)pointCount;

			for (int32 i = 0; i < pointCount; i++)
			{
				float t = (float)i / (float)(pointCount - 1);
				float x = -30.0f + t * 60.0f;
				float z = Math.Sin(t * Math.PI_f * 3.0f) * 15.0f;

				proxy.ControlPoints[i] = .()
				{
					Position = .(x, 0.6f, z),
					Width = 2.0f,
					UV_V = t
				};
			}

			proxy.Color = .(1.0f, 0.8f, 0.3f, 0.7f);
			proxy.UVTilingU = 1.0f;
			proxy.UVTilingV = 3.0f;
			proxy.ProjectionDepth = 2.0f;
			proxy.BlendMode = .Alpha;
			proxy.RecalculateBounds();
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

		// Toggle instancing
		if (keyboard.IsKeyPressed(.I))
		{
			mWorld.InstancingEnabled = !mWorld.InstancingEnabled;
			Console.WriteLine("Instancing: {}", mWorld.InstancingEnabled ? "ON" : "OFF");
		}

		// Cycle LOD bias
		if (keyboard.IsKeyPressed(.L))
		{
			mLODBiasIndex = (mLODBiasIndex + 1) % 3;
			mWorld.LODBias = sLODBiases[mLODBiasIndex];
			Console.WriteLine("LOD Bias: {}", mWorld.LODBias);
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
		mView.UpdateMatrices();

		// Print stats periodically
		mStatsTimer += dt;
		if (mStatsTimer >= 2.0f)
		{
			mStatsTimer = 0.0f;
			let stats = mRenderSystem.Stats;
			let batchStats = mDepthFeature?.Batcher?.Stats ?? .();

			if (stats.DrawCalls != mLastDrawCalls || stats.ShadowDrawCalls != mLastShadowDrawCalls)
			{
				Console.WriteLine("[Stats] Draws:{} Shadow:{} Tris:{} InstGroups:{}/{} Efficiency:{}",
					stats.DrawCalls, stats.ShadowDrawCalls, stats.TriangleCount,
					batchStats.OpaqueInstanceGroupCount, batchStats.TransparentInstanceGroupCount,
					batchStats.InstancingEfficiency);
				mLastDrawCalls = stats.DrawCalls;
				mLastShadowDrawCalls = stats.ShadowDrawCalls;
				mLastTriangleCount = stats.TriangleCount;
			}
		}
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
		for (let mat in mCubeMaterials)
			mat?.ReleaseRef();

		mWorld?.Dispose();

		if (mRenderSystem != null)
		{
			if (mCubeMeshHandle.IsValid)
				mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);

			mRenderSystem.Shutdown();
			delete mRenderSystem;
			mRenderSystem = null;
		}
		delete mWorld;
		delete mView;

		Console.WriteLine("Render Scene shutting down");
	}
}

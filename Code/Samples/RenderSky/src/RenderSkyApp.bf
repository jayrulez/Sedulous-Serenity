namespace RenderSky;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Framework.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;
using Sedulous.Imaging;

/// Sky mode demo: cycles through Gradient, Solid Color, and HDRI sky modes
/// with a 5x5 PBR sphere grid to visualize IBL reflections.
class RenderSkyApp : Application
{
	private RenderSystem mRenderSystem;
	private RenderWorld mWorld;
	private RenderView mView;

	// Features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Meshes
	private GPUMeshHandle mSphereMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;

	// Lights
	private LightProxyHandle mSunLight = .Invalid;
	private float mLightYaw = 2.5f;
	private float mLightPitch = -0.3f;

	// Materials
	private List<MaterialInstance> mMaterials = new .() ~ { for (let m in _) m?.ReleaseRef(); delete _; };

	// Sky mode cycling
	private enum SkyModeOption { Gradient, SolidColor, HDRI }
	private SkyModeOption mCurrentSkyMode = .Gradient;

	// Camera
	private Vector3 mCameraPosition = .(0, 2, 10);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.1f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;

	public this(IShell shell, IDevice device, IBackend backend) : base(shell, device, backend) { }

	protected override void OnInitialize(Sedulous.Framework.Core.Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();
		Sedulous.Imaging.STB.STBImageLoader.Initialize();

		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{ Console.WriteLine("ERROR: Failed to initialize RenderSystem"); return; }

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

		// Start with gradient sky
		SetGradientSky();

		mWorld.AmbientColor = .(0.15f, 0.15f, 0.18f);
		mWorld.AmbientIntensity = 0.1f;
		mWorld.Exposure = 0.1f;

		Console.WriteLine("Render Sky initialized");
		Console.WriteLine("  5x5 sphere grid: Metallic (left-right) x Roughness (front-back)");
		Console.WriteLine("  WASD/QE: move, Right-click: look, ESC: exit");
		Console.WriteLine("  Arrow keys: adjust light direction");
		Console.WriteLine("  T: cycle sky mode (Gradient / Solid Color / HDRI)");
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

	private void CreateScene()
	{
		let sphereMesh = StaticMesh.CreateSphere(0.5f, 32, 16);
		if (mRenderSystem.ResourceManager.UploadMesh(sphereMesh) case .Ok(let h)) mSphereMeshHandle = h;
		delete sphereMesh;

		let planeMesh = StaticMesh.CreatePlane(20.0f, 20.0f, 1, 1);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let h2)) mPlaneMeshHandle = h2;
		delete planeMesh;

		let defaultMat = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial;

		// Floor
		let floor = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(floor))
		{
			proxy.MeshHandle = mPlaneMeshHandle;
			proxy.Materials[0] = defaultMat;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-10, 0, -10), Vector3(10, 0.01f, 10)));
			proxy.SetTransformImmediate(Matrix.CreateTranslation(.(0, -0.5f, 0)));
			proxy.Flags = .DefaultOpaque;
		}

		// 5x5 sphere grid
		let gridSize = 5;
		let spacing = 1.5f;
		let offset = (gridSize - 1) * spacing * 0.5f;

		for (int row = 0; row < gridSize; row++)
		{
			for (int col = 0; col < gridSize; col++)
			{
				float metallic = (float)col / (float)(gridSize - 1);
				float roughness = Math.Max(0.1f, (float)row / (float)(gridSize - 1));

				MaterialInstance mat = null;
				if (baseMat != null)
				{
					mat = new MaterialInstance(baseMat);
					mat.SetColor("BaseColor", .(0.8f, 0.2f, 0.2f, 1.0f));
					mat.SetFloat("Metallic", metallic);
					mat.SetFloat("Roughness", roughness);
					mMaterials.Add(mat);
				}

				let sphere = mWorld.CreateMesh();
				if (let proxy = mWorld.GetMesh(sphere))
				{
					proxy.MeshHandle = mSphereMeshHandle;
					proxy.Materials[0] = mat ?? defaultMat;
					proxy.MaterialCount = 1;
					proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f)));
					let pos = Vector3(col * spacing - offset, 0.5f, row * spacing - offset);
					proxy.SetTransformImmediate(Matrix.CreateTranslation(pos));
					proxy.Flags = .DefaultOpaque;
				}
			}
		}
	}

	private void CreateLights()
	{
		let lightDir = GetLightDirection();
		mSunLight = mWorld.CreateDirectionalLight(lightDir, .(1.0f, 1.0f, 1.0f), 2.0f);
		if (let light = mWorld.GetLight(mSunLight)) light.CastsShadows = true;
		if (mForwardFeature?.ShadowRenderer != null) mForwardFeature.ShadowRenderer.EnableShadows = true;
	}

	private Vector3 GetLightDirection()
	{
		float cosP = Math.Cos(mLightPitch);
		return Vector3.Normalize(.(
			Math.Sin(mLightYaw) * cosP,
			Math.Sin(mLightPitch),
			Math.Cos(mLightYaw) * cosP
		));
	}

	private void UpdateLightDirection()
	{
		if (let light = mWorld.GetLight(mSunLight))
			light.Direction = GetLightDirection();
	}

	// ==================== Sky Mode Cycling ====================

	private void SetGradientSky()
	{
		mSkyFeature.CreateGradientSkyWithGround(
			.(100, 150, 220, 255),   // top: blue sky
			.(200, 210, 220, 255),   // horizon: pale blue-white
			.(80, 70, 60, 255));     // ground: dark earth
	}

	private void SetSolidColorSky()
	{
		mSkyFeature.Mode = .SolidColor;
		mSkyFeature.SolidColor = .(0.3f, 0.4f, 0.6f);
		mSkyFeature.RegenerateIBL();
	}

	private void SetHDRISky()
	{
		let hdrPath = scope $"{AssetDirectory}/Render/textures/environment/BlueSky.hdr";
		if (ImageLoaderFactory.LoadImage(hdrPath) case .Ok(var image))
		{
			defer delete image;
			let texData = TextureData.FromImage(image);
			if (mSkyFeature.SetEnvironmentMapEquirect(texData) case .Ok)
			{
				Console.WriteLine("  HDRI loaded ({}x{})", image.Width, image.Height);
			}
			else
			{
				Console.WriteLine("  ERROR: Failed to set HDRI environment map");
			}
		}
		else
		{
			Console.WriteLine("  ERROR: Failed to load HDR image: {}", hdrPath);
		}
	}

	private void CycleSkyMode()
	{
		switch (mCurrentSkyMode)
		{
		case .Gradient:
			mCurrentSkyMode = .SolidColor;
			SetSolidColorSky();
			Console.WriteLine("Sky: Solid Color");
		case .SolidColor:
			mCurrentSkyMode = .HDRI;
			SetHDRISky();
			Console.WriteLine("Sky: HDRI");
		case .HDRI:
			mCurrentSkyMode = .Gradient;
			SetGradientSky();
			Console.WriteLine("Sky: Gradient");
		}
	}

	// ==================== Input / Update / Render ====================

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;
		if (keyboard.IsKeyPressed(.Escape)) Exit();
		if (keyboard.IsKeyPressed(.T)) CycleSkyMode();
		if (keyboard.IsKeyPressed(.Tab))
		{ mMouseCaptured = !mMouseCaptured; mouse.RelativeMode = mMouseCaptured; mouse.Visible = !mMouseCaptured; }
		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{ mYaw += mouse.DeltaX * 0.003f; mPitch -= mouse.DeltaY * 0.003f; mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f); }
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;
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

		// Light direction control with arrow keys
		float lightSpeed = 1.0f * dt;
		bool lightChanged = false;
		if (keyboard.IsKeyDown(.Left))  { mLightYaw -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Right)) { mLightYaw += lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Up))    { mLightPitch -= lightSpeed; lightChanged = true; }
		if (keyboard.IsKeyDown(.Down))  { mLightPitch += lightSpeed; lightChanged = true; }
		mLightPitch = Math.Clamp(mLightPitch, -Math.PI_f * 0.45f, -0.1f);
		if (lightChanged) UpdateLightDirection();

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
		if (mFinalOutputFeature != null) mFinalOutputFeature.SetSwapChain(render.SwapChain);
		mRenderSystem.SetCamera(mCameraPosition, mCameraForward, .(0, 1, 0), mView.FieldOfView, mView.AspectRatio, mView.NearPlane, mView.FarPlane, mView.Width, mView.Height);
		if (mRenderSystem.BuildRenderGraph(mView) case .Ok) mRenderSystem.Execute(render.Encoder);
		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnShutdown()
	{
		mWorld?.Dispose();

		if (mSphereMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mSphereMeshHandle, mRenderSystem.FrameNumber);
		if (mPlaneMeshHandle.IsValid) mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);
		mRenderSystem?.Shutdown();

		delete mWorld; mWorld = null;
		delete mView; mView = null;
		delete mRenderSystem; mRenderSystem = null;

		Console.WriteLine("Render Sky shutting down");
	}
}

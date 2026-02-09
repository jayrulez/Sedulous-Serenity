namespace RenderStaticMesh;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Framework.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Imaging;
using Sedulous.Textures.Resources;

/// Static mesh sample demonstrating GLTF model loading, texture application,
/// and PBR rendering via the Sedulous.Render pipeline.
class RenderStaticMeshApp : Application
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

	// Model resources
	private Model mModel ~ delete _;
	private ModelImportResult mImportResult ~ delete _;
	private GPUMeshHandle mMeshHandle;
	private GPUTextureHandle mTextureHandle;
	private MeshProxyHandle mMeshProxy;
	private MaterialInstance mMaterial ~ _?.ReleaseRef();

	// Lighting
	private LightProxyHandle mSunLight;

	// Camera
	private Vector3 mCameraPosition = .(0, 1, 3);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.1f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 5.0f;
	private const float FastMoveSpeed = 10.0f;
	private const float LookSpeed = 0.003f;

	// Animation
	private float mModelRotation = 0;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Framework.Core.Context context)
	{
		// Initialize render system
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
		mView.FarPlane = 100.0f;

		RegisterFeatures();
		LoadModel();
		CreateLights();

		mWorld.AmbientColor = .(0.05f, 0.05f, 0.08f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Static Mesh initialized");
		Console.WriteLine("  WASD: move camera");
		Console.WriteLine("  Q/E: move down/up");
		Console.WriteLine("  Right-click + drag: look around");
		Console.WriteLine("  Tab: toggle mouse capture");
		Console.WriteLine("  Shift: move faster");
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

	private void LoadModel()
	{
		GltfModels.Initialize();

		let modelPath = scope $"{AssetDirectory}/samples/models/Duck/glTF/Duck.gltf";
		let gltfBasePath = scope $"{AssetDirectory}/samples/models/Duck/glTF";
		Console.WriteLine("Loading model from: {}", modelPath);

		mModel = new Model();
		if (ModelLoaderFactory.LoadModel(modelPath, mModel) != .Ok)
		{
			Console.WriteLine("ERROR: Failed to load model");
			delete mModel;
			mModel = null;
			return;
		}

		// Import using ModelImporter
		let importOptions = new ModelImportOptions();
		importOptions.Flags = .Meshes | .Textures | .Materials;
		importOptions.BasePath.Set(gltfBasePath);

		let importer = scope ModelImporter(importOptions);
		mImportResult = importer.Import(mModel);

		if (!mImportResult.Success)
		{
			for (let err in mImportResult.Errors)
				Console.WriteLine("  Import error: {}", err);
			return;
		}

		Console.WriteLine("  Imported: {} meshes, {} textures",
			mImportResult.StaticMeshes.Count, mImportResult.Textures.Count);

		// Upload mesh from import result
		if (mImportResult.StaticMeshes.Count > 0)
		{
			let staticMesh = mImportResult.StaticMeshes[0].Mesh;
			if (mRenderSystem.ResourceManager.UploadMesh(staticMesh) case .Ok(let handle))
			{
				mMeshHandle = handle;
				Console.WriteLine("  Uploaded mesh: {} vertices, {} indices",
					staticMesh.Vertices.VertexCount, staticMesh.Indices.IndexCount);
			}
		}

		// Upload texture from import result
		UploadTextureFromImportResult();

		// Create mesh proxy
		CreateMeshProxy();
	}

	private void UploadTextureFromImportResult()
	{
		if (mImportResult == null || mImportResult.Textures.Count == 0)
			return;

		let texResource = mImportResult.Textures[0];
		let image = texResource.Image;
		if (image == null || image.Width == 0 || image.Height == 0)
			return;

		Console.WriteLine("  Texture: {}x{} ({})", image.Width, image.Height, image.Format);

		let gpuFormat = ConvertPixelFormat(image.Format);
		let texData = TextureData.Create2D(image.Data.Ptr, (uint64)image.Data.Length, image.Width, image.Height, gpuFormat);
		if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let texHandle))
		{
			mTextureHandle = texHandle;
			Console.WriteLine("  Uploaded texture to GPU");
		}
	}

	private void CreateMeshProxy()
	{
		if (!mMeshHandle.IsValid) return;

		// Create material
		if (let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			mMaterial = new MaterialInstance(baseMaterial);

			if (mTextureHandle.IsValid)
			{
				if (let texView = mRenderSystem.ResourceManager.GetTextureView(mTextureHandle))
					mMaterial.SetTexture("AlbedoMap", texView);
			}
		}

		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		mMeshProxy = mWorld.CreateMesh();
		if (let proxy = mWorld.GetMesh(mMeshProxy))
		{
			proxy.MeshHandle = mMeshHandle;
			proxy.Materials[0] = mMaterial ?? defaultMaterial;
			proxy.MaterialCount = 1;
			proxy.SetLocalBounds(BoundingBox(Vector3(-1, -1, -1), Vector3(1, 1, 1)));
			proxy.SetTransformImmediate(.Identity);
			proxy.Flags = .DefaultOpaque;
		}
	}

	private void CreateLights()
	{
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -1.0f, 0.3f)),
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

		// Rotate model
		mModelRotation += dt * 0.3f;
		if (let proxy = mWorld.GetMesh(mMeshProxy))
		{
			let transform = Matrix.CreateScale(0.012f) * Matrix.CreateRotationY(mModelRotation);
			proxy.SetTransformImmediate(transform);
		}

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

	private static TextureFormat ConvertPixelFormat(Sedulous.Imaging.Image.PixelFormat format)
	{
		switch (format)
		{
		case .R8:       return .R8Unorm;
		case .RG8:      return .RG8Unorm;
		case .RGB8:     return .RGBA8Unorm;
		case .RGBA8:    return .RGBA8Unorm;
		case .BGR8:     return .BGRA8Unorm;
		case .BGRA8:    return .BGRA8Unorm;
		case .R16F:     return .R16Float;
		case .RG16F:    return .RG16Float;
		case .RGB16F:   return .RGBA16Float;
		case .RGBA16F:  return .RGBA16Float;
		case .R32F:     return .R32Float;
		case .RG32F:    return .RG32Float;
		case .RGB32F:   return .RGBA32Float;
		case .RGBA32F:  return .RGBA32Float;
		default:        return .RGBA8Unorm;
		}
	}

	protected override void OnShutdown()
	{
		if (mMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mMeshHandle, mRenderSystem.FrameNumber);
		if (mTextureHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseTexture(mTextureHandle, mRenderSystem.FrameNumber);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Render Static Mesh shutting down");
	}
}

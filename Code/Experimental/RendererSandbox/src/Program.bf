namespace RendererSandbox;

using System;
using System.Collections;
using System.IO;
using Sedulous.RHI;
using Sedulous.Renderer;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Core.Mathematics;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.Imaging;
using Sedulous.Imaging.STB;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Animation;
using RendererFramework;

using cimgui_Beef;

/// Sandbox application demonstrating Phase 5: Depth Prepass + Forward PBR + Tonemap.
class SandboxApp : Application
{
	private DxcShaderCompiler mShaderCompiler;

	// Render features
	private DepthPrepassFeature mDepthPrepass;
	private ForwardOpaqueFeature mForwardOpaque;
	private ForwardTransparentFeature mForwardTransparent;
	private SkyFeature mSky;
	private MotionVectorFeature mMotionVectors;
	private PostProcessStack mPostProcess;
	private TAAEffect mTAAEffect;
	private BloomEffect mBloomEffect;
	private TonemapEffect mTonemapEffect;
	private BlitToScreenFeature mBlitToScreen;
	private ImGuiFeature mImGui;

	// Reflection probes
	private ReflectionProbeProxyHandle mSceneProbe;
	private bool mReflectionProbesEnabled = true;

	// Materials
	private MaterialDefinition mPBRMatDef;
	private MaterialDefinition mTransparentMatDef;
	private ISampler mMaterialSampler;
	private List<MaterialInstanceHandle> mMaterialHandles = new .() ~ delete _;

	// Meshes
	private GPUMeshHandle mSphereMesh;
	private GPUMeshHandle mCubeMesh;
	private GPUMeshHandle mPlaneMesh;
	private GPUMeshHandle mTorusMesh;

	// Sky & IBL
	private ITexture mSkyTexture;
	private ITextureView mSkyTextureView;
	private ITexture mBrdfLutTexture;
	private ITextureView mBrdfLutTextureView;

	// Scene proxies
	private List<StaticMeshProxyHandle> mProxies = new .() ~ delete _;
	private List<LightProxyHandle> mLightHandles = new .() ~ delete _;

	// Skinned mesh demo
	private SkinnedMeshProxyHandle mFoxProxy;
	private GPUMeshHandle mFoxMesh;
	private GPUBoneBufferHandle mFoxBoneBuffer;
	private Skeleton mFoxSkeleton ~ delete _;
	private List<AnimationClip> mFoxAnimations = new .() ~ DeleteContainerAndItems!(_);
	private int mCurrentAnimIndex;
	private float mAnimTime;
	private bool mAnimPlaying = true;
	private float mAnimSpeed = 1.0f;
	private Matrix[] mPrevSkinningMatrices ~ delete _;

	// Sun/light settings (mutable via ImGui)
	private float mSunYaw = 0.46f;       // atan2(0.3, 0.5) ≈ initial direction
	private float mSunPitch = -1.1f;     // asin(-1/sqrt(1.34)) ≈ initial direction
	private float[3] mSunColor = .(1.0f, 0.98f, 0.95f);
	private float mSunIntensity = 1.0f;

	// Camera control
	private float mCamYaw = 0.0f;
	private float mCamPitch = 0.3f;
	private float mCamDistance = 8.0f;
	private Vector3 mCamTarget = .(0.0f, 0.5f, 0.0f);
	private float mMoveSpeed = 5.0f;
	private float mMouseSensitivity = 0.003f;

	public this() : base(.Vulkan, true)
	{
	}

	protected override StringView Title => "Renderer Sandbox";

	protected override void OnRegisterFeatures(RenderSystem renderSystem)
	{
		let format = (mBackendType == .Vulkan)
			? ShaderOutputFormat.SPIRV
			: ShaderOutputFormat.DXIL;

		mShaderCompiler = new DxcShaderCompiler(format);
		if (mShaderCompiler.Init() case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize shader compiler");
			return;
		}

		renderSystem.SetShaderCompiler(mShaderCompiler);

		mDepthPrepass = new DepthPrepassFeature();
		mForwardOpaque = new ForwardOpaqueFeature();
		mForwardTransparent = new ForwardTransparentFeature();
		mSky = new SkyFeature();
		mMotionVectors = new MotionVectorFeature();
		mTAAEffect = new TAAEffect();
		mBloomEffect = new BloomEffect();
		mTonemapEffect = new TonemapEffect();
		mPostProcess = new PostProcessStack();
		mPostProcess.RegisterEffect(mTAAEffect);
		mPostProcess.RegisterEffect(mBloomEffect);
		mPostProcess.RegisterEffect(mTonemapEffect);
		mBlitToScreen = new BlitToScreenFeature();
		mImGui = new ImGuiFeature();

		renderSystem.RegisterFeature(mDepthPrepass);
		renderSystem.RegisterFeature(mForwardOpaque);
		renderSystem.RegisterFeature(mSky);             // Before transparent — transparent objects don't write depth
		renderSystem.RegisterFeature(mForwardTransparent);
		renderSystem.RegisterFeature(mMotionVectors);
		renderSystem.RegisterFeature(mPostProcess);     // After motion vectors, before blit
		renderSystem.RegisterFeature(mBlitToScreen);
		renderSystem.RegisterFeature(mImGui); // Must be last — renders on top of everything
	}

	protected override Result<void> OnInit()
	{
		// --- ImGui setup ---
		mImGui.SetQueue(mGraphicsQueue);
		mImGui.SetSwapChainFormat(mSwapChain.Format);

		// --- Sky HDRI ---
		if (LoadSkyTexture() case .Err)
			Console.WriteLine("WARNING: Failed to load sky HDRI, sky will not render");
		else
			mWorld.Environment.HdriTexture = mSkyTextureView;

		// --- BRDF LUT ---
		if (LoadBrdfLut() case .Err)
			Console.WriteLine("WARNING: Skipping BRDF LUT load, using fallback");
		else
			mWorld.Environment.BrdfLutTexture = mBrdfLutTextureView;

		// --- Camera ---
		mView.FieldOfView = 60.0f * (Math.PI_f / 180.0f);
		mView.NearPlane = 0.1f;
		mView.FarPlane = 100.0f;
		mView.CameraUp = Vector3(0.0f, 1.0f, 0.0f);
		UpdateCamera();

		let camHandle = mWorld.CreateCamera();
		mWorld.SetCameraPerspective(camHandle, mView.FieldOfView, mView.NearPlane, mView.FarPlane);
		mWorld.SetCameraLookAt(camHandle, mView.CameraPosition, mCamTarget, mView.CameraUp);
		mWorld.SetMainCamera(camHandle);

		// --- Material definition ---
		if (CreateMaterialDefinition() case .Err)
			return .Err;

		// --- Meshes ---
		if (CreateMeshes() case .Err)
			return .Err;

		// --- Scene objects ---
		if (CreateScene() case .Err)
			return .Err;

		// --- Lights ---
		CreateLights();

		// --- Skinned mesh demo ---
		if (LoadFox() case .Err)
			Console.WriteLine("WARNING: Failed to load Fox model");

		// --- Reflection probe ---
		mSceneProbe = mWorld.CreateReflectionProbe(
			.(0.0f, 1.0f, 0.0f),    // center, slightly above ground
			.(-10.0f, -1.0f, -10.0f), // box min
			.(10.0f, 5.0f, 10.0f)     // box max
		);

		// Bake reflection probes (renders scene from probe positions)
		mRenderSystem.BakeReflectionProbes();

		Console.WriteLine("Renderer Sandbox initialized:");
		Console.WriteLine("  WASD = move camera target, Mouse wheel = zoom, Right-click drag = orbit");

		return .Ok;
	}

	private Result<void> LoadSkyTexture()
	{
		if (!STBImageLoader.Initialized)
			STBImageLoader.Initialize();

		let hdriPath = scope String();
		GetAssetPath("Textures/BlueSky.hdr", hdriPath);

		let imageResult = ImageLoaderFactory.LoadImage(hdriPath);
		if (imageResult case .Err)
			return .Err;
		let image = imageResult.Value;
		defer delete image;

		Console.WriteLine(scope $"Loaded HDRI: {image.Width}x{image.Height}");

		let texResult = mDevice.CreateTexture(TextureDesc.Tex2D(
			.RGBA32Float, image.Width, image.Height,
			.Sampled | .CopyDst, label: "Sky_HdriTexture"));
		if (texResult case .Err)
			return .Err;
		mSkyTexture = texResult.Value;

		// Upload via a sync transfer batch (init time, before rendering starts)
		let batch = mGraphicsQueue.CreateTransferBatch();
		if (batch case .Err)
			return .Err;
		let tb = batch.Value;

		let dataLayout = TextureDataLayout() { Offset = 0, BytesPerRow = image.Width * 16, RowsPerImage = image.Height };
		let extent = Extent3D(image.Width, image.Height, 1);
		tb.WriteTexture(mSkyTexture, image.Data, dataLayout, extent);
		tb.Submit();
		mDevice.WaitIdle(); // Wait for copy to complete before releasing staging buffers
		var tbRef = tb;
		mGraphicsQueue.DestroyTransferBatch(ref tbRef);

		let viewResult = mDevice.CreateTextureView(mSkyTexture, TextureViewDesc() { Label = "Sky_HdriView" });
		if (viewResult case .Err)
			return .Err;
		mSkyTextureView = viewResult.Value;

		return .Ok;
	}

	private Result<void> LoadBrdfLut()
	{
		let brdfPath = scope String();
		GetAssetPath("Textures/BRDFLut.bin", brdfPath);
		Console.WriteLine(brdfPath);

		// Read raw binary (512x512 RG16Float = 1MB)
		let data = scope List<uint8>();
		if (System.IO.File.ReadAll(brdfPath, data) case .Err)
		{
			Console.WriteLine("ERROR: Failed to read BRDF LUT file");
			return .Err;
		}

		if (data.Count != 512 * 512 * 4) // RG16Float = 4 bytes per pixel
		{
			Console.WriteLine(scope $"ERROR: BRDF LUT unexpected size: {data.Count} (expected {512 * 512 * 4})");
			return .Err;
		}

		let texResult = mDevice.CreateTexture(TextureDesc.Tex2D(
			.RG16Float, 512, 512, .Sampled | .CopyDst, label: "BRDFLut"));
		if (texResult case .Err)
		{
			Console.WriteLine("ERROR: Failed to create BRDF LUT texture");
			return .Err;
		}
		mBrdfLutTexture = texResult.Value;

		let batch = mGraphicsQueue.CreateTransferBatch();
		if (batch case .Err)
		{
			Console.WriteLine("ERROR: Failed to create transfer batch for BRDF LUT");
			return .Err;
		}
		let tb = batch.Value;

		let dataLayout = TextureDataLayout() { Offset = 0, BytesPerRow = 512 * 4, RowsPerImage = 512 };
		let extent = Extent3D(512, 512, 1);
		tb.WriteTexture(mBrdfLutTexture, Span<uint8>((uint8*)data.Ptr, data.Count), dataLayout, extent);
		tb.Submit();
		mDevice.WaitIdle(); // Wait for copy to complete before releasing staging buffers
		var tbRef = tb;
		mGraphicsQueue.DestroyTransferBatch(ref tbRef);

		let viewResult = mDevice.CreateTextureView(mBrdfLutTexture, TextureViewDesc() { Label = "BRDFLut_View" });
		if (viewResult case .Err)
		{
			Console.WriteLine("ERROR: Failed to create BRDF LUT texture view");
			return .Err;
		}
		mBrdfLutTextureView = viewResult.Value;

		Console.WriteLine("Loaded BRDF LUT (512x512 RG16Float)");
		return .Ok;
	}

	private Result<void> CreateMaterialDefinition()
	{
		let samplerResult = mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear,
			AddressU = .Repeat,
			AddressV = .Repeat,
			AddressW = .Repeat
		});
		if (samplerResult case .Err)
			return .Err;
		mMaterialSampler = samplerResult.Value;

		mPBRMatDef = new MaterialDefinition();
		mPBRMatDef.Name = new String("PBRDefault");
		mPBRMatDef.ShaderName = new String("forward_pbr");
		mPBRMatDef.BlendMode = .Opaque;
		mPBRMatDef.CullMode = .Back;
		mPBRMatDef.DepthMode = .ReadOnly;

		mPBRMatDef.AddScalarProperty("AlbedoColor", .Float4);
		mPBRMatDef.AddScalarProperty("Metallic", .Float);
		mPBRMatDef.AddScalarProperty("Roughness", .Float);
		mPBRMatDef.AddScalarProperty("AO", .Float);
		mPBRMatDef.AddScalarProperty("EmissiveStrength", .Float);
		mPBRMatDef.AddScalarProperty("EmissiveColor", .Float4);

		mPBRMatDef.AddTextureProperty("AlbedoTex");
		mPBRMatDef.AddTextureProperty("NormalTex");
		mPBRMatDef.AddTextureProperty("MetRoughTex");

		mPBRMatDef.AddSamplerProperty("MaterialSampler");

		if (mPBRMatDef.BuildLayout(mDevice) case .Err)
			return .Err;

		// Transparent PBR material definition — same properties, alpha blend
		mTransparentMatDef = new MaterialDefinition();
		mTransparentMatDef.Name = new String("PBRTransparent");
		mTransparentMatDef.ShaderName = new String("forward_pbr");
		mTransparentMatDef.BlendMode = .AlphaBlend;
		mTransparentMatDef.CullMode = .Back;
		mTransparentMatDef.DepthMode = .ReadOnly;

		mTransparentMatDef.AddScalarProperty("AlbedoColor", .Float4);
		mTransparentMatDef.AddScalarProperty("Metallic", .Float);
		mTransparentMatDef.AddScalarProperty("Roughness", .Float);
		mTransparentMatDef.AddScalarProperty("AO", .Float);
		mTransparentMatDef.AddScalarProperty("EmissiveStrength", .Float);
		mTransparentMatDef.AddScalarProperty("EmissiveColor", .Float4);

		mTransparentMatDef.AddTextureProperty("AlbedoTex");
		mTransparentMatDef.AddTextureProperty("NormalTex");
		mTransparentMatDef.AddTextureProperty("MetRoughTex");
		mTransparentMatDef.AddSamplerProperty("MaterialSampler");

		if (mTransparentMatDef.BuildLayout(mDevice) case .Err)
			return .Err;

		return .Ok;
	}

	private Result<MaterialInstanceHandle> CreateTransparentMaterialInstance(
		float r, float g, float b, float alpha,
		float metallic, float roughness)
	{
		let resources = mRenderSystem.Resources;

		let matResult = mRenderSystem.CreateMaterialInstance(mTransparentMatDef);
		if (matResult case .Err)
			return .Err;
		let handle = matResult.Value;
		mMaterialHandles.Add(handle);

		let matInst = mRenderSystem.GetMaterialInstance(handle);
		if (matInst == null)
			return .Err;

		matInst.SetFloat4("AlbedoColor", r, g, b, alpha);
		matInst.SetFloat("Metallic", metallic);
		matInst.SetFloat("Roughness", roughness);
		matInst.SetFloat("AO", 1.0f);
		matInst.SetFloat("EmissiveStrength", 0.0f);
		matInst.SetFloat4("EmissiveColor", 0.0f, 0.0f, 0.0f, 1.0f);

		matInst.SetTexture(0, resources.GetTextureView(resources.WhiteTexture));
		matInst.SetTexture(1, resources.GetTextureView(resources.FlatNormalTexture));
		matInst.SetTexture(2, resources.GetTextureView(resources.WhiteTexture));
		matInst.SetSampler(0, mMaterialSampler);

		return .Ok(handle);
	}

	private Result<MaterialInstanceHandle> CreateMaterialInstance(
		float r, float g, float b,
		float metallic, float roughness)
	{
		let resources = mRenderSystem.Resources;

		let matResult = mRenderSystem.CreateMaterialInstance(mPBRMatDef);
		if (matResult case .Err)
			return .Err;
		let handle = matResult.Value;
		mMaterialHandles.Add(handle);

		let matInst = mRenderSystem.GetMaterialInstance(handle);
		if (matInst == null)
			return .Err;

		matInst.SetFloat4("AlbedoColor", r, g, b, 1.0f);
		matInst.SetFloat("Metallic", metallic);
		matInst.SetFloat("Roughness", roughness);
		matInst.SetFloat("AO", 1.0f);
		matInst.SetFloat("EmissiveStrength", 0.0f);
		matInst.SetFloat4("EmissiveColor", 0.0f, 0.0f, 0.0f, 1.0f);

		matInst.SetTexture(0, resources.GetTextureView(resources.WhiteTexture));
		matInst.SetTexture(1, resources.GetTextureView(resources.FlatNormalTexture));
		matInst.SetTexture(2, resources.GetTextureView(resources.WhiteTexture));
		matInst.SetSampler(0, mMaterialSampler);

		return .Ok(handle);
	}

	private Result<void> CreateMeshes()
	{
		let res = mRenderSystem.Resources;

		{
			var mesh = MeshBuilder.CreateSphere(0.5f, 32, 16);
			defer delete mesh;
			if (res.UploadMesh(mesh) case .Ok(let h)) mSphereMesh = h;
			else return .Err;
		}
		{
			var mesh = MeshBuilder.CreateCube(1.0f);
			defer delete mesh;
			if (res.UploadMesh(mesh) case .Ok(let h)) mCubeMesh = h;
			else return .Err;
		}
		{
			var mesh = MeshBuilder.CreatePlane(20.0f, 20.0f, 1, 1);
			defer delete mesh;
			if (res.UploadMesh(mesh) case .Ok(let h)) mPlaneMesh = h;
			else return .Err;
		}
		{
			var mesh = MeshBuilder.CreateTorus(0.4f, 0.15f, 32, 16);
			defer delete mesh;
			if (res.UploadMesh(mesh) case .Ok(let h)) mTorusMesh = h;
			else return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateScene()
	{
		let sphereBounds = BoundingBox(Vector3(-0.5f), Vector3(0.5f));
		let cubeBounds = BoundingBox(Vector3(-0.5f), Vector3(0.5f));
		let torusBounds = BoundingBox(Vector3(-0.55f, -0.15f, -0.55f), Vector3(0.55f, 0.15f, 0.55f));
		let planeBounds = BoundingBox(Vector3(-10.0f, 0.0f, -10.0f), Vector3(10.0f, 0.0f, 10.0f));

		// Ground plane — dark gray, non-metallic, rough
		if (AddObject(mPlaneMesh, planeBounds,
			Matrix.CreateTranslation(0.0f, 0.0f, 0.0f),
			0.3f, 0.3f, 0.3f, 0.0f, 0.9f) case .Err) return .Err;

		// ============================================================
		// SECTION 1: Point light shadow demo (left area, X = -6)
		// White spheres in a circle around a central point light
		// ============================================================
		let pointCenter = Vector3(-6.0f, 0.0f, 0.0f);
		let circleRadius = 2.0f;
		let sphereCount = 6;
		for (int i = 0; i < sphereCount; i++)
		{
			let angle = (float)i / (float)sphereCount * Math.PI_f * 2.0f;
			let x = pointCenter.X + Math.Cos(angle) * circleRadius;
			let z = pointCenter.Z + Math.Sin(angle) * circleRadius;
			if (AddObject(mSphereMesh, sphereBounds,
				Matrix.CreateTranslation(x, 0.5f, z),
				0.9f, 0.9f, 0.9f, 0.0f, 0.5f) case .Err) return .Err;
		}

		// ============================================================
		// SECTION 2: Spot light shadow demo (right area, X = +6)
		// A cube and sphere on the ground with a spot light angled at them
		// ============================================================
		let spotCenter = Vector3(6.0f, 0.0f, 0.0f);

		// Tall cube — the main shadow caster
		if (AddObject(mCubeMesh, cubeBounds,
			Matrix.CreateScale(1.0f, 2.0f, 1.0f) * Matrix.CreateTranslation(spotCenter.X, 1.0f, spotCenter.Z),
			0.8f, 0.2f, 0.2f, 0.0f, 0.5f) case .Err) return .Err;

		// Small sphere next to the cube
		if (AddObject(mSphereMesh, sphereBounds,
			Matrix.CreateTranslation(spotCenter.X + 1.5f, 0.5f, spotCenter.Z + 0.5f),
			0.2f, 0.8f, 0.2f, 0.0f, 0.5f) case .Err) return .Err;

		// ============================================================
		// SECTION 3: General scene (center area)
		// ============================================================

		// Torus — cyan, metallic
		if (AddObject(mTorusMesh, torusBounds,
			Matrix.CreateTranslation(0.0f, 0.6f, 2.0f),
			0.1f, 0.8f, 0.8f, 0.8f, 0.3f) case .Err) return .Err;

		// Gold sphere
		if (AddObject(mSphereMesh, sphereBounds,
			Matrix.CreateTranslation(0.0f, 0.5f, 0.0f),
			1.0f, 0.76f, 0.33f, 1.0f, 0.2f) case .Err) return .Err;

		// Bright red cube next to gold sphere (for testing probe reflections)
		if (AddObject(mCubeMesh, cubeBounds,
			Matrix.CreateTranslation(-1.5f, 0.5f, 0.0f),
			1.0f, 0.05f, 0.05f, 0.0f, 0.3f) case .Err) return .Err;

		// Purple cube
		if (AddObject(mCubeMesh, cubeBounds,
			Matrix.CreateTranslation(2.0f, 0.5f, 2.0f),
			0.6f, 0.2f, 0.8f, 0.0f, 0.15f) case .Err) return .Err;

		// ============================================================
		// SECTION 4: Transparent objects
		// ============================================================

		// Transparent red sphere — in front of the gold sphere, partially overlapping
		if (AddTransparentObject(mSphereMesh, sphereBounds,
			Matrix.CreateScale(1.2f) * Matrix.CreateTranslation(0.0f, 0.6f, 2.0f),
			0.9f, 0.1f, 0.1f, 0.35f, 0.0f, 0.3f) case .Err) return .Err;

		// Transparent blue cube — standing alone for clear visibility
		if (AddTransparentObject(mCubeMesh, cubeBounds,
			Matrix.CreateScale(1.5f) * Matrix.CreateTranslation(3.0f, 0.75f, -2.0f),
			0.1f, 0.2f, 0.9f, 0.5f, 0.0f, 0.2f) case .Err) return .Err;

		// Transparent green sphere — overlapping the purple cube to test sorting
		if (AddTransparentObject(mSphereMesh, sphereBounds,
			Matrix.CreateTranslation(2.5f, 0.5f, 2.5f),
			0.1f, 0.9f, 0.2f, 0.4f, 0.0f, 0.5f) case .Err) return .Err;

		return .Ok;
	}

	private Result<void> AddObject(GPUMeshHandle mesh, BoundingBox bounds,
		Matrix transform,
		float r, float g, float b, float metallic, float roughness)
	{
		let matResult = CreateMaterialInstance(r, g, b, metallic, roughness);
		if (matResult case .Err)
			return .Err;
		let matHandle = matResult.Value;

		let proxy = mWorld.CreateStaticMesh();
		mWorld.SetStaticMeshTransform(proxy, transform);
		mWorld.SetStaticMeshData(proxy, mesh, bounds);
		mWorld.SetStaticMeshMaterial(proxy, 0, matHandle);
		mWorld.SetStaticMeshFlags(proxy, .Default);
		mProxies.Add(proxy);

		return .Ok;
	}

	private Result<void> AddTransparentObject(GPUMeshHandle mesh, BoundingBox bounds,
		Matrix transform,
		float r, float g, float b, float alpha, float metallic, float roughness)
	{
		let matResult = CreateTransparentMaterialInstance(r, g, b, alpha, metallic, roughness);
		if (matResult case .Err)
			return .Err;
		let matHandle = matResult.Value;

		let proxy = mWorld.CreateStaticMesh();
		mWorld.SetStaticMeshTransform(proxy, transform);
		mWorld.SetStaticMeshData(proxy, mesh, bounds);
		mWorld.SetStaticMeshMaterial(proxy, 0, matHandle);
		mWorld.SetStaticMeshFlags(proxy, .Default);
		mProxies.Add(proxy);

		return .Ok;
	}

	private Result<void> LoadFox()
	{
		// Register GLTF loader
		if (!ModelLoaderFactory.HasLoaders)
			ModelLoaderFactory.RegisterLoader(new GltfLoader());

		// Load model
		let foxPath = scope String();
		GetAssetPath("Models/Fox/glTF/Fox.gltf", foxPath);

		let model = scope Model();
		let loadResult = ModelLoaderFactory.LoadModel(foxPath, model);
		if (loadResult != .Ok)
		{
			Console.WriteLine(scope $"ERROR: Failed to load Fox model: {loadResult}");
			return .Err;
		}

		// Import skinned mesh + skeleton + animations
		let basePath = scope String();
		GetAssetPath("Models/Fox/glTF", basePath);

		let options = ModelImportOptions.SkinnedWithAnimations();
		options.BasePath.Set(basePath);

		let importer = scope ModelImporter(options);
		let result = importer.Import(model);
		defer delete result;

		if (!result.Success)
		{
			for (let err in result.Errors)
				Console.WriteLine(scope $"Import error: {err}");
			return .Err;
		}

		Console.WriteLine(scope $"Fox import: {result.SkinnedMeshes.Count} skinned meshes, {result.Skeletons.Count} skeletons, {result.Animations.Count} animations");

		if (result.SkinnedMeshes.Count == 0 || result.Skeletons.Count == 0)
		{
			Console.WriteLine("ERROR: No skinned meshes or skeletons found");
			return .Err;
		}

		// Upload skinned mesh
		let skinnedMesh = result.SkinnedMeshes[0];
		let res = mRenderSystem.Resources;

		if (res.UploadMesh(skinnedMesh) case .Ok(let h))
			mFoxMesh = h;
		else
			return .Err;

		// Take ownership of skeleton
		let skeleton = result.Skeletons[0];
		mFoxSkeleton = skeleton;
		result.Skeletons.RemoveAt(0); // prevent double-delete

		// Take ownership of animation clips
		for (int i = 0; i < result.Animations.Count; i++)
		{
			let clip = result.Animations[i];
			clip.IsLooping = true;
			mFoxAnimations.Add(clip);
		}
		result.Animations.Clear(); // prevent double-delete

		Console.WriteLine(scope $"Skeleton: {mFoxSkeleton.BoneCount} bones");
		for (let clip in mFoxAnimations)
			Console.WriteLine(scope $"  Animation: '{clip.Name}' ({clip.Duration:.2}s)");

		// Create bone buffer
		if (res.CreateBoneBuffer((uint16)mFoxSkeleton.BoneCount) case .Ok(let bh))
			mFoxBoneBuffer = bh;
		else
			return .Err;

		// Create material for the fox (simple white PBR)
		let matResult = CreateMaterialInstance(0.8f, 0.6f, 0.4f, 0.0f, 0.7f);
		if (matResult case .Err)
			return .Err;
		let foxMat = matResult.Value;

		// Create skinned mesh proxy
		mFoxProxy = mWorld.CreateSkinnedMesh();
		let foxScale = 0.02f; // Fox model is large, scale down
		mWorld.SetSkinnedMeshTransform(mFoxProxy,
			Matrix.CreateScale(foxScale) * Matrix.CreateTranslation(-3.0f, 0.0f, -3.0f));
		mWorld.SetSkinnedMeshData(mFoxProxy, mFoxMesh, mFoxBoneBuffer,
			(uint16)mFoxSkeleton.BoneCount, skinnedMesh.Bounds);
		mWorld.SetSkinnedMeshMaterial(mFoxProxy, 0, foxMat);
		mWorld.SetSkinnedMeshFlags(mFoxProxy, .Default);

		// Initial bone upload (bind pose)
		UpdateFoxBones();

		return .Ok;
	}

	private void UpdateFoxBones()
	{
		if (mFoxSkeleton == null || !mFoxBoneBuffer.IsValid)
			return;

		let boneCount = mFoxSkeleton.BoneCount;

		// Sample animation
		Transform[] localPoses = scope Transform[boneCount];
		if (mFoxAnimations.Count > 0 && mCurrentAnimIndex < mFoxAnimations.Count)
		{
			let clip = mFoxAnimations[mCurrentAnimIndex];
			AnimationSampler.SampleClip(clip, mFoxSkeleton, mAnimTime, localPoses);
		}
		else
		{
			// Bind pose fallback
			for (int i = 0; i < boneCount; i++)
			{
				let bone = mFoxSkeleton.Bones[i];
				localPoses[i] = (bone != null) ? bone.LocalBindPose : .Identity;
			}
		}

		// Compute skinning matrices
		Matrix[] skinningMatrices = scope Matrix[boneCount];
		mFoxSkeleton.ComputeSkinningMatrices(localPoses, skinningMatrices);

		// Allocate previous frame storage on first call
		if (mPrevSkinningMatrices == null)
		{
			mPrevSkinningMatrices = new Matrix[boneCount];
			Internal.MemCpy(mPrevSkinningMatrices.Ptr, skinningMatrices.Ptr, sizeof(Matrix) * boneCount);
		}

		// Upload current + previous bone matrices
		let frameIndex = mRenderSystem.FrameIndex;
		mRenderSystem.Resources.UpdateBoneBuffer(
			mFoxBoneBuffer, frameIndex,
			skinningMatrices.Ptr, mPrevSkinningMatrices.Ptr,
			(uint16)mFoxSkeleton.BoneCount);

		// Save current as previous for next frame
		Internal.MemCpy(mPrevSkinningMatrices.Ptr, skinningMatrices.Ptr, sizeof(Matrix) * boneCount);

		mWorld.MarkBonesDirty(mFoxProxy);
	}

	private void CreateLights()
	{
		// Sun — warm directional light
		let sun = mWorld.CreateLight(.Directional);
		mWorld.SetLightTransform(sun, .(0, 0, 0), Vector3.Normalize(.(0.5f, -1.0f, 0.3f)));
		mWorld.SetLightColor(sun, .(1.0f, 0.98f, 0.95f), 1f);
		mWorld.SetLightShadows(sun, true, 0.003f, 0.02f);
		mLightHandles.Add(sun);

		// Point light — centered above the sphere circle (Section 1, X=-6)
		let point = mWorld.CreateLight(.Point);
		mWorld.SetLightTransform(point, .(-6.0f, 2.0f, 0.0f), .(0, -1, 0));
		mWorld.SetLightColor(point, .(1.0f, 0.8f, 0.5f), 6.0f);
		mWorld.SetLightRange(point, 8.0f);
		mWorld.SetLightShadows(point, true);
		mLightHandles.Add(point);

		// Spot light — close above the tall cube, pointing straight down
		let spot = mWorld.CreateLight(.Spot);
		mWorld.SetLightTransform(spot, .(6.0f, 3.0f, 0.0f), .(0.0f, -1.0f, 0.0f));
		mWorld.SetLightColor(spot, .(0.3f, 0.5f, 1.0f), 50.0f);
		mWorld.SetLightRange(spot, 8.0f);
		mWorld.SetLightShadows(spot, true);
		mLightHandles.Add(spot);
	}

	private void BuildUI()
	{
		igSetNextWindowPos(.() { x = 10, y = 10 }, (.)ImGuiCond.ImGuiCond_FirstUseEver, .() { x = 0, y = 0 });
		igSetNextWindowSize(.() { x = 300, y = 250 }, (.)ImGuiCond.ImGuiCond_FirstUseEver);

		if (igBegin("Scene Settings", null, 0))
		{
			// --- Sun ---
			if (igCollapsingHeader_TreeNodeFlags("Directional Light", (.)ImGuiTreeNodeFlags.ImGuiTreeNodeFlags_DefaultOpen))
			{
				bool sunChanged = false;
				sunChanged |= igSliderFloat("Sun Yaw", &mSunYaw, -Math.PI_f, Math.PI_f, "%.2f", 0);
				sunChanged |= igSliderFloat("Sun Pitch", &mSunPitch, -Math.PI_f * 0.49f, -0.05f, "%.2f", 0);
				sunChanged |= igColorEdit3("Sun Color", &mSunColor[0], 0);
				sunChanged |= igSliderFloat("Sun Intensity", &mSunIntensity, 0.0f, 5.0f, "%.2f", 0);

				if (sunChanged && mLightHandles.Count > 0)
				{
					let sunDir = Vector3(
						Math.Cos(mSunPitch) * Math.Sin(mSunYaw),
						Math.Sin(mSunPitch),
						Math.Cos(mSunPitch) * Math.Cos(mSunYaw));
					mWorld.SetLightTransform(mLightHandles[0], .(0, 0, 0), Vector3.Normalize(sunDir));
					mWorld.SetLightColor(mLightHandles[0],
						.(mSunColor[0], mSunColor[1], mSunColor[2]), mSunIntensity);
				}
			}

			igSeparator();

			// --- Sky & Exposure ---
			if (igCollapsingHeader_TreeNodeFlags("Environment", (.)ImGuiTreeNodeFlags.ImGuiTreeNodeFlags_DefaultOpen))
			{
				var exposure = mView.Exposure;
				var ambientIntensity = mWorld.Environment.AmbientIntensity;
				var skyExposure = mWorld.Environment.SkyExposure;

				igSliderFloat("Scene Exposure", &exposure, 0.1f, 10.0f, "%.2f", 0);
				igSliderFloat("Ambient Intensity", &ambientIntensity, 0.0f, 5.0f, "%.2f", 0);
				igSliderFloat("Sky Exposure", &skyExposure, 0.1f, 10.0f, "%.2f", 0);

				mView.Exposure = exposure;
				mWorld.Environment.AmbientIntensity = ambientIntensity;
				mWorld.Environment.SkyExposure = skyExposure;
			}

			igSeparator();

			// --- Animation ---
			if (mFoxAnimations.Count > 0 &&
				igCollapsingHeader_TreeNodeFlags("Animation", (.)ImGuiTreeNodeFlags.ImGuiTreeNodeFlags_DefaultOpen))
			{
				// Play/Pause button
				if (igButton(mAnimPlaying ? "Pause" : "Play", .() { x = 60, y = 0 }))
					mAnimPlaying = !mAnimPlaying;

				igSameLine(0, 10);
				igSliderFloat("Speed", &mAnimSpeed, 0.0f, 3.0f, "%.1f", 0);

				// Animation clip selector
				let clip = mFoxAnimations[mCurrentAnimIndex];
				if (igBeginCombo("Clip", clip.Name.CStr(), 0))
				{
					for (int i = 0; i < mFoxAnimations.Count; i++)
					{
						let isSelected = (i == mCurrentAnimIndex);
						if (igSelectable_Bool(mFoxAnimations[i].Name.CStr(), isSelected, 0, .()))
						{
							mCurrentAnimIndex = i;
							mAnimTime = 0.0f;
						}
					}
					igEndCombo();
				}

				// Timeline scrubber
				let duration = clip.Duration;
				if (duration > 0)
				{
					var t = mAnimTime % duration;
					if (igSliderFloat("Time", &t, 0.0f, duration, "%.2f", 0))
					{
						mAnimTime = t;
						UpdateFoxBones();
					}
				}
			}

			igSeparator();

			// --- Post-Processing ---
			if (igCollapsingHeader_TreeNodeFlags("Post-Processing", (.)ImGuiTreeNodeFlags.ImGuiTreeNodeFlags_DefaultOpen))
			{
				// TAA
				var taaEnabled = mTAAEffect.Enabled;
				if (igCheckbox("TAA", &taaEnabled))
					mTAAEffect.Enabled = taaEnabled;
				if (taaEnabled)
				{
					var blend = mTAAEffect.BlendFactor;
					igSliderFloat("History Weight", &blend, 0.5f, 0.99f, "%.2f", default);
					mTAAEffect.BlendFactor = blend;

					var clipGamma = mTAAEffect.VarianceClipGamma;
					igSliderFloat("Clip Gamma", &clipGamma, 0.5f, 3.0f, "%.2f", default);
					mTAAEffect.VarianceClipGamma = clipGamma;
				}

				// Bloom
				var bloomEnabled = mBloomEffect.Enabled;
				if (igCheckbox("Bloom", &bloomEnabled))
					mBloomEffect.Enabled = bloomEnabled;
				if (bloomEnabled)
				{
					var bloomThreshold = mBloomEffect.Threshold;
					igSliderFloat("Threshold", &bloomThreshold, 0.0f, 5.0f, "%.2f", default);
					mBloomEffect.Threshold = bloomThreshold;

					var bloomIntensity = mBloomEffect.Intensity;
					igSliderFloat("Bloom Intensity", &bloomIntensity, 0.0f, 2.0f, "%.2f", default);
					mBloomEffect.Intensity = bloomIntensity;
				}

				// Reflection Probes
				var probesEnabled = mReflectionProbesEnabled;
				if (igCheckbox("Reflection Probes", &probesEnabled))
				{
					mReflectionProbesEnabled = probesEnabled;
					mWorld.SetReflectionProbeEnabled(mSceneProbe, probesEnabled);
				}
				if (probesEnabled)
				{
					igSameLine(0, 10);
					if (igButton("Rebake", .()))
					{
						mWorld.MarkReflectionProbeDirty(mSceneProbe);
						mRenderSystem.BakeReflectionProbes();
					}
				}

				// Tonemap
				var tonemapEnabled = mTonemapEffect.Enabled;
				if (igCheckbox("Tonemap", &tonemapEnabled))
					mTonemapEffect.Enabled = tonemapEnabled;

				if (tonemapEnabled)
				{
					var mode = (int32)mTonemapEffect.Mode;
					igRadioButton_IntPtr("ACES", &mode, 0); igSameLine(0, 10);
					igRadioButton_IntPtr("Reinhard", &mode, 1); igSameLine(0, 10);
					igRadioButton_IntPtr("AgX", &mode, 2);
					mTonemapEffect.Mode = (TonemapMode)mode;
				}
			}

			igSeparator();

			// --- Debug ---
			if (igCollapsingHeader_TreeNodeFlags("Debug", (.)ImGuiTreeNodeFlags.ImGuiTreeNodeFlags_DefaultOpen))
			{
				var showMV = mBlitToScreen.DebugMotionVectors;
				if (igCheckbox("Motion Vectors", &showMV))
					mBlitToScreen.DebugMotionVectors = showMV;

				var hiZMip = (int32)mBlitToScreen.DebugHiZMip;
				let maxMip = (int32)mRenderSystem.HiZ.MipCount - 1;
				igSliderInt("Hi-Z Mip", &hiZMip, -1, Math.Max(maxMip, 0), "%d", 0);
				mBlitToScreen.DebugHiZMip = (int)hiZMip;
				if (hiZMip == -1)
					igText("Hi-Z: off (-1 = normal scene)");
				else
					igText(scope $"Hi-Z: mip {hiZMip} (white=near, dark=far)");
			}

			igSeparator();

			// --- Render stats ---
			if (igCollapsingHeader_TreeNodeFlags("Stats", (.)ImGuiTreeNodeFlags.ImGuiTreeNodeFlags_DefaultOpen))
			{
				let stats = mRenderSystem.Stats;
				igText(scope $"Draw calls: {stats.DrawCalls}");
				igText(scope $"Pass count: {stats.PassCount}");
			}
		}
		igEnd();
	}

	private void UpdateCamera()
	{
		// Spherical coordinates around target
		let cosP = Math.Cos(mCamPitch);
		let camOffset = Vector3(
			Math.Sin(mCamYaw) * cosP * mCamDistance,
			Math.Sin(mCamPitch) * mCamDistance,
			Math.Cos(mCamYaw) * cosP * mCamDistance);

		mView.CameraPosition = mCamTarget + camOffset;

		let dir = mCamTarget - mView.CameraPosition;
		let len = dir.Length();
		mView.CameraForward = (len > 0.0001f) ? dir * (1.0f / len) : Vector3(0, 0, -1);
		mView.CameraUp = Vector3(0.0f, 1.0f, 0.0f);
	}

	protected override void OnUpdate(float deltaTime)
	{
		let input = mShell.InputManager;
		let kb = input.Keyboard;
		let mouse = input.Mouse;

		// --- ImGui frame ---
		mImGui.BeginFrame((float)mWidth, (float)mHeight, deltaTime);
		mImGui.UpdateInput(input);

		BuildUI();

		// Advance animation
		if (mAnimPlaying && mFoxProxy.IsValid && mFoxAnimations.Count > 0)
		{
			mAnimTime += deltaTime * mAnimSpeed;
			UpdateFoxBones();
		}

		mImGui.EndFrame();

		// --- Right-click drag to orbit (skip if ImGui wants mouse) ---
		if (mouse.IsButtonDown(.Right) && !mImGui.WantCaptureMouse)
		{
			mCamYaw += mouse.DeltaX * mMouseSensitivity;
			mCamPitch += mouse.DeltaY * mMouseSensitivity;

			// Clamp pitch to avoid gimbal lock
			mCamPitch = Math.Clamp(mCamPitch, -1.4f, 1.4f);
		}

		// --- Mouse wheel to zoom (skip if ImGui wants mouse) ---
		if (mouse.ScrollY != 0.0f && !mImGui.WantCaptureMouse)
		{
			mCamDistance -= mouse.ScrollY * 0.5f;
			mCamDistance = Math.Clamp(mCamDistance, 1.0f, 50.0f);
		}

		// --- WASD to pan camera target ---
		var moveDir = Vector3.Zero;
		// Camera-relative horizontal directions
		let forward2D = Vector3.Normalize(Vector3(
			Math.Sin(mCamYaw), 0.0f, Math.Cos(mCamYaw)));
		let right2D = Vector3.Normalize(Vector3.Cross(forward2D, Vector3(0, 1, 0)));

		if (kb.IsKeyDown(.W)) moveDir = moveDir - forward2D;
		if (kb.IsKeyDown(.S)) moveDir = moveDir + forward2D;
		if (kb.IsKeyDown(.A)) moveDir = moveDir - right2D;
		if (kb.IsKeyDown(.D)) moveDir = moveDir + right2D;
		if (kb.IsKeyDown(.E)) moveDir.Y += 1.0f;
		if (kb.IsKeyDown(.Q)) moveDir.Y -= 1.0f;

		let movLen = moveDir.Length();
		if (movLen > 0.0001f)
		{
			let speed = kb.IsKeyDown(.LeftShift) ? mMoveSpeed * 3.0f : mMoveSpeed;
			mCamTarget = mCamTarget + moveDir * (1.0f / movLen) * speed * deltaTime;
		}

		UpdateCamera();
	}

	protected override void OnShutdown()
	{
		// Destroy skinned mesh proxy before materials
		if (mFoxProxy.IsValid)
			mWorld.DestroySkinnedMesh(mFoxProxy);

		for (let handle in mMaterialHandles)
		{
			if (handle.IsValid)
				mRenderSystem.DestroyMaterialInstance(handle);
		}

		if (mPBRMatDef != null)
		{
			mPBRMatDef.Release(mDevice);
			delete mPBRMatDef;
		}

		if (mTransparentMatDef != null)
		{
			mTransparentMatDef.Release(mDevice);
			delete mTransparentMatDef;
		}

		if (mSkyTextureView != null)
			mDevice.DestroyTextureView(ref mSkyTextureView);
		if (mSkyTexture != null)
			mDevice.DestroyTexture(ref mSkyTexture);
		if (mBrdfLutTextureView != null)
			mDevice.DestroyTextureView(ref mBrdfLutTextureView);
		if (mBrdfLutTexture != null)
			mDevice.DestroyTexture(ref mBrdfLutTexture);

		if (mMaterialSampler != null)
			mDevice.DestroySampler(ref mMaterialSampler);

		if (mShaderCompiler != null)
		{
			mShaderCompiler.Destroy();
			delete mShaderCompiler;
		}
	}

	protected override void OnPostShutdown()
	{
		delete mDepthPrepass;
		delete mForwardOpaque;
		delete mForwardTransparent;
		delete mSky;
		delete mMotionVectors;
		delete mTAAEffect;
		delete mBloomEffect;
		delete mTonemapEffect;
		delete mPostProcess;
		delete mBlitToScreen;
		delete mImGui;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope SandboxApp();
		return app.Run();
	}
}

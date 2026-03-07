namespace RenderCinematic;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.Runtime.Client;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Imaging;
using Sedulous.Textures.Resources;
using Sedulous.GUI;
using Sedulous.GUI.Runtime;

typealias ShellKeyCode = Sedulous.Shell.Input.KeyCode;

/// Cinematic rendering sample demonstrating Phase 5 visual polish effects:
/// Depth of Field, Motion Blur, Film Grain, Color Grading, Vignette, Chromatic Aberration.
class RenderCinematicApp : Application
{
	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Render features (owned by RenderSystem after registration)
	private DepthPrepassFeature mDepthFeature;
	private MotionVectorFeature mMotionVectorFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private GPUSkinningFeature mSkinningFeature;
	private OverlayRenderFeature mOverlayFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Model resources
	private Model mSponzaModel ~ delete _;
	private ModelImportResult mImportResult ~ delete _;

	// Extra models
	private Model mHelmetModel ~ delete _;
	private ModelImportResult mHelmetImport ~ delete _;

	// GPU resources
	private List<GPUMeshHandle> mMeshHandles = new .() ~ delete _;
	private List<GPUTextureHandle> mTextureHandles = new .() ~ delete _;
	private List<MeshProxyHandle> mMeshProxies = new .() ~ delete _;
	private List<MaterialInstance> mMaterialInstances = new .() ~ {
		for (let mat in _)
			mat?.ReleaseRef();
		delete _;
	};

	// Lighting
	private LightProxyHandle mSunLight = .Invalid;
	private List<LightProxyHandle> mPointLights = new .() ~ delete _;

	// Reflection probes
	private ReflectionProbeProxyHandle mCourtyardProbe = .Invalid;

	// Camera (flythrough mode)
	private Vector3 mCameraPosition = .(0, 5, 0);
	private float mYaw = 0.0f;
	private float mPitch = 0.0f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 5.0f;
	private const float FastMoveSpeed = 15.0f;
	private const float LookSpeed = 0.003f;

	// GUI system
	private Sedulous.GUI.Runtime.UISubsystem mUISubsystem;
	private bool mShowGUI = true;

	private DockPanel mRoot;
	private List<delegate void(Slider, float)> mSliderCallbacks = new .() ~ DeleteContainerAndItems!(_);
	private TextBlock mFpsLabel;

	// Timing
	private float mFrameDelta = 0;
	private int mFrameCount = 0;
	private float mFpsTimer = 0;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Runtime.Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		Console.WriteLine("=== Render Cinematic ===");
		Console.WriteLine("DOF, Motion Blur, Film Grain, Color Grading, Vignette, Chromatic Aberration\n");

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
		RegisterPostProcessEffects();
		LoadSponza();
		LoadExtraModels();
		CreateLights();
		CreateReflectionProbes();

		// Environment settings
		mWorld.AmbientColor = .(0.03f, 0.03f, 0.04f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;
		mWorld.TonemapOperator = .ACES;
		mWorld.BloomEnabled = true;
		mWorld.AAMode = .TAA;
		mWorld.SharpenEnabled = true;

		// Phase 5 defaults
		mWorld.DOFEnabled = false;
		mWorld.DOFFocusDistance = 5.0f;
		mWorld.DOFFocusRange = 3.0f;
		mWorld.DOFBokehSize = 4.0f;
		mWorld.MotionBlurEnabled = false;
		mWorld.MotionBlurIntensity = 1.0f;
		mWorld.FilmGrainEnabled = false;
		mWorld.FilmGrainIntensity = 0.15f;
		mWorld.ColorGradingEnabled = false;
		mWorld.VignetteEnabled = false;
		mWorld.VignetteIntensity = 0.4f;
		mWorld.VignetteSmoothness = 0.5f;
		mWorld.ChromaticAberrationEnabled = false;
		mWorld.ChromaticAberrationIntensity = 0.005f;

		// Initialize GUI
		InitializeGUI();
		BuildSettingsPanel();

		Console.WriteLine("\n=== Controls ===");
		Console.WriteLine("  WASD: move camera | Q/E: down/up | Shift: fast");
		Console.WriteLine("  Right-click + drag: look around");
		Console.WriteLine("  Tab: toggle mouse capture");
		Console.WriteLine("  F1: toggle settings panel");
		Console.WriteLine("  ESC: exit");
	}

	private void InitializeGUI()
	{
		mUISubsystem = new Sedulous.GUI.Runtime.UISubsystem();
		mContext.RegisterSubsystem(mUISubsystem);

		let shaderPath = scope $"{AssetDirectory}/Render/shaders";
		if (mUISubsystem.InitializeRendering(mDevice, mSwapChain.Format, (int32)mSwapChain.FrameCount, mShell, mWindow, scope StringView[](shaderPath)) case .Err)
		{
			Console.WriteLine("Warning: Failed to initialize UI");
			return;
		}

		let fontPath = scope $"{AssetDirectory}/framework/fonts/roboto/Roboto-Regular.ttf";
		Sedulous.Fonts.FontLoadOptions fontOptions = .ExtendedLatin;
		fontOptions.PixelHeight = 14;
		mUISubsystem.LoadFont("Roboto", fontPath, fontOptions);
	}

	private void BuildSettingsPanel()
	{
		if (mUISubsystem?.GUIContext == null)
			return;

		mRoot = new DockPanel();
		mRoot.LastChildFill = false;
		mRoot.IsHitTestVisible = false;

		let settingsPanel = new Border();
		settingsPanel.Background = Color(15, 15, 25, 140);
		settingsPanel.Width = 280;
		settingsPanel.Padding = .(8, 8, 8, 8);
		settingsPanel.IsHitTestVisible = true;
		DockPanelProperties.SetDock(settingsPanel, .Right);
		mRoot.AddChild(settingsPanel);

		let scroll = new ScrollViewer();
		scroll.HorizontalScrollBarVisibility = .Disabled;
		settingsPanel.Child = scroll;

		let content = new StackPanel();
		content.Orientation = .Vertical;
		content.Spacing = 6;
		scroll.Content = content;

		// Title
		let title = new TextBlock("Cinematic Settings");
		title.FontSize = 16;
		title.Foreground = Color(220, 220, 255, 255);
		title.Margin = .(0, 0, 0, 8);
		content.AddChild(title);

		mFpsLabel = new TextBlock("FPS: ---");
		mFpsLabel.FontSize = 12;
		mFpsLabel.Foreground = Color(150, 255, 150, 255);
		mFpsLabel.Margin = .(0, 0, 0, 6);
		content.AddChild(mFpsLabel);

		AddSeparator(content);

		// === Depth of Field ===
		AddSectionHeader(content, "Depth of Field");

		AddCheckBox(content, "DOF Enabled", mWorld.DOFEnabled, new (cb, isChecked) => {
			mWorld.DOFEnabled = isChecked;
		});

		AddSlider(content, "Focus Dist", 0.5f, 50.0f, mWorld.DOFFocusDistance, 0.5f, new (s, val) => {
			mWorld.DOFFocusDistance = val;
		});

		AddSlider(content, "Focus Range", 0.5f, 20.0f, mWorld.DOFFocusRange, 0.5f, new (s, val) => {
			mWorld.DOFFocusRange = val;
		});

		AddSlider(content, "Bokeh Size", 1.0f, 16.0f, mWorld.DOFBokehSize, 0.5f, new (s, val) => {
			mWorld.DOFBokehSize = val;
		});

		AddSeparator(content);

		// === Motion Blur ===
		AddSectionHeader(content, "Motion Blur");

		AddCheckBox(content, "Motion Blur", mWorld.MotionBlurEnabled, new (cb, isChecked) => {
			mWorld.MotionBlurEnabled = isChecked;
		});

		AddSlider(content, "Intensity", 0.1f, 3.0f, mWorld.MotionBlurIntensity, 0.1f, new (s, val) => {
			mWorld.MotionBlurIntensity = val;
		});

		AddSeparator(content);

		// === Film Grain ===
		AddSectionHeader(content, "Film Grain");

		AddCheckBox(content, "Film Grain", mWorld.FilmGrainEnabled, new (cb, isChecked) => {
			mWorld.FilmGrainEnabled = isChecked;
		});

		AddSlider(content, "Intensity", 0.01f, 0.5f, mWorld.FilmGrainIntensity, 0.01f, new (s, val) => {
			mWorld.FilmGrainIntensity = val;
		});

		AddSeparator(content);

		// === Color Grading ===
		AddSectionHeader(content, "Color Grading");

		AddCheckBox(content, "Color Grading", mWorld.ColorGradingEnabled, new (cb, isChecked) => {
			mWorld.ColorGradingEnabled = isChecked;
		});

		AddSeparator(content);

		// === Vignette ===
		AddSectionHeader(content, "Vignette");

		AddCheckBox(content, "Vignette", mWorld.VignetteEnabled, new (cb, isChecked) => {
			mWorld.VignetteEnabled = isChecked;
		});

		AddSlider(content, "Intensity", 0.0f, 1.0f, mWorld.VignetteIntensity, 0.05f, new (s, val) => {
			mWorld.VignetteIntensity = val;
		});

		AddSlider(content, "Smoothness", 0.0f, 1.0f, mWorld.VignetteSmoothness, 0.05f, new (s, val) => {
			mWorld.VignetteSmoothness = val;
		});

		AddSeparator(content);

		// === Chromatic Aberration ===
		AddSectionHeader(content, "Chromatic Aberration");

		AddCheckBox(content, "Chromatic Aberr.", mWorld.ChromaticAberrationEnabled, new (cb, isChecked) => {
			mWorld.ChromaticAberrationEnabled = isChecked;
		});

		AddSlider(content, "Intensity", 0.0f, 0.05f, mWorld.ChromaticAberrationIntensity, 0.001f, new (s, val) => {
			mWorld.ChromaticAberrationIntensity = val;
		});

		AddSeparator(content);

		// === Environment ===
		AddSectionHeader(content, "Environment");

		AddSlider(content, "Exposure", 0.1f, 5.0f, mWorld.Exposure, 0.1f, new (s, val) => {
			mWorld.Exposure = val;
		});

		AddSlider(content, "Ambient", 0.0f, 2.0f, mWorld.AmbientIntensity, 0.05f, new (s, val) => {
			mWorld.AmbientIntensity = val;
		});

		AddSlider(content, "Sun Intensity", 0.0f, 10.0f, 3.0f, 0.1f, new (s, val) => {
			if (let light = mWorld.GetLight(mSunLight))
				light.Intensity = val;
		});

		mUISubsystem.GUIContext.RootElement = mRoot;
	}

	// --- GUI helpers ---

	private void AddSectionHeader(StackPanel parent, StringView text)
	{
		let label = new TextBlock(text);
		label.FontSize = 14;
		label.Foreground = Color(180, 200, 255, 255);
		label.Margin = .(0, 4, 0, 4);
		parent.AddChild(label);
	}

	private void AddSeparator(StackPanel parent)
	{
		let sep = new Separator();
		sep.Margin = .(0, 2, 0, 2);
		parent.AddChild(sep);
	}

	private CheckBox AddCheckBox(StackPanel parent, StringView label, bool initialValue, delegate void(ToggleButton, bool) callback)
	{
		let cb = new CheckBox(label);
		cb.IsChecked = initialValue;
		cb.Margin = .(4, 0, 0, 2);
		cb.Checked.Subscribe(callback);
		parent.AddChild(cb);
		return cb;
	}

	private Slider AddSlider(StackPanel parent, StringView label, float min, float max, float initial, float step,
		delegate void(Slider, float) callback)
	{
		mSliderCallbacks.Add(callback);

		let row = new StackPanel();
		row.Orientation = .Horizontal;
		row.Spacing = 8;
		row.Margin = .(4, 0, 0, 0);

		let nameLabel = new TextBlock(label);
		nameLabel.FontSize = 12;
		nameLabel.Foreground = Color(180, 180, 180, 255);
		nameLabel.VerticalAlignment = .Center;
		nameLabel.Width = 100;
		row.AddChild(nameLabel);

		let valueLabel = new TextBlock(scope $"{initial:F2}");
		valueLabel.FontSize = 12;
		valueLabel.Foreground = Color(200, 220, 200, 255);
		valueLabel.VerticalAlignment = .Center;
		valueLabel.Width = 45;
		row.AddChild(valueLabel);

		parent.AddChild(row);

		let slider = new Slider();
		slider.Minimum = min;
		slider.Maximum = max;
		slider.Value = initial;
		slider.Step = step;
		slider.Height = 20;
		slider.Margin = .(16, 0, 8, 2);
		slider.ValueChanged.Subscribe(new (s, val) => {
			valueLabel.Text = scope $"{val:F2}";
			callback(s, val);
		});

		parent.AddChild(slider);
		return slider;
	}

	// --- Feature/effect registration ---

	private void RegisterFeatures()
	{
		mSkinningFeature = new GPUSkinningFeature();
		mRenderSystem.RegisterFeature(mSkinningFeature);

		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mMotionVectorFeature = new MotionVectorFeature();
		mRenderSystem.RegisterFeature(mMotionVectorFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		mOverlayFeature = new OverlayRenderFeature();
		mRenderSystem.RegisterFeature(mOverlayFeature);

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void RegisterPostProcessEffects()
	{
		let stack = mRenderSystem.PostProcessStack;
		if (stack == null) return;

		// Phase 1-3 effects
		stack.RegisterEffect(new ContactShadowEffect(mRenderSystem));
		stack.RegisterEffect(new SSAOEffect(mRenderSystem));
		stack.RegisterEffect(new SSREffect(mRenderSystem));
		stack.RegisterEffect(new BloomEffect(mRenderSystem));
		stack.RegisterEffect(new TAAEffect(mRenderSystem));
		stack.RegisterEffect(new FXAAEffect(mRenderSystem));
		stack.RegisterEffect(new SharpenEffect(mRenderSystem));
		stack.RegisterEffect(new TonemapEffect(mRenderSystem));

		// Phase 5 effects
		stack.RegisterEffect(new DOFEffect(mRenderSystem));
		stack.RegisterEffect(new MotionBlurEffect(mRenderSystem));
		stack.RegisterEffect(new FilmGrainEffect(mRenderSystem));
		stack.RegisterEffect(new ColorGradingEffect(mRenderSystem));
		stack.RegisterEffect(new VignetteEffect(mRenderSystem));
		stack.RegisterEffect(new ChromaticAberrationEffect(mRenderSystem));

		if (stack.Initialize(mDevice) case .Err)
			Console.WriteLine("Warning: Failed to initialize PostProcessStack");
	}

	// --- Model loading ---

	private void LoadSponza()
	{
		GltfModels.Initialize();

		let modelPath = scope $"{AssetDirectory}/samples/models/Sponza/glTF/Sponza.gltf";
		let basePath = scope $"{AssetDirectory}/samples/models/Sponza/glTF";
		Console.WriteLine("Loading Sponza from: {}", modelPath);

		mSponzaModel = new Model();
		if (ModelLoaderFactory.LoadModel(modelPath, mSponzaModel) != .Ok)
		{
			Console.WriteLine("ERROR: Failed to load Sponza model");
			delete mSponzaModel;
			mSponzaModel = null;
			return;
		}

		let importOptions = new ModelImportOptions();
		importOptions.Flags = .Meshes | .Textures | .Materials;
		importOptions.BasePath.Set(basePath);

		let importer = scope ModelImporter(importOptions);
		mImportResult = importer.Import(mSponzaModel);

		if (!mImportResult.Success)
		{
			for (let err in mImportResult.Errors)
				Console.WriteLine("  Import error: {}", err);
			return;
		}

		Console.WriteLine("  Imported: {} meshes, {} textures, {} materials",
			mImportResult.StaticMeshes.Count, mImportResult.Textures.Count,
			mImportResult.Materials.Count);

		UploadTextures();
		CreateMaterials();
		CreateMeshProxies();
	}

	private void UploadTextures()
	{
		for (let texResource in mImportResult.Textures)
		{
			let image = texResource.Image;
			if (image == null || image.Width == 0 || image.Height == 0)
			{
				mTextureHandles.Add(.Invalid);
				continue;
			}

			let texData = TextureData.FromImage(image);
			if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let texHandle))
				mTextureHandles.Add(texHandle);
			else
				mTextureHandles.Add(.Invalid);
		}
	}

	private void CreateMaterials()
	{
		let fallbackMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial;
		let materialSystem = mRenderSystem.MaterialSystem;

		for (let matResource in mImportResult.Materials)
		{
			let baseMat = (matResource.Material != null && matResource.Material.IsValid)
				? matResource.Material : fallbackMaterial;

			if (baseMat == null)
			{
				mMaterialInstances.Add(null);
				continue;
			}

			let matInstance = new MaterialInstance(baseMat);

			for (var kv in matResource.TextureRefs)
			{
				let slotName = kv.key;
				let texRef = kv.value;

				if (texRef.Path == null)
					continue;

				for (int32 texIdx = 0; texIdx < (int32)mImportResult.Textures.Count; texIdx++)
				{
					let texRes = mImportResult.Textures[texIdx];
					bool matches = (texRes.Name == texRef.Path) ||
						(texRes.Name.Length > 0 && texRef.Path.Contains(texRes.Name));
					if (matches)
					{
						if (texIdx < (int32)mTextureHandles.Count && mTextureHandles[texIdx].IsValid)
						{
							if (let texView = mRenderSystem.ResourceManager.GetTextureView(mTextureHandles[texIdx]))
								matInstance.SetTexture(slotName, texView);
						}
						break;
					}
				}
			}

			if (materialSystem != null)
			{
				let addressU = SamplerAddressModeToRHI(matResource.WrapU);
				let addressV = SamplerAddressModeToRHI(matResource.WrapV);
				let (minFilter, mipmapFilter) = MinFilterToRHI(matResource.MinFilter);
				let magFilter = MagFilterToRHI(matResource.MagFilter);
				let sampler = materialSystem.GetOrCreateSampler(addressU, addressV, minFilter, magFilter, mipmapFilter);
				matInstance.SetSampler("MainSampler", sampler);
			}

			mMaterialInstances.Add(matInstance);
		}
	}

	private static AddressMode SamplerAddressModeToRHI(SamplerAddressMode mode)
	{
		switch (mode)
		{
		case .Repeat:        return .Repeat;
		case .MirrorRepeat:  return .MirrorRepeat;
		case .ClampToEdge:   return .ClampToEdge;
		case .ClampToBorder: return .ClampToBorder;
		}
	}

	private static (FilterMode minFilter, FilterMode mipmapFilter) MinFilterToRHI(SamplerMinFilter filter)
	{
		switch (filter)
		{
		case .Nearest:              return (.Nearest, .Nearest);
		case .Linear:               return (.Linear, .Nearest);
		case .NearestMipmapNearest: return (.Nearest, .Nearest);
		case .LinearMipmapNearest:  return (.Linear, .Nearest);
		case .NearestMipmapLinear:  return (.Nearest, .Linear);
		case .LinearMipmapLinear:   return (.Linear, .Linear);
		}
	}

	private static FilterMode MagFilterToRHI(SamplerMagFilter filter)
	{
		switch (filter)
		{
		case .Nearest: return .Nearest;
		case .Linear:  return .Linear;
		}
	}

	private void CreateMeshProxies()
	{
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		for (let meshResource in mImportResult.StaticMeshes)
		{
			let staticMesh = meshResource.Mesh;
			if (staticMesh == null) continue;

			if (mRenderSystem.ResourceManager.UploadMesh(staticMesh) case .Ok(let meshHandle))
			{
				mMeshHandles.Add(meshHandle);

				let proxyHandle = mWorld.CreateMesh();
				if (let proxy = mWorld.GetMesh(proxyHandle))
				{
					proxy.MeshHandle = meshHandle;
					proxy.SetLocalBounds(staticMesh.GetBounds());
					proxy.SetTransformImmediate(.Identity);
					proxy.Flags = .DefaultOpaque;

					int32 maxMatIdx = 0;
					for (let submesh in staticMesh.SubMeshes)
					{
						let matIdx = submesh.materialIndex;
						if (matIdx >= 0 && matIdx < (int32)mMaterialInstances.Count)
						{
							let matInst = mMaterialInstances[matIdx];
							if (matInst != null)
								proxy.Materials[matIdx] = matInst;
							else
								proxy.Materials[matIdx] = defaultMaterial;
						}
						else
						{
							proxy.Materials[matIdx] = defaultMaterial;
						}

						if (matIdx + 1 > maxMatIdx)
							maxMatIdx = matIdx + 1;
					}
					proxy.MaterialCount = maxMatIdx;

					if (proxy.MaterialCount == 0)
					{
						proxy.Materials[0] = defaultMaterial;
						proxy.MaterialCount = 1;
					}
				}

				mMeshProxies.Add(proxyHandle);
			}
		}

		Console.WriteLine("  Created {} mesh proxies", mMeshProxies.Count);
	}

	private void LoadExtraModels()
	{
		// DamagedHelmet — good DOF subject with metallic detail
		let helmetPath = @"D:\Dev\Beef\Sedulous-Serenity\support\glTF-Sample-Assets-main\Models\DamagedHelmet\glTF\DamagedHelmet.gltf";
		let helmetBase = @"D:\Dev\Beef\Sedulous-Serenity\support\glTF-Sample-Assets-main\Models\DamagedHelmet\glTF";
		mHelmetModel = new Model();
		mHelmetImport = LoadAndUploadGLTFModel(helmetPath, helmetBase, mHelmetModel, .(0, 3.0f, 0), 1.0f);
	}

	private ModelImportResult LoadAndUploadGLTFModel(StringView modelPath, StringView basePath, Model model, Vector3 position, float scale)
	{
		GltfModels.Initialize();

		Console.WriteLine("Loading glTF: {}", modelPath);
		if (ModelLoaderFactory.LoadModel(modelPath, model) != .Ok)
		{
			Console.WriteLine("  ERROR: Failed to load model");
			return null;
		}

		let importOptions = new ModelImportOptions();
		importOptions.Flags = .Meshes | .Textures | .Materials;
		importOptions.BasePath.Set(basePath);

		let importer = scope ModelImporter(importOptions);
		let importResult = importer.Import(model);

		if (!importResult.Success)
		{
			for (let err in importResult.Errors)
				Console.WriteLine("  Import error: {}", err);
			return importResult;
		}

		Console.WriteLine("  Imported: {} meshes, {} textures, {} materials",
			importResult.StaticMeshes.Count, importResult.Textures.Count,
			importResult.Materials.Count);

		// Upload textures
		int texStartIdx = mTextureHandles.Count;
		for (let texResource in importResult.Textures)
		{
			let image = texResource.Image;
			if (image == null || image.Width == 0 || image.Height == 0)
			{
				mTextureHandles.Add(.Invalid);
				continue;
			}

			let texData = TextureData.FromImage(image);
			if (mRenderSystem.ResourceManager.UploadTexture(texData) case .Ok(let texHandle))
				mTextureHandles.Add(texHandle);
			else
				mTextureHandles.Add(.Invalid);
		}

		// Create materials
		let fallbackMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial;
		let materialSystem = mRenderSystem.MaterialSystem;
		int matStartIdx = mMaterialInstances.Count;

		for (let matResource in importResult.Materials)
		{
			let baseMat = (matResource.Material != null && matResource.Material.IsValid)
				? matResource.Material : fallbackMaterial;

			if (baseMat == null)
			{
				mMaterialInstances.Add(null);
				continue;
			}

			let matInstance = new MaterialInstance(baseMat);

			for (var kv in matResource.TextureRefs)
			{
				let slotName = kv.key;
				let texRef = kv.value;

				if (texRef.Path == null)
					continue;

				for (int32 texIdx = 0; texIdx < (int32)importResult.Textures.Count; texIdx++)
				{
					let texRes = importResult.Textures[texIdx];
					bool matches = (texRes.Name == texRef.Path) ||
						(texRes.Name.Length > 0 && texRef.Path.Contains(texRes.Name));
					if (matches)
					{
						let globalIdx = texStartIdx + texIdx;
						if (globalIdx < mTextureHandles.Count && mTextureHandles[globalIdx].IsValid)
						{
							if (let texView = mRenderSystem.ResourceManager.GetTextureView(mTextureHandles[globalIdx]))
								matInstance.SetTexture(slotName, texView);
						}
						break;
					}
				}
			}

			if (materialSystem != null)
			{
				let addressU = SamplerAddressModeToRHI(matResource.WrapU);
				let addressV = SamplerAddressModeToRHI(matResource.WrapV);
				let (minFilter, mipmapFilter) = MinFilterToRHI(matResource.MinFilter);
				let magFilter = MagFilterToRHI(matResource.MagFilter);
				let sampler = materialSystem.GetOrCreateSampler(addressU, addressV, minFilter, magFilter, mipmapFilter);
				matInstance.SetSampler("MainSampler", sampler);
			}

			mMaterialInstances.Add(matInstance);
		}

		// Create mesh proxies with transform
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;
		var transform = Matrix.CreateScale(scale) * Matrix.CreateTranslation(position);

		for (let meshResource in importResult.StaticMeshes)
		{
			let staticMesh = meshResource.Mesh;
			if (staticMesh == null) continue;

			if (mRenderSystem.ResourceManager.UploadMesh(staticMesh) case .Ok(let meshHandle))
			{
				mMeshHandles.Add(meshHandle);

				let proxyHandle = mWorld.CreateMesh();
				if (let proxy = mWorld.GetMesh(proxyHandle))
				{
					proxy.MeshHandle = meshHandle;
					proxy.SetLocalBounds(staticMesh.GetBounds());
					proxy.SetTransformImmediate(transform);
					proxy.Flags = .DefaultOpaque;

					int32 maxMatIdx = 0;
					for (let submesh in staticMesh.SubMeshes)
					{
						let matIdx = submesh.materialIndex;
						let globalMatIdx = matStartIdx + matIdx;
						if (matIdx >= 0 && globalMatIdx < (int32)mMaterialInstances.Count)
						{
							let matInst = mMaterialInstances[globalMatIdx];
							if (matInst != null)
								proxy.Materials[matIdx] = matInst;
							else
								proxy.Materials[matIdx] = defaultMaterial;
						}
						else
						{
							proxy.Materials[matIdx] = defaultMaterial;
						}

						if (matIdx + 1 > maxMatIdx)
							maxMatIdx = matIdx + 1;
					}
					proxy.MaterialCount = maxMatIdx;

					if (proxy.MaterialCount == 0)
					{
						proxy.Materials[0] = defaultMaterial;
						proxy.MaterialCount = 1;
					}
				}

				mMeshProxies.Add(proxyHandle);
			}
		}

		Console.WriteLine("  Placed at ({}, {}, {}) scale={}", position.X, position.Y, position.Z, scale);
		return importResult;
	}

	private void CreateLights()
	{
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.4f, -0.8f, 0.3f)),
			.(1.0f, 0.98f, 0.92f),
			3.0f
		);

		if (let light = mWorld.GetLight(mSunLight))
			light.CastsShadows = true;

		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;

		Vector3[4] lightPositions = .(
			.(-4.0f, 3.0f, 0.0f),
			.( 4.0f, 3.0f, 0.0f),
			.( 0.0f, 3.0f, -3.0f),
			.( 0.0f, 3.0f,  3.0f)
		);

		for (let pos in lightPositions)
		{
			let pointLight = mWorld.CreatePointLight(pos, .(1.0f, 0.9f, 0.7f), 1.5f, 15.0f);
			mPointLights.Add(pointLight);
		}
	}

	private void CreateReflectionProbes()
	{
		mCourtyardProbe = mWorld.CreateReflectionProbe();
		if (let probe = mWorld.GetReflectionProbe(mCourtyardProbe))
		{
			probe.Position = .(0, 3, 0);
			probe.Radius = 15.0f;
			probe.IsEnabled = true;
			probe.ZenithColor = .(0.3f, 0.25f, 0.2f);
			probe.HorizonColor = .(0.4f, 0.35f, 0.3f);
			probe.GroundColor = .(0.2f, 0.18f, 0.15f);
			probe.IsDirty = true;
		}
	}

	// --- Input ---

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		if (keyboard.IsKeyPressed(.F1))
		{
			mShowGUI = !mShowGUI;
			if (mUISubsystem?.GUIContext?.RootElement != null)
				mUISubsystem.GUIContext.RootElement.Visibility = mShowGUI ? .Visible : .Collapsed;
		}

		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		bool guiWantsMouse = mShowGUI && mUISubsystem != null && mUISubsystem.UIConsumedInput;

		if (mMouseCaptured || (mouse.IsButtonDown(.Right) && !guiWantsMouse))
		{
			mYaw += mouse.DeltaX * LookSpeed;
			mPitch -= mouse.DeltaY * LookSpeed;
			mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;
		mFrameDelta = dt;

		// FPS counter
		mFrameCount++;
		mFpsTimer += dt;
		if (mFpsTimer >= 1.0f)
		{
			if (mFpsLabel != null)
				mFpsLabel.Text = scope $"FPS: {mFrameCount}";
			mFrameCount = 0;
			mFpsTimer -= 1.0f;
		}

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

		mCameraForward = forward;

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

		// GUI Overlay
		if (mShowGUI)
			mUISubsystem?.Render(render.Encoder, render.SwapChain.CurrentTextureView,
				render.SwapChain.Width, render.SwapChain.Height,
				(int32)render.SwapChain.CurrentFrameIndex);

		return true;
	}

	protected override void OnShutdown()
	{
		DeleteAndNullify!(mRoot);

		mWorld?.Dispose();

		for (let meshHandle in mMeshHandles)
		{
			if (meshHandle.IsValid)
				mRenderSystem.ResourceManager.ReleaseMesh(meshHandle, mRenderSystem.FrameNumber);
		}

		for (let texHandle in mTextureHandles)
		{
			if (texHandle.IsValid)
				mRenderSystem.ResourceManager.ReleaseTexture(texHandle, mRenderSystem.FrameNumber);
		}

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("RenderCinematic shutting down");
	}
}

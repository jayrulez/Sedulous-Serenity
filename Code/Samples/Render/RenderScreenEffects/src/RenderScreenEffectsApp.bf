namespace RenderScreenEffects;

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
using Sedulous.GUI.Shell;
using Sedulous.Drawing;
using Sedulous.Drawing.Renderer;
using Sedulous.Drawing.Fonts;
using Sedulous.Fonts;
using Sedulous.Shaders;

typealias ShellKeyCode = Sedulous.Shell.Input.KeyCode;

/// Screen-space effects sample demonstrating SSAO, SSR, and contact shadows
/// in the Sponza architectural scene, with a GUI settings panel.
class RenderScreenEffectsApp : Application
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

	// Extra models (DamagedHelmet, MetalRoughSpheres)
	private Model mHelmetModel ~ delete _;
	private ModelImportResult mHelmetImport ~ delete _;
	private Model mSpheresModel ~ delete _;
	private ModelImportResult mSpheresImport ~ delete _;

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
	private GUIContext mGUIContext ~ delete _;
	private FontService mFontService ~ delete _;
	private DrawContext mDrawContext ~ delete _;
	private DrawingRenderer mDrawingRenderer;
	private ShaderSystem mUIShaderSystem;
	private GUIInputHelper mInputHelper = new .() ~ delete _;
	private ShellClipboardAdapter mClipboard ~ delete _;
	private Sedulous.GUI.CursorType mLastCursor = .Default;
	private bool mShowGUI = true;

	private DockPanel mRoot ~ delete _;

	// Slider callback delegates (captured inside wrapper lambdas, not owned by EventAccessor)
	private List<delegate void(Slider, float)> mSliderCallbacks = new .() ~ DeleteContainerAndItems!(_);

	// GUI widget references (for syncing state)
	private CheckBox mSSAOCheck;
	private Slider mSSAORadiusSlider;
	private Slider mSSAOIntensitySlider;
	private CheckBox mSSRCheck;
	private Slider mSSRIntensitySlider;
	private CheckBox mContactShadowsCheck;
	private Slider mContactShadowLengthSlider;
	private CheckBox mBloomCheck;
	private Slider mBloomIntensitySlider;
	private ComboBox mTonemapCombo;
	private Slider mExposureSlider;
	private ComboBox mAAModeCombo;
	private CheckBox mSharpenCheck;
	private Slider mSharpenIntensitySlider;
	private Slider mAmbientSlider;
	private Slider mSunIntensitySlider;
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

		Console.WriteLine("=== Render Screen Effects ===");
		Console.WriteLine("SSAO, SSR, Contact Shadows in Sponza\n");

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

		// Environment settings
		mWorld.AmbientColor = .(0.03f, 0.03f, 0.04f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;
		mWorld.TonemapOperator = .ACES;
		mWorld.BloomEnabled = true;
		mWorld.AAMode = .TAA;
		mWorld.SharpenEnabled = true;

		// Screen-space effects defaults
		mWorld.SSAOEnabled = true;
		mWorld.SSAORadius = 0.5f;
		mWorld.SSAOIntensity = 1.5f;
		mWorld.SSREnabled = false;
		mWorld.ContactShadowsEnabled = true;
		mWorld.ContactShadowLength = 0.1f;

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
		// Font system
		mFontService = new FontService();
		let fontPath = scope $"{AssetDirectory}/framework/fonts/roboto/Roboto-Regular.ttf";
		FontLoadOptions fontOptions = .ExtendedLatin;
		fontOptions.PixelHeight = 14;
		if (mFontService.LoadFont("Roboto", fontPath, fontOptions) case .Err)
		{
			Console.WriteLine("Warning: Failed to load font");
			return;
		}

		// Shader system for DrawingRenderer
		mUIShaderSystem = new ShaderSystem();
		let shaderPath = scope $"{AssetDirectory}/Render/shaders";
		if (mUIShaderSystem.Initialize(mDevice, scope StringView[](shaderPath)) case .Err)
		{
			Console.WriteLine("Warning: Failed to init UI shader system");
			return;
		}

		// Draw context
		mDrawContext = new DrawContext(mFontService);

		// Drawing renderer
		mDrawingRenderer = new DrawingRenderer();
		if (mDrawingRenderer.Initialize(mDevice, mSwapChain.Format, (int32)mSwapChain.FrameCount, mUIShaderSystem) case .Err)
		{
			Console.WriteLine("Warning: Failed to init drawing renderer");
			return;
		}

		// Clipboard
		mClipboard = new ShellClipboardAdapter(mShell.Clipboard);

		// GUI context
		mGUIContext = new GUIContext();
		mGUIContext.RegisterClipboard(mClipboard);
		mGUIContext.RegisterService<IFontService>(mFontService);
		mGUIContext.SetViewportSize((float)mSwapChain.Width, (float)mSwapChain.Height);
	}

	private void BuildSettingsPanel()
	{
		if (mGUIContext == null)
			return;

		// Root: DockPanel with settings panel docked right, nothing else (3D scene shows through)
		mRoot = new DockPanel();
		mRoot.LastChildFill = false;
		mRoot.IsHitTestVisible = false; // Root itself doesn't capture clicks

		// Settings panel on the right
		let settingsPanel = new Border();
		settingsPanel.Background = Color(15, 15, 25, 140);
		settingsPanel.Width = 280;
		settingsPanel.Padding = .(8, 8, 8, 8);
		settingsPanel.IsHitTestVisible = true;
		DockPanelProperties.SetDock(settingsPanel, .Right);
		mRoot.AddChild(settingsPanel);

		// Scrollable content
		let scroll = new ScrollViewer();
		scroll.HorizontalScrollBarVisibility = .Disabled;
		settingsPanel.Child = scroll;

		let content = new StackPanel();
		content.Orientation = .Vertical;
		content.Spacing = 6;
		scroll.Content = content;

		// Title
		let title = new TextBlock("Render Settings");
		title.FontSize = 16;
		title.Foreground = Color(220, 220, 255, 255);
		title.Margin = .(0, 0, 0, 8);
		content.AddChild(title);

		// FPS display
		mFpsLabel = new TextBlock("FPS: ---");
		mFpsLabel.FontSize = 12;
		mFpsLabel.Foreground = Color(150, 255, 150, 255);
		mFpsLabel.Margin = .(0, 0, 0, 6);
		content.AddChild(mFpsLabel);

		AddSeparator(content);

		// === Screen-Space Effects ===
		AddSectionHeader(content, "Screen-Space Effects");

		// SSAO
		mSSAOCheck = AddCheckBox(content, "SSAO", mWorld.SSAOEnabled, new (cb, isChecked) => {
			mWorld.SSAOEnabled = isChecked;
		});

		mSSAORadiusSlider = AddSlider(content, "  Radius", 0.1f, 2.0f, mWorld.SSAORadius, 0.05f, new (s, val) => {
			mWorld.SSAORadius = val;
		});

		mSSAOIntensitySlider = AddSlider(content, "  Intensity", 0.1f, 4.0f, mWorld.SSAOIntensity, 0.1f, new (s, val) => {
			mWorld.SSAOIntensity = val;
		});

		AddSeparator(content);

		// SSR
		mSSRCheck = AddCheckBox(content, "SSR (Screen-Space Reflections)", mWorld.SSREnabled, new (cb, isChecked) => {
			mWorld.SSREnabled = isChecked;
		});

		mSSRIntensitySlider = AddSlider(content, "  Intensity", 0.0f, 2.0f, mWorld.SSRIntensity, 0.1f, new (s, val) => {
			mWorld.SSRIntensity = val;
		});

		AddSeparator(content);

		// Contact Shadows
		mContactShadowsCheck = AddCheckBox(content, "Contact Shadows", mWorld.ContactShadowsEnabled, new (cb, isChecked) => {
			mWorld.ContactShadowsEnabled = isChecked;
		});

		mContactShadowLengthSlider = AddSlider(content, "  Ray Length", 0.01f, 0.5f, mWorld.ContactShadowLength, 0.01f, new (s, val) => {
			mWorld.ContactShadowLength = val;
		});

		AddSeparator(content);

		// === Post-Processing ===
		AddSectionHeader(content, "Post-Processing");

		// Bloom
		mBloomCheck = AddCheckBox(content, "Bloom", mWorld.BloomEnabled, new (cb, isChecked) => {
			mWorld.BloomEnabled = isChecked;
		});

		mBloomIntensitySlider = AddSlider(content, "  Intensity", 0.0f, 2.0f, mWorld.BloomIntensity, 0.05f, new (s, val) => {
			mWorld.BloomIntensity = val;
		});

		AddSeparator(content);

		// Tonemapping
		AddLabel(content, "Tonemapping");
		mTonemapCombo = new ComboBox();
		mTonemapCombo.Width = 160;
		mTonemapCombo.Margin = .(16, 0, 0, 4);
		mTonemapCombo.AddItem("ACES");
		mTonemapCombo.AddItem("Reinhard");
		mTonemapCombo.AddItem("Uncharted2");
		mTonemapCombo.SelectedIndex = (int32)mWorld.TonemapOperator;
		mTonemapCombo.SelectionChanged.Subscribe(new (cb) => {
			switch (cb.SelectedIndex)
			{
			case 0: mWorld.TonemapOperator = .ACES;
			case 1: mWorld.TonemapOperator = .Reinhard;
			case 2: mWorld.TonemapOperator = .Uncharted2;
			}
		});
		content.AddChild(mTonemapCombo);

		// Exposure
		mExposureSlider = AddSlider(content, "Exposure", 0.1f, 5.0f, mWorld.Exposure, 0.1f, new (s, val) => {
			mWorld.Exposure = val;
		});

		AddSeparator(content);

		// === Anti-Aliasing ===
		AddSectionHeader(content, "Anti-Aliasing");

		AddLabel(content, "AA Mode");
		mAAModeCombo = new ComboBox();
		mAAModeCombo.Width = 160;
		mAAModeCombo.Margin = .(16, 0, 0, 4);
		mAAModeCombo.AddItem("None");
		mAAModeCombo.AddItem("FXAA");
		mAAModeCombo.AddItem("TAA");
		switch (mWorld.AAMode)
		{
		case .None: mAAModeCombo.SelectedIndex = 0;
		case .FXAA: mAAModeCombo.SelectedIndex = 1;
		case .TAA: mAAModeCombo.SelectedIndex = 2;
		}
		mAAModeCombo.SelectionChanged.Subscribe(new (cb) => {
			switch (cb.SelectedIndex)
			{
			case 0: mWorld.AAMode = .None;
			case 1: mWorld.AAMode = .FXAA;
			case 2: mWorld.AAMode = .TAA;
			}
		});
		content.AddChild(mAAModeCombo);

		mSharpenCheck = AddCheckBox(content, "CAS Sharpen", mWorld.SharpenEnabled, new (cb, isChecked) => {
			mWorld.SharpenEnabled = isChecked;
		});

		mSharpenIntensitySlider = AddSlider(content, "  Sharpen", 0.0f, 1.5f, mWorld.SharpenIntensity, 0.05f, new (s, val) => {
			mWorld.SharpenIntensity = val;
		});

		AddSeparator(content);

		// === Environment ===
		AddSectionHeader(content, "Environment");

		mAmbientSlider = AddSlider(content, "Ambient", 0.0f, 2.0f, mWorld.AmbientIntensity, 0.05f, new (s, val) => {
			mWorld.AmbientIntensity = val;
		});

		mSunIntensitySlider = AddSlider(content, "Sun Intensity", 0.0f, 10.0f, 3.0f, 0.1f, new (s, val) => {
			if (let light = mWorld.GetLight(mSunLight))
				light.Intensity = val;
		});

		mGUIContext.RootElement = mRoot;
	}

	// --- GUI helper methods ---

	private void AddSectionHeader(StackPanel parent, StringView text)
	{
		let label = new TextBlock(text);
		label.FontSize = 14;
		label.Foreground = Color(180, 200, 255, 255);
		label.Margin = .(0, 4, 0, 4);
		parent.AddChild(label);
	}

	private void AddLabel(StackPanel parent, StringView text)
	{
		let label = new TextBlock(text);
		label.FontSize = 12;
		label.Foreground = Color(200, 200, 200, 255);
		label.Margin = .(4, 0, 0, 2);
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
		// Track callback for cleanup (captured by wrapper lambda, not owned by EventAccessor)
		mSliderCallbacks.Add(callback);

		// Label + value row
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

		// Slider
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

	// --- Feature/effect registration (unchanged) ---

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

		stack.RegisterEffect(new ContactShadowEffect(mRenderSystem));
		stack.RegisterEffect(new SSAOEffect(mRenderSystem));
		stack.RegisterEffect(new SSREffect(mRenderSystem));
		stack.RegisterEffect(new BloomEffect(mRenderSystem));
		stack.RegisterEffect(new TAAEffect(mRenderSystem));
		stack.RegisterEffect(new FXAAEffect(mRenderSystem));
		stack.RegisterEffect(new SharpenEffect(mRenderSystem));
		stack.RegisterEffect(new TonemapEffect(mRenderSystem));

		if (stack.Initialize(mDevice) case .Err)
			Console.WriteLine("Warning: Failed to initialize PostProcessStack");
	}

	// --- Model loading (unchanged) ---

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

		Console.WriteLine("  Uploaded {} textures to GPU", mTextureHandles.Count);
	}

	private void CreateMaterials()
	{
		let fallbackMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial;
		let materialSystem = mRenderSystem.MaterialSystem;

		for (let matResource in mImportResult.Materials)
		{
			// Use the imported material (has correct ShaderFlags: NormalMap, Emissive, etc.)
			// Fall back to default material if the imported one is invalid
			let baseMat = (matResource.Material != null && matResource.Material.IsValid)
				? matResource.Material : fallbackMaterial;

			if (baseMat == null)
			{
				mMaterialInstances.Add(null);
				continue;
			}

			let matInstance = new MaterialInstance(baseMat);

			// Resolve texture references
			for (var kv in matResource.TextureRefs)
			{
				let slotName = kv.key;
				let texRef = kv.value;

				if (texRef.Path == null)
					continue;

				for (int32 texIdx = 0; texIdx < (int32)mImportResult.Textures.Count; texIdx++)
				{
					let texRes = mImportResult.Textures[texIdx];
					// Match by exact name or check if path contains the texture name
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

			// Apply sampler settings from material resource
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

		Console.WriteLine("  Created {} material instances", mMaterialInstances.Count);
	}

	// --- Sampler conversion helpers ---

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

	/// Loads extra GLB models (DamagedHelmet, MetalRoughSpheres) to showcase screen-space effects.
	private void LoadExtraModels()
	{
		// DamagedHelmet — metallic surfaces for SSR, crevices for SSAO
		let helmetPath = @"D:\Dev\Beef\Sedulous-Serenity\support\glTF-Sample-Assets-main\Models\DamagedHelmet\glTF\DamagedHelmet.gltf";
		let helmetBase = @"D:\Dev\Beef\Sedulous-Serenity\support\glTF-Sample-Assets-main\Models\DamagedHelmet\glTF";
		mHelmetModel = new Model();
		mHelmetImport = LoadAndUploadGLTFModel(helmetPath, helmetBase, mHelmetModel, .(0, 3.0f, 0), 1.0f);

		// MetalRoughSpheres — full roughness/metallic gradient grid for SSR validation
		let spheresPath = @"D:\Dev\Beef\Sedulous-Serenity\support\glTF-Sample-Assets-main\Models\MetalRoughSpheres\glTF\MetalRoughSpheres.gltf";
		let spheresBase = @"D:\Dev\Beef\Sedulous-Serenity\support\glTF-Sample-Assets-main\Models\MetalRoughSpheres\glTF";
		mSpheresModel = new Model();
		mSpheresImport = LoadAndUploadGLTFModel(spheresPath, spheresBase, mSpheresModel, .(5.0f, 1.5f, 0), 0.5f);
	}

	/// Generic helper to load a glTF model, import, upload, and create proxies with a transform.
	private ModelImportResult LoadAndUploadGLTFModel(StringView modelPath, StringView basePath, Model model, Vector3 position, float scale)
	{
		GltfModels.Initialize(); // Ensure initialized (safe to call multiple times)

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

			// Resolve texture references
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

			// Apply sampler
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

	// --- Input ---

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		// Toggle GUI
		if (keyboard.IsKeyPressed(.F1))
		{
			mShowGUI = !mShowGUI;
			if (mGUIContext?.RootElement != null)
				mGUIContext.RootElement.Visibility = mShowGUI ? .Visible : .Collapsed;
		}

		// Toggle mouse capture
		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		// Route mouse to GUI (GUI is on the right, camera uses right-click which doesn't conflict)
		if (mGUIContext != null && mShowGUI)
		{
			GUIInputHelper.ProcessMouseInput(mouse, keyboard, mGUIContext);
			mInputHelper.ProcessKeyboardInput(keyboard, mGUIContext, mFrameDelta);

			// Update cursor
			let guiCursor = mGUIContext.CurrentCursor;
			if (guiCursor != mLastCursor)
			{
				mLastCursor = guiCursor;
				mouse.Cursor = InputMapping.MapCursor(guiCursor);
			}
		}

		// Camera look: right-click drag or mouse-captured mode
		// Only when not interacting with GUI
		bool guiWantsMouse = mShowGUI && mGUIContext != null &&
			mGUIContext.CurrentCursor != .Default;

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

		// Update view
		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = mCameraForward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices(mDevice.FlipProjectionRequired);

		// Update GUI
		if (mGUIContext != null)
			mGUIContext.Update(dt, (double)frame.TotalTime);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		// --- 3D Scene ---
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

		// --- GUI Overlay ---
		if (mShowGUI && mGUIContext != null && mDrawingRenderer != null)
		{
			let frameIndex = (int32)render.SwapChain.CurrentFrameIndex;

			// Build GUI draw commands
			mDrawContext.Clear();
			mGUIContext.Render(mDrawContext);

			// Prepare renderer
			mDrawingRenderer.UpdateProjection(render.SwapChain.Width, render.SwapChain.Height, frameIndex);
			mDrawingRenderer.Prepare(mDrawContext.GetBatch(), frameIndex);

			// Render GUI in a second pass on the swap chain (LoadOp = Load to preserve 3D scene)
			let textureView = render.SwapChain.CurrentTextureView;
			if (textureView != null)
			{
				RenderPassColorAttachment[1] colorAttachments = .(.()
				{
					View = textureView,
					ResolveTarget = null,
					LoadOp = .Load,
					StoreOp = .Store,
					ClearValue = .(0, 0, 0, 0)
				});
				RenderPassDescriptor guiPassDesc = .(colorAttachments);

				let guiPass = render.Encoder.BeginRenderPass(&guiPassDesc);
				if (guiPass != null)
				{
					mDrawingRenderer.Render(guiPass, render.SwapChain.Width, render.SwapChain.Height, frameIndex);
					guiPass.End();
					delete guiPass;
				}
			}
		}

		return true;
	}

	protected override void OnResize(int32 width, int32 height)
	{
		if (mGUIContext != null)
			mGUIContext.SetViewportSize((float)width, (float)height);
	}

	protected override void OnShutdown()
	{
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

		// Clean up GUI renderer
		if (mDrawingRenderer != null)
		{
			mDrawingRenderer.Dispose();
			delete mDrawingRenderer;
			mDrawingRenderer = null;
		}

		if (mUIShaderSystem != null)
		{
			mUIShaderSystem.Dispose();
			delete mUIShaderSystem;
			mUIShaderSystem = null;
		}

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("RenderScreenEffects shutting down");
	}
}

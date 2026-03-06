using Sedulous.Core.Mathematics;
using Sedulous.Runtime.Client;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.Render;
using Sedulous.GUI;
using Sedulous.GUI.Shell;
using Sedulous.Drawing;
using Sedulous.Drawing.Renderer;
using Sedulous.Drawing.Fonts;
using Sedulous.Fonts;
using Sedulous.Shaders;
using System;
using System.Collections;

namespace RenderTerrain;

typealias ShellKeyCode = Sedulous.Shell.Input.KeyCode;

/// Terrain + Grass rendering sample with GUI settings panel.
class RenderTerrainApp : Application
{
	// Render system (cleaned up in OnShutdown, not field destructors)
	private RenderSystem mRenderSystem;
	private RenderWorld mWorld;
	private RenderView mView;

	// Render features (owned by RenderSystem after registration)
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private TerrainFeature mTerrainFeature;
	private GrassFeature mGrassFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Terrain proxy
	private TerrainProxyHandle mTerrainHandle = .Invalid;

	// Grass proxy
	private GrassProxyHandle mGrassHandle = .Invalid;
	private ITexture mGrassBladeTexture;
	private ITextureView mGrassBladeView;

	// Terrain textures (cleaned up in OnShutdown)
	private ITexture mHeightmapTexture;
	private ITextureView mHeightmapView;
	private ITexture mNormalMapTexture;
	private ITextureView mNormalMapView;
	private ITexture mSplatmapTexture;
	private ITextureView mSplatmapView;
	private ITexture[4] mLayerTextures;
	private ITextureView[4] mLayerViews;

	// CPU terrain data (retained for grass placement)
	private float[] mCpuHeightmap ~ delete _;
	private uint8[] mCpuSplatmap ~ delete _;

	// Light
	private LightProxyHandle mSunLight = .Invalid;

	// Orbital camera
	private float mOrbitalYaw = 0.8f;
	private float mOrbitalPitch = 0.5f;
	private float mOrbitalDistance = 180.0f;
	private Vector3 mOrbitalTarget = .(128, 15, 128);

	// Heightmap dimensions
	const int32 HeightmapSize = 512;

	// Terrain settings
	private float mHeightScale = 30.0f;

	// Delta time
	private float mDeltaTime = 0.016f;

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

	// Slider callback delegates
	private List<delegate void(Slider, float)> mSliderCallbacks = new .() ~ DeleteContainerAndItems!(_);

	// GUI widget references
	private TextBlock mFpsLabel;
	private Slider mHeightScaleSlider;

	// Timing
	private int mFrameCount = 0;
	private float mFpsTimer = 0;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnShutdown()
	{
		mWorld?.Dispose();

		// Clean up GUI renderer before render system shutdown
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

		mRenderSystem?.Shutdown();

		// Delete views before textures
		delete mGrassBladeView; mGrassBladeView = null;
		delete mGrassBladeTexture; mGrassBladeTexture = null;
		delete mHeightmapView; mHeightmapView = null;
		delete mNormalMapView; mNormalMapView = null;
		delete mSplatmapView; mSplatmapView = null;
		for (int32 i = 0; i < 4; i++)
		{
			if (mLayerViews[i] != null) { delete mLayerViews[i]; mLayerViews[i] = null; }
			if (mLayerTextures[i] != null) { delete mLayerTextures[i]; mLayerTextures[i] = null; }
		}
		delete mHeightmapTexture; mHeightmapTexture = null;
		delete mNormalMapTexture; mNormalMapTexture = null;
		delete mSplatmapTexture; mSplatmapTexture = null;

		delete mWorld; mWorld = null;
		delete mView; mView = null;
		delete mRenderSystem; mRenderSystem = null;

		Console.WriteLine("Render Terrain shutting down");
	}

	protected override void OnInitialize(Sedulous.Runtime.Context context)
	{
		Console.WriteLine("=== Terrain + Grass Rendering Sample ===\n");

		// Initialize render system
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
		mView.NearPlane = 0.5f;
		mView.FarPlane = 500.0f;

		// Register features
		RegisterFeatures();

		// Generate and upload terrain textures
		GenerateTerrainTextures();

		// Create terrain proxy
		CreateTerrain();

		// Create grass (needs terrain data)
		CreateGrass();

		// Create lights
		CreateLights();

		// Set environment
		mWorld.AmbientColor = .(0.03f, 0.04f, 0.05f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;
		mWorld.AAMode = .None;

		// Create camera
		let cam = mWorld.CreatePerspectiveCamera(
			.(200, 80, 200), mOrbitalTarget, .Up,
			mView.FieldOfView, mView.AspectRatio,
			mView.NearPlane, mView.FarPlane);
		mWorld.SetMainCamera(cam);

		// Initialize GUI
		InitializeGUI();
		BuildSettingsPanel();

		Console.WriteLine("\nControls:");
		Console.WriteLine("  WASD: orbit camera");
		Console.WriteLine("  Q/E: zoom in/out");
		Console.WriteLine("  +/-: adjust height scale");
		Console.WriteLine("  F1: toggle settings panel");
		Console.WriteLine("  ESC: exit\n");
	}

	// ===========================================================
	// GUI
	// ===========================================================

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
		let title = new TextBlock("Terrain + Grass Settings");
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

		// === Terrain ===
		AddSectionHeader(content, "Terrain");

		mHeightScaleSlider = AddSlider(content, "Height Scale", 1.0f, 60.0f, mHeightScale, 1.0f, new (s, val) => {
			mHeightScale = val;
			UpdateHeightScale();
		});

		AddSlider(content, "Roughness", 0.0f, 1.0f, 0.85f, 0.05f, new (s, val) => {
			if (let terrain = mWorld.GetTerrain(mTerrainHandle))
				terrain.Roughness = val;
			mWorld.MarkTerrainsDirty();
		});

		AddSeparator(content);

		// === Grass Placement ===
		AddSectionHeader(content, "Grass Placement");

		AddSlider(content, "Distance", 10.0f, 200.0f, 60.0f, 5.0f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.Distance = val;
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Density", 1.0f, 20.0f, 5.0f, 1.0f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.Density = val;
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Min Scale", 0.1f, 1.0f, 0.5f, 0.05f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.MinScale = val;
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Max Scale", 0.5f, 3.0f, 1.3f, 0.1f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.MaxScale = val;
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Splat Thr.", 0.0f, 1.0f, 0.3f, 0.05f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.SplatThreshold = val;
			mWorld.MarkGrassDirty();
		});

		AddSeparator(content);

		// === Grass Appearance ===
		AddSectionHeader(content, "Grass Appearance");

		AddSlider(content, "Blade Width", 0.02f, 0.5f, 0.12f, 0.01f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.BladeWidth = val;
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Blade Height", 0.1f, 2.0f, 0.5f, 0.05f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.BladeHeight = val;
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Alpha Cut", 0.0f, 1.0f, 0.4f, 0.05f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.AlphaCutoff = val;
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Roughness", 0.0f, 1.0f, 0.85f, 0.05f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.Roughness = val;
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Color R", 0.0f, 1.0f, 0.35f, 0.02f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.GrassColor = .(val, grass.GrassColor.Y, grass.GrassColor.Z);
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Color G", 0.0f, 1.0f, 0.55f, 0.02f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.GrassColor = .(grass.GrassColor.X, val, grass.GrassColor.Z);
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Color B", 0.0f, 1.0f, 0.15f, 0.02f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.GrassColor = .(grass.GrassColor.X, grass.GrassColor.Y, val);
			mWorld.MarkGrassDirty();
		});

		AddSeparator(content);

		// === Wind ===
		AddSectionHeader(content, "Wind");

		AddSlider(content, "Strength", 0.0f, 2.0f, 0.25f, 0.05f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.WindStrength = val;
			mWorld.MarkGrassDirty();
		});

		AddSlider(content, "Frequency", 0.0f, 5.0f, 1.5f, 0.1f, new (s, val) => {
			if (let grass = mWorld.GetGrass(mGrassHandle))
				grass.WindFrequency = val;
			mWorld.MarkGrassDirty();
		});

		AddSeparator(content);

		// === Environment ===
		AddSectionHeader(content, "Environment");

		AddSlider(content, "Sun Intens.", 0.0f, 10.0f, 3.0f, 0.5f, new (s, val) => {
			if (let light = mWorld.GetLight(mSunLight))
				light.Intensity = val;
		});

		AddSlider(content, "Ambient", 0.0f, 2.0f, 0.5f, 0.05f, new (s, val) => {
			mWorld.AmbientIntensity = val;
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

	private void AddSeparator(StackPanel parent)
	{
		let sep = new Separator();
		sep.Margin = .(0, 2, 0, 2);
		parent.AddChild(sep);
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

	// ===========================================================
	// Feature Registration
	// ===========================================================

	private void RegisterFeatures()
	{
		mDepthFeature = new DepthPrepassFeature();
		if (mRenderSystem.RegisterFeature(mDepthFeature) case .Err)
			Console.WriteLine("Warning: Failed to register DepthPrepassFeature");

		mForwardFeature = new ForwardOpaqueFeature();
		if (mRenderSystem.RegisterFeature(mForwardFeature) case .Err)
			Console.WriteLine("Warning: Failed to register ForwardOpaqueFeature");

		mTerrainFeature = new TerrainFeature();
		if (mRenderSystem.RegisterFeature(mTerrainFeature) case .Err)
			Console.WriteLine("Warning: Failed to register TerrainFeature");

		mGrassFeature = new GrassFeature();
		if (mRenderSystem.RegisterFeature(mGrassFeature) case .Err)
			Console.WriteLine("Warning: Failed to register GrassFeature");

		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");

		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");

		Console.WriteLine("Registered terrain + grass rendering features");
	}

	// ===========================================================
	// Terrain Texture Generation
	// ===========================================================

	private void GenerateTerrainTextures()
	{
		GenerateHeightmap();
		GenerateNormalMap();
		GenerateSplatmap();
		GenerateLayerTextures();
		Console.WriteLine("Generated terrain textures");
	}

	/// Compute terrain height at normalized UV coordinates.
	private static float ComputeHeight(float fx, float fy)
	{
		float h = 0.0f;
		h += Math.Sin(fx * 3.0f * Math.PI_f) * 0.3f;
		h += Math.Sin(fy * 2.5f * Math.PI_f) * 0.25f;
		h += Math.Sin((fx + fy) * 5.0f * Math.PI_f) * 0.15f;
		h += Math.Sin(fx * 8.0f * Math.PI_f) * Math.Cos(fy * 6.0f * Math.PI_f) * 0.1f;
		h += Math.Sin(fx * 13.0f * Math.PI_f + 1.7f) * Math.Sin(fy * 11.0f * Math.PI_f + 0.3f) * 0.05f;
		h = (h + 0.85f) * 0.5f;
		return Math.Clamp(h, 0.0f, 1.0f);
	}

	private void GenerateHeightmap()
	{
		TextureDescriptor desc = .()
		{
			Label = "Terrain Heightmap",
			Width = HeightmapSize, Height = HeightmapSize, Depth = 1,
			Format = .R16Float, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex): mHeightmapTexture = tex;
		case .Err: Console.WriteLine("ERROR: Failed to create heightmap"); return;
		}

		// Keep CPU float array for grass placement
		mCpuHeightmap = new float[HeightmapSize * HeightmapSize];
		uint16[] pixels = new uint16[HeightmapSize * HeightmapSize];
		defer delete pixels;

		for (int32 y = 0; y < HeightmapSize; y++)
		{
			for (int32 x = 0; x < HeightmapSize; x++)
			{
				float h = ComputeHeight((float)x / (float)HeightmapSize, (float)y / (float)HeightmapSize);
				mCpuHeightmap[y * HeightmapSize + x] = h;
				pixels[y * HeightmapSize + x] = FloatToHalf(h);
			}
		}

		TextureDataLayout layout = .() { BytesPerRow = (uint32)(HeightmapSize * 2), RowsPerImage = (uint32)HeightmapSize };
		Extent3D size = .((uint32)HeightmapSize, (uint32)HeightmapSize, 1);
		mDevice.Queue.WriteTextureSync(mHeightmapTexture, Span<uint8>((uint8*)pixels.Ptr, HeightmapSize * HeightmapSize * 2), &layout, &size);

		TextureViewDescriptor viewDesc = .() { Format = .R16Float, Dimension = .Texture2D };
		if (mDevice.CreateTextureView(mHeightmapTexture, &viewDesc) case .Ok(let view))
			mHeightmapView = view;
	}

	private void GenerateNormalMap()
	{
		TextureDescriptor desc = .()
		{
			Label = "Terrain Normal Map",
			Width = HeightmapSize, Height = HeightmapSize, Depth = 1,
			Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex): mNormalMapTexture = tex;
		case .Err: return;
		}

		// Scale CPU heightmap values to world heights
		float[] heights = new float[HeightmapSize * HeightmapSize];
		defer delete heights;

		for (int32 i = 0; i < HeightmapSize * HeightmapSize; i++)
			heights[i] = mCpuHeightmap[i] * mHeightScale;

		uint8[] pixels = new uint8[HeightmapSize * HeightmapSize * 4];
		defer delete pixels;

		float worldSizePerTexel = 256.0f / (float)HeightmapSize;

		for (int32 y = 0; y < HeightmapSize; y++)
		{
			for (int32 x = 0; x < HeightmapSize; x++)
			{
				let x0 = Math.Max(x - 1, 0);
				let x1 = Math.Min(x + 1, HeightmapSize - 1);
				let y0 = Math.Max(y - 1, 0);
				let y1 = Math.Min(y + 1, HeightmapSize - 1);

				float hL = heights[y * HeightmapSize + x0];
				float hR = heights[y * HeightmapSize + x1];
				float hD = heights[y0 * HeightmapSize + x];
				float hU = heights[y1 * HeightmapSize + x];

				float dx = (hR - hL) / (2.0f * worldSizePerTexel);
				float dz = (hU - hD) / (2.0f * worldSizePerTexel);

				Vector3 normal = Vector3.Normalize(.(-dx, 1.0f, -dz));

				int32 idx = (y * HeightmapSize + x) * 4;
				pixels[idx + 0] = (uint8)(Math.Clamp(normal.X * 0.5f + 0.5f, 0.0f, 1.0f) * 255.0f);
				pixels[idx + 1] = (uint8)(Math.Clamp(normal.Y * 0.5f + 0.5f, 0.0f, 1.0f) * 255.0f);
				pixels[idx + 2] = (uint8)(Math.Clamp(normal.Z * 0.5f + 0.5f, 0.0f, 1.0f) * 255.0f);
				pixels[idx + 3] = 255;
			}
		}

		TextureDataLayout layout = .() { BytesPerRow = (uint32)(HeightmapSize * 4), RowsPerImage = (uint32)HeightmapSize };
		Extent3D size = .((uint32)HeightmapSize, (uint32)HeightmapSize, 1);
		mDevice.Queue.WriteTextureSync(mNormalMapTexture, Span<uint8>(pixels.Ptr, HeightmapSize * HeightmapSize * 4), &layout, &size);

		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D };
		if (mDevice.CreateTextureView(mNormalMapTexture, &viewDesc) case .Ok(let view))
			mNormalMapView = view;
	}

	private void GenerateSplatmap()
	{
		TextureDescriptor desc = .()
		{
			Label = "Terrain Splatmap",
			Width = HeightmapSize, Height = HeightmapSize, Depth = 1,
			Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex): mSplatmapTexture = tex;
		case .Err: return;
		}

		// Retain CPU splatmap for grass placement
		mCpuSplatmap = new uint8[HeightmapSize * HeightmapSize * 4];
		uint8[] pixels = mCpuSplatmap;

		float worldSizePerTexel = 256.0f / (float)HeightmapSize;

		for (int32 y = 0; y < HeightmapSize; y++)
		{
			for (int32 x = 0; x < HeightmapSize; x++)
			{
				float h = mCpuHeightmap[y * HeightmapSize + x];

				// Compute slope
				let x0 = Math.Max(x - 1, 0);
				let x1 = Math.Min(x + 1, HeightmapSize - 1);
				let y0 = Math.Max(y - 1, 0);
				let y1 = Math.Min(y + 1, HeightmapSize - 1);

				float hL = mCpuHeightmap[y * HeightmapSize + x0];
				float hR = mCpuHeightmap[y * HeightmapSize + x1];
				float hD = mCpuHeightmap[y0 * HeightmapSize + x];
				float hU = mCpuHeightmap[y1 * HeightmapSize + x];

				float dx = (hR - hL) * mHeightScale / (2.0f * worldSizePerTexel);
				float dz = (hU - hD) * mHeightScale / (2.0f * worldSizePerTexel);
				float slope = Math.Sqrt(dx * dx + dz * dz);

				float grass = 0, dirt = 0, rock = 0, snow = 0;

				grass = Math.Clamp(1.0f - (h - 0.3f) * 4.0f, 0.0f, 1.0f);
				dirt = Math.Clamp(1.0f - Math.Abs(h - 0.5f) * 5.0f, 0.0f, 1.0f);
				snow = Math.Clamp((h - 0.7f) * 5.0f, 0.0f, 1.0f);
				rock = Math.Clamp((slope - 0.5f) * 2.0f, 0.0f, 1.0f);

				float rockBlend = rock;
				grass *= (1.0f - rockBlend);
				dirt *= (1.0f - rockBlend);
				snow *= (1.0f - rockBlend * 0.5f);

				float total = grass + dirt + rock + snow;
				if (total > 0.001f)
				{
					grass /= total; dirt /= total; rock /= total; snow /= total;
				}
				else
				{
					grass = 1.0f;
				}

				int32 idx = (y * HeightmapSize + x) * 4;
				pixels[idx + 0] = (uint8)(grass * 255.0f);
				pixels[idx + 1] = (uint8)(dirt * 255.0f);
				pixels[idx + 2] = (uint8)(rock * 255.0f);
				pixels[idx + 3] = (uint8)(snow * 255.0f);
			}
		}

		TextureDataLayout layout = .() { BytesPerRow = (uint32)(HeightmapSize * 4), RowsPerImage = (uint32)HeightmapSize };
		Extent3D size = .((uint32)HeightmapSize, (uint32)HeightmapSize, 1);
		mDevice.Queue.WriteTextureSync(mSplatmapTexture, Span<uint8>(pixels.Ptr, HeightmapSize * HeightmapSize * 4), &layout, &size);

		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D };
		if (mDevice.CreateTextureView(mSplatmapTexture, &viewDesc) case .Ok(let view))
			mSplatmapView = view;
	}

	private void GenerateLayerTextures()
	{
		Color[4] colors = .(
			.(76, 153, 51, 255),    // Green (grass)
			.(140, 100, 60, 255),   // Brown (dirt)
			.(128, 128, 128, 255),  // Gray (rock)
			.(230, 230, 240, 255)   // White-ish (snow)
		);

		for (int32 i = 0; i < 4; i++)
		{
			TextureDescriptor desc = .()
			{
				Label = "Terrain Layer",
				Width = 4, Height = 4, Depth = 1,
				Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
				SampleCount = 1, Dimension = .Texture2D,
				Usage = .Sampled | .CopyDst
			};

			switch (mDevice.CreateTexture(&desc))
			{
			case .Ok(let tex): mLayerTextures[i] = tex;
			case .Err: continue;
			}

			uint8[64] pixels = default;
			for (int32 p = 0; p < 16; p++)
			{
				pixels[p * 4 + 0] = colors[i].R;
				pixels[p * 4 + 1] = colors[i].G;
				pixels[p * 4 + 2] = colors[i].B;
				pixels[p * 4 + 3] = colors[i].A;
			}

			TextureDataLayout layout = .() { BytesPerRow = 16, RowsPerImage = 4 };
			Extent3D size = .(4, 4, 1);
			mDevice.Queue.WriteTextureSync(mLayerTextures[i], Span<uint8>(&pixels[0], 64), &layout, &size);

			TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D };
			if (mDevice.CreateTextureView(mLayerTextures[i], &viewDesc) case .Ok(let view))
				mLayerViews[i] = view;
		}
	}

	// ===========================================================
	// Scene Setup
	// ===========================================================

	private void CreateTerrain()
	{
		mTerrainHandle = mWorld.CreateTerrain();
		if (let terrain = mWorld.GetTerrain(mTerrainHandle))
		{
			terrain.Position = .Zero;
			terrain.WorldSize = .(256, 256);
			terrain.HeightScale = mHeightScale;
			terrain.HeightmapWidth = HeightmapSize;
			terrain.HeightmapHeight = HeightmapSize;
			terrain.PatchCountX = 8;
			terrain.PatchCountZ = 8;
			terrain.LayerScales = .(16.0f, 16.0f, 16.0f, 16.0f);
			terrain.Roughness = 0.85f;
			terrain.Metallic = 0.0f;

			terrain.HeightmapView = mHeightmapView;
			terrain.NormalMapView = mNormalMapView;
			terrain.SplatmapView = mSplatmapView;
			terrain.LayerAlbedoViews[0] = mLayerViews[0];
			terrain.LayerAlbedoViews[1] = mLayerViews[1];
			terrain.LayerAlbedoViews[2] = mLayerViews[2];
			terrain.LayerAlbedoViews[3] = mLayerViews[3];

			terrain.WorldBounds = .(.(0, 0, 0), .(256, mHeightScale, 256));
		}

		mWorld.MarkTerrainsDirty();
		mTerrainFeature.InvalidateBindGroups();
		Console.WriteLine("Created terrain: 256x256 world units, 8x8 patches, heightScale={}", mHeightScale);
	}

	private void CreateGrass()
	{
		GenerateGrassBladeTexture();

		mGrassHandle = mWorld.CreateGrass();
		if (let grass = mWorld.GetGrass(mGrassHandle))
		{
			// Terrain placement
			grass.TerrainOrigin = .Zero;
			grass.TerrainWorldSize = .(256, 256);
			grass.HeightScale = mHeightScale;
			grass.HeightmapData = mCpuHeightmap.Ptr;
			grass.HeightmapWidth = (uint32)HeightmapSize;
			grass.HeightmapHeight = (uint32)HeightmapSize;
			grass.SplatmapData = mCpuSplatmap.Ptr;
			grass.SplatmapWidth = (uint32)HeightmapSize;
			grass.SplatmapHeight = (uint32)HeightmapSize;
			grass.SplatChannel = 0; // R channel = grass layer
			grass.SplatThreshold = 0.3f;

			// Appearance
			grass.GrassColor = .(0.35f, 0.55f, 0.15f);
			grass.AlphaCutoff = 0.4f;
			grass.Roughness = 0.85f;
			grass.BladeWidth = 0.12f;
			grass.BladeHeight = 0.5f;

			// Placement
			grass.Distance = 60.0f;
			grass.Density = 5.0f;
			grass.MinScale = 0.5f;
			grass.MaxScale = 1.3f;

			// Wind
			grass.WindStrength = 0.25f;
			grass.WindFrequency = 1.5f;
			grass.WindDirection = Vector2.Normalize(.(1.0f, 0.3f));

			// Texture
			grass.AlbedoView = mGrassBladeView;

			grass.WorldBounds = .(.(0, 0, 0), .(256, mHeightScale, 256));
		}

		mWorld.MarkGrassDirty();
		mGrassFeature.InvalidateBindGroups();
		Console.WriteLine("Created grass: density=5, distance=60, splatChannel=0 (grass layer)");
	}

	private void GenerateGrassBladeTexture()
	{
		// Procedural grass blade: 32x64 RGBA8, vertical gradient with tapered alpha shape
		int32 texW = 32;
		int32 texH = 64;

		TextureDescriptor desc = .()
		{
			Label = "Grass Blade",
			Width = (uint32)texW, Height = (uint32)texH, Depth = 1,
			Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex): mGrassBladeTexture = tex;
		case .Err: return;
		}

		uint8[] pixels = new uint8[texW * texH * 4];
		defer delete pixels;

		for (int32 y = 0; y < texH; y++)
		{
			float v = (float)y / (float)(texH - 1); // 0=top(V=0=root), 1=bottom(V=1=tip)
			float tipFactor = v; // 0 at root (top), 1 at tip (bottom)

			for (int32 x = 0; x < texW; x++)
			{
				float u = (float)x / (float)(texW - 1);

				float centerDist = Math.Abs(u - 0.5f) * 2.0f;
				float bladeWidth = 1.0f - tipFactor * 0.7f;
				float alpha = 1.0f - Math.Clamp((centerDist - bladeWidth * 0.5f) / 0.15f, 0.0f, 1.0f);

				if (tipFactor > 0.8f)
				{
					float tipBlend = (tipFactor - 0.8f) / 0.2f;
					alpha *= 1.0f - tipBlend * tipBlend;
				}

				float green = 0.5f + tipFactor * 0.15f;
				uint8 r = (uint8)(80 + tipFactor * 20);
				uint8 g = (uint8)(green * 255.0f);
				uint8 b = (uint8)(40 + tipFactor * 10);
				uint8 a = (uint8)(Math.Clamp(alpha, 0.0f, 1.0f) * 255.0f);

				int32 idx = (y * texW + x) * 4;
				pixels[idx + 0] = r;
				pixels[idx + 1] = g;
				pixels[idx + 2] = b;
				pixels[idx + 3] = a;
			}
		}

		TextureDataLayout layout = .() { BytesPerRow = (uint32)(texW * 4), RowsPerImage = (uint32)texH };
		Extent3D size = .((uint32)texW, (uint32)texH, 1);
		mDevice.Queue.WriteTextureSync(mGrassBladeTexture, Span<uint8>(pixels.Ptr, texW * texH * 4), &layout, &size);

		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D };
		if (mDevice.CreateTextureView(mGrassBladeTexture, &viewDesc) case .Ok(let view))
			mGrassBladeView = view;
	}

	private void CreateLights()
	{
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -0.8f, 0.3f)),
			.(1.0f, 0.95f, 0.85f),
			3.0f);

		if (let light = mWorld.GetLight(mSunLight))
			light.CastsShadows = true;

		Console.WriteLine("Created directional sun light with shadows");
	}

	// ===========================================================
	// Update Loop
	// ===========================================================

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

		// Route mouse/keyboard to GUI
		if (mGUIContext != null && mShowGUI)
		{
			GUIInputHelper.ProcessMouseInput(mouse, keyboard, mGUIContext);
			mInputHelper.ProcessKeyboardInput(keyboard, mGUIContext, mDeltaTime);

			let guiCursor = mGUIContext.CurrentCursor;
			if (guiCursor != mLastCursor)
			{
				mLastCursor = guiCursor;
				mouse.Cursor = InputMapping.MapCursor(guiCursor);
			}
		}

		// Camera controls — only when GUI doesn't want mouse
		bool guiWantsMouse = mShowGUI && mGUIContext != null &&
			mGUIContext.CurrentCursor != .Default;

		if (!guiWantsMouse)
		{
			float rotSpeed = 1.5f * mDeltaTime;
			float zoomSpeed = 60.0f * mDeltaTime;

			if (keyboard.IsKeyDown(.W)) mOrbitalPitch += rotSpeed;
			if (keyboard.IsKeyDown(.S)) mOrbitalPitch -= rotSpeed;
			if (keyboard.IsKeyDown(.A)) mOrbitalYaw -= rotSpeed;
			if (keyboard.IsKeyDown(.D)) mOrbitalYaw += rotSpeed;
			if (keyboard.IsKeyDown(.Q)) mOrbitalDistance -= zoomSpeed;
			if (keyboard.IsKeyDown(.E)) mOrbitalDistance += zoomSpeed;
		}

		// Height scale keyboard adjustment (always works)
		float heightSpeed = 10.0f * mDeltaTime;
		if (keyboard.IsKeyDown(.Equals))
		{
			mHeightScale += heightSpeed;
			UpdateHeightScale();
			if (mHeightScaleSlider != null)
				mHeightScaleSlider.Value = mHeightScale;
		}
		if (keyboard.IsKeyDown(.Minus))
		{
			mHeightScale = Math.Max(1.0f, mHeightScale - heightSpeed);
			UpdateHeightScale();
			if (mHeightScaleSlider != null)
				mHeightScaleSlider.Value = mHeightScale;
		}

		mOrbitalPitch = Math.Clamp(mOrbitalPitch, 0.1f, 1.4f);
		mOrbitalDistance = Math.Clamp(mOrbitalDistance, 20.0f, 400.0f);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;
		mDeltaTime = dt;

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

		UpdateCamera();

		// Update GUI
		if (mGUIContext != null)
			mGUIContext.Update(dt, (double)frame.TotalTime);
	}

	private void UpdateHeightScale()
	{
		if (let terrain = mWorld.GetTerrain(mTerrainHandle))
		{
			terrain.HeightScale = mHeightScale;
			terrain.WorldBounds = .(.(0, 0, 0), .(256, mHeightScale, 256));
		}
		if (let grass = mWorld.GetGrass(mGrassHandle))
		{
			grass.HeightScale = mHeightScale;
			grass.WorldBounds = .(.(0, 0, 0), .(256, mHeightScale, 256));
		}
		mWorld.MarkTerrainsDirty();
		mWorld.MarkGrassDirty();
	}

	private void UpdateCamera()
	{
		float x = mOrbitalDistance * Math.Cos(mOrbitalPitch) * Math.Cos(mOrbitalYaw);
		float y = mOrbitalDistance * Math.Sin(mOrbitalPitch);
		float z = mOrbitalDistance * Math.Cos(mOrbitalPitch) * Math.Sin(mOrbitalYaw);

		let camPos = mOrbitalTarget + Vector3(x, y, z);

		if (let cam = mWorld.GetCamera(mWorld.MainCamera))
		{
			cam.SetLookAt(camPos, mOrbitalTarget, .Up);
			cam.AspectRatio = (float)mView.Width / (float)mView.Height;
			cam.UpdateMatrices(true);
		}

		mView.CameraPosition = camPos;
		mView.CameraForward = Vector3.Normalize(mOrbitalTarget - camPos);
		mView.CameraUp = .Up;
	}

	// ===========================================================
	// Render
	// ===========================================================

	protected override bool OnRenderFrame(RenderContext render)
	{
		if (mRenderSystem == null)
			return false;

		mView.Width = render.SwapChain.Width;
		mView.Height = render.SwapChain.Height;

		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		let camPos = mView.CameraPosition;
		let camFwd = mView.CameraForward;
		mRenderSystem.SetCamera(
			camPos, camFwd, Vector3.Up,
			mView.FieldOfView, mView.AspectRatio,
			mView.NearPlane, mView.FarPlane,
			mView.Width, mView.Height);

		if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
			mRenderSystem.Execute(render.Encoder);

		mRenderSystem.EndFrame();

		// --- GUI Overlay ---
		if (mShowGUI && mGUIContext != null && mDrawingRenderer != null)
		{
			let frameIndex = (int32)render.SwapChain.CurrentFrameIndex;

			mDrawContext.Clear();
			mGUIContext.Render(mDrawContext);

			mDrawingRenderer.UpdateProjection(render.SwapChain.Width, render.SwapChain.Height, frameIndex);
			mDrawingRenderer.Prepare(mDrawContext.GetBatch(), frameIndex);

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
		if (mView != null)
		{
			mView.Width = (uint32)width;
			mView.Height = (uint32)height;
		}
		if (mGUIContext != null)
			mGUIContext.SetViewportSize((float)width, (float)height);
	}

	/// Convert float to IEEE 754 half-precision.
	private static uint16 FloatToHalf(float value)
	{
		float val = value;
		uint32 f = *(uint32*)&val;
		uint32 sign = (f >> 16) & 0x8000;
		int32 exponent = (int32)((f >> 23) & 0xFF) - 127;
		uint32 mantissa = f & 0x7FFFFF;

		if (exponent > 15)
			return (uint16)(sign | 0x7C00);
		if (exponent < -14)
			return (uint16)sign;

		uint16 halfExp = (uint16)((exponent + 15) << 10);
		uint16 halfMant = (uint16)(mantissa >> 13);

		return (uint16)(sign | halfExp | halfMant);
	}
}

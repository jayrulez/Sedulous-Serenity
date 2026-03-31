using Sedulous.Core.Mathematics;
using Sedulous.Runtime.Client;
using Sedulous.RHI;
using Sedulous.Shell.Input;
using Sedulous.Render;
using Sedulous.GUI;
using Sedulous.GUI.Runtime;
using Sedulous.Fonts;
using System;
using System.Collections;

namespace RenderWater;

typealias ShellKeyCode = Sedulous.Shell.Input.KeyCode;

/// Water rendering sample.
/// Demonstrates water plane with animated waves, refraction, Fresnel reflection,
/// depth-based absorption, and shore foam over terrain.
class RenderWaterApp : Application
{
	// Render system
	private RenderSystem mRenderSystem;
	private RenderWorld mWorld;
	private RenderView mView;

	// Render features (owned by RenderSystem after registration)
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private TerrainFeature mTerrainFeature;
	private WaterFeature mWaterFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Terrain proxy
	private TerrainProxyHandle mTerrainHandle = .Invalid;

	// Water proxy
	private WaterProxyHandle mWaterHandle = .Invalid;

	// Terrain textures
	private ITexture mHeightmapTexture;
	private ITextureView mHeightmapView;
	private ITexture mNormalMapTexture;
	private ITextureView mNormalMapView;
	private ITexture mSplatmapTexture;
	private ITextureView mSplatmapView;
	private ITexture[4] mLayerTextures;
	private ITextureView[4] mLayerViews;

	// Water textures
	private ITexture mWaterNormalTexture;
	private ITextureView mWaterNormalView;
	private ITexture mFoamTexture;
	private ITextureView mFoamView;

	// Light
	private LightProxyHandle mSunLight = .Invalid;

	// Orbital camera
	private float mOrbitalYaw = 0.8f;
	private float mOrbitalPitch = 0.45f;
	private float mOrbitalDistance = 200.0f;
	private Vector3 mOrbitalTarget = .(128, 12, 128);

	// Heightmap dimensions
	const int32 HeightmapSize = 512;
	const int32 WaterNormalMapSize = 256;

	// Terrain settings
	private float mHeightScale = 20.0f;

	// Water level
	private float mWaterLevel = 10.0f;

	// Delta time
	private float mDeltaTime = 0.016f;

	// GUI system
	private Sedulous.GUI.Runtime.UISubsystem mUISubsystem;
	private bool mShowGUI = true;

	private DockPanel mRoot;

	// Slider callback delegates
	private List<delegate void(Slider, float)> mSliderCallbacks = new .() ~ DeleteContainerAndItems!(_);

	// GUI widget references
	private TextBlock mFpsLabel;
	private Slider mWaterLevelSlider;

	// Timing
	private int mFrameCount = 0;
	private float mFpsTimer = 0;

	public this()
		: base()
	{
	}

	protected override void OnShutdown()
	{
		DeleteAndNullify!(mRoot);

		mWorld?.Dispose();

		// Destroy sample-owned textures before render system shutdown
		if (mDevice != null)
		{
			mDevice.DestroyTextureView(ref mHeightmapView);
			mDevice.DestroyTextureView(ref mNormalMapView);
			mDevice.DestroyTextureView(ref mSplatmapView);
			for (int32 i = 0; i < 4; i++)
			{
				mDevice.DestroyTextureView(ref mLayerViews[i]);
				mDevice.DestroyTexture(ref mLayerTextures[i]);
			}
			mDevice.DestroyTexture(ref mHeightmapTexture);
			mDevice.DestroyTexture(ref mNormalMapTexture);
			mDevice.DestroyTexture(ref mSplatmapTexture);

			mDevice.DestroyTextureView(ref mWaterNormalView);
			mDevice.DestroyTextureView(ref mFoamView);
			mDevice.DestroyTexture(ref mWaterNormalTexture);
			mDevice.DestroyTexture(ref mFoamTexture);
		}

		if (mRenderSystem != null)
		{
			mRenderSystem.Shutdown();
			delete mRenderSystem;
			mRenderSystem = null;
		}
		delete mWorld;
		delete mView;

		Console.WriteLine("Render Water shutting down");
	}

	protected override void OnInitialize(Sedulous.Runtime.Context context)
	{
		Console.WriteLine("=== Water Rendering Sample ===\n");

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
		mView.NearPlane = 0.5f;
		mView.FarPlane = 500.0f;

		RegisterFeatures();
		GenerateTerrainTextures();
		GenerateWaterTextures();
		CreateTerrain();
		CreateWater();
		CreateLights();

		// Environment
		mWorld.AmbientColor = .(0.03f, 0.04f, 0.05f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;
		mWorld.AAMode = .None;

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
		Console.WriteLine("  +/-: adjust water level");
		Console.WriteLine("  F1: toggle settings panel");
		Console.WriteLine("  ESC: exit\n");
	}

	private void InitializeGUI()
	{
		mUISubsystem = new Sedulous.GUI.Runtime.UISubsystem();
		mContext.RegisterSubsystem(mUISubsystem);

		let shaderPath = scope $"{AssetDirectory}/Render/shaders";
		if (mUISubsystem.InitializeRendering(mDevice, mSwapChain.Format, (int32)mSwapChain.BufferCount, mShell, mWindow, scope StringView[](shaderPath)) case .Err)
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
		let title = new TextBlock("Water Settings");
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

		// === Water ===
		AddSectionHeader(content, "Water");

		mWaterLevelSlider = AddSlider(content, "Water Level", 0.0f, 20.0f, mWaterLevel, 0.5f, new (s, val) => {
			mWaterLevel = val;
			UpdateWaterLevel();
		});

		AddSlider(content, "Wave Speed", 0.0f, 5.0f, 0.8f, 0.1f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.WaveSpeed = val;
			mWorld.MarkWatersDirty();
		});

		AddSlider(content, "Wave Scale", 1.0f, 20.0f, 6.0f, 0.5f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.WaveScale = val;
			mWorld.MarkWatersDirty();
		});

		AddSlider(content, "Normal Str", 0.0f, 2.0f, 0.4f, 0.05f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.NormalStrength = val;
			mWorld.MarkWatersDirty();
		});

		AddSeparator(content);

		// === Color & Depth ===
		AddSectionHeader(content, "Color & Depth");

		AddSlider(content, "Color R", 0.0f, 0.5f, 0.0f, 0.01f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.WaterColor = .(val, water.WaterColor.Y, water.WaterColor.Z, 1.0f);
			mWorld.MarkWatersDirty();
		});

		AddSlider(content, "Color G", 0.0f, 0.5f, 0.08f, 0.01f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.WaterColor = .(water.WaterColor.X, val, water.WaterColor.Z, 1.0f);
			mWorld.MarkWatersDirty();
		});

		AddSlider(content, "Color B", 0.0f, 0.5f, 0.15f, 0.01f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.WaterColor = .(water.WaterColor.X, water.WaterColor.Y, val, 1.0f);
			mWorld.MarkWatersDirty();
		});

		AddSlider(content, "Max Depth", 1.0f, 30.0f, 8.0f, 0.5f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.MaxVisibleDepth = val;
			mWorld.MarkWatersDirty();
		});

		AddSeparator(content);

		// === Reflection ===
		AddSectionHeader(content, "Reflection");

		AddSlider(content, "Fresnel R0", 0.0f, 0.2f, 0.02f, 0.005f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.FresnelR0 = val;
			mWorld.MarkWatersDirty();
		});

		AddSlider(content, "Roughness", 0.0f, 1.0f, 0.08f, 0.05f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.Roughness = val;
			mWorld.MarkWatersDirty();
		});

		AddSlider(content, "Refraction", 0.0f, 0.1f, 0.025f, 0.005f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.RefractionStrength = val;
			mWorld.MarkWatersDirty();
		});

		AddSlider(content, "Spec Power", 32.0f, 512.0f, 256.0f, 16.0f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.SpecularPower = val;
			mWorld.MarkWatersDirty();
		});

		AddSeparator(content);

		// === Foam ===
		AddSectionHeader(content, "Foam");

		AddSlider(content, "Depth Thr.", 0.0f, 3.0f, 0.8f, 0.1f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.FoamDepthThreshold = val;
			mWorld.MarkWatersDirty();
		});

		AddSlider(content, "Intensity", 0.0f, 2.0f, 0.7f, 0.1f, new (s, val) => {
			if (let water = mWorld.GetWater(mWaterHandle))
				water.FoamIntensity = val;
			mWorld.MarkWatersDirty();
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

		mUISubsystem.GUIContext.RootElement = mRoot;
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

		mWaterFeature = new WaterFeature();
		if (mRenderSystem.RegisterFeature(mWaterFeature) case .Err)
			Console.WriteLine("Warning: Failed to register WaterFeature");

		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");

		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");

		Console.WriteLine("Registered water rendering features");
	}

	// ===========================================================
	// Terrain Texture Generation (same as RenderTerrain but lower amplitude)
	// ===========================================================

	private void GenerateTerrainTextures()
	{
		GenerateHeightmap();
		GenerateTerrainNormalMap();
		GenerateSplatmap();
		GenerateLayerTextures();
		Console.WriteLine("Generated terrain textures");
	}

	private float SampleHeight(float fx, float fy)
	{
		float h = 0.0f;
		h += Math.Sin(fx * 3.0f * Math.PI_f) * 0.3f;
		h += Math.Sin(fy * 2.5f * Math.PI_f) * 0.25f;
		h += Math.Sin((fx + fy) * 5.0f * Math.PI_f) * 0.12f;
		h += Math.Sin(fx * 8.0f * Math.PI_f) * Math.Cos(fy * 6.0f * Math.PI_f) * 0.08f;
		h = (h + 0.75f) * 0.5f; // Normalized so valleys go below water level
		return Math.Clamp(h, 0.0f, 1.0f);
	}

	private void GenerateHeightmap()
	{
		TextureDesc desc = .()
		{
			Label = "Terrain Heightmap",
			Width = HeightmapSize, Height = HeightmapSize, Depth = 1,
			Format = .R16Float, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(desc))
		{
		case .Ok(let tex): mHeightmapTexture = tex;
		case .Err: Console.WriteLine("ERROR: Failed to create heightmap"); return;
		}

		uint16[] pixels = new uint16[HeightmapSize * HeightmapSize];
		defer delete pixels;

		for (int32 y = 0; y < HeightmapSize; y++)
		{
			for (int32 x = 0; x < HeightmapSize; x++)
			{
				float fx = (float)x / (float)HeightmapSize;
				float fy = (float)y / (float)HeightmapSize;
				float h = SampleHeight(fx, fy);
				pixels[y * HeightmapSize + x] = FloatToHalf(h);
			}
		}

		TextureDataLayout layout = .() { BytesPerRow = (uint32)(HeightmapSize * 2), RowsPerImage = (uint32)HeightmapSize };
		Extent3D size = .((uint32)HeightmapSize, (uint32)HeightmapSize, 1);
		TransferHelper.WriteTextureSync(mDevice.GetQueue(.Graphics), mDevice, mHeightmapTexture, Span<uint8>((uint8*)pixels.Ptr, HeightmapSize * HeightmapSize * 2), layout, size);

		TextureViewDesc viewDesc = .() { Format = .R16Float, Dimension = .Texture2D };
		if (mDevice.CreateTextureView(mHeightmapTexture, viewDesc) case .Ok(let view))
			mHeightmapView = view;
	}

	private void GenerateTerrainNormalMap()
	{
		TextureDesc desc = .()
		{
			Label = "Terrain Normal Map",
			Width = HeightmapSize, Height = HeightmapSize, Depth = 1,
			Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(desc))
		{
		case .Ok(let tex): mNormalMapTexture = tex;
		case .Err: return;
		}

		float[] heights = new float[HeightmapSize * HeightmapSize];
		defer delete heights;

		for (int32 y = 0; y < HeightmapSize; y++)
			for (int32 x = 0; x < HeightmapSize; x++)
				heights[y * HeightmapSize + x] = SampleHeight((float)x / HeightmapSize, (float)y / HeightmapSize) * mHeightScale;

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

				float dx = (heights[y * HeightmapSize + x1] - heights[y * HeightmapSize + x0]) / (2.0f * worldSizePerTexel);
				float dz = (heights[y1 * HeightmapSize + x] - heights[y0 * HeightmapSize + x]) / (2.0f * worldSizePerTexel);

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
		TransferHelper.WriteTextureSync(mDevice.GetQueue(.Graphics), mDevice, mNormalMapTexture, Span<uint8>(pixels.Ptr, HeightmapSize * HeightmapSize * 4), layout, size);

		TextureViewDesc viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D };
		if (mDevice.CreateTextureView(mNormalMapTexture, viewDesc) case .Ok(let view))
			mNormalMapView = view;
	}

	private void GenerateSplatmap()
	{
		TextureDesc desc = .()
		{
			Label = "Terrain Splatmap",
			Width = HeightmapSize, Height = HeightmapSize, Depth = 1,
			Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(desc))
		{
		case .Ok(let tex): mSplatmapTexture = tex;
		case .Err: return;
		}

		uint8[] pixels = new uint8[HeightmapSize * HeightmapSize * 4];
		defer delete pixels;

		for (int32 y = 0; y < HeightmapSize; y++)
		{
			for (int32 x = 0; x < HeightmapSize; x++)
			{
				float h = SampleHeight((float)x / HeightmapSize, (float)y / HeightmapSize);

				float grass = Math.Clamp(1.0f - (h - 0.3f) * 4.0f, 0.0f, 1.0f);
				float dirt = Math.Clamp(1.0f - Math.Abs(h - 0.5f) * 5.0f, 0.0f, 1.0f);
				float rock = Math.Clamp((h - 0.6f) * 5.0f, 0.0f, 1.0f);
				float sand = Math.Clamp(1.0f - (h - 0.2f) * 8.0f, 0.0f, 1.0f); // Sand near water level

				float total = grass + dirt + rock + sand;
				if (total > 0.001f)
				{
					grass /= total; dirt /= total; rock /= total; sand /= total;
				}
				else
				{
					grass = 1.0f;
				}

				int32 idx = (y * HeightmapSize + x) * 4;
				pixels[idx + 0] = (uint8)(grass * 255.0f);
				pixels[idx + 1] = (uint8)(dirt * 255.0f);
				pixels[idx + 2] = (uint8)(rock * 255.0f);
				pixels[idx + 3] = (uint8)(sand * 255.0f);
			}
		}

		TextureDataLayout layout = .() { BytesPerRow = (uint32)(HeightmapSize * 4), RowsPerImage = (uint32)HeightmapSize };
		Extent3D size = .((uint32)HeightmapSize, (uint32)HeightmapSize, 1);
		TransferHelper.WriteTextureSync(mDevice.GetQueue(.Graphics), mDevice, mSplatmapTexture, Span<uint8>(pixels.Ptr, HeightmapSize * HeightmapSize * 4), layout, size);

		TextureViewDesc viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D };
		if (mDevice.CreateTextureView(mSplatmapTexture, viewDesc) case .Ok(let view))
			mSplatmapView = view;
	}

	private void GenerateLayerTextures()
	{
		Color[4] colors = .(
			.(76, 153, 51, 255),    // Green (grass)
			.(140, 100, 60, 255),   // Brown (dirt)
			.(128, 128, 128, 255),  // Gray (rock)
			.(194, 178, 128, 255)   // Sandy (beach)
		);

		for (int32 i = 0; i < 4; i++)
		{
			TextureDesc desc = .()
			{
				Label = "Terrain Layer",
				Width = 4, Height = 4, Depth = 1,
				Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
				SampleCount = 1, Dimension = .Texture2D,
				Usage = .Sampled | .CopyDst
			};

			switch (mDevice.CreateTexture(desc))
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
			TransferHelper.WriteTextureSync(mDevice.GetQueue(.Graphics), mDevice, mLayerTextures[i], Span<uint8>(&pixels[0], 64), layout, size);

			TextureViewDesc viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D };
			if (mDevice.CreateTextureView(mLayerTextures[i], viewDesc) case .Ok(let view))
				mLayerViews[i] = view;
		}
	}

	// ===========================================================
	// Water Texture Generation
	// ===========================================================

	private void GenerateWaterTextures()
	{
		GenerateWaterNormalMap();
		GenerateFoamTexture();
		Console.WriteLine("Generated water textures");
	}

	private void GenerateWaterNormalMap()
	{
		// Procedural tileable wave normal + height map (RGBA8Unorm)
		// RG: normal XY (encoded 0-1), B: normal Z, A: height
		TextureDesc desc = .()
		{
			Label = "Water Normal Map",
			Width = WaterNormalMapSize, Height = WaterNormalMapSize, Depth = 1,
			Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(desc))
		{
		case .Ok(let tex): mWaterNormalTexture = tex;
		case .Err: Console.WriteLine("ERROR: Failed to create water normal map"); return;
		}

		uint8[] pixels = new uint8[WaterNormalMapSize * WaterNormalMapSize * 4];
		defer delete pixels;

		for (int32 y = 0; y < WaterNormalMapSize; y++)
		{
			for (int32 x = 0; x < WaterNormalMapSize; x++)
			{
				float fx = (float)x / (float)WaterNormalMapSize;
				float fy = (float)y / (float)WaterNormalMapSize;

				// Layered sine waves for tileable pattern (period = 1.0 in UV)
				float h = 0.0f;
				h += Math.Sin(fx * 2.0f * Math.PI_f * 3.0f) * Math.Cos(fy * 2.0f * Math.PI_f * 2.0f) * 0.3f;
				h += Math.Sin(fx * 2.0f * Math.PI_f * 7.0f + 1.3f) * Math.Sin(fy * 2.0f * Math.PI_f * 5.0f + 0.7f) * 0.15f;
				h += Math.Cos((fx + fy) * 2.0f * Math.PI_f * 4.0f) * 0.2f;
				h += Math.Sin(fx * 2.0f * Math.PI_f * 11.0f + 2.1f) * Math.Cos(fy * 2.0f * Math.PI_f * 9.0f + 1.5f) * 0.08f;
				h = h * 0.5f + 0.5f; // Normalize to [0,1]

				// Compute normal from finite differences of this height
				float eps = 1.0f / (float)WaterNormalMapSize;
				float fx1 = fx + eps;
				float fy1 = fy + eps;

				float hx = 0.0f;
				hx += Math.Sin(fx1 * 2.0f * Math.PI_f * 3.0f) * Math.Cos(fy * 2.0f * Math.PI_f * 2.0f) * 0.3f;
				hx += Math.Sin(fx1 * 2.0f * Math.PI_f * 7.0f + 1.3f) * Math.Sin(fy * 2.0f * Math.PI_f * 5.0f + 0.7f) * 0.15f;
				hx += Math.Cos((fx1 + fy) * 2.0f * Math.PI_f * 4.0f) * 0.2f;
				hx += Math.Sin(fx1 * 2.0f * Math.PI_f * 11.0f + 2.1f) * Math.Cos(fy * 2.0f * Math.PI_f * 9.0f + 1.5f) * 0.08f;
				hx = hx * 0.5f + 0.5f;

				float hy = 0.0f;
				hy += Math.Sin(fx * 2.0f * Math.PI_f * 3.0f) * Math.Cos(fy1 * 2.0f * Math.PI_f * 2.0f) * 0.3f;
				hy += Math.Sin(fx * 2.0f * Math.PI_f * 7.0f + 1.3f) * Math.Sin(fy1 * 2.0f * Math.PI_f * 5.0f + 0.7f) * 0.15f;
				hy += Math.Cos((fx + fy1) * 2.0f * Math.PI_f * 4.0f) * 0.2f;
				hy += Math.Sin(fx * 2.0f * Math.PI_f * 11.0f + 2.1f) * Math.Cos(fy1 * 2.0f * Math.PI_f * 9.0f + 1.5f) * 0.08f;
				hy = hy * 0.5f + 0.5f;

				float dx = (hx - h) / eps;
				float dy = (hy - h) / eps;
				Vector3 normal = Vector3.Normalize(.(-dx * 0.5f, 1.0f, -dy * 0.5f));

				int32 idx = (y * WaterNormalMapSize + x) * 4;
				pixels[idx + 0] = (uint8)(Math.Clamp(normal.X * 0.5f + 0.5f, 0.0f, 1.0f) * 255.0f);
				pixels[idx + 1] = (uint8)(Math.Clamp(normal.Y * 0.5f + 0.5f, 0.0f, 1.0f) * 255.0f);
				pixels[idx + 2] = (uint8)(Math.Clamp(normal.Z * 0.5f + 0.5f, 0.0f, 1.0f) * 255.0f);
				pixels[idx + 3] = (uint8)(Math.Clamp(h, 0.0f, 1.0f) * 255.0f); // Height in alpha
			}
		}

		TextureDataLayout layout = .() { BytesPerRow = (uint32)(WaterNormalMapSize * 4), RowsPerImage = (uint32)WaterNormalMapSize };
		Extent3D size = .((uint32)WaterNormalMapSize, (uint32)WaterNormalMapSize, 1);
		TransferHelper.WriteTextureSync(mDevice.GetQueue(.Graphics), mDevice, mWaterNormalTexture, Span<uint8>(pixels.Ptr, WaterNormalMapSize * WaterNormalMapSize * 4), layout, size);

		TextureViewDesc viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D };
		if (mDevice.CreateTextureView(mWaterNormalTexture, viewDesc) case .Ok(let view))
			mWaterNormalView = view;
	}

	private void GenerateFoamTexture()
	{
		// Simple procedural foam texture (R8Unorm)
		const int32 foamSize = 256;

		TextureDesc desc = .()
		{
			Label = "Foam Texture",
			Width = foamSize, Height = foamSize, Depth = 1,
			Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(desc))
		{
		case .Ok(let tex): mFoamTexture = tex;
		case .Err: return;
		}

		uint8[] pixels = new uint8[foamSize * foamSize * 4];
		defer delete pixels;

		// Simple hash-based noise for foam
		for (int32 y = 0; y < foamSize; y++)
		{
			for (int32 x = 0; x < foamSize; x++)
			{
				float fx = (float)x / (float)foamSize;
				float fy = (float)y / (float)foamSize;

				// Multi-octave noise approximation
				float n = 0.0f;
				n += (Math.Sin(fx * 2.0f * Math.PI_f * 13.0f + 3.7f) * Math.Sin(fy * 2.0f * Math.PI_f * 17.0f + 1.2f)) * 0.5f + 0.5f;
				n += (Math.Cos(fx * 2.0f * Math.PI_f * 23.0f + 0.5f) * Math.Cos(fy * 2.0f * Math.PI_f * 19.0f + 2.8f)) * 0.25f + 0.25f;
				n = Math.Clamp(n * 0.7f, 0.0f, 1.0f);

				// Threshold for foam-like pattern
				float foam = n > 0.45f ? Math.Clamp((n - 0.45f) * 5.0f, 0.0f, 1.0f) : 0.0f;

				uint8 v = (uint8)(foam * 255.0f);
				int32 idx = (y * foamSize + x) * 4;
				pixels[idx + 0] = v;
				pixels[idx + 1] = v;
				pixels[idx + 2] = v;
				pixels[idx + 3] = 255;
			}
		}

		TextureDataLayout layout = .() { BytesPerRow = (uint32)(foamSize * 4), RowsPerImage = (uint32)foamSize };
		Extent3D size = .((uint32)foamSize, (uint32)foamSize, 1);
		TransferHelper.WriteTextureSync(mDevice.GetQueue(.Graphics), mDevice, mFoamTexture, Span<uint8>(pixels.Ptr, foamSize * foamSize * 4), layout, size);

		TextureViewDesc viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D };
		if (mDevice.CreateTextureView(mFoamTexture, viewDesc) case .Ok(let view))
			mFoamView = view;
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
		Console.WriteLine("Created terrain: 256x256 world units, 8x8 patches");
	}

	private void CreateWater()
	{
		mWaterHandle = mWorld.CreateWater();
		if (let water = mWorld.GetWater(mWaterHandle))
		{
			water.Position = .(128, mWaterLevel, 128);  // Center of terrain
			water.Size = .(256, 256);
			water.WaterColor = .(0.0f, 0.08f, 0.15f, 1.0f);
			water.WaveSpeed = 0.8f;
			water.WaveScale = 6.0f;
			water.NormalStrength = 0.4f;
			water.FresnelR0 = 0.02f;
			water.RefractionStrength = 0.025f;
			water.SpecularPower = 256.0f;
			water.MaxVisibleDepth = 8.0f;
			water.FoamDepthThreshold = 0.8f;
			water.FoamIntensity = 0.7f;
			water.Roughness = 0.08f;
			water.FlowDirection = Vector2.Normalize(.(1.0f, 0.3f));
			water.NormalMapView = mWaterNormalView;
			water.FoamTextureView = mFoamView;
			water.WorldBounds = .(.(0, mWaterLevel - 1, 0), .(256, mWaterLevel + 1, 256));
		}

		mWorld.MarkWatersDirty();
		Console.WriteLine("Created water plane at y={}", mWaterLevel);
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

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		// Toggle GUI
		if (keyboard.IsKeyPressed(.F1))
		{
			mShowGUI = !mShowGUI;
			if (mUISubsystem?.GUIContext?.RootElement != null)
				mUISubsystem.GUIContext.RootElement.Visibility = mShowGUI ? .Visible : .Collapsed;
		}

		// Camera controls — only when GUI doesn't want mouse
		bool guiWantsMouse = mShowGUI && mUISubsystem != null && mUISubsystem.UIConsumedInput;

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

		// Water level keyboard adjustment (always works)
		float waterSpeed = 5.0f * mDeltaTime;
		if (keyboard.IsKeyDown(.Equals))
		{
			mWaterLevel += waterSpeed;
			UpdateWaterLevel();
			if (mWaterLevelSlider != null)
				mWaterLevelSlider.Value = mWaterLevel;
		}
		if (keyboard.IsKeyDown(.Minus))
		{
			mWaterLevel = Math.Max(0.0f, mWaterLevel - waterSpeed);
			UpdateWaterLevel();
			if (mWaterLevelSlider != null)
				mWaterLevelSlider.Value = mWaterLevel;
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
	}

	private void UpdateWaterLevel()
	{
		if (let water = mWorld.GetWater(mWaterHandle))
		{
			water.Position = .(128, mWaterLevel, 128);
			water.WorldBounds = .(.(0, mWaterLevel - 1, 0), .(256, mWaterLevel + 1, 256));
		}
		mWorld.MarkWatersDirty();
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
		if (mShowGUI)
			mUISubsystem?.Render(render.Encoder, render.SwapChain.CurrentTextureView,
				render.SwapChain.Width, render.SwapChain.Height,
				(int32)render.SwapChain.CurrentImageIndex);

		return true;
	}

	protected override void OnResize(int32 width, int32 height)
	{
		if (mView != null)
		{
			mView.Width = (uint32)width;
			mView.Height = (uint32)height;
		}
		mRenderSystem?.SetViewportSize((uint32)width, (uint32)height);
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

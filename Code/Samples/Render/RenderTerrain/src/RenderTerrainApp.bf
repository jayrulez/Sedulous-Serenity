using Sedulous.Core.Mathematics;
using Sedulous.Runtime.Client;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using System;

namespace RenderTerrain;

/// Terrain rendering sample.
/// Demonstrates heightmap-based terrain with splatmap texture blending,
/// full PBR lighting, shadows, IBL, and reflection probes.
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
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Terrain proxy
	private TerrainProxyHandle mTerrainHandle = .Invalid;

	// Terrain textures (cleaned up in OnShutdown)
	private ITexture mHeightmapTexture;
	private ITextureView mHeightmapView;
	private ITexture mNormalMapTexture;
	private ITextureView mNormalMapView;
	private ITexture mSplatmapTexture;
	private ITextureView mSplatmapView;
	private ITexture[4] mLayerTextures;
	private ITextureView[4] mLayerViews;

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

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnShutdown()
	{
		mWorld?.Dispose();
		mRenderSystem?.Shutdown();

		// Delete views before textures
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
		Console.WriteLine("=== Terrain Rendering Sample ===\n");

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

		Console.WriteLine("\nControls:");
		Console.WriteLine("  WASD: orbit camera");
		Console.WriteLine("  Q/E: zoom in/out");
		Console.WriteLine("  +/-: adjust height scale");
		Console.WriteLine("  ESC: exit\n");
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

		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");

		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");

		Console.WriteLine("Registered terrain rendering features");
	}

	private void GenerateTerrainTextures()
	{
		// Heightmap: R16Float, 512x512
		GenerateHeightmap();

		// Normal map: RGBA8Unorm, 512x512
		GenerateNormalMap();

		// Splatmap: RGBA8Unorm, 512x512
		GenerateSplatmap();

		// Layer textures: 4x4 solid colors
		GenerateLayerTextures();

		Console.WriteLine("Generated terrain textures");
	}

	private void GenerateHeightmap()
	{
		TextureDescriptor desc = .()
		{
			Label = "Terrain Heightmap",
			Width = HeightmapSize,
			Height = HeightmapSize,
			Depth = 1,
			Format = .R16Float,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex): mHeightmapTexture = tex;
		case .Err:
			Console.WriteLine("ERROR: Failed to create heightmap");
			return;
		}

		// Generate rolling hills via layered sine waves
		uint16[] pixels = new uint16[HeightmapSize * HeightmapSize];
		defer delete pixels;

		for (int32 y = 0; y < HeightmapSize; y++)
		{
			for (int32 x = 0; x < HeightmapSize; x++)
			{
				float fx = (float)x / (float)HeightmapSize;
				float fy = (float)y / (float)HeightmapSize;

				float h = 0.0f;
				h += Math.Sin(fx * 3.0f * Math.PI_f) * 0.3f;
				h += Math.Sin(fy * 2.5f * Math.PI_f) * 0.25f;
				h += Math.Sin((fx + fy) * 5.0f * Math.PI_f) * 0.15f;
				h += Math.Sin(fx * 8.0f * Math.PI_f) * Math.Cos(fy * 6.0f * Math.PI_f) * 0.1f;
				h += Math.Sin(fx * 13.0f * Math.PI_f + 1.7f) * Math.Sin(fy * 11.0f * Math.PI_f + 0.3f) * 0.05f;
				h = (h + 0.85f) * 0.5f; // Normalize to ~[0,1]
				h = Math.Clamp(h, 0.0f, 1.0f);

				// Convert to half-float
				pixels[y * HeightmapSize + x] = FloatToHalf(h);
			}
		}

		TextureDataLayout layout = .() { BytesPerRow = (uint32)(HeightmapSize * 2), RowsPerImage = (uint32)HeightmapSize };
		Extent3D size = .((uint32)HeightmapSize, (uint32)HeightmapSize, 1);
		mDevice.Queue.WriteTextureSync(mHeightmapTexture, Span<uint8>((uint8*)pixels.Ptr, HeightmapSize * HeightmapSize * 2), &layout, &size);

		TextureViewDescriptor viewDesc = .()
		{
			Format = .R16Float,
			Dimension = .Texture2D
		};
		if (mDevice.CreateTextureView(mHeightmapTexture, &viewDesc) case .Ok(let view))
			mHeightmapView = view;
	}

	private void GenerateNormalMap()
	{
		TextureDescriptor desc = .()
		{
			Label = "Terrain Normal Map",
			Width = HeightmapSize,
			Height = HeightmapSize,
			Depth = 1,
			Format = .RGBA8Unorm,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex): mNormalMapTexture = tex;
		case .Err: return;
		}

		// Compute normals from heightmap using central differences
		// First, regenerate heights in float for computation
		float[] heights = new float[HeightmapSize * HeightmapSize];
		defer delete heights;

		for (int32 y = 0; y < HeightmapSize; y++)
		{
			for (int32 x = 0; x < HeightmapSize; x++)
			{
				float fx = (float)x / (float)HeightmapSize;
				float fy = (float)y / (float)HeightmapSize;

				float h = 0.0f;
				h += Math.Sin(fx * 3.0f * Math.PI_f) * 0.3f;
				h += Math.Sin(fy * 2.5f * Math.PI_f) * 0.25f;
				h += Math.Sin((fx + fy) * 5.0f * Math.PI_f) * 0.15f;
				h += Math.Sin(fx * 8.0f * Math.PI_f) * Math.Cos(fy * 6.0f * Math.PI_f) * 0.1f;
				h += Math.Sin(fx * 13.0f * Math.PI_f + 1.7f) * Math.Sin(fy * 11.0f * Math.PI_f + 0.3f) * 0.05f;
				h = (h + 0.85f) * 0.5f;
				h = Math.Clamp(h, 0.0f, 1.0f);
				heights[y * HeightmapSize + x] = h * mHeightScale;
			}
		}

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

				// Central differences
				float dx = (hR - hL) / (2.0f * worldSizePerTexel);
				float dz = (hU - hD) / (2.0f * worldSizePerTexel);

				Vector3 normal = Vector3.Normalize(.(-dx, 1.0f, -dz));

				// Encode to [0,1]
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

		TextureViewDescriptor viewDesc = .()
		{
			Format = .RGBA8Unorm,
			Dimension = .Texture2D
		};
		if (mDevice.CreateTextureView(mNormalMapTexture, &viewDesc) case .Ok(let view))
			mNormalMapView = view;
	}

	private void GenerateSplatmap()
	{
		TextureDescriptor desc = .()
		{
			Label = "Terrain Splatmap",
			Width = HeightmapSize,
			Height = HeightmapSize,
			Depth = 1,
			Format = .RGBA8Unorm,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex): mSplatmapTexture = tex;
		case .Err: return;
		}

		// Height-based splatting:
		// R = green (low grass)
		// G = brown (mid-height dirt/rock)
		// B = gray (steep slopes)
		// A = white (high snow)
		uint8[] pixels = new uint8[HeightmapSize * HeightmapSize * 4];
		defer delete pixels;

		// Regenerate heights for splatmap computation
		float[] heights = new float[HeightmapSize * HeightmapSize];
		defer delete heights;

		for (int32 y = 0; y < HeightmapSize; y++)
		{
			for (int32 x = 0; x < HeightmapSize; x++)
			{
				float fx = (float)x / (float)HeightmapSize;
				float fy = (float)y / (float)HeightmapSize;

				float h = 0.0f;
				h += Math.Sin(fx * 3.0f * Math.PI_f) * 0.3f;
				h += Math.Sin(fy * 2.5f * Math.PI_f) * 0.25f;
				h += Math.Sin((fx + fy) * 5.0f * Math.PI_f) * 0.15f;
				h += Math.Sin(fx * 8.0f * Math.PI_f) * Math.Cos(fy * 6.0f * Math.PI_f) * 0.1f;
				h += Math.Sin(fx * 13.0f * Math.PI_f + 1.7f) * Math.Sin(fy * 11.0f * Math.PI_f + 0.3f) * 0.05f;
				h = (h + 0.85f) * 0.5f;
				heights[y * HeightmapSize + x] = Math.Clamp(h, 0.0f, 1.0f);
			}
		}

		float worldSizePerTexel = 256.0f / (float)HeightmapSize;

		for (int32 y = 0; y < HeightmapSize; y++)
		{
			for (int32 x = 0; x < HeightmapSize; x++)
			{
				float h = heights[y * HeightmapSize + x];

				// Compute slope
				let x0 = Math.Max(x - 1, 0);
				let x1 = Math.Min(x + 1, HeightmapSize - 1);
				let y0 = Math.Max(y - 1, 0);
				let y1 = Math.Min(y + 1, HeightmapSize - 1);

				float hL = heights[y * HeightmapSize + x0];
				float hR = heights[y * HeightmapSize + x1];
				float hD = heights[y0 * HeightmapSize + x];
				float hU = heights[y1 * HeightmapSize + x];

				float dx = (hR - hL) * mHeightScale / (2.0f * worldSizePerTexel);
				float dz = (hU - hD) * mHeightScale / (2.0f * worldSizePerTexel);
				float slope = Math.Sqrt(dx * dx + dz * dz);

				// Blend weights
				float grass = 0, dirt = 0, rock = 0, snow = 0;

				// Low areas: grass
				grass = Math.Clamp(1.0f - (h - 0.3f) * 4.0f, 0.0f, 1.0f);

				// Mid areas: dirt
				dirt = Math.Clamp(1.0f - Math.Abs(h - 0.5f) * 5.0f, 0.0f, 1.0f);

				// High areas: snow
				snow = Math.Clamp((h - 0.7f) * 5.0f, 0.0f, 1.0f);

				// Steep areas: rock
				rock = Math.Clamp((slope - 0.5f) * 2.0f, 0.0f, 1.0f);

				// Rock overrides other layers on steep slopes
				float rockBlend = rock;
				grass *= (1.0f - rockBlend);
				dirt *= (1.0f - rockBlend);
				snow *= (1.0f - rockBlend * 0.5f);

				// Normalize
				float total = grass + dirt + rock + snow;
				if (total > 0.001f)
				{
					grass /= total;
					dirt /= total;
					rock /= total;
					snow /= total;
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

		TextureViewDescriptor viewDesc = .()
		{
			Format = .RGBA8Unorm,
			Dimension = .Texture2D
		};
		if (mDevice.CreateTextureView(mSplatmapTexture, &viewDesc) case .Ok(let view))
			mSplatmapView = view;
	}

	private void GenerateLayerTextures()
	{
		// Create 4x4 solid-color textures for each terrain layer
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
				Width = 4,
				Height = 4,
				Depth = 1,
				Format = .RGBA8Unorm,
				MipLevelCount = 1,
				ArrayLayerCount = 1,
				SampleCount = 1,
				Dimension = .Texture2D,
				Usage = .Sampled | .CopyDst
			};

			switch (mDevice.CreateTexture(&desc))
			{
			case .Ok(let tex): mLayerTextures[i] = tex;
			case .Err: continue;
			}

			// Fill 4x4 with solid color
			uint8[64] pixels = default; // 4*4*4 bytes
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

			TextureViewDescriptor viewDesc = .()
			{
				Format = .RGBA8Unorm,
				Dimension = .Texture2D
			};
			if (mDevice.CreateTextureView(mLayerTextures[i], &viewDesc) case .Ok(let view))
				mLayerViews[i] = view;
		}
	}

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

	private void CreateLights()
	{
		// Sun directional light
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(0.5f, -0.8f, 0.3f)),
			.(1.0f, 0.95f, 0.85f),
			3.0f);

		if (let light = mWorld.GetLight(mSunLight))
		{
			light.CastsShadows = true;
		}

		Console.WriteLine("Created directional sun light with shadows");
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;

		float rotSpeed = 1.5f * mDeltaTime;
		float zoomSpeed = 60.0f * mDeltaTime;
		float heightSpeed = 10.0f * mDeltaTime;

		if (keyboard.IsKeyDown(.W)) mOrbitalPitch += rotSpeed;
		if (keyboard.IsKeyDown(.S)) mOrbitalPitch -= rotSpeed;
		if (keyboard.IsKeyDown(.A)) mOrbitalYaw -= rotSpeed;
		if (keyboard.IsKeyDown(.D)) mOrbitalYaw += rotSpeed;
		if (keyboard.IsKeyDown(.Q)) mOrbitalDistance -= zoomSpeed;
		if (keyboard.IsKeyDown(.E)) mOrbitalDistance += zoomSpeed;

		// Height scale adjustment
		if (keyboard.IsKeyDown(.Equals))
		{
			mHeightScale += heightSpeed;
			UpdateHeightScale();
		}
		if (keyboard.IsKeyDown(.Minus))
		{
			mHeightScale = Math.Max(1.0f, mHeightScale - heightSpeed);
			UpdateHeightScale();
		}

		// Escape
		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		// Clamp
		mOrbitalPitch = Math.Clamp(mOrbitalPitch, 0.1f, 1.4f);
		mOrbitalDistance = Math.Clamp(mOrbitalDistance, 20.0f, 400.0f);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		mDeltaTime = (float)frame.DeltaTime;
		UpdateCamera();
	}

	private void UpdateHeightScale()
	{
		if (let terrain = mWorld.GetTerrain(mTerrainHandle))
		{
			terrain.HeightScale = mHeightScale;
			terrain.WorldBounds = .(.(0, 0, 0), .(256, mHeightScale, 256));
		}
		mWorld.MarkTerrainsDirty();
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

		// Update view size
		mView.Width = render.SwapChain.Width;
		mView.Height = render.SwapChain.Height;

		// Begin frame
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		// Set swap chain for final output
		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		// Update camera in render system
		let camPos = mView.CameraPosition;
		let camFwd = mView.CameraForward;
		mRenderSystem.SetCamera(
			camPos, camFwd, Vector3.Up,
			mView.FieldOfView, mView.AspectRatio,
			mView.NearPlane, mView.FarPlane,
			mView.Width, mView.Height);

		// Build and execute render graph
		if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
		{
			mRenderSystem.Execute(render.Encoder);
		}

		// End frame
		mRenderSystem.EndFrame();

		return true;
	}

	protected override void OnResize(int32 width, int32 height)
	{
		if (mView != null)
		{
			mView.Width = (uint32)width;
			mView.Height = (uint32)height;
		}
	}

	/// Convert float to IEEE 754 half-precision.
	private static uint16 FloatToHalf(float value)
	{
		// Simple conversion via bit manipulation
		float val = value;
		uint32 f = *(uint32*)&val;
		uint32 sign = (f >> 16) & 0x8000;
		int32 exponent = (int32)((f >> 23) & 0xFF) - 127;
		uint32 mantissa = f & 0x7FFFFF;

		if (exponent > 15)
			return (uint16)(sign | 0x7C00); // Infinity
		if (exponent < -14)
			return (uint16)sign; // Zero (denormals flush to zero)

		uint16 halfExp = (uint16)((exponent + 15) << 10);
		uint16 halfMant = (uint16)(mantissa >> 13);

		return (uint16)(sign | halfExp | halfMant);
	}
}

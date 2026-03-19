namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// Sky rendering mode.
[Reflect]
public enum SkyMode
{
	/// Procedural sky using Preetham/Hosek model.
	Procedural,
	/// HDRI environment map.
	EnvironmentMap,
	/// Solid color.
	SolidColor
}

/// Sky parameters for procedural sky.
/// Must match SkyUniforms in sky.frag.hlsl
[CRepr]
public struct ProceduralSkyParams
{
	/// Sun direction (normalized).
	public Vector3 SunDirection;
	/// Sun intensity multiplier.
	public float SunIntensity;

	/// Sun color.
	public Vector3 SunColor;
	/// Atmosphere density multiplier.
	public float AtmosphereDensity;

	/// Ground color (for below horizon).
	public Vector3 GroundColor;
	/// Exposure value for tone mapping.
	public float Exposure;

	/// Zenith (top of sky) color tint.
	public Vector3 ZenithColor;
	/// Cloud coverage (0-1, for future use).
	public float CloudCoverage;

	/// Horizon color tint.
	public Vector3 HorizonColor;
	/// Time (for animated effects).
	public float Time;

	/// Solid color (used when Mode is SolidColor).
	public Vector3 SolidColor;
	/// Sky mode (0 = Procedural, 1 = SolidColor).
	public float Mode;

	/// Default values.
	public static Self Default => .()
	{
		SunDirection = Vector3.Normalize(.(-0.5f, 0.8f, 0.3f)),
		SunIntensity = 20.0f,
		SunColor = .(1.0f, 0.95f, 0.9f),
		AtmosphereDensity = 1.0f,
		GroundColor = .(0.3f, 0.25f, 0.2f),
		Exposure = 1.0f,
		ZenithColor = .(0.3f, 0.5f, 0.85f),
		CloudCoverage = 0.0f,
		HorizonColor = .(0.8f, 0.85f, 0.9f),
		Time = 0.0f,
		SolidColor = .(0.529f, 0.808f, 0.922f), // Sky blue default
		Mode = 0.0f
	};

	/// Size in bytes (must be 96 bytes: 6 float4s).
	public static int Size => 96;
}

/// Sky and atmosphere render feature.
public class SkyFeature : RenderFeatureBase
{
	// Sky mode
	private SkyMode mMode = .Procedural;
	private ProceduralSkyParams mSkyParams = .Default;

	// Environment map
	private ITexture mEnvironmentMap;
	private ITextureView mEnvironmentMapView;
	private bool mOwnsEnvironmentMap = false;
	private ITexture mIrradianceMap;
	private ITextureView mIrradianceMapView;
	private ITexture mPrefilteredMap;
	private ITextureView mPrefilteredMapView;
	private ITexture mBRDFLut;
	private ITextureView mBRDFLutView;

	// Flag: true if environment map was set externally (HDRI), false if generated from colors
	private bool mIsExternalEnvMap = false;

	// Incremented whenever IBL views change, so consumers can detect stale bind groups
	private uint32 mIBLGeneration = 0;

	// Cubemap sampler and fallback
	private ISampler mEnvSampler ~ delete _;
	private ITexture mFallbackCubemap ~ delete _;
	private ITextureView mFallbackCubemapView ~ delete _;

	// Sky rendering (per-frame for multi-buffering)
	private IRenderPipeline mSkyPipeline ~ delete _;
	private IBuffer[RenderConfig.FrameBufferCount] mSkyParamsBuffers;
	private IBindGroupLayout mSkyBindGroupLayout ~ delete _;
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSkyBindGroups;

	// Full-screen quad mesh (kept for potential future use, shader uses SV_VertexID)
	private IBuffer mFullscreenQuadVB ~ delete _;

	// GPU IBL compute pipelines (lazily created on first HDRI use)
	private IComputePipeline mEquirectToCubemapPipeline;
	private IComputePipeline mIBLIrradiancePipeline;
	private IComputePipeline mIBLPrefilterPipeline;
	private IBindGroupLayout mEquirectBindGroupLayout;
	private IBindGroupLayout mIBLConvolveBindGroupLayout;
	private IPipelineLayout mEquirectPipelineLayout;
	private IPipelineLayout mIBLConvolvePipelineLayout;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => Renderer.RenderFrameContext?.FrameIndex ?? 0;

	/// Gets the bind group index accounting for the active view.
	private int32 GetBindGroupIndex(int32 frameIndex) => frameIndex * RenderConfig.MaxViews + (Renderer.RenderFrameContext?.ActiveViewIndex ?? 0);

	/// Feature name.
	public override StringView Name => "Sky";

	/// Sky renders after opaque but BEFORE transparent (at depth = 1.0).
	/// Transparent objects render on top of the sky.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
	}

	/// Gets or sets the sky mode.
	public SkyMode Mode
	{
		get => mMode;
		set => mMode = value;
	}

	/// Gets or sets the solid color (used when Mode is SolidColor).
	public Vector3 SolidColor
	{
		get => mSkyParams.SolidColor;
		set => mSkyParams.SolidColor = value;
	}

	/// Gets or sets the procedural sky parameters.
	public ref ProceduralSkyParams SkyParams => ref mSkyParams;

	/// Gets the environment map view for IBL.
	public ITextureView EnvironmentMapView => mEnvironmentMapView;

	/// Gets the irradiance map view for IBL.
	public ITextureView IrradianceMapView => mIrradianceMapView;

	/// Gets the prefiltered environment map for IBL.
	public ITextureView PrefilteredMapView => mPrefilteredMapView;

	/// Gets the BRDF LUT for IBL.
	public ITextureView BRDFLutView => mBRDFLutView;

	/// Gets the environment sampler for cubemap sampling.
	public ISampler EnvironmentSampler => mEnvSampler;

	/// Gets the IBL generation counter. Incremented whenever IBL views change.
	public uint32 IBLGeneration => mIBLGeneration;

	protected override Result<void> OnInitialize()
	{
		// Create sky params buffer
		if (CreateSkyParamsBuffer() case .Err)
			return .Err;

		// Create fullscreen quad
		if (CreateFullscreenQuad() case .Err)
			return .Err;

		// Create BRDF LUT
		if (CreateBRDFLut() case .Err)
			return .Err;

		// Create env sampler and fallback cubemap
		if (CreateEnvSamplerAndFallback() case .Err)
			return .Err;

		// Create sky pipeline
		if (CreateSkyPipeline() case .Err)
			return .Err;

		// Generate IBL maps from default sky parameters
		GenerateIBLMaps();

		return .Ok;
	}

	private IPipelineLayout mSkyPipelineLayout ~ delete _;

	private Result<void> CreateSkyPipeline()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Load sky shaders
		let shaderResult = Renderer.ShaderSystem.GetShaderPair("sky");
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		// Create bind group layout
		// Binding indices match HLSL register indices per type: b0, b1, t0, s0
		BindGroupLayoutEntry[4] layoutEntries = .(
			.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer }, // Camera (b0)
			.() { Binding = 1, Visibility = .Fragment, Type = .UniformBuffer }, // Sky params (b1)
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .TextureCube), // Environment cubemap (t0)
			BindGroupLayoutEntry.Sampler(0, .Fragment) // Cubemap sampler (s0)
		);

		BindGroupLayoutDesc layoutDesc = .()
		{
			Label = "Sky BindGroup Layout",
			Entries = layoutEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mSkyBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] bgLayouts = .(mSkyBindGroupLayout);
		PipelineLayoutDesc plDesc = .(bgLayouts);
		switch (Renderer.Device.CreatePipelineLayout(plDesc))
		{
		case .Ok(let layout): mSkyPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Color targets
		ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

		// Sky uses fullscreen triangle with SV_VertexID - no vertex buffers needed
		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "Sky Pipeline",
			Layout = mSkyPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = default // No vertex buffers - SV_VertexID
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = .Skybox,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(pipelineDesc))
		{
		case .Ok(let pipeline): mSkyPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
		// Clean up per-frame resources
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mSkyParamsBuffers[i] != null)
			{
				delete mSkyParamsBuffers[i];
				mSkyParamsBuffers[i] = null;
			}
		}

		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mSkyBindGroups[i] != null)
			{
				delete mSkyBindGroups[i];
				mSkyBindGroups[i] = null;
			}
		}

		if (mOwnsEnvironmentMap)
		{
			if (mEnvironmentMapView != null) delete mEnvironmentMapView;
			if (mEnvironmentMap != null) delete mEnvironmentMap;
		}
		if (mIrradianceMapView != null) delete mIrradianceMapView;
		if (mIrradianceMap != null) delete mIrradianceMap;
		if (mPrefilteredMapView != null) delete mPrefilteredMapView;
		if (mPrefilteredMap != null) delete mPrefilteredMap;
		if (mBRDFLutView != null) delete mBRDFLutView;
		if (mBRDFLut != null) delete mBRDFLut;

		// Clean up GPU IBL compute pipelines
		if (mEquirectToCubemapPipeline != null) delete mEquirectToCubemapPipeline;
		if (mIBLIrradiancePipeline != null) delete mIBLIrradiancePipeline;
		if (mIBLPrefilterPipeline != null) delete mIBLPrefilterPipeline;
		if (mEquirectBindGroupLayout != null) delete mEquirectBindGroupLayout;
		if (mIBLConvolveBindGroupLayout != null) delete mIBLConvolveBindGroupLayout;
		if (mEquirectPipelineLayout != null) delete mEquirectPipelineLayout;
		if (mIBLConvolvePipelineLayout != null) delete mIBLConvolvePipelineLayout;
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		// Get existing resources
		let colorHandle = graph.GetResource("SceneColor");
		let depthHandle = graph.GetResource("SceneDepth");

		if (!colorHandle.IsValid || !depthHandle.IsValid)
			return;

		// Capture frame index for consistent multi-buffering
		let frameIndex = FrameIndex;

		// Upload sky params
		UpdateSkyParams(frameIndex);

		// Add sky rendering pass
		// Note: Must be NeverCull because render graph culling only preserves FirstWriter,
		// and ForwardOpaque is the first writer of SceneColor
		graph.AddGraphicsPass("Sky")
			.WriteColor(colorHandle, .Load, .Store) // Blend sky into existing color
			.ReadDepth(depthHandle) // Use depth for sky masking
			.NeverCull() // Don't cull - sky renders in background
			.SetExecuteCallback(new (encoder) => {
				ExecuteSkyPass(encoder, view, frameIndex);
			});
	}

	/// Sets an HDRI environment map.
	public Result<void> SetEnvironmentMap(ITexture envMap)
	{
		// Flush GPU and invalidate bind groups before destroying views
		FlushAndInvalidateBindGroups();

		// Release old maps
		if (mOwnsEnvironmentMap)
		{
			if (mEnvironmentMapView != null) { delete mEnvironmentMapView; mEnvironmentMapView = null; }
			if (mEnvironmentMap != null) { delete mEnvironmentMap; mEnvironmentMap = null; }
		}
		mOwnsEnvironmentMap = false;
		if (mIrradianceMapView != null) { delete mIrradianceMapView; mIrradianceMapView = null; }
		if (mIrradianceMap != null) { delete mIrradianceMap; mIrradianceMap = null; }
		if (mPrefilteredMapView != null) { delete mPrefilteredMapView; mPrefilteredMapView = null; }
		if (mPrefilteredMap != null) { delete mPrefilteredMap; mPrefilteredMap = null; }

		mEnvironmentMap = envMap;

		// Create view
		TextureViewDesc viewDesc = .()
		{
			Label = "Environment Map View",
			Dimension = .TextureCube
		};

		switch (Renderer.Device.CreateTextureView(mEnvironmentMap, viewDesc))
		{
		case .Ok(let view): mEnvironmentMapView = view;
		case .Err: return .Err;
		}

		mIsExternalEnvMap = true;
		mMode = .EnvironmentMap;

		// Generate IBL maps (skipped for external HDRI — needs GPU convolution)
		GenerateIBLMaps();
		return .Ok;
	}

	private Result<void> CreateSkyParamsBuffer()
	{
		// Create per-frame sky params buffers
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			// Use Upload memory for CPU mapping (avoids command buffer for writes)
			BufferDesc desc = .()
			{
				Label = "Sky Params",
				Size = (uint64)ProceduralSkyParams.Size,
				Usage = .Uniform,
				MemoryAccess = .CpuToGpu // CPU-mappable
			};

			switch (Renderer.Device.CreateBuffer(desc))
			{
			case .Ok(let buf): mSkyParamsBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	private Result<void> CreateFullscreenQuad()
	{
		// Full-screen triangle (more efficient than quad)
		float[12] vertices = .(
			-1.0f, -1.0f, 0.0f, 0.0f,  // Bottom-left
			 3.0f, -1.0f, 2.0f, 0.0f,  // Bottom-right (oversized)
			-1.0f,  3.0f, 0.0f, 2.0f   // Top-left (oversized)
		);

		BufferDesc desc = .()
		{
			Label = "Fullscreen Triangle",
			Size = sizeof(decltype(vertices)),
			Usage = .Vertex | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(desc))
		{
		case .Ok(let buf):
			mFullscreenQuadVB = buf;
			UploadBuffer(mFullscreenQuadVB, 0, Span<uint8>((uint8*)&vertices[0], sizeof(decltype(vertices))));
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateBRDFLut()
	{
		// Create 2D texture for BRDF integration LUT
		TextureDesc desc = .()
		{
			Label = "BRDF LUT",
			Width = (uint32)BRDFLutData.Width,
			Height = (uint32)BRDFLutData.Height,
			Depth = 1,
			Format = .RG16Float,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst  // Need CopyDst for WriteTexture
		};

		switch (Renderer.Device.CreateTexture(desc))
		{
		case .Ok(let tex): mBRDFLut = tex;
		case .Err: return .Err;
		}

		TextureViewDesc viewDesc = .()
		{
			Label = "BRDF LUT View",
			Dimension = .Texture2D,
			Format = .RG16Float  // Must match texture format
		};

		switch (Renderer.Device.CreateTextureView(mBRDFLut, viewDesc))
		{
		case .Ok(let view): mBRDFLutView = view;
		case .Err: return .Err;
		}

		// Upload pre-generated BRDF LUT data
		UploadBRDFLut();

		return .Ok;
	}

	/// Uploads pre-generated BRDF integration LUT from BRDFLutData.
	/// The data was generated offline using GGX importance sampling with 1024 samples per texel.
	private void UploadBRDFLut()
	{
		if (mBRDFLut == null)
			return;

		var layout = TextureDataLayout()
		{
			BytesPerRow = (uint32)(BRDFLutData.Width * 4), // RG16Float = 4 bytes per pixel
			RowsPerImage = (uint32)BRDFLutData.Height
		};
		var writeSize = Extent3D((uint32)BRDFLutData.Width, (uint32)BRDFLutData.Height, 1);
		UploadTexture(mBRDFLut, Span<uint8>(&BRDFLutData.Data, BRDFLutData.DataSize), &layout, &writeSize);
	}

	/// Converts a float to half-precision (IEEE 754 binary16).
	private static uint16 FloatToHalf(float value)
	{
		// Simplified conversion - handles common cases
		if (value == 0.0f) return 0;
		if (value != value) return 0x7E00; // NaN

		var val = value;
		uint32 bits = *(uint32*)&val;
		uint32 sign = (bits >> 16) & 0x8000;
		int32 exp = (int32)((bits >> 23) & 0xFF) - 127 + 15;
		uint32 mantissa = bits & 0x007FFFFF;

		if (exp <= 0)
		{
			// Denormalized or zero
			return (uint16)sign;
		}
		else if (exp >= 31)
		{
			// Overflow to infinity
			return (uint16)(sign | 0x7C00);
		}

		return (uint16)(sign | ((uint32)exp << 10) | (mantissa >> 13));
	}

	/// Regenerates IBL maps from current sky parameters.
	/// Call after changing sky mode or sky colors at runtime.
	public void RegenerateIBL()
	{
		GenerateIBLMaps();
	}

	private void GenerateIBLMaps()
	{
		if (mIsExternalEnvMap)
		{
			// IBL already generated by SetEnvironmentMapEquirect
			return;
		}

		switch (mMode)
		{
		case .Procedural, .EnvironmentMap:
			GenerateIBLMapsFromColors(mSkyParams.ZenithColor, mSkyParams.HorizonColor, mSkyParams.GroundColor);
		case .SolidColor:
			GenerateIBLMapsFromColors(mSkyParams.SolidColor, mSkyParams.SolidColor, mSkyParams.SolidColor);
		}
	}

	private void GenerateIBLMapsFromColors(Vector3 topColor, Vector3 horizonColor, Vector3 groundColor)
	{
		FlushAndInvalidateBindGroups();
		GenerateIrradianceMap(topColor, horizonColor, groundColor);
		GeneratePrefilteredMap(topColor, horizonColor, groundColor);
		mIBLGeneration++;
	}

	/// Flushes in-flight GPU work and invalidates all bind groups that reference
	/// sky/IBL views, so those views can be safely destroyed.
	private void FlushAndInvalidateBindGroups()
	{
		Renderer.Device.WaitIdle();

		// Invalidate sky bind groups (owned by this feature)
		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mSkyBindGroups[i] != null)
			{
				delete mSkyBindGroups[i];
				mSkyBindGroups[i] = null;
			}
		}

		// Invalidate scene bind groups in ForwardOpaqueFeature (references IBL views)
		let forwardFeature = Renderer.GetFeature<ForwardOpaqueFeature>();
		if (forwardFeature != null)
			forwardFeature.InvalidateSceneBindGroups();
	}

	// ==================== GPU IBL Compute Pipeline ====================

	/// Releases old environment and IBL maps.
	private void ReleaseEnvironmentAndIBLMaps()
	{
		if (mOwnsEnvironmentMap)
		{
			if (mEnvironmentMapView != null) { delete mEnvironmentMapView; mEnvironmentMapView = null; }
			if (mEnvironmentMap != null) { delete mEnvironmentMap; mEnvironmentMap = null; }
		}
		mOwnsEnvironmentMap = false;
		if (mIrradianceMapView != null) { delete mIrradianceMapView; mIrradianceMapView = null; }
		if (mIrradianceMap != null) { delete mIrradianceMap; mIrradianceMap = null; }
		if (mPrefilteredMapView != null) { delete mPrefilteredMapView; mPrefilteredMapView = null; }
		if (mPrefilteredMap != null) { delete mPrefilteredMap; mPrefilteredMap = null; }
	}

	/// Lazily creates compute pipelines for GPU IBL generation.
	private Result<void> EnsureIBLComputePipelines()
	{
		if (mEquirectToCubemapPipeline != null)
			return .Ok; // Already created

		let shaderSystem = Renderer.ShaderSystem;
		if (shaderSystem == null)
			return .Err;

		let device = Renderer.Device;

		// --- Equirect-to-cubemap pipeline ---
		let equirectShaderResult = shaderSystem.GetShader("equirect_to_cubemap", .Compute);
		if (equirectShaderResult case .Err)
			return .Err;
		let equirectShader = equirectShaderResult.Value;

		// Layout: b0 (uniform), t0 (Texture2D), s0 (sampler), u0 (RWTexture2DArray)
		BindGroupLayoutEntry[4] equirectLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Compute),
			BindGroupLayoutEntry.SampledTexture(0, .Compute, .Texture2D),
			BindGroupLayoutEntry.Sampler(0, .Compute),
			.() { Binding = 0, Visibility = .Compute, Type = .StorageTextureReadWrite,
				  StorageTextureFormat = .RGBA32Float, TextureViewDimension = .Texture2DArray }
		);

		BindGroupLayoutDesc equirectLayoutDesc = .() { Label = "Equirect IBL Layout", Entries = equirectLayoutEntries };
		switch (device.CreateBindGroupLayout(equirectLayoutDesc))
		{
		case .Ok(let layout): mEquirectBindGroupLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] equirectBGLayouts = .(mEquirectBindGroupLayout);
		PipelineLayoutDesc equirectPLDesc = .(equirectBGLayouts);
		switch (device.CreatePipelineLayout(equirectPLDesc))
		{
		case .Ok(let layout): mEquirectPipelineLayout = layout;
		case .Err: return .Err;
		}

		ComputePipelineDesc equirectPipelineDesc = .(mEquirectPipelineLayout, equirectShader.Module, "main");
		switch (device.CreateComputePipeline(equirectPipelineDesc))
		{
		case .Ok(let pipeline): mEquirectToCubemapPipeline = pipeline;
		case .Err: return .Err;
		}

		// --- IBL convolve pipeline (shared layout for irradiance + prefilter) ---
		// Layout: b0 (uniform), t0 (TextureCube), s0 (sampler), u0 (RWTexture2DArray)
		BindGroupLayoutEntry[4] convolveLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Compute),
			BindGroupLayoutEntry.SampledTexture(0, .Compute, .TextureCube),
			BindGroupLayoutEntry.Sampler(0, .Compute),
			.() { Binding = 0, Visibility = .Compute, Type = .StorageTextureReadWrite,
				  StorageTextureFormat = .RGBA32Float, TextureViewDimension = .Texture2DArray }
		);

		BindGroupLayoutDesc convolveLayoutDesc = .() { Label = "IBL Convolve Layout", Entries = convolveLayoutEntries };
		switch (device.CreateBindGroupLayout(convolveLayoutDesc))
		{
		case .Ok(let layout): mIBLConvolveBindGroupLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] convolveBGLayouts = .(mIBLConvolveBindGroupLayout);
		PipelineLayoutDesc convolvePLDesc = .(convolveBGLayouts);
		switch (device.CreatePipelineLayout(convolvePLDesc))
		{
		case .Ok(let layout): mIBLConvolvePipelineLayout = layout;
		case .Err: return .Err;
		}

		// Irradiance pipeline
		let irrShaderResult = shaderSystem.GetShader("ibl_irradiance", .Compute);
		if (irrShaderResult case .Err)
			return .Err;

		ComputePipelineDesc irrPipelineDesc = .(mIBLConvolvePipelineLayout, irrShaderResult.Value.Module, "main");
		switch (device.CreateComputePipeline(irrPipelineDesc))
		{
		case .Ok(let pipeline): mIBLIrradiancePipeline = pipeline;
		case .Err: return .Err;
		}

		// Prefilter pipeline
		let prefShaderResult = shaderSystem.GetShader("ibl_prefilter", .Compute);
		if (prefShaderResult case .Err)
			return .Err;

		ComputePipelineDesc prefPipelineDesc = .(mIBLConvolvePipelineLayout, prefShaderResult.Value.Module, "main");
		switch (device.CreateComputePipeline(prefPipelineDesc))
		{
		case .Ok(let pipeline): mIBLPrefilterPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	/// CRepr params struct matching equirect_to_cubemap.comp.hlsl cbuffer
	[CRepr]
	private struct EquirectParams
	{
		public uint32 Resolution;
		public uint32 _pad0;
		public uint32 _pad1;
		public uint32 _pad2;
	}

	/// CRepr params struct matching ibl_prefilter.comp.hlsl cbuffer
	[CRepr]
	private struct PrefilterParams
	{
		public uint32 Resolution;
		public float Roughness;
		public uint32 _pad0;
		public uint32 _pad1;
	}

	/// Sets an equirectangular HDR panorama as the environment map.
	/// Converts to cubemap and generates IBL maps via GPU compute shaders.
	public Result<void> SetEnvironmentMapEquirect(TextureData equirectData, int32 cubemapResolution = 512)
	{
		// Ensure compute pipelines are ready
		if (EnsureIBLComputePipelines() case .Err)
			return .Err;

		let device = Renderer.Device;

		// Flush GPU and invalidate bind groups before destroying views
		FlushAndInvalidateBindGroups();

		// Release old environment and IBL maps
		ReleaseEnvironmentAndIBLMaps();

		// --- 1. Upload equirect image to temporary GPU texture ---
		TextureDesc equirectTexDesc = .()
		{
			Label = "Equirect HDR",
			Width = equirectData.Width,
			Height = equirectData.Height,
			Depth = 1,
			Format = equirectData.Format,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		ITexture equirectTexture = null;
		switch (device.CreateTexture(equirectTexDesc))
		{
		case .Ok(let tex): equirectTexture = tex;
		case .Err: return .Err;
		}
		defer delete equirectTexture;

		// Upload pixel data
		uint32 bpp = TextureData.GetBytesPerPixel(equirectData.Format);
		uint32 bytesPerRow = equirectData.BytesPerRow > 0 ? equirectData.BytesPerRow : equirectData.Width * bpp;
		var equirectLayout = TextureDataLayout() { BytesPerRow = bytesPerRow, RowsPerImage = equirectData.Height };
		var equirectSize = Extent3D(equirectData.Width, equirectData.Height, 1);
		UploadTexture(equirectTexture, Span<uint8>(equirectData.Pixels, (int)equirectData.Size), &equirectLayout, &equirectSize);

		TextureViewDesc equirectViewDesc = .() { Label = "Equirect View", Dimension = .Texture2D, Format = equirectData.Format };
		ITextureView equirectView = null;
		switch (device.CreateTextureView(equirectTexture, equirectViewDesc))
		{
		case .Ok(let view): equirectView = view;
		case .Err: return .Err;
		}
		defer delete equirectView;

		// --- 2. Create output cubemaps ---
		let cubeRes = (uint32)cubemapResolution;
		const uint32 IrrSize = 32;
		const uint32 PrefBase = 128;
		const uint32 PrefMips = 5;

		// Environment cubemap
		TextureDesc envCubeDesc = .Cubemap(cubeRes, .RGBA32Float, .Storage | .Sampled);
		switch (device.CreateTexture(envCubeDesc))
		{
		case .Ok(let tex): mEnvironmentMap = tex;
		case .Err: return .Err;
		}
		mOwnsEnvironmentMap = true;

		// Irradiance cubemap
		TextureDesc irrDesc = .Cubemap(IrrSize, .RGBA32Float, .Storage | .Sampled);
		switch (device.CreateTexture(irrDesc))
		{
		case .Ok(let tex): mIrradianceMap = tex;
		case .Err: return .Err;
		}

		// Prefiltered cubemap with mip chain
		TextureDesc prefDesc = .Cubemap(PrefBase, .RGBA32Float, .Storage | .Sampled, PrefMips);
		switch (device.CreateTexture(prefDesc))
		{
		case .Ok(let tex): mPrefilteredMap = tex;
		case .Err: return .Err;
		}

		// --- 3. Create storage views (Texture2DArray for compute writes) ---
		// Environment cubemap storage view (all 6 faces, mip 0)
		TextureViewDesc envStorageViewDesc = .()
		{
			Label = "Env Cubemap Storage",
			Format = .RGBA32Float,
			Dimension = .Texture2DArray,
			BaseMipLevel = 0, MipLevelCount = 1,
			BaseArrayLayer = 0, ArrayLayerCount = 6
		};
		ITextureView envStorageView = null;
		switch (device.CreateTextureView(mEnvironmentMap, envStorageViewDesc))
		{
		case .Ok(let view): envStorageView = view;
		case .Err: return .Err;
		}

		// Irradiance storage view
		TextureViewDesc irrStorageViewDesc = .()
		{
			Label = "Irradiance Storage",
			Format = .RGBA32Float,
			Dimension = .Texture2DArray,
			BaseMipLevel = 0, MipLevelCount = 1,
			BaseArrayLayer = 0, ArrayLayerCount = 6
		};
		ITextureView irrStorageView = null;
		switch (device.CreateTextureView(mIrradianceMap, irrStorageViewDesc))
		{
		case .Ok(let view): irrStorageView = view;
		case .Err: return .Err;
		}

		// Prefiltered storage views — one per mip level
		ITextureView[PrefMips] prefStorageViews = default;
		for (uint32 mip = 0; mip < PrefMips; mip++)
		{
			TextureViewDesc prefStorageViewDesc = .()
			{
				Label = "Prefilter Storage",
				Format = .RGBA32Float,
				Dimension = .Texture2DArray,
				BaseMipLevel = mip, MipLevelCount = 1,
				BaseArrayLayer = 0, ArrayLayerCount = 6
			};
			switch (device.CreateTextureView(mPrefilteredMap, prefStorageViewDesc))
			{
			case .Ok(let view): prefStorageViews[mip] = view;
			case .Err:
				// Clean up already-created views
				for (uint32 j = 0; j < mip; j++)
					if (prefStorageViews[j] != null) delete prefStorageViews[j];
				if (irrStorageView != null) delete irrStorageView;
				if (envStorageView != null) delete envStorageView;
				return .Err;
			}
		}

		// Create TextureCube sampled view for environment cubemap (needed by irradiance/prefilter shaders)
		TextureViewDesc envCubeViewDesc = .()
		{
			Label = "Env Cubemap View",
			Format = .RGBA32Float,
			Dimension = .TextureCube,
			BaseMipLevel = 0, MipLevelCount = 1,
			BaseArrayLayer = 0, ArrayLayerCount = 6
		};
		switch (device.CreateTextureView(mEnvironmentMap, envCubeViewDesc))
		{
		case .Ok(let view): mEnvironmentMapView = view;
		case .Err:
			for (uint32 j = 0; j < PrefMips; j++)
				if (prefStorageViews[j] != null) delete prefStorageViews[j];
			if (irrStorageView != null) delete irrStorageView;
			if (envStorageView != null) delete envStorageView;
			return .Err;
		}

		// --- 4. Create params buffers ---
		// Equirect params
		EquirectParams equirectParams = .() { Resolution = cubeRes };
		IBuffer equirectParamsBuf = null;
		{
			BufferDesc bufDesc = .() { Label = "Equirect Params", Size = sizeof(EquirectParams), Usage = .Uniform | .CopyDst };
			switch (device.CreateBuffer(bufDesc))
			{
			case .Ok(let buf): equirectParamsBuf = buf;
			case .Err:
				for (uint32 j = 0; j < PrefMips; j++) if (prefStorageViews[j] != null) delete prefStorageViews[j];
				delete irrStorageView; delete envStorageView;
				return .Err;
			}
			UploadBuffer(equirectParamsBuf, 0, Span<uint8>((uint8*)&equirectParams, sizeof(EquirectParams)));
		}

		// Prefilter params (one per mip)
		IBuffer[PrefMips] prefParamsBufs = default;
		for (uint32 mip = 0; mip < PrefMips; mip++)
		{
			uint32 mipSize = PrefBase >> mip;
			float roughness = (float)mip / (float)(PrefMips - 1);
			PrefilterParams prefParams = .() { Resolution = mipSize, Roughness = roughness };

			BufferDesc bufDesc = .() { Label = "Prefilter Params", Size = sizeof(PrefilterParams), Usage = .Uniform | .CopyDst };
			switch (device.CreateBuffer(bufDesc))
			{
			case .Ok(let buf): prefParamsBufs[mip] = buf;
			case .Err:
				for (uint32 j = 0; j < mip; j++) if (prefParamsBufs[j] != null) delete prefParamsBufs[j];
				delete equirectParamsBuf;
				for (uint32 j = 0; j < PrefMips; j++) if (prefStorageViews[j] != null) delete prefStorageViews[j];
				delete irrStorageView; delete envStorageView;
				return .Err;
			}
			UploadBuffer(prefParamsBufs[mip], 0, Span<uint8>((uint8*)&prefParams, sizeof(PrefilterParams)));
		}

		// Irradiance needs a dummy params buffer (bind group layout requires b0)
		EquirectParams irrParams = .() { Resolution = IrrSize };
		IBuffer irrParamsBuf = null;
		{
			BufferDesc bufDesc = .() { Label = "Irradiance Params", Size = sizeof(EquirectParams), Usage = .Uniform | .CopyDst };
			switch (device.CreateBuffer(bufDesc))
			{
			case .Ok(let buf): irrParamsBuf = buf;
			case .Err:
				for (uint32 j = 0; j < PrefMips; j++) if (prefParamsBufs[j] != null) delete prefParamsBufs[j];
				delete equirectParamsBuf;
				for (uint32 j = 0; j < PrefMips; j++) if (prefStorageViews[j] != null) delete prefStorageViews[j];
				delete irrStorageView; delete envStorageView;
				return .Err;
			}
			UploadBuffer(irrParamsBuf, 0, Span<uint8>((uint8*)&irrParams, sizeof(EquirectParams)));
		}

		// --- 5. Create bind groups ---
		// Equirect bind group
		BindGroupEntry[4] equirectBGEntries = .(
			BindGroupEntry.Buffer(0, equirectParamsBuf, 0, sizeof(EquirectParams)),
			BindGroupEntry.Texture(0, equirectView),
			BindGroupEntry.Sampler(0, mEnvSampler),
			BindGroupEntry.Texture(0, envStorageView)
		);
		BindGroupDesc equirectBGDesc = .(mEquirectBindGroupLayout, equirectBGEntries);
		equirectBGDesc.Label = "Equirect BG";

		IBindGroup equirectBG = null;
		switch (device.CreateBindGroup(equirectBGDesc))
		{
		case .Ok(let bg): equirectBG = bg;
		case .Err:
			delete irrParamsBuf;
			for (uint32 j = 0; j < PrefMips; j++) if (prefParamsBufs[j] != null) delete prefParamsBufs[j];
			delete equirectParamsBuf;
			for (uint32 j = 0; j < PrefMips; j++) if (prefStorageViews[j] != null) delete prefStorageViews[j];
			delete irrStorageView; delete envStorageView;
			return .Err;
		}

		// Irradiance bind group
		BindGroupEntry[4] irrBGEntries = .(
			BindGroupEntry.Buffer(0, irrParamsBuf, 0, sizeof(EquirectParams)),
			BindGroupEntry.Texture(0, mEnvironmentMapView),
			BindGroupEntry.Sampler(0, mEnvSampler),
			BindGroupEntry.Texture(0, irrStorageView)
		);
		BindGroupDesc irrBGDesc = .(mIBLConvolveBindGroupLayout, irrBGEntries);
		irrBGDesc.Label = "Irradiance BG";

		IBindGroup irrBG = null;
		switch (device.CreateBindGroup(irrBGDesc))
		{
		case .Ok(let bg): irrBG = bg;
		case .Err:
			delete equirectBG;
			delete irrParamsBuf;
			for (uint32 j = 0; j < PrefMips; j++) if (prefParamsBufs[j] != null) delete prefParamsBufs[j];
			delete equirectParamsBuf;
			for (uint32 j = 0; j < PrefMips; j++) if (prefStorageViews[j] != null) delete prefStorageViews[j];
			delete irrStorageView; delete envStorageView;
			return .Err;
		}

		// Prefilter bind groups (one per mip)
		IBindGroup[PrefMips] prefBGs = default;
		for (uint32 mip = 0; mip < PrefMips; mip++)
		{
			BindGroupEntry[4] prefBGEntries = .(
				BindGroupEntry.Buffer(0, prefParamsBufs[mip], 0, sizeof(PrefilterParams)),
				BindGroupEntry.Texture(0, mEnvironmentMapView),
				BindGroupEntry.Sampler(0, mEnvSampler),
				BindGroupEntry.Texture(0, prefStorageViews[mip])
			);
			BindGroupDesc prefBGDesc = .(mIBLConvolveBindGroupLayout, prefBGEntries);
			prefBGDesc.Label = "Prefilter BG";

			switch (device.CreateBindGroup(prefBGDesc))
			{
			case .Ok(let bg): prefBGs[mip] = bg;
			case .Err:
				for (uint32 j = 0; j < mip; j++) if (prefBGs[j] != null) delete prefBGs[j];
				delete irrBG; delete equirectBG;
				delete irrParamsBuf;
				for (uint32 j = 0; j < PrefMips; j++) if (prefParamsBufs[j] != null) delete prefParamsBufs[j];
				delete equirectParamsBuf;
				for (uint32 j = 0; j < PrefMips; j++) if (prefStorageViews[j] != null) delete prefStorageViews[j];
				delete irrStorageView; delete envStorageView;
				return .Err;
			}
		}

		// --- 6. Record and submit compute work ---
		let encoder = device.CreateCommandEncoder();
		if (encoder == null)
		{
			// Clean up everything
			for (uint32 j = 0; j < PrefMips; j++) if (prefBGs[j] != null) delete prefBGs[j];
			delete irrBG; delete equirectBG;
			delete irrParamsBuf;
			for (uint32 j = 0; j < PrefMips; j++) if (prefParamsBufs[j] != null) delete prefParamsBufs[j];
			delete equirectParamsBuf;
			for (uint32 j = 0; j < PrefMips; j++) if (prefStorageViews[j] != null) delete prefStorageViews[j];
			delete irrStorageView; delete envStorageView;
			return .Err;
		}

		// Transition output textures from Undefined → General for storage writes
		encoder.TextureBarrier(mEnvironmentMap, .Undefined, .General);
		encoder.TextureBarrier(mIrradianceMap, .Undefined, .General);
		encoder.TextureBarrier(mPrefilteredMap, .Undefined, .General);

		// Pass 1: Equirect → Cubemap
		{
			let pass = encoder.BeginComputePass("Equirect to Cubemap");
			pass.SetPipeline(mEquirectToCubemapPipeline);
			pass.SetBindGroup(0, equirectBG, default);
			pass.Dispatch((cubeRes + 7) / 8, (cubeRes + 7) / 8, 6);
			pass.End();
			delete pass;
		}

		// Transition env cubemap: General (storage write) → ShaderReadOnly (sampled by irradiance/prefilter)
		encoder.TextureBarrier(mEnvironmentMap, .General, .ShaderReadOnly);

		// Pass 2: Irradiance convolution
		{
			let pass = encoder.BeginComputePass("IBL Irradiance");
			pass.SetPipeline(mIBLIrradiancePipeline);
			pass.SetBindGroup(0, irrBG, default);
			pass.Dispatch(IrrSize / 8, IrrSize / 8, 6);
			pass.End();
			delete pass;
		}

		// Passes 3-7: Prefiltered convolution per mip
		for (uint32 mip = 0; mip < PrefMips; mip++)
		{
			uint32 mipSize = PrefBase >> mip;
			let pass = encoder.BeginComputePass("IBL Prefilter");
			pass.SetPipeline(mIBLPrefilterPipeline);
			pass.SetBindGroup(0, prefBGs[mip], default);
			pass.Dispatch((mipSize + 7) / 8, (mipSize + 7) / 8, 6);
			pass.End();
			delete pass;
		}

		// Transition IBL outputs to ShaderReadOnly for rendering
		encoder.TextureBarrier(mIrradianceMap, .General, .ShaderReadOnly);
		encoder.TextureBarrier(mPrefilteredMap, .General, .ShaderReadOnly);

		let cmdBuf = encoder.Finish();
		defer delete encoder;
		device.Queue.Submit(cmdBuf);
		device.WaitIdle();
		delete cmdBuf;

		// --- 7. Create sampled views for IBL ---
		// Irradiance cubemap view
		TextureViewDesc irrCubeViewDesc = .()
		{
			Label = "Irradiance Cubemap View",
			Format = .RGBA32Float, Dimension = .TextureCube,
			BaseMipLevel = 0, MipLevelCount = 1,
			BaseArrayLayer = 0, ArrayLayerCount = 6
		};
		switch (device.CreateTextureView(mIrradianceMap, irrCubeViewDesc))
		{
		case .Ok(let view): mIrradianceMapView = view;
		case .Err: return .Err;
		}

		// Prefiltered cubemap view (all mips)
		TextureViewDesc prefCubeViewDesc = .()
		{
			Label = "Prefiltered Cubemap View",
			Format = .RGBA32Float, Dimension = .TextureCube,
			BaseMipLevel = 0, MipLevelCount = PrefMips,
			BaseArrayLayer = 0, ArrayLayerCount = 6
		};
		switch (device.CreateTextureView(mPrefilteredMap, prefCubeViewDesc))
		{
		case .Ok(let view): mPrefilteredMapView = view;
		case .Err: return .Err;
		}

		// --- 8. Clean up temporary resources ---
		for (uint32 j = 0; j < PrefMips; j++) if (prefBGs[j] != null) delete prefBGs[j];
		delete irrBG;
		delete equirectBG;
		delete irrParamsBuf;
		for (uint32 j = 0; j < PrefMips; j++) if (prefParamsBufs[j] != null) delete prefParamsBufs[j];
		delete equirectParamsBuf;
		for (uint32 j = 0; j < PrefMips; j++) if (prefStorageViews[j] != null) delete prefStorageViews[j];
		delete irrStorageView;
		delete envStorageView;

		// --- 9. Set state ---
		mMode = .EnvironmentMap;
		mIsExternalEnvMap = true;
		mIBLGeneration++;

		return .Ok;
	}

	// ==================== IBL Helper Methods ====================

	/// Computes world-space direction for a cubemap texel.
	/// Face order: 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z
	private static Vector3 CubemapTexelDirection(int32 face, int32 x, int32 y, int32 resolution)
	{
		float u = ((float)x + 0.5f) / (float)resolution * 2.0f - 1.0f;
		float v = ((float)y + 0.5f) / (float)resolution * 2.0f - 1.0f;

		Vector3 dir;
		switch (face)
		{
		case 0: dir = .(1.0f, -v, -u);     // +X
		case 1: dir = .(-1.0f, -v, u);     // -X
		case 2: dir = .(u, 1.0f, v);       // +Y
		case 3: dir = .(u, -1.0f, -v);     // -Y
		case 4: dir = .(u, -v, 1.0f);      // +Z
		default: dir = .(-u, -v, -1.0f);   // -Z
		}
		return Vector3.Normalize(dir);
	}

	/// Evaluates gradient sky color for any world direction.
	private static Vector3 SampleGradientSky(Vector3 dir, Vector3 topColor, Vector3 horizonColor, Vector3 groundColor)
	{
		float elevation = dir.Y;
		if (elevation > 0.0f)
			return Vector3.Lerp(horizonColor, topColor, elevation);
		else
			return Vector3.Lerp(horizonColor, groundColor, -elevation);
	}

	/// GGX importance sampling — returns half-vector in tangent space (Z-up).
	private static Vector3 ImportanceSampleGGX(float xi1, float xi2, float roughness)
	{
		float a = roughness * roughness;
		float phi = 2.0f * Math.PI_f * xi1;
		float cosTheta = Math.Sqrt((1.0f - xi2) / (1.0f + (a * a - 1.0f) * xi2));
		float sinTheta = Math.Sqrt(1.0f - cosTheta * cosTheta);

		return .(Math.Cos(phi) * sinTheta, Math.Sin(phi) * sinTheta, cosTheta);
	}

	/// Builds an orthonormal basis from N (assumed normalized).
	private static void BuildTangentBasis(Vector3 N, out Vector3 T, out Vector3 B)
	{
		Vector3 up = (Math.Abs(N.Y) < 0.999f) ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
		T = Vector3.Normalize(Vector3.Cross(up, N));
		B = Vector3.Cross(N, T);
	}

	/// Transforms a tangent-space vector to world space using the given basis.
	private static Vector3 TangentToWorld(Vector3 v, Vector3 T, Vector3 B, Vector3 N)
	{
		return T * v.X + B * v.Y + N * v.Z;
	}

	/// Hammersley quasi-random sequence (low-discrepancy).
	private static float RadicalInverseVdC(uint32 bits)
	{
		var bits;
		bits = (bits << 16) | (bits >> 16);
		bits = ((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1);
		bits = ((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2);
		bits = ((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4);
		bits = ((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8);
		return (float)bits * 2.3283064365386963e-10f;
	}

	// ==================== Irradiance Map Generation ====================

	private Result<void> GenerateIrradianceMap(Vector3 topColor, Vector3 horizonColor, Vector3 groundColor)
	{
		const int32 IrrSize = 32;
		const int32 NumSamplesAzi = 64;
		const int32 NumSamplesElev = 16;
		let totalSamples = NumSamplesAzi * NumSamplesElev;

		// Release old
		if (mIrradianceMapView != null) { delete mIrradianceMapView; mIrradianceMapView = null; }
		if (mIrradianceMap != null) { delete mIrradianceMap; mIrradianceMap = null; }

		// Create cubemap texture
		TextureDesc texDesc = .Cubemap((uint32)IrrSize, .RGBA16Float, .Sampled | .CopyDst);
		switch (Renderer.Device.CreateTexture(texDesc))
		{
		case .Ok(let tex): mIrradianceMap = tex;
		case .Err: return .Err;
		}

		// Generate and upload each face
		int32 pixelsPerFace = IrrSize * IrrSize;
		uint16[] faceData = new uint16[pixelsPerFace * 4]; // RGBA16Float = 4 x uint16
		defer delete faceData;

		for (int32 face = 0; face < 6; face++)
		{
			for (int32 y = 0; y < IrrSize; y++)
			{
				for (int32 x = 0; x < IrrSize; x++)
				{
					Vector3 N = CubemapTexelDirection(face, x, y, IrrSize);

					// Build tangent frame
					Vector3 T, B;
					BuildTangentBasis(N, out T, out B);

					// Hemisphere convolution with cosine weighting
					Vector3 irradiance = .Zero;
					for (int32 ei = 0; ei < NumSamplesElev; ei++)
					{
						float theta = Math.PI_f * 0.5f * ((float)ei + 0.5f) / (float)NumSamplesElev;
						float cosTheta = Math.Cos(theta);
						float sinTheta = Math.Sin(theta);

						for (int32 ai = 0; ai < NumSamplesAzi; ai++)
						{
							float phi = 2.0f * Math.PI_f * (float)ai / (float)NumSamplesAzi;
							// Sample direction in tangent space
							Vector3 tsSample = .(Math.Cos(phi) * sinTheta, Math.Sin(phi) * sinTheta, cosTheta);
							// Transform to world space
							Vector3 sampleDir = TangentToWorld(tsSample, T, B, N);
							Vector3 skyColor = SampleGradientSky(sampleDir, topColor, horizonColor, groundColor);
							irradiance += skyColor * cosTheta * sinTheta;
						}
					}
					irradiance = irradiance * (Math.PI_f / (float)totalSamples);

					int32 idx = (y * IrrSize + x) * 4;
					faceData[idx + 0] = FloatToHalf(irradiance.X);
					faceData[idx + 1] = FloatToHalf(irradiance.Y);
					faceData[idx + 2] = FloatToHalf(irradiance.Z);
					faceData[idx + 3] = FloatToHalf(1.0f);
				}
			}

			// Upload face
			var layout = TextureDataLayout() { BytesPerRow = (uint32)(IrrSize * 8), RowsPerImage = (uint32)IrrSize };
			var writeSize = Extent3D((uint32)IrrSize, (uint32)IrrSize, 1);
			UploadTexture(mIrradianceMap, Span<uint8>((uint8*)faceData.Ptr, faceData.Count * 2), &layout, &writeSize, 0, (uint32)face);
		}

		// Create cubemap view
		TextureViewDesc viewDesc = .()
		{
			Format = .RGBA16Float,
			Dimension = .TextureCube,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6
		};

		switch (Renderer.Device.CreateTextureView(mIrradianceMap, viewDesc))
		{
		case .Ok(let view): mIrradianceMapView = view;
		case .Err: return .Err;
		}

		return .Ok;
	}

	// ==================== Prefiltered Specular Map Generation ====================

	private Result<void> GeneratePrefilteredMap(Vector3 topColor, Vector3 horizonColor, Vector3 groundColor)
	{
		const int32 BaseSize = 128;
		const uint32 MipLevels = 5;
		const int32 NumSamples = 128;

		// Release old
		if (mPrefilteredMapView != null) { delete mPrefilteredMapView; mPrefilteredMapView = null; }
		if (mPrefilteredMap != null) { delete mPrefilteredMap; mPrefilteredMap = null; }

		// Create cubemap with mip chain
		TextureDesc texDesc = .Cubemap((uint32)BaseSize, .RGBA16Float, .Sampled | .CopyDst, MipLevels);
		switch (Renderer.Device.CreateTexture(texDesc))
		{
		case .Ok(let tex): mPrefilteredMap = tex;
		case .Err: return .Err;
		}

		// Allocate max-size buffer (for mip 0)
		int32 maxPixels = BaseSize * BaseSize;
		uint16[] faceData = new uint16[maxPixels * 4];
		defer delete faceData;

		for (uint32 mip = 0; mip < MipLevels; mip++)
		{
			int32 mipSize = BaseSize >> (int32)mip;
			float roughness = (float)mip / (float)(MipLevels - 1);

			for (int32 face = 0; face < 6; face++)
			{
				for (int32 y = 0; y < mipSize; y++)
				{
					for (int32 x = 0; x < mipSize; x++)
					{
						Vector3 N = CubemapTexelDirection(face, x, y, mipSize);
						Vector3 R = N; // For prefiltering, assume V = R = N
						Vector3 V = R;

						Vector3 T, B;
						BuildTangentBasis(N, out T, out B);

						Vector3 prefilteredColor = .Zero;
						float totalWeight = 0.0f;

						for (int32 i = 0; i < NumSamples; i++)
						{
							// Hammersley sequence
							float xi1 = (float)i / (float)NumSamples;
							float xi2 = RadicalInverseVdC((uint32)i);

							// Importance sample GGX
							Vector3 H = TangentToWorld(ImportanceSampleGGX(xi1, xi2, roughness), T, B, N);
							Vector3 L = H * (2.0f * Vector3.Dot(V, H)) - V;

							float NdotL = Math.Max(Vector3.Dot(N, L), 0.0f);
							if (NdotL > 0.0f)
							{
								Vector3 skyColor = SampleGradientSky(L, topColor, horizonColor, groundColor);
								prefilteredColor += skyColor * NdotL;
								totalWeight += NdotL;
							}
						}

						if (totalWeight > 0.0f)
							prefilteredColor = prefilteredColor * (1.0f / totalWeight);

						int32 idx = (y * mipSize + x) * 4;
						faceData[idx + 0] = FloatToHalf(prefilteredColor.X);
						faceData[idx + 1] = FloatToHalf(prefilteredColor.Y);
						faceData[idx + 2] = FloatToHalf(prefilteredColor.Z);
						faceData[idx + 3] = FloatToHalf(1.0f);
					}
				}

				// Upload face at this mip level
				var layout = TextureDataLayout() { BytesPerRow = (uint32)(mipSize * 8), RowsPerImage = (uint32)mipSize };
				var writeSize = Extent3D((uint32)mipSize, (uint32)mipSize, 1);
				UploadTexture(mPrefilteredMap, Span<uint8>((uint8*)faceData.Ptr, mipSize * mipSize * 8), &layout, &writeSize, mip, (uint32)face);
			}
		}

		// Create cubemap view with all mip levels
		TextureViewDesc viewDesc = .()
		{
			Format = .RGBA16Float,
			Dimension = .TextureCube,
			BaseMipLevel = 0,
			MipLevelCount = MipLevels,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6
		};

		switch (Renderer.Device.CreateTextureView(mPrefilteredMap, viewDesc))
		{
		case .Ok(let view): mPrefilteredMapView = view;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateEnvSamplerAndFallback()
	{
		// Create sampler for cubemap sampling
		SamplerDesc samplerDesc = .();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Linear;
		samplerDesc.AddressU = .ClampToEdge;
		samplerDesc.AddressV = .ClampToEdge;
		samplerDesc.AddressW = .ClampToEdge;

		switch (Renderer.Device.CreateSampler(samplerDesc))
		{
		case .Ok(let sampler): mEnvSampler = sampler;
		case .Err: return .Err;
		}

		// Create a 1x1 black fallback cubemap
		TextureDesc texDesc = .Cubemap(1, .RGBA8Unorm, .Sampled | .CopyDst);

		switch (Renderer.Device.CreateTexture(texDesc))
		{
		case .Ok(let tex): mFallbackCubemap = tex;
		case .Err: return .Err;
		}

		// Upload black pixels to each face
		uint8[4] blackPixel = .(0, 0, 0, 255);
		TextureDataLayout layout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
		Extent3D size = .(1, 1, 1);
		Span<uint8> data = .(&blackPixel, 4);

		for (uint32 face = 0; face < 6; face++)
			UploadTexture(mFallbackCubemap, data, &layout, &size, 0, face);

		// Create cube view
		TextureViewDesc viewDesc = .()
		{
			Format = .RGBA8Unorm,
			Dimension = .TextureCube,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6
		};

		switch (Renderer.Device.CreateTextureView(mFallbackCubemap, viewDesc))
		{
		case .Ok(let view): mFallbackCubemapView = view;
		case .Err: return .Err;
		}

		return .Ok;
	}

	/// Creates a procedural gradient sky cubemap matching RendererIntegrated's SkyboxRenderer.
	/// topColor: Color at zenith (straight up)
	/// horizonColor: Color at the horizon
	/// groundColor: Color when looking down (defaults to horizon/3)
	public Result<void> CreateGradientSky(Color topColor, Color horizonColor, int32 resolution = 64)
	{
		Color groundColor = Color(
			(uint8)(horizonColor.R / 2),
			(uint8)(horizonColor.G / 2),
			(uint8)(horizonColor.B / 2),
			255
		);
		return CreateGradientSkyWithGround(topColor, horizonColor, groundColor, resolution);
	}

	/// Creates a procedural gradient sky cubemap with explicit ground color.
	public Result<void> CreateGradientSkyWithGround(Color topColor, Color horizonColor, Color groundColor, int32 resolution = 64)
	{
		// Flush GPU and invalidate bind groups before destroying views
		FlushAndInvalidateBindGroups();

		// Release old owned environment map
		if (mOwnsEnvironmentMap)
		{
			if (mEnvironmentMapView != null) { delete mEnvironmentMapView; mEnvironmentMapView = null; }
			if (mEnvironmentMap != null) { delete mEnvironmentMap; mEnvironmentMap = null; }
		}

		// Create cubemap texture
		TextureDesc texDesc = .Cubemap((uint32)resolution, .RGBA8Unorm, .Sampled | .CopyDst);

		switch (Renderer.Device.CreateTexture(texDesc))
		{
		case .Ok(let tex): mEnvironmentMap = tex;
		case .Err: return .Err;
		}
		mOwnsEnvironmentMap = true;

		// Generate gradient data for each face
		int32 faceSize = resolution * resolution * 4;
		uint8[] faceData = new uint8[faceSize];
		defer delete faceData;

		TextureDataLayout layout = .()
		{
			Offset = 0,
			BytesPerRow = (uint32)(resolution * 4),
			RowsPerImage = (uint32)resolution
		};

		Extent3D size = .((uint32)resolution, (uint32)resolution, 1);

		// Cubemap face order: +X, -X, +Y, -Y, +Z, -Z
		for (int32 face = 0; face < 6; face++)
		{
			for (int32 y = 0; y < resolution; y++)
			{
				Color c;

				if (face == 2) // +Y (top/zenith)
				{
					c = topColor;
				}
				else if (face == 3) // -Y (bottom/ground)
				{
					c = groundColor;
				}
				else
				{
					// Side faces: gradient top -> horizon -> ground
					float t = (float)y / (float)(resolution - 1);

					if (t < 0.5f)
					{
						// Upper half: top to horizon
						float u = t * 2.0f;
						c = topColor.Interpolate(horizonColor, u);
					}
					else
					{
						// Lower half: horizon to ground
						float u = (t - 0.5f) * 2.0f;
						c = horizonColor.Interpolate(groundColor, u);
					}
				}

				for (int32 x = 0; x < resolution; x++)
				{
					int32 idx = (y * resolution + x) * 4;
					faceData[idx + 0] = c.R;
					faceData[idx + 1] = c.G;
					faceData[idx + 2] = c.B;
					faceData[idx + 3] = c.A;
				}
			}

			// Upload this face
			Span<uint8> data = .(faceData.Ptr, faceSize);
			UploadTexture(mEnvironmentMap, data, &layout, &size, 0, (uint32)face);
		}

		// Create cube view
		TextureViewDesc viewDesc = .()
		{
			Format = .RGBA8Unorm,
			Dimension = .TextureCube,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6
		};

		switch (Renderer.Device.CreateTextureView(mEnvironmentMap, viewDesc))
		{
		case .Ok(let view): mEnvironmentMapView = view;
		case .Err: return .Err;
		}

		mMode = .EnvironmentMap;

		// Store colors in linear space on sky params for IBL generation
		mSkyParams.ZenithColor = .(
			Math.Pow((float)topColor.R / 255.0f, 2.2f),
			Math.Pow((float)topColor.G / 255.0f, 2.2f),
			Math.Pow((float)topColor.B / 255.0f, 2.2f)
		);
		mSkyParams.HorizonColor = .(
			Math.Pow((float)horizonColor.R / 255.0f, 2.2f),
			Math.Pow((float)horizonColor.G / 255.0f, 2.2f),
			Math.Pow((float)horizonColor.B / 255.0f, 2.2f)
		);
		mSkyParams.GroundColor = .(
			Math.Pow((float)groundColor.R / 255.0f, 2.2f),
			Math.Pow((float)groundColor.G / 255.0f, 2.2f),
			Math.Pow((float)groundColor.B / 255.0f, 2.2f)
		);
		mIsExternalEnvMap = false;

		// Generate IBL maps from sky colors
		GenerateIBLMaps();

		return .Ok;
	}

	/// Ensures the sky bind group exists for the current frame and view.
	private void EnsureSkyBindGroup(int32 frameIndex)
	{
		let skyParamsBuffer = mSkyParamsBuffers[frameIndex];
		if (mSkyBindGroupLayout == null || skyParamsBuffer == null)
			return;

		// Get current frame's camera buffer
		let frameContext = Renderer.RenderFrameContext;
		if (frameContext == null)
			return;

		let cameraBuffer = frameContext.SceneUniformBuffer;
		if (cameraBuffer == null)
			return;

		// Need sampler and cubemap view
		if (mEnvSampler == null || mFallbackCubemapView == null)
			return;

		let bindGroupIndex = GetBindGroupIndex(frameIndex);

		// Delete old bind group if exists
		if (mSkyBindGroups[bindGroupIndex] != null)
		{
			delete mSkyBindGroups[bindGroupIndex];
			mSkyBindGroups[bindGroupIndex] = null;
		}

		// Pick active cubemap view (user env map or fallback)
		let cubemapView = (mEnvironmentMapView != null) ? mEnvironmentMapView : mFallbackCubemapView;

		// Create bind group entries (binding indices match register spaces: b0, b1, t0, s0)
		BindGroupEntry[4] entries = .(
			BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Buffer(1, skyParamsBuffer, 0, (uint64)ProceduralSkyParams.Size),
			BindGroupEntry.Texture(0, cubemapView),
			BindGroupEntry.Sampler(0, mEnvSampler)
		);

		BindGroupDesc desc = .()
		{
			Label = "Sky BindGroup",
			Layout = mSkyBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(desc) case .Ok(let bg))
			mSkyBindGroups[bindGroupIndex] = bg;
	}

	private void UpdateSkyParams(int32 frameIndex)
	{
		// Update time from renderer
		mSkyParams.Time = Renderer.RenderFrameContext?.TotalTime ?? 0.0f;

		// Set mode from enum (0 = Procedural, 1 = SolidColor, 2 = EnvironmentMap)
		switch (mMode)
		{
		case .Procedural: mSkyParams.Mode = 0.0f;
		case .SolidColor: mSkyParams.Mode = 1.0f;
		case .EnvironmentMap: mSkyParams.Mode = 2.0f;
		}

		// Use current frame's buffer
		let skyParamsBuffer = mSkyParamsBuffers[frameIndex];
		if (skyParamsBuffer == null)
			return;

		// Use Map/Unmap to avoid command buffer creation
		if (let ptr = skyParamsBuffer.Map())
		{
			// Bounds check: buffer size is ProceduralSkyParams.Size (96 bytes)
			Runtime.Assert(ProceduralSkyParams.Size <= (.)skyParamsBuffer.Size, scope $"ProceduralSkyParams copy size exceeds buffer size ({skyParamsBuffer.Size})");
			Internal.MemCpy(ptr, &mSkyParams, ProceduralSkyParams.Size);
			skyParamsBuffer.Unmap();
		}

		// Ensure bind group is ready for this frame
		EnsureSkyBindGroup(frameIndex);
	}

	private void ExecuteSkyPass(IRenderPassEncoder encoder, RenderView view, int32 frameIndex)
	{
		if (mSkyPipeline == null)
			return;

		// Set viewport — render to per-view SceneColor texture at (0,0), not swapchain offset
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, view.Width, view.Height);

		// Bind pipeline
		encoder.SetPipeline(mSkyPipeline);

		// Bind resources using current frame and view's bind group
		let skyBindGroup = mSkyBindGroups[GetBindGroupIndex(frameIndex)];
		if (skyBindGroup != null)
			encoder.SetBindGroup(0, skyBindGroup, default);

		// Draw fullscreen triangle using SV_VertexID (no vertex buffer needed)
		encoder.Draw(3, 1, 0, 0);
		Renderer.Stats.DrawCalls++;
	}
}

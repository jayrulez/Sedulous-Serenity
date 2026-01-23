namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Sky rendering mode.
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

	// Cubemap sampler and fallback
	private ISampler mEnvSampler ~ delete _;
	private ITexture mFallbackCubemap ~ delete _;
	private ITextureView mFallbackCubemapView ~ delete _;

	// Sky rendering (per-frame for multi-buffering)
	private IRenderPipeline mSkyPipeline ~ delete _;
	private IBuffer[RenderConfig.FrameBufferCount] mSkyParamsBuffers;
	private IBindGroupLayout mSkyBindGroupLayout ~ delete _;
	private IBindGroup[RenderConfig.FrameBufferCount] mSkyBindGroups;

	// Full-screen quad mesh (kept for potential future use, shader uses SV_VertexID)
	private IBuffer mFullscreenQuadVB ~ delete _;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => Renderer.RenderFrameContext?.FrameIndex ?? 0;

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

		BindGroupLayoutDescriptor layoutDesc = .()
		{
			Label = "Sky BindGroup Layout",
			Entries = layoutEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout): mSkyBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] bgLayouts = .(mSkyBindGroupLayout);
		PipelineLayoutDescriptor plDesc = .(bgLayouts);
		switch (Renderer.Device.CreatePipelineLayout(&plDesc))
		{
		case .Ok(let layout): mSkyPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Color targets
		ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

		// Sky uses fullscreen triangle with SV_VertexID - no vertex buffers needed
		RenderPipelineDescriptor pipelineDesc = .()
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

		switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
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
		TextureViewDescriptor viewDesc = .()
		{
			Label = "Environment Map View",
			Dimension = .TextureCube
		};

		switch (Renderer.Device.CreateTextureView(mEnvironmentMap, &viewDesc))
		{
		case .Ok(let view): mEnvironmentMapView = view;
		case .Err: return .Err;
		}

		// Generate irradiance and prefiltered maps
		// This would use compute shaders for IBL preprocessing
		GenerateIBLMaps();

		mMode = .EnvironmentMap;
		return .Ok;
	}

	private Result<void> CreateSkyParamsBuffer()
	{
		// Create per-frame sky params buffers
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			// Use Upload memory for CPU mapping (avoids command buffer for writes)
			BufferDescriptor desc = .()
			{
				Label = "Sky Params",
				Size = (uint64)ProceduralSkyParams.Size,
				Usage = .Uniform,
				MemoryAccess = .Upload // CPU-mappable
			};

			switch (Renderer.Device.CreateBuffer(&desc))
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

		BufferDescriptor desc = .()
		{
			Label = "Fullscreen Triangle",
			Size = sizeof(decltype(vertices)),
			Usage = .Vertex | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&desc))
		{
		case .Ok(let buf):
			mFullscreenQuadVB = buf;
			Renderer.Device.Queue.WriteBuffer(mFullscreenQuadVB, 0, Span<uint8>((uint8*)&vertices[0], sizeof(decltype(vertices))));
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateBRDFLut()
	{
		// Create 2D texture for BRDF integration LUT
		TextureDescriptor desc = .()
		{
			Label = "BRDF LUT",
			Width = 512,
			Height = 512,
			Depth = 1,
			Format = .RG16Float,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst  // Need CopyDst for WriteTexture
		};

		switch (Renderer.Device.CreateTexture(&desc))
		{
		case .Ok(let tex): mBRDFLut = tex;
		case .Err: return .Err;
		}

		TextureViewDescriptor viewDesc = .()
		{
			Label = "BRDF LUT View",
			Dimension = .Texture2D,
			Format = .RG16Float  // Must match texture format
		};

		switch (Renderer.Device.CreateTextureView(mBRDFLut, &viewDesc))
		{
		case .Ok(let view): mBRDFLutView = view;
		case .Err: return .Err;
		}

		// Generate BRDF LUT (CPU fallback)
		GenerateBRDFLut();

		return .Ok;
	}

	/// Generates BRDF integration LUT for IBL.
	/// This is a CPU fallback - a production implementation would use a compute shader.
	private void GenerateBRDFLut()
	{
		if (mBRDFLut == null)
			return;

		const int32 Size = 512;
		uint16[] data = new uint16[Size * Size * 2]; // RG16Float = 2 uint16 per pixel
		defer delete data;

		// Generate BRDF integration values
		for (int32 y = 0; y < Size; y++)
		{
			float roughness = (float)(y + 1) / (float)Size; // Avoid roughness = 0

			for (int32 x = 0; x < Size; x++)
			{
				float NdotV = (float)(x + 1) / (float)Size; // Avoid NdotV = 0

				// Simplified BRDF integration approximation
				// In production, this would use importance sampling
				float a = roughness * roughness;
				float a2 = a * a;

				// Approximate F0 scale and bias
				float scale = 1.0f - Math.Pow(1.0f - NdotV, 5.0f);
				float bias = Math.Pow(1.0f - NdotV, 5.0f);

				// Roughness adjustment
				scale *= (1.0f - a2 * 0.5f);
				bias *= (1.0f - a * 0.3f);

				// Clamp to valid range
				scale = Math.Clamp(scale, 0.0f, 1.0f);
				bias = Math.Clamp(bias, 0.0f, 1.0f);

				// Convert to half-float (simplified - using full precision conversion)
				int32 idx = (y * Size + x) * 2;
				data[idx] = FloatToHalf(scale);
				data[idx + 1] = FloatToHalf(bias);
			}
		}

		// Upload to texture
		var layout = TextureDataLayout()
		{
			BytesPerRow = (uint32)(Size * 4), // 2 * sizeof(uint16) per pixel
			RowsPerImage = (uint32)Size
		};
		var writeSize = Extent3D((uint32)Size, (uint32)Size, 1);
		Renderer.Device.Queue.WriteTexture(mBRDFLut, Span<uint8>((uint8*)data.Ptr, data.Count * 2), &layout, &writeSize);
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

	private void GenerateIBLMaps()
	{
		// IBL map generation would use compute shaders to:
		// 1. Generate diffuse irradiance cubemap (convolution)
		// 2. Generate prefiltered specular cubemap (roughness mips)
		// For now, these are created as black textures and will be filled
		// when SetEnvironmentMap is called with proper compute shader support.
	}

	private Result<void> CreateEnvSamplerAndFallback()
	{
		// Create sampler for cubemap sampling
		SamplerDescriptor samplerDesc = .();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Linear;
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		samplerDesc.AddressModeW = .ClampToEdge;

		switch (Renderer.Device.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler): mEnvSampler = sampler;
		case .Err: return .Err;
		}

		// Create a 1x1 black fallback cubemap
		TextureDescriptor texDesc = .Cubemap(1, .RGBA8Unorm, .Sampled | .CopyDst);

		switch (Renderer.Device.CreateTexture(&texDesc))
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
			Renderer.Device.Queue.WriteTexture(mFallbackCubemap, data, &layout, &size, 0, face);

		// Create cube view
		TextureViewDescriptor viewDesc = .()
		{
			Format = .RGBA8Unorm,
			Dimension = .TextureCube,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6
		};

		switch (Renderer.Device.CreateTextureView(mFallbackCubemap, &viewDesc))
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
			(uint8)(horizonColor.R / 3),
			(uint8)(horizonColor.G / 3),
			(uint8)(horizonColor.B / 3),
			255
		);
		return CreateGradientSkyWithGround(topColor, horizonColor, groundColor, resolution);
	}

	/// Creates a procedural gradient sky cubemap with explicit ground color.
	public Result<void> CreateGradientSkyWithGround(Color topColor, Color horizonColor, Color groundColor, int32 resolution = 64)
	{
		// Release old owned environment map
		if (mOwnsEnvironmentMap)
		{
			if (mEnvironmentMapView != null) { delete mEnvironmentMapView; mEnvironmentMapView = null; }
			if (mEnvironmentMap != null) { delete mEnvironmentMap; mEnvironmentMap = null; }
		}

		// Create cubemap texture
		TextureDescriptor texDesc = .Cubemap((uint32)resolution, .RGBA8Unorm, .Sampled | .CopyDst);

		switch (Renderer.Device.CreateTexture(&texDesc))
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
			Renderer.Device.Queue.WriteTexture(mEnvironmentMap, data, &layout, &size, 0, (uint32)face);
		}

		// Create cube view
		TextureViewDescriptor viewDesc = .()
		{
			Format = .RGBA8Unorm,
			Dimension = .TextureCube,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6
		};

		switch (Renderer.Device.CreateTextureView(mEnvironmentMap, &viewDesc))
		{
		case .Ok(let view): mEnvironmentMapView = view;
		case .Err: return .Err;
		}

		mMode = .EnvironmentMap;

		// Force bind group recreation on next frame
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mSkyBindGroups[i] != null)
			{
				delete mSkyBindGroups[i];
				mSkyBindGroups[i] = null;
			}
		}

		return .Ok;
	}

	/// Ensures the sky bind group exists for the current frame.
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

		// Delete old bind group if exists
		if (mSkyBindGroups[frameIndex] != null)
		{
			delete mSkyBindGroups[frameIndex];
			mSkyBindGroups[frameIndex] = null;
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

		BindGroupDescriptor desc = .()
		{
			Label = "Sky BindGroup",
			Layout = mSkyBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&desc) case .Ok(let bg))
			mSkyBindGroups[frameIndex] = bg;
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

		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Bind pipeline
		encoder.SetPipeline(mSkyPipeline);

		// Bind resources using current frame's bind group
		let skyBindGroup = mSkyBindGroups[frameIndex];
		if (skyBindGroup != null)
			encoder.SetBindGroup(0, skyBindGroup, default);

		// Draw fullscreen triangle using SV_VertexID (no vertex buffer needed)
		encoder.Draw(3, 1, 0, 0);
		Renderer.Stats.DrawCalls++;
	}
}

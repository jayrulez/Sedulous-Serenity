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
	private ITexture mIrradianceMap;
	private ITextureView mIrradianceMapView;
	private ITexture mPrefilteredMap;
	private ITextureView mPrefilteredMapView;
	private ITexture mBRDFLut;
	private ITextureView mBRDFLutView;

	// Sky rendering
	private IRenderPipeline mSkyPipeline ~ delete _;
	private IBuffer mSkyParamsBuffer ~ delete _;
	private IBindGroupLayout mSkyBindGroupLayout ~ delete _;
	private IBindGroup mSkyBindGroup ~ delete _;

	// Full-screen quad mesh (kept for potential future use, shader uses SV_VertexID)
	private IBuffer mFullscreenQuadVB ~ delete _;

	// Cached frame index for bind group updates
	private int32 mLastFrameIndex = -1;

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
		BindGroupLayoutEntry[2] layoutEntries = .(
			.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer }, // Camera
			.() { Binding = 1, Visibility = .Fragment, Type = .UniformBuffer } // Sky params
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
		if (mEnvironmentMapView != null) delete mEnvironmentMapView;
		if (mEnvironmentMap != null) delete mEnvironmentMap;
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

		// Upload sky params
		UpdateSkyParams();

		// Add sky rendering pass
		// Note: Must be NeverCull because render graph culling only preserves FirstWriter,
		// and ForwardOpaque is the first writer of SceneColor
		graph.AddGraphicsPass("Sky")
			.WriteColor(colorHandle, .Load, .Store) // Blend sky into existing color
			.ReadDepth(depthHandle) // Use depth for sky masking
			.NeverCull() // Don't cull - sky renders in background
			.SetExecuteCallback(new (encoder) => {
				ExecuteSkyPass(encoder, view);
			});
	}

	/// Sets an HDRI environment map.
	public Result<void> SetEnvironmentMap(ITexture envMap)
	{
		// Release old maps
		if (mEnvironmentMapView != null) { delete mEnvironmentMapView; mEnvironmentMapView = null; }
		if (mEnvironmentMap != null) { delete mEnvironmentMap; mEnvironmentMap = null; }
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
		case .Ok(let buf): mSkyParamsBuffer = buf;
		case .Err: return .Err;
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

	/// Ensures the sky bind group exists and is up to date for the current frame.
	private void EnsureSkyBindGroup()
	{
		if (mSkyBindGroupLayout == null || mSkyParamsBuffer == null)
			return;

		// Get current frame's camera buffer
		let frameContext = Renderer.RenderFrameContext;
		if (frameContext == null)
			return;

		let cameraBuffer = frameContext.SceneUniformBuffer;
		if (cameraBuffer == null)
			return;

		// Only recreate bind group if frame index changed (triple buffering)
		let currentFrameIndex = frameContext.FrameIndex;
		if (mSkyBindGroup != null && mLastFrameIndex == currentFrameIndex)
			return;

		// Release old bind group
		if (mSkyBindGroup != null)
		{
			delete mSkyBindGroup;
			mSkyBindGroup = null;
		}

		// Create bind group entries
		// Binding 0: Camera uniforms (SceneUniforms)
		// Binding 1: Sky params
		BindGroupEntry[2] entries = .(
			BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Buffer(1, mSkyParamsBuffer, 0, (uint64)ProceduralSkyParams.Size)
		);

		BindGroupDescriptor desc = .()
		{
			Label = "Sky BindGroup",
			Layout = mSkyBindGroupLayout,
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroup(&desc))
		{
		case .Ok(let bg):
			mSkyBindGroup = bg;
			mLastFrameIndex = currentFrameIndex;
		case .Err:
			return;
		}
	}

	private void UpdateSkyParams()
	{
		// Update time from renderer
		mSkyParams.Time = Renderer.RenderFrameContext?.TotalTime ?? 0.0f;

		// Set mode from enum (0 = Procedural, 1 = SolidColor)
		mSkyParams.Mode = (mMode == .SolidColor) ? 1.0f : 0.0f;

		// Use Map/Unmap to avoid command buffer creation
		if (let ptr = mSkyParamsBuffer.Map())
		{
			// Bounds check: buffer size is ProceduralSkyParams.Size (96 bytes)
			Runtime.Assert(ProceduralSkyParams.Size <= (.)mSkyParamsBuffer.Size, scope $"ProceduralSkyParams copy size exceeds buffer size ({mSkyParamsBuffer.Size})");
			Internal.MemCpy(ptr, &mSkyParams, ProceduralSkyParams.Size);
			mSkyParamsBuffer.Unmap();
		}

		// Ensure bind group is ready for this frame
		EnsureSkyBindGroup();
	}

	private void ExecuteSkyPass(IRenderPassEncoder encoder, RenderView view)
	{
		if (mSkyPipeline == null)
			return;

		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Bind pipeline
		encoder.SetPipeline(mSkyPipeline);

		// Bind resources
		if (mSkyBindGroup != null)
			encoder.SetBindGroup(0, mSkyBindGroup, default);

		// Draw fullscreen triangle using SV_VertexID (no vertex buffer needed)
		encoder.Draw(3, 1, 0, 0);
		Renderer.Stats.DrawCalls++;
	}
}

namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// GPU parameters for inject pass (must match volumetric_inject.comp.hlsl cbuffer VolumetricParams)
[CRepr]
public struct InjectParams
{
	public Matrix InvViewProjection;
	public Vector3 CameraPosition;
	public float NearPlane;
	public Vector3 VolumeSize;
	public float FarPlane;
	public Vector3 FogColor;
	public float FogDensity;
	public Vector3 AmbientLight;
	public float Anisotropy;
	public Vector3 WindDirection;
	public float NoiseScale;
	public float NoiseStrength;
	public float Time;
	public uint32 LightCount;
	public float _Padding;

	public static int Size => 160;
}

/// GPU parameters for inject pass froxel info (must match volumetric_inject.comp.hlsl cbuffer FroxelParams)
[CRepr]
public struct InjectFroxelParams
{
	public uint32 FroxelDimensionsX;
	public uint32 FroxelDimensionsY;
	public uint32 FroxelDimensionsZ;
	public uint32 _FroxelPadding;
	public Vector2 FroxelScale;
	public Vector2 FroxelBias;

	public static int Size => 32;
}

/// GPU parameters for scatter pass (must match volumetric_scatter.comp.hlsl cbuffer VolumetricParams)
[CRepr]
public struct ScatterParams
{
	public uint32 FroxelDimensionsX;
	public uint32 FroxelDimensionsY;
	public uint32 FroxelDimensionsZ;
	public uint32 _Padding;
	public float NearPlane;
	public float FarPlane;
	public float _Padding2a;
	public float _Padding2b;

	public static int Size => 32;
}

/// GPU parameters for apply pass (must match volumetric_apply.frag.hlsl cbuffer VolumetricParams)
[CRepr]
public struct ApplyParams
{
	public Matrix ViewMatrix;
	public Matrix InvProjectionMatrix;
	public float NearPlane;
	public float FarPlane;
	public float ScreenSizeX;
	public float ScreenSizeY;
	public uint32 FroxelDimensionsX;
	public uint32 FroxelDimensionsY;
	public uint32 FroxelDimensionsZ;
	public float _Padding;

	public static int Size => 160;
}

/// User-facing volumetric fog settings.
public struct VolumetricFogSettings
{
	/// Fog color.
	public Vector3 FogColor;
	/// Fog density (0-1).
	public float FogDensity;
	/// Anisotropy for phase function (-1 to 1, 0 = isotropic).
	public float Anisotropy;
	/// Noise scale for fog variation.
	public float NoiseScale;
	/// Noise strength (0-1).
	public float NoiseStrength;
	/// Ambient light contribution.
	public Vector3 AmbientLight;

	/// Default settings.
	public static Self Default => .()
	{
		FogColor = .(0.5f, 0.6f, 0.7f),
		FogDensity = 0.02f,
		Anisotropy = 0.3f,
		NoiseScale = 0.1f,
		NoiseStrength = 0.3f,
		AmbientLight = .(0.1f, 0.1f, 0.15f)
	};
}

/// Volumetric fog render feature.
/// Uses froxel-based ray marching with temporal reprojection.
public class VolumetricFogFeature : RenderFeatureBase
{
	// Froxel dimensions
	private uint32 mFroxelsX = 160;
	private uint32 mFroxelsY = 90;
	private uint32 mFroxelsZ = 64;

	// Froxel volume textures
	private ITexture mScatteringVolume;
	private ITextureView mScatteringVolumeView;
	private ITexture mIntegratedVolume;
	private ITextureView mIntegratedVolumeView;

	// Noise texture
	private ITexture mNoiseTexture;
	private ITextureView mNoiseTextureView;

	// Samplers
	private ISampler mLinearSampler;
	private ISampler mPointSampler;

	// Compute pipelines and layouts
	private IComputePipeline mInjectPipeline;
	private IComputePipeline mScatterPipeline;
	private IPipelineLayout mInjectPipelineLayout;
	private IPipelineLayout mScatterPipelineLayout;

	// Apply pipeline and layout
	private IRenderPipeline mApplyPipeline;
	private IPipelineLayout mApplyPipelineLayout;

	// Bind group layouts
	private IBindGroupLayout mInjectBindGroupLayout;
	private IBindGroupLayout mScatterBindGroupLayout;
	private IBindGroupLayout mApplyBindGroupLayout;

	// Parameter buffers
	private IBuffer mInjectParamsBuffer;
	private IBuffer mInjectFroxelParamsBuffer;
	private IBuffer mScatterParamsBuffer;
	private IBuffer mApplyParamsBuffer;

	// Per-frame bind groups (using arrays to avoid use-after-free with in-flight command buffers)
	private IBindGroup[RenderConfig.FrameBufferCount] mInjectBindGroups;
	private IBindGroup[RenderConfig.FrameBufferCount] mScatterBindGroups;
	private IBindGroup[RenderConfig.FrameBufferCount] mApplyBindGroups;

	// Depth-only view for sampling (depth/stencil textures need aspect specified)
	// Per-frame array since depth texture is transient and views are referenced by in-flight command buffers
	private ITextureView[RenderConfig.FrameBufferCount] mDepthOnlyViews;

	// Settings
	private VolumetricFogSettings mSettings = .Default;

	// Cached view data for callbacks
	private ViewContext mCurrentView;

	/// Feature name.
	public override StringView Name => "VolumetricFog";

	/// Gets or sets the fog settings.
	public ref VolumetricFogSettings Settings => ref mSettings;

	/// Gets the integrated fog volume view for use by other features (e.g., FinalOutput).
	public ITextureView IntegratedVolumeView => mIntegratedVolumeView;

	/// Gets the froxel dimensions.
	public (uint32 x, uint32 y, uint32 z) FroxelDimensions => (mFroxelsX, mFroxelsY, mFroxelsZ);

	/// Gets the linear sampler for fog sampling.
	public ISampler LinearSampler => mLinearSampler;

	/// Gets the RenderSystem for use by associated effects.
	public RenderSystem RenderSystem => mRenderer;

	/// Depends on forward opaque for depth and lighting data.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
	}

	protected override Result<void> OnInitialize(InitContext initCtx)
	{
		// Create froxel volume textures
		if (CreateFroxelVolumes(initCtx.TransferBatch) case .Err)
			return .Err;

		// Create noise texture
		if (CreateNoiseTexture(initCtx.TransferBatch) case .Err)
			return .Err;

		// Create samplers
		if (CreateSamplers() case .Err)
			return .Err;

		// Create parameter buffers
		if (CreateParamBuffers() case .Err)
			return .Err;

		// Create pipelines
		if (CreatePipelines() case .Err)
			return .Err;

		return .Ok;
	}

	protected override void OnShutdown()
	{
		let device = Renderer.Device;

		// Clean up per-frame resources
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mInjectBindGroups[i] != null)
				device.DestroyBindGroup(ref mInjectBindGroups[i]);
			if (mScatterBindGroups[i] != null)
				device.DestroyBindGroup(ref mScatterBindGroups[i]);
			if (mApplyBindGroups[i] != null)
				device.DestroyBindGroup(ref mApplyBindGroups[i]);
			if (mDepthOnlyViews[i] != null)
				device.DestroyTextureView(ref mDepthOnlyViews[i]);
		}

		// Clean up field resources
		device.DestroyTextureView(ref mScatteringVolumeView);
		device.DestroyTexture(ref mScatteringVolume);
		device.DestroyTextureView(ref mIntegratedVolumeView);
		device.DestroyTexture(ref mIntegratedVolume);
		device.DestroyTextureView(ref mNoiseTextureView);
		device.DestroyTexture(ref mNoiseTexture);
		device.DestroySampler(ref mLinearSampler);
		device.DestroySampler(ref mPointSampler);
		device.DestroyComputePipeline(ref mInjectPipeline);
		device.DestroyComputePipeline(ref mScatterPipeline);
		device.DestroyPipelineLayout(ref mInjectPipelineLayout);
		device.DestroyPipelineLayout(ref mScatterPipelineLayout);
		device.DestroyRenderPipeline(ref mApplyPipeline);
		device.DestroyPipelineLayout(ref mApplyPipelineLayout);
		device.DestroyBindGroupLayout(ref mInjectBindGroupLayout);
		device.DestroyBindGroupLayout(ref mScatterBindGroupLayout);
		device.DestroyBindGroupLayout(ref mApplyBindGroupLayout);
		device.DestroyBuffer(ref mInjectParamsBuffer);
		device.DestroyBuffer(ref mInjectFroxelParamsBuffer);
		device.DestroyBuffer(ref mScatterParamsBuffer);
		device.DestroyBuffer(ref mApplyParamsBuffer);
	}

	public override void AddPasses(RenderGraph graph, ViewContext view, RenderableList renderables)
	{
		if (!view.PostProcess.EnableVolumetricFog)
			return;

		// Check if resources are ready
		if (mInjectPipeline == null || mScatterPipeline == null ||
			mScatteringVolume == null || mIntegratedVolume == null)
			return;

		// Cache view for callbacks
		mCurrentView = view;

		// Capture frame index from view context
		let frameIndex = view.FrameIndex;

		// Update parameters
		UpdateParams(view);

		// Import froxel volumes into render graph for automatic layout management
		let scatteringHandle = graph.ImportTarget("FogScattering", mScatteringVolume, mScatteringVolumeView);
		let integratedHandle = graph.ImportTarget("FogIntegrated", mIntegratedVolume, mIntegratedVolumeView);

		// Create bind groups for this frame
		CreateFrameBindGroups(view, frameIndex);

		// Add inject pass - injects fog density and lighting into scattering volume
		graph.AddComputePass("VolumetricFog_Inject", scope (builder) => {
				builder.WriteStorage(scatteringHandle);
				builder.NeverCull();
				builder.SetComputeExecute(new /*[&]*/ (encoder) => {
					ExecuteInjectPass(encoder, frameIndex);
				});
			});

		// Add scatter/integrate pass - reads scattering, writes integrated
		graph.AddComputePass("VolumetricFog_Scatter", scope (builder) => {
				builder.ReadTexture(scatteringHandle); // Read from inject output
				builder.WriteStorage(integratedHandle);
				builder.NeverCull();
				builder.SetComputeExecute(new /*[&]*/ (encoder) => {
					ExecuteScatterPass(encoder, frameIndex);
				});
			});

		// Note: Fog application is done in PostProcessStack via VolumetricFogEffect
	}

	/// Gets or creates a depth-only view for the given depth texture.
	private ITextureView GetOrCreateDepthOnlyView(ITexture depthTexture, int32 frameIndex)
	{
		if (depthTexture == null)
			return null;

		// Destroy previous view for this frame slot (safe now since that frame's commands have completed).
		// Must recreate each frame because depth texture is transient.
		if (mDepthOnlyViews[frameIndex] != null)
			Renderer.Device.DestroyTextureView(ref mDepthOnlyViews[frameIndex]);

		// Create depth-only view
		TextureViewDesc viewDesc = .()
		{
			Label = "Depth Only View",
			Dimension = .Texture2D,
			Format = .Depth24PlusStencil8, // Match the depth format used by the render system
			Aspect = .DepthOnly
		};

		switch (Renderer.Device.CreateTextureView(depthTexture, viewDesc))
		{
		case .Ok(let view):
			mDepthOnlyViews[frameIndex] = view;
			return view;
		case .Err:
			return null;
		}
	}

	private Result<void> CreateFroxelVolumes(ITransferBatch transferBatch)
	{
		// Use RGBA32Float to match shader's RWTexture3D<float4>
		var froxelDesc = TextureDesc()
		{
			Label = "Scattering Volume",
			Width = mFroxelsX,
			Height = mFroxelsY,
			Depth = mFroxelsZ,
			Format = .RGBA32Float,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture3D,
			Usage = .Sampled | .Storage | .CopyDst // Add CopyDst for initialization
		};

		// Scattering volume
		switch (Renderer.Device.CreateTexture(froxelDesc))
		{
		case .Ok(let tex): mScatteringVolume = tex;
		case .Err: return .Err;
		}

		TextureViewDesc viewDesc = .()
		{
			Label = "Scattering Volume View",
			Dimension = .Texture3D,
			Format = .RGBA32Float
		};

		switch (Renderer.Device.CreateTextureView(mScatteringVolume, viewDesc))
		{
		case .Ok(let view): mScatteringVolumeView = view;
		case .Err: return .Err;
		}

		// Integrated volume
		froxelDesc.Label = "Integrated Volume";
		switch (Renderer.Device.CreateTexture(froxelDesc))
		{
		case .Ok(let tex): mIntegratedVolume = tex;
		case .Err: return .Err;
		}

		viewDesc.Label = "Integrated Volume View";
		switch (Renderer.Device.CreateTextureView(mIntegratedVolume, viewDesc))
		{
		case .Ok(let view): mIntegratedVolumeView = view;
		case .Err: return .Err;
		}

		// Initialize volumes with zeros to transition from UNDEFINED layout
		// Each texel is RGBA32Float = 16 bytes
		let texelCount = mFroxelsX * mFroxelsY * mFroxelsZ;
		let dataSize = texelCount * 16;
		uint8[] zeroData = new uint8[dataSize];
		defer delete zeroData;

		var layout = TextureDataLayout() { BytesPerRow = mFroxelsX * 16, RowsPerImage = mFroxelsY };
		var writeSize = Extent3D(mFroxelsX, mFroxelsY, mFroxelsZ);

		transferBatch.WriteTexture(mScatteringVolume, Span<uint8>(&zeroData[0], dataSize), layout, writeSize);
		transferBatch.WriteTexture(mIntegratedVolume, Span<uint8>(&zeroData[0], dataSize), layout, writeSize);

		return .Ok;
	}

	private Result<void> CreateNoiseTexture(ITransferBatch transferBatch)
	{
		// Create a simple 3D noise texture (16x16x16)
		const uint32 NoiseSize = 16;
		var noiseDesc = TextureDesc()
		{
			Label = "Volumetric Noise",
			Width = NoiseSize,
			Height = NoiseSize,
			Depth = NoiseSize,
			Format = .R8Unorm,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture3D,
			Usage = .Sampled | .CopyDst
		};

		switch (Renderer.Device.CreateTexture(noiseDesc))
		{
		case .Ok(let tex): mNoiseTexture = tex;
		case .Err: return .Err;
		}

		// Generate simple noise data
		uint8[] noiseData = scope uint8[NoiseSize * NoiseSize * NoiseSize];
		uint32 seed = 12345;
		for (int i = 0; i < noiseData.Count; i++)
		{
			// Simple LCG random
			seed = seed * 1103515245 + 12345;
			noiseData[i] = (uint8)((seed >> 16) & 0xFF);
		}

		var layout = TextureDataLayout() { BytesPerRow = NoiseSize, RowsPerImage = NoiseSize };
		var writeSize = Extent3D(NoiseSize, NoiseSize, NoiseSize);
		transferBatch.WriteTexture(mNoiseTexture, Span<uint8>(&noiseData[0], noiseData.Count), layout, writeSize);

		TextureViewDesc viewDesc = .()
		{
			Label = "Volumetric Noise View",
			Dimension = .Texture3D,
			Format = .R8Unorm
		};

		switch (Renderer.Device.CreateTextureView(mNoiseTexture, viewDesc))
		{
		case .Ok(let view): mNoiseTextureView = view;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateSamplers()
	{
		// Linear sampler
		SamplerDesc linearDesc = .()
		{
			Label = "Volumetric Linear Sampler",
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge,
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear
		};

		switch (Renderer.Device.CreateSampler(linearDesc))
		{
		case .Ok(let sampler): mLinearSampler = sampler;
		case .Err: return .Err;
		}

		// Point sampler
		SamplerDesc pointDesc = .()
		{
			Label = "Volumetric Point Sampler",
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge,
			MinFilter = .Nearest,
			MagFilter = .Nearest,
			MipmapFilter = .Nearest
		};

		switch (Renderer.Device.CreateSampler(pointDesc))
		{
		case .Ok(let sampler): mPointSampler = sampler;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateParamBuffers()
	{
		// Inject params buffer
		BufferDesc injectDesc = .()
		{
			Label = "Inject Params",
			Size = (uint64)InjectParams.Size,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(injectDesc))
		{
		case .Ok(let buf): mInjectParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Inject froxel params buffer
		BufferDesc injectFroxelDesc = .()
		{
			Label = "Inject Froxel Params",
			Size = (uint64)InjectFroxelParams.Size,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(injectFroxelDesc))
		{
		case .Ok(let buf): mInjectFroxelParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Scatter params buffer
		BufferDesc scatterDesc = .()
		{
			Label = "Scatter Params",
			Size = (uint64)ScatterParams.Size,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(scatterDesc))
		{
		case .Ok(let buf): mScatterParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Apply params buffer
		BufferDesc applyDesc = .()
		{
			Label = "Apply Params",
			Size = (uint64)ApplyParams.Size,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(applyDesc))
		{
		case .Ok(let buf): mApplyParamsBuffer = buf;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreatePipelines()
	{
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// ===== Inject pipeline =====
		// Layout: b0 = volumetric params, b1 = froxel params, t0 = lights, t1 = noise, u0 = scattering (RW), s0 = linear
		BindGroupLayoutEntry[6] injectEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer },       // b0: volumetric params
			.() { Binding = 1, Visibility = .Compute, Type = .UniformBuffer },       // b1: froxel params
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadOnly },       // t0: lights structured buffer (read-only)
			.() { Binding = 1, Visibility = .Compute, Type = .SampledTexture },      // t1: noise texture
			.() { Binding = 0, Visibility = .Compute, Type = .StorageTextureReadWrite }, // u0: scattering volume
			.() { Binding = 0, Visibility = .Compute, Type = .Sampler }              // s0: linear sampler
		);

		BindGroupLayoutDesc injectLayoutDesc = .()
		{
			Label = "Inject BindGroup Layout",
			Entries = injectEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(injectLayoutDesc))
		{
		case .Ok(let layout): mInjectBindGroupLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] injectLayouts = .(mInjectBindGroupLayout);
		PipelineLayoutDesc injectPLDesc = .(injectLayouts);
		switch (Renderer.Device.CreatePipelineLayout(injectPLDesc))
		{
		case .Ok(let layout): mInjectPipelineLayout = layout;
		case .Err: return .Err;
		}

		let injectResult = Renderer.ShaderSystem.GetShader("volumetric_inject", .Compute);
		if (injectResult case .Ok(let shader))
		{
			ComputePipelineDesc desc = .(mInjectPipelineLayout, shader.Module);
			desc.Label = "Volumetric Inject Pipeline";

			switch (Renderer.Device.CreateComputePipeline(desc))
			{
			case .Ok(let pipeline): mInjectPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		// ===== Scatter pipeline =====
		// Layout: b0 = params, t0 = scattering (sampled), u0 = integrated (RW)
		BindGroupLayoutEntry[3] scatterEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer },       // b0: params
			.() { Binding = 0, Visibility = .Compute, Type = .SampledTexture },      // t0: scattering (read-only)
			.() { Binding = 0, Visibility = .Compute, Type = .StorageTextureReadWrite }  // u0: integrated
		);

		BindGroupLayoutDesc scatterLayoutDesc = .()
		{
			Label = "Scatter BindGroup Layout",
			Entries = scatterEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(scatterLayoutDesc))
		{
		case .Ok(let layout): mScatterBindGroupLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] scatterLayouts = .(mScatterBindGroupLayout);
		PipelineLayoutDesc scatterPLDesc = .(scatterLayouts);
		switch (Renderer.Device.CreatePipelineLayout(scatterPLDesc))
		{
		case .Ok(let layout): mScatterPipelineLayout = layout;
		case .Err: return .Err;
		}

		let scatterResult = Renderer.ShaderSystem.GetShader("volumetric_scatter", .Compute);
		if (scatterResult case .Ok(let scatterShader))
		{
			ComputePipelineDesc desc = .(mScatterPipelineLayout, scatterShader.Module);
			desc.Label = "Volumetric Scatter Pipeline";

			switch (Renderer.Device.CreateComputePipeline(desc))
			{
			case .Ok(let pipeline): mScatterPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		// ===== Apply pipeline =====
		// Layout: b0 = params, t0 = sceneColor, t1 = sceneDepth, t2 = integrated volume, s0 = linear, s1 = point
		BindGroupLayoutEntry[6] applyEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },    // b0: params
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },   // t0: scene color
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },   // t1: scene depth
			.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture },   // t2: integrated volume
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler },          // s0: linear sampler
			.() { Binding = 1, Visibility = .Fragment, Type = .Sampler }           // s1: point sampler
		);

		BindGroupLayoutDesc applyLayoutDesc = .()
		{
			Label = "Apply BindGroup Layout",
			Entries = applyEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(applyLayoutDesc))
		{
		case .Ok(let layout): mApplyBindGroupLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] applyLayouts = .(mApplyBindGroupLayout);
		PipelineLayoutDesc applyPLDesc = .(applyLayouts);
		switch (Renderer.Device.CreatePipelineLayout(applyPLDesc))
		{
		case .Ok(let layout): mApplyPipelineLayout = layout;
		case .Err: return .Err;
		}

		let applyResult = Renderer.ShaderSystem.GetShaderPair("volumetric_apply");
		if (applyResult case .Ok(let shaders))
		{
			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float)
			);

			RenderPipelineDesc applyDesc = .()
			{
				Label = "Volumetric Apply Pipeline",
				Layout = mApplyPipelineLayout,
				Vertex = .()
				{
					Shader = .(shaders.vert.Module, "main"),
					Buffers = default
				},
				Fragment = .()
				{
					Shader = .(shaders.frag.Module, "main"),
					Targets = colorTargets
				},
				Primitive = .()
				{
					Topology = .TriangleList,
					FrontFace = .CCW,
					CullMode = .None
				},
				DepthStencil = null,
				Multisample = .()
				{
					Count = 1,
					Mask = uint32.MaxValue
				}
			};

			switch (Renderer.Device.CreateRenderPipeline(applyDesc))
			{
			case .Ok(let pipeline): mApplyPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		return .Ok;
	}

	private void UpdateParams(ViewContext view)
	{
		// Compute inverse view projection matrix
		Matrix invViewProjection = .Identity;
		Matrix.Invert(view.ViewProjectionMatrix, out invViewProjection);

		// Compute inverse projection matrix
		Matrix invProjection = .Identity;
		Matrix.Invert(view.ProjectionMatrix, out invProjection);

		// Get light count from lighting system
		uint32 lightCount = 0;
		if (Renderer.LightingSystem?.LightBuffer != null)
			lightCount = (uint32)Renderer.LightingSystem.LightBuffer.LightCount;

		// Update inject params
		InjectParams injectParams = .()
		{
			InvViewProjection = invViewProjection,
			CameraPosition = view.CameraPosition,
			NearPlane = view.NearPlane,
			VolumeSize = .((float)mFroxelsX, (float)mFroxelsY, (float)mFroxelsZ),
			FarPlane = view.FarPlane,
			FogColor = mSettings.FogColor,
			FogDensity = mSettings.FogDensity,
			AmbientLight = mSettings.AmbientLight,
			Anisotropy = mSettings.Anisotropy,
			WindDirection = .(1, 0, 0), // Default wind direction
			NoiseScale = mSettings.NoiseScale,
			NoiseStrength = mSettings.NoiseStrength,
			Time = (float)Internal.GetTickCountMicro() / 1000000.0f,
			LightCount = lightCount
		};

		TransferHelper.WriteMappedBuffer(
			mInjectParamsBuffer, 0,
			Span<uint8>((uint8*)&injectParams, InjectParams.Size)
		);

		// Update inject froxel params
		InjectFroxelParams injectFroxelParams = .()
		{
			FroxelDimensionsX = mFroxelsX,
			FroxelDimensionsY = mFroxelsY,
			FroxelDimensionsZ = mFroxelsZ,
			FroxelScale = .(1.0f / (float)mFroxelsX, 1.0f / (float)mFroxelsY),
			FroxelBias = .(0, 0)
		};

		TransferHelper.WriteMappedBuffer(
			mInjectFroxelParamsBuffer, 0,
			Span<uint8>((uint8*)&injectFroxelParams, InjectFroxelParams.Size)
		);

		// Update scatter params
		ScatterParams scatterParams = .()
		{
			FroxelDimensionsX = mFroxelsX,
			FroxelDimensionsY = mFroxelsY,
			FroxelDimensionsZ = mFroxelsZ,
			NearPlane = view.NearPlane,
			FarPlane = view.FarPlane
		};

		TransferHelper.WriteMappedBuffer(
			mScatterParamsBuffer, 0,
			Span<uint8>((uint8*)&scatterParams, ScatterParams.Size)
		);

		// Update apply params
		ApplyParams applyParams = .()
		{
			ViewMatrix = view.ViewMatrix,
			InvProjectionMatrix = invProjection,
			NearPlane = view.NearPlane,
			FarPlane = view.FarPlane,
			ScreenSizeX = (float)view.Width,
			ScreenSizeY = (float)view.Height,
			FroxelDimensionsX = mFroxelsX,
			FroxelDimensionsY = mFroxelsY,
			FroxelDimensionsZ = mFroxelsZ
		};

		TransferHelper.WriteMappedBuffer(
			mApplyParamsBuffer, 0,
			Span<uint8>((uint8*)&applyParams, ApplyParams.Size)
		);
	}

	private void CreateFrameBindGroups(ViewContext view, int32 frameIndex)
	{
		// Only create if bind group doesn't exist yet for this frame slot.
		// Using per-frame arrays avoids use-after-free with in-flight command buffers.
		// The bind groups reference frame-specific buffers which are stable handles.

		// Get light buffer from ForwardOpaqueFeature
		IBuffer lightBuffer = null;
		int lightBufferSize = 0;
		if (Renderer.LightingSystem?.LightBuffer != null)
		{
			lightBuffer = Renderer.LightingSystem.LightBuffer.GetLightDataBuffer(frameIndex);
			lightBufferSize = Math.Max(Renderer.LightingSystem.LightBuffer.LightCount, 1) * GPULight.Size;
		}

		// Create inject bind group if not already created for this frame slot
		if (mInjectBindGroups[frameIndex] == null &&
			mInjectBindGroupLayout != null && mInjectParamsBuffer != null &&
			mInjectFroxelParamsBuffer != null && lightBuffer != null &&
			mNoiseTextureView != null && mScatteringVolumeView != null && mLinearSampler != null)
		{
			BindGroupEntry[6] injectEntries = .(
				BindGroupEntry.Buffer(/*0,*/mInjectParamsBuffer, 0, (uint64)InjectParams.Size),
				BindGroupEntry.Buffer(/*1,*/mInjectFroxelParamsBuffer, 0, (uint64)InjectFroxelParams.Size),
				BindGroupEntry.Buffer(/*0,*/lightBuffer, 0, (uint64)lightBufferSize), // t0: lights
				BindGroupEntry.Texture(/*1,*/mNoiseTextureView), // t1: noise
				BindGroupEntry.Texture(/*0,*/mScatteringVolumeView), // u0: scattering
				BindGroupEntry.Sampler(/*0,*/mLinearSampler) // s0: linear sampler
			);

			BindGroupDesc injectBgDesc = .()
			{
				Label = "Inject BindGroup",
				Layout = mInjectBindGroupLayout,
				Entries = injectEntries
			};

			switch (Renderer.Device.CreateBindGroup(injectBgDesc))
			{
			case .Ok(let bg): mInjectBindGroups[frameIndex] = bg;
			case .Err: // Non-fatal
			}
		}

		// Create scatter bind group if not already created for this frame slot
		if (mScatterBindGroups[frameIndex] == null &&
			mScatterBindGroupLayout != null && mScatterParamsBuffer != null &&
			mScatteringVolumeView != null && mIntegratedVolumeView != null)
		{
			BindGroupEntry[3] scatterEntries = .(
				BindGroupEntry.Buffer(/*0,*/mScatterParamsBuffer, 0, (uint64)ScatterParams.Size),
				BindGroupEntry.Texture(/*0,*/mScatteringVolumeView),  // t0: scattering (read-only)
				BindGroupEntry.Texture(/*0,*/mIntegratedVolumeView)   // u0: integrated (RW)
			);

			BindGroupDesc scatterBgDesc = .()
			{
				Label = "Scatter BindGroup",
				Layout = mScatterBindGroupLayout,
				Entries = scatterEntries
			};

			switch (Renderer.Device.CreateBindGroup(scatterBgDesc))
			{
			case .Ok(let bg): mScatterBindGroups[frameIndex] = bg;
			case .Err: // Non-fatal
			}
		}

		// Note: Apply bind group is created inside the execute callback
		// because it needs scene color/depth views from the render graph
	}

	/// Creates the apply bind group with scene textures from the render graph.
	/// Note: Apply bind group must be recreated each frame because it references transient scene color/depth views.
	private void CreateApplyBindGroup(ITextureView sceneColorView, ITextureView sceneDepthView, int32 frameIndex)
	{

		// Clean up previous for this frame slot (must recreate because scene views are transient)
		if (mApplyBindGroups[frameIndex] != null)
			Renderer.Device.DestroyBindGroup(ref mApplyBindGroups[frameIndex]);

		if (mApplyBindGroupLayout == null || mApplyParamsBuffer == null ||
			sceneColorView == null || sceneDepthView == null ||
			mIntegratedVolumeView == null || mLinearSampler == null || mPointSampler == null)
			return;

		BindGroupEntry[6] applyEntries = .(
			BindGroupEntry.Buffer(/*0,*/mApplyParamsBuffer, 0, (uint64)ApplyParams.Size),
			BindGroupEntry.Texture(/*0,*/sceneColorView),
			BindGroupEntry.Texture(/*1,*/sceneDepthView),
			BindGroupEntry.Texture(/*2,*/mIntegratedVolumeView),
			BindGroupEntry.Sampler(/*0,*/mLinearSampler),
			BindGroupEntry.Sampler(/*1,*/mPointSampler)
		);

		BindGroupDesc applyBgDesc = .()
		{
			Label = "Apply BindGroup",
			Layout = mApplyBindGroupLayout,
			Entries = applyEntries
		};

		switch (Renderer.Device.CreateBindGroup(applyBgDesc))
		{
		case .Ok(let bg): mApplyBindGroups[frameIndex] = bg;
		case .Err: // Non-fatal
		}
	}

	private void ExecuteInjectPass(IComputePassEncoder encoder, int32 frameIndex)
	{
		let bindGroup = mInjectBindGroups[frameIndex];
		if (mInjectPipeline == null || bindGroup == null)
			return;

		encoder.SetPipeline(mInjectPipeline);
		encoder.SetBindGroup(0, bindGroup, default);

		// Dispatch - inject shader uses [numthreads(8, 8, 8)] for full 3D coverage
		let dispatchX = (mFroxelsX + 7) / 8;
		let dispatchY = (mFroxelsY + 7) / 8;
		let dispatchZ = (mFroxelsZ + 7) / 8;
		encoder.Dispatch(dispatchX, dispatchY, dispatchZ);

		Renderer.Stats.ComputeDispatches++;
	}

	private void ExecuteScatterPass(IComputePassEncoder encoder, int32 frameIndex)
	{
		let bindGroup = mScatterBindGroups[frameIndex];
		if (mScatterPipeline == null || bindGroup == null)
			return;

		encoder.SetPipeline(mScatterPipeline);
		encoder.SetBindGroup(0, bindGroup, default);

		// Dispatch - scatter shader uses [numthreads(8, 8, 1)] and marches Z internally
		let dispatchX = (mFroxelsX + 7) / 8;
		let dispatchY = (mFroxelsY + 7) / 8;
		encoder.Dispatch(dispatchX, dispatchY, 1);

		Renderer.Stats.ComputeDispatches++;
	}

	private void ExecuteApplyPass(IRenderPassEncoder encoder, ViewContext view, ITextureView sceneColorView, ITextureView sceneDepthView, int32 frameIndex)
	{
		if (mApplyPipeline == null)
			return;

		// Create bind group with current scene textures
		CreateApplyBindGroup(sceneColorView, sceneDepthView, frameIndex);

		let bindGroup = mApplyBindGroups[frameIndex];
		if (bindGroup == null)
			return;

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, view.Width, view.Height);

		encoder.SetPipeline(mApplyPipeline);
		encoder.SetBindGroup(0, bindGroup, default);

		// Draw fullscreen triangle (3 vertices, vertex shader generates positions)
		encoder.Draw(3, 1, 0, 0);
		Renderer.Stats.DrawCalls++;
	}
}

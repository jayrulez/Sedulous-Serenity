namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// GPU parameters for fog application (must match fog_apply.frag.hlsl).
[CRepr]
struct FogApplyParams
{
	public float NearPlane;
	public float FarPlane;
	public uint32 FroxelDimensionsX;
	public uint32 FroxelDimensionsY;
	public uint32 FroxelDimensionsZ;
	public float _Padding1;
	public float _Padding2;
	public float _Padding3;

	public static int Size => 32;
}

/// Post-process effect that applies volumetric fog to the scene.
/// Reads from the integrated fog volume computed by VolumetricFogFeature.
public class VolumetricFogEffect : IPostProcessEffect
{
	private VolumetricFogFeature mFogFeature;
	private IDevice mDevice;

	// Pipeline resources
	private IRenderPipeline mApplyPipeline ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IBuffer mParamsBuffer ~ delete _;
	private ISampler mPointSampler ~ delete _;

	// Per-frame bind group - recreated each frame since inputs are transient resources
	private IBindGroup mBindGroup ~ delete _;

	// Depth-only view - recreated each frame since depth texture is transient
	private ITextureView mDepthOnlyView ~ delete _;

	private bool mEnabled = true;

	/// Creates a new volumetric fog effect.
	/// @param fogFeature The VolumetricFogFeature that computes the fog volume.
	public this(VolumetricFogFeature fogFeature)
	{
		mFogFeature = fogFeature;
	}

	public StringView Name => "VolumetricFog";

	public int Priority => 10; // Early in the chain (pre-lighting)

	public bool Enabled
	{
		get => mEnabled && mFogFeature != null && mFogFeature.IntegratedVolumeView != null;
		set => mEnabled = value;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create point sampler for scene color/depth
		SamplerDescriptor pointDesc = .();
		pointDesc.Label = "Fog Point Sampler";
		pointDesc.AddressModeU = .ClampToEdge;
		pointDesc.AddressModeV = .ClampToEdge;
		pointDesc.AddressModeW = .ClampToEdge;
		pointDesc.MinFilter = .Nearest;
		pointDesc.MagFilter = .Nearest;
		pointDesc.MipmapFilter = .Nearest;

		switch (device.CreateSampler(&pointDesc))
		{
		case .Ok(let sampler): mPointSampler = sampler;
		case .Err: return .Err;
		}

		// Create params buffer
		BufferDescriptor bufDesc = .();
		bufDesc.Label = "Fog Apply Params";
		bufDesc.Size = (uint64)FogApplyParams.Size;
		bufDesc.Usage = .Uniform | .CopyDst;

		switch (device.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Create bind group layout
		// b0 = params, t0 = input color, t1 = depth, t2 = fog volume, s0 = point sampler, s1 = linear sampler
		BindGroupLayoutEntry[6] layoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler },
			.() { Binding = 1, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDescriptor layoutDesc = .();
		layoutDesc.Label = "Fog Apply Layout";
		layoutDesc.Entries = layoutEntries;

		switch (device.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor plDesc = .(layouts);
		switch (device.CreatePipelineLayout(&plDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline
		if (CreatePipeline(device) case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreatePipeline(IDevice device)
	{
		let renderSystem = mFogFeature?.RenderSystem;
		if (renderSystem == null || renderSystem.ShaderSystem == null)
			return .Ok;

		let shaderResult = renderSystem.ShaderSystem.GetShaderPair("fog_apply");
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Label = "Fog Apply Pipeline",
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = default
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
			DepthStencil = null,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		switch (device.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mApplyPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	public void Shutdown()
	{
	}

	public void AddPasses(
		RenderGraph graph,
		RenderView view,
		RGResourceHandle inputHandle,
		RGResourceHandle outputHandle,
		RGResourceHandle depthHandle)
	{
		// Check view-level fog toggle
		if (!view.PostProcess.EnableVolumetricFog)
			return;

		if (mApplyPipeline == null || mFogFeature == null)
			return;

		let fogVolumeView = mFogFeature.IntegratedVolumeView;
		if (fogVolumeView == null)
			return;

		// Get the fog volume handle from the render graph for proper barrier management
		// This was imported by VolumetricFogFeature as "FogIntegrated"
		let fogVolumeHandle = graph.GetResource("FogIntegrated");
		if (!fogVolumeHandle.IsValid)
			return;

		// Update params
		let dims = mFogFeature.FroxelDimensions;
		FogApplyParams fogParams = .();
		fogParams.NearPlane = view.NearPlane;
		fogParams.FarPlane = view.FarPlane;
		fogParams.FroxelDimensionsX = dims.x;
		fogParams.FroxelDimensionsY = dims.y;
		fogParams.FroxelDimensionsZ = dims.z;

		mDevice.Queue.WriteBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&fogParams, FogApplyParams.Size)
		);

		// Capture for callback
		RenderGraph graphRef = graph;
		RGResourceHandle inputCopy = inputHandle;
		RGResourceHandle depthCopy = depthHandle;

		graph.AddGraphicsPass("PostProcess_VolumetricFog")
			.ReadTexture(inputHandle)
			.ReadTexture(depthHandle)
			.ReadTexture(fogVolumeHandle) // Declare fog volume read for proper barrier
			.WriteColor(outputHandle, .DontCare, .Store)
			.NeverCull()
			.SetExecuteCallback(new [=] (encoder) => {
				let inputView = graphRef.GetTextureView(inputCopy);
				let depthTexture = graphRef.GetTexture(depthCopy);
				let depthView = GetOrCreateDepthOnlyView(depthTexture);
				ExecuteApply(encoder, view, inputView, depthView, fogVolumeView);
			});
	}

	private ITextureView GetOrCreateDepthOnlyView(ITexture depthTexture)
	{
		if (depthTexture == null)
			return null;

		// Always recreate depth-only view each frame since depth texture is a transient resource.
		// Caching by pointer is unsafe because transient resources are destroyed each frame,
		// and memory reuse in release builds can cause stale pointer matches.
		if (mDepthOnlyView != null)
		{
			delete mDepthOnlyView;
			mDepthOnlyView = null;
		}

		TextureViewDescriptor viewDesc = .();
		viewDesc.Label = "Fog Depth Only View";
		viewDesc.Dimension = .Texture2D;
		viewDesc.Format = .Depth24PlusStencil8;
		viewDesc.Aspect = .DepthOnly;

		switch (mDevice.CreateTextureView(depthTexture, &viewDesc))
		{
		case .Ok(let createdView):
			mDepthOnlyView = createdView;
			return createdView;
		case .Err:
			return null;
		}
	}

	private void ExecuteApply(
		IRenderPassEncoder encoder,
		RenderView view,
		ITextureView inputView,
		ITextureView depthView,
		ITextureView fogVolumeView)
	{
		if (inputView == null || depthView == null || fogVolumeView == null)
			return;

		// Always recreate bind group each frame since input/depth are transient resources.
		// Caching by pointer is unsafe because transient resources are destroyed each frame,
		// and memory reuse in release builds can cause stale pointer matches.
		let fogLinearSampler = mFogFeature.LinearSampler;
		if (mBindGroup != null)
		{
			delete mBindGroup;
			mBindGroup = null;
		}

		BindGroupEntry[6] entries = .(
			BindGroupEntry.Buffer(0, mParamsBuffer, 0, (uint64)FogApplyParams.Size),
			BindGroupEntry.Texture(0, inputView),
			BindGroupEntry.Texture(1, depthView),
			BindGroupEntry.Texture(2, fogVolumeView),
			BindGroupEntry.Sampler(0, mPointSampler),
			BindGroupEntry.Sampler(1, fogLinearSampler)
		);

		BindGroupDescriptor bgDesc = .();
		bgDesc.Label = "Fog Apply BindGroup";
		bgDesc.Layout = mBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(&bgDesc))
		{
		case .Ok(let bg): mBindGroup = bg;
		case .Err: return;
		}

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		encoder.SetPipeline(mApplyPipeline);
		encoder.SetBindGroup(0, mBindGroup, default);
		encoder.Draw(3, 1, 0, 0);

		// Update stats through feature's render system
		let renderSystem = mFogFeature?.RenderSystem;
		if (renderSystem != null)
			renderSystem.Stats.DrawCalls++;
	}
}

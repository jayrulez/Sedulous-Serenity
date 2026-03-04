namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

/// GPU parameters for SSAO generation (must match ssao.frag.hlsl cbuffer).
[CRepr]
struct SSAOParams
{
	public Matrix ProjectionMatrix;      // 64
	public Matrix InvProjectionMatrix;   // 64
	public float TexelSizeX;             // 4
	public float TexelSizeY;             // 4
	public float Radius;                 // 4
	public float Intensity;              // 4
	public float Bias;                   // 4
	public float NearPlane;              // 4
	public float FarPlane;               // 4
	public int32 SampleCount;            // 4
	public float ScreenSizeX;            // 4
	public float ScreenSizeY;            // 4
	public float _Pad0;                  // 4
	public float _Pad1;                  // 4

	public static int Size => 176;
}

/// GPU parameters for SSAO apply pass (must match ssao_apply.frag.hlsl cbuffer).
[CRepr]
struct SSAOApplyParams
{
	public float TexelSizeX;
	public float TexelSizeY;
	public float _Pad0;
	public float _Pad1;

	public static int Size => 16;
}

/// Post-process effect that applies screen-space ambient occlusion.
/// Uses hemisphere sampling with depth-reconstructed normals.
/// Two passes: AO generation (to R8 texture) and bilateral-blur apply.
public class SSAOEffect : IPostProcessEffect
{
	private RenderSystem mRenderSystem;
	private IDevice mDevice;

	// AO generation pipeline
	private IRenderPipeline mGeneratePipeline ~ delete _;
	private IPipelineLayout mGeneratePipelineLayout ~ delete _;
	private IBindGroupLayout mGenerateBindGroupLayout ~ delete _;

	// AO apply pipeline
	private IRenderPipeline mApplyPipeline ~ delete _;
	private IPipelineLayout mApplyPipelineLayout ~ delete _;
	private IBindGroupLayout mApplyBindGroupLayout ~ delete _;

	// Persistent AO texture (recreated on resize)
	private ITexture mAOTexture ~ delete _;
	private ITextureView mAOTextureView ~ delete _;
	private uint32 mAOWidth;
	private uint32 mAOHeight;

	// Buffers and samplers
	private IBuffer mParamsBuffer ~ delete _;
	private IBuffer mApplyParamsBuffer ~ delete _;
	private ISampler mPointSampler ~ delete _;

	// Per-frame bind groups
	private IBindGroup[RenderConfig.FrameBufferCount] mGenerateBindGroups;
	private IBindGroup[RenderConfig.FrameBufferCount] mApplyBindGroups;

	private bool mEnabled = true;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	/// Creates a new SSAO effect.
	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public StringView Name => "SSAO";

	public int Priority => 100; // Lighting effects range

	public bool Enabled
	{
		get => mEnabled;
		set => mEnabled = value;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create point sampler
		SamplerDescriptor samplerDesc = .();
		samplerDesc.Label = "SSAO Point Sampler";
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		samplerDesc.AddressModeW = .ClampToEdge;
		samplerDesc.MinFilter = .Nearest;
		samplerDesc.MagFilter = .Nearest;
		samplerDesc.MipmapFilter = .Nearest;

		switch (device.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler): mPointSampler = sampler;
		case .Err: return .Err;
		}

		// Create params buffers
		BufferDescriptor bufDesc = .();
		bufDesc.Label = "SSAO Params";
		bufDesc.Size = (uint64)SSAOParams.Size;
		bufDesc.Usage = .Uniform;
		bufDesc.MemoryAccess = .Upload;

		switch (device.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mParamsBuffer = buf;
		case .Err: return .Err;
		}

		bufDesc.Label = "SSAO Apply Params";
		bufDesc.Size = (uint64)SSAOApplyParams.Size;

		switch (device.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mApplyParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Create generate bind group layout: b0=params, t0=depth, t1=gbuffer, s0=point sampler
		BindGroupLayoutEntry[4] genLayoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDescriptor genLayoutDesc = .();
		genLayoutDesc.Label = "SSAO Generate BindGroup Layout";
		genLayoutDesc.Entries = genLayoutEntries;

		switch (device.CreateBindGroupLayout(&genLayoutDesc))
		{
		case .Ok(let layout): mGenerateBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create apply bind group layout: b0=applyParams, t0=sceneColor, t1=aoTexture, t2=depth, s0=point sampler
		BindGroupLayoutEntry[5] applyLayoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDescriptor applyLayoutDesc = .();
		applyLayoutDesc.Label = "SSAO Apply BindGroup Layout";
		applyLayoutDesc.Entries = applyLayoutEntries;

		switch (device.CreateBindGroupLayout(&applyLayoutDesc))
		{
		case .Ok(let layout): mApplyBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layouts
		IBindGroupLayout[1] genLayouts = .(mGenerateBindGroupLayout);
		PipelineLayoutDescriptor genPLDesc = .(genLayouts);
		switch (device.CreatePipelineLayout(&genPLDesc))
		{
		case .Ok(let layout): mGeneratePipelineLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] applyLayouts = .(mApplyBindGroupLayout);
		PipelineLayoutDescriptor applyPLDesc = .(applyLayouts);
		switch (device.CreatePipelineLayout(&applyPLDesc))
		{
		case .Ok(let layout): mApplyPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Create pipelines
		if (CreatePipelines(device) case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreatePipelines(IDevice device)
	{
		if (mRenderSystem?.ShaderSystem == null)
			return .Ok;

		// SSAO generate pipeline (outputs to R8Unorm)
		let ssaoResult = mRenderSystem.ShaderSystem.GetShaderPair("ssao");
		if (ssaoResult case .Ok(let shaders))
		{
			let (vertShader, fragShader) = shaders;
			ColorTargetState[1] colorTargets = .(.(.R8Unorm));

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "SSAO Generate Pipeline",
				Layout = mGeneratePipelineLayout,
				Vertex = .() { Shader = .(vertShader.Module, "main"), Buffers = default },
				Fragment = .() { Shader = .(fragShader.Module, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = null,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			switch (device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mGeneratePipeline = pipeline;
			case .Err: return .Err;
			}
		}

		// SSAO apply pipeline (outputs to RGBA16Float)
		let applyResult = mRenderSystem.ShaderSystem.GetShaderPair("ssao_apply");
		if (applyResult case .Ok(let applyShaders))
		{
			let (vertShader, fragShader) = applyShaders;
			ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "SSAO Apply Pipeline",
				Layout = mApplyPipelineLayout,
				Vertex = .() { Shader = .(vertShader.Module, "main"), Buffers = default },
				Fragment = .() { Shader = .(fragShader.Module, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = null,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			switch (device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mApplyPipeline = pipeline;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	/// Ensures the AO texture exists and matches the viewport size.
	private void EnsureAOTexture(uint32 width, uint32 height)
	{
		if (mAOTexture != null && mAOWidth == width && mAOHeight == height)
			return;

		// Release old
		if (mAOTextureView != null) { delete mAOTextureView; mAOTextureView = null; }
		if (mAOTexture != null) { delete mAOTexture; mAOTexture = null; }

		// Create R8Unorm AO texture
		TextureDescriptor texDesc = .();
		texDesc.Width = width;
		texDesc.Height = height;
		texDesc.Format = .R8Unorm;
		texDesc.Usage = .RenderTarget | .Sampled;
		texDesc.Dimension = .Texture2D;
		texDesc.MipLevelCount = 1;
		texDesc.SampleCount = 1;
		texDesc.Label = "SSAO AO Texture";

		if (mDevice.CreateTexture(&texDesc) case .Ok(let tex))
			mAOTexture = tex;
		else
			return;

		TextureViewDescriptor viewDesc = .();
		viewDesc.Format = .R8Unorm;
		viewDesc.Dimension = .Texture2D;
		viewDesc.BaseMipLevel = 0;
		viewDesc.MipLevelCount = 1;
		viewDesc.BaseArrayLayer = 0;
		viewDesc.ArrayLayerCount = 1;
		viewDesc.Aspect = .All;

		if (mDevice.CreateTextureView(mAOTexture, &viewDesc) case .Ok(let view))
			mAOTextureView = view;

		mAOWidth = width;
		mAOHeight = height;
	}

	public void Shutdown()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mGenerateBindGroups[i] != null) { delete mGenerateBindGroups[i]; mGenerateBindGroups[i] = null; }
			if (mApplyBindGroups[i] != null) { delete mApplyBindGroups[i]; mApplyBindGroups[i] = null; }
		}
	}

	public void AddPasses(
		RenderGraph graph,
		RenderView view,
		RGResourceHandle inputHandle,
		RGResourceHandle outputHandle,
		RGResourceHandle depthHandle)
	{
		if (mGeneratePipeline == null || mApplyPipeline == null)
			return;

		// Check SSAO enabled on world
		let world = mRenderSystem?.ActiveWorld;
		if (world == null || !world.SSAOEnabled)
			return;

		// Look up GBuffer for normals (required)
		let gbufferHandle = graph.GetResource("SceneNormalRoughness");
		if (!gbufferHandle.IsValid)
			return;

		// Ensure AO texture exists
		EnsureAOTexture(view.Width, view.Height);
		if (mAOTexture == null)
			return;

		// Compute inverse projection
		var invProj = view.ProjectionMatrix;
		Matrix.Invert(view.ProjectionMatrix, out invProj);

		// Upload SSAO params
		var ssaoParams = SSAOParams();
		ssaoParams.ProjectionMatrix = view.ProjectionMatrix;
		ssaoParams.InvProjectionMatrix = invProj;
		ssaoParams.TexelSizeX = 1.0f / (float)view.Width;
		ssaoParams.TexelSizeY = 1.0f / (float)view.Height;
		ssaoParams.Radius = world.SSAORadius;
		ssaoParams.Intensity = world.SSAOIntensity;
		ssaoParams.Bias = 0.05f;
		ssaoParams.NearPlane = view.NearPlane;
		ssaoParams.FarPlane = view.FarPlane;
		ssaoParams.SampleCount = 16;
		ssaoParams.ScreenSizeX = (float)view.Width;
		ssaoParams.ScreenSizeY = (float)view.Height;

		mDevice.Queue.WriteBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&ssaoParams, SSAOParams.Size)
		);

		// Upload apply params
		var applyParams = SSAOApplyParams();
		applyParams.TexelSizeX = 1.0f / (float)view.Width;
		applyParams.TexelSizeY = 1.0f / (float)view.Height;

		mDevice.Queue.WriteBuffer(
			mApplyParamsBuffer, 0,
			Span<uint8>((uint8*)&applyParams, SSAOApplyParams.Size)
		);

		// Import AO texture into render graph
		let aoHandle = graph.ImportTexture("SSAO_AO", mAOTexture, mAOTextureView);

		// Capture for callbacks
		RenderGraph graphRef = graph;
		RGResourceHandle depthCopy = depthHandle;
		RGResourceHandle inputCopy = inputHandle;
		RGResourceHandle aoCopy = aoHandle;
		RGResourceHandle gbufferCopy = gbufferHandle;

		// Pass 1: SSAO Generation — depth + GBuffer normals → AO texture
		graph.AddGraphicsPass("SSAO_Generate")
			.ReadTexture(depthHandle)
			.ReadTexture(gbufferHandle)
			.WriteColor(aoHandle, .DontCare, .Store)
			.NeverCull()
			.SetExecuteCallback(new [=] (encoder) => {
				let depthView = graphRef.GetDepthOnlyTextureView(depthCopy);
				let gbufferView = graphRef.GetTextureView(gbufferCopy);
				ExecuteGeneratePass(encoder, view, depthView, gbufferView);
			});

		// Pass 2: SSAO Apply — input + AO + depth → output
		graph.AddGraphicsPass("SSAO_Apply")
			.ReadTexture(inputHandle)
			.ReadTexture(aoHandle)
			.ReadTexture(depthHandle)
			.WriteColor(outputHandle, .DontCare, .Store)
			.NeverCull()
			.SetExecuteCallback(new [=] (encoder) => {
				let inView = graphRef.GetTextureView(inputCopy);
				let aoView = graphRef.GetTextureView(aoCopy);
				let dView = graphRef.GetDepthOnlyTextureView(depthCopy);
				ExecuteApplyPass(encoder, view, inView, aoView, dView);
			});
	}

	private void ExecuteGeneratePass(IRenderPassEncoder encoder, RenderView view, ITextureView depthView, ITextureView gbufferView)
	{
		if (depthView == null || gbufferView == null)
			return;

		let frameIndex = FrameIndex;

		// Recreate bind group per frame
		if (mGenerateBindGroups[frameIndex] != null)
		{
			delete mGenerateBindGroups[frameIndex];
			mGenerateBindGroups[frameIndex] = null;
		}

		BindGroupEntry[4] entries = .(
			BindGroupEntry.Buffer(0, mParamsBuffer, 0, (uint64)SSAOParams.Size),
			BindGroupEntry.Texture(0, depthView),
			BindGroupEntry.Texture(1, gbufferView),
			BindGroupEntry.Sampler(0, mPointSampler)
		);

		BindGroupDescriptor bgDesc = .();
		bgDesc.Label = "SSAO Generate BindGroup";
		bgDesc.Layout = mGenerateBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(&bgDesc))
		{
		case .Ok(let bg): mGenerateBindGroups[frameIndex] = bg;
		case .Err: return;
		}

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		encoder.SetPipeline(mGeneratePipeline);
		encoder.SetBindGroup(0, mGenerateBindGroups[frameIndex], default);
		encoder.Draw(3, 1, 0, 0);

		if (mRenderSystem != null)
			mRenderSystem.Stats.DrawCalls++;
	}

	private void ExecuteApplyPass(IRenderPassEncoder encoder, RenderView view,
		ITextureView inputView, ITextureView aoView, ITextureView depthView)
	{
		if (inputView == null || aoView == null || depthView == null)
			return;

		let frameIndex = FrameIndex;

		// Recreate bind group per frame
		if (mApplyBindGroups[frameIndex] != null)
		{
			delete mApplyBindGroups[frameIndex];
			mApplyBindGroups[frameIndex] = null;
		}

		BindGroupEntry[5] entries = .(
			BindGroupEntry.Buffer(0, mApplyParamsBuffer, 0, (uint64)SSAOApplyParams.Size),
			BindGroupEntry.Texture(0, inputView),
			BindGroupEntry.Texture(1, aoView),
			BindGroupEntry.Texture(2, depthView),
			BindGroupEntry.Sampler(0, mPointSampler)
		);

		BindGroupDescriptor bgDesc = .();
		bgDesc.Label = "SSAO Apply BindGroup";
		bgDesc.Layout = mApplyBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(&bgDesc))
		{
		case .Ok(let bg): mApplyBindGroups[frameIndex] = bg;
		case .Err: return;
		}

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		encoder.SetPipeline(mApplyPipeline);
		encoder.SetBindGroup(0, mApplyBindGroups[frameIndex], default);
		encoder.Draw(3, 1, 0, 0);

		if (mRenderSystem != null)
			mRenderSystem.Stats.DrawCalls++;
	}
}

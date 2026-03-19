namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// GPU parameters for tonemapping (must match tonemap.frag.hlsl cbuffer).
[CRepr]
struct TonemapParams
{
	public float Exposure;
	public int32 Operator;
	public float _Pad0;
	public float _Pad1;

	public static int Size => 16;
}

/// Post-process effect that applies configurable tonemapping.
/// Supports ACES, Reinhard, and Uncharted2 operators.
public class TonemapEffect : IPostProcessEffect
{
	private RenderSystem mRenderSystem;
	private IDevice mDevice;

	// Pipeline resources
	private IRenderPipeline mPipeline ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IBuffer mParamsBuffer ~ delete _;
	private ISampler mLinearSampler ~ delete _;

	// Per-frame bind groups
	private IBindGroup[RenderConfig.FrameBufferCount] mBindGroups;

	private bool mEnabled = true;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	/// Creates a new tonemap effect.
	/// @param renderSystem The render system (for frame context and shader access).
	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public StringView Name => "Tonemap";

	public int Priority => 400; // Final adjustment range

	public bool Enabled
	{
		get => mEnabled;
		set => mEnabled = value;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create linear sampler
		SamplerDesc samplerDesc = .();
		samplerDesc.Label = "Tonemap Linear Sampler";
		samplerDesc.AddressU = .ClampToEdge;
		samplerDesc.AddressV = .ClampToEdge;
		samplerDesc.AddressW = .ClampToEdge;
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Nearest;

		switch (device.CreateSampler(samplerDesc))
		{
		case .Ok(let sampler): mLinearSampler = sampler;
		case .Err: return .Err;
		}

		// Create params buffer
		BufferDesc bufDesc = .();
		bufDesc.Label = "Tonemap Params";
		bufDesc.Size = (uint64)TonemapParams.Size;
		bufDesc.Usage = .Uniform;
		bufDesc.MemoryAccess = .CpuToGpu;

		switch (device.CreateBuffer(bufDesc))
		{
		case .Ok(let buf): mParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Create bind group layout: b0=params, t0=source, s0=sampler
		BindGroupLayoutEntry[3] layoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDesc layoutDesc = .();
		layoutDesc.Label = "Tonemap BindGroup Layout";
		layoutDesc.Entries = layoutEntries;

		switch (device.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDesc plDesc = .(layouts);
		switch (device.CreatePipelineLayout(plDesc))
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
		if (mRenderSystem?.ShaderSystem == null)
			return .Ok;

		let shaderResult = mRenderSystem.ShaderSystem.GetShaderPair("tonemap");
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "Tonemap Pipeline",
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

		switch (device.CreateRenderPipeline(pipelineDesc))
		{
		case .Ok(let pipeline): mPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	public void Shutdown()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mBindGroups[i] != null)
			{
				delete mBindGroups[i];
				mBindGroups[i] = null;
			}
		}
	}

	public void AddPasses(
		RenderGraph graph,
		RenderView view,
		RGResourceHandle inputHandle,
		RGResourceHandle outputHandle,
		RGResourceHandle depthHandle)
	{
		if (mPipeline == null)
			return;

		// Read tonemap settings from active world
		let world = mRenderSystem?.ActiveWorld;
		float exposure = world?.Exposure ?? 1.0f;
		TonemapOperator tonemapOp = world?.TonemapOperator ?? .ACES;

		// Upload params
		var tonemapParams = TonemapParams();
		tonemapParams.Exposure = exposure;
		tonemapParams.Operator = (int32)tonemapOp;

		mDevice.Queue.WriteMappedBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&tonemapParams, TonemapParams.Size)
		);

		// Capture for callback
		RenderGraph graphRef = graph;
		RGResourceHandle inputCopy = inputHandle;

		graph.AddGraphicsPass("PostProcess_Tonemap")
			.ReadTexture(inputHandle)
			.WriteColor(outputHandle, .DontCare, .Store)
			.NeverCull()
			.SetExecuteCallback(new [=] (encoder) => {
				let inputView = graphRef.GetTextureView(inputCopy);
				ExecutePass(encoder, view, inputView);
			});
	}

	private void ExecutePass(IRenderPassEncoder encoder, RenderView view, ITextureView inputView)
	{
		if (inputView == null)
			return;

		let frameIndex = FrameIndex;

		// Recreate bind group per frame (input is transient)
		if (mBindGroups[frameIndex] != null)
		{
			delete mBindGroups[frameIndex];
			mBindGroups[frameIndex] = null;
		}

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, mParamsBuffer, 0, (uint64)TonemapParams.Size),
			BindGroupEntry.Texture(0, inputView),
			BindGroupEntry.Sampler(0, mLinearSampler)
		);

		BindGroupDesc bgDesc = .();
		bgDesc.Label = "Tonemap BindGroup";
		bgDesc.Layout = mBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg): mBindGroups[frameIndex] = bg;
		case .Err: return;
		}

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissor(0, 0, view.Width, view.Height);

		encoder.SetPipeline(mPipeline);
		encoder.SetBindGroup(0, mBindGroups[frameIndex], default);
		encoder.Draw(3, 1, 0, 0);

		if (mRenderSystem != null)
			mRenderSystem.Stats.DrawCalls++;
	}
}

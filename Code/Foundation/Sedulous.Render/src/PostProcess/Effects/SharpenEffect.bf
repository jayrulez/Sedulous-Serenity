namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// GPU parameters for sharpening (must match sharpen.frag.hlsl cbuffer).
[CRepr]
struct SharpenParams
{
	public float Intensity;
	public float TexelSizeX;
	public float TexelSizeY;
	public float _Pad;

	public static int Size => 16;
}

/// Post-process effect that applies CAS-style adaptive sharpening.
/// Useful to counteract TAA softening.
public class SharpenEffect : IPostProcessEffect
{
	private RenderSystem mRenderSystem;
	private IDevice mDevice;

	// Pipeline resources
	private IRenderPipeline mPipeline ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IBuffer mParamsBuffer ~ delete _;
	private ISampler mPointSampler ~ delete _;

	// Per-frame bind groups
	private IBindGroup[RenderConfig.FrameBufferCount] mBindGroups;

	private bool mEnabled = true;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	/// Creates a new sharpen effect.
	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public StringView Name => "Sharpen";

	public int Priority => 320; // Anti-aliasing range, after FXAA

	public bool Enabled
	{
		get => mEnabled;
		set => mEnabled = value;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create point sampler
		SamplerDesc samplerDesc = .();
		samplerDesc.Label = "Sharpen Point Sampler";
		samplerDesc.AddressU = .ClampToEdge;
		samplerDesc.AddressV = .ClampToEdge;
		samplerDesc.AddressW = .ClampToEdge;
		samplerDesc.MinFilter = .Nearest;
		samplerDesc.MagFilter = .Nearest;
		samplerDesc.MipmapFilter = .Nearest;

		switch (device.CreateSampler(samplerDesc))
		{
		case .Ok(let sampler): mPointSampler = sampler;
		case .Err: return .Err;
		}

		// Create params buffer
		BufferDesc bufDesc = .();
		bufDesc.Label = "Sharpen Params";
		bufDesc.Size = (uint64)SharpenParams.Size;
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
		layoutDesc.Label = "Sharpen BindGroup Layout";
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

		let shaderResult = mRenderSystem.ShaderSystem.GetShaderPair("sharpen");
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "Sharpen Pipeline",
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

		// Check sharpen enabled on world
		let world = mRenderSystem?.ActiveWorld;
		if (world == null || !world.SharpenEnabled)
			return;

		// Upload params
		var sharpenParams = SharpenParams();
		sharpenParams.Intensity = world.SharpenIntensity;
		sharpenParams.TexelSizeX = 1.0f / (float)view.Width;
		sharpenParams.TexelSizeY = 1.0f / (float)view.Height;

		mDevice.Queue.WriteMappedBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&sharpenParams, SharpenParams.Size)
		);

		// Capture for callback
		RenderGraph graphRef = graph;
		RGResourceHandle inputCopy = inputHandle;

		graph.AddGraphicsPass("PostProcess_Sharpen")
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
			BindGroupEntry.Buffer(0, mParamsBuffer, 0, (uint64)SharpenParams.Size),
			BindGroupEntry.Texture(0, inputView),
			BindGroupEntry.Sampler(0, mPointSampler)
		);

		BindGroupDesc bgDesc = .();
		bgDesc.Label = "Sharpen BindGroup";
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

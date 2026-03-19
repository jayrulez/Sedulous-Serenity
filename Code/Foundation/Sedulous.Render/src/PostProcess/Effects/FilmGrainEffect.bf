namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// GPU parameters for film grain (must match film_grain.frag.hlsl cbuffer).
[CRepr]
struct FilmGrainParams
{
	public float Intensity;
	public float Time;
	public float ScreenSizeX;
	public float ScreenSizeY;

	public static int Size => 16;
}

/// Post-process effect that adds animated film grain noise.
/// Grain is stronger in shadows (luminance-weighted).
public class FilmGrainEffect : IPostProcessEffect
{
	private RenderSystem mRenderSystem;
	private IDevice mDevice;

	private IRenderPipeline mPipeline ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IBuffer mParamsBuffer ~ delete _;
	private ISampler mLinearSampler ~ delete _;

	private IBindGroup[RenderConfig.FrameBufferCount] mBindGroups;

	private bool mEnabled = true;

	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public StringView Name => "FilmGrain";

	public int Priority => 410;

	public bool Enabled
	{
		get => mEnabled;
		set => mEnabled = value;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		SamplerDesc samplerDesc = .();
		samplerDesc.Label = "FilmGrain Linear Sampler";
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

		BufferDesc bufDesc = .();
		bufDesc.Label = "FilmGrain Params";
		bufDesc.Size = (uint64)FilmGrainParams.Size;
		bufDesc.Usage = .Uniform;
		bufDesc.MemoryAccess = .CpuToGpu;

		switch (device.CreateBuffer(bufDesc))
		{
		case .Ok(let buf): mParamsBuffer = buf;
		case .Err: return .Err;
		}

		BindGroupLayoutEntry[3] layoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDesc layoutDesc = .();
		layoutDesc.Label = "FilmGrain BindGroup Layout";
		layoutDesc.Entries = layoutEntries;

		switch (device.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDesc plDesc = .(layouts);
		switch (device.CreatePipelineLayout(plDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		if (CreatePipeline(device) case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreatePipeline(IDevice device)
	{
		if (mRenderSystem?.ShaderSystem == null)
			return .Ok;

		let shaderResult = mRenderSystem.ShaderSystem.GetShaderPair("film_grain");
		if (shaderResult case .Err)
			return .Ok;

		let (vertShader, fragShader) = shaderResult.Value;

		ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "FilmGrain Pipeline",
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

		let world = mRenderSystem?.ActiveWorld;
		if (world == null || !world.FilmGrainEnabled)
			return;

		var grainParams = FilmGrainParams();
		grainParams.Intensity = world.FilmGrainIntensity;
		grainParams.Time = mRenderSystem.RenderFrameContext?.TotalTime ?? 0.0f;
		grainParams.ScreenSizeX = (float)view.Width;
		grainParams.ScreenSizeY = (float)view.Height;

		mDevice.Queue.WriteMappedBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&grainParams, FilmGrainParams.Size)
		);

		RenderGraph graphRef = graph;
		RGResourceHandle inputCopy = inputHandle;

		graph.AddGraphicsPass("PostProcess_FilmGrain")
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

		if (mBindGroups[frameIndex] != null)
		{
			delete mBindGroups[frameIndex];
			mBindGroups[frameIndex] = null;
		}

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, mParamsBuffer, 0, (uint64)FilmGrainParams.Size),
			BindGroupEntry.Texture(0, inputView),
			BindGroupEntry.Sampler(0, mLinearSampler)
		);

		BindGroupDesc bgDesc = .();
		bgDesc.Label = "FilmGrain BindGroup";
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

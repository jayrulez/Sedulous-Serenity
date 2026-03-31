namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;

using internal Sedulous.Renderer;

/// Tonemap curve selection.
public enum TonemapMode : uint32
{
	ACES = 0,
	Reinhard = 1,
	AgX = 2
}

/// Tonemap params UBO (matches tonemap.hlsl cbuffer).
[CRepr]
struct TonemapParams
{
	public float Exposure;
	public uint32 TonemapMode;
	public float[2] _pad;
}

/// Tonemapping post-process effect.
/// Applies exposure + tonemap curve to HDR input → LDR output.
/// Should be the last effect in the chain (highest priority number).
public class TonemapEffect : IPostProcessEffect
{
	private IDevice mDevice;
	private IRenderPipeline mPipeline;
	private IPipelineLayout mPipelineLayout;
	private IBindGroupLayout mBindGroupLayout;
	private ISampler mSampler;
	private IBuffer mParamsBuffer;
	private void* mParamsPtr;

	public TonemapMode Mode = .ACES;

	public StringView Name => "Tonemap";
	public int32 Priority => 1000;
	public bool Enabled { get; set; } = true;

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;

		if (initCtx.Shaders.RegisterShader("postprocess/tonemap") case .Err)
			return .Err;

		// Sampler
		let samplerResult = mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear, MagFilter = .Linear, MipmapFilter = .Linear,
			AddressU = .ClampToEdge, AddressV = .ClampToEdge, AddressW = .ClampToEdge,
			Label = "Tonemap_Sampler"
		});
		if (samplerResult case .Err) return .Err;
		mSampler = samplerResult.Value;

		// Bind group layout: t0=input, s1=sampler, b2=params
		BindGroupLayoutEntry[3] entries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(1, .Fragment),
			BindGroupLayoutEntry.UniformBuffer(2, .Fragment)
		);
		let layoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
			{ Entries = entries, Label = "Tonemap_Layout" });
		if (layoutResult case .Err) return .Err;
		mBindGroupLayout = layoutResult.Value;

		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		let pipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
			{ BindGroupLayouts = layouts, Label = "Tonemap_PipeLayout" });
		if (pipeLayoutResult case .Err) return .Err;
		mPipelineLayout = pipeLayoutResult.Value;

		let vs = initCtx.Shaders.GetCompiledShader("postprocess/tonemap", .Vertex);
		if (vs case .Err)
		{
			Console.WriteLine("ERROR: Failed to compile tonemap vertex shader");
			return .Err;
		}
		let fs = initCtx.Shaders.GetCompiledShader("postprocess/tonemap", .Fragment);
		if (fs case .Err)
		{
			Console.WriteLine("ERROR: Failed to compile tonemap fragment shader");
			return .Err;
		}

		var colorTarget = ColorTargetState() { Format = .RGBA16Float };
		let pipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mPipelineLayout,
			Vertex = .() { Shader = .(vs.Value, "VSMain" ), Buffers = default },
			Fragment = .() { Shader = .(fs.Value, "PSMain" ) , Targets = Span<ColorTargetState>(&colorTarget, 1) },
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			DepthStencil = DepthStencilState.Disabled(.Undefined),
			Multisample = .() { Count = 1 },
			Label = "Tonemap_Pipeline"
		});
		if (pipeResult case .Err) return .Err;
		mPipeline = pipeResult.Value;

		// Params UBO
		let paramsResult = mDevice.CreateBuffer(BufferDesc()
		{
			Size = (uint64)sizeof(TonemapParams),
			Usage = .Uniform,
			Memory = .CpuToGpu,
			Label = "Tonemap_Params"
		});
		if (paramsResult case .Err) return .Err;
		mParamsBuffer = paramsResult.Value;
		mParamsPtr = mParamsBuffer.Map();

		return .Ok;
	}

	public RGTexture OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx,
		PostProcessInputs inputs)
	{
		let renderW = viewCtx.RenderWidth;
		let renderH = viewCtx.RenderHeight;
		let device = mDevice;
		let pipeline = mPipeline;
		let bindGroupLayout = mBindGroupLayout;
		let sampler = mSampler;
		let paramsBuffer = mParamsBuffer;
		let inputTex = inputs.SceneColor;

		// Update params
		if (mParamsPtr != null)
		{
			var p = TonemapParams();
			p.Exposure = viewCtx.Exposure;
			p.TonemapMode = (uint32)Mode;
			Internal.MemCpy(mParamsPtr, &p, sizeof(TonemapParams));
		}

		RGTexture outputTex = default;

		graph.AddPass("Tonemap", .Graphics, scope [&] (builder) =>
		{
			outputTex = builder.CreateTexture(
				RGTextureDesc.RenderTarget(.RGBA16Float, renderW, renderH, 1, "Tonemapped"));

			builder.ReadTexture(inputTex, .Fragment);
			builder.WriteRenderTarget(outputTex, 0, .DontCare, .Store);
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let inputView = registry.GetTextureView(inputTex);
				if (inputView == null) return;

				var bgEntries = BindGroupEntry[3](
					BindGroupEntry.Texture(inputView),
					BindGroupEntry.Sampler(sampler),
					BindGroupEntry.Buffer(paramsBuffer, 0, (uint64)sizeof(TonemapParams))
				);
				let bgResult = device.CreateBindGroup(BindGroupDesc()
					{ Layout = bindGroupLayout, Entries = bgEntries, Label = "Tonemap_BG" });
				if (bgResult case .Err) return;
				var bindGroup = bgResult.Value;

				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);
				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0, 1);
				rp.SetScissor(0, 0, renderW, renderH);
				rp.SetPipeline(pipeline);
				rp.SetBindGroup(0, bindGroup);
				rp.Draw(3, 1, 0, 0);
				rp.End();

				// Safe to destroy immediately — DX12 staging has a copy of the descriptors
				device.DestroyBindGroup(ref bindGroup);
			});
		});

		return outputTex;
	}

	public void OnShutdown(IDevice device)
	{
		if (mPipeline != null) device.DestroyRenderPipeline(ref mPipeline);
		if (mPipelineLayout != null) device.DestroyPipelineLayout(ref mPipelineLayout);
		if (mBindGroupLayout != null) device.DestroyBindGroupLayout(ref mBindGroupLayout);
		if (mSampler != null) device.DestroySampler(ref mSampler);
		if (mParamsBuffer != null) { mParamsBuffer.Unmap(); device.DestroyBuffer(ref mParamsBuffer); }
	}
}

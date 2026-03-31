namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// Downsample params UBO (matches bloom_downsample.hlsl cbuffer).
[CRepr]
struct BloomDownsampleParams
{
	public float Threshold;
	public float SoftThreshold;
	public float Intensity;
	public uint32 MipLevel;
	public Vector2 TexelSize;
	public float[2] _pad;
}

/// Upsample params UBO (matches bloom_upsample.hlsl cbuffer).
[CRepr]
struct BloomUpsampleParams
{
	public float Threshold;
	public float SoftThreshold;
	public float Intensity;
	public uint32 MipLevel;
	public Vector2 TexelSize;
	public uint32 HasPrevUpsample;
	public float _pad;
}

/// Composite params UBO (matches bloom_composite.hlsl cbuffer).
[CRepr]
struct BloomCompositeParams
{
	public float Intensity;
	public float[3] _pad;
}

/// Bloom post-process effect.
/// Extracts bright pixels, progressively downsamples with 13-tap filter,
/// upsamples with 9-tap tent, and composites back.
public class BloomEffect : IPostProcessEffect
{
	public const int MipCount = 4;  // 4 downsample levels (1/2, 1/4, 1/8, 1/16)

	private IDevice mDevice;

	// Downsample pipeline
	private IRenderPipeline mDownsamplePipeline;
	private IPipelineLayout mDownsamplePipelineLayout;
	private IBindGroupLayout mDownsampleBindGroupLayout;

	// Upsample pipeline
	private IRenderPipeline mUpsamplePipeline;
	private IPipelineLayout mUpsamplePipelineLayout;
	private IBindGroupLayout mUpsampleBindGroupLayout;

	// Composite pipeline
	private IRenderPipeline mCompositePipeline;
	private IPipelineLayout mCompositePipelineLayout;
	private IBindGroupLayout mCompositeBindGroupLayout;

	// Shared
	private ISampler mLinearSampler;

	// Per-pass param buffers (CpuToGpu mapped buffers can't be shared across
	// passes — all execute callbacks run before GPU starts, overwriting each other).
	// 4 downsample + 3 upsample + 1 composite = 8 passes max
	public const int MaxPasses = MipCount + (MipCount - 1) + 1;
	private IBuffer[MaxPasses] mParamsBuffers;
	private void*[MaxPasses] mParamsPtrs;

	// Configuration
	public float Threshold = 1.0f;
	public float SoftThreshold = 0.5f;
	public float Intensity = 0.5f;

	public StringView Name => "Bloom";
	public int32 Priority => 100;
	public bool Enabled { get; set; } = true;

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;

		if (initCtx.Shaders.RegisterShader("postprocess/bloom_downsample") case .Err) return .Err;
		if (initCtx.Shaders.RegisterShader("postprocess/bloom_upsample") case .Err) return .Err;
		if (initCtx.Shaders.RegisterShader("postprocess/bloom_composite") case .Err) return .Err;

		// Shared sampler
		let samplerResult = mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear, MagFilter = .Linear, MipmapFilter = .Linear,
			AddressU = .ClampToEdge, AddressV = .ClampToEdge, AddressW = .ClampToEdge,
			Label = "Bloom_Sampler"
		});
		if (samplerResult case .Err) return .Err;
		mLinearSampler = samplerResult.Value;

		// Per-pass param buffers
		for (int i = 0; i < MaxPasses; i++)
		{
			let paramsResult = mDevice.CreateBuffer(BufferDesc()
			{
				Size = 256,
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "Bloom_Params"
			});
			if (paramsResult case .Err) return .Err;
			mParamsBuffers[i] = paramsResult.Value;
			mParamsPtrs[i] = mParamsBuffers[i].Map();
		}

		// --- Downsample pipeline: t0=Input, s1=LinearSampler, b2=Params ---
		if (CreateDownsamplePipeline(initCtx) case .Err) return .Err;

		// --- Upsample pipeline: t0=CurrentMip, t1=PrevUpsample, s2=LinearSampler, b3=Params ---
		if (CreateUpsamplePipeline(initCtx) case .Err) return .Err;

		// --- Composite pipeline: t0=SceneColor, t1=BloomResult, s2=LinearSampler, b3=Params ---
		if (CreateCompositePipeline(initCtx) case .Err) return .Err;

		return .Ok;
	}

	private Result<void> CreateDownsamplePipeline(InitContext initCtx)
	{
		BindGroupLayoutEntry[3] entries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(1, .Fragment),
			BindGroupLayoutEntry.UniformBuffer(2, .Fragment)
		);
		let layoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
			{ Entries = entries, Label = "Bloom_Down_Layout" });
		if (layoutResult case .Err) return .Err;
		mDownsampleBindGroupLayout = layoutResult.Value;

		IBindGroupLayout[1] layouts = .(mDownsampleBindGroupLayout);
		let pipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
			{ BindGroupLayouts = layouts, Label = "Bloom_Down_PipeLayout" });
		if (pipeLayoutResult case .Err) return .Err;
		mDownsamplePipelineLayout = pipeLayoutResult.Value;

		let vs = initCtx.Shaders.GetCompiledShader("postprocess/bloom_downsample", .Vertex);
		if (vs case .Err) { Console.WriteLine("ERROR: bloom_downsample VS compile failed"); return .Err; }
		let fs = initCtx.Shaders.GetCompiledShader("postprocess/bloom_downsample", .Fragment);
		if (fs case .Err) { Console.WriteLine("ERROR: bloom_downsample FS compile failed"); return .Err; }

		var colorTarget = ColorTargetState() { Format = .RGBA16Float };
		let pipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mDownsamplePipelineLayout,
			Vertex = .() { Shader = .(vs.Value, "VSMain" ), Buffers = default },
			Fragment = .() { Shader = .(fs.Value, "PSMain" ) , Targets = Span<ColorTargetState>(&colorTarget, 1) },
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			DepthStencil = DepthStencilState.Disabled(.Undefined),
			Multisample = .() { Count = 1 },
			Label = "Bloom_DownsamplePipeline"
		});
		if (pipeResult case .Err) return .Err;
		mDownsamplePipeline = pipeResult.Value;
		return .Ok;
	}

	private Result<void> CreateUpsamplePipeline(InitContext initCtx)
	{
		BindGroupLayoutEntry[4] entries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.SampledTexture(1, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(2, .Fragment),
			BindGroupLayoutEntry.UniformBuffer(3, .Fragment)
		);
		let layoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
			{ Entries = entries, Label = "Bloom_Up_Layout" });
		if (layoutResult case .Err) return .Err;
		mUpsampleBindGroupLayout = layoutResult.Value;

		IBindGroupLayout[1] layouts = .(mUpsampleBindGroupLayout);
		let pipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
			{ BindGroupLayouts = layouts, Label = "Bloom_Up_PipeLayout" });
		if (pipeLayoutResult case .Err) return .Err;
		mUpsamplePipelineLayout = pipeLayoutResult.Value;

		let vs = initCtx.Shaders.GetCompiledShader("postprocess/bloom_upsample", .Vertex);
		if (vs case .Err) { Console.WriteLine("ERROR: bloom_upsample VS compile failed"); return .Err; }
		let fs = initCtx.Shaders.GetCompiledShader("postprocess/bloom_upsample", .Fragment);
		if (fs case .Err) { Console.WriteLine("ERROR: bloom_upsample FS compile failed"); return .Err; }

		var colorTarget = ColorTargetState() { Format = .RGBA16Float };
		let pipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mUpsamplePipelineLayout,
			Vertex = .() { Shader = .(vs.Value, "VSMain" ), Buffers = default },
			Fragment = .() { Shader = .(fs.Value, "PSMain" ) , Targets = Span<ColorTargetState>(&colorTarget, 1) },
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			DepthStencil = DepthStencilState.Disabled(.Undefined),
			Multisample = .() { Count = 1 },
			Label = "Bloom_UpsamplePipeline"
		});
		if (pipeResult case .Err) return .Err;
		mUpsamplePipeline = pipeResult.Value;
		return .Ok;
	}

	private Result<void> CreateCompositePipeline(InitContext initCtx)
	{
		BindGroupLayoutEntry[4] entries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.SampledTexture(1, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(2, .Fragment),
			BindGroupLayoutEntry.UniformBuffer(3, .Fragment)
		);
		let layoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
			{ Entries = entries, Label = "Bloom_Comp_Layout" });
		if (layoutResult case .Err) return .Err;
		mCompositeBindGroupLayout = layoutResult.Value;

		IBindGroupLayout[1] layouts = .(mCompositeBindGroupLayout);
		let pipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
			{ BindGroupLayouts = layouts, Label = "Bloom_Comp_PipeLayout" });
		if (pipeLayoutResult case .Err) return .Err;
		mCompositePipelineLayout = pipeLayoutResult.Value;

		let vs = initCtx.Shaders.GetCompiledShader("postprocess/bloom_composite", .Vertex);
		if (vs case .Err) { Console.WriteLine("ERROR: bloom_composite VS compile failed"); return .Err; }
		let fs = initCtx.Shaders.GetCompiledShader("postprocess/bloom_composite", .Fragment);
		if (fs case .Err) { Console.WriteLine("ERROR: bloom_composite FS compile failed"); return .Err; }

		var colorTarget = ColorTargetState() { Format = .RGBA16Float };
		let pipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mCompositePipelineLayout,
			Vertex = .() { Shader = .(vs.Value, "VSMain" ), Buffers = default },
			Fragment = .() { Shader = .(fs.Value, "PSMain" ) , Targets = Span<ColorTargetState>(&colorTarget, 1) },
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			DepthStencil = DepthStencilState.Disabled(.Undefined),
			Multisample = .() { Count = 1 },
			Label = "Bloom_CompositePipeline"
		});
		if (pipeResult case .Err) return .Err;
		mCompositePipeline = pipeResult.Value;
		return .Ok;
	}

	public RGTexture OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx,
		PostProcessInputs inputs)
	{
		let device = mDevice;
		let linearSampler = mLinearSampler;
		let inputTex = inputs.SceneColor;
		let renderW = viewCtx.RenderWidth;
		let renderH = viewCtx.RenderHeight;
		let downPipeline = mDownsamplePipeline;
		let downLayout = mDownsampleBindGroupLayout;
		let upPipeline = mUpsamplePipeline;
		let upLayout = mUpsampleBindGroupLayout;
		let compPipeline = mCompositePipeline;
		let compLayout = mCompositeBindGroupLayout;
		let threshold = Threshold;
		let softThreshold = SoftThreshold;
		let intensity = Intensity;

		// Create downsample chain textures
		RGTexture[MipCount] downTextures = default;
		uint32[MipCount] mipWidths = default;
		uint32[MipCount] mipHeights = default;

		for (int i = 0; i < MipCount; i++)
		{
			mipWidths[i] = Math.Max(1, renderW >> (uint32)(i + 1));
			mipHeights[i] = Math.Max(1, renderH >> (uint32)(i + 1));
		}

		int passIdx = 0;

		// --- Downsample passes ---
		for (int mip = 0; mip < MipCount; mip++)
		{
			let srcTex = (mip == 0) ? inputTex : downTextures[mip - 1];
			let srcW = (mip == 0) ? renderW : mipWidths[mip - 1];
			let srcH = (mip == 0) ? renderH : mipHeights[mip - 1];
			let dstW = mipWidths[mip];
			let dstH = mipHeights[mip];
			let mipLevel = (uint32)mip;
			let passParamsBuffer = mParamsBuffers[passIdx];
			let passParamsPtr = mParamsPtrs[passIdx];
			passIdx++;

			graph.AddPass(scope $"Bloom_Down{mip}", .Graphics, scope [&] (builder) =>
			{
				downTextures[mip] = builder.CreateTexture(
					RGTextureDesc.RenderTarget(.RGBA16Float, dstW, dstH, 1,
						scope $"Bloom_Down{mip}"));

				builder.ReadTexture(srcTex, .Fragment);
				builder.WriteRenderTarget(downTextures[mip], 0, .DontCare, .Store);
				builder.HasSideEffects();

				let graphPass = builder.Pass;
				builder.SetExecute(new [=] (encoder, registry) =>
				{
					let srcView = registry.GetTextureView(srcTex);
					if (srcView == null) return;

					if (passParamsPtr != null)
					{
						var p = BloomDownsampleParams();
						p.Threshold = threshold;
						p.SoftThreshold = softThreshold;
						p.Intensity = intensity;
						p.MipLevel = mipLevel;
						p.TexelSize = .(1.0f / (float)srcW, 1.0f / (float)srcH);
						Internal.MemCpy(passParamsPtr, &p, sizeof(BloomDownsampleParams));
					}

					var bgEntries = BindGroupEntry[3](
						BindGroupEntry.Texture(srcView),
						BindGroupEntry.Sampler(linearSampler),
						BindGroupEntry.Buffer(passParamsBuffer, 0, 256)
					);
					let bgResult = device.CreateBindGroup(BindGroupDesc()
						{ Layout = downLayout, Entries = bgEntries, Label = "Bloom_Down_BG" });
					if (bgResult case .Err) return;
					var bg = bgResult.Value;

					let rpDesc = registry.GetRenderPassDesc(graphPass);
					let rp = encoder.BeginRenderPass(rpDesc);
					rp.SetViewport(0, 0, (float)dstW, (float)dstH, 0, 1);
					rp.SetScissor(0, 0, dstW, dstH);
					rp.SetPipeline(downPipeline);
					rp.SetBindGroup(0, bg);
					rp.Draw(3, 1, 0, 0);
					rp.End();
					device.DestroyBindGroup(ref bg);
				});
			});
		}

		// --- Upsample passes ---
		RGTexture[MipCount - 1] upTextures = default;

		for (int i_ = 0; i_ < MipCount - 1; i_++)
		{
			let i = i_;
			let srcMip = MipCount - 1 - i;
			let dstW = mipWidths[srcMip - 1];
			let dstH = mipHeights[srcMip - 1];
			let srcW = mipWidths[srcMip];
			let srcH = mipHeights[srcMip];
			let hasPrev = (i > 0);
			let mipLevel = (uint32)srcMip;
			let passParamsBuffer = mParamsBuffers[passIdx];
			let passParamsPtr = mParamsPtrs[passIdx];
			passIdx++;

			graph.AddPass(scope $"Bloom_Up{i}", .Graphics, scope [&] (builder) =>
			{
				upTextures[i] = builder.CreateTexture(
					RGTextureDesc.RenderTarget(.RGBA16Float, dstW, dstH, 1,
						scope $"Bloom_Up{i}"));

				builder.ReadTexture(downTextures[srcMip], .Fragment);
				if (hasPrev) builder.ReadTexture(upTextures[i - 1], .Fragment);
				builder.WriteRenderTarget(upTextures[i], 0, .DontCare, .Store);
				builder.HasSideEffects();

				let graphPass = builder.Pass;
				builder.SetExecute(new [=] (encoder, registry) =>
				{
					let currentView = registry.GetTextureView(downTextures[srcMip]);
					if (currentView == null) return;

					let prevView = hasPrev ? registry.GetTextureView(upTextures[i - 1]) : null;
					let actualPrevView = (prevView != null) ? prevView : currentView;

					if (passParamsPtr != null)
					{
						var p = BloomUpsampleParams();
						p.Threshold = threshold;
						p.SoftThreshold = softThreshold;
						p.Intensity = intensity;
						p.MipLevel = mipLevel;
						p.TexelSize = .(1.0f / (float)srcW, 1.0f / (float)srcH);
						p.HasPrevUpsample = hasPrev ? 1 : 0;
						Internal.MemCpy(passParamsPtr, &p, sizeof(BloomUpsampleParams));
					}

					var bgEntries = BindGroupEntry[4](
						BindGroupEntry.Texture(currentView),
						BindGroupEntry.Texture(actualPrevView),
						BindGroupEntry.Sampler(linearSampler),
						BindGroupEntry.Buffer(passParamsBuffer, 0, 256)
					);
					let bgResult = device.CreateBindGroup(BindGroupDesc()
						{ Layout = upLayout, Entries = bgEntries, Label = "Bloom_Up_BG" });
					if (bgResult case .Err) return;
					var bg = bgResult.Value;

					let rpDesc = registry.GetRenderPassDesc(graphPass);
					let rp = encoder.BeginRenderPass(rpDesc);
					rp.SetViewport(0, 0, (float)dstW, (float)dstH, 0, 1);
					rp.SetScissor(0, 0, dstW, dstH);
					rp.SetPipeline(upPipeline);
					rp.SetBindGroup(0, bg);
					rp.Draw(3, 1, 0, 0);
					rp.End();
					device.DestroyBindGroup(ref bg);
				});
			});
		}

		// --- Composite pass ---
		let bloomResult = upTextures[MipCount - 2];
		RGTexture outputTex = default;
		let compParamsBuffer = mParamsBuffers[passIdx];
		let compParamsPtr = mParamsPtrs[passIdx];

		graph.AddPass("Bloom_Composite", .Graphics, scope [&] (builder) =>
		{
			outputTex = builder.CreateTexture(
				RGTextureDesc.RenderTarget(.RGBA16Float, renderW, renderH, 1, "Bloom_Output"));

			builder.ReadTexture(inputTex, .Fragment);
			builder.ReadTexture(bloomResult, .Fragment);
			builder.WriteRenderTarget(outputTex, 0, .DontCare, .Store);
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let sceneView = registry.GetTextureView(inputTex);
				let bloomView = registry.GetTextureView(bloomResult);
				if (sceneView == null || bloomView == null) return;

				if (compParamsPtr != null)
				{
					var p = BloomCompositeParams();
					p.Intensity = intensity;
					Internal.MemCpy(compParamsPtr, &p, sizeof(BloomCompositeParams));
				}

				var bgEntries = BindGroupEntry[4](
					BindGroupEntry.Texture(sceneView),
					BindGroupEntry.Texture(bloomView),
					BindGroupEntry.Sampler(linearSampler),
					BindGroupEntry.Buffer(compParamsBuffer, 0, 256)
				);
				let bgResult = device.CreateBindGroup(BindGroupDesc()
					{ Layout = compLayout, Entries = bgEntries, Label = "Bloom_Comp_BG" });
				if (bgResult case .Err) return;
				var bg = bgResult.Value;

				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);
				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0, 1);
				rp.SetScissor(0, 0, renderW, renderH);
				rp.SetPipeline(compPipeline);
				rp.SetBindGroup(0, bg);
				rp.Draw(3, 1, 0, 0);
				rp.End();
				device.DestroyBindGroup(ref bg);
			});
		});

		return outputTex;
	}

	public void OnShutdown(IDevice device)
	{
		if (mDownsamplePipeline != null) device.DestroyRenderPipeline(ref mDownsamplePipeline);
		if (mDownsamplePipelineLayout != null) device.DestroyPipelineLayout(ref mDownsamplePipelineLayout);
		if (mDownsampleBindGroupLayout != null) device.DestroyBindGroupLayout(ref mDownsampleBindGroupLayout);
		if (mUpsamplePipeline != null) device.DestroyRenderPipeline(ref mUpsamplePipeline);
		if (mUpsamplePipelineLayout != null) device.DestroyPipelineLayout(ref mUpsamplePipelineLayout);
		if (mUpsampleBindGroupLayout != null) device.DestroyBindGroupLayout(ref mUpsampleBindGroupLayout);
		if (mCompositePipeline != null) device.DestroyRenderPipeline(ref mCompositePipeline);
		if (mCompositePipelineLayout != null) device.DestroyPipelineLayout(ref mCompositePipelineLayout);
		if (mCompositeBindGroupLayout != null) device.DestroyBindGroupLayout(ref mCompositeBindGroupLayout);
		if (mLinearSampler != null) device.DestroySampler(ref mLinearSampler);
		for (int i = 0; i < MaxPasses; i++)
			if (mParamsBuffers[i] != null) { mParamsBuffers[i].Unmap(); device.DestroyBuffer(ref mParamsBuffers[i]); }
	}
}

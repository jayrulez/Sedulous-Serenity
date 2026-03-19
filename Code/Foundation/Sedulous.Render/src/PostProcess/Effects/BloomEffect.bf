namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// GPU parameters for bloom downsample (must match bloom_downsample.frag.hlsl).
[CRepr]
struct BloomDownsampleParams
{
	public float Threshold;
	public float TexelSizeX;
	public float TexelSizeY;
	public float IsFirstPass;

	public static int Size => 16;
}

/// GPU parameters for bloom upsample (must match bloom_upsample.frag.hlsl).
[CRepr]
struct BloomUpsampleParams
{
	public float Intensity;
	public float TexelSizeX;
	public float TexelSizeY;
	public float _Pad;

	public static int Size => 16;
}

/// Post-process effect that adds bloom (glow on bright areas).
/// Uses a multi-pass downsample/upsample chain with 13-tap and tent filters.
public class BloomEffect : IPostProcessEffect
{
	private const int32 MipCount = 5;

	private RenderSystem mRenderSystem;
	private IDevice mDevice;

	// Pipelines
	private IRenderPipeline mDownsamplePipeline ~ delete _;
	private IPipelineLayout mDownsamplePipelineLayout ~ delete _;
	private IBindGroupLayout mDownsampleBindGroupLayout ~ delete _;

	private IRenderPipeline mUpsamplePipeline ~ delete _;
	private IPipelineLayout mUpsamplePipelineLayout ~ delete _;
	private IBindGroupLayout mUpsampleBindGroupLayout ~ delete _;

	// Shared sampler
	private ISampler mLinearSampler ~ delete _;

	// Per-pass param buffers (downsample: MipCount, upsample: MipCount)
	private IBuffer[MipCount] mDownsampleParamBuffers;
	private IBuffer[MipCount] mUpsampleParamBuffers;

	// Per-frame bind groups for each pass
	// We need a bind group per mip per frame. Use a flat array [mip * FrameBufferCount + frame].
	private IBindGroup[MipCount * RenderConfig.FrameBufferCount] mDownsampleBindGroups;
	private IBindGroup[MipCount * RenderConfig.FrameBufferCount] mUpsampleBindGroups;

	private bool mEnabled = true;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	/// Creates a new bloom effect.
	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public StringView Name => "Bloom";

	public int Priority => 200; // Color effects range

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
		samplerDesc.Label = "Bloom Linear Sampler";
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

		// Create param buffers for each mip (both down and up)
		for (int32 i = 0; i < MipCount; i++)
		{
			BufferDesc bufDesc = .();
			bufDesc.Label = "Bloom Downsample Params";
			bufDesc.Size = (uint64)BloomDownsampleParams.Size;
			bufDesc.Usage = .Uniform;
			bufDesc.Memory = .CpuToGpu;

			switch (device.CreateBuffer(bufDesc))
			{
			case .Ok(let buf): mDownsampleParamBuffers[i] = buf;
			case .Err: return .Err;
			}

			bufDesc.Label = "Bloom Upsample Params";
			bufDesc.Size = (uint64)BloomUpsampleParams.Size;

			switch (device.CreateBuffer(bufDesc))
			{
			case .Ok(let buf): mUpsampleParamBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		// Create downsample bind group layout: b0=params, t0=source, s0=sampler
		BindGroupLayoutEntry[3] dsLayoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDesc dsLayoutDesc = .();
		dsLayoutDesc.Label = "Bloom Downsample Layout";
		dsLayoutDesc.Entries = dsLayoutEntries;

		switch (device.CreateBindGroupLayout(dsLayoutDesc))
		{
		case .Ok(let layout): mDownsampleBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create upsample bind group layout: b0=params, t0=current mip, t1=previous level, s0=sampler
		BindGroupLayoutEntry[4] usLayoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDesc usLayoutDesc = .();
		usLayoutDesc.Label = "Bloom Upsample Layout";
		usLayoutDesc.Entries = usLayoutEntries;

		switch (device.CreateBindGroupLayout(usLayoutDesc))
		{
		case .Ok(let layout): mUpsampleBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layouts
		IBindGroupLayout[1] dsLayouts = .(mDownsampleBindGroupLayout);
		PipelineLayoutDesc dsPLDesc = .(dsLayouts);
		switch (device.CreatePipelineLayout(dsPLDesc))
		{
		case .Ok(let layout): mDownsamplePipelineLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] usLayouts = .(mUpsampleBindGroupLayout);
		PipelineLayoutDesc usPLDesc = .(usLayouts);
		switch (device.CreatePipelineLayout(usPLDesc))
		{
		case .Ok(let layout): mUpsamplePipelineLayout = layout;
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

		// Downsample pipeline
		let dsShaderResult = mRenderSystem.ShaderSystem.GetShaderPair("bloom_downsample");
		if (dsShaderResult case .Ok(let shaders))
		{
			let (vertShader, fragShader) = shaders;
			ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

			RenderPipelineDesc pipelineDesc = .()
			{
				Label = "Bloom Downsample Pipeline",
				Layout = mDownsamplePipelineLayout,
				Vertex = .() { Shader = .(vertShader.Module, "main"), Buffers = default },
				Fragment = .() { Shader = .(fragShader.Module, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = null,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			switch (device.CreateRenderPipeline(pipelineDesc))
			{
			case .Ok(let pipeline): mDownsamplePipeline = pipeline;
			case .Err: return .Err;
			}
		}

		// Upsample pipeline
		let usShaderResult = mRenderSystem.ShaderSystem.GetShaderPair("bloom_upsample");
		if (usShaderResult case .Ok(let usShaders))
		{
			let (vertShader, fragShader) = usShaders;
			ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

			RenderPipelineDesc pipelineDesc = .()
			{
				Label = "Bloom Upsample Pipeline",
				Layout = mUpsamplePipelineLayout,
				Vertex = .() { Shader = .(vertShader.Module, "main"), Buffers = default },
				Fragment = .() { Shader = .(fragShader.Module, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = null,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			switch (device.CreateRenderPipeline(pipelineDesc))
			{
			case .Ok(let pipeline): mUpsamplePipeline = pipeline;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	public void Shutdown()
	{
		for (int i = 0; i < MipCount; i++)
		{
			if (mDownsampleParamBuffers[i] != null) { delete mDownsampleParamBuffers[i]; mDownsampleParamBuffers[i] = null; }
			if (mUpsampleParamBuffers[i] != null) { delete mUpsampleParamBuffers[i]; mUpsampleParamBuffers[i] = null; }
		}

		for (int i = 0; i < MipCount * RenderConfig.FrameBufferCount; i++)
		{
			if (mDownsampleBindGroups[i] != null) { delete mDownsampleBindGroups[i]; mDownsampleBindGroups[i] = null; }
			if (mUpsampleBindGroups[i] != null) { delete mUpsampleBindGroups[i]; mUpsampleBindGroups[i] = null; }
		}
	}

	public void AddPasses(
		RenderGraph graph,
		RenderView view,
		RGResourceHandle inputHandle,
		RGResourceHandle outputHandle,
		RGResourceHandle depthHandle)
	{
		if (mDownsamplePipeline == null || mUpsamplePipeline == null)
			return;

		// Check bloom enabled on world
		let world = mRenderSystem?.ActiveWorld;
		if (world == null || !world.BloomEnabled)
			return;

		if (!view.PostProcess.EnableBloom)
			return;

		float threshold = world.BloomThreshold;
		float intensity = world.BloomIntensity;

		// Compute mip dimensions (each half the previous, minimum 1)
		uint32[MipCount] mipWidths = default;
		uint32[MipCount] mipHeights = default;
		uint32 w = view.Width;
		uint32 h = view.Height;
		for (int32 i = 0; i < MipCount; i++)
		{
			w = Math.Max(w / 2, 1);
			h = Math.Max(h / 2, 1);
			mipWidths[i] = w;
			mipHeights[i] = h;
		}

		// Create transient textures for downsample mip chain
		RGResourceHandle[MipCount] mipHandles = default;
		for (int32 i = 0; i < MipCount; i++)
		{
			let desc = TextureResourceDesc(mipWidths[i], mipHeights[i], .RGBA16Float, .RenderTarget | .Sampled);
			let name = scope String()..AppendF("BloomMip{}", i);
			mipHandles[i] = graph.CreateTexture(name, desc);
		}

		// ---- Downsample chain ----
		// Pass 0: input → mip[0] (threshold + downsample)
		// Pass i: mip[i-1] → mip[i] (just downsample)
		float srcW = (float)view.Width;
		float srcH = (float)view.Height;

		for (int32 i = 0; i < MipCount; i++)
		{
			let source = (i == 0) ? inputHandle : mipHandles[i - 1];
			let target = mipHandles[i];

			BloomDownsampleParams dsParams = .();
			dsParams.Threshold = threshold;
			dsParams.TexelSizeX = 1.0f / srcW;
			dsParams.TexelSizeY = 1.0f / srcH;
			dsParams.IsFirstPass = (i == 0) ? 1.0f : 0.0f;

			mDevice.Queue.WriteMappedBuffer(
				mDownsampleParamBuffers[i], 0,
				Span<uint8>((uint8*)&dsParams, BloomDownsampleParams.Size)
			);

			RenderGraph graphRef = graph;
			RGResourceHandle srcCopy = source;
			int32 mipIndex = i;
			uint32 mw = mipWidths[i];
			uint32 mh = mipHeights[i];

			graph.AddGraphicsPass(scope String()..AppendF("Bloom_Down{}", i))
				.ReadTexture(source)
				.WriteColor(target, .DontCare, .Store)
				.NeverCull()
				.SetExecuteCallback(new [=] (encoder) => {
					let srcView = graphRef.GetTextureView(srcCopy);
					ExecuteDownsamplePass(encoder, srcView, mipIndex, mw, mh);
				});

			srcW = (float)mipWidths[i];
			srcH = (float)mipHeights[i];
		}

		// ---- Upsample chain ----
		// MipCount passes, going from smallest mip back to full resolution.
		//
		// Pass i=0: upsample mip[4]          + blend with mip[3]  → upsample[0] (at mip[3] resolution)
		// Pass i=1: upsample upsample[0]     + blend with mip[2]  → upsample[1] (at mip[2] resolution)
		// Pass i=2: upsample upsample[1]     + blend with mip[1]  → upsample[2] (at mip[1] resolution)
		// Pass i=3: upsample upsample[2]     + blend with mip[0]  → upsample[3] (at mip[0] resolution)
		// Pass i=4: upsample upsample[3]     + blend with input   → outputHandle (at full resolution)

		// Create upsample targets sized to match their output resolution
		RGResourceHandle[MipCount] upsampleHandles = default;
		for (int32 i = 0; i < MipCount; i++)
		{
			int32 targetLevel = (int32)(MipCount - 2) - i; // 3, 2, 1, 0, -1
			uint32 uw, uh;
			if (targetLevel >= 0)
			{
				uw = mipWidths[targetLevel];
				uh = mipHeights[targetLevel];
			}
			else
			{
				uw = view.Width;
				uh = view.Height;
			}
			let desc = TextureResourceDesc(uw, uh, .RGBA16Float, .RenderTarget | .Sampled);
			let name = scope String()..AppendF("BloomUp{}", i);
			upsampleHandles[i] = graph.CreateTexture(name, desc);
		}

		for (int32 i = 0; i < MipCount; i++)
		{
			int32 targetLevel = (int32)(MipCount - 2) - i; // 3, 2, 1, 0, -1

			// Bloom source: smallest mip for first pass, previous upsample result for rest
			RGResourceHandle currentBloom;
			float bloomTexelW, bloomTexelH;
			if (i == 0)
			{
				currentBloom = mipHandles[MipCount - 1];
				bloomTexelW = 1.0f / (float)mipWidths[MipCount - 1];
				bloomTexelH = 1.0f / (float)mipHeights[MipCount - 1];
			}
			else
			{
				currentBloom = upsampleHandles[i - 1];
				// Previous upsample target was one level higher
				int32 prevTargetLevel = targetLevel + 1;
				if (prevTargetLevel >= 0)
				{
					bloomTexelW = 1.0f / (float)mipWidths[prevTargetLevel];
					bloomTexelH = 1.0f / (float)mipHeights[prevTargetLevel];
				}
				else
				{
					bloomTexelW = 1.0f / (float)view.Width;
					bloomTexelH = 1.0f / (float)view.Height;
				}
			}

			// Blend target: the higher-res mip, or original input for final pass
			RGResourceHandle blendTarget;
			uint32 targetW, targetH;
			RGResourceHandle writeTarget;

			if (targetLevel >= 0)
			{
				blendTarget = mipHandles[targetLevel];
				targetW = mipWidths[targetLevel];
				targetH = mipHeights[targetLevel];
				writeTarget = upsampleHandles[i];
			}
			else
			{
				blendTarget = inputHandle;
				targetW = view.Width;
				targetH = view.Height;
				writeTarget = outputHandle; // Final pass writes to PostProcessStack's output
			}

			BloomUpsampleParams usParams = .();
			usParams.Intensity = intensity;
			usParams.TexelSizeX = bloomTexelW;
			usParams.TexelSizeY = bloomTexelH;

			mDevice.Queue.WriteMappedBuffer(
				mUpsampleParamBuffers[i], 0,
				Span<uint8>((uint8*)&usParams, BloomUpsampleParams.Size)
			);

			RenderGraph graphRef = graph;
			RGResourceHandle bloomCopy = currentBloom;
			RGResourceHandle blendCopy = blendTarget;
			int32 passIndex = i;
			uint32 tw = targetW;
			uint32 th = targetH;

			graph.AddGraphicsPass(scope String()..AppendF("Bloom_Up{}", i))
				.ReadTexture(currentBloom)
				.ReadTexture(blendTarget)
				.WriteColor(writeTarget, .DontCare, .Store)
				.NeverCull()
				.SetExecuteCallback(new [=] (encoder) => {
					let bloomView = graphRef.GetTextureView(bloomCopy);
					let blendView = graphRef.GetTextureView(blendCopy);
					ExecuteUpsamplePass(encoder, bloomView, blendView, passIndex, tw, th);
				});
		}
	}

	private void ExecuteDownsamplePass(IRenderPassEncoder encoder, ITextureView sourceView, int32 mipIndex, uint32 width, uint32 height)
	{
		if (sourceView == null)
			return;

		let frameIndex = FrameIndex;
		let bgIndex = mipIndex * RenderConfig.FrameBufferCount + frameIndex;

		// Recreate bind group
		if (mDownsampleBindGroups[bgIndex] != null)
		{
			delete mDownsampleBindGroups[bgIndex];
			mDownsampleBindGroups[bgIndex] = null;
		}

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, mDownsampleParamBuffers[mipIndex], 0, (uint64)BloomDownsampleParams.Size),
			BindGroupEntry.Texture(0, sourceView),
			BindGroupEntry.Sampler(0, mLinearSampler)
		);

		BindGroupDesc bgDesc = .();
		bgDesc.Label = "Bloom Downsample BG";
		bgDesc.Layout = mDownsampleBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg): mDownsampleBindGroups[bgIndex] = bg;
		case .Err: return;
		}

		encoder.SetViewport(0, 0, (float)width, (float)height, 0, 1);
		encoder.SetScissor(0, 0, width, height);

		encoder.SetPipeline(mDownsamplePipeline);
		encoder.SetBindGroup(0, mDownsampleBindGroups[bgIndex], default);
		encoder.Draw(3, 1, 0, 0);

		if (mRenderSystem != null)
			mRenderSystem.Stats.DrawCalls++;
	}

	private void ExecuteUpsamplePass(IRenderPassEncoder encoder, ITextureView bloomView, ITextureView blendView, int32 passIndex, uint32 width, uint32 height)
	{
		if (bloomView == null || blendView == null)
			return;

		let frameIndex = FrameIndex;
		let bgIndex = passIndex * RenderConfig.FrameBufferCount + frameIndex;

		// Recreate bind group
		if (mUpsampleBindGroups[bgIndex] != null)
		{
			delete mUpsampleBindGroups[bgIndex];
			mUpsampleBindGroups[bgIndex] = null;
		}

		BindGroupEntry[4] entries = .(
			BindGroupEntry.Buffer(0, mUpsampleParamBuffers[passIndex], 0, (uint64)BloomUpsampleParams.Size),
			BindGroupEntry.Texture(0, bloomView),
			BindGroupEntry.Texture(1, blendView),
			BindGroupEntry.Sampler(0, mLinearSampler)
		);

		BindGroupDesc bgDesc = .();
		bgDesc.Label = "Bloom Upsample BG";
		bgDesc.Layout = mUpsampleBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg): mUpsampleBindGroups[bgIndex] = bg;
		case .Err: return;
		}

		encoder.SetViewport(0, 0, (float)width, (float)height, 0, 1);
		encoder.SetScissor(0, 0, width, height);

		encoder.SetPipeline(mUpsamplePipeline);
		encoder.SetBindGroup(0, mUpsampleBindGroups[bgIndex], default);
		encoder.Draw(3, 1, 0, 0);

		if (mRenderSystem != null)
			mRenderSystem.Stats.DrawCalls++;
	}
}

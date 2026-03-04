namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// GPU parameters for TAA resolve (must match taa.frag.hlsl cbuffer).
[CRepr]
struct TAAParams
{
	public float TexelSizeX;
	public float TexelSizeY;
	public float FirstFrame;
	public float _Pad;

	public static int Size => 16;
}

/// Post-process effect that applies Temporal Anti-Aliasing.
/// Uses motion-vector-based reprojection with neighborhood clamping
/// and a history ping-pong buffer.
public class TAAEffect : IPostProcessEffect
{
	private RenderSystem mRenderSystem;
	private IDevice mDevice;

	// TAA resolve pipeline
	private IRenderPipeline mResolvePipeline ~ delete _;
	private IPipelineLayout mResolvePipelineLayout ~ delete _;
	private IBindGroupLayout mResolveBindGroupLayout ~ delete _;

	// History copy pipeline
	private IRenderPipeline mCopyPipeline ~ delete _;
	private IPipelineLayout mCopyPipelineLayout ~ delete _;
	private IBindGroupLayout mCopyBindGroupLayout ~ delete _;

	// Persistent history buffers (double-buffered)
	private ITexture mHistoryA ~ delete _;
	private ITexture mHistoryB ~ delete _;
	private ITextureView mHistoryAView ~ delete _;
	private ITextureView mHistoryBView ~ delete _;
	private uint32 mHistoryWidth;
	private uint32 mHistoryHeight;
	private bool mReadFromA = true; // true = read A (history), write B
	private bool mFirstFrame = true;

	// Samplers
	private ISampler mLinearSampler ~ delete _;
	private ISampler mPointSampler ~ delete _;

	// Params buffer
	private IBuffer mParamsBuffer ~ delete _;

	// Per-frame bind groups
	private IBindGroup[RenderConfig.FrameBufferCount] mResolveBindGroups;
	private IBindGroup[RenderConfig.FrameBufferCount] mCopyBindGroups;

	private bool mEnabled = true;

	/// Gets the current frame index for multi-buffering.
	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	/// Creates a new TAA effect.
	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public StringView Name => "TAA";

	public int Priority => 300; // Anti-aliasing range

	public bool Enabled
	{
		get => mEnabled;
		set => mEnabled = value;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create samplers
		SamplerDescriptor linearDesc = .();
		linearDesc.Label = "TAA Linear Sampler";
		linearDesc.AddressModeU = .ClampToEdge;
		linearDesc.AddressModeV = .ClampToEdge;
		linearDesc.AddressModeW = .ClampToEdge;
		linearDesc.MinFilter = .Linear;
		linearDesc.MagFilter = .Linear;
		linearDesc.MipmapFilter = .Nearest;

		switch (device.CreateSampler(&linearDesc))
		{
		case .Ok(let sampler): mLinearSampler = sampler;
		case .Err: return .Err;
		}

		SamplerDescriptor pointDesc = .();
		pointDesc.Label = "TAA Point Sampler";
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
		bufDesc.Label = "TAA Params";
		bufDesc.Size = (uint64)TAAParams.Size;
		bufDesc.Usage = .Uniform;
		bufDesc.MemoryAccess = .Upload;

		switch (device.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Create resolve bind group layout: b0=params, t0=current, t1=history, t2=motion, s0=linear, s1=point
		BindGroupLayoutEntry[6] resolveLayoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler },
			.() { Binding = 1, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDescriptor resolveLayoutDesc = .();
		resolveLayoutDesc.Label = "TAA Resolve BindGroup Layout";
		resolveLayoutDesc.Entries = resolveLayoutEntries;

		switch (device.CreateBindGroupLayout(&resolveLayoutDesc))
		{
		case .Ok(let layout): mResolveBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create copy bind group layout: t0=source, s0=point
		BindGroupLayoutEntry[2] copyLayoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }
		);

		BindGroupLayoutDescriptor copyLayoutDesc = .();
		copyLayoutDesc.Label = "TAA Copy BindGroup Layout";
		copyLayoutDesc.Entries = copyLayoutEntries;

		switch (device.CreateBindGroupLayout(&copyLayoutDesc))
		{
		case .Ok(let layout): mCopyBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layouts
		IBindGroupLayout[1] resolveLayouts = .(mResolveBindGroupLayout);
		PipelineLayoutDescriptor resolvePLDesc = .(resolveLayouts);
		switch (device.CreatePipelineLayout(&resolvePLDesc))
		{
		case .Ok(let layout): mResolvePipelineLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] copyLayouts = .(mCopyBindGroupLayout);
		PipelineLayoutDescriptor copyPLDesc = .(copyLayouts);
		switch (device.CreatePipelineLayout(&copyPLDesc))
		{
		case .Ok(let layout): mCopyPipelineLayout = layout;
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

		// TAA resolve pipeline
		let taaResult = mRenderSystem.ShaderSystem.GetShaderPair("taa");
		if (taaResult case .Ok(let shaders))
		{
			let (vertShader, fragShader) = shaders;
			ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

			RenderPipelineDescriptor pipelineDesc = .()
			{
				Label = "TAA Resolve Pipeline",
				Layout = mResolvePipelineLayout,
				Vertex = .() { Shader = .(vertShader.Module, "main"), Buffers = default },
				Fragment = .() { Shader = .(fragShader.Module, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = null,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			switch (device.CreateRenderPipeline(&pipelineDesc))
			{
			case .Ok(let pipeline): mResolvePipeline = pipeline;
			case .Err: return .Err;
			}
		}

		// History copy pipeline (uses taa vertex shader + fullscreen_copy fragment)
		let copyVertResult = mRenderSystem.ShaderSystem.GetShader("taa", .Vertex);
		let copyFragResult = mRenderSystem.ShaderSystem.GetShader("fullscreen_copy", .Fragment);
		if (copyVertResult case .Ok(let vertShader))
		{
			if (copyFragResult case .Ok(let fragShader))
			{
				ColorTargetState[1] colorTargets = .(.(.RGBA16Float));

				RenderPipelineDescriptor pipelineDesc = .()
				{
					Label = "TAA History Copy Pipeline",
					Layout = mCopyPipelineLayout,
					Vertex = .() { Shader = .(vertShader.Module, "main"), Buffers = default },
					Fragment = .() { Shader = .(fragShader.Module, "main"), Targets = colorTargets },
					Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
					DepthStencil = null,
					Multisample = .() { Count = 1, Mask = uint32.MaxValue }
				};

				switch (device.CreateRenderPipeline(&pipelineDesc))
				{
				case .Ok(let pipeline): mCopyPipeline = pipeline;
				case .Err: return .Err;
				}
			}
		}

		return .Ok;
	}

	/// Ensures history textures exist and match the viewport size.
	private void EnsureHistoryTextures(uint32 width, uint32 height)
	{
		if (mHistoryA != null && mHistoryWidth == width && mHistoryHeight == height)
			return;

		// Release old textures
		if (mHistoryAView != null) { delete mHistoryAView; mHistoryAView = null; }
		if (mHistoryBView != null) { delete mHistoryBView; mHistoryBView = null; }
		if (mHistoryA != null) { delete mHistoryA; mHistoryA = null; }
		if (mHistoryB != null) { delete mHistoryB; mHistoryB = null; }

		// Create new history textures
		TextureDescriptor texDesc = .();
		texDesc.Width = width;
		texDesc.Height = height;
		texDesc.Format = .RGBA16Float;
		texDesc.Usage = .RenderTarget | .Sampled;
		texDesc.Dimension = .Texture2D;
		texDesc.MipLevelCount = 1;
		texDesc.SampleCount = 1;

		texDesc.Label = "TAA History A";
		if (mDevice.CreateTexture(&texDesc) case .Ok(let texA))
			mHistoryA = texA;
		else
			return;

		texDesc.Label = "TAA History B";
		if (mDevice.CreateTexture(&texDesc) case .Ok(let texB))
			mHistoryB = texB;
		else
			return;

		// Create views
		TextureViewDescriptor viewDesc = .();
		viewDesc.Format = .RGBA16Float;
		viewDesc.Dimension = .Texture2D;
		viewDesc.BaseMipLevel = 0;
		viewDesc.MipLevelCount = 1;
		viewDesc.BaseArrayLayer = 0;
		viewDesc.ArrayLayerCount = 1;
		viewDesc.Aspect = .All;

		if (mDevice.CreateTextureView(mHistoryA, &viewDesc) case .Ok(let viewA))
			mHistoryAView = viewA;

		if (mDevice.CreateTextureView(mHistoryB, &viewDesc) case .Ok(let viewB))
			mHistoryBView = viewB;

		mHistoryWidth = width;
		mHistoryHeight = height;
		mFirstFrame = true;
		mReadFromA = true;
	}

	public void Shutdown()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mResolveBindGroups[i] != null) { delete mResolveBindGroups[i]; mResolveBindGroups[i] = null; }
			if (mCopyBindGroups[i] != null) { delete mCopyBindGroups[i]; mCopyBindGroups[i] = null; }
		}
	}

	public void AddPasses(
		RenderGraph graph,
		RenderView view,
		RGResourceHandle inputHandle,
		RGResourceHandle outputHandle,
		RGResourceHandle depthHandle)
	{
		if (mResolvePipeline == null)
			return;

		// Check AA mode on world
		let world = mRenderSystem?.ActiveWorld;
		if (world == null || world.AAMode != .TAA)
			return;

		// Get motion vectors from render graph
		let motionHandle = graph.GetResource("MotionVectors");
		if (!motionHandle.IsValid)
			return;

		// Ensure history textures exist
		EnsureHistoryTextures(view.Width, view.Height);
		if (mHistoryA == null || mHistoryB == null)
			return;

		// Upload TAA params
		var taaParams = TAAParams();
		taaParams.TexelSizeX = 1.0f / (float)view.Width;
		taaParams.TexelSizeY = 1.0f / (float)view.Height;
		taaParams.FirstFrame = mFirstFrame ? 1.0f : 0.0f;

		mDevice.Queue.WriteMappedBuffer(
			mParamsBuffer, 0,
			Span<uint8>((uint8*)&taaParams, TAAParams.Size)
		);

		// Import history textures into render graph
		let readHistoryTex = mReadFromA ? mHistoryA : mHistoryB;
		let readHistoryView = mReadFromA ? mHistoryAView : mHistoryBView;
		let writeHistoryTex = mReadFromA ? mHistoryB : mHistoryA;
		let writeHistoryView = mReadFromA ? mHistoryBView : mHistoryAView;

		let historyReadHandle = graph.ImportTexture("TAAHistoryRead", readHistoryTex, readHistoryView);
		let historyWriteHandle = graph.ImportTexture("TAAHistoryWrite", writeHistoryTex, writeHistoryView);

		// Capture for callbacks
		RenderGraph graphRef = graph;
		RGResourceHandle inputCopy = inputHandle;
		RGResourceHandle motionCopy = motionHandle;
		ITextureView historyViewCopy = readHistoryView;

		// Pass 1: TAA resolve — read input + history + motion → write to output
		graph.AddGraphicsPass("PostProcess_TAAResolve")
			.ReadTexture(inputHandle)
			.ReadTexture(historyReadHandle)
			.ReadTexture(motionHandle)
			.WriteColor(outputHandle, .DontCare, .Store)
			.NeverCull()
			.SetExecuteCallback(new [=] (encoder) => {
				let inputView = graphRef.GetTextureView(inputCopy);
				let motionView = graphRef.GetTextureView(motionCopy);
				ExecuteResolvePass(encoder, view, inputView, historyViewCopy, motionView);
			});

		// Pass 2: Copy resolved output to history write buffer
		RGResourceHandle outputCopy = outputHandle;

		if (mCopyPipeline != null)
		{
			graph.AddGraphicsPass("TAA_HistoryCopy")
				.ReadTexture(outputHandle)
				.WriteColor(historyWriteHandle, .DontCare, .Store)
				.NeverCull()
				.SetExecuteCallback(new [=] (encoder) => {
					let resolvedView = graphRef.GetTextureView(outputCopy);
					ExecuteCopyPass(encoder, view, resolvedView);
				});
		}

		// Swap history buffers for next frame
		mReadFromA = !mReadFromA;
		mFirstFrame = false;
	}

	private void ExecuteResolvePass(IRenderPassEncoder encoder, RenderView view,
		ITextureView inputView, ITextureView historyView, ITextureView motionView)
	{
		if (inputView == null || historyView == null || motionView == null)
			return;

		let frameIndex = FrameIndex;

		// Recreate bind group (transient textures change per frame)
		if (mResolveBindGroups[frameIndex] != null)
		{
			delete mResolveBindGroups[frameIndex];
			mResolveBindGroups[frameIndex] = null;
		}

		BindGroupEntry[6] entries = .(
			BindGroupEntry.Buffer(0, mParamsBuffer, 0, (uint64)TAAParams.Size),
			BindGroupEntry.Texture(0, inputView),
			BindGroupEntry.Texture(1, historyView),
			BindGroupEntry.Texture(2, motionView),
			BindGroupEntry.Sampler(0, mLinearSampler),
			BindGroupEntry.Sampler(1, mPointSampler)
		);

		BindGroupDescriptor bgDesc = .();
		bgDesc.Label = "TAA Resolve BindGroup";
		bgDesc.Layout = mResolveBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(&bgDesc))
		{
		case .Ok(let bg): mResolveBindGroups[frameIndex] = bg;
		case .Err: return;
		}

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		encoder.SetPipeline(mResolvePipeline);
		encoder.SetBindGroup(0, mResolveBindGroups[frameIndex], default);
		encoder.Draw(3, 1, 0, 0);

		if (mRenderSystem != null)
			mRenderSystem.Stats.DrawCalls++;
	}

	private void ExecuteCopyPass(IRenderPassEncoder encoder, RenderView view, ITextureView sourceView)
	{
		if (sourceView == null)
			return;

		let frameIndex = FrameIndex;

		// Recreate bind group
		if (mCopyBindGroups[frameIndex] != null)
		{
			delete mCopyBindGroups[frameIndex];
			mCopyBindGroups[frameIndex] = null;
		}

		BindGroupEntry[2] entries = .(
			BindGroupEntry.Texture(0, sourceView),
			BindGroupEntry.Sampler(0, mPointSampler)
		);

		BindGroupDescriptor bgDesc = .();
		bgDesc.Label = "TAA Copy BindGroup";
		bgDesc.Layout = mCopyBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(&bgDesc))
		{
		case .Ok(let bg): mCopyBindGroups[frameIndex] = bg;
		case .Err: return;
		}

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		encoder.SetPipeline(mCopyPipeline);
		encoder.SetBindGroup(0, mCopyBindGroups[frameIndex], default);
		encoder.Draw(3, 1, 0, 0);

		if (mRenderSystem != null)
			mRenderSystem.Stats.DrawCalls++;
	}
}

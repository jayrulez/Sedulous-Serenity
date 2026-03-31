namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// TAA params UBO (matches taa_resolve.hlsl cbuffer).
[CRepr]
struct TAAParams
{
	public float BlendFactor;
	public uint32 FrameNumber;
	public Vector2 ScreenSize;
	public Vector2 JitterOffset;
	public Vector2 PrevJitterOffset;
	public uint32 HistoryValid;
	public float VarianceClipGamma;
	public float VelocityWeightScale;
	public float JitterScale;
	public float _pad;
}

/// Temporal Anti-Aliasing post-process effect.
/// Applies sub-pixel jitter to the projection matrix and resolves with
/// neighborhood clamping + motion-vector reprojection.
public class TAAEffect : IPostProcessEffect
{
	private IDevice mDevice;
	private IRenderPipeline mResolvePipeline;
	private IPipelineLayout mPipelineLayout;
	private IBindGroupLayout mBindGroupLayout;
	private ISampler mLinearSampler;
	private ISampler mPointSampler;
	private IBuffer mParamsBuffer;
	private void* mParamsPtr;

	// Persistent history (double-buffered, outside render graph)
	private ITexture[2] mHistoryTextures;
	private ITextureView[2] mHistoryViews;
	private int mWriteIndex;  // which history buffer to write this frame
	private bool mHistoryValid;
	private uint32 mHistoryWidth;
	private uint32 mHistoryHeight;

	// Jitter state
	private Vector2 mCurrentJitter;
	private Vector2 mPrevJitter;

	public float BlendFactor = 0.95f;
	public float VarianceClipGamma = 1.25f;
	public float VelocityWeightScale = 0.1f;
	public float JitterScale = 1.0f;

	public StringView Name => "TAA";
	public int32 Priority => 0;
	public bool Enabled { get; set; } = true;

	// ---- Halton sequence ----

	private static float Halton(int index, int base_)
	{
		float result = 0.0f;
		float f = 1.0f / (float)base_;
		int i = index;
		while (i > 0)
		{
			result += f * (float)(i % base_);
			i /= base_;
			f /= (float)base_;
		}
		return result;
	}

	// ---- IPostProcessEffect ----

	public void OnPreGraph(ViewContext viewCtx, FrameContext frameCtx)
	{
		let frameIdx = (int)(frameCtx.FrameNumber % 16) + 1;  // 1-based for Halton

		mPrevJitter = mCurrentJitter;

		// Halton(2,3) offset centered to [-0.5, 0.5] pixel
		float jitterX = Halton(frameIdx, 2) - 0.5f;
		float jitterY = Halton(frameIdx, 3) - 0.5f;

		// Scale to NDC: one pixel in NDC = 2/screenSize
		float ndcX = jitterX * JitterScale * 2.0f / (float)viewCtx.RenderWidth;
		float ndcY = jitterY * JitterScale * 2.0f / (float)viewCtx.RenderHeight;

		mCurrentJitter = .(ndcX, ndcY);

		// Modify projection matrix row 3 (XNA row-major: M31=row3.col1, M32=row3.col2)
		viewCtx.ProjectionMatrix.M31 += ndcX;
		viewCtx.ProjectionMatrix.M32 += ndcY;

		// Recompute VP
		viewCtx.ViewProjectionMatrix = viewCtx.ViewMatrix * viewCtx.ProjectionMatrix;

		// Store for other systems and shader
		viewCtx.JitterOffset = mCurrentJitter;
		viewCtx.PrevJitterOffset = mPrevJitter;
	}

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;

		if (initCtx.Shaders.RegisterShader("postprocess/taa_resolve") case .Err)
			return .Err;

		// Samplers
		let linearResult = mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear, MagFilter = .Linear, MipmapFilter = .Linear,
			AddressU = .ClampToEdge, AddressV = .ClampToEdge, AddressW = .ClampToEdge,
			Label = "TAA_LinearSampler"
		});
		if (linearResult case .Err) return .Err;
		mLinearSampler = linearResult.Value;

		let pointResult = mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Nearest, MagFilter = .Nearest, MipmapFilter = .Nearest,
			AddressU = .ClampToEdge, AddressV = .ClampToEdge, AddressW = .ClampToEdge,
			Label = "TAA_PointSampler"
		});
		if (pointResult case .Err) return .Err;
		mPointSampler = pointResult.Value;

		// Bind group layout: t0=SceneColor, t1=History, t2=MotionVectors, t3=Depth,
		//                    s4=LinearSampler, s5=PointSampler, b6=TAAParams
		BindGroupLayoutEntry[7] entries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.SampledTexture(1, .Fragment, .Texture2D),
			BindGroupLayoutEntry.SampledTexture(2, .Fragment, .Texture2D),
			BindGroupLayoutEntry.SampledTexture(3, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(4, .Fragment),
			BindGroupLayoutEntry.Sampler(5, .Fragment),
			BindGroupLayoutEntry.UniformBuffer(6, .Fragment)
		);
		let layoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
			{ Entries = entries, Label = "TAA_Layout" });
		if (layoutResult case .Err) return .Err;
		mBindGroupLayout = layoutResult.Value;

		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		let pipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
			{ BindGroupLayouts = layouts, Label = "TAA_PipeLayout" });
		if (pipeLayoutResult case .Err) return .Err;
		mPipelineLayout = pipeLayoutResult.Value;

		let vs = initCtx.Shaders.GetCompiledShader("postprocess/taa_resolve", .Vertex);
		if (vs case .Err) { Console.WriteLine("ERROR: Failed to compile TAA vertex shader"); return .Err; }
		let fs = initCtx.Shaders.GetCompiledShader("postprocess/taa_resolve", .Fragment);
		if (fs case .Err) { Console.WriteLine("ERROR: Failed to compile TAA fragment shader"); return .Err; }

		var colorTarget = ColorTargetState() { Format = .RGBA16Float };
		let pipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mPipelineLayout,
			Vertex = .() { Shader = .(vs.Value, "VSMain" ), Buffers = default },
			Fragment = .() { Shader = .(fs.Value, "PSMain" ) , Targets = Span<ColorTargetState>(&colorTarget, 1) },
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			DepthStencil = DepthStencilState.Disabled(.Undefined),
			Multisample = .() { Count = 1 },
			Label = "TAA_ResolvePipeline"
		});
		if (pipeResult case .Err) return .Err;
		mResolvePipeline = pipeResult.Value;

		// Params UBO
		let paramsResult = mDevice.CreateBuffer(BufferDesc()
		{
			Size = (uint64)sizeof(TAAParams),
			Usage = .Uniform,
			Memory = .CpuToGpu,
			Label = "TAA_Params"
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

		// Ensure history textures exist at the right size
		if (!EnsureHistoryTextures(renderW, renderH))
			return inputs.SceneColor;  // Fall through if history can't be created

		let device = mDevice;
		let pipeline = mResolvePipeline;
		let bindGroupLayout = mBindGroupLayout;
		let linearSampler = mLinearSampler;
		let pointSampler = mPointSampler;
		let paramsBuffer = mParamsBuffer;
		let inputTex = inputs.SceneColor;
		let motionTex = inputs.MotionVectors;
		let depthTex = inputs.Depth;

		// Update params
		if (mParamsPtr != null)
		{
			var p = TAAParams();
			p.BlendFactor = BlendFactor;
			p.FrameNumber = frameCtx.FrameNumber;
			p.ScreenSize = .(viewCtx.RenderWidth, viewCtx.RenderHeight);
			p.JitterOffset = mCurrentJitter;
			p.PrevJitterOffset = mPrevJitter;
			p.HistoryValid = mHistoryValid ? 1 : 0;
			p.VarianceClipGamma = VarianceClipGamma;
			p.VelocityWeightScale = VelocityWeightScale;
			p.JitterScale = JitterScale;
			Internal.MemCpy(mParamsPtr, &p, sizeof(TAAParams));
		}

		// Import history read texture (previous frame's output)
		// First frame: texture is in Undefined layout (never written), let render graph transition it.
		let readIdx = 1 - mWriteIndex;
		let writeIdx = mWriteIndex;  // Capture before swap for execute callback
		let historyInitialState = mHistoryValid ? ResourceState.ShaderRead : ResourceState.Undefined;
		let historyTex = graph.ImportTexture("TAA_History",
			mHistoryTextures[readIdx], mHistoryViews[readIdx], historyInitialState);

		// Create output texture
		RGTexture outputTex = default;

		graph.AddPass("TAA_Resolve", .Graphics, scope [&] (builder) =>
		{
			outputTex = builder.CreateTexture(
				RGTextureDesc.RenderTarget(.RGBA16Float, renderW, renderH, 1, "TAA_Output"));

			builder.ReadTexture(inputTex, .Fragment);
			builder.ReadTexture(historyTex, .Fragment);
			if (motionTex.IsValid) builder.ReadTexture(motionTex, .Fragment);
			if (depthTex.IsValid) builder.ReadTexture(depthTex, .Fragment);
			builder.WriteRenderTarget(outputTex, 0, .DontCare, .Store);
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let sceneView = registry.GetTextureView(inputTex);
				let historyView = registry.GetTextureView(historyTex);
				if (sceneView == null || historyView == null) return;

				let motionView = motionTex.IsValid ? registry.GetTextureView(motionTex) : null;
				let depthView = depthTex.IsValid ? registry.GetTextureView(depthTex) : null;

				// Use fallback views if motion/depth not available
				let actualMotionView = (motionView != null) ? motionView : sceneView;
				let actualDepthView = (depthView != null) ? depthView : sceneView;

				var bgEntries = BindGroupEntry[7](
					BindGroupEntry.Texture(sceneView),
					BindGroupEntry.Texture(historyView),
					BindGroupEntry.Texture(actualMotionView),
					BindGroupEntry.Texture(actualDepthView),
					BindGroupEntry.Sampler(linearSampler),
					BindGroupEntry.Sampler(pointSampler),
					BindGroupEntry.Buffer(paramsBuffer, 0, (uint64)sizeof(TAAParams))
				);
				let bgResult = device.CreateBindGroup(BindGroupDesc()
					{ Layout = bindGroupLayout, Entries = bgEntries, Label = "TAA_BG" });
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

				device.DestroyBindGroup(ref bindGroup);

				// Copy resolved output to history write buffer
				let outputView = registry.GetTextureView(outputTex);
				if (outputView != null && outputView.Texture != null)
				{
					let srcTex = outputView.Texture;
					let dstTex = mHistoryTextures[writeIdx];

					encoder.Barrier(BarrierGroup()
					{
						TextureBarriers = .(scope TextureBarrier[2](
							.() { Texture = srcTex, OldState = .RenderTarget, NewState = .CopySrc },
							.() { Texture = dstTex, OldState = .ShaderRead, NewState = .CopyDst }
						))
					});

					encoder.CopyTextureToTexture(srcTex, dstTex, TextureCopyRegion()
					{
						Extent = .((uint32)renderW, (uint32)renderH, 1)
					});

					encoder.Barrier(BarrierGroup()
					{
						TextureBarriers = .(scope TextureBarrier[2](
							.() { Texture = srcTex, OldState = .CopySrc, NewState = .RenderTarget },
							.() { Texture = dstTex, OldState = .CopyDst, NewState = .ShaderRead }
						))
					});
				}
			});
		});

		// Mark history as valid after first frame
		mHistoryValid = true;

		// Swap ping-pong for next frame
		mWriteIndex = 1 - mWriteIndex;

		return outputTex;
	}

	public void OnShutdown(IDevice device)
	{
		DestroyHistoryTextures();
		if (mResolvePipeline != null) device.DestroyRenderPipeline(ref mResolvePipeline);
		if (mPipelineLayout != null) device.DestroyPipelineLayout(ref mPipelineLayout);
		if (mBindGroupLayout != null) device.DestroyBindGroupLayout(ref mBindGroupLayout);
		if (mLinearSampler != null) device.DestroySampler(ref mLinearSampler);
		if (mPointSampler != null) device.DestroySampler(ref mPointSampler);
		if (mParamsBuffer != null) { mParamsBuffer.Unmap(); device.DestroyBuffer(ref mParamsBuffer); }
	}

	// ---- History texture management ----

	private bool EnsureHistoryTextures(uint32 width, uint32 height)
	{
		if (mHistoryWidth == width && mHistoryHeight == height &&
			mHistoryTextures[0] != null && mHistoryTextures[1] != null)
			return true;

		DestroyHistoryTextures();

		for (int i = 0; i < 2; i++)
		{
			let texResult = mDevice.CreateTexture(TextureDesc.Tex2D(
				.RGBA16Float, width, height, .Sampled | .CopyDst | .RenderTarget,
				label: (i == 0) ? "TAA_History0" : "TAA_History1"));
			if (texResult case .Err) return false;
			mHistoryTextures[i] = texResult.Value;

			let viewResult = mDevice.CreateTextureView(mHistoryTextures[i],
				TextureViewDesc() { Label = (i == 0) ? "TAA_HistoryView0" : "TAA_HistoryView1" });
			if (viewResult case .Err) return false;
			mHistoryViews[i] = viewResult.Value;
		}

		mHistoryWidth = width;
		mHistoryHeight = height;
		mHistoryValid = false;
		mWriteIndex = 0;
		return true;
	}

	private void DestroyHistoryTextures()
	{
		for (int i = 0; i < 2; i++)
		{
			if (mHistoryViews[i] != null)
				mDevice.DestroyTextureView(ref mHistoryViews[i]);
			if (mHistoryTextures[i] != null)
				mDevice.DestroyTexture(ref mHistoryTextures[i]);
		}
		mHistoryWidth = 0;
		mHistoryHeight = 0;
		mHistoryValid = false;
	}
}

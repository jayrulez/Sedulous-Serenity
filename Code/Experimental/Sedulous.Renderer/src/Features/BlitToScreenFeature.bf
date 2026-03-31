namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;

/// Fullscreen tonemap + blit pass.
/// Reads the HDR scene color texture from ForwardOpaqueFeature and writes
/// a tonemapped, gamma-corrected result to the backbuffer.
class BlitToScreenFeature : IRenderFeature
{
	private IDevice mDevice;
	private RenderSystem mSystem;
	private IBindGroupLayout mBlitLayout;
	private IPipelineLayout mBlitPipelineLayout;
	private IRenderPipeline mBlitPipeline;
	private IRenderPipeline mBlitPassthroughPipeline;  // No tonemap — post-process stack already tonemapped
	private ISampler mLinearSampler;

	// Debug motion vector visualization
	private IBindGroupLayout mDebugMVLayout;
	private IPipelineLayout mDebugMVPipelineLayout;
	private IRenderPipeline mDebugMVPipeline;

	// Debug Hi-Z visualization
	private IBindGroupLayout mDebugHiZLayout;
	private IPipelineLayout mDebugHiZPipelineLayout;
	private IRenderPipeline mDebugHiZPipeline;
	private IBuffer mDebugHiZParamsBuffer;
	private void* mDebugHiZParamsPtr;

	/// When true, composites motion vectors as a color overlay.
	public bool DebugMotionVectors;

	/// When >= 0, shows Hi-Z pyramid at this mip level.
	public int DebugHiZMip = -1;

	public StringView Name => "BlitToScreen";

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;
		mSystem = initCtx.System;

		// Register blit shader (loaded from search paths)
		if (initCtx.Shaders.RegisterShader("blit_tonemap") case .Err)
			return .Err;

		// Create sampler
		let samplerResult = mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear,
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge
		});
		if (samplerResult case .Err)
			return .Err;
		mLinearSampler = samplerResult.Value;

		// Bind group layout: binding 0 = sampled texture, binding 1 = sampler
		var entries = BindGroupLayoutEntry[2](
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(1, .Fragment)
		);
		let layoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = Span<BindGroupLayoutEntry>(&entries[0], 2),
			Label = "BlitLayout"
		});
		if (layoutResult case .Err)
			return .Err;
		mBlitLayout = layoutResult.Value;

		// Pipeline layout: single set
		IBindGroupLayout[1] layouts = .(mBlitLayout);
		let pipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = Span<IBindGroupLayout>(&layouts[0], 1),
			Label = "BlitPipelineLayout"
		});
		if (pipeLayoutResult case .Err)
			return .Err;
		mBlitPipelineLayout = pipeLayoutResult.Value;

		// Compile shaders
		let vsResult = initCtx.Shaders.GetCompiledShader("blit_tonemap", .Vertex);
		if (vsResult case .Err)
			return .Err;
		let fsResult = initCtx.Shaders.GetCompiledShader("blit_tonemap", .Fragment);
		if (fsResult case .Err)
			return .Err;

		// Create pipeline (no vertex buffers — fullscreen triangle from SV_VertexID)
		var colorTarget = ColorTargetState()
		{
			Format = .BGRA8UnormSrgb
		};

		let pipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mBlitPipelineLayout,
			Vertex = .() { Shader = .(vsResult.Value, "VSMain" ), Buffers = default },
			Fragment = .() { Shader = .(fsResult.Value, "PSMain" ) , Targets = Span<ColorTargetState>(&colorTarget, 1) },
			Primitive = .()
			{
				Topology = .TriangleList,
				CullMode = .None,
				FrontFace = .CCW
			},
			DepthStencil = DepthStencilState.Disabled(.Undefined),
			Multisample = .() { Count = 1 },
			Label = "BlitToScreenPipeline"
		});
		if (pipeResult case .Err)
			return .Err;
		mBlitPipeline = pipeResult.Value;

		// Passthrough variant (no tonemap — for when PostProcessStack handles it)
		let ptVS = initCtx.Shaders.GetCompiledShader("blit_tonemap", .Vertex, .Passthrough);
		let ptFS = initCtx.Shaders.GetCompiledShader("blit_tonemap", .Fragment, .Passthrough);
		if (ptVS case .Ok(let ptVSM))
		{
			if (ptFS case .Ok(let ptFSM))
			{
				let ptResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
				{
					Layout = mBlitPipelineLayout,
					Vertex = .() { Shader = .(ptVSM, "VSMain" ), Buffers = default },
					Fragment = .() { Shader = .(ptFSM, "PSMain" ) , Targets = Span<ColorTargetState>(&colorTarget, 1) },
					Primitive = .() { Topology = .TriangleList, CullMode = .None, FrontFace = .CCW },
					DepthStencil = DepthStencilState.Disabled(.Undefined),
					Multisample = .() { Count = 1 },
					Label = "BlitPassthroughPipeline"
				});
				if (ptResult case .Ok(let p))
					mBlitPassthroughPipeline = p;
			}
		}

		// --- Debug motion vector visualization pipeline ---
		if (initCtx.Shaders.RegisterShader("debug_motion_vectors") case .Err)
			return .Err;

		// Layout: scene color (t0) + motion vectors (t1) + sampler (s2)
		var debugEntries = BindGroupLayoutEntry[3](
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.SampledTexture(1, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(2, .Fragment)
		);
		let debugLayoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = Span<BindGroupLayoutEntry>(&debugEntries[0], 3),
			Label = "DebugMVLayout"
		});
		if (debugLayoutResult case .Err)
			return .Err;
		mDebugMVLayout = debugLayoutResult.Value;

		IBindGroupLayout[1] debugLayouts = .(mDebugMVLayout);
		let debugPipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = Span<IBindGroupLayout>(&debugLayouts[0], 1),
			Label = "DebugMVPipelineLayout"
		});
		if (debugPipeLayoutResult case .Err)
			return .Err;
		mDebugMVPipelineLayout = debugPipeLayoutResult.Value;

		let debugVS = initCtx.Shaders.GetCompiledShader("debug_motion_vectors", .Vertex);
		if (debugVS case .Err) return .Err;
		let debugFS = initCtx.Shaders.GetCompiledShader("debug_motion_vectors", .Fragment);
		if (debugFS case .Err) return .Err;

		var debugColorTarget = ColorTargetState() { Format = .BGRA8UnormSrgb };
		let debugPipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mDebugMVPipelineLayout,
			Vertex = .() { Shader = .(debugVS.Value, "VSMain" ), Buffers = default },
			Fragment = .() { Shader = .(debugFS.Value, "PSMain" ) , Targets = Span<ColorTargetState>(&debugColorTarget, 1) },
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			DepthStencil = DepthStencilState.Disabled(.Undefined),
			Multisample = .() { Count = 1 },
			Label = "DebugMVPipeline"
		});
		if (debugPipeResult case .Err) return .Err;
		mDebugMVPipeline = debugPipeResult.Value;

		// --- Debug Hi-Z visualization pipeline ---
		if (initCtx.Shaders.RegisterShader("debug_hiz") case .Err)
			return .Err;

		// Layout: b0=params, t1=HiZ texture, s2=point sampler
		var debugHiZEntries = BindGroupLayoutEntry[3](
			BindGroupLayoutEntry.UniformBuffer(0, .Fragment),
			BindGroupLayoutEntry.SampledTexture(1, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(2, .Fragment)
		);
		let hiZLayoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = Span<BindGroupLayoutEntry>(&debugHiZEntries[0], 3),
			Label = "DebugHiZLayout"
		});
		if (hiZLayoutResult case .Err) return .Err;
		mDebugHiZLayout = hiZLayoutResult.Value;

		IBindGroupLayout[1] hiZLayouts = .(mDebugHiZLayout);
		let hiZPipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = Span<IBindGroupLayout>(&hiZLayouts[0], 1),
			Label = "DebugHiZPipelineLayout"
		});
		if (hiZPipeLayoutResult case .Err) return .Err;
		mDebugHiZPipelineLayout = hiZPipeLayoutResult.Value;

		let hiZVS = initCtx.Shaders.GetCompiledShader("debug_hiz", .Vertex);
		if (hiZVS case .Err) return .Err;
		let hiZFS = initCtx.Shaders.GetCompiledShader("debug_hiz", .Fragment);
		if (hiZFS case .Err) return .Err;

		var hiZColorTarget = ColorTargetState() { Format = .BGRA8UnormSrgb };
		let hiZPipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mDebugHiZPipelineLayout,
			Vertex = .() { Shader = .(hiZVS.Value, "VSMain" ), Buffers = default },
			Fragment = .() { Shader = .(hiZFS.Value, "PSMain" ) , Targets = Span<ColorTargetState>(&hiZColorTarget, 1) },
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			DepthStencil = DepthStencilState.Disabled(.Undefined),
			Multisample = .() { Count = 1 },
			Label = "DebugHiZPipeline"
		});
		if (hiZPipeResult case .Err) return .Err;
		mDebugHiZPipeline = hiZPipeResult.Value;

		// Params UBO
		let hiZParamsResult = mDevice.CreateBuffer(BufferDesc()
		{
			Size = 16, // 4 x uint32/float
			Usage = .Uniform,
			Memory = .CpuToGpu,
			Label = "DebugHiZParams"
		});
		if (hiZParamsResult case .Err) return .Err;
		mDebugHiZParamsBuffer = hiZParamsResult.Value;
		mDebugHiZParamsPtr = mDebugHiZParamsBuffer.Map();

		return .Ok;
	}

	public void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx)
	{
		let forwardFeature = mSystem.GetFeature<ForwardOpaqueFeature>();
		if (forwardFeature == null) return;

		// If PostProcessStack is active, read from its output (already tonemapped).
		// Otherwise fall back to scene color (blit shader does tonemap).
		let postStack = mSystem.GetFeature<PostProcessStack>();
		let sceneColorTex = (postStack != null && postStack.HasEnabledEffects && postStack.OutputTexture.IsValid)
			? postStack.OutputTexture
			: forwardFeature.SceneColorTexture;
		if (!sceneColorTex.IsValid) return;

		let backbuffer = viewCtx.RenderTarget;
		let renderW = viewCtx.RenderWidth;
		let renderH = viewCtx.RenderHeight;
		let device = mDevice;
		let sampler = mLinearSampler;

		// Debug Hi-Z visualization mode
		if (DebugHiZMip >= 0)
		{
			let hiZ = mSystem.HiZ;
			if (hiZ != null && hiZ.Generated && hiZ.HiZView != null)
			{
				let debugPipeline = mDebugHiZPipeline;
				let debugLayout = mDebugHiZLayout;
				let hiZView = hiZ.HiZView;
				let hiZSampler = hiZ.PointSampler;
				let paramsBuffer = mDebugHiZParamsBuffer;
				let displayMip = (uint32)DebugHiZMip;
				let totalMips = hiZ.MipCount;

				// Update params
				if (mDebugHiZParamsPtr != null)
				{
					let ptr = (uint32*)mDebugHiZParamsPtr;
					ptr[0] = displayMip;
					ptr[1] = totalMips;
					((float*)mDebugHiZParamsPtr)[2] = 0.0f; // DepthMin
					((float*)mDebugHiZParamsPtr)[3] = 1.0f; // DepthMax
				}

				graph.AddPass("BlitToScreen", .Graphics, scope [&] (builder) =>
				{
					builder.WriteRenderTarget(backbuffer, 0, .Clear, .Store,
						ClearColor(0.0f, 0.0f, 0.0f, 1.0f));
					builder.HasSideEffects();

					let graphPass = builder.Pass;
					builder.SetExecute(new [=] (encoder, registry) =>
					{
						var bgEntries = BindGroupEntry[3](
							BindGroupEntry.Buffer(paramsBuffer, 0, 16),
							BindGroupEntry.Texture(hiZView),
							BindGroupEntry.Sampler(hiZSampler)
						);
						let bgResult = device.CreateBindGroup(BindGroupDesc()
						{
							Layout = debugLayout,
							Entries = Span<BindGroupEntry>(&bgEntries[0], 3),
							Label = "DebugHiZBindGroup"
						});
						if (bgResult case .Err) return;
						let bg = bgResult.Value;

						let rpDesc = registry.GetRenderPassDesc(graphPass);
						let rp = encoder.BeginRenderPass(rpDesc);
						rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
						rp.SetScissor(0, 0, renderW, renderH);
						rp.SetPipeline(debugPipeline);
						rp.SetBindGroup(0, bg);
						rp.Draw(3, 1, 0, 0);
						rp.End();

						var bgRef = bg;
						device.DestroyBindGroup(ref bgRef);
					});
				});
				return;
			}
		}

		// Debug motion vector visualization mode
		if (DebugMotionVectors)
		{
			let motionFeature = mSystem.GetFeature<MotionVectorFeature>();
			if (motionFeature == null) return;
			let motionTex = motionFeature.MotionVectorTexture;
			if (!motionTex.IsValid) return;

			let debugPipeline = mDebugMVPipeline;
			let debugLayout = mDebugMVLayout;

			graph.AddPass("BlitToScreen", .Graphics, scope [&] (builder) =>
			{
				builder.ReadTexture(sceneColorTex, .Fragment);
				builder.ReadTexture(motionTex, .Fragment);
				builder.WriteRenderTarget(backbuffer, 0, .Clear, .Store,
					ClearColor(0.0f, 0.0f, 0.0f, 1.0f));
				builder.HasSideEffects();

				let graphPass = builder.Pass;
				builder.SetExecute(new [=] (encoder, registry) =>
				{
					let sceneColorView = registry.GetTextureView(sceneColorTex);
					let motionView = registry.GetTextureView(motionTex);
					if (sceneColorView == null || motionView == null) return;

					var bgEntries = BindGroupEntry[3](
						BindGroupEntry.Texture(sceneColorView),
						BindGroupEntry.Texture(motionView),
						BindGroupEntry.Sampler(sampler)
					);
					let bgResult = device.CreateBindGroup(BindGroupDesc()
					{
						Layout = debugLayout,
						Entries = Span<BindGroupEntry>(&bgEntries[0], 3),
						Label = "DebugMVBindGroup"
					});
					if (bgResult case .Err) return;
					let bg = bgResult.Value;

					let rpDesc = registry.GetRenderPassDesc(graphPass);
					let rp = encoder.BeginRenderPass(rpDesc);
					rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
					rp.SetScissor(0, 0, renderW, renderH);
					rp.SetPipeline(debugPipeline);
					rp.SetBindGroup(0, bg);
					rp.Draw(3, 1, 0, 0);
					rp.End();

					var bgRef = bg;
					device.DestroyBindGroup(ref bgRef);
				});
			});
			return;
		}

		// Normal blit path — use passthrough pipeline when post-process stack already tonemapped
		let usePassthrough = postStack != null && postStack.HasEnabledEffects && mBlitPassthroughPipeline != null;
		let pipeline = usePassthrough ? mBlitPassthroughPipeline : mBlitPipeline;
		let blitLayout = mBlitLayout;

		graph.AddPass("BlitToScreen", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(sceneColorTex, .Fragment);
			builder.WriteRenderTarget(backbuffer, 0, .Clear, .Store,
				ClearColor(0.0f, 0.0f, 0.0f, 1.0f));
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let sceneColorView = registry.GetTextureView(sceneColorTex);
				if (sceneColorView == null) return;

				var bgEntries = BindGroupEntry[2](
					BindGroupEntry.Texture(sceneColorView),
					BindGroupEntry.Sampler(sampler)
				);
				let bgResult = device.CreateBindGroup(BindGroupDesc()
				{
					Layout = blitLayout,
					Entries = Span<BindGroupEntry>(&bgEntries[0], 2),
					Label = "BlitBindGroup"
				});
				if (bgResult case .Err) return;
				let blitBindGroup = bgResult.Value;

				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);
				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
				rp.SetScissor(0, 0, renderW, renderH);
				rp.SetPipeline(pipeline);
				rp.SetBindGroup(0, blitBindGroup);
				rp.Draw(3, 1, 0, 0);
				rp.End();

				var bg = blitBindGroup;
				device.DestroyBindGroup(ref bg);
			});
		});
	}

	public void OnPostRender() { }

	public void OnShutdown(IDevice device)
	{
		if (mBlitPassthroughPipeline != null)
			device.DestroyRenderPipeline(ref mBlitPassthroughPipeline);
		if (mBlitPipeline != null)
			device.DestroyRenderPipeline(ref mBlitPipeline);
		if (mBlitPipelineLayout != null)
			device.DestroyPipelineLayout(ref mBlitPipelineLayout);
		if (mBlitLayout != null)
			device.DestroyBindGroupLayout(ref mBlitLayout);
		if (mDebugHiZPipeline != null)
			device.DestroyRenderPipeline(ref mDebugHiZPipeline);
		if (mDebugHiZPipelineLayout != null)
			device.DestroyPipelineLayout(ref mDebugHiZPipelineLayout);
		if (mDebugHiZLayout != null)
			device.DestroyBindGroupLayout(ref mDebugHiZLayout);
		if (mDebugHiZParamsBuffer != null)
			{ mDebugHiZParamsBuffer.Unmap(); device.DestroyBuffer(ref mDebugHiZParamsBuffer); }
		if (mDebugMVPipeline != null)
			device.DestroyRenderPipeline(ref mDebugMVPipeline);
		if (mDebugMVPipelineLayout != null)
			device.DestroyPipelineLayout(ref mDebugMVPipelineLayout);
		if (mDebugMVLayout != null)
			device.DestroyBindGroupLayout(ref mDebugMVLayout);
		if (mLinearSampler != null)
			device.DestroySampler(ref mLinearSampler);
	}
}

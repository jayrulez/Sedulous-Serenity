namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// Final output render feature.
/// Blits the scene color to the swapchain for presentation.
///
/// This feature integrates with the render graph's automatic barrier system:
/// - SceneColor (transient) gets automatic ColorAttachment → ShaderReadOnly barrier
/// - Swapchain (imported) is handled by the driver, no explicit barrier needed
///
public class FinalOutputFeature : RenderFeatureBase
{
	/// GPU-packed blit parameters.
	/// Layout MUST match blit.frag.hlsl BlitParams cbuffer.
	[CRepr]
	private struct BlitParams
	{
		public float Exposure;
		public int32 Passthrough; // 1 = skip tonemapping (when PostProcess tonemap is active)
		public float _Pad1;
		public float _Pad2;

		public static int Size => 16;
	}

	// Blit pipeline
	private IRenderPipeline mBlitPipeline ~ delete _;
	private IPipelineLayout mBlitPipelineLayout ~ delete _;
	private IBindGroupLayout mBlitBindGroupLayout ~ delete _;
	private ISampler mLinearSampler ~ delete _;

	// Per-frame uniform buffers for blit params (exposure etc.)
	private IBuffer[RenderConfig.FrameBufferCount] mBlitParamsBuffers;

	// Per-frame, per-view bind groups - recreated each frame since scene color is a transient resource
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mBlitBindGroups;

	// Swapchain reference (set each frame)
	private ISwapChain mSwapChain;

	// Current exposure value (updated from RenderWorld each frame)
	private float mExposure = 1.0f;

	/// Feature name.
	public override StringView Name => "FinalOutput";

	/// Depends on all rendering features being complete.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("Sky"); // Run after sky (last visual feature)
	}

	/// Sets the swapchain to output to.
	public void SetSwapChain(ISwapChain swapChain)
	{
		mSwapChain = swapChain;
	}

	protected override Result<void> OnInitialize()
	{
		// Create linear sampler for blit
		SamplerDescriptor samplerDesc = .()
		{
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge,
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Nearest
		};

		switch (Renderer.Device.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler): mLinearSampler = sampler;
		case .Err: return .Err;
		}

		// Create per-frame uniform buffers for blit params
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDescriptor bufDesc = .()
			{
				Label = "Blit Params",
				Size = (uint64)BlitParams.Size,
				Usage = .Uniform,
				MemoryAccess = .Upload
			};

			switch (Renderer.Device.CreateBuffer(&bufDesc))
			{
			case .Ok(let buf): mBlitParamsBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		// Create blit pipeline
		if (CreateBlitPipeline() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateBlitPipeline()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Load blit shaders
		let shaderResult = Renderer.ShaderSystem.GetShaderPair("blit");
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		// Create bind group layout: b0=blit params, t0=source texture, s0=sampler
		BindGroupLayoutEntry[3] layoutEntries = .(
			.() { Binding = 0, Visibility = .Fragment, Type = .UniformBuffer },  // b0
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture }, // t0
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }         // s0
		);

		BindGroupLayoutDescriptor layoutDesc = .()
		{
			Label = "Blit BindGroup Layout",
			Entries = layoutEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout): mBlitBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] bgLayouts = .(mBlitBindGroupLayout);
		PipelineLayoutDescriptor plDesc = .(bgLayouts);
		switch (Renderer.Device.CreatePipelineLayout(&plDesc))
		{
		case .Ok(let layout): mBlitPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Color targets - match swapchain format
		ColorTargetState[1] colorTargets = .(.(.BGRA8UnormSrgb));

		// Blit uses fullscreen triangle with SV_VertexID
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Label = "Blit Pipeline",
			Layout = mBlitPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = default // No vertex buffers - SV_VertexID
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
			DepthStencil = .None, // No depth attachment for blit
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mBlitPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mBlitParamsBuffers[i] != null)
			{
				delete mBlitParamsBuffers[i];
				mBlitParamsBuffers[i] = null;
			}
		}

		for (int i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mBlitBindGroups[i] != null)
			{
				delete mBlitBindGroups[i];
				mBlitBindGroups[i] = null;
			}
		}
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		if (mSwapChain == null)
			return;

		// Skip if swapchain has no valid texture (e.g., during resize or minimized)
		if (mSwapChain.CurrentTexture == null || mSwapChain.CurrentTextureView == null)
			return;

		// Import swapchain as render target
		let swapchainHandle = graph.ImportTexture("Swapchain", mSwapChain.CurrentTexture, mSwapChain.CurrentTextureView);

		// First view clears the swapchain, subsequent views load (preserving previous view's output)
		let isFirstView = (Renderer.RenderFrameContext?.ActiveViewIndex ?? 0) == 0;
		LoadOp loadOp = isFirstView ? .Clear : .Load;

		// Check for post-processed output first, then fall back to scene color
		var sourceHandle = Renderer.PostProcessOutput;
		if (!sourceHandle.IsValid)
			sourceHandle = graph.GetResource("SceneColor");

		// Update exposure from world
		mExposure = world.Exposure;

		// Capture viewport info for the blit callback
		uint32 vpX = view.ViewportX;
		uint32 vpY = view.ViewportY;
		uint32 vpW = view.Width;
		uint32 vpH = view.Height;

		if (sourceHandle.IsValid && mBlitPipeline != null)
		{
			// Full mode: blit source to swapchain
			RenderGraph graphRef = graph;
			RGResourceHandle colorHandle = sourceHandle;

			graph.AddGraphicsPass("FinalOutput")
				.ReadTexture(sourceHandle)
				.WriteColor(swapchainHandle, loadOp, .Store, .(0.0f, 0.0f, 0.0f, 1.0f))
				.NeverCull()
				.SetExecuteCallback(new [=](encoder) => {
					let sceneColorView = graphRef.GetTextureView(colorHandle);
					ExecuteBlitPass(encoder, sceneColorView, vpX, vpY, vpW, vpH);
				});
		}
		else
		{
			// Minimal mode: just clear swapchain
			graph.AddGraphicsPass("FinalOutput_Clear")
				.WriteColor(swapchainHandle, loadOp, .Store, .(1.0f, 0.0f, 1.0f, 1.0f))
				.NeverCull();
		}

		// Mark swapchain for Present layout transition only after the last view renders.
		// Earlier views leave the swapchain in ColorAttachment so subsequent views can render to it.
		let isLastView = (Renderer.RenderFrameContext?.ActiveViewIndex ?? 0) >= (Renderer.RenderFrameContext?.ViewCount ?? 1) - 1;
		if (isLastView)
			graph.MarkForPresent(swapchainHandle);
	}

	/// Executes the blit pass (called by render graph).
	private void ExecuteBlitPass(IRenderPassEncoder encoder, ITextureView sceneColorView, uint32 vpX, uint32 vpY, uint32 vpW, uint32 vpH)
	{
		if (mSwapChain == null || mBlitPipeline == null)
			return;

		if (sceneColorView == null)
		{
			Console.WriteLine("[FinalOutput] ERROR: sceneColorView is null!");
			return;
		}

		// Recreate bind group for current frame+view slot.
		let frameIndex = Renderer.RenderFrameContext?.FrameIndex ?? 0;
		let viewIndex = Renderer.RenderFrameContext?.ActiveViewIndex ?? 0;
		let bgIndex = frameIndex * RenderConfig.MaxViews + viewIndex;

		if (mBlitBindGroups[bgIndex] != null)
		{
			delete mBlitBindGroups[bgIndex];
			mBlitBindGroups[bgIndex] = null;
		}

		// Upload blit params (exposure) for this frame
		// When a TonemapEffect is active in PostProcessStack, use passthrough mode
		// (tonemapping already applied by the effect).
		bool hasTonemapEffect = Renderer.PostProcessStack?.GetEffect("Tonemap")?.Enabled ?? false;

		let paramsBuffer = mBlitParamsBuffers[frameIndex];
		if (paramsBuffer != null)
		{
			BlitParams blitParams = .()
			{
				Exposure = hasTonemapEffect ? 1.0f : mExposure,
				Passthrough = hasTonemapEffect ? 1 : 0
			};
			if (let ptr = paramsBuffer.Map())
			{
				Internal.MemCpy(ptr, &blitParams, BlitParams.Size);
				paramsBuffer.Unmap();
			}
		}

		// Create new bind group with current scene color
		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, paramsBuffer, 0, (uint64)BlitParams.Size),
			BindGroupEntry.Texture(0, sceneColorView),
			BindGroupEntry.Sampler(0, mLinearSampler)
		);

		BindGroupDescriptor bgDesc = .()
		{
			Label = "Blit BindGroup",
			Layout = mBlitBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&bgDesc) case .Ok(let bg))
			mBlitBindGroups[bgIndex] = bg;

		// Set viewport and scissor to this view's region
		encoder.SetViewport((float)vpX, (float)vpY, (float)vpW, (float)vpH, 0, 1);
		encoder.SetScissorRect((int32)vpX, (int32)vpY, vpW, vpH);

		// Draw fullscreen blit if bind group is ready
		if (mBlitBindGroups[bgIndex] != null)
		{
			encoder.SetPipeline(mBlitPipeline);
			encoder.SetBindGroup(0, mBlitBindGroups[bgIndex], default);
			encoder.Draw(3, 1, 0, 0);
			Renderer.Stats.DrawCalls++;
		}
		else
		{
			Console.WriteLine("[FinalOutput] ERROR: mBlitBindGroup is null!");
		}
	}

	/// Legacy method for manual blit (deprecated - use render graph integration instead).
	/// Kept for backwards compatibility during transition.
	[Obsolete("Use render graph integration instead. FinalOutput now runs as part of Execute().", false)]
	public void BlitToSwapchain(ICommandEncoder encoder, ITexture sceneColorTexture, ITextureView sceneColorView)
	{
		// No-op - the render graph handles this now
	}
}

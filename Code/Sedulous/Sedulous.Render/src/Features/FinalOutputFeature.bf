namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Final output render feature.
/// Blits the scene color to the swapchain for presentation.
///
/// This feature integrates with the render graph's automatic barrier system:
/// - SceneColor (transient) gets automatic ColorAttachment → ShaderReadOnly barrier
/// - Swapchain (imported) is handled by the driver, no explicit barrier needed
///
public class FinalOutputFeature : RenderFeatureBase
{
	// Blit pipeline
	private IRenderPipeline mBlitPipeline ~ delete _;
	private IPipelineLayout mBlitPipelineLayout ~ delete _;
	private IBindGroupLayout mBlitBindGroupLayout ~ delete _;
	private ISampler mLinearSampler ~ delete _;

	// Per-frame bind groups - recreated each frame since scene color is a transient resource
	private IBindGroup[RenderConfig.FrameBufferCount] mBlitBindGroups;

	// Swapchain reference (set each frame)
	private ISwapChain mSwapChain;

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

		// Create bind group layout: t0=source texture, s0=sampler
		BindGroupLayoutEntry[2] layoutEntries = .(
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

		// Check for post-processed output first, then fall back to scene color
		var sourceHandle = Renderer.PostProcessOutput;
		if (!sourceHandle.IsValid)
			sourceHandle = graph.GetResource("SceneColor");

		if (sourceHandle.IsValid && mBlitPipeline != null)
		{
			// Full mode: blit source (post-processed or scene color) to swapchain
			// Capture the graph and handle for use in the execute callback
			RenderGraph graphRef = graph;
			RGResourceHandle colorHandle = sourceHandle;

			graph.AddGraphicsPass("FinalOutput")
				.ReadTexture(sourceHandle)
				.WriteColor(swapchainHandle, .Clear, .Store, .(1.0f, 0.0f, 1.0f, 1.0f))
				.NeverCull()
				.SetExecuteCallback(new [=](encoder) => {
					// Get texture view INSIDE the callback - after the graph has allocated resources
					let sceneColorView = graphRef.GetTextureView(colorHandle);
					ExecuteBlitPass(encoder, sceneColorView);
				});
		}
		else
		{
			// Minimal mode: just clear swapchain to a test color (magenta for visibility)
			// The render pass LoadOp.Clear handles the actual clear - no execute callback needed
			graph.AddGraphicsPass("FinalOutput_Clear")
				.WriteColor(swapchainHandle, .Clear, .Store, .(1.0f, 0.0f, 1.0f, 1.0f))
				.NeverCull();
		}

		// Mark swapchain for Present layout transition at end of frame
		graph.MarkForPresent(swapchainHandle);
	}

	/// Executes the blit pass (called by render graph).
	private void ExecuteBlitPass(IRenderPassEncoder encoder, ITextureView sceneColorView)
	{
		if (mSwapChain == null || mBlitPipeline == null)
			return;

		if (sceneColorView == null)
		{
			Console.WriteLine("[FinalOutput] ERROR: sceneColorView is null!");
			return;
		}

		// Recreate bind group for current frame slot only.
		// Only the current frame's fence has been waited, so only its bind group is safe to free.
		let frameIndex = Renderer.RenderFrameContext?.FrameIndex ?? 0;

		if (mBlitBindGroups[frameIndex] != null)
		{
			delete mBlitBindGroups[frameIndex];
			mBlitBindGroups[frameIndex] = null;
		}

		// Create new bind group with current scene color
		BindGroupEntry[2] entries = .(
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
			mBlitBindGroups[frameIndex] = bg;

		// Set viewport and scissor
		encoder.SetViewport(0, 0, mSwapChain.Width, mSwapChain.Height, 0, 1);
		encoder.SetScissorRect(0, 0, mSwapChain.Width, mSwapChain.Height);

		// Draw fullscreen blit if bind group is ready
		if (mBlitBindGroups[frameIndex] != null)
		{
			encoder.SetPipeline(mBlitPipeline);
			encoder.SetBindGroup(0, mBlitBindGroups[frameIndex], default);
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

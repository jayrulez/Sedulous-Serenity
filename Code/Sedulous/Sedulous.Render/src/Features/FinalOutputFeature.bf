namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Final output render feature.
/// Blits the scene color to the swapchain for presentation.
///
/// ## Current Implementation (Manual Barriers)
///
/// The render graph does not yet support automatic image layout transitions/barriers.
/// Therefore, this feature operates OUTSIDE the render graph:
///
/// 1. `AddPasses()` does nothing - no render graph integration
/// 2. Application must call `BlitToSwapchain()` manually after `RenderGraph.Execute()`
/// 3. `BlitToSwapchain()` manually inserts the texture barrier and creates the render pass
///
/// Example usage:
/// ```
/// renderSystem.Execute(encoder);
/// finalOutputFeature.BlitToSwapchain(encoder, sceneColorTexture, sceneColorView);
/// ```
///
/// ## Future Implementation (Automatic Barriers)
///
/// When the render graph supports automatic layout transitions, refactor as follows:
///
/// 1. Move `BlitToSwapchain()` logic into `AddPasses()`:
///    ```
///    graph.AddGraphicsPass("FinalOutput")
///        .ReadTexture(colorHandle)  // RG will insert ColorAttachment->ShaderReadOnly barrier
///        .WriteColor(swapchainHandle, .Clear, .Store, clearColor)
///        .NeverCull()
///        .SetExecuteCallback(new (encoder) => ExecuteBlitPass(encoder));
///    ```
///
/// 2. Remove the manual `BlitToSwapchain()` method
///
/// 3. Application code simplifies to just:
///    ```
///    renderSystem.Execute(encoder);  // FinalOutput pass runs automatically
///    ```
///
/// 4. The render graph will handle:
///    - Barrier insertion before ReadTexture resources
///    - Swapchain layout transitions for presentation
///    - Pass ordering based on dependencies
///
public class FinalOutputFeature : RenderFeatureBase
{
	// Blit pipeline
	private IRenderPipeline mBlitPipeline ~ delete _;
	private IPipelineLayout mBlitPipelineLayout ~ delete _;
	private IBindGroupLayout mBlitBindGroupLayout ~ delete _;
	private ISampler mLinearSampler ~ delete _;

	// Bind group (recreated when scene color changes)
	private IBindGroup mBlitBindGroup ~ delete _;
	private ITextureView mLastSceneColorView;

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
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		// FinalOutput doesn't add render graph passes - it runs manually after the graph
		// to properly handle swapchain transitions and barriers.
	}

	/// Blits the scene color to the swapchain.
	/// Call this AFTER RenderGraph.Execute() to present the final image.
	public void BlitToSwapchain(ICommandEncoder encoder, ITexture sceneColorTexture, ITextureView sceneColorView)
	{
		if (mSwapChain == null || mBlitPipeline == null)
			return;

		// Transition SceneColor from ColorAttachment to ShaderReadOnly for sampling
		if (sceneColorTexture != null)
			encoder.TextureBarrier(sceneColorTexture, .ColorAttachment, .ShaderReadOnly);

		// Create or update bind group if scene color view changed
		if (sceneColorView != null && sceneColorView != mLastSceneColorView)
		{
			// Release old bind group
			if (mBlitBindGroup != null)
			{
				delete mBlitBindGroup;
				mBlitBindGroup = null;
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
				mBlitBindGroup = bg;

			mLastSceneColorView = sceneColorView;
		}

		// Create render pass for swapchain
		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = mSwapChain.CurrentTextureView,
			ResolveTarget = null,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = .(0.0f, 0.0f, 0.0f, 1.0f)
		});

		RenderPassDescriptor desc = .(colorAttachments);

		let renderPass = encoder.BeginRenderPass(&desc);
		if (renderPass == null)
			return;
		defer { renderPass.End(); delete renderPass; }

		renderPass.SetViewport(0, 0, mSwapChain.Width, mSwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, mSwapChain.Width, mSwapChain.Height);

		// Draw fullscreen blit if bind group is ready
		if (mBlitBindGroup != null)
		{
			renderPass.SetPipeline(mBlitPipeline);
			renderPass.SetBindGroup(0, mBlitBindGroup, default);
			renderPass.Draw(3, 1, 0, 0);
			Renderer.Stats.DrawCalls++;
		}
	}
}

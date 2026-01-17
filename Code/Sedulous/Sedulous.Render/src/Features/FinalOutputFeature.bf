namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Final output render feature.
/// Blits the scene color to the swapchain for presentation.
/// This feature must be registered last as it outputs to the swapchain.
public class FinalOutputFeature : RenderFeatureBase
{
	// Blit pipeline
	private IRenderPipeline mBlitPipeline ~ delete _;
	private IPipelineLayout mBlitPipelineLayout ~ delete _;
	private IBindGroupLayout mBlitBindGroupLayout ~ delete _;
	private ISampler mLinearSampler ~ delete _;

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
		if (mSwapChain == null)
			return;

		// Get scene color buffer
		let colorHandle = graph.GetResource("SceneColor");
		if (!colorHandle.IsValid)
			return;

		// Import swapchain as output target
		let swapchainHandle = graph.ImportTexture(
			"Swapchain",
			mSwapChain.CurrentTexture,
			mSwapChain.CurrentTextureView
		);

		// Add final blit pass
		graph.AddGraphicsPass("FinalOutput")
			.ReadTexture(colorHandle)
			.WriteColor(swapchainHandle, .Clear, .Store, .(0.0f, 0.0f, 0.0f, 1.0f))
			.NeverCull()
			.SetExecuteCallback(new (encoder) => {
				ExecuteBlitPass(encoder, view, colorHandle);
			});
	}

	private void ExecuteBlitPass(IRenderPassEncoder encoder, RenderView view, RGResourceHandle colorHandle)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// If blit pipeline isn't ready, the render pass will just clear the swapchain
		// This ensures the swapchain is transitioned to the correct layout for presentation
		if (mBlitPipeline == null)
			return;

		// Set pipeline
		encoder.SetPipeline(mBlitPipeline);

		// TODO: Create and bind the source texture bind group
		// For now, the render pass clears the swapchain.
		// Full blit implementation requires the render graph to provide resolved texture views.

		// Draw fullscreen triangle
		encoder.Draw(3, 1, 0, 0);
		Renderer.Stats.DrawCalls++;
	}
}

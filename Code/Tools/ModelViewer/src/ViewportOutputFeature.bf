namespace ModelViewer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Render;

/// Custom render feature that blits rendered content to a viewport texture.
/// Similar to FinalOutputFeature but outputs to an external texture instead of swapchain.
public class ViewportOutputFeature : RenderFeatureBase
{
	/// GPU-packed blit parameters.
	/// Layout MUST match blit.frag.hlsl BlitParams cbuffer.
	[CRepr]
	private struct BlitParams
	{
		public float Exposure;
		public float _Pad0;
		public float _Pad1;
		public float _Pad2;

		public static int Size => 16;
	}

	// Blit pipeline resources
	private IRenderPipeline mBlitPipeline ~ delete _;
	private IPipelineLayout mBlitPipelineLayout ~ delete _;
	private IBindGroupLayout mBlitBindGroupLayout ~ delete _;
	private ISampler mLinearSampler ~ delete _;

	// Per-frame uniform buffers for blit params
	private IBuffer[RenderConfig.FrameBufferCount] mBlitParamsBuffers;

	// Per-frame bind groups
	private IBindGroup[RenderConfig.FrameBufferCount] mBlitBindGroups;

	// External target textures (set each frame)
	private ITexture mColorTexture;
	private ITextureView mColorTextureView;
	private uint32 mWidth;
	private uint32 mHeight;

	// Current exposure value
	private float mExposure = 1.0f;

	/// Feature name.
	public override StringView Name => "ViewportOutput";

	/// This feature runs after all rendering.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("Sky");
	}

	/// Sets the output target textures for the current frame.
	public void SetOutputTarget(ITexture colorTexture, ITextureView colorView,
		ITexture depthTexture, ITextureView depthView, uint32 width, uint32 height)
	{
		mColorTexture = colorTexture;
		mColorTextureView = colorView;
		mWidth = width;
		mHeight = height;
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
				Label = "ViewportBlit Params",
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
			Label = "ViewportBlit BindGroup Layout",
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

		// Color targets - match viewport format (RGBA8Unorm)
		ColorTargetState[1] colorTargets = .(.(.RGBA8Unorm));

		// Blit uses fullscreen triangle with SV_VertexID
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Label = "ViewportBlit Pipeline",
			Layout = mBlitPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = default
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
			DepthStencil = .None,
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
			if (mBlitBindGroups[i] != null)
			{
				delete mBlitBindGroups[i];
				mBlitBindGroups[i] = null;
			}
		}
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		if (mColorTexture == null)
			return;

		// Import the viewport color texture as output target
		let viewportHandle = graph.ImportTexture("ViewportColor", mColorTexture, mColorTextureView);

		// Get scene color (rendered by ForwardOpaque)
		var sourceHandle = Renderer.PostProcessOutput;
		if (!sourceHandle.IsValid)
			sourceHandle = graph.GetResource("SceneColor");

		// Update exposure from world
		mExposure = world.Exposure;

		if (sourceHandle.IsValid && mBlitPipeline != null)
		{
			// Capture values for the lambda
			RenderGraph graphRef = graph;
			RGResourceHandle colorHandle = sourceHandle;
			uint32 vpW = mWidth;
			uint32 vpH = mHeight;

			graph.AddGraphicsPass("ViewportOutput")
				.ReadTexture(sourceHandle)
				.WriteColor(viewportHandle, .Clear, .Store, .(0.1f, 0.1f, 0.15f, 1.0f))
				.NeverCull()
				.SetExecuteCallback(new [=](encoder) => {
					let sceneColorView = graphRef.GetTextureView(colorHandle);
					ExecuteBlitPass(encoder, sceneColorView, vpW, vpH);
				});
		}
		else
		{
			// Fallback: just clear the viewport
			graph.AddGraphicsPass("ViewportOutput_Clear")
				.WriteColor(viewportHandle, .Clear, .Store, .(0.1f, 0.1f, 0.15f, 1.0f))
				.NeverCull();
		}
	}

	private void ExecuteBlitPass(IRenderPassEncoder encoder, ITextureView sceneColorView, uint32 vpW, uint32 vpH)
	{
		if (mBlitPipeline == null)
			return;

		if (sceneColorView == null)
		{
			Console.WriteLine("[ViewportOutput] ERROR: sceneColorView is null!");
			return;
		}

		// Recreate bind group for current frame
		let frameIndex = Renderer.RenderFrameContext?.FrameIndex ?? 0;

		if (mBlitBindGroups[frameIndex] != null)
		{
			delete mBlitBindGroups[frameIndex];
			mBlitBindGroups[frameIndex] = null;
		}

		// Upload blit params (exposure) for this frame
		let paramsBuffer = mBlitParamsBuffers[frameIndex];
		if (paramsBuffer != null)
		{
			BlitParams blitParams = .() { Exposure = mExposure };
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
			Label = "ViewportBlit BindGroup",
			Layout = mBlitBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&bgDesc) case .Ok(let bg))
			mBlitBindGroups[frameIndex] = bg;

		// Set viewport and scissor
		encoder.SetViewport(0, 0, (float)vpW, (float)vpH, 0, 1);
		encoder.SetScissorRect(0, 0, vpW, vpH);

		// Draw fullscreen blit
		if (mBlitBindGroups[frameIndex] != null)
		{
			encoder.SetPipeline(mBlitPipeline);
			encoder.SetBindGroup(0, mBlitBindGroups[frameIndex], default);
			encoder.Draw(3, 1, 0, 0);
			Renderer.Stats.DrawCalls++;
		}
	}
}

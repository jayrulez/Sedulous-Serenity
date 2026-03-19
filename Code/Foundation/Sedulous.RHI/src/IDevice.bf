namespace Sedulous.RHI;

using System;
using System.Collections;

/// A logical GPU device for creating resources and submitting commands.
interface IDevice : IDisposable
{
	/// The adapter this device was created from.
	IAdapter Adapter { get; }

	/// The main command queue.
	IQueue Queue { get; }

	/// Whether projection matrices need Y-axis flipping for this backend.
	/// True for Vulkan (Y points down in NDC), false for OpenGL/DirectX (Y points up).
	bool FlipProjectionRequired { get; }

	// ===== Resource Creation =====

	/// Creates a buffer.
	Result<IBuffer> CreateBuffer(BufferDesc descriptor);

	/// Creates a texture.
	Result<ITexture> CreateTexture(TextureDesc descriptor);

	/// Creates a texture view.
	Result<ITextureView> CreateTextureView(ITexture texture, TextureViewDesc descriptor);

	/// Creates a sampler.
	Result<ISampler> CreateSampler(SamplerDesc descriptor);

	/// Creates a shader module from compiled bytecode.
	Result<IShaderModule> CreateShaderModule(ShaderModuleDesc descriptor);

	// ===== Binding =====

	/// Creates a bind group layout.
	Result<IBindGroupLayout> CreateBindGroupLayout(BindGroupLayoutDesc descriptor);

	/// Creates a bind group.
	Result<IBindGroup> CreateBindGroup(BindGroupDesc descriptor);

	/// Creates a pipeline layout.
	Result<IPipelineLayout> CreatePipelineLayout(PipelineLayoutDesc descriptor);

	// ===== Pipelines =====

	/// Creates a render pipeline.
	Result<IRenderPipeline> CreateRenderPipeline(RenderPipelineDesc descriptor);

	/// Creates a compute pipeline.
	Result<IComputePipeline> CreateComputePipeline(ComputePipelineDesc descriptor);

	// ===== Commands =====

	/// Creates a command encoder for recording commands.
	ICommandEncoder CreateCommandEncoder();

	// ===== Queries =====

	/// Creates a query set for GPU timing, occlusion, or pipeline statistics.
	Result<IQuerySet> CreateQuerySet(QuerySetDesc descriptor);

	// ===== Presentation =====

	/// Creates a swap chain for presenting to a surface.
	Result<ISwapChain> CreateSwapChain(ISurface surface, SwapChainDesc descriptor);

	// ===== Synchronization =====

	/// Creates a fence.
	Result<IFence> CreateFence(bool signaled = false);

	/// Waits for all GPU operations to complete.
	void WaitIdle();
}

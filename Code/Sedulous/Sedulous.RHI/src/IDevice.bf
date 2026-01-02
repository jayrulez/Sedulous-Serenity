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

	// ===== Resource Creation =====

	/// Creates a buffer.
	Result<IBuffer> CreateBuffer(BufferDescriptor* descriptor);

	/// Creates a texture.
	Result<ITexture> CreateTexture(TextureDescriptor* descriptor);

	/// Creates a texture view.
	Result<ITextureView> CreateTextureView(ITexture texture, TextureViewDescriptor* descriptor);

	/// Creates a sampler.
	Result<ISampler> CreateSampler(SamplerDescriptor* descriptor);

	/// Creates a shader module from compiled bytecode.
	Result<IShaderModule> CreateShaderModule(ShaderModuleDescriptor* descriptor);

	// ===== Binding =====

	/// Creates a bind group layout.
	Result<IBindGroupLayout> CreateBindGroupLayout(BindGroupLayoutDescriptor* descriptor);

	/// Creates a bind group.
	Result<IBindGroup> CreateBindGroup(BindGroupDescriptor* descriptor);

	/// Creates a pipeline layout.
	Result<IPipelineLayout> CreatePipelineLayout(PipelineLayoutDescriptor* descriptor);

	// ===== Pipelines =====

	/// Creates a render pipeline.
	Result<IRenderPipeline> CreateRenderPipeline(RenderPipelineDescriptor* descriptor);

	/// Creates a compute pipeline.
	Result<IComputePipeline> CreateComputePipeline(ComputePipelineDescriptor* descriptor);

	// ===== Commands =====

	/// Creates a command encoder for recording commands.
	ICommandEncoder CreateCommandEncoder();

	// ===== Presentation =====

	/// Creates a swap chain for presenting to a surface.
	Result<ISwapChain> CreateSwapChain(ISurface surface, SwapChainDescriptor* descriptor);

	// ===== Synchronization =====

	/// Creates a fence.
	Result<IFence> CreateFence(bool signaled = false);

	/// Waits for all GPU operations to complete.
	void WaitIdle();
}

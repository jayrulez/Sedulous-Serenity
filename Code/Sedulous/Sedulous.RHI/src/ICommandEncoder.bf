namespace Sedulous.RHI;

/// Encodes commands to be submitted to the GPU.
interface ICommandEncoder
{
	/// Begins a render pass.
	IRenderPassEncoder BeginRenderPass(RenderPassDescriptor* descriptor);

	/// Begins a compute pass.
	IComputePassEncoder BeginComputePass();

	/// Copies data from one buffer to another.
	void CopyBufferToBuffer(IBuffer source, uint64 sourceOffset, IBuffer destination, uint64 destinationOffset, uint64 size);

	/// Copies data from a buffer to a texture.
	void CopyBufferToTexture(IBuffer source, ITexture destination, BufferTextureCopyInfo* copyInfo);

	/// Copies data from a texture to a buffer.
	void CopyTextureToBuffer(ITexture source, IBuffer destination, BufferTextureCopyInfo* copyInfo);

	/// Copies data from one texture to another.
	void CopyTextureToTexture(ITexture source, ITexture destination, TextureCopyInfo* copyInfo);

	/// Finishes recording and returns an immutable command buffer.
	ICommandBuffer Finish();
}

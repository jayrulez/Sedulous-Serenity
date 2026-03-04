namespace Sedulous.RHI;

using System;

/// A command queue for submitting work to the GPU.
interface IQueue
{
	/// Submits command buffers for execution.
	void Submit(Span<ICommandBuffer> commandBuffers);

	/// Submits a single command buffer for execution.
	void Submit(ICommandBuffer commandBuffer);

	/// Submits command buffers for execution with swap chain synchronization.
	/// Use this when rendering to a swap chain to ensure proper synchronization
	/// between image acquisition, rendering, and presentation.
	void Submit(Span<ICommandBuffer> commandBuffers, ISwapChain swapChain);

	/// Submits a single command buffer with swap chain synchronization.
	void Submit(ICommandBuffer commandBuffer, ISwapChain swapChain);

	/// Direct CPU write to a host-visible buffer (Upload/Readback memory).
	/// Zero GPU synchronization. Asserts if buffer is not mappable.
	void WriteMappedBuffer(IBuffer buffer, uint64 offset, Span<uint8> data);

	/// Staging upload to any buffer. Creates temp staging buffer, GPU copy, vkQueueWaitIdle.
	/// Use only for initialization or infrequent updates to device-local buffers.
	void WriteStagedBufferSync(IBuffer buffer, uint64 offset, Span<uint8> data);

	/// Staging upload to a texture. Always synchronous (staging + GPU copy + wait).
	/// Textures cannot be memory-mapped; this is the only write path.
	void WriteTextureSync(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout, Extent3D* writeSize, uint32 mipLevel = 0, uint32 arrayLayer = 0);

	/// Direct CPU read from a host-visible buffer (Readback memory).
	/// Zero GPU synchronization. Asserts if buffer is not mappable.
	void ReadMappedBuffer(IBuffer buffer, uint64 offset, Span<uint8> data);

	/// Staging read from any buffer. GPU copy to staging + vkQueueWaitIdle.
	void ReadStagedBufferSync(IBuffer buffer, uint64 offset, Span<uint8> data);

	/// Staging read from a texture. Always synchronous.
	void ReadTextureSync(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout, Extent3D* readSize, uint32 mipLevel = 0, uint32 arrayLayer = 0);

	/// Gets the timestamp period in nanoseconds.
	/// Multiply GPU timestamp values by this to convert to nanoseconds.
	float GetTimestampPeriod();
}

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

	/// Writes data to a buffer (convenience method, may be slower than staging).
	void WriteBuffer(IBuffer buffer, uint64 offset, Span<uint8> data);

	/// Writes data to a texture (convenience method, may be slower than staging).
	void WriteTexture(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout, Extent3D* writeSize, uint32 mipLevel = 0, uint32 arrayLayer = 0);

	/// Reads data from a buffer back to CPU memory.
	/// This is a synchronous operation that waits for the GPU to complete.
	/// For better performance, use a staging buffer with MemoryAccess.Readback and Map/Unmap.
	void ReadBuffer(IBuffer buffer, uint64 offset, Span<uint8> data);

	/// Reads data from a texture back to CPU memory.
	/// This is a synchronous operation that waits for the GPU to complete.
	/// For better performance, use a staging buffer with MemoryAccess.Readback and Map/Unmap.
	void ReadTexture(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout, Extent3D* readSize, uint32 mipLevel = 0, uint32 arrayLayer = 0);

	/// Gets the timestamp period in nanoseconds.
	/// Multiply GPU timestamp values by this to convert to nanoseconds.
	float GetTimestampPeriod();
}

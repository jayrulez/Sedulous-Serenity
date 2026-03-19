using System;
namespace Sedulous.RHI;

/// Batches multiple GPU transfer operations into a single command buffer submission.
/// Created via IQueue.CreateTransferBatch(). Records transfers without submitting,
/// then Submit() executes all recorded transfers with a single GPU sync point.
/// Reusable after Submit() — can record more transfers and submit again.
/// Caller owns the object and must delete it when done.
interface ITransferBatch
{
	/// Records a staging upload to a texture. Does not submit — call Submit() when done.
	void WriteTexture(ITexture texture, Span<uint8> data, TextureDataLayout* dataLayout,
		Extent3D* writeSize, uint32 mipLevel = 0, uint32 arrayLayer = 0);

	/// Records a staging upload to a buffer. Does not submit — call Submit() when done.
	void WriteBuffer(IBuffer buffer, uint64 offset, Span<uint8> data);

	/// Submits all recorded transfers, waits for completion, and frees staging resources.
	/// No-op if no transfers were recorded. Batch is reusable after this call.
	void Submit();
}

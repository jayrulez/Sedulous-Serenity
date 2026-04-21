namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;

/// Batches staging → GPU buffer copies for buffers that cannot be CpuToGpu + Storage
/// (DX12 UPLOAD heaps cannot have UAV access). Systems enqueue copies after their
/// CPU-side Map/Write/Unmap; RenderSystem.Execute flushes the queue on the command
/// encoder before the render graph runs, followed by a single memory barrier.
public class StagedBufferCopyQueue
{
	private struct CopyEntry
	{
		public IBuffer Staging;
		public IBuffer Gpu;
		public uint64 Size;
	}

	private List<CopyEntry> mEntries = new .() ~ delete _;

	/// Enqueues a staging → GPU buffer copy. Call after Map/Write/Unmap on the staging buffer.
	/// The copy is deferred until Flush() is called on the command encoder.
	public void Enqueue(IBuffer staging, IBuffer gpu, uint64 size)
	{
		if (staging == null || gpu == null || size == 0)
			return;

		mEntries.Add(.() { Staging = staging, Gpu = gpu, Size = size });
	}

	/// Issues all queued CopyBufferToBuffer commands on the encoder, then emits a
	/// single memory barrier (CopyDst → ShaderRead) so subsequent render/compute
	/// passes can safely read the GPU buffers. Clears the queue afterwards.
	public void Flush(ICommandEncoder encoder)
	{
		if (mEntries.Count == 0)
			return;

		// Issue all copies
		for (let entry in mEntries)
			encoder.CopyBufferToBuffer(entry.Staging, 0, entry.Gpu, 0, entry.Size);

		// Single memory barrier: all copies done → all shader reads safe.
		// Using a global memory barrier is simpler than per-buffer barriers and
		// covers all the destination buffers in one call.
		var mb = MemoryBarrier() { OldState = .CopyDst, NewState = .ShaderRead };
		encoder.Barrier(.() { MemoryBarriers = .(&mb, 1) });

		mEntries.Clear();
	}

	/// Number of pending copies (for diagnostics).
	public int32 PendingCount => (int32)mEntries.Count;
}

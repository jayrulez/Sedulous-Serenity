namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;

/// GPU-side bone buffer for skinned mesh animation.
/// Stores current + previous frame bone matrices for motion vectors.
/// Double-buffered per frame-in-flight to avoid CPU/GPU contention.
public class GPUBoneBuffer
{
	/// Per-frame GPU storage buffers for bone matrices (shader reads from here).
	public IBuffer[RenderConfig.FrameBufferCount] Buffers;
	/// Per-frame staging buffers (CpuToGpu, CPU writes here).
	public IBuffer[RenderConfig.FrameBufferCount] StagingBuffers;
	/// Mapped pointers to staging buffers for CPU writes.
	public void*[RenderConfig.FrameBufferCount] MappedPtrs;
	/// Number of bones this buffer supports.
	public uint16 BoneCount;
	/// Size in bytes per buffer.
	public uint64 Size;
	/// Reference count.
	public int32 RefCount;
	/// Generation for handle validation.
	public uint32 Generation;
	/// Whether this slot is in use.
	public bool IsActive;
	/// Whether staging data has been written and needs upload this frame.
	public bool[RenderConfig.FrameBufferCount] NeedsUpload;
	/// Whether each frame slot's GPU buffer has been used (for barrier tracking).
	/// First use: Undefined→CopyDst. Subsequent: ShaderRead→CopyDst.
	public bool[RenderConfig.FrameBufferCount] HasBeenUsed;

	/// Gets the GPU buffer for the given frame index (for shader binding).
	public IBuffer GetBuffer(int frameIndex) => Buffers[frameIndex];

	/// Frees GPU resources.
	public void Release(IDevice device)
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (Buffers[i] != null)
				device.DestroyBuffer(ref Buffers[i]);
			if (StagingBuffers[i] != null)
				device.DestroyBuffer(ref StagingBuffers[i]);
		}
		IsActive = false;
	}
}

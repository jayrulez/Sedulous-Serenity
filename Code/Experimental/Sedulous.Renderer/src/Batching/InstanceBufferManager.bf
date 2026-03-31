namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

/// Manages per-frame GPU instance buffers using a ring buffer pattern.
/// Each frame gets its own buffer to avoid GPU/CPU contention.
class InstanceBufferManager
{
	private IDevice mDevice;
	private IBuffer[RenderConfig.FrameBufferCount] mBuffers;
	private void*[RenderConfig.FrameBufferCount] mMappedPtrs;
	private uint32[RenderConfig.FrameBufferCount] mOffsets;
	private uint32 mCapacity;
	private int mCurrentFrame;

	/// Initializes instance buffers.
	public Result<void> Initialize(IDevice device, uint32 maxInstances = 65536)
	{
		mDevice = device;
		mCapacity = maxInstances * (uint32)sizeof(InstanceData);

		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			let result = device.CreateBuffer(BufferDesc()
			{
				Size = (uint64)mCapacity,
				Usage = .Vertex,
				Memory = .CpuToGpu,
				Label = "InstanceBuffer"
			});

			if (result case .Err)
				return .Err;

			mBuffers[i] = result.Value;
			mMappedPtrs[i] = mBuffers[i].Map();
		}

		return .Ok;
	}

	/// Resets the write offset for the current frame. Call once per frame.
	public void Reset(int frameIndex)
	{
		mCurrentFrame = frameIndex;
		mOffsets[frameIndex] = 0;
	}

	/// Allocates space for instances and returns the buffer + byte offset.
	/// Returns null buffer if capacity exceeded.
	public (IBuffer buffer, uint32 offset) AllocateInstances(uint32 count)
	{
		let size = count * (uint32)sizeof(InstanceData);

		if (mOffsets[mCurrentFrame] + size > mCapacity)
			return (null, 0);

		let offset = mOffsets[mCurrentFrame];
		mOffsets[mCurrentFrame] += size;
		return (mBuffers[mCurrentFrame], offset);
	}

	/// Uploads instance data at the given byte offset.
	public void UploadInstanceData(Span<InstanceData> data, uint32 bufferOffset)
	{
		if (mMappedPtrs[mCurrentFrame] == null) return;

		Internal.MemCpy(
			(uint8*)mMappedPtrs[mCurrentFrame] + bufferOffset,
			data.Ptr,
			data.Length * sizeof(InstanceData)
		);
	}

	/// Gets the current frame's instance buffer.
	public IBuffer CurrentBuffer => mBuffers[mCurrentFrame];

	/// Shuts down and releases all GPU resources.
	public void Shutdown()
	{
		if (mDevice == null) return;

		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mBuffers[i] != null)
			{
				mBuffers[i].Unmap();
				mMappedPtrs[i] = null;
				mDevice.DestroyBuffer(ref mBuffers[i]);
			}
		}
	}
}

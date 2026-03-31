namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

/// Per-object uniform data (256 bytes, aligned for dynamic offset UBO).
[CRepr]
struct ObjectUniforms
{
	public Matrix WorldMatrix;         // 64 bytes
	public Matrix PrevWorldMatrix;     // 64 bytes
	public Matrix NormalMatrix;        // 64 bytes (inverse-transpose for correct normal transform)
	public uint32 ObjectID;            // 4 bytes
	public uint32 MaterialID;          // 4 bytes
	public float[14] _Padding;        // 56 bytes
	// Total: 256 bytes
}

/// Manages per-object uniform buffers with dynamic offsets.
/// Buffers are sized [FrameBufferCount * MaxViews] so multiple views
/// can be batched into a single submission without overwriting each other.
class ObjectUniformManager
{
	private IDevice mDevice;
	private IBuffer[RenderConfig.TotalBufferSlots] mBuffers;
	private void*[RenderConfig.TotalBufferSlots] mMappedPtrs;
	private uint32[RenderConfig.TotalBufferSlots] mOffsets;
	private uint32 mCapacity;
	private int mCurrentSlot;

	/// Initializes object uniform buffers.
	public Result<void> Initialize(IDevice device, uint32 maxObjects = 4096)
	{
		mDevice = device;
		mCapacity = maxObjects * (uint32)sizeof(ObjectUniforms);

		for (int i = 0; i < RenderConfig.TotalBufferSlots; i++)
		{
			let result = device.CreateBuffer(BufferDesc()
			{
				Size = (uint64)mCapacity,
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "ObjectUniforms"
			});

			if (result case .Err)
				return .Err;

			mBuffers[i] = result.Value;
			mMappedPtrs[i] = mBuffers[i].Map();
		}

		return .Ok;
	}

	/// Resets the write offset for the current slot. Call once per view.
	public void Reset(int frameIndex, int viewIndex)
	{
		mCurrentSlot = RenderConfig.BufferSlot(frameIndex, viewIndex);
		mOffsets[mCurrentSlot] = 0;
	}

	/// Writes object uniforms and returns the byte offset for dynamic binding.
	/// Returns uint32.MaxValue if capacity is exceeded.
	public uint32 AllocateObject(ObjectUniforms uniforms)
	{
		var uniforms;
		if (mOffsets[mCurrentSlot] + (uint32)sizeof(ObjectUniforms) > mCapacity)
			return uint32.MaxValue;

		let offset = mOffsets[mCurrentSlot];
		if (mMappedPtrs[mCurrentSlot] != null)
		{
			Internal.MemCpy(
				(uint8*)mMappedPtrs[mCurrentSlot] + offset,
				&uniforms,
				sizeof(ObjectUniforms)
			);
		}
		mOffsets[mCurrentSlot] += (uint32)sizeof(ObjectUniforms);
		return offset;
	}

	/// Gets the current slot's object uniform buffer.
	public IBuffer CurrentBuffer => mBuffers[mCurrentSlot];

	/// Shuts down and releases all GPU resources.
	public void Shutdown()
	{
		if (mDevice == null) return;

		for (int i = 0; i < RenderConfig.TotalBufferSlots; i++)
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

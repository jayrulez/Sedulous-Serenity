namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;

/// Type of transient buffer.
enum TransientBufferType
{
	/// Vertex buffer for dynamic geometry.
	Vertex,
	/// Index buffer for dynamic geometry.
	Index,
	/// Uniform buffer for per-draw constants.
	Uniform,
	/// Storage buffer for compute data.
	Storage
}

/// Per-frame transient buffer with bump allocation.
/// Provides fast, frame-scoped allocations that reset each frame.
class TransientBuffer
{
	private IBuffer mBuffer;
	private void* mMappedPtr;
	private uint32 mSize;
	private uint32 mOffset;
	private uint32 mAlignment;
	private BufferUsage mUsage;

	/// Gets the underlying GPU buffer.
	public IBuffer Buffer => mBuffer;

	/// Gets the total size of the buffer.
	public uint32 Size => mSize;

	/// Gets the current allocation offset.
	public uint32 CurrentOffset => mOffset;

	/// Gets the remaining space in bytes.
	public uint32 RemainingSpace => mSize - mOffset;

	/// Gets whether the buffer is valid and mapped.
	public bool IsValid => mBuffer != null && mMappedPtr != null;

	public this(IDevice device, uint32 size, BufferUsage usage, uint32 alignment)
	{
		mSize = size;
		mOffset = 0;
		mAlignment = alignment;
		mUsage = usage;

		// Create the GPU buffer with Upload memory access for CPU writes
		BufferDescriptor desc = .(size, usage, .Upload);
		if (device.CreateBuffer(&desc) case .Ok(let buffer))
		{
			mBuffer = buffer;
			mMappedPtr = buffer.Map();
		}
	}

	public ~this()
	{
		if (mBuffer != null)
		{
			if (mMappedPtr != null)
				mBuffer.Unmap();
			delete mBuffer;
		}
	}

	/// Resets the buffer for a new frame.
	/// All previous allocations become invalid.
	public void Reset()
	{
		mOffset = 0;
	}

	/// Allocates memory from the buffer.
	/// Returns Invalid if there's not enough space.
	public TransientAllocation Allocate(uint32 size)
	{
		return AllocateAligned(size, mAlignment);
	}

	/// Allocates memory with custom alignment.
	/// Returns Invalid if there's not enough space.
	public TransientAllocation AllocateAligned(uint32 size, uint32 alignment)
	{
		if (!IsValid || size == 0)
			return .Invalid;

		// Align the current offset
		let alignedOffset = AlignUp(mOffset, alignment);

		// Check if we have enough space
		if (alignedOffset + size > mSize)
			return .Invalid;

		// Calculate the data pointer
		let dataPtr = (uint8*)mMappedPtr + alignedOffset;

		// Bump the offset
		mOffset = alignedOffset + size;

		return .(mBuffer, alignedOffset, size, dataPtr);
	}

	/// Allocates and writes data in one call.
	public TransientAllocation AllocateAndWrite<T>(T data) where T : struct
	{
		let alloc = AllocateAligned((.)sizeof(T), mAlignment);
		if (alloc.IsValid)
			alloc.Write(data);
		return alloc;
	}

	/// Allocates and writes a span of data.
	public TransientAllocation AllocateAndWriteSpan<T>(Span<T> data) where T : struct
	{
		let size = (uint32)(data.Length * sizeof(T));
		let alloc = AllocateAligned(size, mAlignment);
		if (alloc.IsValid)
			alloc.WriteSpan(data);
		return alloc;
	}

	/// Aligns a value up to the specified alignment.
	private static uint32 AlignUp(uint32 value, uint32 alignment)
	{
		return (value + alignment - 1) & ~(alignment - 1);
	}
}

/// Pool of transient buffers for per-frame allocations.
/// Uses a ring buffer approach with one buffer per frame in flight.
class TransientBufferPool
{
	private TransientBuffer[RenderConfig.MAX_FRAMES_IN_FLIGHT] mVertexBuffers;
	private TransientBuffer[RenderConfig.MAX_FRAMES_IN_FLIGHT] mIndexBuffers;
	private TransientBuffer[RenderConfig.MAX_FRAMES_IN_FLIGHT] mUniformBuffers;
	private int32 mCurrentFrame = 0;

	/// Gets the current frame's vertex buffer.
	public TransientBuffer VertexBuffer => mVertexBuffers[mCurrentFrame];

	/// Gets the current frame's index buffer.
	public TransientBuffer IndexBuffer => mIndexBuffers[mCurrentFrame];

	/// Gets the current frame's uniform buffer.
	public TransientBuffer UniformBuffer => mUniformBuffers[mCurrentFrame];

	/// Gets whether all buffers are valid.
	public bool IsValid
	{
		get
		{
			for (int i = 0; i < RenderConfig.MAX_FRAMES_IN_FLIGHT; i++)
			{
				if (mVertexBuffers[i] == null || !mVertexBuffers[i].IsValid)
					return false;
				if (mIndexBuffers[i] == null || !mIndexBuffers[i].IsValid)
					return false;
				if (mUniformBuffers[i] == null || !mUniformBuffers[i].IsValid)
					return false;
			}
			return true;
		}
	}

	/// Statistics for the current frame.
	public struct FrameStats
	{
		public uint32 VertexBytesUsed;
		public uint32 VertexBytesTotal;
		public uint32 IndexBytesUsed;
		public uint32 IndexBytesTotal;
		public uint32 UniformBytesUsed;
		public uint32 UniformBytesTotal;

		public float VertexUsagePercent => VertexBytesTotal > 0 ? (float)VertexBytesUsed / VertexBytesTotal * 100 : 0;
		public float IndexUsagePercent => IndexBytesTotal > 0 ? (float)IndexBytesUsed / IndexBytesTotal * 100 : 0;
		public float UniformUsagePercent => UniformBytesTotal > 0 ? (float)UniformBytesUsed / UniformBytesTotal * 100 : 0;
	}

	/// Gets statistics for the current frame's buffers.
	public FrameStats GetStats()
	{
		return .()
		{
			VertexBytesUsed = mVertexBuffers[mCurrentFrame]?.CurrentOffset ?? 0,
			VertexBytesTotal = mVertexBuffers[mCurrentFrame]?.Size ?? 0,
			IndexBytesUsed = mIndexBuffers[mCurrentFrame]?.CurrentOffset ?? 0,
			IndexBytesTotal = mIndexBuffers[mCurrentFrame]?.Size ?? 0,
			UniformBytesUsed = mUniformBuffers[mCurrentFrame]?.CurrentOffset ?? 0,
			UniformBytesTotal = mUniformBuffers[mCurrentFrame]?.Size ?? 0
		};
	}

	public this(IDevice device)
	{
		// Create buffers for each frame in flight
		for (int i = 0; i < RenderConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			mVertexBuffers[i] = new TransientBuffer(
				device,
				RenderConfig.TRANSIENT_VERTEX_BUFFER_SIZE,
				.Vertex,
				RenderConfig.VERTEX_BUFFER_ALIGNMENT
			);

			mIndexBuffers[i] = new TransientBuffer(
				device,
				RenderConfig.TRANSIENT_INDEX_BUFFER_SIZE,
				.Index,
				RenderConfig.INDEX_BUFFER_ALIGNMENT
			);

			mUniformBuffers[i] = new TransientBuffer(
				device,
				RenderConfig.TRANSIENT_UNIFORM_BUFFER_SIZE,
				.Uniform,
				RenderConfig.UNIFORM_BUFFER_ALIGNMENT
			);
		}
	}

	public ~this()
	{
		for (int i = 0; i < RenderConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			delete mVertexBuffers[i];
			delete mIndexBuffers[i];
			delete mUniformBuffers[i];
		}
	}

	/// Called at the start of each frame to reset the current frame's buffers.
	/// @param frameIndex The current frame index (0 to MAX_FRAMES_IN_FLIGHT-1).
	public void BeginFrame(int32 frameIndex)
	{
		mCurrentFrame = frameIndex % RenderConfig.MAX_FRAMES_IN_FLIGHT;

		// Reset the buffers for this frame
		mVertexBuffers[mCurrentFrame].Reset();
		mIndexBuffers[mCurrentFrame].Reset();
		mUniformBuffers[mCurrentFrame].Reset();
	}

	/// Allocates vertex data from the current frame's vertex buffer.
	public TransientAllocation AllocateVertices<T>(int count) where T : struct
	{
		let size = (uint32)(count * sizeof(T));
		return mVertexBuffers[mCurrentFrame].AllocateAligned(size, RenderConfig.VERTEX_BUFFER_ALIGNMENT);
	}

	/// Allocates and writes vertex data.
	public TransientAllocation AllocateVertices<T>(Span<T> data) where T : struct
	{
		return mVertexBuffers[mCurrentFrame].AllocateAndWriteSpan(data);
	}

	/// Allocates index data from the current frame's index buffer.
	public TransientAllocation AllocateIndices<T>(int count) where T : struct
	{
		let size = (uint32)(count * sizeof(T));
		return mIndexBuffers[mCurrentFrame].AllocateAligned(size, RenderConfig.INDEX_BUFFER_ALIGNMENT);
	}

	/// Allocates and writes index data.
	public TransientAllocation AllocateIndices<T>(Span<T> data) where T : struct
	{
		return mIndexBuffers[mCurrentFrame].AllocateAndWriteSpan(data);
	}

	/// Allocates uniform data from the current frame's uniform buffer.
	public TransientAllocation AllocateUniform<T>() where T : struct
	{
		return mUniformBuffers[mCurrentFrame].AllocateAligned((.)sizeof(T), RenderConfig.UNIFORM_BUFFER_ALIGNMENT);
	}

	/// Allocates and writes uniform data.
	public TransientAllocation AllocateUniform<T>(T data) where T : struct
	{
		return mUniformBuffers[mCurrentFrame].AllocateAndWrite(data);
	}

	/// Raw allocation from vertex buffer with custom size/alignment.
	public TransientAllocation AllocateRawVertex(uint32 size, uint32 alignment = 0)
	{
		return mVertexBuffers[mCurrentFrame].AllocateAligned(size, alignment > 0 ? alignment : RenderConfig.VERTEX_BUFFER_ALIGNMENT);
	}

	/// Raw allocation from index buffer with custom size/alignment.
	public TransientAllocation AllocateRawIndex(uint32 size, uint32 alignment = 0)
	{
		return mIndexBuffers[mCurrentFrame].AllocateAligned(size, alignment > 0 ? alignment : RenderConfig.INDEX_BUFFER_ALIGNMENT);
	}

	/// Raw allocation from uniform buffer with custom size/alignment.
	public TransientAllocation AllocateRawUniform(uint32 size, uint32 alignment = 0)
	{
		return mUniformBuffers[mCurrentFrame].AllocateAligned(size, alignment > 0 ? alignment : RenderConfig.UNIFORM_BUFFER_ALIGNMENT);
	}
}

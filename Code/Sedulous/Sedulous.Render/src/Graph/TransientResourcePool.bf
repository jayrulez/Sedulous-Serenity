namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;

/// Allocation from the transient buffer pool.
public struct TransientAllocation
{
	/// The buffer containing the allocation.
	public IBuffer Buffer;

	/// Offset within the buffer.
	public uint64 Offset;

	/// Size of the allocation.
	public uint64 Size;

	/// Whether this allocation is valid.
	public bool IsValid => Buffer != null;

	/// Invalid allocation.
	public static Self Invalid => .();
}

/// Per-frame transient buffer for temporary GPU allocations.
/// Uses a ring buffer approach with triple buffering.
class TransientBufferRing
{
	private IBuffer mBuffer;
	private uint64 mSize;
	private uint64 mOffset;
	private uint64 mAlignment;

	public IBuffer Buffer => mBuffer;
	public uint64 Size => mSize;
	public uint64 UsedBytes => mOffset;
	public uint64 FreeBytes => mSize - mOffset;

	public Result<void> Initialize(IDevice device, uint64 size, BufferUsage usage)
	{
		mSize = size;
		mAlignment = 256; // Common alignment for uniform buffers

		var desc = BufferDescriptor()
		{
			Size = size,
			Usage = usage | .CopyDst
		};

		if (device.CreateBuffer(&desc) case .Ok(let buffer))
		{
			mBuffer = buffer;
			return .Ok;
		}

		return .Err;
	}

	public void Reset()
	{
		mOffset = 0;
	}

	public TransientAllocation Allocate(uint64 size, uint64 alignment = 0)
	{
		var actualAlignment = alignment;
		if (actualAlignment == 0)
			actualAlignment = mAlignment;

		// Align offset
		let alignedOffset = (mOffset + actualAlignment - 1) & ~(actualAlignment - 1);
		let endOffset = alignedOffset + size;

		if (endOffset > mSize)
			return .Invalid;

		mOffset = endOffset;

		return .()
		{
			Buffer = mBuffer,
			Offset = alignedOffset,
			Size = size
		};
	}

	public void Shutdown()
	{
		if (mBuffer != null)
		{
			delete mBuffer;
			mBuffer = null;
		}
	}
}

/// Pool of per-frame transient buffers for temporary GPU allocations.
/// Supports multiple buffer types (uniform, vertex, index, storage).
public class TransientResourcePool : IDisposable
{
	private IDevice mDevice;
	private int32 mCurrentFrameIndex;

	// Triple-buffered uniform buffers
	private TransientBufferRing[RenderConfig.FrameBufferCount] mUniformBuffers;

	// Triple-buffered vertex/index staging buffers
	private TransientBufferRing[RenderConfig.FrameBufferCount] mVertexBuffers;

	// Triple-buffered storage buffers
	private TransientBufferRing[RenderConfig.FrameBufferCount] mStorageBuffers;

	/// Gets the device.
	public IDevice Device => mDevice;

	/// Gets the current frame index.
	public int32 FrameIndex => mCurrentFrameIndex;

	/// Initializes the pool.
	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create uniform buffer rings
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			mUniformBuffers[i] = new TransientBufferRing();
			if (mUniformBuffers[i].Initialize(device, RenderConfig.TransientBufferPoolSize, .Uniform) case .Err)
				return .Err;
		}

		// Create vertex buffer rings
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			mVertexBuffers[i] = new TransientBufferRing();
			if (mVertexBuffers[i].Initialize(device, RenderConfig.TransientBufferPoolSize, .Vertex | .Index) case .Err)
				return .Err;
		}

		// Create storage buffer rings
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			mStorageBuffers[i] = new TransientBufferRing();
			if (mStorageBuffers[i].Initialize(device, RenderConfig.TransientBufferPoolSize, .Storage) case .Err)
				return .Err;
		}

		return .Ok;
	}

	/// Begins a new frame.
	public void BeginFrame(int32 frameIndex)
	{
		mCurrentFrameIndex = frameIndex;

		// Reset current frame's buffers
		mUniformBuffers[frameIndex].Reset();
		mVertexBuffers[frameIndex].Reset();
		mStorageBuffers[frameIndex].Reset();
	}

	/// Ends the current frame.
	public void EndFrame()
	{
		// Nothing to do - buffers persist until next use of this frame index
	}

	/// Allocates from the uniform buffer pool.
	public TransientAllocation AllocateUniform(uint64 size, uint64 alignment = 256)
	{
		return mUniformBuffers[mCurrentFrameIndex].Allocate(size, alignment);
	}

	/// Allocates from the vertex/index buffer pool.
	public TransientAllocation AllocateVertex(uint64 size, uint64 alignment = 4)
	{
		return mVertexBuffers[mCurrentFrameIndex].Allocate(size, alignment);
	}

	/// Allocates from the storage buffer pool.
	public TransientAllocation AllocateStorage(uint64 size, uint64 alignment = 16)
	{
		return mStorageBuffers[mCurrentFrameIndex].Allocate(size, alignment);
	}

	/// Writes data to a transient uniform allocation.
	public TransientAllocation WriteUniform<T>(T* data) where T : struct
	{
		let size = (uint64)sizeof(T);
		let allocation = AllocateUniform(size);
		if (allocation.IsValid)
		{
			mDevice.Queue.WriteBuffer(allocation.Buffer, allocation.Offset, Span<uint8>((uint8*)data, (int)size));
		}
		return allocation;
	}

	/// Writes data to a transient uniform allocation.
	public TransientAllocation WriteUniform<T>(Span<T> data) where T : struct
	{
		let size = (uint64)(sizeof(T) * data.Length);
		let allocation = AllocateUniform(size);
		if (allocation.IsValid)
		{
			mDevice.Queue.WriteBuffer(allocation.Buffer, allocation.Offset, Span<uint8>((uint8*)data.Ptr, (int)size));
		}
		return allocation;
	}

	/// Writes vertex data to a transient allocation.
	public TransientAllocation WriteVertices<T>(Span<T> vertices) where T : struct
	{
		let size = (uint64)(sizeof(T) * vertices.Length);
		let allocation = AllocateVertex(size);
		if (allocation.IsValid)
		{
			mDevice.Queue.WriteBuffer(allocation.Buffer, allocation.Offset, Span<uint8>((uint8*)vertices.Ptr, (int)size));
		}
		return allocation;
	}

	/// Writes index data to a transient allocation.
	public TransientAllocation WriteIndices(Span<uint16> indices)
	{
		let size = (uint64)(sizeof(uint16) * indices.Length);
		let allocation = AllocateVertex(size, 2);
		if (allocation.IsValid)
		{
			mDevice.Queue.WriteBuffer(allocation.Buffer, allocation.Offset, Span<uint8>((uint8*)indices.Ptr, (int)size));
		}
		return allocation;
	}

	/// Writes index data to a transient allocation.
	public TransientAllocation WriteIndices(Span<uint32> indices)
	{
		let size = (uint64)(sizeof(uint32) * indices.Length);
		let allocation = AllocateVertex(size, 4);
		if (allocation.IsValid)
		{
			mDevice.Queue.WriteBuffer(allocation.Buffer, allocation.Offset, Span<uint8>((uint8*)indices.Ptr, (int)size));
		}
		return allocation;
	}

	/// Gets statistics for the current frame.
	public void GetStats(out uint64 uniformUsed, out uint64 vertexUsed, out uint64 storageUsed)
	{
		uniformUsed = mUniformBuffers[mCurrentFrameIndex].UsedBytes;
		vertexUsed = mVertexBuffers[mCurrentFrameIndex].UsedBytes;
		storageUsed = mStorageBuffers[mCurrentFrameIndex].UsedBytes;
	}

	public void Dispose()
	{
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mUniformBuffers[i] != null)
			{
				mUniformBuffers[i].Shutdown();
				delete mUniformBuffers[i];
			}
			if (mVertexBuffers[i] != null)
			{
				mVertexBuffers[i].Shutdown();
				delete mVertexBuffers[i];
			}
			if (mStorageBuffers[i] != null)
			{
				mStorageBuffers[i].Shutdown();
				delete mStorageBuffers[i];
			}
		}
	}
}

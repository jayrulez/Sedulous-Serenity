namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;

/// Allocation result from the uniform buffer allocator.
struct UniformAllocation
{
	/// The buffer containing the allocation.
	public IBuffer Buffer;

	/// Offset into the buffer.
	public uint64 Offset;

	/// Size of the allocation.
	public uint64 Size;

	/// Returns true if this is a valid allocation.
	public bool IsValid => Buffer != null;
}

/// Page of uniform buffer memory.
class UniformBufferPage
{
	public IBuffer Buffer;
	public uint64 Size;
	public uint64 UsedBytes;

	public this(IBuffer buffer, uint64 size)
	{
		Buffer = buffer;
		Size = size;
		UsedBytes = 0;
	}

	public ~this()
	{
		if (Buffer != null)
			delete Buffer;
	}

	/// Tries to allocate from this page.
	public bool TryAllocate(uint64 size, uint64 alignment, out UniformAllocation allocation)
	{
		// Align the current offset
		let alignedOffset = (UsedBytes + alignment - 1) & ~(alignment - 1);

		if (alignedOffset + size > Size)
		{
			allocation = default;
			return false;
		}

		allocation = .()
		{
			Buffer = Buffer,
			Offset = alignedOffset,
			Size = size
		};

		UsedBytes = alignedOffset + size;
		return true;
	}

	/// Resets the page for reuse.
	public void Reset()
	{
		UsedBytes = 0;
	}
}

/// Allocates uniform buffer memory for per-frame data.
/// Uses a ring buffer approach with multiple pages per frame.
class UniformBufferAllocator
{
	private IDevice mDevice;
	private uint64 mPageSize;
	private uint64 mMinAlignment;

	// Per-frame page lists
	private List<UniformBufferPage>[FrameConfig.MAX_FRAMES_IN_FLIGHT] mFramePages;
	private int32 mCurrentFrame = 0;

	/// Creates a uniform buffer allocator.
	/// pageSize: Size of each buffer page (default 256KB).
	/// minAlignment: Minimum alignment for allocations (default 256 for uniform buffers).
	public this(IDevice device, uint64 pageSize = 256 * 1024, uint64 minAlignment = 256)
	{
		mDevice = device;
		mPageSize = pageSize;
		mMinAlignment = minAlignment;

		for (int i = 0; i < FrameConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			mFramePages[i] = new .();
		}
	}

	public ~this()
	{
		for (int i = 0; i < FrameConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			for (let page in mFramePages[i])
				delete page;
			delete mFramePages[i];
		}
	}

	/// Begins a new frame, resetting allocations for the current frame.
	public void BeginFrame(int32 frameIndex)
	{
		mCurrentFrame = frameIndex % FrameConfig.MAX_FRAMES_IN_FLIGHT;

		// Reset all pages for this frame
		for (let page in mFramePages[mCurrentFrame])
		{
			page.Reset();
		}
	}

	/// Allocates uniform buffer memory.
	public Result<UniformAllocation> Allocate(uint64 size)
	{
		return Allocate(size, mMinAlignment);
	}

	/// Allocates uniform buffer memory with specified alignment.
	public Result<UniformAllocation> Allocate(uint64 size, uint64 alignment)
	{
		if (size == 0)
			return .Err;

		// Ensure minimum alignment
		var effectiveAlignment = Math.Max(alignment, mMinAlignment);

		let pages = mFramePages[mCurrentFrame];

		// Try to allocate from existing pages
		for (let page in pages)
		{
			if (page.TryAllocate(size, effectiveAlignment, let allocation))
				return .Ok(allocation);
		}

		// Need a new page
		let pageSize = Math.Max(mPageSize, size + effectiveAlignment);
		if (CreatePage(pageSize) case .Ok(let newPage))
		{
			pages.Add(newPage);
			if (newPage.TryAllocate(size, effectiveAlignment, let allocation))
				return .Ok(allocation);
		}

		return .Err;
	}

	/// Allocates and writes data to uniform buffer.
	public Result<UniformAllocation> AllocateAndWrite<T>(T data) where T : struct
	{
		let size = (uint64)sizeof(T);
		if (Allocate(size) case .Ok(let allocation))
		{
			// Write data to buffer
			var dataCopy = data;
			Span<uint8> dataSpan = .((uint8*)&dataCopy, (int)size);
			mDevice.Queue.WriteBuffer(allocation.Buffer, allocation.Offset, dataSpan);
			return .Ok(allocation);
		}
		return .Err;
	}

	/// Allocates and writes an array of data to uniform buffer.
	public Result<UniformAllocation> AllocateAndWriteArray<T>(Span<T> data) where T : struct
	{
		let size = (uint64)(sizeof(T) * data.Length);
		if (size == 0)
			return .Err;

		if (Allocate(size) case .Ok(let allocation))
		{
			Span<uint8> dataSpan = .((uint8*)data.Ptr, (int)size);
			mDevice.Queue.WriteBuffer(allocation.Buffer, allocation.Offset, dataSpan);
			return .Ok(allocation);
		}
		return .Err;
	}

	/// Creates a new buffer page.
	private Result<UniformBufferPage> CreatePage(uint64 size)
	{
		BufferDescriptor desc = .()
		{
			Size = size,
			Usage = .Uniform | .CopyDst
		};

		if (mDevice.CreateBuffer(&desc) case .Ok(let buffer))
		{
			return .Ok(new UniformBufferPage(buffer, size));
		}

		return .Err;
	}

	/// Gets statistics about the allocator.
	public (int32 totalPages, uint64 totalMemory, uint64 usedMemory) GetStats()
	{
		int32 totalPages = 0;
		uint64 totalMemory = 0;
		uint64 usedMemory = 0;

		for (int i = 0; i < FrameConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			for (let page in mFramePages[i])
			{
				totalPages++;
				totalMemory += page.Size;
				usedMemory += page.UsedBytes;
			}
		}

		return (totalPages, totalMemory, usedMemory);
	}

	/// Current frame index.
	public int32 CurrentFrame => mCurrentFrame;
}

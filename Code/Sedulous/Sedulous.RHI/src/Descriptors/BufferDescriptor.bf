using System;

namespace Sedulous.RHI;

/// Describes a buffer to be created.
struct BufferDescriptor
{
	/// Size of the buffer in bytes.
	public uint64 Size;
	/// How the buffer will be used.
	public BufferUsage Usage;
	/// Memory access pattern hint.
	public MemoryAccess MemoryAccess;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		Size = 0;
		Usage = .None;
		MemoryAccess = .GpuOnly;
		Label = default;
	}

	public this(uint64 size, BufferUsage usage, MemoryAccess memoryAccess = .GpuOnly)
	{
		Size = size;
		Usage = usage;
		MemoryAccess = memoryAccess;
		Label = default;
	}
}

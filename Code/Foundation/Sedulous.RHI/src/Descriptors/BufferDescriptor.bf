using System;

namespace Sedulous.RHI;

/// Describes a buffer to be created.
struct BufferDesc
{
	/// Size of the buffer in bytes.
	public uint64 Size;
	/// How the buffer will be used.
	public BufferUsage Usage;
	/// Memory access pattern hint.
	public MemoryAccess MemoryAccess;
	/// Byte stride of each element for structured storage buffers.
	/// Set to sizeof(T) when binding as StructuredBuffer<T> / RWStructuredBuffer<T>.
	/// 0 (default) = raw byte-address buffer.
	public uint32 StructureByteStride;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		Size = 0;
		Usage = .None;
		MemoryAccess = .GpuOnly;
		StructureByteStride = 0;
		Label = default;
	}

	public this(uint64 size, BufferUsage usage, MemoryAccess memoryAccess = .GpuOnly)
	{
		Size = size;
		Usage = usage;
		MemoryAccess = memoryAccess;
		StructureByteStride = 0;
		Label = default;
	}
}

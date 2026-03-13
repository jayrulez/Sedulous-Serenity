namespace Sedulous.RHI;

using System;

/// A GPU buffer resource.
interface IBuffer : IDisposable
{
	/// Debug name for tracking resource leaks.
	StringView DebugName { get; }

	/// Size of the buffer in bytes.
	uint64 Size { get; }

	/// Usage flags.
	BufferUsage Usage { get; }

	/// Byte stride of each element for structured storage buffers.
	/// 0 = raw byte-address buffer.
	uint32 StructureByteStride { get; }

	/// Maps the buffer for CPU access.
	/// Returns null if mapping fails or buffer is not mappable.
	void* Map();

	/// Unmaps a previously mapped buffer.
	void Unmap();
}

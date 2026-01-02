namespace Sedulous.RHI;

using System;

/// A GPU buffer resource.
interface IBuffer : IDisposable
{
	/// Size of the buffer in bytes.
	uint64 Size { get; }

	/// Usage flags.
	BufferUsage Usage { get; }

	/// Maps the buffer for CPU access.
	/// Returns null if mapping fails or buffer is not mappable.
	void* Map();

	/// Unmaps a previously mapped buffer.
	void Unmap();
}

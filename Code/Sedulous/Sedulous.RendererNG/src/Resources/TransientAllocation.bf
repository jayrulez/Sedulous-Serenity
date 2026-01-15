namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;

/// Represents an allocation from a transient buffer pool.
/// Valid only for the current frame - do not cache across frames.
struct TransientAllocation
{
	/// The GPU buffer containing the allocation.
	public IBuffer Buffer;

	/// Offset into the buffer where the allocation starts.
	public uint32 Offset;

	/// Size of the allocation in bytes.
	public uint32 Size;

	/// CPU-accessible pointer to the allocation (if buffer is mapped).
	public void* Data;

	/// Returns true if this is a valid allocation.
	public bool IsValid => Buffer != null && Data != null;

	/// Invalid allocation constant.
	public static readonly Self Invalid = .();

	public this()
	{
		Buffer = null;
		Offset = 0;
		Size = 0;
		Data = null;
	}

	public this(IBuffer buffer, uint32 offset, uint32 size, void* data)
	{
		Buffer = buffer;
		Offset = offset;
		Size = size;
		Data = data;
	}

	/// Writes data to the allocation.
	/// Returns true if the write was successful.
	public bool Write<T>(T data) where T : struct
	{
		if (!IsValid)
			return false;

		if ((uint32)sizeof(T) > Size)
			return false;

		*(T*)Data = data;
		return true;
	}

	/// Writes a span of data to the allocation.
	/// Returns true if the write was successful.
	public bool WriteSpan<T>(Span<T> data) where T : struct
	{
		if (!IsValid)
			return false;

		let byteSize = (uint32)(data.Length * sizeof(T));
		if (byteSize > Size)
			return false;

		Internal.MemCpy(Data, data.Ptr, byteSize);
		return true;
	}

	/// Gets a typed pointer to the allocation data.
	public T* GetPtr<T>() where T : struct
	{
		return (T*)Data;
	}
}

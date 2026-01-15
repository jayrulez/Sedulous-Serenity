namespace Sedulous.RendererNG;

using System;

/// Handle to a GPU buffer resource.
/// Type-safe wrapper around ResourceHandle for buffers.
struct BufferHandle : IEquatable<BufferHandle>, IHashable
{
	/// Underlying resource handle.
	private ResourceHandle mHandle;

	/// Invalid handle constant.
	public static readonly Self Invalid = .(ResourceHandle.Invalid);

	/// Gets the underlying resource handle.
	public ResourceHandle Handle => mHandle;

	/// Gets the index into the buffer pool.
	public uint32 Index => mHandle.Index;

	/// Gets the generation counter.
	public uint32 Generation => mHandle.Generation;

	/// Returns true if this handle has a valid index.
	public bool HasValidIndex => mHandle.HasValidIndex;

	/// Creates a buffer handle from a resource handle.
	public this(ResourceHandle handle)
	{
		mHandle = handle;
	}

	/// Creates a buffer handle from index and generation.
	public this(uint32 index, uint32 generation)
	{
		mHandle = .(index, generation);
	}

	public bool Equals(BufferHandle other)
	{
		return mHandle == other.mHandle;
	}

	public int GetHashCode()
	{
		return mHandle.GetHashCode();
	}

	public static bool operator ==(BufferHandle lhs, BufferHandle rhs)
	{
		return lhs.Equals(rhs);
	}

	public static bool operator !=(BufferHandle lhs, BufferHandle rhs)
	{
		return !lhs.Equals(rhs);
	}

	/// Implicit conversion to ResourceHandle.
	public static implicit operator ResourceHandle(BufferHandle handle)
	{
		return handle.mHandle;
	}
}

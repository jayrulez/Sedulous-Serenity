namespace Sedulous.RendererNG;

using System;

/// Type-safe handle to a proxy in a ProxyPool.
/// Uses index + generation for safe access and use-after-free detection.
struct ProxyHandle<T> : IEquatable<Self>, IHashable where T : struct
{
	private uint32 mIndex;
	private uint32 mGeneration;

	/// Invalid handle constant.
	public static readonly Self Invalid = .((uint32)-1, 0);

	/// Gets the slot index.
	public uint32 Index => mIndex;

	/// Gets the generation counter.
	public uint32 Generation => mGeneration;

	/// Returns true if this handle has a valid index (not Invalid).
	/// Note: This doesn't guarantee the handle is still valid in the pool.
	public bool HasValidIndex => mIndex != (uint32)-1;

	public this(uint32 index, uint32 generation)
	{
		mIndex = index;
		mGeneration = generation;
	}

	public bool Equals(Self other)
	{
		return mIndex == other.mIndex && mGeneration == other.mGeneration;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ (mGeneration << 16));
	}

	public static bool operator ==(Self lhs, Self rhs)
	{
		return lhs.Equals(rhs);
	}

	public static bool operator !=(Self lhs, Self rhs)
	{
		return !lhs.Equals(rhs);
	}
}

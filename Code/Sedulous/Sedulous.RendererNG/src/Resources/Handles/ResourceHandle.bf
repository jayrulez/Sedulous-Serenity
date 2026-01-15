namespace Sedulous.RendererNG;

using System;

/// Base handle structure for GPU resources.
/// Uses generation-based validation to detect stale references.
/// When a resource is freed, its slot can be reused with an incremented generation.
/// Any handle with the old generation will fail validation.
struct ResourceHandle : IEquatable<ResourceHandle>, IHashable
{
	/// Index into the resource pool array.
	private uint32 mIndex;

	/// Generation counter for validity checking.
	private uint32 mGeneration;

	/// Invalid handle constant.
	public static readonly Self Invalid = .((uint32)-1, 0);

	/// Gets the index into the resource pool.
	public uint32 Index => mIndex;

	/// Gets the generation counter.
	public uint32 Generation => mGeneration;

	/// Returns true if this handle has a valid index (not Invalid).
	/// Note: This only checks the index, not whether the resource still exists.
	/// Use the pool's IsValid() method for full validation.
	public bool HasValidIndex => mIndex != (uint32)-1;

	/// Creates a new resource handle.
	public this(uint32 index, uint32 generation)
	{
		mIndex = index;
		mGeneration = generation;
	}

	public bool Equals(ResourceHandle other)
	{
		return mIndex == other.mIndex && mGeneration == other.mGeneration;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ (mGeneration << 16));
	}

	public static bool operator ==(ResourceHandle lhs, ResourceHandle rhs)
	{
		return lhs.Equals(rhs);
	}

	public static bool operator !=(ResourceHandle lhs, ResourceHandle rhs)
	{
		return !lhs.Equals(rhs);
	}
}

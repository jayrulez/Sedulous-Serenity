namespace Sedulous.RendererNG;

using System;

/// Lightweight handle to a bind group in the pool.
/// Uses generation to detect stale handles.
struct BindGroupHandle : IHashable, IEquatable<BindGroupHandle>
{
	public uint32 Index;
	public uint32 Generation;

	public static readonly Self Invalid = .(uint32.MaxValue, 0);

	public this(uint32 index, uint32 generation)
	{
		Index = index;
		Generation = generation;
	}

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode()
	{
		return (int)Index ^ ((int)Generation << 16);
	}

	public bool Equals(Self other)
	{
		return Index == other.Index && Generation == other.Generation;
	}

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}

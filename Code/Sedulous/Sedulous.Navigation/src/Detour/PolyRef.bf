using System;

namespace Sedulous.Navigation.Detour;

/// A reference to a polygon in the navigation mesh.
/// Encodes salt (validity check), tile index, and polygon index.
[CRepr]
struct PolyRef : IEquatable<PolyRef>, IHashable
{
	public uint64 Value;

	// Bit layout: [salt:10 | tileIndex:22 | polyIndex:32]
	private const int32 PolyBits = 32;
	private const int32 TileBits = 22;
	private const int32 SaltBits = 10;
	private const uint64 PolyMask = (1UL << PolyBits) - 1;
	private const uint64 TileMask = (1UL << TileBits) - 1;
	private const uint64 SaltMask = (1UL << SaltBits) - 1;

	public static PolyRef Null => PolyRef(0);

	public bool IsValid => Value != 0;

	public this(uint64 value)
	{
		Value = value;
	}

	/// Creates a PolyRef from its component parts.
	public static PolyRef Encode(int32 salt, int32 tileIndex, int32 polyIndex)
	{
		uint64 v = ((uint64)(salt & (int32)SaltMask) << (PolyBits + TileBits)) |
			((uint64)(tileIndex & (int32)TileMask) << PolyBits) |
			((uint64)(polyIndex) & PolyMask);
		return PolyRef(v);
	}

	/// Extracts the salt component.
	public int32 Salt => (int32)((Value >> (PolyBits + TileBits)) & SaltMask);

	/// Extracts the tile index.
	public int32 TileIndex => (int32)((Value >> PolyBits) & TileMask);

	/// Extracts the polygon index within the tile.
	public int32 PolyIndex => (int32)(Value & PolyMask);

	public bool Equals(PolyRef other) => Value == other.Value;
	public int GetHashCode() => (int)Value;

	public static bool operator ==(PolyRef lhs, PolyRef rhs) => lhs.Value == rhs.Value;
	public static bool operator !=(PolyRef lhs, PolyRef rhs) => lhs.Value != rhs.Value;
}

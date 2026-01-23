using System;

namespace Sedulous.Navigation.Recast;

/// Represents a tile coordinate in a tiled navmesh.
[CRepr]
struct TileCoord : IEquatable<TileCoord>, IHashable
{
	public int32 X;
	public int32 Z;

	public this(int32 x, int32 z)
	{
		X = x;
		Z = z;
	}

	public bool Equals(TileCoord other) => X == other.X && Z == other.Z;
	public int GetHashCode() => X * 73856093 ^ Z * 19349663;

	public static bool operator ==(TileCoord lhs, TileCoord rhs) => lhs.X == rhs.X && lhs.Z == rhs.Z;
	public static bool operator !=(TileCoord lhs, TileCoord rhs) => !(lhs == rhs);
}

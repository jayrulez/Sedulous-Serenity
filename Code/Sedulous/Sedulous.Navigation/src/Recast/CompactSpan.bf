using System;

namespace Sedulous.Navigation.Recast;

/// Represents an open (walkable) span in a compact heightfield.
[CRepr]
struct CompactSpan
{
	/// Lower y-coordinate of the open space (in voxel units).
	public uint16 Y;
	/// Height of the open space above Y.
	public uint16 Height;
	/// Packed neighbor connections (4 directions, 6 bits each = 24 bits).
	public uint32 Connections;
	/// Region ID this span belongs to.
	public uint16 RegionId;

	public const uint16 NullRegion = 0;
	public const int32 NotConnected = 0x3F; // 6-bit max = no connection

	/// Gets the neighbor connection index for the given direction (0-3).
	public int32 GetConnection(int32 dir)
	{
		return (int32)((Connections >> (dir * 6)) & 0x3F);
	}

	/// Sets the neighbor connection for the given direction.
	public void SetConnection(int32 dir, int32 value) mut
	{
		uint32 shift = (uint32)(dir * 6);
		Connections = (Connections & ~(0x3Fu << (int)shift)) | ((uint32)(value & 0x3F) << (int)shift);
	}
}

/// A cell entry in the compact heightfield, pointing to its spans.
[CRepr]
struct CompactCell
{
	/// Index of the first span in the spans array.
	public int32 FirstSpan;
	/// Number of spans in this cell.
	public int32 SpanCount;
}

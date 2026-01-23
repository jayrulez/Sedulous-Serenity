using System;

namespace Sedulous.Navigation.Recast;

/// Area flag constants for navigation regions.
static class NavArea
{
	public const uint8 Null = 0;       // Non-walkable
	public const uint8 Walkable = 63;  // Default walkable
	public const uint8 Ground = 1;
	public const uint8 Water = 2;
	public const uint8 Road = 3;
	public const uint8 Door = 4;
	public const uint8 Grass = 5;
	public const uint8 Jump = 6;
}

/// Represents a solid span in a heightfield column.
/// Spans are stored as a linked list per column cell.
class HeightfieldSpan
{
	/// Minimum y-coordinate of the span (in voxel units).
	public int32 MinY;
	/// Maximum y-coordinate of the span (in voxel units).
	public int32 MaxY;
	/// Area classification for this span.
	public uint8 Area;
	/// Next span in the column (linked list, sorted by MinY ascending).
	public HeightfieldSpan Next;

	public this()
	{
		MinY = 0;
		MaxY = 0;
		Area = NavArea.Null;
		Next = null;
	}

	public this(int32 minY, int32 maxY, uint8 area)
	{
		MinY = minY;
		MaxY = maxY;
		Area = area;
		Next = null;
	}
}

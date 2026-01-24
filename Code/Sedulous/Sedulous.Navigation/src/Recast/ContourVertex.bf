using System;

namespace Sedulous.Navigation.Recast;

/// A vertex in a contour, stored as integer grid coordinates.
[CRepr]
struct ContourVertex
{
	public int32 X;
	public int32 Y;
	public int32 Z;
	/// Region connection flag (packed region ID of the neighbor on this edge).
	public int32 RegionFlag;

	public this(int32 x, int32 y, int32 z, int32 regionFlag)
	{
		X = x;
		Y = y;
		Z = z;
		RegionFlag = regionFlag;
	}
}

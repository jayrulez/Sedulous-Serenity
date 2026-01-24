using System;

namespace Sedulous.Navigation.Detour;

/// Default query filter with area costs and include/exclude flags.
class NavMeshQueryFilter : INavMeshQueryFilter
{
	private float[NavMeshConstants.MaxAreas] mAreaCosts;
	private uint16 mIncludeFlags;
	private uint16 mExcludeFlags;

	public uint16 IncludeFlags { get => mIncludeFlags; set => mIncludeFlags = value; }
	public uint16 ExcludeFlags { get => mExcludeFlags; set => mExcludeFlags = value; }

	public this()
	{
		mIncludeFlags = 0xFFFF; // Include all by default
		mExcludeFlags = 0;

		for (int32 i = 0; i < NavMeshConstants.MaxAreas; i++)
			mAreaCosts[i] = 1.0f;
	}

	/// Sets the traversal cost multiplier for an area type.
	public void SetAreaCost(int32 area, float cost)
	{
		if (area >= 0 && area < NavMeshConstants.MaxAreas)
			mAreaCosts[area] = cost;
	}

	/// Gets the traversal cost multiplier for an area type.
	public float GetAreaCost(int32 area)
	{
		if (area >= 0 && area < NavMeshConstants.MaxAreas)
			return mAreaCosts[area];
		return 1.0f;
	}

	public bool PassFilter(PolyRef polyRef, in NavPoly poly)
	{
		return (poly.Flags & mIncludeFlags) != 0 && (poly.Flags & mExcludeFlags) == 0;
	}

	public float GetCost(float[3] a, float[3] b, PolyRef polyRef, in NavPoly poly)
	{
		float dx = b[0] - a[0];
		float dy = b[1] - a[1];
		float dz = b[2] - a[2];
		float dist = Math.Sqrt(dx * dx + dy * dy + dz * dz);
		return dist * mAreaCosts[(int32)poly.Area];
	}
}

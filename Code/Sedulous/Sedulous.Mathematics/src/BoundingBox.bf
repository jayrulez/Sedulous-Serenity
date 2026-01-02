using System;

namespace Sedulous.Mathematics;

/// An axis-aligned bounding box defined by minimum and maximum points.
[CRepr]
public struct BoundingBox : IEquatable<BoundingBox>
{
	/// Minimum corner of the box.
	public Vector3 Min;

	/// Maximum corner of the box.
	public Vector3 Max;

	/// Creates a bounding box from min and max points.
	public this(Vector3 min, Vector3 max)
	{
		Min = min;
		Max = max;
	}

	/// Creates a bounding box centered at origin with given size.
	public static BoundingBox FromSize(Vector3 size)
	{
		let halfSize = size * 0.5f;
		return .(-halfSize, halfSize);
	}

	/// Creates a bounding box from center and half-extents.
	public static BoundingBox FromCenterAndExtents(Vector3 center, Vector3 extents)
	{
		return .(center - extents, center + extents);
	}

	/// Gets the center of the bounding box.
	public Vector3 Center => (Min + Max) * 0.5f;

	/// Gets the size (dimensions) of the bounding box.
	public Vector3 Size => Max - Min;

	/// Gets the half-extents of the bounding box.
	public Vector3 Extents => (Max - Min) * 0.5f;

	/// Expands the bounding box to include a point.
	public void Expand(Vector3 point) mut
	{
		Min = Vector3.Min(Min, point);
		Max = Vector3.Max(Max, point);
	}

	/// Expands the bounding box to include another bounding box.
	public void Expand(BoundingBox other) mut
	{
		Min = Vector3.Min(Min, other.Min);
		Max = Vector3.Max(Max, other.Max);
	}

	/// Checks if the box contains a point.
	public bool Contains(Vector3 point)
	{
		return point.X >= Min.X && point.X <= Max.X &&
			   point.Y >= Min.Y && point.Y <= Max.Y &&
			   point.Z >= Min.Z && point.Z <= Max.Z;
	}

	/// Checks if the box intersects another box.
	public bool Intersects(BoundingBox other)
	{
		return Min.X <= other.Max.X && Max.X >= other.Min.X &&
			   Min.Y <= other.Max.Y && Max.Y >= other.Min.Y &&
			   Min.Z <= other.Max.Z && Max.Z >= other.Min.Z;
	}

	/// Gets the 8 corners of the bounding box.
	public void GetCorners(Vector3* corners)
	{
		corners[0] = .(Min.X, Min.Y, Min.Z);
		corners[1] = .(Max.X, Min.Y, Min.Z);
		corners[2] = .(Min.X, Max.Y, Min.Z);
		corners[3] = .(Max.X, Max.Y, Min.Z);
		corners[4] = .(Min.X, Min.Y, Max.Z);
		corners[5] = .(Max.X, Min.Y, Max.Z);
		corners[6] = .(Min.X, Max.Y, Max.Z);
		corners[7] = .(Max.X, Max.Y, Max.Z);
	}

	/// Transforms the bounding box by a matrix.
	public BoundingBox Transform(Matrix4x4 matrix)
	{
		Vector3[8] corners = ?;
		GetCorners(&corners);

		var transformed = corners[0].Transform(matrix);
		var result = BoundingBox(transformed, transformed);

		for (int i = 1; i < 8; i++)
		{
			result.Expand(corners[i].Transform(matrix));
		}

		return result;
	}

	public bool Equals(BoundingBox other)
	{
		return Min.Equals(other.Min) && Max.Equals(other.Max);
	}

	public static bool operator ==(BoundingBox a, BoundingBox b) => a.Equals(b);
	public static bool operator !=(BoundingBox a, BoundingBox b) => !a.Equals(b);

	public override void ToString(String str)
	{
		str.AppendF("BoundingBox(Min: ({0}, {1}, {2}), Max: ({3}, {4}, {5}))",
			Min.X, Min.Y, Min.Z, Max.X, Max.Y, Max.Z);
	}
}

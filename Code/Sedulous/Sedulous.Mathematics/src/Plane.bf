namespace Sedulous.Mathematics;

using System;

/// Represents a plane in 3D space as normal vector and distance from origin.
struct Plane
{
	/// Normal vector of the plane.
	public Vector3 Normal;

	/// Distance from origin along the normal.
	public float D;

	/// Creates a plane from normal and distance.
	public this(Vector3 normal, float d)
	{
		Normal = normal;
		D = d;
	}

	/// Creates a plane from four coefficients (ax + by + cz + d = 0).
	public this(float a, float b, float c, float d)
	{
		Normal = .(a, b, c);
		D = d;
	}

	/// Creates a plane from a point and normal.
	public static Plane FromPointNormal(Vector3 point, Vector3 normal)
	{
		let n = Vector3.Normalize(normal);
		return .(n, -Vector3.Dot(n, point));
	}

	/// Creates a plane from three points (counter-clockwise winding).
	public static Plane FromPoints(Vector3 a, Vector3 b, Vector3 c)
	{
		let ab = b - a;
		let ac = c - a;
		let normal = Vector3.Normalize(Vector3.Cross(ab, ac));
		return .(normal, -Vector3.Dot(normal, a));
	}

	/// Normalizes the plane equation.
	public Plane Normalize()
	{
		float len = Normal.Length;
		if (len > 0.0001f)
			return .(Normal / len, D / len);
		return this;
	}

	/// Gets the signed distance from a point to the plane.
	/// Positive = in front of plane, negative = behind plane.
	public float DistanceToPoint(Vector3 point)
	{
		return Vector3.Dot(Normal, point) + D;
	}

	/// Projects a point onto the plane.
	public Vector3 ProjectPoint(Vector3 point)
	{
		float dist = DistanceToPoint(point);
		return point - Normal * dist;
	}

	/// Classifies which side of the plane a point is on.
	public PlaneIntersectionType Classify(Vector3 point, float epsilon = 0.0001f)
	{
		float dist = DistanceToPoint(point);
		if (dist > epsilon)
			return .Front;
		if (dist < -epsilon)
			return .Back;
		return .Intersecting;
	}

	/// Intersects the plane with a ray. Returns distance along ray or -1 if no intersection.
	public float IntersectRay(Vector3 rayOrigin, Vector3 rayDirection)
	{
		float denom = Vector3.Dot(Normal, rayDirection);
		if (Math.Abs(denom) < 0.0001f)
			return -1.0f;

		float t = -(Vector3.Dot(Normal, rayOrigin) + D) / denom;
		return t >= 0.0f ? t : -1.0f;
	}

	/// Flips the plane to face the opposite direction.
	public Plane Flip()
	{
		return .(-Normal, -D);
	}
}

/// Result of a plane intersection test.
enum PlaneIntersectionType
{
	/// Object is in front of the plane.
	Front,
	/// Object is behind the plane.
	Back,
	/// Object intersects the plane.
	Intersecting
}

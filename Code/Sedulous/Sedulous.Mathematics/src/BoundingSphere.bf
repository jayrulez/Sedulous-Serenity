namespace Sedulous.Mathematics;

using System;

/// Represents a sphere in 3D space for bounding volume tests.
struct BoundingSphere
{
	/// Center point of the sphere.
	public Vector3 Center;

	/// Radius of the sphere.
	public float Radius;

	/// Creates a bounding sphere.
	public this(Vector3 center, float radius)
	{
		Center = center;
		Radius = radius;
	}

	/// Creates a bounding sphere at origin with given radius.
	public this(float radius)
	{
		Center = .Zero;
		Radius = radius;
	}

	/// Empty bounding sphere at origin with zero radius.
	public static readonly Self Zero = .(.Zero, 0);

	/// Unit sphere centered at origin.
	public static readonly Self Unit = .(.Zero, 1.0f);

	/// Creates a bounding sphere that contains all the given points.
	public static BoundingSphere FromPoints(Span<Vector3> points)
	{
		if (points.Length == 0)
			return .Zero;

		// Find center (average of all points)
		Vector3 center = .Zero;
		for (let p in points)
			center += p;
		center /= (float)points.Length;

		// Find radius (max distance from center)
		float maxDistSq = 0.0f;
		for (let p in points)
		{
			float distSq = Vector3.DistanceSquared(center, p);
			if (distSq > maxDistSq)
				maxDistSq = distSq;
		}

		return .(center, Math.Sqrt(maxDistSq));
	}

	/// Creates a bounding sphere from a bounding box.
	public static BoundingSphere FromBoundingBox(BoundingBox @box)
	{
		let center = @box.Center;
		let radius = Vector3.Distance(center, @box.Max);
		return .(center, radius);
	}

	/// Tests if this sphere contains a point.
	public bool Contains(Vector3 point)
	{
		return Vector3.DistanceSquared(Center, point) <= Radius * Radius;
	}

	/// Tests if this sphere contains another sphere.
	public bool Contains(BoundingSphere other)
	{
		float dist = Vector3.Distance(Center, other.Center);
		return dist + other.Radius <= Radius;
	}

	/// Tests if this sphere intersects another sphere.
	public bool Intersects(BoundingSphere other)
	{
		float distSq = Vector3.DistanceSquared(Center, other.Center);
		float radiusSum = Radius + other.Radius;
		return distSq <= radiusSum * radiusSum;
	}

	/// Tests if this sphere intersects a bounding box.
	public bool Intersects(BoundingBox @box)
	{
		// Find closest point on box to sphere center
		Vector3 closest;
		closest.X = Math.Clamp(Center.X, @box.Min.X, @box.Max.X);
		closest.Y = Math.Clamp(Center.Y, @box.Min.Y, @box.Max.Y);
		closest.Z = Math.Clamp(Center.Z, @box.Min.Z, @box.Max.Z);
		float distSq = Vector3.DistanceSquared(Center, closest);
		return distSq <= Radius * Radius;
	}

	/// Tests if this sphere intersects a plane.
	public PlaneIntersectionType Intersects(Plane plane)
	{
		float dist = plane.DistanceToPoint(Center);
		if (dist > Radius)
			return .Front;
		if (dist < -Radius)
			return .Back;
		return .Intersecting;
	}

	/// Transforms the bounding sphere by a matrix.
	/// Note: Non-uniform scaling will not produce correct results.
	public BoundingSphere Transform(Matrix4x4 matrix)
	{
		// Transform center
		let newCenter = Center.Transform(matrix);

		// Scale radius by max scale factor
		float scaleX = Math.Sqrt(matrix.M11 * matrix.M11 + matrix.M12 * matrix.M12 + matrix.M13 * matrix.M13);
		float scaleY = Math.Sqrt(matrix.M21 * matrix.M21 + matrix.M22 * matrix.M22 + matrix.M23 * matrix.M23);
		float scaleZ = Math.Sqrt(matrix.M31 * matrix.M31 + matrix.M32 * matrix.M32 + matrix.M33 * matrix.M33);
		float maxScale = Math.Max(Math.Max(scaleX, scaleY), scaleZ);

		return .(newCenter, Radius * maxScale);
	}

	/// Merges this sphere with another, creating a sphere that contains both.
	public BoundingSphere Merge(BoundingSphere other)
	{
		let diff = other.Center - Center;
		float dist = diff.Length;

		// One contains the other
		if (dist + other.Radius <= Radius)
			return this;
		if (dist + Radius <= other.Radius)
			return other;

		// Create new sphere
		float newRadius = (dist + Radius + other.Radius) * 0.5f;
		let newCenter = Center + diff * ((newRadius - Radius) / dist);
		return .(newCenter, newRadius);
	}

	/// Expands the sphere to include a point.
	public BoundingSphere ExpandToInclude(Vector3 point)
	{
		let diff = point - Center;
		float dist = diff.Length;

		if (dist <= Radius)
			return this;

		float newRadius = (dist + Radius) * 0.5f;
		let newCenter = Center + diff * ((newRadius - Radius) / dist);
		return .(newCenter, newRadius);
	}
}

namespace Sedulous.RendererNG;

using System;
using Sedulous.Mathematics;

/// Result of frustum culling test.
enum CullResult : uint8
{
	/// Object is completely outside the frustum.
	Outside,
	/// Object is partially inside the frustum.
	Intersects,
	/// Object is completely inside the frustum.
	Inside
}

/// Performs frustum culling tests against bounding volumes.
/// Uses the 6 planes from a RenderView's frustum.
struct FrustumCuller
{
	/// The 6 frustum planes (left, right, bottom, top, near, far).
	public Plane[6] Planes;

	/// Creates a culler from a RenderView's frustum planes.
	public this(RenderView view)
	{
		Planes = view.FrustumPlanes;
	}

	/// Creates a culler from explicit frustum planes.
	public this(Plane[6] planes)
	{
		Planes = planes;
	}

	/// Creates a culler from a view-projection matrix.
	/// Extracts frustum planes using the Gribb/Hartmann method for row-major matrices.
	public this(Matrix viewProjection)
	{
		Planes = ExtractPlanes(viewProjection);
	}

	/// Tests an axis-aligned bounding box against the frustum.
	/// Returns Outside if the box is completely outside any plane.
	/// Returns Inside if the box is completely inside all planes.
	/// Returns Intersects if the box crosses one or more planes.
	public CullResult TestAABB(BoundingBox bounds)
	{
		var result = CullResult.Inside;

		for (int i = 0; i < 6; i++)
		{
			let plane = Planes[i];

			// Find the positive vertex (furthest along the plane normal)
			Vector3 positiveVertex;
			positiveVertex.X = (plane.Normal.X >= 0) ? bounds.Max.X : bounds.Min.X;
			positiveVertex.Y = (plane.Normal.Y >= 0) ? bounds.Max.Y : bounds.Min.Y;
			positiveVertex.Z = (plane.Normal.Z >= 0) ? bounds.Max.Z : bounds.Min.Z;

			// Find the negative vertex (furthest against the plane normal)
			Vector3 negativeVertex;
			negativeVertex.X = (plane.Normal.X >= 0) ? bounds.Min.X : bounds.Max.X;
			negativeVertex.Y = (plane.Normal.Y >= 0) ? bounds.Min.Y : bounds.Max.Y;
			negativeVertex.Z = (plane.Normal.Z >= 0) ? bounds.Min.Z : bounds.Max.Z;

			// Test positive vertex - if it's behind the plane, bounds is outside
			float positiveDistance = Vector3.Dot(plane.Normal, positiveVertex) + plane.D;
			if (positiveDistance < 0)
				return .Outside;

			// Test negative vertex - if it's behind the plane, bounds intersects
			float negativeDistance = Vector3.Dot(plane.Normal, negativeVertex) + plane.D;
			if (negativeDistance < 0)
				result = .Intersects;
		}

		return result;
	}

	/// Tests an axis-aligned bounding box against the frustum (fast path).
	/// Returns true if the box is at least partially visible.
	public bool IsVisibleAABB(BoundingBox bounds)
	{
		for (int i = 0; i < 6; i++)
		{
			let plane = Planes[i];

			// Find the positive vertex (furthest along the plane normal)
			Vector3 positiveVertex;
			positiveVertex.X = (plane.Normal.X >= 0) ? bounds.Max.X : bounds.Min.X;
			positiveVertex.Y = (plane.Normal.Y >= 0) ? bounds.Max.Y : bounds.Min.Y;
			positiveVertex.Z = (plane.Normal.Z >= 0) ? bounds.Max.Z : bounds.Min.Z;

			// If positive vertex is behind the plane, bounds is outside
			float distance = Vector3.Dot(plane.Normal, positiveVertex) + plane.D;
			if (distance < 0)
				return false;
		}

		return true;
	}

	/// Tests a bounding sphere against the frustum.
	public CullResult TestSphere(BoundingSphere sphere)
	{
		var result = CullResult.Inside;

		for (int i = 0; i < 6; i++)
		{
			let plane = Planes[i];
			float distance = Vector3.Dot(plane.Normal, sphere.Center) + plane.D;

			if (distance < -sphere.Radius)
				return .Outside;

			if (distance < sphere.Radius)
				result = .Intersects;
		}

		return result;
	}

	/// Tests a bounding sphere against the frustum (fast path).
	/// Returns true if the sphere is at least partially visible.
	public bool IsVisibleSphere(BoundingSphere sphere)
	{
		for (int i = 0; i < 6; i++)
		{
			let plane = Planes[i];
			float distance = Vector3.Dot(plane.Normal, sphere.Center) + plane.D;

			if (distance < -sphere.Radius)
				return false;
		}

		return true;
	}

	/// Tests a bounding sphere against the frustum (fast path).
	/// Returns true if the sphere is at least partially visible.
	public bool IsVisibleSphere(Vector3 center, float radius)
	{
		for (int i = 0; i < 6; i++)
		{
			let plane = Planes[i];
			float distance = Vector3.Dot(plane.Normal, center) + plane.D;

			if (distance < -radius)
				return false;
		}

		return true;
	}

	/// Tests a point against the frustum.
	public bool IsVisiblePoint(Vector3 point)
	{
		for (int i = 0; i < 6; i++)
		{
			let plane = Planes[i];
			float distance = Vector3.Dot(plane.Normal, point) + plane.D;

			if (distance < 0)
				return false;
		}

		return true;
	}

	/// Extracts frustum planes from a view-projection matrix.
	/// Uses Gribb/Hartmann method for row-major matrices with row vector convention (v * M).
	/// The matrix uses XNA/MonoGame convention where basis vectors are in columns.
	public static Plane[6] ExtractPlanes(Matrix m)
	{
		Plane[6] planes = ?;

		// For row vector * matrix convention (v * M), extract from columns
		// Left plane: col4 + col1
		planes[0] = Plane.Normalize(Plane(
			m.M14 + m.M11,
			m.M24 + m.M21,
			m.M34 + m.M31,
			m.M44 + m.M41
		));

		// Right plane: col4 - col1
		planes[1] = Plane.Normalize(Plane(
			m.M14 - m.M11,
			m.M24 - m.M21,
			m.M34 - m.M31,
			m.M44 - m.M41
		));

		// Bottom plane: col4 + col2
		planes[2] = Plane.Normalize(Plane(
			m.M14 + m.M12,
			m.M24 + m.M22,
			m.M34 + m.M32,
			m.M44 + m.M42
		));

		// Top plane: col4 - col2
		planes[3] = Plane.Normalize(Plane(
			m.M14 - m.M12,
			m.M24 - m.M22,
			m.M34 - m.M32,
			m.M44 - m.M42
		));

		// Near plane: col3 (for 0-1 depth range)
		planes[4] = Plane.Normalize(Plane(
			m.M13,
			m.M23,
			m.M33,
			m.M43
		));

		// Far plane: col4 - col3
		planes[5] = Plane.Normalize(Plane(
			m.M14 - m.M13,
			m.M24 - m.M23,
			m.M34 - m.M33,
			m.M44 - m.M43
		));

		return planes;
	}
}

namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;

/// Stateless frustum culling utilities.
static class FrustumCuller
{
	/// Tests an AABB against a frustum. Returns true if at least partially inside.
	public static bool TestAABB(BoundingFrustum frustum, BoundingBox bounds)
	{
		return frustum.Contains(bounds) != .Disjoint;
	}

	/// Tests a sphere against a frustum. Returns true if at least partially inside.
	public static bool TestSphere(BoundingFrustum frustum, BoundingSphere sphere)
	{
		return frustum.Contains(sphere) != .Disjoint;
	}

	/// Transforms a local-space AABB by a world matrix to produce a world-space AABB.
	/// Uses the optimized min/max approach (avoids transforming 8 corners).
	public static BoundingBox TransformAABB(BoundingBox local, Matrix transform)
	{
		// Extract translation
		var newCenter = Vector3(transform.M41, transform.M42, transform.M43);
		var newExtent = Vector3.Zero;

		let center = (local.Min + local.Max) * 0.5f;
		let extent = (local.Max - local.Min) * 0.5f;

		// Transform center
		newCenter += Vector3(
			center.X * transform.M11 + center.Y * transform.M21 + center.Z * transform.M31,
			center.X * transform.M12 + center.Y * transform.M22 + center.Z * transform.M32,
			center.X * transform.M13 + center.Y * transform.M23 + center.Z * transform.M33
		);

		// Transform extent using absolute values of matrix columns
		newExtent = Vector3(
			extent.X * Math.Abs(transform.M11) + extent.Y * Math.Abs(transform.M21) + extent.Z * Math.Abs(transform.M31),
			extent.X * Math.Abs(transform.M12) + extent.Y * Math.Abs(transform.M22) + extent.Z * Math.Abs(transform.M32),
			extent.X * Math.Abs(transform.M13) + extent.Y * Math.Abs(transform.M23) + extent.Z * Math.Abs(transform.M33)
		);

		return BoundingBox(newCenter - newExtent, newCenter + newExtent);
	}
}

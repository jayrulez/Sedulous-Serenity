namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Result of a frustum culling test.
public enum CullResult : uint8
{
	/// Object is completely outside the frustum.
	Outside,

	/// Object intersects the frustum boundary.
	Intersects,

	/// Object is completely inside the frustum.
	Inside
}

/// CPU-based frustum culler for visibility determination.
/// Tests AABBs and spheres against camera frustum planes.
public class FrustumCuller
{
	/// Frustum planes extracted from view-projection matrix.
	/// Order: Left, Right, Bottom, Top, Near, Far
	private Plane[6] mPlanes;

	/// Whether the frustum has been initialized.
	private bool mInitialized = false;

	/// Statistics for the current frame.
	private CullStats mStats;

	/// Gets culling statistics for the current frame.
	public CullStats Stats => mStats;

	/// Updates the frustum planes from a view-projection matrix.
	public void SetFrustum(Matrix viewProjection)
	{
		ExtractPlanes(viewProjection);
		mInitialized = true;
	}

	/// Updates the frustum planes from a camera proxy.
	public void SetFrustum(CameraProxy* camera)
	{
		if (camera != null)
		{
			mPlanes = camera.FrustumPlanes;
			mInitialized = true;
		}
	}

	/// Resets statistics for a new frame.
	public void ResetStats()
	{
		mStats = .();
	}

	/// Tests if an AABB is visible to the frustum.
	/// Returns true if the AABB is at least partially visible.
	public bool IsVisible(BoundingBox bounds)
	{
		if (!mInitialized)
			return true;

		mStats.TotalTests++;

		for (int i = 0; i < 6; i++)
		{
			let plane = mPlanes[i];

			// Get the positive vertex (furthest along plane normal)
			Vector3 positiveVertex = .(
				plane.Normal.X >= 0 ? bounds.Max.X : bounds.Min.X,
				plane.Normal.Y >= 0 ? bounds.Max.Y : bounds.Min.Y,
				plane.Normal.Z >= 0 ? bounds.Max.Z : bounds.Min.Z
			);

			// If positive vertex is behind plane, AABB is outside frustum
			if (Vector3.Dot(plane.Normal, positiveVertex) + plane.D < 0)
			{
				mStats.CulledCount++;
				return false;
			}
		}

		mStats.VisibleCount++;
		return true;
	}

	/// Tests if a sphere is visible to the frustum.
	/// Returns true if the sphere is at least partially visible.
	public bool IsVisible(BoundingSphere sphere)
	{
		if (!mInitialized)
			return true;

		mStats.TotalTests++;

		for (int i = 0; i < 6; i++)
		{
			let plane = mPlanes[i];
			let distance = Vector3.Dot(plane.Normal, sphere.Center) + plane.D;

			if (distance < -sphere.Radius)
			{
				mStats.CulledCount++;
				return false;
			}
		}

		mStats.VisibleCount++;
		return true;
	}

	/// Tests if a point is visible to the frustum.
	public bool IsVisible(Vector3 point)
	{
		if (!mInitialized)
			return true;

		mStats.TotalTests++;

		for (int i = 0; i < 6; i++)
		{
			let plane = mPlanes[i];
			let distance = Vector3.Dot(plane.Normal, point) + plane.D;

			if (distance < 0)
			{
				mStats.CulledCount++;
				return false;
			}
		}

		mStats.VisibleCount++;
		return true;
	}

	/// Tests an AABB and returns detailed cull result.
	public CullResult TestAABB(BoundingBox bounds)
	{
		if (!mInitialized)
			return .Inside;

		mStats.TotalTests++;
		bool intersects = false;

		for (int i = 0; i < 6; i++)
		{
			let plane = mPlanes[i];

			// Get positive and negative vertices
			Vector3 positiveVertex = .(
				plane.Normal.X >= 0 ? bounds.Max.X : bounds.Min.X,
				plane.Normal.Y >= 0 ? bounds.Max.Y : bounds.Min.Y,
				plane.Normal.Z >= 0 ? bounds.Max.Z : bounds.Min.Z
			);

			Vector3 negativeVertex = .(
				plane.Normal.X >= 0 ? bounds.Min.X : bounds.Max.X,
				plane.Normal.Y >= 0 ? bounds.Min.Y : bounds.Max.Y,
				plane.Normal.Z >= 0 ? bounds.Min.Z : bounds.Max.Z
			);

			let posDistance = Vector3.Dot(plane.Normal, positiveVertex) + plane.D;
			let negDistance = Vector3.Dot(plane.Normal, negativeVertex) + plane.D;

			// If positive vertex is behind plane, completely outside
			if (posDistance < 0)
			{
				mStats.CulledCount++;
				return .Outside;
			}

			// If negative vertex is behind plane, intersecting
			if (negDistance < 0)
				intersects = true;
		}

		mStats.VisibleCount++;
		return intersects ? .Intersects : .Inside;
	}

	/// Tests a sphere and returns detailed cull result.
	public CullResult TestSphere(BoundingSphere sphere)
	{
		if (!mInitialized)
			return .Inside;

		mStats.TotalTests++;
		bool intersects = false;

		for (int i = 0; i < 6; i++)
		{
			let plane = mPlanes[i];
			let distance = Vector3.Dot(plane.Normal, sphere.Center) + plane.D;

			if (distance < -sphere.Radius)
			{
				mStats.CulledCount++;
				return .Outside;
			}

			if (distance < sphere.Radius)
				intersects = true;
		}

		mStats.VisibleCount++;
		return intersects ? .Intersects : .Inside;
	}

	/// Culls mesh proxies, returning handles of visible meshes.
	public void CullMeshes(RenderWorld world, List<MeshProxyHandle> outVisibleHandles)
	{
		outVisibleHandles.Clear();

		world.ForEachMesh(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive)
				return;

			if ((proxy.Flags & .Visible) == 0)
				return;

			if (IsVisible(proxy.WorldBounds))
				outVisibleHandles.Add(.() { Handle = handle });
		});
	}

	/// Culls skinned mesh proxies, returning handles of visible meshes.
	public void CullSkinnedMeshes(RenderWorld world, List<SkinnedMeshProxyHandle> outVisibleHandles)
	{
		outVisibleHandles.Clear();

		world.ForEachSkinnedMesh(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive)
				return;

			if ((proxy.Flags & .Visible) == 0)
				return;

			// Use animation bounds for skinned meshes (larger than local bounds)
			if (IsVisible(proxy.WorldBounds))
				outVisibleHandles.Add(.() { Handle = handle });
		});
	}

	/// Culls lights, returning handles of lights that affect the visible area.
	public void CullLights(RenderWorld world, List<LightProxyHandle> outVisibleHandles)
	{
		outVisibleHandles.Clear();

		world.ForEachLight(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive || !proxy.IsEnabled)
				return;

			// Directional lights always affect the scene
			if (proxy.Type == .Directional)
			{
				outVisibleHandles.Add(.() { Handle = handle });
				return;
			}

			// For point/spot lights, test their bounding sphere
			let sphere = BoundingSphere(proxy.Position, proxy.Range);
			if (IsVisible(sphere))
				outVisibleHandles.Add(.() { Handle = handle });
		});
	}

	/// Extracts frustum planes from view-projection matrix.
	/// Uses Gribb/Hartmann method for row-major matrices with row vectors.
	/// Row vectors: clip = worldPos * VP, so use columns for extraction.
	/// Matrix naming: MRC where R=row, C=column (1-indexed)
	private void ExtractPlanes(Matrix m)
	{
		// For row-major with row vectors (clip = world * VP):
		// Extract from columns of the matrix
		// Left plane: col4 + col1
		mPlanes[0] = NormalizePlane(Plane(
			m.M14 + m.M11,
			m.M24 + m.M21,
			m.M34 + m.M31,
			m.M44 + m.M41
		));

		// Right plane: col4 - col1
		mPlanes[1] = NormalizePlane(Plane(
			m.M14 - m.M11,
			m.M24 - m.M21,
			m.M34 - m.M31,
			m.M44 - m.M41
		));

		// Bottom plane: col4 + col2
		mPlanes[2] = NormalizePlane(Plane(
			m.M14 + m.M12,
			m.M24 + m.M22,
			m.M34 + m.M32,
			m.M44 + m.M42
		));

		// Top plane: col4 - col2
		mPlanes[3] = NormalizePlane(Plane(
			m.M14 - m.M12,
			m.M24 - m.M22,
			m.M34 - m.M32,
			m.M44 - m.M42
		));

		// Near plane: col3 (D3D convention, near=0 in NDC)
		mPlanes[4] = NormalizePlane(Plane(
			m.M13,
			m.M23,
			m.M33,
			m.M43
		));

		// Far plane: col4 - col3
		mPlanes[5] = NormalizePlane(Plane(
			m.M14 - m.M13,
			m.M24 - m.M23,
			m.M34 - m.M33,
			m.M44 - m.M43
		));
	}

	/// Normalizes a plane so the normal has unit length.
	private static Plane NormalizePlane(Plane plane)
	{
		let length = plane.Normal.Length();
		if (length > 0.0001f)
		{
			let invLength = 1.0f / length;
			return Plane(
				plane.Normal.X * invLength,
				plane.Normal.Y * invLength,
				plane.Normal.Z * invLength,
				plane.D * invLength
			);
		}
		return plane;
	}
}

/// Statistics from frustum culling operations.
public struct CullStats
{
	/// Total number of visibility tests performed.
	public int32 TotalTests;

	/// Number of objects that passed visibility test.
	public int32 VisibleCount;

	/// Number of objects culled (not visible).
	public int32 CulledCount;

	/// Percentage of objects culled.
	public float CullPercentage => TotalTests > 0 ? (float)CulledCount / (float)TotalTests * 100.0f : 0.0f;
}

namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Performs frustum culling to determine visible objects.
class FrustumCuller
{
	/// Small tolerance to avoid precision issues at frustum edges.
	private const float FRUSTUM_TOLERANCE = 0.5f;

	/// Cached frustum planes from camera.
	private Plane[6] mFrustumPlanes;

	/// Updates the frustum planes from a camera proxy.
	public void SetCamera(CameraProxy* camera)
	{
		if (camera != null)
			mFrustumPlanes = camera.FrustumPlanes;
	}

	/// Tests if an AABB is visible in the frustum.
	/// Uses a small tolerance to avoid precision issues at frustum edges.
	public bool IsVisible(BoundingBox bounds)
	{
		let center = (bounds.Min + bounds.Max) * 0.5f;
		let extents = (bounds.Max - bounds.Min) * 0.5f;

		for (int i = 0; i < 6; i++)
		{
			let plane = mFrustumPlanes[i];

			// Signed distance from center to plane
			float d = plane.Normal.X * center.X +
					  plane.Normal.Y * center.Y +
					  plane.Normal.Z * center.Z + plane.D;

			// Projection of extents onto plane normal
			float r = extents.X * Math.Abs(plane.Normal.X) +
					  extents.Y * Math.Abs(plane.Normal.Y) +
					  extents.Z * Math.Abs(plane.Normal.Z);

			// If box is entirely behind plane (with tolerance), it's culled
			if (d + r < -FRUSTUM_TOLERANCE)
				return false;
		}

		return true;
	}

	/// Tests if a bounding sphere is visible in the frustum.
	public bool IsVisible(BoundingSphere sphere)
	{
		for (int i = 0; i < 6; i++)
		{
			let plane = mFrustumPlanes[i];
			float d = plane.Normal.X * sphere.Center.X +
					  plane.Normal.Y * sphere.Center.Y +
					  plane.Normal.Z * sphere.Center.Z + plane.D;

			if (d < -sphere.Radius - FRUSTUM_TOLERANCE)
				return false;
		}

		return true;
	}

	/// Tests visibility and returns intersection type.
	public FrustumIntersection TestIntersection(BoundingBox bounds)
	{
		let center = (bounds.Min + bounds.Max) * 0.5f;
		let extents = (bounds.Max - bounds.Min) * 0.5f;
		bool intersecting = false;

		for (int i = 0; i < 6; i++)
		{
			let plane = mFrustumPlanes[i];

			float d = plane.Normal.X * center.X +
					  plane.Normal.Y * center.Y +
					  plane.Normal.Z * center.Z + plane.D;

			float r = extents.X * Math.Abs(plane.Normal.X) +
					  extents.Y * Math.Abs(plane.Normal.Y) +
					  extents.Z * Math.Abs(plane.Normal.Z);

			if (d + r < 0)
				return .Outside;

			if (d - r < 0)
				intersecting = true;
		}

		return intersecting ? .Intersecting : .Inside;
	}

	/// Debug: which plane culled the last object (0-5: left,right,bottom,top,near,far, -1: none)
	public int32 LastCullingPlane = -1;

	/// Culls mesh proxies and returns visible ones.
	public void CullMeshes(List<MeshProxy*> proxies, List<MeshProxy*> outVisible, Vector3 cameraPos)
	{
		outVisible.Clear();
		LastCullingPlane = -1;

		for (let proxy in proxies)
		{
			if (!proxy.IsVisible)
				continue;

			let (visible, cullingPlane) = IsVisibleDebug(proxy.WorldBounds);
			if (visible)
			{
				// Calculate distance to camera for sorting/LOD
				let center = (proxy.WorldBounds.Min + proxy.WorldBounds.Max) * 0.5f;
				proxy.DistanceToCamera = Vector3.Distance(center, cameraPos);
				outVisible.Add(proxy);
			}
			else
			{
				proxy.Flags |= .Culled;
				LastCullingPlane = cullingPlane;
			}
		}
	}

	/// Debug version that returns which plane caused culling
	private (bool visible, int32 cullingPlane) IsVisibleDebug(BoundingBox bounds)
	{
		let center = (bounds.Min + bounds.Max) * 0.5f;
		let extents = (bounds.Max - bounds.Min) * 0.5f;

		for (int i = 0; i < 6; i++)
		{
			let plane = mFrustumPlanes[i];
			float d = plane.Normal.X * center.X +
					  plane.Normal.Y * center.Y +
					  plane.Normal.Z * center.Z + plane.D;
			float r = extents.X * Math.Abs(plane.Normal.X) +
					  extents.Y * Math.Abs(plane.Normal.Y) +
					  extents.Z * Math.Abs(plane.Normal.Z);

			if (d + r < -FRUSTUM_TOLERANCE)
				return (false, (int32)i);
		}

		return (true, -1);
	}

	/// Culls light proxies.
	public void CullLights(List<LightProxy*> lights, List<LightProxy*> outVisible)
	{
		outVisible.Clear();

		for (let light in lights)
		{
			if (!light.Enabled)
				continue;

			// Directional lights always visible
			if (light.Type == .Directional)
			{
				outVisible.Add(light);
				continue;
			}

			// Test light bounding sphere
			let sphere = BoundingSphere(light.Position, light.Range);
			if (IsVisible(sphere))
				outVisible.Add(light);
		}
	}
}

/// Result of a frustum intersection test.
enum FrustumIntersection
{
	/// Entirely outside the frustum.
	Outside,
	/// Partially inside the frustum.
	Intersecting,
	/// Entirely inside the frustum.
	Inside
}

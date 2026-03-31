namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;

/// Result of a frustum culling test.
public enum CullResult : uint8
{
	Outside,
	Intersects,
	Inside
}

/// CPU-based frustum culler for visibility determination.
public class FrustumCuller
{
	private Plane[6] mPlanes;
	private bool mInitialized = false;
	private CullStats mStats;

	public CullStats Stats => mStats;

	public void SetFrustum(Matrix viewProjection)
	{
		ExtractPlanes(viewProjection);
		mInitialized = true;
	}

	public void SetFrustum(CameraProxy* camera)
	{
		if (camera != null)
		{
			mPlanes = camera.FrustumPlanes;
			mInitialized = true;
		}
	}

	public void ResetStats()
	{
		mStats = .();
	}

	public bool IsVisible(BoundingBox bounds)
	{
		if (!mInitialized)
			return true;

		mStats.TotalTests++;

		for (int i = 0; i < 6; i++)
		{
			let plane = mPlanes[i];
			Vector3 positiveVertex = .(
				plane.Normal.X >= 0 ? bounds.Max.X : bounds.Min.X,
				plane.Normal.Y >= 0 ? bounds.Max.Y : bounds.Min.Y,
				plane.Normal.Z >= 0 ? bounds.Max.Z : bounds.Min.Z
			);

			if (Vector3.Dot(plane.Normal, positiveVertex) + plane.D < 0)
			{
				mStats.CulledCount++;
				return false;
			}
		}

		mStats.VisibleCount++;
		return true;
	}

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

	public bool IsVisible(Vector3 point)
	{
		if (!mInitialized)
			return true;

		mStats.TotalTests++;

		for (int i = 0; i < 6; i++)
		{
			let plane = mPlanes[i];
			if (Vector3.Dot(plane.Normal, point) + plane.D < 0)
			{
				mStats.CulledCount++;
				return false;
			}
		}

		mStats.VisibleCount++;
		return true;
	}

	public CullResult TestAABB(BoundingBox bounds)
	{
		if (!mInitialized)
			return .Inside;

		mStats.TotalTests++;
		bool intersects = false;

		for (int i = 0; i < 6; i++)
		{
			let plane = mPlanes[i];

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

			if (Vector3.Dot(plane.Normal, positiveVertex) + plane.D < 0)
			{
				mStats.CulledCount++;
				return .Outside;
			}
			if (Vector3.Dot(plane.Normal, negativeVertex) + plane.D < 0)
				intersects = true;
		}

		mStats.VisibleCount++;
		return intersects ? .Intersects : .Inside;
	}

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

	public void CullStaticMeshes(RenderWorld world, List<StaticMeshProxyHandle> outVisibleHandles)
	{
		outVisibleHandles.Clear();
		world.ForEachStaticMesh(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive) return;
			if ((proxy.Flags & .Visible) == 0) return;
			if (IsVisible(proxy.WorldBounds))
				outVisibleHandles.Add(.() { Handle = handle });
		});
	}

	public void CullSkinnedMeshes(RenderWorld world, List<SkinnedMeshProxyHandle> outVisibleHandles)
	{
		outVisibleHandles.Clear();
		world.ForEachSkinnedMesh(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive) return;
			if ((proxy.Flags & .Visible) == 0) return;
			if (IsVisible(proxy.WorldBounds))
				outVisibleHandles.Add(.() { Handle = handle });
		});
	}

	public void CullLights(RenderWorld world, List<LightProxyHandle> outVisibleHandles)
	{
		outVisibleHandles.Clear();
		world.ForEachLight(scope [&](handle, proxy) =>
		{
			if (!proxy.IsActive || !proxy.IsEnabled) return;
			if (proxy.Type == .Directional)
			{
				outVisibleHandles.Add(.() { Handle = handle });
				return;
			}
			let sphere = BoundingSphere(proxy.Position, proxy.Range);
			if (IsVisible(sphere))
				outVisibleHandles.Add(.() { Handle = handle });
		});
	}

	private void ExtractPlanes(Matrix m)
	{
		mPlanes[0] = NormalizePlane(Plane(m.M14 + m.M11, m.M24 + m.M21, m.M34 + m.M31, m.M44 + m.M41));
		mPlanes[1] = NormalizePlane(Plane(m.M14 - m.M11, m.M24 - m.M21, m.M34 - m.M31, m.M44 - m.M41));
		mPlanes[2] = NormalizePlane(Plane(m.M14 + m.M12, m.M24 + m.M22, m.M34 + m.M32, m.M44 + m.M42));
		mPlanes[3] = NormalizePlane(Plane(m.M14 - m.M12, m.M24 - m.M22, m.M34 - m.M32, m.M44 - m.M42));
		mPlanes[4] = NormalizePlane(Plane(m.M13, m.M23, m.M33, m.M43));
		mPlanes[5] = NormalizePlane(Plane(m.M14 - m.M13, m.M24 - m.M23, m.M34 - m.M33, m.M44 - m.M43));
	}

	private static Plane NormalizePlane(Plane plane)
	{
		let length = plane.Normal.Length();
		if (length > 0.0001f)
		{
			let invLength = 1.0f / length;
			return Plane(plane.Normal.X * invLength, plane.Normal.Y * invLength, plane.Normal.Z * invLength, plane.D * invLength);
		}
		return plane;
	}
}

/// Statistics from frustum culling operations.
public struct CullStats
{
	public int32 TotalTests;
	public int32 VisibleCount;
	public int32 CulledCount;
	public float CullPercentage => TotalTests > 0 ? (float)CulledCount / (float)TotalTests * 100.0f : 0.0f;
}

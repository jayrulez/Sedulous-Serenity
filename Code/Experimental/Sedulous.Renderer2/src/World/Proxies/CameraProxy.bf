namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;

/// Camera projection type.
public enum ProjectionType : uint8
{
	Perspective,
	Orthographic
}

/// Proxy for a camera in the render world.
public struct CameraProxy
{
	public Vector3 Position;
	public Vector3 Forward;
	public Vector3 Up;
	public Vector3 Right;
	public Matrix ViewMatrix;
	public Matrix ProjectionMatrix;
	public Matrix ViewProjectionMatrix;
	public Matrix PrevViewProjectionMatrix;
	public Matrix InverseViewMatrix;
	public Matrix InverseProjectionMatrix;
	public Plane[6] FrustumPlanes;
	public ProjectionType Projection;
	public float FieldOfView;
	public float AspectRatio;
	public float NearPlane;
	public float FarPlane;
	public float OrthoWidth;
	public float OrthoHeight;
	public Vector2 JitterOffset;
	public uint8 JitterIndex;
	public int32 Priority;
	public uint32 Generation;
	public bool IsActive;
	public bool IsMainCamera;

	public static Self CreatePerspective(Vector3 position, Vector3 target, Vector3 up, float fov, float aspectRatio, float nearPlane, float farPlane)
	{
		Self proxy = .();
		proxy.Position = position;
		proxy.Forward = Vector3.Normalize(target - position);
		proxy.Up = Vector3.Normalize(up);
		proxy.Right = Vector3.Normalize(Vector3.Cross(proxy.Forward, proxy.Up));
		proxy.Projection = .Perspective;
		proxy.FieldOfView = fov;
		proxy.AspectRatio = aspectRatio;
		proxy.NearPlane = nearPlane;
		proxy.FarPlane = farPlane;
		proxy.JitterOffset = .Zero;
		proxy.JitterIndex = 0;
		proxy.Priority = 0;
		proxy.IsActive = true;
		proxy.IsMainCamera = false;
		proxy.UpdateMatrices();
		return proxy;
	}

	public static Self CreateOrthographic(Vector3 position, Vector3 target, Vector3 up, float width, float height, float nearPlane, float farPlane)
	{
		Self proxy = .();
		proxy.Position = position;
		proxy.Forward = Vector3.Normalize(target - position);
		proxy.Up = Vector3.Normalize(up);
		proxy.Right = Vector3.Normalize(Vector3.Cross(proxy.Forward, proxy.Up));
		proxy.Projection = .Orthographic;
		proxy.OrthoWidth = width;
		proxy.OrthoHeight = height;
		proxy.AspectRatio = width / height;
		proxy.NearPlane = nearPlane;
		proxy.FarPlane = farPlane;
		proxy.JitterOffset = .Zero;
		proxy.JitterIndex = 0;
		proxy.Priority = 0;
		proxy.IsActive = true;
		proxy.IsMainCamera = false;
		proxy.UpdateMatrices();
		return proxy;
	}

	public void UpdateMatrices() mut
	{
		PrevViewProjectionMatrix = ViewProjectionMatrix;
		let target = Position + Forward;
		ViewMatrix = Matrix.CreateLookAt(Position, target, Up);

		if (Projection == .Perspective)
			ProjectionMatrix = Matrix.CreatePerspectiveFieldOfView(FieldOfView, AspectRatio, NearPlane, FarPlane);
		else
			ProjectionMatrix = Matrix.CreateOrthographic(OrthoWidth, OrthoHeight, NearPlane, FarPlane);

		if (JitterOffset.X != 0 || JitterOffset.Y != 0)
		{
			var jitteredProj = ProjectionMatrix;
			jitteredProj.M31 += JitterOffset.X;
			jitteredProj.M32 += JitterOffset.Y;
			ProjectionMatrix = jitteredProj;
		}

		ViewProjectionMatrix = ViewMatrix * ProjectionMatrix;
		Matrix.TryInvert(ViewMatrix, out InverseViewMatrix);
		Matrix.TryInvert(ProjectionMatrix, out InverseProjectionMatrix);
		ExtractFrustumPlanes();
	}

	public void SetLookAt(Vector3 position, Vector3 target, Vector3 up) mut
	{
		Position = position;
		Forward = Vector3.Normalize(target - position);
		Up = Vector3.Normalize(up);
		Right = Vector3.Normalize(Vector3.Cross(Forward, Up));
	}

	public void SetPositionDirection(Vector3 position, Vector3 forward, Vector3 up) mut
	{
		Position = position;
		Forward = Vector3.Normalize(forward);
		Up = Vector3.Normalize(up);
		Right = Vector3.Normalize(Vector3.Cross(Forward, Up));
	}

	public void SetJitter(Vector2 pixelOffset, uint32 viewportWidth, uint32 viewportHeight) mut
	{
		JitterOffset = Vector2(
			pixelOffset.X * 2.0f / (float)viewportWidth,
			pixelOffset.Y * 2.0f / (float)viewportHeight
		);
	}

	public void AdvanceJitter(uint8 sampleCount) mut
	{
		JitterIndex = (JitterIndex + 1) % sampleCount;
	}

	public bool IsVisible(BoundingBox bounds)
	{
		for (int i = 0; i < 6; i++)
		{
			let plane = FrustumPlanes[i];
			Vector3 positiveVertex = .(
				plane.Normal.X >= 0 ? bounds.Max.X : bounds.Min.X,
				plane.Normal.Y >= 0 ? bounds.Max.Y : bounds.Min.Y,
				plane.Normal.Z >= 0 ? bounds.Max.Z : bounds.Min.Z
			);
			if (Vector3.Dot(plane.Normal, positiveVertex) + plane.D < 0)
				return false;
		}
		return true;
	}

	public bool IsVisible(BoundingSphere sphere)
	{
		for (int i = 0; i < 6; i++)
		{
			let plane = FrustumPlanes[i];
			let distance = Vector3.Dot(plane.Normal, sphere.Center) + plane.D;
			if (distance < -sphere.Radius)
				return false;
		}
		return true;
	}

	private void ExtractFrustumPlanes() mut
	{
		let m = ViewProjectionMatrix;

		FrustumPlanes[0] = Plane.Normalize(Plane(m.M14 + m.M11, m.M24 + m.M21, m.M34 + m.M31, m.M44 + m.M41));
		FrustumPlanes[1] = Plane.Normalize(Plane(m.M14 - m.M11, m.M24 - m.M21, m.M34 - m.M31, m.M44 - m.M41));
		FrustumPlanes[2] = Plane.Normalize(Plane(m.M14 + m.M12, m.M24 + m.M22, m.M34 + m.M32, m.M44 + m.M42));
		FrustumPlanes[3] = Plane.Normalize(Plane(m.M14 - m.M12, m.M24 - m.M22, m.M34 - m.M32, m.M44 - m.M42));
		FrustumPlanes[4] = Plane.Normalize(Plane(m.M13, m.M23, m.M33, m.M43));
		FrustumPlanes[5] = Plane.Normalize(Plane(m.M14 - m.M13, m.M24 - m.M23, m.M34 - m.M33, m.M44 - m.M43));
	}

	public void Reset() mut
	{
		Position = .Zero;
		Forward = .(0, 0, -1);
		Up = .(0, 1, 0);
		Right = .(1, 0, 0);
		ViewMatrix = .Identity;
		ProjectionMatrix = .Identity;
		ViewProjectionMatrix = .Identity;
		PrevViewProjectionMatrix = .Identity;
		InverseViewMatrix = .Identity;
		InverseProjectionMatrix = .Identity;
		FrustumPlanes = default;
		Projection = .Perspective;
		FieldOfView = Math.PI_f / 4.0f;
		AspectRatio = 16.0f / 9.0f;
		NearPlane = 0.1f;
		FarPlane = 1000.0f;
		OrthoWidth = 10.0f;
		OrthoHeight = 10.0f;
		JitterOffset = .Zero;
		JitterIndex = 0;
		Priority = 0;
		IsActive = false;
		IsMainCamera = false;
	}
}

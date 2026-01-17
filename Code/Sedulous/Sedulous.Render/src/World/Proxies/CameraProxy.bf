namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;

/// Camera projection type.
public enum ProjectionType : uint8
{
	/// Perspective projection (3D).
	Perspective,

	/// Orthographic projection (2D/isometric).
	Orthographic
}

/// Proxy for a camera in the render world.
/// Contains all data needed for view/projection calculations and culling.
public struct CameraProxy
{
	/// Position in world space.
	public Vector3 Position;

	/// Forward direction (normalized).
	public Vector3 Forward;

	/// Up direction (normalized).
	public Vector3 Up;

	/// Right direction (computed from forward and up).
	public Vector3 Right;

	/// View matrix.
	public Matrix ViewMatrix;

	/// Projection matrix.
	public Matrix ProjectionMatrix;

	/// Combined view-projection matrix.
	public Matrix ViewProjectionMatrix;

	/// Previous frame view-projection matrix (for motion vectors and reprojection).
	public Matrix PrevViewProjectionMatrix;

	/// Inverse view matrix.
	public Matrix InverseViewMatrix;

	/// Inverse projection matrix.
	public Matrix InverseProjectionMatrix;

	/// Frustum planes for culling (6 planes: left, right, bottom, top, near, far).
	public Plane[6] FrustumPlanes;

	/// Projection type.
	public ProjectionType Projection;

	/// Field of view in radians (for perspective).
	public float FieldOfView;

	/// Aspect ratio (width / height).
	public float AspectRatio;

	/// Near clipping plane distance.
	public float NearPlane;

	/// Far clipping plane distance.
	public float FarPlane;

	/// Orthographic width (for orthographic projection).
	public float OrthoWidth;

	/// Orthographic height (for orthographic projection).
	public float OrthoHeight;

	/// TAA jitter offset in pixels.
	public Vector2 JitterOffset;

	/// Current jitter index in the TAA sequence.
	public uint8 JitterIndex;

	/// Render priority (higher = rendered first for multi-camera setups).
	public int32 Priority;

	/// Generation counter (for handle validation).
	public uint32 Generation;

	/// Whether this proxy slot is in use.
	public bool IsActive;

	/// Whether this camera is the main/active camera.
	public bool IsMainCamera;

	/// Creates a default perspective camera.
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

	/// Creates a default orthographic camera.
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

	/// Updates view and projection matrices from current camera parameters.
	public void UpdateMatrices(bool flipY = false) mut
	{
		// Store previous VP for motion vectors
		PrevViewProjectionMatrix = ViewProjectionMatrix;

		// Build view matrix
		let target = Position + Forward;
		ViewMatrix = Matrix.CreateLookAt(Position, target, Up);

		// Build projection matrix
		if (Projection == .Perspective)
		{
			ProjectionMatrix = Matrix.CreatePerspectiveFieldOfView(FieldOfView, AspectRatio, NearPlane, FarPlane);
		}
		else
		{
			ProjectionMatrix = Matrix.CreateOrthographic(OrthoWidth, OrthoHeight, NearPlane, FarPlane);
		}

		// Flip Y for Vulkan if required
		if (flipY)
			ProjectionMatrix.M22 = -ProjectionMatrix.M22;

		// Apply TAA jitter
		if (JitterOffset.X != 0 || JitterOffset.Y != 0)
		{
			var jitteredProj = ProjectionMatrix;
			jitteredProj.M31 += JitterOffset.X;
			jitteredProj.M32 += JitterOffset.Y;
			ProjectionMatrix = jitteredProj;
		}

		// Combined VP
		ViewProjectionMatrix = ViewMatrix * ProjectionMatrix;

		// Inverse matrices
		Matrix.TryInvert(ViewMatrix, out InverseViewMatrix);
		Matrix.TryInvert(ProjectionMatrix, out InverseProjectionMatrix);

		// Extract frustum planes
		ExtractFrustumPlanes();
	}

	/// Sets camera position and orientation.
	public void SetLookAt(Vector3 position, Vector3 target, Vector3 up) mut
	{
		Position = position;
		Forward = Vector3.Normalize(target - position);
		Up = Vector3.Normalize(up);
		Right = Vector3.Normalize(Vector3.Cross(Forward, Up));
	}

	/// Sets camera position and direction.
	public void SetPositionDirection(Vector3 position, Vector3 forward, Vector3 up) mut
	{
		Position = position;
		Forward = Vector3.Normalize(forward);
		Up = Vector3.Normalize(up);
		Right = Vector3.Normalize(Vector3.Cross(Forward, Up));
	}

	/// Sets the TAA jitter offset for the current frame.
	/// Offset is in clip space (-1 to 1), will be applied to projection matrix.
	public void SetJitter(Vector2 pixelOffset, uint32 viewportWidth, uint32 viewportHeight) mut
	{
		// Convert pixel offset to clip space offset
		JitterOffset = Vector2(
			pixelOffset.X * 2.0f / (float)viewportWidth,
			pixelOffset.Y * 2.0f / (float)viewportHeight
		);
	}

	/// Advances to the next jitter sample in the TAA sequence.
	public void AdvanceJitter(uint8 sampleCount) mut
	{
		JitterIndex = (JitterIndex + 1) % sampleCount;
	}

	/// Tests if an AABB is visible to this camera.
	public bool IsVisible(BoundingBox bounds)
	{
		// Test against all 6 frustum planes
		for (int i = 0; i < 6; i++)
		{
			let plane = FrustumPlanes[i];

			// Get the positive vertex (furthest along plane normal)
			Vector3 positiveVertex = .(
				plane.Normal.X >= 0 ? bounds.Max.X : bounds.Min.X,
				plane.Normal.Y >= 0 ? bounds.Max.Y : bounds.Min.Y,
				plane.Normal.Z >= 0 ? bounds.Max.Z : bounds.Min.Z
			);

			// If positive vertex is behind plane, AABB is outside frustum
			if (Vector3.Dot(plane.Normal, positiveVertex) + plane.D < 0)
				return false;
		}

		return true;
	}

	/// Tests if a sphere is visible to this camera.
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

	/// Extracts frustum planes from the view-projection matrix.
	/// Uses Gribb/Hartmann method for row-major matrices with row vectors.
	/// Row vectors: clip = worldPos * VP, so use columns for extraction.
	/// Matrix naming: MRC where R=row, C=column (1-indexed)
	private void ExtractFrustumPlanes() mut
	{
		let m = ViewProjectionMatrix;

		// For row-major with row vectors (clip = world * VP):
		// Extract from columns of the matrix
		// Left plane: col4 + col1
		FrustumPlanes[0] = Plane.Normalize(Plane(
			m.M14 + m.M11,
			m.M24 + m.M21,
			m.M34 + m.M31,
			m.M44 + m.M41
		));

		// Right plane: col4 - col1
		FrustumPlanes[1] = Plane.Normalize(Plane(
			m.M14 - m.M11,
			m.M24 - m.M21,
			m.M34 - m.M31,
			m.M44 - m.M41
		));

		// Bottom plane: col4 + col2
		FrustumPlanes[2] = Plane.Normalize(Plane(
			m.M14 + m.M12,
			m.M24 + m.M22,
			m.M34 + m.M32,
			m.M44 + m.M42
		));

		// Top plane: col4 - col2
		FrustumPlanes[3] = Plane.Normalize(Plane(
			m.M14 - m.M12,
			m.M24 - m.M22,
			m.M34 - m.M32,
			m.M44 - m.M42
		));

		// Near plane: col3 (D3D convention, near=0 in NDC)
		FrustumPlanes[4] = Plane.Normalize(Plane(
			m.M13,
			m.M23,
			m.M33,
			m.M43
		));

		// Far plane: col4 - col3
		FrustumPlanes[5] = Plane.Normalize(Plane(
			m.M14 - m.M13,
			m.M24 - m.M23,
			m.M34 - m.M33,
			m.M44 - m.M43
		));
	}

	/// Resets the proxy for reuse.
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
		FieldOfView = Math.PI_f / 4.0f; // 45 degrees
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

namespace Sedulous.Framework.Renderer;

using System;
using Sedulous.Mathematics;

/// Render proxy for a camera in the scene.
/// Caches computed matrices and frustum planes for efficient culling.
struct CameraProxy
{
	/// Unique ID for this proxy.
	public uint32 Id;

	/// Is this the main/active camera.
	public bool IsMain;

	/// Camera is enabled for rendering.
	public bool Enabled;

	/// Camera position in world space.
	public Vector3 Position;

	/// Camera forward direction.
	public Vector3 Forward;

	/// Camera up direction.
	public Vector3 Up;

	/// Camera right direction.
	public Vector3 Right;

	/// Vertical field of view in radians.
	public float FieldOfView;

	/// Near clipping plane distance.
	public float NearPlane;

	/// Far clipping plane distance.
	public float FarPlane;

	/// Aspect ratio (width / height).
	public float AspectRatio;

	/// Use reverse-Z depth.
	public bool UseReverseZ;

	/// Jitter offset for TAA (in clip space).
	public Vector2 JitterOffset;

	/// Cached view matrix.
	public Matrix ViewMatrix;

	/// Cached projection matrix.
	public Matrix ProjectionMatrix;

	/// Previous frame's view-projection (for motion vectors).
	public Matrix PreviousViewProjection;

	/// Cached view-projection matrix.
	public Matrix ViewProjectionMatrix;

	/// Jittered view-projection (for TAA).
	public Matrix JitteredViewProjectionMatrix;

	/// Inverse view matrix.
	public Matrix InverseViewMatrix;

	/// Inverse projection matrix.
	public Matrix InverseProjectionMatrix;

	/// Frustum planes for culling (left, right, bottom, top, near, far).
	public Plane[6] FrustumPlanes;

	/// Viewport dimensions.
	public uint32 ViewportWidth;
	public uint32 ViewportHeight;

	/// Layer mask for what this camera can see.
	public uint32 LayerMask;

	/// Render target priority (lower = renders first).
	public int32 Priority;

	/// Creates an invalid camera proxy.
	public static Self Invalid => .()
	{
		Id = uint32.MaxValue,
		IsMain = false,
		Enabled = false,
		Position = .Zero,
		Forward = .(0, 0, -1),
		Up = .(0, 1, 0),
		Right = .(1, 0, 0),
		FieldOfView = Math.PI_f / 4.0f,
		NearPlane = 0.1f,
		FarPlane = 1000.0f,
		AspectRatio = 16.0f / 9.0f,
		UseReverseZ = true,
		JitterOffset = .Zero,
		ViewMatrix = .Identity,
		ProjectionMatrix = .Identity,
		PreviousViewProjection = .Identity,
		ViewProjectionMatrix = .Identity,
		JitteredViewProjectionMatrix = .Identity,
		InverseViewMatrix = .Identity,
		InverseProjectionMatrix = .Identity,
		FrustumPlanes = .(),
		ViewportWidth = 1920,
		ViewportHeight = 1080,
		LayerMask = 0xFFFFFFFF,
		Priority = 0
	};

	/// Creates a camera proxy from a Camera struct.
	public static Self FromCamera(uint32 id, Camera camera, uint32 viewportWidth, uint32 viewportHeight)
	{
		var proxy = Invalid;
		proxy.Id = id;
		proxy.Enabled = true;
		proxy.Position = camera.Position;
		proxy.Forward = camera.Forward;
		proxy.Up = camera.Up;
		proxy.Right = Vector3.Normalize(Vector3.Cross(camera.Forward, camera.Up));
		proxy.FieldOfView = camera.FieldOfView;
		proxy.NearPlane = camera.NearPlane;
		proxy.FarPlane = camera.FarPlane;
		proxy.AspectRatio = camera.AspectRatio;
		proxy.UseReverseZ = camera.UseReverseZ;
		proxy.JitterOffset = camera.JitterOffset;
		proxy.ViewportWidth = viewportWidth;
		proxy.ViewportHeight = viewportHeight;
		proxy.UpdateMatrices();
		return proxy;
	}

	/// Updates all cached matrices and frustum planes.
	public void UpdateMatrices() mut
	{
		// Save previous VP for motion vectors
		PreviousViewProjection = ViewProjectionMatrix;

		// Compute view matrix
		ViewMatrix = Matrix.CreateLookAt(Position, Position + Forward, Up);

		// Compute projection matrix
		// Note: Y-flip for Vulkan should be applied by the caller using Device.FlipProjectionRequired
		if (UseReverseZ)
			ProjectionMatrix = CreateReverseZPerspective(FieldOfView, AspectRatio, NearPlane, FarPlane);
		else
			ProjectionMatrix = Matrix.CreatePerspectiveFieldOfView(FieldOfView, AspectRatio, NearPlane, FarPlane);

		// Compute combined matrices (with Y-flip for GPU)
		// Row-vector order: View * Projection
		ViewProjectionMatrix = ViewMatrix * ProjectionMatrix;

		// Jittered VP for TAA
		var jitteredProj = ProjectionMatrix;
		jitteredProj.M31 += JitterOffset.X;
		jitteredProj.M32 += JitterOffset.Y;
		JitteredViewProjectionMatrix = ViewMatrix * jitteredProj;

		// Compute inverse matrices
		InverseViewMatrix = Matrix.Invert(ViewMatrix);
		InverseProjectionMatrix = Matrix.Invert(ProjectionMatrix);

		// Compute frustum planes directly from camera geometry
		ComputeFrustumPlanesFromCamera();
	}

	/// Updates position and direction from transform matrix.
	public void SetTransform(Matrix transform) mut
	{
		Position = transform.Translation;
		Forward = -Vector3.Normalize(.(transform.M31, transform.M32, transform.M33));
		Up = Vector3.Normalize(.(transform.M21, transform.M22, transform.M23));
		Right = Vector3.Normalize(.(transform.M11, transform.M12, transform.M13));
		UpdateMatrices();
	}

	/// Sets TAA jitter using Halton sequence.
	public void SetHaltonJitter(uint32 frameIndex) mut
	{
		float x = HaltonSequence(frameIndex + 1, 2);
		float y = HaltonSequence(frameIndex + 1, 3);
		JitterOffset.X = (x - 0.5f) / (float)ViewportWidth * 2.0f;
		JitterOffset.Y = (y - 0.5f) / (float)ViewportHeight * 2.0f;
	}

	/// Clears TAA jitter.
	public void ClearJitter() mut
	{
		JitterOffset = .Zero;
	}

	/// Tests if a bounding box is inside the frustum.
	public bool IsInFrustum(BoundingBox bounds)
	{
		let center = (bounds.Min + bounds.Max) * 0.5f;
		let extents = (bounds.Max - bounds.Min) * 0.5f;

		for (int i = 0; i < 6; i++)
		{
			let plane = FrustumPlanes[i];
			float d = plane.Normal.X * center.X + plane.Normal.Y * center.Y + plane.Normal.Z * center.Z + plane.D;
			float r = extents.X * Math.Abs(plane.Normal.X) +
					  extents.Y * Math.Abs(plane.Normal.Y) +
					  extents.Z * Math.Abs(plane.Normal.Z);

			if (d + r < 0)
				return false;
		}

		return true;
	}

	/// Tests if a bounding sphere is inside the frustum.
	public bool IsInFrustum(BoundingSphere sphere)
	{
		for (int i = 0; i < 6; i++)
		{
			let plane = FrustumPlanes[i];
			float d = plane.Normal.X * sphere.Center.X +
					  plane.Normal.Y * sphere.Center.Y +
					  plane.Normal.Z * sphere.Center.Z + plane.D;

			if (d < -sphere.Radius)
				return false;
		}

		return true;
	}

	/// Computes frustum planes directly from camera geometry.
	/// More reliable than matrix extraction - doesn't depend on matrix conventions.
	private void ComputeFrustumPlanesFromCamera() mut
	{
		// Recompute Right vector from Forward and Up (in case camera rotated)
		Right = Vector3.Normalize(Vector3.Cross(Forward, Up));

		// Compute half angles
		float halfVFov = FieldOfView * 0.5f;
		float halfHFov = Math.Atan(Math.Tan(halfVFov) * AspectRatio);

		// Compute edge directions (from camera toward frustum edges)
		float tanH = Math.Tan(halfHFov);
		float tanV = Math.Tan(halfVFov);

		// Left edge: forward + left offset
		Vector3 leftEdge = Vector3.Normalize(Forward - Right * tanH);
		// Right edge: forward + right offset
		Vector3 rightEdge = Vector3.Normalize(Forward + Right * tanH);
		// Bottom edge: forward + down offset
		Vector3 bottomEdge = Vector3.Normalize(Forward - Up * tanV);
		// Top edge: forward + up offset
		Vector3 topEdge = Vector3.Normalize(Forward + Up * tanV);

		// Compute plane normals (pointing INTO frustum)
		// Left plane: cross(leftEdge, Up) points right (into frustum)
		Vector3 leftNormal = Vector3.Normalize(Vector3.Cross(leftEdge, Up));
		// Right plane: cross(Up, rightEdge) points left (into frustum)
		Vector3 rightNormal = Vector3.Normalize(Vector3.Cross(Up, rightEdge));
		// Bottom plane: cross(Right, bottomEdge) points up (into frustum)
		Vector3 bottomNormal = Vector3.Normalize(Vector3.Cross(Right, bottomEdge));
		// Top plane: cross(topEdge, Right) points down (into frustum)
		Vector3 topNormal = Vector3.Normalize(Vector3.Cross(topEdge, Right));

		// Plane D = -dot(normal, pointOnPlane), camera position is on all side planes
		FrustumPlanes[0] = .(leftNormal, -Vector3.Dot(leftNormal, Position));
		FrustumPlanes[1] = .(rightNormal, -Vector3.Dot(rightNormal, Position));
		FrustumPlanes[2] = .(bottomNormal, -Vector3.Dot(bottomNormal, Position));
		FrustumPlanes[3] = .(topNormal, -Vector3.Dot(topNormal, Position));

		// Near plane: normal = Forward, point = Position + Forward * NearPlane
		Vector3 nearPoint = Position + Forward * NearPlane;
		FrustumPlanes[4] = .(Forward, -Vector3.Dot(Forward, nearPoint));

		// Far plane: normal = -Forward, point = Position + Forward * FarPlane
		Vector3 farPoint = Position + Forward * FarPlane;
		Vector3 farNormal = -Forward;
		FrustumPlanes[5] = .(farNormal, -Vector3.Dot(farNormal, farPoint));
	}

	/// Normalizes a plane.
	private static Plane NormalizePlane(Plane p)
	{
		float len = Math.Sqrt(p.Normal.X * p.Normal.X + p.Normal.Y * p.Normal.Y + p.Normal.Z * p.Normal.Z);
		if (len > 0.0001f)
			return .(p.Normal / len, p.D / len);
		return p;
	}

	/// Creates reverse-Z perspective projection.
	private static Matrix CreateReverseZPerspective(float fov, float aspect, float near, float far)
	{
		float tanHalfFov = Math.Tan(fov * 0.5f);

		Matrix result = default;
		result.M11 = 1.0f / (aspect * tanHalfFov);
		result.M22 = 1.0f / tanHalfFov;
		result.M33 = near / (far - near);
		result.M34 = -1.0f;
		result.M43 = (far * near) / (far - near);
		result.M44 = 0.0f;

		return result;
	}

	/// Halton sequence generator.
	private static float HaltonSequence(uint32 index, uint32 base_)
	{
		float result = 0.0f;
		float f = 1.0f;
		var i = index;

		while (i > 0)
		{
			f /= (float)base_;
			result += f * (float)(i % base_);
			i /= base_;
		}

		return result;
	}

	/// Checks if this proxy is valid.
	public bool IsValid => Id != uint32.MaxValue;
}

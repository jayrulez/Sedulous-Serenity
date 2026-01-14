namespace Sedulous.RendererNext;

using System;
using Sedulous.Mathematics;

/// Camera definition for rendering.
struct Camera
{
	/// Camera position in world space.
	public Vector3 Position;

	/// Camera forward direction (normalized).
	public Vector3 Forward;

	/// Camera up direction (normalized).
	public Vector3 Up;

	/// Vertical field of view in radians.
	public float FieldOfView;

	/// Near clipping plane distance.
	public float NearPlane;

	/// Far clipping plane distance.
	public float FarPlane;

	/// Aspect ratio (width / height).
	public float AspectRatio;

	/// Use reverse-Z depth mapping.
	public bool UseReverseZ;

	/// TAA jitter offset in clip space.
	public Vector2 JitterOffset;

	/// Creates a default camera.
	public static Self Default => .()
	{
		Position = .Zero,
		Forward = .(0, 0, -1),
		Up = .(0, 1, 0),
		FieldOfView = Math.PI_f / 4.0f,
		NearPlane = 0.1f,
		FarPlane = 1000.0f,
		AspectRatio = 16.0f / 9.0f,
		UseReverseZ = true,
		JitterOffset = .Zero
	};

	/// Creates a perspective camera looking at a target.
	public static Self LookAt(Vector3 position, Vector3 target, Vector3 up, float fov, float aspect, float near, float far)
	{
		return .()
		{
			Position = position,
			Forward = Vector3.Normalize(target - position),
			Up = up,
			FieldOfView = fov,
			NearPlane = near,
			FarPlane = far,
			AspectRatio = aspect,
			UseReverseZ = true,
			JitterOffset = .Zero
		};
	}

	/// Computes the right vector.
	public Vector3 Right => Vector3.Normalize(Vector3.Cross(Forward, Up));

	/// Computes the view matrix.
	public Matrix GetViewMatrix()
	{
		return Matrix.CreateLookAt(Position, Position + Forward, Up);
	}

	/// Computes the projection matrix.
	public Matrix GetProjectionMatrix()
	{
		if (UseReverseZ)
			return CreateReverseZPerspective(FieldOfView, AspectRatio, NearPlane, FarPlane);
		else
			return Matrix.CreatePerspectiveFieldOfView(FieldOfView, AspectRatio, NearPlane, FarPlane);
	}

	/// Creates a reverse-Z perspective projection matrix.
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
}

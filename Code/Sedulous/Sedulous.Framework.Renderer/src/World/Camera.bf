namespace Sedulous.Framework.Renderer;

using System;
using Sedulous.Mathematics;

/// Camera for 3D rendering with view and projection matrices.
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

	/// Whether to use reverse-Z depth (recommended for better precision).
	public bool UseReverseZ;

	/// Jitter offset for TAA (in clip space, typically -0.5 to 0.5 pixels).
	public Vector2 JitterOffset;

	/// Creates a default camera.
	public this()
	{
		Position = .(0, 0, 5);
		Forward = .(0, 0, -1);
		Up = .(0, 1, 0);
		FieldOfView = Math.PI_f / 4.0f; // 45 degrees
		NearPlane = 0.1f;
		FarPlane = 1000.0f;
		AspectRatio = 16.0f / 9.0f;
		UseReverseZ = true;
		JitterOffset = .Zero;
	}

	/// Creates a camera looking at a target point.
	public static Self LookAt(Vector3 position, Vector3 target, Vector3 up, float fov = Math.PI_f / 4.0f)
	{
		var camera = Self();
		camera.Position = position;
		camera.Forward = Vector3.Normalize(target - position);
		camera.Up = up;
		camera.FieldOfView = fov;
		return camera;
	}

	/// Gets the view matrix.
	public Matrix4x4 ViewMatrix
	{
		get
		{
			return Matrix4x4.CreateLookAt(Position, Position + Forward, Up);
		}
	}

	/// Gets the projection matrix (standard or reverse-Z).
	public Matrix4x4 ProjectionMatrix
	{
		get
		{
			if (UseReverseZ)
			{
				return CreateReverseZPerspective(FieldOfView, AspectRatio, NearPlane, FarPlane);
			}
			else
			{
				return Matrix4x4.CreatePerspective(FieldOfView, AspectRatio, NearPlane, FarPlane);
			}
		}
	}

	/// Gets the jittered projection matrix for TAA.
	public Matrix4x4 JitteredProjectionMatrix
	{
		get
		{
			var proj = ProjectionMatrix;
			// Apply jitter to projection matrix (in clip space)
			proj.M31 += JitterOffset.X;
			proj.M32 += JitterOffset.Y;
			return proj;
		}
	}

	/// Gets the combined view-projection matrix.
	public Matrix4x4 ViewProjectionMatrix
	{
		get
		{
			return ProjectionMatrix * ViewMatrix;
		}
	}

	/// Gets the right direction vector.
	public Vector3 Right
	{
		get
		{
			return Vector3.Normalize(Vector3.Cross(Forward, Up));
		}
	}

	/// Creates a reverse-Z perspective projection matrix.
	/// In reverse-Z, near plane maps to 1 and far plane maps to 0.
	/// This provides better depth precision at distance.
	private static Matrix4x4 CreateReverseZPerspective(float fov, float aspect, float near, float far)
	{
		float tanHalfFov = Math.Tan(fov * 0.5f);

		Matrix4x4 result = .Zero;
		result.M11 = 1.0f / (aspect * tanHalfFov);
		result.M22 = 1.0f / tanHalfFov;
		// Reverse-Z: swap near and far in the projection
		result.M33 = near / (far - near);
		result.M34 = -1.0f;
		result.M43 = (far * near) / (far - near);
		result.M44 = 0.0f;

		return result;
	}

	/// Updates aspect ratio (call on window resize).
	public void SetAspectRatio(uint32 width, uint32 height) mut
	{
		AspectRatio = (float)width / (float)height;
	}

	/// Sets a Halton sequence jitter for TAA.
	/// frameIndex should be 0-15 for a 16-sample sequence.
	public void SetHaltonJitter(uint32 frameIndex, uint32 width, uint32 height) mut
	{
		// Halton sequence bases 2 and 3
		float x = HaltonSequence(frameIndex + 1, 2);
		float y = HaltonSequence(frameIndex + 1, 3);

		// Convert to clip space (-0.5 to 0.5 pixels, then to NDC)
		JitterOffset.X = (x - 0.5f) / (float)width * 2.0f;
		JitterOffset.Y = (y - 0.5f) / (float)height * 2.0f;
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
}

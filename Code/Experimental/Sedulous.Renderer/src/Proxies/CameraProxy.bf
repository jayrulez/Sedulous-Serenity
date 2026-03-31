namespace Sedulous.Renderer;

using Sedulous.Core.Mathematics;
using System;

/// Camera projection type.
enum ProjectionType
{
	Perspective,
	Orthographic,
}

/// Camera proxy data — projection, view parameters.
[CRepr]
struct CameraProxy
{
	/// Projection mode.
	public ProjectionType Projection = .Perspective;
	/// World-space position.
	public Vector3 Position;
	/// Look-at target.
	public Vector3 Target = .(0, 0, -1);
	/// Up vector.
	public Vector3 Up = .(0, 1, 0);
	/// Vertical field of view in radians (perspective only).
	public float FieldOfView = 1.0472f; // 60 degrees
	/// Near clip plane distance.
	public float NearPlane = 0.1f;
	/// Far clip plane distance.
	public float FarPlane = 1000.0f;
	/// Orthographic width (orthographic only).
	public float OrthoWidth = 10.0f;
	/// Orthographic height (orthographic only).
	public float OrthoHeight = 10.0f;
}

namespace Sedulous.RendererNG;

using System;
using Sedulous.Mathematics;

/// Projection type for cameras.
enum ProjectionType : uint8
{
	/// Perspective projection (3D).
	Perspective,
	/// Orthographic projection (2D/isometric).
	Orthographic
}

/// Proxy for a camera/view.
/// Contains all data needed for view and projection calculations.
struct CameraProxy
{
	/// World position of the camera.
	public Vector3 Position;

	/// Forward direction (normalized).
	public Vector3 Forward;

	/// Up direction (normalized).
	public Vector3 Up;

	/// Right direction (normalized, derived from Forward × Up).
	public Vector3 Right;

	/// Field of view in radians (for perspective projection).
	public float FieldOfView;

	/// Near clipping plane distance.
	public float NearPlane;

	/// Far clipping plane distance.
	public float FarPlane;

	/// Aspect ratio (width / height).
	public float AspectRatio;

	/// Orthographic width (for orthographic projection).
	public float OrthoWidth;

	/// Orthographic height (for orthographic projection).
	public float OrthoHeight;

	/// Projection type.
	public ProjectionType Projection;

	/// Camera flags.
	public CameraFlags Flags;

	/// Layer mask for what this camera sees.
	public uint32 CullingMask;

	/// Render priority (lower = renders first).
	public int32 Priority;

	/// Viewport rectangle (0-1 normalized).
	public Rect Viewport;

	/// Returns true if this camera is enabled.
	public bool IsEnabled => (Flags & .Enabled) != 0;

	/// Calculates the view matrix.
	public Matrix GetViewMatrix()
	{
		return Matrix.CreateLookAt(Position, Position + Forward, Up);
	}

	/// Calculates the projection matrix.
	public Matrix GetProjectionMatrix()
	{
		if (Projection == .Perspective)
		{
			return Matrix.CreatePerspectiveFieldOfView(FieldOfView, AspectRatio, NearPlane, FarPlane);
		}
		else
		{
			return Matrix.CreateOrthographic(OrthoWidth, OrthoHeight, NearPlane, FarPlane);
		}
	}

	/// Calculates the view-projection matrix.
	public Matrix GetViewProjectionMatrix()
	{
		return GetViewMatrix() * GetProjectionMatrix();
	}

	/// Creates a default perspective camera proxy.
	public static Self DefaultPerspective => .()
	{
		Position = .Zero,
		Forward = .(0, 0, -1),
		Up = .(0, 1, 0),
		Right = .(1, 0, 0),
		FieldOfView = Math.PI_f / 4, // 45 degrees
		NearPlane = 0.1f,
		FarPlane = 1000.0f,
		AspectRatio = 16.0f / 9.0f,
		OrthoWidth = 10.0f,
		OrthoHeight = 10.0f,
		Projection = .Perspective,
		Flags = .Enabled | .MainCamera,
		CullingMask = 0xFFFFFFFF,
		Priority = 0,
		Viewport = .(0, 0, 1, 1)
	};

	/// Creates a default orthographic camera proxy.
	public static Self DefaultOrthographic => .()
	{
		Position = .Zero,
		Forward = .(0, 0, -1),
		Up = .(0, 1, 0),
		Right = .(1, 0, 0),
		FieldOfView = Math.PI_f / 4,
		NearPlane = 0.1f,
		FarPlane = 1000.0f,
		AspectRatio = 16.0f / 9.0f,
		OrthoWidth = 10.0f,
		OrthoHeight = 10.0f,
		Projection = .Orthographic,
		Flags = .Enabled,
		CullingMask = 0xFFFFFFFF,
		Priority = 0,
		Viewport = .(0, 0, 1, 1)
	};
}

/// Flags for camera behavior.
enum CameraFlags : uint32
{
	None = 0,

	/// Camera is enabled and should render.
	Enabled = 1 << 0,

	/// This is the main camera.
	MainCamera = 1 << 1,

	/// Camera clears the color buffer.
	ClearColor = 1 << 2,

	/// Camera clears the depth buffer.
	ClearDepth = 1 << 3,

	/// Camera renders to the screen (vs. render texture).
	RenderToScreen = 1 << 4,

	/// Default flags.
	Default = Enabled | ClearColor | ClearDepth | RenderToScreen
}

/// Rectangle for viewport definition.
struct Rect
{
	public float X;
	public float Y;
	public float Width;
	public float Height;

	public this(float x, float y, float width, float height)
	{
		X = x;
		Y = y;
		Width = width;
		Height = height;
	}
}

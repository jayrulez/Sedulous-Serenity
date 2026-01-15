namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Type of render view.
enum RenderViewType : uint8
{
	/// Main camera view.
	MainCamera,
	/// Secondary camera view (split-screen, picture-in-picture).
	SecondaryCamera,
	/// Shadow cascade view.
	ShadowCascade,
	/// Local light shadow view (atlas tile).
	ShadowLocal,
	/// Reflection probe view.
	ReflectionProbe,
	/// Custom view.
	Custom
}

/// Flags for render view configuration.
enum RenderViewFlags : uint16
{
	None = 0,

	/// View is enabled and should be rendered.
	Enabled = 1 << 0,

	/// Clear color attachment.
	ClearColor = 1 << 1,

	/// Clear depth attachment.
	ClearDepth = 1 << 2,

	/// Use reverse-Z depth.
	ReverseZ = 1 << 3,

	/// Use orthographic projection.
	Orthographic = 1 << 4,

	/// Depth-only rendering (shadow pass).
	DepthOnly = 1 << 5,

	/// Render transparent objects.
	RenderTransparent = 1 << 6,

	/// Render opaque objects.
	RenderOpaque = 1 << 7,

	/// Default flags for main camera.
	DefaultCamera = Enabled | ClearColor | ClearDepth | RenderOpaque | RenderTransparent,

	/// Default flags for shadow cascade.
	DefaultShadow = Enabled | ClearDepth | DepthOnly | RenderOpaque
}

/// A render view defines how a scene is rendered from a particular viewpoint.
/// Used for cameras, shadow cascades, reflection probes, etc.
class RenderView
{
	// ===== Identity =====

	/// Unique view ID within the frame.
	public uint32 Id;

	/// Type of this view.
	public RenderViewType Type = .MainCamera;

	/// Configuration flags.
	public RenderViewFlags Flags = .DefaultCamera;

	/// Render priority (lower = rendered first, shadows typically negative).
	public int16 Priority = 0;

	/// Debug name for this view.
	public String Name ~ delete _;

	// ===== Transform =====

	/// View position in world space.
	public Vector3 Position;

	/// View forward direction (normalized).
	public Vector3 Forward = .(0, 0, -1);

	/// View up direction (normalized).
	public Vector3 Up = .(0, 1, 0);

	/// View right direction (normalized).
	public Vector3 Right = .(1, 0, 0);

	// ===== Projection =====

	/// Near clipping plane distance.
	public float NearPlane = 0.1f;

	/// Far clipping plane distance.
	public float FarPlane = 1000.0f;

	/// Field of view in radians (perspective) or ortho size (orthographic).
	public float FieldOfViewOrSize = Math.PI_f / 4.0f;

	/// Aspect ratio (width / height).
	public float AspectRatio = 16.0f / 9.0f;

	// ===== Matrices =====

	/// View matrix (world to view space).
	public Matrix ViewMatrix = .Identity;

	/// Projection matrix (view to clip space).
	public Matrix ProjectionMatrix = .Identity;

	/// Combined view-projection matrix.
	public Matrix ViewProjectionMatrix = .Identity;

	/// Inverse view matrix.
	public Matrix InverseViewMatrix = .Identity;

	/// Inverse projection matrix.
	public Matrix InverseProjectionMatrix = .Identity;

	/// Inverse view-projection matrix.
	public Matrix InverseViewProjectionMatrix = .Identity;

	/// Previous frame's view-projection (for motion vectors).
	public Matrix PreviousViewProjectionMatrix = .Identity;

	// ===== Frustum =====

	/// Frustum planes for culling (left, right, bottom, top, near, far).
	public Plane[6] FrustumPlanes;

	// ===== Layer Mask =====

	/// Layer mask for filtering objects.
	public uint32 LayerMask = uint32.MaxValue;

	// ===== Viewport =====

	/// Viewport X position in pixels.
	public int32 ViewportX = 0;

	/// Viewport Y position in pixels.
	public int32 ViewportY = 0;

	/// Viewport width in pixels.
	public int32 ViewportWidth = 1920;

	/// Viewport height in pixels.
	public int32 ViewportHeight = 1080;

	/// Scissor X position in pixels.
	public int32 ScissorX = 0;

	/// Scissor Y position in pixels.
	public int32 ScissorY = 0;

	/// Scissor width in pixels.
	public int32 ScissorWidth = 1920;

	/// Scissor height in pixels.
	public int32 ScissorHeight = 1080;

	// ===== Render Targets =====

	/// Color render target (null for shadow views).
	public ITextureView ColorTarget;

	/// Depth render target.
	public ITextureView DepthTarget;

	// ===== Clear Values =====

	/// Color to clear to.
	public Vector4 ClearColor = .(0.1f, 0.1f, 0.1f, 1.0f);

	/// Depth value to clear to.
	public float ClearDepth = 1.0f;

	/// Stencil value to clear to.
	public uint8 ClearStencil = 0;

	// ===== Shadow-Specific =====

	/// Cascade index (for shadow cascades).
	public int32 CascadeIndex = -1;

	/// Shadow atlas tile index (for local shadows).
	public int32 AtlasTileIndex = -1;

	// ===== Methods =====

	/// Creates a new render view with a name.
	public this(StringView name = "")
	{
		if (!name.IsEmpty)
			Name = new String(name);
	}

	/// Whether this view is enabled.
	public bool IsEnabled => Flags.HasFlag(.Enabled);

	/// Whether this is a depth-only view.
	public bool IsDepthOnly => Flags.HasFlag(.DepthOnly);

	/// Whether to clear the color attachment.
	public bool ShouldClearColor => Flags.HasFlag(.ClearColor);

	/// Whether to clear the depth attachment.
	public bool ShouldClearDepth => Flags.HasFlag(.ClearDepth);

	/// Whether this view uses reverse-Z depth.
	public bool UsesReverseZ => Flags.HasFlag(.ReverseZ);

	/// Whether this view uses orthographic projection.
	public bool IsOrthographic => Flags.HasFlag(.Orthographic);

	/// Updates all matrices from position, direction, and projection parameters.
	public void UpdateMatrices()
	{
		// Build view matrix
		ViewMatrix = Matrix.CreateLookAt(Position, Position + Forward, Up);
		InverseViewMatrix = Matrix.Invert(ViewMatrix);

		// Build projection matrix
		if (IsOrthographic)
		{
			float halfWidth = FieldOfViewOrSize * AspectRatio * 0.5f;
			float halfHeight = FieldOfViewOrSize * 0.5f;
			ProjectionMatrix = Matrix.CreateOrthographic(halfWidth * 2, halfHeight * 2, NearPlane, FarPlane);
		}
		else
		{
			ProjectionMatrix = Matrix.CreatePerspectiveFieldOfView(FieldOfViewOrSize, AspectRatio, NearPlane, FarPlane);
		}
		InverseProjectionMatrix = Matrix.Invert(ProjectionMatrix);

		// Combined matrices
		ViewProjectionMatrix = ViewMatrix * ProjectionMatrix;
		InverseViewProjectionMatrix = Matrix.Invert(ViewProjectionMatrix);

		// Extract frustum planes
		ExtractFrustumPlanes();
	}

	/// Extracts frustum planes from the view-projection matrix.
	/// Uses Gribb/Hartmann method adapted for row-major matrices with row vector convention (v * M).
	/// Translation is in row 4 (M41, M42, M43), so we extract planes from rows.
	private void ExtractFrustumPlanes()
	{
		let m = ViewProjectionMatrix;

		// For row-major matrices with v*M convention:
		// Left plane:   row4 + row1
		FrustumPlanes[0] = Plane.Normalize(Plane(
			m.M41 + m.M11,
			m.M42 + m.M12,
			m.M43 + m.M13,
			m.M44 + m.M14
		));

		// Right plane:  row4 - row1
		FrustumPlanes[1] = Plane.Normalize(Plane(
			m.M41 - m.M11,
			m.M42 - m.M12,
			m.M43 - m.M13,
			m.M44 - m.M14
		));

		// Bottom plane: row4 + row2
		FrustumPlanes[2] = Plane.Normalize(Plane(
			m.M41 + m.M21,
			m.M42 + m.M22,
			m.M43 + m.M23,
			m.M44 + m.M24
		));

		// Top plane:    row4 - row2
		FrustumPlanes[3] = Plane.Normalize(Plane(
			m.M41 - m.M21,
			m.M42 - m.M22,
			m.M43 - m.M23,
			m.M44 - m.M24
		));

		// Near plane:   row3 (for [0,1] depth range)
		FrustumPlanes[4] = Plane.Normalize(Plane(
			m.M31,
			m.M32,
			m.M33,
			m.M34
		));

		// Far plane:    row4 - row3
		FrustumPlanes[5] = Plane.Normalize(Plane(
			m.M41 - m.M31,
			m.M42 - m.M32,
			m.M43 - m.M33,
			m.M44 - m.M34
		));
	}

	/// Sets the viewport and scissor to the same rectangle.
	public void SetViewport(int32 x, int32 y, int32 width, int32 height)
	{
		ViewportX = x;
		ViewportY = y;
		ViewportWidth = width;
		ViewportHeight = height;
		ScissorX = x;
		ScissorY = y;
		ScissorWidth = width;
		ScissorHeight = height;
		AspectRatio = (float)width / (float)height;
	}

	/// Saves the current view-projection as the previous frame's matrix.
	public void SavePreviousTransform()
	{
		PreviousViewProjectionMatrix = ViewProjectionMatrix;
	}

	// ===== Factory Methods =====

	/// Creates a perspective camera view.
	public static RenderView CreateCamera(
		StringView name,
		Vector3 position,
		Vector3 forward,
		Vector3 up,
		float fovRadians,
		float aspectRatio,
		float nearPlane,
		float farPlane,
		int32 viewportWidth,
		int32 viewportHeight)
	{
		let view = new RenderView(name);
		view.Type = .MainCamera;
		view.Flags = .DefaultCamera;
		view.Position = position;
		view.Forward = Vector3.Normalize(forward);
		view.Up = Vector3.Normalize(up);
		view.Right = Vector3.Normalize(Vector3.Cross(view.Forward, view.Up));
		view.FieldOfViewOrSize = fovRadians;
		view.AspectRatio = aspectRatio;
		view.NearPlane = nearPlane;
		view.FarPlane = farPlane;
		view.SetViewport(0, 0, viewportWidth, viewportHeight);
		view.UpdateMatrices();
		return view;
	}

	/// Creates a perspective camera view from a CameraProxy.
	public static RenderView CreateFromCameraProxy(CameraProxy* camera, int32 viewportWidth, int32 viewportHeight)
	{
		let view = new RenderView();
		view.Type = .MainCamera;
		view.Flags = .DefaultCamera;

		if ((camera.Flags & .MainCamera) != 0)
			view.Type = .MainCamera;

		view.Position = camera.Position;
		view.Forward = camera.Forward;
		view.Up = camera.Up;
		view.Right = camera.Right;
		view.FieldOfViewOrSize = camera.FieldOfView;
		view.AspectRatio = camera.AspectRatio;
		view.NearPlane = camera.NearPlane;
		view.FarPlane = camera.FarPlane;
		view.LayerMask = camera.CullingMask;
		view.Priority = (int16)camera.Priority;

		if (camera.Projection == .Orthographic)
		{
			view.Flags |= .Orthographic;
			view.FieldOfViewOrSize = camera.OrthoHeight;
		}

		// Apply viewport from camera's normalized viewport
		let vx = (int32)(camera.Viewport.X * viewportWidth);
		let vy = (int32)(camera.Viewport.Y * viewportHeight);
		let vw = (int32)(camera.Viewport.Width * viewportWidth);
		let vh = (int32)(camera.Viewport.Height * viewportHeight);
		view.SetViewport(vx, vy, vw, vh);

		view.UpdateMatrices();
		return view;
	}

	/// Creates a shadow cascade view for directional light shadows.
	public static RenderView CreateShadowCascade(
		int32 cascadeIndex,
		Vector3 lightDirection,
		Matrix viewMatrix,
		Matrix projectionMatrix,
		int32 resolution)
	{
		let view = new RenderView();
		view.Type = .ShadowCascade;
		view.Flags = .DefaultShadow;
		view.CascadeIndex = cascadeIndex;
		view.Priority = (int16)(-100 + cascadeIndex); // Shadows render before main views

		// For shadow views, we set matrices directly
		view.ViewMatrix = viewMatrix;
		view.ProjectionMatrix = projectionMatrix;
		view.ViewProjectionMatrix = viewMatrix * projectionMatrix;
		view.InverseViewMatrix = Matrix.Invert(viewMatrix);
		view.InverseProjectionMatrix = Matrix.Invert(projectionMatrix);
		view.InverseViewProjectionMatrix = Matrix.Invert(view.ViewProjectionMatrix);

		// Extract position from inverse view matrix
		view.Position = .(view.InverseViewMatrix.M14, view.InverseViewMatrix.M24, view.InverseViewMatrix.M34);
		view.Forward = Vector3.Normalize(lightDirection);

		view.SetViewport(0, 0, resolution, resolution);

		return view;
	}

	/// Creates a local light shadow view (for point/spot lights in shadow atlas).
	public static RenderView CreateShadowLocal(
		int32 atlasTileIndex,
		Vector3 position,
		Vector3 direction,
		float range,
		float fovRadians,
		int32 tileX,
		int32 tileY,
		int32 tileSize)
	{
		let view = new RenderView();
		view.Type = .ShadowLocal;
		view.Flags = .DefaultShadow;
		view.AtlasTileIndex = atlasTileIndex;
		view.Priority = -50; // After cascades, before main views

		view.Position = position;
		view.Forward = Vector3.Normalize(direction);
		// Calculate right and up vectors
		let worldUp = Vector3(0, 1, 0);
		if (Math.Abs(Vector3.Dot(view.Forward, worldUp)) > 0.99f)
			view.Right = Vector3.Normalize(Vector3.Cross(Vector3(1, 0, 0), view.Forward));
		else
			view.Right = Vector3.Normalize(Vector3.Cross(worldUp, view.Forward));
		view.Up = Vector3.Cross(view.Forward, view.Right);

		view.NearPlane = 0.1f;
		view.FarPlane = range;
		view.FieldOfViewOrSize = fovRadians;
		view.AspectRatio = 1.0f;

		view.SetViewport(tileX, tileY, tileSize, tileSize);
		view.UpdateMatrices();

		return view;
	}
}

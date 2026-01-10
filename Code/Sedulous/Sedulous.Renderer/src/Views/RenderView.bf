namespace Sedulous.Renderer;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Identifies the purpose/type of a render view.
enum RenderViewType : uint8
{
	/// Main camera view (primary display).
	MainCamera,
	/// Secondary camera (split-screen, picture-in-picture).
	SecondaryCamera,
	/// Cascaded shadow map (directional light).
	ShadowCascade,
	/// Local shadow map (point/spot light).
	ShadowLocal,
	/// Reflection probe capture.
	ReflectionProbe,
	/// Custom/user-defined view.
	Custom
}

/// Flags controlling render view behavior.
enum RenderViewFlags : uint16
{
	None            = 0,
	/// View is enabled for rendering.
	Enabled         = 1 << 0,
	/// Clear color target before rendering.
	ClearColor      = 1 << 1,
	/// Clear depth target before rendering.
	ClearDepth      = 1 << 2,
	/// Use reverse-Z depth (near=1, far=0).
	ReverseZ        = 1 << 3,
	/// Orthographic projection (vs perspective).
	Orthographic    = 1 << 4,
	/// Depth-only rendering (shadow maps).
	DepthOnly       = 1 << 5
}

/// A unified render view abstraction representing any rendering viewpoint.
/// Encapsulates camera/shadow/reflection views with associated render targets,
/// viewport, projection, and layer mask culling.
struct RenderView
{
	// ==================== Identity ====================

	/// Unique ID for this view within the frame.
	public uint32 Id;

	/// Type of view (determines rendering path).
	public RenderViewType Type;

	/// Behavior flags.
	public RenderViewFlags Flags;

	/// Render priority (lower values render first; shadows typically negative).
	public int16 Priority;

	// ==================== Transform ====================

	/// View position in world space.
	public Vector3 Position;

	/// Forward direction (normalized).
	public Vector3 Forward;

	/// Up direction (normalized).
	public Vector3 Up;

	/// Right direction (normalized).
	public Vector3 Right;

	// ==================== Projection ====================

	/// Near clipping plane distance.
	public float NearPlane;

	/// Far clipping plane distance.
	public float FarPlane;

	/// Field of view (radians) for perspective, or orthographic size.
	public float FieldOfViewOrSize;

	/// Aspect ratio (width / height).
	public float AspectRatio;

	// ==================== Cached Matrices ====================

	/// View matrix (world to view space).
	public Matrix ViewMatrix;

	/// Projection matrix (view to clip space).
	public Matrix ProjectionMatrix;

	/// Combined view-projection matrix.
	public Matrix ViewProjectionMatrix;

	/// Inverse view matrix (view to world space).
	public Matrix InverseViewMatrix;

	/// Inverse projection matrix (clip to view space).
	public Matrix InverseProjectionMatrix;

	// ==================== Culling ====================

	/// Frustum planes for culling (left, right, bottom, top, near, far).
	public Plane[6] FrustumPlanes;

	/// Layer mask - only objects with matching layers are rendered.
	public uint32 LayerMask;

	// ==================== Viewport/Scissor ====================

	/// Viewport X offset in pixels.
	public int32 ViewportX;

	/// Viewport Y offset in pixels.
	public int32 ViewportY;

	/// Viewport width in pixels.
	public uint32 ViewportWidth;

	/// Viewport height in pixels.
	public uint32 ViewportHeight;

	/// Scissor X offset in pixels.
	public int32 ScissorX;

	/// Scissor Y offset in pixels.
	public int32 ScissorY;

	/// Scissor width in pixels.
	public uint32 ScissorWidth;

	/// Scissor height in pixels.
	public uint32 ScissorHeight;

	// ==================== Render Targets (borrowed) ====================

	/// Color render target (null for depth-only passes).
	public ITextureView* ColorTarget;

	/// Depth render target.
	public ITextureView* DepthTarget;

	/// Clear color (used if ClearColor flag is set).
	public Color ClearColor;

	/// Clear depth value (used if ClearDepth flag is set).
	public float ClearDepth;

	// ==================== Type-Specific Data ====================

	/// Sub-index for multi-part views (cascade index, atlas slot, cube face).
	public int32 SubIndex;

	/// Source camera proxy handle (for camera-derived views).
	public ProxyHandle SourceCamera;

	/// Source light proxy handle (for shadow views).
	public ProxyHandle SourceLight;

	// ==================== Factory Methods ====================

	/// Creates an invalid render view.
	public static Self Invalid => .()
	{
		Id = uint32.MaxValue,
		Type = .Custom,
		Flags = .None,
		Priority = 0,
		Position = .Zero,
		Forward = .(0, 0, -1),
		Up = .(0, 1, 0),
		Right = .(1, 0, 0),
		NearPlane = 0.1f,
		FarPlane = 1000.0f,
		FieldOfViewOrSize = Math.PI_f / 4.0f,
		AspectRatio = 16.0f / 9.0f,
		ViewMatrix = .Identity,
		ProjectionMatrix = .Identity,
		ViewProjectionMatrix = .Identity,
		InverseViewMatrix = .Identity,
		InverseProjectionMatrix = .Identity,
		FrustumPlanes = .(),
		LayerMask = 0xFFFFFFFF,
		ViewportX = 0,
		ViewportY = 0,
		ViewportWidth = 1920,
		ViewportHeight = 1080,
		ScissorX = 0,
		ScissorY = 0,
		ScissorWidth = 1920,
		ScissorHeight = 1080,
		ColorTarget = null,
		DepthTarget = null,
		ClearColor = .(0, 0, 0, 1),
		ClearDepth = 0.0f,  // Reverse-Z default
		SubIndex = 0,
		SourceCamera = .Invalid,
		SourceLight = .Invalid
	};

	/// Creates a render view from a camera proxy.
	public static Self FromCameraProxy(
		uint32 id,
		CameraProxy* camera,
		ITextureView* colorTarget,
		ITextureView* depthTarget,
		bool isMainCamera = true)
	{
		var view = Invalid;
		view.Id = id;
		view.Type = isMainCamera ? .MainCamera : .SecondaryCamera;
		view.Flags = .Enabled | .ClearColor | .ClearDepth;
		if (camera.UseReverseZ)
			view.Flags |= .ReverseZ;
		view.Priority = isMainCamera ? 0 : 100;

		// Transform
		view.Position = camera.Position;
		view.Forward = camera.Forward;
		view.Up = camera.Up;
		view.Right = camera.Right;

		// Projection
		view.NearPlane = camera.NearPlane;
		view.FarPlane = camera.FarPlane;
		view.FieldOfViewOrSize = camera.FieldOfView;
		view.AspectRatio = camera.AspectRatio;

		// Matrices
		view.ViewMatrix = camera.ViewMatrix;
		view.ProjectionMatrix = camera.ProjectionMatrix;
		view.ViewProjectionMatrix = camera.ViewProjectionMatrix;
		view.InverseViewMatrix = camera.InverseViewMatrix;
		view.InverseProjectionMatrix = camera.InverseProjectionMatrix;

		// Culling
		view.FrustumPlanes = camera.FrustumPlanes;
		view.LayerMask = camera.LayerMask;

		// Viewport
		view.ViewportX = 0;
		view.ViewportY = 0;
		view.ViewportWidth = camera.ViewportWidth;
		view.ViewportHeight = camera.ViewportHeight;
		view.ScissorX = 0;
		view.ScissorY = 0;
		view.ScissorWidth = camera.ViewportWidth;
		view.ScissorHeight = camera.ViewportHeight;

		// Render targets
		view.ColorTarget = colorTarget;
		view.DepthTarget = depthTarget;
		view.ClearColor = .(0.1f, 0.1f, 0.1f, 1.0f);
		view.ClearDepth = camera.UseReverseZ ? 0.0f : 1.0f;

		// Source
		view.SourceCamera = .((uint32)camera.Id, 1);

		return view;
	}

	/// Creates a render view for a shadow cascade (directional light).
	public static Self ForShadowCascade(
		uint32 id,
		int32 cascadeIndex,
		Matrix viewProjection,
		ITextureView* depthTarget,
		uint32 viewportSize,
		int32 viewportX,
		int32 viewportY,
		ProxyHandle lightHandle,
		uint32 layerMask = 0xFFFFFFFF)
	{
		var view = Invalid;
		view.Id = id;
		view.Type = .ShadowCascade;
		view.Flags = .Enabled | .ClearDepth | .DepthOnly | .Orthographic;
		view.Priority = (int16)(-100 + cascadeIndex);  // Shadows render before main pass

		// We extract position/forward from the inverse view-projection if needed
		// For now, use identity - shadow culling uses ViewProjectionMatrix directly
		view.Position = .Zero;
		view.Forward = .(0, 0, -1);
		view.Up = .(0, 1, 0);
		view.Right = .(1, 0, 0);

		// Projection (orthographic for cascaded shadows)
		view.NearPlane = 0.0f;
		view.FarPlane = 1.0f;
		view.FieldOfViewOrSize = 1.0f;  // Ortho size
		view.AspectRatio = 1.0f;

		// Matrices
		view.ViewProjectionMatrix = viewProjection;
		ExtractFrustumPlanesFromMatrix(viewProjection, ref view.FrustumPlanes);

		// Culling
		view.LayerMask = layerMask;

		// Viewport (may be offset for atlas-based rendering)
		view.ViewportX = viewportX;
		view.ViewportY = viewportY;
		view.ViewportWidth = viewportSize;
		view.ViewportHeight = viewportSize;
		view.ScissorX = viewportX;
		view.ScissorY = viewportY;
		view.ScissorWidth = viewportSize;
		view.ScissorHeight = viewportSize;

		// Render targets
		view.ColorTarget = null;
		view.DepthTarget = depthTarget;
		view.ClearDepth = 1.0f;  // Standard Z for shadows

		// Type-specific
		view.SubIndex = cascadeIndex;
		view.SourceLight = lightHandle;

		return view;
	}

	/// Creates a render view for a local shadow (point/spot light).
	public static Self ForLocalShadow(
		uint32 id,
		int32 atlasSlot,
		Matrix viewProjection,
		ITextureView* depthTarget,
		int32 viewportX,
		int32 viewportY,
		uint32 viewportSize,
		ProxyHandle lightHandle,
		uint32 layerMask = 0xFFFFFFFF)
	{
		var view = Invalid;
		view.Id = id;
		view.Type = .ShadowLocal;
		view.Flags = .Enabled | .ClearDepth | .DepthOnly;
		view.Priority = (int16)(-50 + atlasSlot);  // After cascades, before main

		view.Position = .Zero;
		view.Forward = .(0, 0, -1);
		view.Up = .(0, 1, 0);
		view.Right = .(1, 0, 0);

		// Projection (perspective for local lights)
		view.NearPlane = 0.1f;
		view.FarPlane = 100.0f;
		view.FieldOfViewOrSize = Math.PI_f / 2.0f;  // 90 degrees for cube face
		view.AspectRatio = 1.0f;

		// Matrices
		view.ViewProjectionMatrix = viewProjection;
		ExtractFrustumPlanesFromMatrix(viewProjection, ref view.FrustumPlanes);

		// Culling
		view.LayerMask = layerMask;

		// Viewport (atlas tile)
		view.ViewportX = viewportX;
		view.ViewportY = viewportY;
		view.ViewportWidth = viewportSize;
		view.ViewportHeight = viewportSize;
		view.ScissorX = viewportX;
		view.ScissorY = viewportY;
		view.ScissorWidth = viewportSize;
		view.ScissorHeight = viewportSize;

		// Render targets
		view.ColorTarget = null;
		view.DepthTarget = depthTarget;
		view.ClearDepth = 1.0f;

		// Type-specific
		view.SubIndex = atlasSlot;
		view.SourceLight = lightHandle;

		return view;
	}

	/// Creates a render view for reflection probe capture.
	public static Self ForReflectionProbe(
		uint32 id,
		int32 cubeFace,
		Vector3 probePosition,
		Matrix viewProjection,
		ITextureView* colorTarget,
		ITextureView* depthTarget,
		uint32 faceSize,
		uint32 layerMask = 0xFFFFFFFF)
	{
		var view = Invalid;
		view.Id = id;
		view.Type = .ReflectionProbe;
		view.Flags = .Enabled | .ClearColor | .ClearDepth;
		view.Priority = -200;  // Render before shadows

		view.Position = probePosition;

		// Forward direction based on cube face
		switch (cubeFace)
		{
		case 0: view.Forward = .(1, 0, 0); view.Up = .(0, 1, 0);   // +X
		case 1: view.Forward = .(-1, 0, 0); view.Up = .(0, 1, 0);  // -X
		case 2: view.Forward = .(0, 1, 0); view.Up = .(0, 0, -1);  // +Y
		case 3: view.Forward = .(0, -1, 0); view.Up = .(0, 0, 1);  // -Y
		case 4: view.Forward = .(0, 0, 1); view.Up = .(0, 1, 0);   // +Z
		case 5: view.Forward = .(0, 0, -1); view.Up = .(0, 1, 0);  // -Z
		default: view.Forward = .(0, 0, -1); view.Up = .(0, 1, 0);
		}
		view.Right = Vector3.Normalize(Vector3.Cross(view.Forward, view.Up));

		// Projection (90 degree FOV for cube face)
		view.NearPlane = 0.1f;
		view.FarPlane = 1000.0f;
		view.FieldOfViewOrSize = Math.PI_f / 2.0f;
		view.AspectRatio = 1.0f;

		// Matrices
		view.ViewProjectionMatrix = viewProjection;
		ExtractFrustumPlanesFromMatrix(viewProjection, ref view.FrustumPlanes);

		// Culling
		view.LayerMask = layerMask;

		// Viewport
		view.ViewportX = 0;
		view.ViewportY = 0;
		view.ViewportWidth = faceSize;
		view.ViewportHeight = faceSize;
		view.ScissorX = 0;
		view.ScissorY = 0;
		view.ScissorWidth = faceSize;
		view.ScissorHeight = faceSize;

		// Render targets
		view.ColorTarget = colorTarget;
		view.DepthTarget = depthTarget;
		view.ClearColor = .(0, 0, 0, 1);
		view.ClearDepth = 1.0f;

		// Type-specific
		view.SubIndex = cubeFace;

		return view;
	}

	// ==================== Property Aliases ====================

	/// Gets the field of view (for perspective views).
	/// For orthographic views, returns FieldOfViewOrSize.
	public float FieldOfView => FieldOfViewOrSize;

	// ==================== Utility Methods ====================

	/// Returns true if this is a valid render view.
	public bool IsValid => Id != uint32.MaxValue;

	/// Returns true if the Enabled flag is set.
	public bool IsEnabled => Flags.HasFlag(.Enabled);

	/// Returns true if this is a depth-only pass (shadow map).
	public bool IsDepthOnly => Flags.HasFlag(.DepthOnly);

	/// Returns true if an object with the given layer mask is visible to this view.
	public bool IsLayerVisible(uint32 objectLayerMask)
	{
		return (objectLayerMask & LayerMask) != 0;
	}

	/// Gets the scissor rectangle.
	public void GetScissorRect(out int32 x, out int32 y, out uint32 width, out uint32 height)
	{
		x = ScissorX;
		y = ScissorY;
		width = ScissorWidth;
		height = ScissorHeight;
	}

	/// Gets the viewport rectangle.
	public void GetViewportRect(out int32 x, out int32 y, out uint32 width, out uint32 height)
	{
		x = ViewportX;
		y = ViewportY;
		width = ViewportWidth;
		height = ViewportHeight;
	}

	/// Updates the view matrix from position and orientation.
	public void UpdateViewMatrix() mut
	{
		ViewMatrix = Matrix.CreateLookAt(Position, Position + Forward, Up);
		InverseViewMatrix = Matrix.Invert(ViewMatrix);
		ViewProjectionMatrix = ViewMatrix * ProjectionMatrix;
	}

	/// Sets the viewport and scissor rect together.
	/// Useful for split-screen or picture-in-picture setups.
	public void SetViewport(int32 x, int32 y, uint32 width, uint32 height) mut
	{
		ViewportX = x;
		ViewportY = y;
		ViewportWidth = width;
		ViewportHeight = height;
		ScissorX = x;
		ScissorY = y;
		ScissorWidth = width;
		ScissorHeight = height;
	}

	/// Sets viewport as a fraction of a target size.
	/// Useful for split-screen (e.g., left half = 0.0, 0.0, 0.5, 1.0).
	public void SetViewportFraction(
		float xFrac, float yFrac, float widthFrac, float heightFrac,
		uint32 targetWidth, uint32 targetHeight) mut
	{
		ViewportX = (int32)(xFrac * targetWidth);
		ViewportY = (int32)(yFrac * targetHeight);
		ViewportWidth = (uint32)(widthFrac * targetWidth);
		ViewportHeight = (uint32)(heightFrac * targetHeight);
		ScissorX = ViewportX;
		ScissorY = ViewportY;
		ScissorWidth = ViewportWidth;
		ScissorHeight = ViewportHeight;

		// Update aspect ratio
		if (ViewportHeight > 0)
			AspectRatio = (float)ViewportWidth / (float)ViewportHeight;
	}

	/// Creates a split-screen camera view from a camera proxy.
	/// splitIndex: 0=left/top, 1=right/bottom (for 2-player)
	/// horizontal: true for side-by-side, false for top-bottom
	public static Self ForSplitScreen(
		uint32 id,
		CameraProxy* camera,
		ITextureView* colorTarget,
		ITextureView* depthTarget,
		uint32 targetWidth,
		uint32 targetHeight,
		int32 splitIndex,
		bool horizontal = true)
	{
		var view = FromCameraProxy(id, camera, colorTarget, depthTarget, splitIndex == 0);

		if (horizontal)
		{
			// Side-by-side: each player gets half width
			uint32 halfWidth = targetWidth / 2;
			view.ViewportX = splitIndex * (int32)halfWidth;
			view.ViewportY = 0;
			view.ViewportWidth = halfWidth;
			view.ViewportHeight = targetHeight;
		}
		else
		{
			// Top-bottom: each player gets half height
			uint32 halfHeight = targetHeight / 2;
			view.ViewportX = 0;
			view.ViewportY = splitIndex * (int32)halfHeight;
			view.ViewportWidth = targetWidth;
			view.ViewportHeight = halfHeight;
		}

		view.ScissorX = view.ViewportX;
		view.ScissorY = view.ViewportY;
		view.ScissorWidth = view.ViewportWidth;
		view.ScissorHeight = view.ViewportHeight;

		// Update aspect ratio based on new viewport
		if (view.ViewportHeight > 0)
			view.AspectRatio = (float)view.ViewportWidth / (float)view.ViewportHeight;

		// Secondary views have higher priority
		view.Priority = splitIndex > 0 ? (int16)100 : (int16)0;
		view.Type = splitIndex == 0 ? .MainCamera : .SecondaryCamera;

		return view;
	}

	/// Extracts frustum planes from a view-projection matrix.
	/// Planes point inward (positive half-space is inside frustum).
	public static void ExtractFrustumPlanesFromMatrix(Matrix vp, ref Plane[6] planes)
	{
		// Left plane: row4 + row1
		planes[0] = Plane.Normalize(.(
			vp.M14 + vp.M11,
			vp.M24 + vp.M21,
			vp.M34 + vp.M31,
			vp.M44 + vp.M41
		));

		// Right plane: row4 - row1
		planes[1] = Plane.Normalize(.(
			vp.M14 - vp.M11,
			vp.M24 - vp.M21,
			vp.M34 - vp.M31,
			vp.M44 - vp.M41
		));

		// Bottom plane: row4 + row2
		planes[2] = Plane.Normalize(.(
			vp.M14 + vp.M12,
			vp.M24 + vp.M22,
			vp.M34 + vp.M32,
			vp.M44 + vp.M42
		));

		// Top plane: row4 - row2
		planes[3] = Plane.Normalize(.(
			vp.M14 - vp.M12,
			vp.M24 - vp.M22,
			vp.M34 - vp.M32,
			vp.M44 - vp.M42
		));

		// Near plane: row4 + row3 (or just row3 for D3D-style)
		planes[4] = Plane.Normalize(.(
			vp.M14 + vp.M13,
			vp.M24 + vp.M23,
			vp.M34 + vp.M33,
			vp.M44 + vp.M43
		));

		// Far plane: row4 - row3
		planes[5] = Plane.Normalize(.(
			vp.M14 - vp.M13,
			vp.M24 - vp.M23,
			vp.M34 - vp.M33,
			vp.M44 - vp.M43
		));
	}
}

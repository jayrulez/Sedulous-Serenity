namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;

/// Sort mode for draw calls within a pass.
enum SortMode
{
	None,
	FrontToBack,
	BackToFront,
	ByMaterial,
}

/// A camera/viewport configuration for rendering.
/// Each call to RenderSystem.Render() uses one RenderView.
class RenderView
{
	/// Display name (for debug labels).
	public String Name ~ delete _;
	/// Output width in pixels.
	public uint32 Width;
	/// Output height in pixels.
	public uint32 Height;
	/// Viewport X offset.
	public uint32 ViewportX;
	/// Viewport Y offset.
	public uint32 ViewportY;
	/// View index for multi-view rendering.
	public int32 ViewIndex;

	/// Camera world-space position.
	public Vector3 CameraPosition;
	/// Camera forward direction.
	public Vector3 CameraForward;
	/// Camera up direction.
	public Vector3 CameraUp;

	/// Vertical field of view in radians.
	public float FieldOfView = 1.0472f;
	/// Near clip plane.
	public float NearPlane = 0.1f;
	/// Far clip plane.
	public float FarPlane = 1000.0f;
	/// Scene exposure multiplier (per-camera setting).
	public float Exposure = 1.0f;

	/// View matrix (computed).
	public Matrix ViewMatrix;
	/// Projection matrix (computed).
	public Matrix ProjectionMatrix;
	/// View * Projection (computed).
	public Matrix ViewProjectionMatrix;
	/// Previous frame's VP matrix (for motion vectors / TAA reprojection).
	public Matrix PrevViewProjectionMatrix;

	/// Frustum planes extracted from VP matrix.
	public BoundingFrustum Frustum;

	/// Whether this view renders to the swap chain.
	public bool IsSwapChainTarget = true;

	/// Updates computed matrices from camera parameters.
	public void UpdateMatrices()
	{
		let prevVP = ViewProjectionMatrix;

		ViewMatrix = Matrix.CreateLookAt(CameraPosition, CameraPosition + CameraForward, CameraUp);

		let aspect = (Width > 0 && Height > 0) ? (float)Width / (float)Height : 1.0f;
		ProjectionMatrix = Matrix.CreatePerspectiveFieldOfView(FieldOfView, aspect, NearPlane, FarPlane);

		ViewProjectionMatrix = ViewMatrix * ProjectionMatrix;
		PrevViewProjectionMatrix = prevVP;
		Frustum = BoundingFrustum(ViewProjectionMatrix);
	}

	/// Populates this view from a camera proxy.
	public void FromCamera(ref CameraProxy camera, uint32 width, uint32 height)
	{
		Width = width;
		Height = height;
		CameraPosition = camera.Position;

		let dir = camera.Target - camera.Position;
		let len = dir.Length();
		CameraForward = (len > 0.0001f) ? dir * (1.0f / len) : Vector3(0, 0, -1);
		CameraUp = camera.Up;
		FieldOfView = camera.FieldOfView;
		NearPlane = camera.NearPlane;
		FarPlane = camera.FarPlane;

		UpdateMatrices();
	}
}

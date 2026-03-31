namespace Sedulous.Renderer;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.RenderGraph;

/// Per-view rendering context. Populated by RenderSystem for each
/// RenderView rendered in a frame. Features read this to know
/// the target dimensions, camera, and where to write output.
class ViewContext
{
	/// Render target dimensions in pixels.
	public uint32 RenderWidth;
	public uint32 RenderHeight;

	/// Render graph handle for the output target (e.g. backbuffer).
	public RGTexture RenderTarget;

	/// Camera world-space position.
	public Vector3 CameraPosition;
	/// Camera forward direction (normalized).
	public Vector3 CameraForward;

	/// View matrix.
	public Matrix ViewMatrix;
	/// Projection matrix.
	public Matrix ProjectionMatrix;
	/// View * Projection.
	public Matrix ViewProjectionMatrix;
	/// Previous frame's VP matrix (for motion vectors / TAA).
	public Matrix PrevViewProjectionMatrix;

	/// Sub-pixel jitter offset in NDC space. Set by TAA before uniform upload.
	public Vector2 JitterOffset;
	/// Previous frame's jitter offset.
	public Vector2 PrevJitterOffset;

	/// Near clip plane distance.
	public float NearPlane;
	/// Far clip plane distance.
	public float FarPlane;

	/// Scene exposure multiplier (per-camera setting).
	public float Exposure = 1.0f;

	/// View frustum for culling.
	public BoundingFrustum Frustum;

	/// The scene uniform buffer for this frame slot (for binding in passes).
	public IBuffer SceneUniformBuffer;

	/// The scene uniforms struct (read-only snapshot for this view).
	public SceneUniforms Uniforms;

	/// Populates this context from a RenderView.
	public void Update(RenderView view)
	{
		RenderWidth = view.Width;
		RenderHeight = view.Height;
		CameraPosition = view.CameraPosition;
		CameraForward = view.CameraForward;
		ViewMatrix = view.ViewMatrix;
		ProjectionMatrix = view.ProjectionMatrix;
		ViewProjectionMatrix = view.ViewProjectionMatrix;
		PrevViewProjectionMatrix = view.PrevViewProjectionMatrix;
		NearPlane = view.NearPlane;
		FarPlane = view.FarPlane;
		Exposure = view.Exposure;
		Frustum = view.Frustum;
	}
}

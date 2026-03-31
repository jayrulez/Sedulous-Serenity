namespace Sedulous.Render;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;

/// Per-view rendering context. Populated by RenderSystem for each
/// RenderView rendered in a frame. Features read this to know
/// the target dimensions, camera, frame timing, and where to write output.
/// This is the single source of truth for features — features should not
/// reach back to RenderFrameContext or RenderSystem for per-frame data.
public class ViewContext
{
	/// Render target dimensions in pixels.
	public uint32 Width;
	public uint32 Height;

	/// Camera world-space position.
	public Vector3 CameraPosition;
	/// Camera forward direction (normalized).
	public Vector3 CameraForward;
	/// Camera up direction (normalized).
	public Vector3 CameraUp;

	/// View matrix.
	public Matrix ViewMatrix;
	/// Projection matrix.
	public Matrix ProjectionMatrix;
	/// View * Projection.
	public Matrix ViewProjectionMatrix;
	/// Previous frame's VP matrix (for motion vectors / TAA).
	public Matrix PrevViewProjectionMatrix;

	/// Near clip plane distance.
	public float NearPlane;
	/// Far clip plane distance.
	public float FarPlane;
	/// Field of view in radians.
	public float FieldOfView;
	/// Aspect ratio (width / height).
	public float AspectRatio;

	/// View frustum planes for culling (6 planes).
	public Plane[6] FrustumPlanes;

	/// Post-processing settings for this view.
	public PostProcessSettings PostProcess;

	/// TAA jitter state for this view.
	public TAAJitterState TAAJitter;

	/// View slot index (0 to MaxViews-1, for multi-view).
	public int32 ViewIndex;

	/// Viewport X offset within the swapchain (for split-screen).
	public uint32 ViewportX;
	/// Viewport Y offset within the swapchain (for split-screen).
	public uint32 ViewportY;

	/// Final output texture view (swap chain backbuffer or offscreen target).
	public ITextureView OutputTarget;
	/// Whether this view renders to the swap chain.
	public bool IsSwapChainTarget;

	// --- Frame data (populated by RenderSystem from RenderFrameContext) ---

	/// Current frame index for multi-buffered resources.
	public int32 FrameIndex;

	/// Active view index within the current frame (for bind group indexing).
	public int32 ActiveViewIndex;

	/// Number of views being rendered this frame.
	public int32 ViewCount = 1;

	/// The scene uniform buffer for this frame slot (for binding in passes).
	public IBuffer SceneUniformBuffer;

	/// Scene exposure multiplier.
	public float Exposure = 1.0f;

	/// Frame delta time in seconds.
	public float DeltaTime;

	/// Total elapsed time in seconds.
	public float TotalTime;

	/// Gets the bind group index for multi-buffered, multi-view resources.
	public int32 GetBindGroupIndex()
	{
		return FrameIndex * RenderConfig.MaxViews + ActiveViewIndex;
	}

	/// Populates this context from a RenderView.
	/// Frame-level data (FrameIndex, SceneUniformBuffer, etc.) is populated
	/// separately by RenderSystem after this call.
	public void Update(RenderView view)
	{
		Width = view.Width;
		Height = view.Height;
		CameraPosition = view.CameraPosition;
		CameraForward = view.CameraForward;
		CameraUp = view.CameraUp;
		ViewMatrix = view.ViewMatrix;
		ProjectionMatrix = view.ProjectionMatrix;
		ViewProjectionMatrix = view.ViewProjectionMatrix;
		NearPlane = view.NearPlane;
		FarPlane = view.FarPlane;
		FieldOfView = view.FieldOfView;
		AspectRatio = view.AspectRatio;
		FrustumPlanes = view.FrustumPlanes;
		PostProcess = view.PostProcess;
		TAAJitter = view.TAAJitter;
		ViewIndex = view.ViewIndex;
		ViewportX = view.ViewportX;
		ViewportY = view.ViewportY;
		OutputTarget = view.OutputTarget;
		IsSwapChainTarget = view.IsSwapChainTarget;
	}
}

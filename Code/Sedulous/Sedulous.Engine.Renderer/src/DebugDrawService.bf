namespace Sedulous.Engine.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Engine.Core;
using Sedulous.Renderer;
using Sedulous.Mathematics;

/// Context service for debug drawing (lines, wireframes, solid primitives).
/// Provides a high-level API for drawing debug primitives that can be
/// depth-tested or rendered as overlays.
///
/// Usage:
/// 1. Create and register with Context after RendererService
/// 2. Draw primitives during Update (DrawLine, DrawWireBox, etc.)
/// 3. Service automatically adds render pass to the graph
///
/// The service supports two render modes:
/// - DepthTest: Primitives integrate with scene geometry (default)
/// - Overlay: Primitives always render on top
class DebugDrawService : ContextService, IDisposable
{
	private Context mContext;
	private RendererService mRendererService;
	private DebugRenderer mDebugRenderer ~ delete _;
	private bool mInitialized = false;

	// Camera vectors for text billboarding
	private Vector3 mCameraRight = Vector3.UnitX;
	private Vector3 mCameraUp = Vector3.UnitY;

	/// Gets whether the service has been initialized.
	public bool IsInitialized => mInitialized;

	/// Creates a new debug draw service.
	public this()
	{
	}

	// ==================== High-Level Draw API ====================

	/// Draws a line between two points.
	public void DrawLine(Vector3 start, Vector3 end, Color color, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer != null)
			mDebugRenderer.AddLine(start, end, color, mode);
	}

	/// Draws a ray from origin in a direction.
	public void DrawRay(Vector3 origin, Vector3 direction, Color color, DebugRenderMode mode = .DepthTest)
	{
		DrawLine(origin, origin + direction, color, mode);
	}

	/// Draws a wireframe axis-aligned bounding box.
	public void DrawWireBox(BoundingBox bounds, Color color, DebugRenderMode mode = .DepthTest)
	{
		DrawWireBox(bounds.Min, bounds.Max, color, mode);
	}

	/// Draws a wireframe box from min to max corners.
	public void DrawWireBox(Vector3 min, Vector3 max, Color color, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer == null)
			return;

		// Bottom face
		mDebugRenderer.AddLine(.(min.X, min.Y, min.Z), .(max.X, min.Y, min.Z), color, mode);
		mDebugRenderer.AddLine(.(max.X, min.Y, min.Z), .(max.X, min.Y, max.Z), color, mode);
		mDebugRenderer.AddLine(.(max.X, min.Y, max.Z), .(min.X, min.Y, max.Z), color, mode);
		mDebugRenderer.AddLine(.(min.X, min.Y, max.Z), .(min.X, min.Y, min.Z), color, mode);

		// Top face
		mDebugRenderer.AddLine(.(min.X, max.Y, min.Z), .(max.X, max.Y, min.Z), color, mode);
		mDebugRenderer.AddLine(.(max.X, max.Y, min.Z), .(max.X, max.Y, max.Z), color, mode);
		mDebugRenderer.AddLine(.(max.X, max.Y, max.Z), .(min.X, max.Y, max.Z), color, mode);
		mDebugRenderer.AddLine(.(min.X, max.Y, max.Z), .(min.X, max.Y, min.Z), color, mode);

		// Vertical edges
		mDebugRenderer.AddLine(.(min.X, min.Y, min.Z), .(min.X, max.Y, min.Z), color, mode);
		mDebugRenderer.AddLine(.(max.X, min.Y, min.Z), .(max.X, max.Y, min.Z), color, mode);
		mDebugRenderer.AddLine(.(max.X, min.Y, max.Z), .(max.X, max.Y, max.Z), color, mode);
		mDebugRenderer.AddLine(.(min.X, min.Y, max.Z), .(min.X, max.Y, max.Z), color, mode);
	}

	/// Draws a filled (solid) axis-aligned bounding box.
	public void DrawFilledBox(BoundingBox bounds, Color color, DebugRenderMode mode = .DepthTest)
	{
		DrawFilledBox(bounds.Min, bounds.Max, color, mode);
	}

	/// Draws a filled (solid) box from min to max corners.
	public void DrawFilledBox(Vector3 min, Vector3 max, Color color, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer == null)
			return;

		// Define the 8 corners
		Vector3 v0 = .(min.X, min.Y, min.Z);
		Vector3 v1 = .(max.X, min.Y, min.Z);
		Vector3 v2 = .(max.X, min.Y, max.Z);
		Vector3 v3 = .(min.X, min.Y, max.Z);
		Vector3 v4 = .(min.X, max.Y, min.Z);
		Vector3 v5 = .(max.X, max.Y, min.Z);
		Vector3 v6 = .(max.X, max.Y, max.Z);
		Vector3 v7 = .(min.X, max.Y, max.Z);

		// Bottom face (Y = min)
		mDebugRenderer.AddQuad(v0, v1, v2, v3, color, mode);
		// Top face (Y = max)
		mDebugRenderer.AddQuad(v4, v7, v6, v5, color, mode);
		// Front face (Z = min)
		mDebugRenderer.AddQuad(v0, v4, v5, v1, color, mode);
		// Back face (Z = max)
		mDebugRenderer.AddQuad(v2, v6, v7, v3, color, mode);
		// Left face (X = min)
		mDebugRenderer.AddQuad(v0, v3, v7, v4, color, mode);
		// Right face (X = max)
		mDebugRenderer.AddQuad(v1, v5, v6, v2, color, mode);
	}

	/// Draws a wireframe sphere.
	public void DrawWireSphere(Vector3 center, float radius, Color color, int segments = 16, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer == null)
			return;

		float angleStep = Math.PI_f * 2.0f / segments;

		// XY circle (around Z axis)
		for (int i = 0; i < segments; i++)
		{
			float a0 = i * angleStep;
			float a1 = (i + 1) * angleStep;
			Vector3 p0 = center + .(Math.Cos(a0) * radius, Math.Sin(a0) * radius, 0);
			Vector3 p1 = center + .(Math.Cos(a1) * radius, Math.Sin(a1) * radius, 0);
			mDebugRenderer.AddLine(p0, p1, color, mode);
		}

		// XZ circle (around Y axis)
		for (int i = 0; i < segments; i++)
		{
			float a0 = i * angleStep;
			float a1 = (i + 1) * angleStep;
			Vector3 p0 = center + .(Math.Cos(a0) * radius, 0, Math.Sin(a0) * radius);
			Vector3 p1 = center + .(Math.Cos(a1) * radius, 0, Math.Sin(a1) * radius);
			mDebugRenderer.AddLine(p0, p1, color, mode);
		}

		// YZ circle (around X axis)
		for (int i = 0; i < segments; i++)
		{
			float a0 = i * angleStep;
			float a1 = (i + 1) * angleStep;
			Vector3 p0 = center + .(0, Math.Cos(a0) * radius, Math.Sin(a0) * radius);
			Vector3 p1 = center + .(0, Math.Cos(a1) * radius, Math.Sin(a1) * radius);
			mDebugRenderer.AddLine(p0, p1, color, mode);
		}
	}

	/// Draws a wireframe capsule (cylinder with hemisphere caps).
	public void DrawWireCapsule(Vector3 center, float radius, float height, Color color, int segments = 16, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer == null)
			return;

		float halfHeight = height * 0.5f - radius;
		Vector3 top = center + .(0, halfHeight, 0);
		Vector3 bottom = center - .(0, halfHeight, 0);

		float angleStep = Math.PI_f * 2.0f / segments;

		// Draw vertical lines
		for (int i = 0; i < segments; i++)
		{
			float angle = i * angleStep;
			float x = Math.Cos(angle) * radius;
			float z = Math.Sin(angle) * radius;
			mDebugRenderer.AddLine(top + .(x, 0, z), bottom + .(x, 0, z), color, mode);
		}

		// Draw circles at top and bottom
		for (int i = 0; i < segments; i++)
		{
			float a0 = i * angleStep;
			float a1 = (i + 1) * angleStep;

			Vector3 p0Top = top + .(Math.Cos(a0) * radius, 0, Math.Sin(a0) * radius);
			Vector3 p1Top = top + .(Math.Cos(a1) * radius, 0, Math.Sin(a1) * radius);
			mDebugRenderer.AddLine(p0Top, p1Top, color, mode);

			Vector3 p0Bottom = bottom + .(Math.Cos(a0) * radius, 0, Math.Sin(a0) * radius);
			Vector3 p1Bottom = bottom + .(Math.Cos(a1) * radius, 0, Math.Sin(a1) * radius);
			mDebugRenderer.AddLine(p0Bottom, p1Bottom, color, mode);
		}

		// Draw hemisphere caps (simplified with arcs)
		int halfSegments = segments / 2;
		float halfAngleStep = Math.PI_f / halfSegments;

		// Top hemisphere arcs (XY and ZY planes)
		for (int i = 0; i < halfSegments; i++)
		{
			float a0 = i * halfAngleStep;
			float a1 = (i + 1) * halfAngleStep;

			// XY plane arc at top
			Vector3 p0 = top + .(Math.Sin(a0) * radius, Math.Cos(a0) * radius, 0);
			Vector3 p1 = top + .(Math.Sin(a1) * radius, Math.Cos(a1) * radius, 0);
			mDebugRenderer.AddLine(p0, p1, color, mode);

			// ZY plane arc at top
			p0 = top + .(0, Math.Cos(a0) * radius, Math.Sin(a0) * radius);
			p1 = top + .(0, Math.Cos(a1) * radius, Math.Sin(a1) * radius);
			mDebugRenderer.AddLine(p0, p1, color, mode);

			// XY plane arc at bottom (inverted)
			p0 = bottom + .(Math.Sin(a0) * radius, -Math.Cos(a0) * radius, 0);
			p1 = bottom + .(Math.Sin(a1) * radius, -Math.Cos(a1) * radius, 0);
			mDebugRenderer.AddLine(p0, p1, color, mode);

			// ZY plane arc at bottom (inverted)
			p0 = bottom + .(0, -Math.Cos(a0) * radius, Math.Sin(a0) * radius);
			p1 = bottom + .(0, -Math.Cos(a1) * radius, Math.Sin(a1) * radius);
			mDebugRenderer.AddLine(p0, p1, color, mode);
		}
	}

	/// Draws a wireframe cylinder.
	public void DrawWireCylinder(Vector3 center, float radius, float height, Color color, int segments = 16, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer == null)
			return;

		float halfHeight = height * 0.5f;
		Vector3 top = center + .(0, halfHeight, 0);
		Vector3 bottom = center - .(0, halfHeight, 0);

		float angleStep = Math.PI_f * 2.0f / segments;

		// Draw vertical lines and circles
		for (int i = 0; i < segments; i++)
		{
			float a0 = i * angleStep;
			float a1 = (i + 1) * angleStep;

			// Vertical line
			float x = Math.Cos(a0) * radius;
			float z = Math.Sin(a0) * radius;
			mDebugRenderer.AddLine(top + .(x, 0, z), bottom + .(x, 0, z), color, mode);

			// Top circle segment
			Vector3 p0Top = top + .(Math.Cos(a0) * radius, 0, Math.Sin(a0) * radius);
			Vector3 p1Top = top + .(Math.Cos(a1) * radius, 0, Math.Sin(a1) * radius);
			mDebugRenderer.AddLine(p0Top, p1Top, color, mode);

			// Bottom circle segment
			Vector3 p0Bottom = bottom + .(Math.Cos(a0) * radius, 0, Math.Sin(a0) * radius);
			Vector3 p1Bottom = bottom + .(Math.Cos(a1) * radius, 0, Math.Sin(a1) * radius);
			mDebugRenderer.AddLine(p0Bottom, p1Bottom, color, mode);
		}
	}

	/// Draws a wireframe cone.
	public void DrawWireCone(Vector3 apex, Vector3 direction, float length, float angle, Color color, int segments = 16, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer == null)
			return;

		// Calculate base center and radius
		Vector3 dirNorm = Vector3.Normalize(direction);
		Vector3 baseCenter = apex + dirNorm * length;
		float radius = length * Math.Tan(angle);

		// Find perpendicular vectors for the base circle
		Vector3 up = Math.Abs(dirNorm.Y) < 0.99f ? Vector3.UnitY : Vector3.UnitX;
		Vector3 right = Vector3.Normalize(Vector3.Cross(up, dirNorm));
		Vector3 forward = Vector3.Cross(dirNorm, right);

		float angleStep = Math.PI_f * 2.0f / segments;

		// Draw base circle and lines to apex
		for (int i = 0; i < segments; i++)
		{
			float a0 = i * angleStep;
			float a1 = (i + 1) * angleStep;

			Vector3 p0 = baseCenter + (right * Math.Cos(a0) + forward * Math.Sin(a0)) * radius;
			Vector3 p1 = baseCenter + (right * Math.Cos(a1) + forward * Math.Sin(a1)) * radius;

			// Base circle
			mDebugRenderer.AddLine(p0, p1, color, mode);

			// Lines to apex
			mDebugRenderer.AddLine(apex, p0, color, mode);
		}
	}

	/// Draws a 3D cross/axes at a position.
	public void DrawCross(Vector3 center, float size, Color color, DebugRenderMode mode = .DepthTest)
	{
		float halfSize = size * 0.5f;
		DrawLine(center - .(halfSize, 0, 0), center + .(halfSize, 0, 0), color, mode);
		DrawLine(center - .(0, halfSize, 0), center + .(0, halfSize, 0), color, mode);
		DrawLine(center - .(0, 0, halfSize), center + .(0, 0, halfSize), color, mode);
	}

	/// Draws coordinate axes with different colors (X=red, Y=green, Z=blue).
	public void DrawAxes(Vector3 origin, float length, DebugRenderMode mode = .DepthTest)
	{
		DrawLine(origin, origin + .(length, 0, 0), Color.Red, mode);
		DrawLine(origin, origin + .(0, length, 0), Color.Green, mode);
		DrawLine(origin, origin + .(0, 0, length), Color.Blue, mode);
	}

	/// Draws coordinate axes with a transformation matrix applied.
	public void DrawAxes(Matrix transform, float length, DebugRenderMode mode = .DepthTest)
	{
		Vector3 origin = transform.Translation;
		Vector3 right = Vector3.TransformNormal(Vector3.UnitX, transform);
		Vector3 up = Vector3.TransformNormal(Vector3.UnitY, transform);
		Vector3 forward = Vector3.TransformNormal(Vector3.UnitZ, transform);

		DrawLine(origin, origin + right * length, Color.Red, mode);
		DrawLine(origin, origin + up * length, Color.Green, mode);
		DrawLine(origin, origin + forward * length, Color.Blue, mode);
	}

	/// Draws a wireframe frustum.
	public void DrawWireFrustum(Matrix viewProjection, Color color, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer == null)
			return;

		// Invert view-projection to get world-space corners
		Matrix invVP = Matrix.Invert(viewProjection);

		// NDC corners (-1 to 1 in clip space)
		Vector3[8] ndcCorners = .(
			.(-1, -1, 0), .(1, -1, 0), .(1, 1, 0), .(-1, 1, 0),  // Near plane
			.(-1, -1, 1), .(1, -1, 1), .(1, 1, 1), .(-1, 1, 1)   // Far plane
		);

		// Transform to world space
		Vector3[8] worldCorners = .();
		for (int i = 0; i < 8; i++)
		{
			Vector4 clip = .(ndcCorners[i].X, ndcCorners[i].Y, ndcCorners[i].Z, 1);
			Vector4 world = Vector4.Transform(clip, invVP);
			worldCorners[i] = .(world.X / world.W, world.Y / world.W, world.Z / world.W);
		}

		// Near plane
		mDebugRenderer.AddLine(worldCorners[0], worldCorners[1], color, mode);
		mDebugRenderer.AddLine(worldCorners[1], worldCorners[2], color, mode);
		mDebugRenderer.AddLine(worldCorners[2], worldCorners[3], color, mode);
		mDebugRenderer.AddLine(worldCorners[3], worldCorners[0], color, mode);

		// Far plane
		mDebugRenderer.AddLine(worldCorners[4], worldCorners[5], color, mode);
		mDebugRenderer.AddLine(worldCorners[5], worldCorners[6], color, mode);
		mDebugRenderer.AddLine(worldCorners[6], worldCorners[7], color, mode);
		mDebugRenderer.AddLine(worldCorners[7], worldCorners[4], color, mode);

		// Connecting edges
		mDebugRenderer.AddLine(worldCorners[0], worldCorners[4], color, mode);
		mDebugRenderer.AddLine(worldCorners[1], worldCorners[5], color, mode);
		mDebugRenderer.AddLine(worldCorners[2], worldCorners[6], color, mode);
		mDebugRenderer.AddLine(worldCorners[3], worldCorners[7], color, mode);
	}

	/// Draws a wireframe grid on the XZ plane.
	public void DrawGrid(Vector3 center, float size, int divisions, Color color, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer == null)
			return;

		float halfSize = size * 0.5f;
		float step = size / divisions;

		for (int i = 0; i <= divisions; i++)
		{
			float offset = -halfSize + i * step;

			// X-parallel lines
			Vector3 startX = center + .(-halfSize, 0, offset);
			Vector3 endX = center + .(halfSize, 0, offset);
			mDebugRenderer.AddLine(startX, endX, color, mode);

			// Z-parallel lines
			Vector3 startZ = center + .(offset, 0, -halfSize);
			Vector3 endZ = center + .(offset, 0, halfSize);
			mDebugRenderer.AddLine(startZ, endZ, color, mode);
		}
	}

	/// Draws a filled triangle.
	public void DrawTriangle(Vector3 v0, Vector3 v1, Vector3 v2, Color color, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer != null)
			mDebugRenderer.AddTriangle(v0, v1, v2, color, mode);
	}

	/// Draws a filled quad.
	public void DrawQuad(Vector3 v0, Vector3 v1, Vector3 v2, Vector3 v3, Color color, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer != null)
			mDebugRenderer.AddQuad(v0, v1, v2, v3, color, mode);
	}

	/// Sets the camera vectors used for text billboarding.
	/// Call this once per frame before drawing text, typically from AddDebugPass.
	public void SetCameraVectors(Vector3 right, Vector3 up)
	{
		mCameraRight = right;
		mCameraUp = up;
	}

	/// Sets the camera vectors from a view matrix.
	/// The right and up vectors are extracted from the inverse of the view matrix.
	public void SetCameraFromView(Matrix view)
	{
		// Extract camera orientation from view matrix
		// View matrix rows contain inverted camera axes
		mCameraRight = .(view.M11, view.M21, view.M31);
		mCameraUp = .(view.M12, view.M22, view.M32);
	}

	/// Draws 3D text at the specified world position.
	/// Text is billboard-oriented using the camera vectors set by SetCameraVectors.
	/// @param text The string to render.
	/// @param position World-space position of the text (bottom-left origin).
	/// @param color Text color.
	/// @param scale Size multiplier (1.0 = default size).
	/// @param mode Depth test or overlay mode.
	public void DrawText(StringView text, Vector3 position, Color color, float scale = 1.0f, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer != null)
			mDebugRenderer.AddText(text, position, color, scale, mCameraRight, mCameraUp, mode);
	}

	/// Draws 3D text with explicit billboard orientation.
	/// @param text The string to render.
	/// @param position World-space position of the text (bottom-left origin).
	/// @param color Text color.
	/// @param scale Size multiplier (1.0 = default size).
	/// @param right Camera right vector for billboarding.
	/// @param up Camera up vector for billboarding.
	/// @param mode Depth test or overlay mode.
	public void DrawText(StringView text, Vector3 position, Color color, float scale, Vector3 right, Vector3 up, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer != null)
			mDebugRenderer.AddText(text, position, color, scale, right, up, mode);
	}

	/// Draws 3D text centered at the specified world position.
	/// Text is billboard-oriented using the camera vectors set by SetCameraVectors.
	public void DrawTextCentered(StringView text, Vector3 position, Color color, float scale = 1.0f, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer != null)
			mDebugRenderer.AddTextCentered(text, position, color, scale, mCameraRight, mCameraUp, mode);
	}

	/// Draws 3D text centered with explicit billboard orientation.
	public void DrawTextCentered(StringView text, Vector3 position, Color color, float scale, Vector3 right, Vector3 up, DebugRenderMode mode = .DepthTest)
	{
		if (mDebugRenderer != null)
			mDebugRenderer.AddTextCentered(text, position, color, scale, right, up, mode);
	}

	/// Sets the screen size for 2D text positioning.
	/// Call this once per frame before drawing 2D text.
	public void SetScreenSize(uint32 width, uint32 height)
	{
		if (mDebugRenderer != null)
			mDebugRenderer.SetScreenSize(width, height);
	}

	/// Draws 2D screen-space text.
	/// @param text The string to render.
	/// @param x X position in pixels (from left edge).
	/// @param y Y position in pixels (from top edge).
	/// @param color Text color.
	/// @param scale Size multiplier (1.0 = 8 pixels per character).
	public void DrawText2D(StringView text, float x, float y, Color color, float scale = 1.0f)
	{
		if (mDebugRenderer != null)
			mDebugRenderer.AddText2D(text, x, y, color, scale);
	}

	/// Draws 2D screen-space text aligned to the right edge.
	/// @param text The string to render.
	/// @param rightMargin Pixels from the right edge.
	/// @param y Y position in pixels (from top edge).
	/// @param color Text color.
	/// @param scale Size multiplier.
	public void DrawText2DRight(StringView text, float rightMargin, float y, Color color, float scale = 1.0f)
	{
		if (mDebugRenderer != null)
			mDebugRenderer.AddText2DRight(text, rightMargin, y, color, scale);
	}

	/// Returns true if there are any debug primitives to render.
	public bool HasPrimitives => mDebugRenderer != null && mDebugRenderer.HasPrimitives;

	// ==================== Render Graph Integration ====================

	/// Adds the debug draw pass to the render graph.
	/// Call this after adding scene passes but before ExecuteFrame.
	public void AddDebugPass(RenderGraph graph, ResourceHandle colorTarget, ResourceHandle depthTarget,
		Matrix viewProjection, uint32 width, uint32 height, int32 frameIndex, StringView dependsOn = "Scene3D")
	{
		if (mDebugRenderer == null || !mDebugRenderer.HasPrimitives)
			return;

		// Set view-projection and upload data (don't call BeginFrame - primitives already added)
		mDebugRenderer.SetViewProjection(viewProjection);
		mDebugRenderer.PrepareGPU(frameIndex);

		// Clear CPU-side lists now that data is on GPU (ready for next frame's primitives)
		mDebugRenderer.BeginFrame();

		let renderer = mDebugRenderer;
		let w = width;
		let h = height;
		let frame = frameIndex;

		var passBuilder = graph.AddGraphicsPass("DebugDraw")
			.SetColorAttachment(0, colorTarget, .Load, .Store, default)
			.SetDepthAttachment(depthTarget, .Load, .Store, 1.0f)
			.SetExecute(new [=](ctx) => {
				renderer.Render(ctx.RenderPass, frame, w, h);
			});

		// Add dependency if specified
		if (!dependsOn.IsEmpty)
			passBuilder.AddDependency(dependsOn);
	}

	/// Clears all batched debug primitives.
	/// Called automatically after uploading to GPU, but can be called manually.
	public void Clear()
	{
		if (mDebugRenderer != null)
			mDebugRenderer.BeginFrame();
	}

	// ==================== IContextService Implementation ====================

	/// Called when the service is registered with the context.
	public override void OnRegister(Context context)
	{
		mContext = context;
	}

	/// Called when the service is unregistered from the context.
	public override void OnUnregister()
	{
		mContext = null;
	}

	/// Called during context startup.
	public override void Startup()
	{
		// Look up renderer service
		mRendererService = mContext?.GetService<RendererService>();
		if (mRendererService == null)
		{
			mContext?.Logger?.LogWarning("DebugDrawService: RendererService not found - debug drawing disabled");
			return;
		}

		if (!mRendererService.IsInitialized)
		{
			mContext?.Logger?.LogWarning("DebugDrawService: RendererService not initialized - debug drawing disabled");
			return;
		}

		// Create the debug renderer
		mDebugRenderer = new DebugRenderer(mRendererService.Device, mRendererService.ShaderLibrary);
		if (mDebugRenderer.Initialize(mRendererService.ColorFormat, mRendererService.DepthFormat) case .Err)
		{
			mContext?.Logger?.LogError("DebugDrawService: Failed to initialize DebugRenderer");
			delete mDebugRenderer;
			mDebugRenderer = null;
			return;
		}

		mInitialized = true;
		mContext?.Logger?.LogDebug("DebugDrawService: Initialized");
	}

	/// Called during context shutdown.
	public override void Shutdown()
	{
		mInitialized = false;
	}

	/// Called each frame during context update.
	public override void Update(float deltaTime)
	{
		// Debug drawing happens via direct API calls, nothing to do here
	}

	// ==================== IDisposable Implementation ====================

	public void Dispose()
	{
		Shutdown();
	}
}

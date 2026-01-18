namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Render mode for debug primitives.
public enum DebugRenderMode
{
	/// Depth-tested, integrates with scene geometry.
	DepthTest,
	/// Always rendered on top, ignores depth.
	Overlay
}

/// Debug render feature for drawing lines, triangles, and text.
/// Provides immediate-mode debug drawing API that integrates with the render graph.
public class DebugRenderFeature : RenderFeatureBase
{
	private const int32 MAX_VERTICES = 65536;
	private const int32 MAX_FRAMES = 3;

	// Pipelines
	private IRenderPipeline mLinePipelineDepth ~ delete _;
	private IRenderPipeline mLinePipelineOverlay ~ delete _;
	private IRenderPipeline mTriPipelineDepth ~ delete _;
	private IRenderPipeline mTriPipelineOverlay ~ delete _;
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;

	// Per-frame resources
	private IBuffer[MAX_FRAMES] mVertexBuffers ~ { for (var b in _) delete b; };
	private IBuffer[MAX_FRAMES] mUniformBuffers ~ { for (var b in _) delete b; };
	private IBindGroup[MAX_FRAMES] mBindGroups ~ { for (var b in _) delete b; };

	// Batching state
	private List<DebugVertex> mLineVerticesDepth = new .() ~ delete _;
	private List<DebugVertex> mLineVerticesOverlay = new .() ~ delete _;
	private List<DebugVertex> mTriVerticesDepth = new .() ~ delete _;
	private List<DebugVertex> mTriVerticesOverlay = new .() ~ delete _;

	// Text rendering
	private IRenderPipeline mTextPipelineDepth ~ delete _;
	private IRenderPipeline mTextPipelineOverlay ~ delete _;
	private IBindGroupLayout mTextBindGroupLayout ~ delete _;
	private IPipelineLayout mTextPipelineLayout ~ delete _;
	private IBuffer[MAX_FRAMES] mTextVertexBuffers ~ { for (var b in _) delete b; };
	private IBindGroup[MAX_FRAMES] mTextBindGroups ~ { for (var b in _) delete b; };
	private ITexture mFontTexture ~ delete _;
	private ITextureView mFontTextureView ~ delete _;
	private ISampler mFontSampler ~ delete _;
	private List<DebugTextVertex> mTextVerticesDepth = new .() ~ delete _;
	private List<DebugTextVertex> mTextVerticesOverlay = new .() ~ delete _;

	// 2D screen-space text rendering
	private IRenderPipeline mText2DPipeline ~ delete _;
	private IBindGroupLayout mText2DBindGroupLayout ~ delete _;
	private IPipelineLayout mText2DPipelineLayout ~ delete _;
	private IBuffer[MAX_FRAMES] mText2DVertexBuffers ~ { for (var b in _) delete b; };
	private IBuffer[MAX_FRAMES] mScreenParamBuffers ~ { for (var b in _) delete b; };
	private IBindGroup[MAX_FRAMES] mText2DBindGroups ~ { for (var b in _) delete b; };
	private List<DebugText2DVertex> mText2DVertices = new .() ~ delete _;

	// Saved counts after PrepareGPU
	private int32 mLineDepthCount;
	private int32 mLineOverlayCount;
	private int32 mTriDepthCount;
	private int32 mTriOverlayCount;
	private int32 mTextDepthCount;
	private int32 mTextOverlayCount;
	private int32 mText2DCount;

	// Current frame's view-projection matrix
	private Matrix mViewProjection;
	private uint32 mScreenWidth;
	private uint32 mScreenHeight;
	private float mFlipY;

	// Formats
	private TextureFormat mColorFormat = .RGBA16Float;
	private TextureFormat mDepthFormat = .Depth32Float;

	// Frame index tracking
	private int32 mCurrentFrame = 0;

	/// Feature name.
	public override StringView Name => "DebugRender";

	/// Depends on forward opaque for depth buffer.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
	}

	protected override Result<void> OnInitialize()
	{
		let device = Renderer.Device;

		// Get depth format from render system (color stays RGBA16Float for HDR SceneColor)
		mDepthFormat = Renderer.DepthFormat;

		// Set Y-flip flag based on backend
		mFlipY = device.FlipProjectionRequired ? 1.0f : 0.0f;

		// Create bind group layout (camera uniform buffer)
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor layoutDesc = .(layoutEntries);
		switch (device.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout):
			mBindGroupLayout = layout;
		case .Err:
			return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		switch (device.CreatePipelineLayout(&pipelineLayoutDesc))
		{
		case .Ok(let layout):
			mPipelineLayout = layout;
		case .Err:
			return .Err;
		}

		// Create per-frame resources
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			// Uniform buffer for view-projection matrix
			BufferDescriptor uniformDesc = .((uint64)sizeof(Matrix), .Uniform, .Upload);
			switch (device.CreateBuffer(&uniformDesc))
			{
			case .Ok(let buffer):
				mUniformBuffers[i] = buffer;
			case .Err:
				return .Err;
			}

			// Vertex buffer (large enough for all primitives)
			BufferDescriptor vertexDesc = .((uint64)(MAX_VERTICES * DebugVertex.SizeInBytes), .Vertex, .Upload);
			switch (device.CreateBuffer(&vertexDesc))
			{
			case .Ok(let buffer):
				mVertexBuffers[i] = buffer;
			case .Err:
				return .Err;
			}

			// Bind group
			BindGroupEntry[1] entries = .(
				BindGroupEntry.Buffer(0, mUniformBuffers[i])
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			switch (device.CreateBindGroup(&bindGroupDesc))
			{
			case .Ok(let group):
				mBindGroups[i] = group;
			case .Err:
				return .Err;
			}
		}

		// Initialize text rendering resources
		if (InitializeTextResources() case .Err)
			return .Err;

		// Initialize 2D text resources
		if (InitializeText2DResources() case .Err)
			return .Err;

		return .Ok;
	}

	protected override void OnShutdown()
	{
		// Resources cleaned up by destructors
	}

	/// Begins a new frame, clearing previous batches.
	public void BeginFrame()
	{
		mLineVerticesDepth.Clear();
		mLineVerticesOverlay.Clear();
		mTriVerticesDepth.Clear();
		mTriVerticesOverlay.Clear();
		mTextVerticesDepth.Clear();
		mTextVerticesOverlay.Clear();
		mText2DVertices.Clear();
	}

	/// Sets the view-projection matrix for rendering.
	public void SetViewProjection(Matrix viewProjection)
	{
		mViewProjection = viewProjection;
	}

	/// Sets the screen size for 2D text rendering.
	public void SetScreenSize(uint32 width, uint32 height)
	{
		mScreenWidth = width;
		mScreenHeight = height;
	}

	// ==================== Line/Triangle Drawing ====================

	/// Adds a line to the batch.
	public void AddLine(Vector3 start, Vector3 end, Color color, DebugRenderMode mode = .DepthTest)
	{
		let list = (mode == .DepthTest) ? mLineVerticesDepth : mLineVerticesOverlay;
		list.Add(.(start, color));
		list.Add(.(end, color));
	}

	/// Adds a triangle to the batch.
	public void AddTriangle(Vector3 v0, Vector3 v1, Vector3 v2, Color color, DebugRenderMode mode = .DepthTest)
	{
		let list = (mode == .DepthTest) ? mTriVerticesDepth : mTriVerticesOverlay;
		list.Add(.(v0, color));
		list.Add(.(v1, color));
		list.Add(.(v2, color));
	}

	/// Adds a quad (two triangles) to the batch.
	public void AddQuad(Vector3 v0, Vector3 v1, Vector3 v2, Vector3 v3, Color color, DebugRenderMode mode = .DepthTest)
	{
		AddTriangle(v0, v1, v2, color, mode);
		AddTriangle(v0, v2, v3, color, mode);
	}

	// ==================== Shape Helpers ====================

	/// Draws a wireframe box.
	public void AddBox(BoundingBox bounds, Color color, DebugRenderMode mode = .DepthTest)
	{
		let min = bounds.Min;
		let max = bounds.Max;

		// 8 corners
		Vector3 c000 = .(min.X, min.Y, min.Z);
		Vector3 c001 = .(min.X, min.Y, max.Z);
		Vector3 c010 = .(min.X, max.Y, min.Z);
		Vector3 c011 = .(min.X, max.Y, max.Z);
		Vector3 c100 = .(max.X, min.Y, min.Z);
		Vector3 c101 = .(max.X, min.Y, max.Z);
		Vector3 c110 = .(max.X, max.Y, min.Z);
		Vector3 c111 = .(max.X, max.Y, max.Z);

		// Bottom face
		AddLine(c000, c100, color, mode);
		AddLine(c100, c101, color, mode);
		AddLine(c101, c001, color, mode);
		AddLine(c001, c000, color, mode);

		// Top face
		AddLine(c010, c110, color, mode);
		AddLine(c110, c111, color, mode);
		AddLine(c111, c011, color, mode);
		AddLine(c011, c010, color, mode);

		// Vertical edges
		AddLine(c000, c010, color, mode);
		AddLine(c100, c110, color, mode);
		AddLine(c101, c111, color, mode);
		AddLine(c001, c011, color, mode);
	}

	/// Draws a wireframe box from center and half-extents.
	public void AddBox(Vector3 center, Vector3 halfExtents, Color color, DebugRenderMode mode = .DepthTest)
	{
		AddBox(BoundingBox(center - halfExtents, center + halfExtents), color, mode);
	}

	/// Draws a wireframe sphere approximation.
	public void AddSphere(Vector3 center, float radius, Color color, int segments = 16, DebugRenderMode mode = .DepthTest)
	{
		let step = Math.PI_f * 2.0f / (float)segments;

		// Draw three circles (XY, XZ, YZ planes)
		for (int i = 0; i < segments; i++)
		{
			let angle0 = (float)i * step;
			let angle1 = (float)(i + 1) * step;

			let cos0 = Math.Cos(angle0);
			let sin0 = Math.Sin(angle0);
			let cos1 = Math.Cos(angle1);
			let sin1 = Math.Sin(angle1);

			// XY plane
			AddLine(
				center + .(cos0 * radius, sin0 * radius, 0),
				center + .(cos1 * radius, sin1 * radius, 0),
				color, mode
			);

			// XZ plane
			AddLine(
				center + .(cos0 * radius, 0, sin0 * radius),
				center + .(cos1 * radius, 0, sin1 * radius),
				color, mode
			);

			// YZ plane
			AddLine(
				center + .(0, cos0 * radius, sin0 * radius),
				center + .(0, cos1 * radius, sin1 * radius),
				color, mode
			);
		}
	}

	/// Draws a wireframe sphere from BoundingSphere.
	public void AddSphere(BoundingSphere sphere, Color color, int segments = 16, DebugRenderMode mode = .DepthTest)
	{
		AddSphere(sphere.Center, sphere.Radius, color, segments, mode);
	}

	/// Draws a coordinate axis at the given position.
	public void AddAxes(Vector3 position, float size = 1.0f, DebugRenderMode mode = .DepthTest)
	{
		AddLine(position, position + .(size, 0, 0), Color.Red, mode);
		AddLine(position, position + .(0, size, 0), Color.Green, mode);
		AddLine(position, position + .(0, 0, size), Color.Blue, mode);
	}

	/// Draws coordinate axes with custom rotation.
	public void AddAxes(Vector3 position, Matrix rotation, float size = 1.0f, DebugRenderMode mode = .DepthTest)
	{
		let right = Vector3.TransformNormal(.(1, 0, 0), rotation);
		let up = Vector3.TransformNormal(.(0, 1, 0), rotation);
		let forward = Vector3.TransformNormal(.(0, 0, 1), rotation);

		AddLine(position, position + right * size, Color.Red, mode);
		AddLine(position, position + up * size, Color.Green, mode);
		AddLine(position, position + forward * size, Color.Blue, mode);
	}

	/// Draws a frustum outline.
	public void AddFrustum(Matrix viewProjection, Color color, DebugRenderMode mode = .DepthTest)
	{
		let invVP = Matrix.Invert(viewProjection);

		// NDC corners
		Vector3[8] ndcCorners = .(
			.(-1, -1, 0), .(1, -1, 0), .(1, 1, 0), .(-1, 1, 0), // Near
			.(-1, -1, 1), .(1, -1, 1), .(1, 1, 1), .(-1, 1, 1)  // Far
		);

		// Transform to world space
		Vector3[8] worldCorners = ?;
		for (int i = 0; i < 8; i++)
		{
			let ndc = ndcCorners[i];
			var clip = Vector4(ndc.X, ndc.Y, ndc.Z, 1.0f);
			var world = Vector4.Transform(clip, invVP);
			world /= world.W;
			worldCorners[i] = .(world.X, world.Y, world.Z);
		}

		// Near plane
		AddLine(worldCorners[0], worldCorners[1], color, mode);
		AddLine(worldCorners[1], worldCorners[2], color, mode);
		AddLine(worldCorners[2], worldCorners[3], color, mode);
		AddLine(worldCorners[3], worldCorners[0], color, mode);

		// Far plane
		AddLine(worldCorners[4], worldCorners[5], color, mode);
		AddLine(worldCorners[5], worldCorners[6], color, mode);
		AddLine(worldCorners[6], worldCorners[7], color, mode);
		AddLine(worldCorners[7], worldCorners[4], color, mode);

		// Connecting edges
		AddLine(worldCorners[0], worldCorners[4], color, mode);
		AddLine(worldCorners[1], worldCorners[5], color, mode);
		AddLine(worldCorners[2], worldCorners[6], color, mode);
		AddLine(worldCorners[3], worldCorners[7], color, mode);
	}

	/// Draws a grid on the XZ plane.
	public void AddGrid(Vector3 center, float size, int divisions, Color color, DebugRenderMode mode = .DepthTest)
	{
		let halfSize = size * 0.5f;
		let step = size / (float)divisions;

		for (int i = 0; i <= divisions; i++)
		{
			let t = (float)i * step - halfSize;

			// Lines parallel to X axis
			AddLine(
				center + .(-halfSize, 0, t),
				center + .(halfSize, 0, t),
				color, mode
			);

			// Lines parallel to Z axis
			AddLine(
				center + .(t, 0, -halfSize),
				center + .(t, 0, halfSize),
				color, mode
			);
		}
	}

	/// Draws an arrow from start to end.
	public void AddArrow(Vector3 start, Vector3 end, Color color, float headSize = 0.1f, DebugRenderMode mode = .DepthTest)
	{
		AddLine(start, end, color, mode);

		let dir = Vector3.Normalize(end - start);

		// Find perpendicular vectors
		Vector3 perp1, perp2;
		if (Math.Abs(dir.Y) < 0.99f)
		{
			perp1 = Vector3.Normalize(Vector3.Cross(dir, .(0, 1, 0)));
		}
		else
		{
			perp1 = Vector3.Normalize(Vector3.Cross(dir, .(1, 0, 0)));
		}
		perp2 = Vector3.Cross(dir, perp1);

		let headBase = end - dir * headSize;
		let headRadius = headSize * 0.5f;

		// Arrow head lines
		AddLine(end, headBase + perp1 * headRadius, color, mode);
		AddLine(end, headBase - perp1 * headRadius, color, mode);
		AddLine(end, headBase + perp2 * headRadius, color, mode);
		AddLine(end, headBase - perp2 * headRadius, color, mode);
	}

	/// Draws a ray from origin in a direction.
	public void AddRay(Vector3 origin, Vector3 direction, Color color, DebugRenderMode mode = .DepthTest)
	{
		AddLine(origin, origin + direction, color, mode);
	}

	/// Draws a 3D cross at a position.
	public void AddCross(Vector3 center, float size, Color color, DebugRenderMode mode = .DepthTest)
	{
		float halfSize = size * 0.5f;
		AddLine(center - .(halfSize, 0, 0), center + .(halfSize, 0, 0), color, mode);
		AddLine(center - .(0, halfSize, 0), center + .(0, halfSize, 0), color, mode);
		AddLine(center - .(0, 0, halfSize), center + .(0, 0, halfSize), color, mode);
	}

	/// Draws a filled (solid) box.
	public void AddFilledBox(BoundingBox bounds, Color color, DebugRenderMode mode = .DepthTest)
	{
		let min = bounds.Min;
		let max = bounds.Max;

		Vector3 v0 = .(min.X, min.Y, min.Z);
		Vector3 v1 = .(max.X, min.Y, min.Z);
		Vector3 v2 = .(max.X, min.Y, max.Z);
		Vector3 v3 = .(min.X, min.Y, max.Z);
		Vector3 v4 = .(min.X, max.Y, min.Z);
		Vector3 v5 = .(max.X, max.Y, min.Z);
		Vector3 v6 = .(max.X, max.Y, max.Z);
		Vector3 v7 = .(min.X, max.Y, max.Z);

		// Bottom face (Y = min)
		AddQuad(v0, v1, v2, v3, color, mode);
		// Top face (Y = max)
		AddQuad(v4, v7, v6, v5, color, mode);
		// Front face (Z = min)
		AddQuad(v0, v4, v5, v1, color, mode);
		// Back face (Z = max)
		AddQuad(v2, v6, v7, v3, color, mode);
		// Left face (X = min)
		AddQuad(v0, v3, v7, v4, color, mode);
		// Right face (X = max)
		AddQuad(v1, v5, v6, v2, color, mode);
	}

	/// Draws a wireframe capsule (cylinder with hemisphere caps).
	public void AddCapsule(Vector3 center, float radius, float height, Color color, int segments = 16, DebugRenderMode mode = .DepthTest)
	{
		float halfHeight = height * 0.5f - radius;
		Vector3 top = center + .(0, halfHeight, 0);
		Vector3 bottom = center - .(0, halfHeight, 0);

		float angleStep = Math.PI_f * 2.0f / segments;

		// Draw vertical lines
		for (int i = 0; i < segments; i++)
		{
			float angle = (float)i * angleStep;
			float x = Math.Cos(angle) * radius;
			float z = Math.Sin(angle) * radius;
			AddLine(top + .(x, 0, z), bottom + .(x, 0, z), color, mode);
		}

		// Draw circles at top and bottom
		for (int i = 0; i < segments; i++)
		{
			float a0 = (float)i * angleStep;
			float a1 = (float)(i + 1) * angleStep;

			Vector3 p0Top = top + .(Math.Cos(a0) * radius, 0, Math.Sin(a0) * radius);
			Vector3 p1Top = top + .(Math.Cos(a1) * radius, 0, Math.Sin(a1) * radius);
			AddLine(p0Top, p1Top, color, mode);

			Vector3 p0Bottom = bottom + .(Math.Cos(a0) * radius, 0, Math.Sin(a0) * radius);
			Vector3 p1Bottom = bottom + .(Math.Cos(a1) * radius, 0, Math.Sin(a1) * radius);
			AddLine(p0Bottom, p1Bottom, color, mode);
		}

		// Draw hemisphere caps
		int halfSegments = segments / 2;
		float halfAngleStep = Math.PI_f / halfSegments;

		for (int i = 0; i < halfSegments; i++)
		{
			float a0 = (float)i * halfAngleStep;
			float a1 = (float)(i + 1) * halfAngleStep;

			// XY plane arc at top
			Vector3 p0 = top + .(Math.Sin(a0) * radius, Math.Cos(a0) * radius, 0);
			Vector3 p1 = top + .(Math.Sin(a1) * radius, Math.Cos(a1) * radius, 0);
			AddLine(p0, p1, color, mode);

			// ZY plane arc at top
			p0 = top + .(0, Math.Cos(a0) * radius, Math.Sin(a0) * radius);
			p1 = top + .(0, Math.Cos(a1) * radius, Math.Sin(a1) * radius);
			AddLine(p0, p1, color, mode);

			// XY plane arc at bottom (inverted)
			p0 = bottom + .(Math.Sin(a0) * radius, -Math.Cos(a0) * radius, 0);
			p1 = bottom + .(Math.Sin(a1) * radius, -Math.Cos(a1) * radius, 0);
			AddLine(p0, p1, color, mode);

			// ZY plane arc at bottom (inverted)
			p0 = bottom + .(0, -Math.Cos(a0) * radius, Math.Sin(a0) * radius);
			p1 = bottom + .(0, -Math.Cos(a1) * radius, Math.Sin(a1) * radius);
			AddLine(p0, p1, color, mode);
		}
	}

	/// Draws a wireframe cylinder.
	public void AddCylinder(Vector3 center, float radius, float height, Color color, int segments = 16, DebugRenderMode mode = .DepthTest)
	{
		float halfHeight = height * 0.5f;
		Vector3 top = center + .(0, halfHeight, 0);
		Vector3 bottom = center - .(0, halfHeight, 0);

		float angleStep = Math.PI_f * 2.0f / segments;

		for (int i = 0; i < segments; i++)
		{
			float a0 = (float)i * angleStep;
			float a1 = (float)(i + 1) * angleStep;

			// Vertical line
			float x = Math.Cos(a0) * radius;
			float z = Math.Sin(a0) * radius;
			AddLine(top + .(x, 0, z), bottom + .(x, 0, z), color, mode);

			// Top circle segment
			Vector3 p0Top = top + .(Math.Cos(a0) * radius, 0, Math.Sin(a0) * radius);
			Vector3 p1Top = top + .(Math.Cos(a1) * radius, 0, Math.Sin(a1) * radius);
			AddLine(p0Top, p1Top, color, mode);

			// Bottom circle segment
			Vector3 p0Bottom = bottom + .(Math.Cos(a0) * radius, 0, Math.Sin(a0) * radius);
			Vector3 p1Bottom = bottom + .(Math.Cos(a1) * radius, 0, Math.Sin(a1) * radius);
			AddLine(p0Bottom, p1Bottom, color, mode);
		}
	}

	/// Draws a wireframe cone.
	public void AddCone(Vector3 apex, Vector3 direction, float length, float angle, Color color, int segments = 16, DebugRenderMode mode = .DepthTest)
	{
		Vector3 dirNorm = Vector3.Normalize(direction);
		Vector3 baseCenter = apex + dirNorm * length;
		float radius = length * Math.Tan(angle);

		// Find perpendicular vectors for the base circle
		Vector3 up = Math.Abs(dirNorm.Y) < 0.99f ? Vector3.UnitY : Vector3.UnitX;
		Vector3 right = Vector3.Normalize(Vector3.Cross(up, dirNorm));
		Vector3 forward = Vector3.Cross(dirNorm, right);

		float angleStep = Math.PI_f * 2.0f / segments;

		for (int i = 0; i < segments; i++)
		{
			float a0 = (float)i * angleStep;
			float a1 = (float)(i + 1) * angleStep;

			Vector3 p0 = baseCenter + (right * Math.Cos(a0) + forward * Math.Sin(a0)) * radius;
			Vector3 p1 = baseCenter + (right * Math.Cos(a1) + forward * Math.Sin(a1)) * radius;

			// Base circle
			AddLine(p0, p1, color, mode);

			// Lines to apex
			AddLine(apex, p0, color, mode);
		}
	}

	/// Draws a circle on the specified plane.
	public void AddCircle(Vector3 center, float radius, Vector3 normal, Color color, int segments = 32, DebugRenderMode mode = .DepthTest)
	{
		Vector3 up = Math.Abs(normal.Y) < 0.99f ? Vector3.UnitY : Vector3.UnitX;
		Vector3 right = Vector3.Normalize(Vector3.Cross(up, normal));
		Vector3 forward = Vector3.Cross(normal, right);

		float angleStep = Math.PI_f * 2.0f / segments;

		for (int i = 0; i < segments; i++)
		{
			float a0 = (float)i * angleStep;
			float a1 = (float)(i + 1) * angleStep;

			Vector3 p0 = center + (right * Math.Cos(a0) + forward * Math.Sin(a0)) * radius;
			Vector3 p1 = center + (right * Math.Cos(a1) + forward * Math.Sin(a1)) * radius;
			AddLine(p0, p1, color, mode);
		}
	}

	// ==================== 3D Text ====================

	/// Adds 3D text to the batch.
	/// The text is rendered as billboards facing the camera.
	public void AddText(StringView text, Vector3 position, Color color, float scale, Vector3 right, Vector3 up, DebugRenderMode mode = .DepthTest)
	{
		if (mFontTexture == null)
			return;

		let list = (mode == .DepthTest) ? mTextVerticesDepth : mTextVerticesOverlay;

		let charWorldWidth = scale * 0.1f;
		let charWorldHeight = scale * 0.1f;

		var cursorX = 0.0f;

		for (let c in text.DecodedChars)
		{
			float u0, v0, u1, v1;
			if (!DebugFont.GetCharUV(c, out u0, out v0, out u1, out v1))
			{
				cursorX += charWorldWidth;
				continue;
			}

			let xOffset = right * cursorX;
			let p0 = position + xOffset;
			let p1 = position + xOffset + right * charWorldWidth;
			let p2 = position + xOffset + right * charWorldWidth + up * charWorldHeight;
			let p3 = position + xOffset + up * charWorldHeight;

			// Triangle 1: p0, p1, p2
			list.Add(.(p0, .(u0, v1), color));
			list.Add(.(p1, .(u1, v1), color));
			list.Add(.(p2, .(u1, v0), color));

			// Triangle 2: p0, p2, p3
			list.Add(.(p0, .(u0, v1), color));
			list.Add(.(p2, .(u1, v0), color));
			list.Add(.(p3, .(u0, v0), color));

			cursorX += charWorldWidth;
		}
	}

	/// Adds 3D text centered at the given position.
	public void AddTextCentered(StringView text, Vector3 position, Color color, float scale, Vector3 right, Vector3 up, DebugRenderMode mode = .DepthTest)
	{
		let charWorldWidth = scale * 0.1f;
		let charWorldHeight = scale * 0.1f;
		let textWidth = text.Length * charWorldWidth;
		let textHeight = charWorldHeight;

		let centeredPos = position - right * (textWidth * 0.5f) - up * (textHeight * 0.5f);
		AddText(text, centeredPos, color, scale, right, up, mode);
	}

	// ==================== 2D Text ====================

	/// Adds 2D screen-space text.
	public void AddText2D(StringView text, float x, float y, Color color, float scale = 1.0f)
	{
		if (mFontTexture == null)
			return;

		let charPixelWidth = (float)DebugFont.CharWidth * scale;
		let charPixelHeight = (float)DebugFont.CharHeight * scale;

		var cursorX = x;

		for (let c in text.DecodedChars)
		{
			float u0, v0, u1, v1;
			if (!DebugFont.GetCharUV(c, out u0, out v0, out u1, out v1))
			{
				cursorX += charPixelWidth;
				continue;
			}

			let left = cursorX;
			let right = cursorX + charPixelWidth;
			let top = y;
			let bottom = y + charPixelHeight;

			// Triangle 1
			mText2DVertices.Add(.(left, top, u0, v0, color));
			mText2DVertices.Add(.(left, bottom, u0, v1, color));
			mText2DVertices.Add(.(right, bottom, u1, v1, color));

			// Triangle 2
			mText2DVertices.Add(.(left, top, u0, v0, color));
			mText2DVertices.Add(.(right, bottom, u1, v1, color));
			mText2DVertices.Add(.(right, top, u1, v0, color));

			cursorX += charPixelWidth;
		}
	}

	/// Adds 2D screen-space text aligned to the right edge.
	public void AddText2DRight(StringView text, float rightMargin, float y, Color color, float scale = 1.0f)
	{
		let charPixelWidth = (float)DebugFont.CharWidth * scale;
		let textWidth = text.Length * charPixelWidth;
		let x = (float)mScreenWidth - rightMargin - textWidth;
		AddText2D(text, x, y, color, scale);
	}

	/// Returns true if there are any primitives to render.
	public bool HasPrimitives =>
		mLineVerticesDepth.Count > 0 || mLineVerticesOverlay.Count > 0 ||
		mTriVerticesDepth.Count > 0 || mTriVerticesOverlay.Count > 0 ||
		mTextVerticesDepth.Count > 0 || mTextVerticesOverlay.Count > 0 ||
		mText2DVertices.Count > 0;

	// ==================== Render Graph Integration ====================

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		// Get scene color from forward pass
		let colorHandle = graph.GetResource("SceneColor");
		if (!colorHandle.IsValid)
			return;

		// Get depth buffer
		let depthHandle = graph.GetResource("SceneDepth");
		if (!depthHandle.IsValid)
			return;

		// Set up for this frame
		SetViewProjection(view.ViewProjectionMatrix);
		SetScreenSize(view.Width, view.Height);

		// Upload data to GPU
		PrepareGPU();

		// Skip if nothing to render
		if (!HasPrimitives)
			return;

		// Store frame index for render callback
		int32 frameIndex = mCurrentFrame;

		// Add debug render pass
		graph.AddGraphicsPass("DebugRender")
			.WriteColor(colorHandle, .Load, .Store, .(0, 0, 0, 1))
			.ReadDepth(depthHandle)
			.NeverCull()
			.SetExecuteCallback(new (encoder) => {
				ExecuteDebugPass(encoder, view, frameIndex);
			});

		// Advance frame
		mCurrentFrame = (mCurrentFrame + 1) % MAX_FRAMES;
	}

	private void PrepareGPU()
	{
		let device = Renderer.Device;
		int32 frameIndex = mCurrentFrame;

		// Save counts
		mLineDepthCount = (int32)mLineVerticesDepth.Count;
		mLineOverlayCount = (int32)mLineVerticesOverlay.Count;
		mTriDepthCount = (int32)mTriVerticesDepth.Count;
		mTriOverlayCount = (int32)mTriVerticesOverlay.Count;
		mTextDepthCount = (int32)mTextVerticesDepth.Count;
		mTextOverlayCount = (int32)mTextVerticesOverlay.Count;
		mText2DCount = (int32)mText2DVertices.Count;

		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		if (device?.Queue == null || mUniformBuffers[frameIndex] == null)
			return;

		// Upload view-projection matrix using Map/Unmap
		if (let ptr = mUniformBuffers[frameIndex].Map())
		{
			var vp = mViewProjection;
			let uniformBuffer = mUniformBuffers[frameIndex];
			// Bounds check against actual buffer size
			Runtime.Assert(sizeof(Matrix) <= (.)uniformBuffer.Size, scope $"Matrix copy size ({sizeof(Matrix)}) exceeds uniform buffer size ({uniformBuffer.Size})");
			Internal.MemCpy(ptr, &vp, sizeof(Matrix));
			uniformBuffer.Unmap();
		}

		// Calculate total vertices needed
		int totalVertices = mLineDepthCount + mLineOverlayCount + mTriDepthCount + mTriOverlayCount;

		// Upload line/triangle vertices using Map/Unmap
		if (totalVertices > 0 && mVertexBuffers[frameIndex] != null)
		{
			if (let ptr = mVertexBuffers[frameIndex].Map())
			{
				List<DebugVertex> allVertices = scope .();
				allVertices.AddRange(mLineVerticesDepth);
				allVertices.AddRange(mLineVerticesOverlay);
				allVertices.AddRange(mTriVerticesDepth);
				allVertices.AddRange(mTriVerticesOverlay);

				let dataSize = allVertices.Count * DebugVertex.SizeInBytes;
				let vertexBuffer = mVertexBuffers[frameIndex];
				// Bounds check against actual buffer size
				Runtime.Assert(dataSize <= (.)vertexBuffer.Size, scope $"Debug vertex data size ({dataSize}) exceeds buffer size ({vertexBuffer.Size})");
				Internal.MemCpy(ptr, allVertices.Ptr, dataSize);
				vertexBuffer.Unmap();
			}
		}

		// Upload text vertices using Map/Unmap
		int totalTextVertices = mTextDepthCount + mTextOverlayCount;
		if (totalTextVertices > 0 && mTextVertexBuffers[frameIndex] != null)
		{
			if (let ptr = mTextVertexBuffers[frameIndex].Map())
			{
				List<DebugTextVertex> allTextVertices = scope .();
				allTextVertices.AddRange(mTextVerticesDepth);
				allTextVertices.AddRange(mTextVerticesOverlay);

				let dataSize = allTextVertices.Count * DebugTextVertex.SizeInBytes;
				let textBuffer = mTextVertexBuffers[frameIndex];
				// Bounds check against actual buffer size
				Runtime.Assert(dataSize <= (.)textBuffer.Size, scope $"Debug text vertex data size ({dataSize}) exceeds buffer size ({textBuffer.Size})");
				Internal.MemCpy(ptr, allTextVertices.Ptr, dataSize);
				textBuffer.Unmap();
			}
		}

		// Upload 2D text vertices and screen params using Map/Unmap
		if (mText2DCount > 0 && mText2DVertexBuffers[frameIndex] != null && mScreenParamBuffers[frameIndex] != null)
		{
			if (let ptr = mScreenParamBuffers[frameIndex].Map())
			{
				float[4] screenParams = .((float)mScreenWidth, (float)mScreenHeight, mFlipY, 0);
				let screenBuffer = mScreenParamBuffers[frameIndex];
				// Bounds check against actual buffer size
				Runtime.Assert(sizeof(float[4]) <= (.)screenBuffer.Size, scope $"Screen params copy size ({sizeof(float[4])}) exceeds buffer size ({screenBuffer.Size})");
				Internal.MemCpy(ptr, &screenParams, sizeof(float[4]));
				screenBuffer.Unmap();
			}

			if (let ptr = mText2DVertexBuffers[frameIndex].Map())
			{
				let dataSize = mText2DVertices.Count * DebugText2DVertex.SizeInBytes;
				let text2DBuffer = mText2DVertexBuffers[frameIndex];
				// Bounds check against actual buffer size
				Runtime.Assert(dataSize <= (.)text2DBuffer.Size, scope $"Debug 2D text vertex data size ({dataSize}) exceeds buffer size ({text2DBuffer.Size})");
				Internal.MemCpy(ptr, mText2DVertices.Ptr, dataSize);
				text2DBuffer.Unmap();
			}
		}
	}

	private void ExecuteDebugPass(IRenderPassEncoder encoder, RenderView view, int32 frameIndex)
	{
		// Ensure pipelines are created
		if (mLinePipelineDepth == null)
			CreatePipelines();

		if (mLinePipelineDepth == null)
			return;

		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		var bindGroup = mBindGroups[frameIndex];
		var vertexBuffer = mVertexBuffers[frameIndex];

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		uint32 vertexOffset = 0;

		// Render depth-tested lines
		if (mLineDepthCount > 0 && mLinePipelineDepth != null)
		{
			encoder.SetPipeline(mLinePipelineDepth);
			encoder.SetBindGroup(0, bindGroup, default);
			encoder.SetVertexBuffer(0, vertexBuffer, 0);
			encoder.Draw((uint32)mLineDepthCount, 1, vertexOffset, 0);
			vertexOffset += (uint32)mLineDepthCount;
		}

		// Render overlay lines
		if (mLineOverlayCount > 0 && mLinePipelineOverlay != null)
		{
			encoder.SetPipeline(mLinePipelineOverlay);
			encoder.SetBindGroup(0, bindGroup, default);
			encoder.SetVertexBuffer(0, vertexBuffer, 0);
			encoder.Draw((uint32)mLineOverlayCount, 1, vertexOffset, 0);
			vertexOffset += (uint32)mLineOverlayCount;
		}

		// Render depth-tested triangles
		if (mTriDepthCount > 0 && mTriPipelineDepth != null)
		{
			encoder.SetPipeline(mTriPipelineDepth);
			encoder.SetBindGroup(0, bindGroup, default);
			encoder.SetVertexBuffer(0, vertexBuffer, 0);
			encoder.Draw((uint32)mTriDepthCount, 1, vertexOffset, 0);
			vertexOffset += (uint32)mTriDepthCount;
		}

		// Render overlay triangles
		if (mTriOverlayCount > 0 && mTriPipelineOverlay != null)
		{
			encoder.SetPipeline(mTriPipelineOverlay);
			encoder.SetBindGroup(0, bindGroup, default);
			encoder.SetVertexBuffer(0, vertexBuffer, 0);
			encoder.Draw((uint32)mTriOverlayCount, 1, vertexOffset, 0);
		}

		// Render 3D text
		RenderText(encoder, frameIndex);

		// Render 2D text
		RenderText2D(encoder, frameIndex);
	}

	private void RenderText(IRenderPassEncoder encoder, int32 frameIndex)
	{
		if (mTextPipelineDepth == null)
			CreateTextPipelines();

		if (mTextPipelineDepth == null || mTextBindGroups[frameIndex] == null)
			return;

		var textBindGroup = mTextBindGroups[frameIndex];
		var textVertexBuffer = mTextVertexBuffers[frameIndex];

		uint32 textVertexOffset = 0;

		if (mTextDepthCount > 0)
		{
			encoder.SetPipeline(mTextPipelineDepth);
			encoder.SetBindGroup(0, textBindGroup, default);
			encoder.SetVertexBuffer(0, textVertexBuffer, 0);
			encoder.Draw((uint32)mTextDepthCount, 1, textVertexOffset, 0);
			textVertexOffset += (uint32)mTextDepthCount;
		}

		if (mTextOverlayCount > 0 && mTextPipelineOverlay != null)
		{
			encoder.SetPipeline(mTextPipelineOverlay);
			encoder.SetBindGroup(0, textBindGroup, default);
			encoder.SetVertexBuffer(0, textVertexBuffer, 0);
			encoder.Draw((uint32)mTextOverlayCount, 1, textVertexOffset, 0);
		}
	}

	private void RenderText2D(IRenderPassEncoder encoder, int32 frameIndex)
	{
		if (mText2DCount == 0)
			return;

		if (mText2DPipeline == null)
			CreateText2DPipeline();

		if (mText2DPipeline == null || mText2DBindGroups[frameIndex] == null || mText2DVertexBuffers[frameIndex] == null)
			return;

		encoder.SetPipeline(mText2DPipeline);
		encoder.SetBindGroup(0, mText2DBindGroups[frameIndex], default);
		encoder.SetVertexBuffer(0, mText2DVertexBuffers[frameIndex], 0);
		encoder.Draw((uint32)mText2DCount, 1, 0, 0);
	}

	// ==================== Pipeline Creation ====================

	private void CreatePipelines()
	{
		let shaderSystem = Renderer.ShaderSystem;
		if (shaderSystem == null)
			return;

		let shaderPair = shaderSystem.GetShaderPair("debug", .None);
		if (shaderPair case .Err)
		{
			Console.WriteLine("[DebugRenderFeature] Failed to load debug shaders");
			return;
		}

		let vertShader = shaderPair.Value.vert.Module;
		let fragShader = shaderPair.Value.frag.Module;

		// Vertex layout
		VertexAttribute[2] attrs = .(
			.(VertexFormat.Float3, 0, 0),           // Position
			.(VertexFormat.UByte4Normalized, 12, 1) // Color
		);
		VertexBufferLayout[1] vertexLayouts = .(
			.((uint32)DebugVertex.SizeInBytes, attrs, .Vertex)
		);

		// Color target with alpha blending
		ColorTargetState[1] colorTargets = .(
			.()
			{
				Format = mColorFormat,
				Blend = .()
				{
					Color = .(.Add, .SrcAlpha, .OneMinusSrcAlpha),
					Alpha = .(.Add, .One, .OneMinusSrcAlpha)
				},
				WriteMask = .All
			}
		);

		let device = Renderer.Device;

		// Depth-tested line pipeline
		{
			DepthStencilState depthState = .()
			{
				Format = mDepthFormat,
				DepthTestEnabled = true,
				DepthWriteEnabled = false,
				DepthCompare = .LessEqual
			};

			RenderPipelineDescriptor desc = .()
			{
				Layout = mPipelineLayout,
				Vertex = .() { Shader = .(vertShader, "main"), Buffers = vertexLayouts },
				Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .LineList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = depthState,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			if (device.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mLinePipelineDepth = pipeline;
		}

		// Overlay line pipeline
		{
			DepthStencilState depthState = .()
			{
				Format = mDepthFormat,
				DepthTestEnabled = false,
				DepthWriteEnabled = false,
				DepthCompare = .Always
			};

			RenderPipelineDescriptor desc = .()
			{
				Layout = mPipelineLayout,
				Vertex = .() { Shader = .(vertShader, "main"), Buffers = vertexLayouts },
				Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .LineList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = depthState,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			if (device.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mLinePipelineOverlay = pipeline;
		}

		// Depth-tested triangle pipeline
		{
			DepthStencilState depthState = .()
			{
				Format = mDepthFormat,
				DepthTestEnabled = true,
				DepthWriteEnabled = false,
				DepthCompare = .LessEqual
			};

			RenderPipelineDescriptor desc = .()
			{
				Layout = mPipelineLayout,
				Vertex = .() { Shader = .(vertShader, "main"), Buffers = vertexLayouts },
				Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = depthState,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			if (device.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mTriPipelineDepth = pipeline;
		}

		// Overlay triangle pipeline
		{
			DepthStencilState depthState = .()
			{
				Format = mDepthFormat,
				DepthTestEnabled = false,
				DepthWriteEnabled = false,
				DepthCompare = .Always
			};

			RenderPipelineDescriptor desc = .()
			{
				Layout = mPipelineLayout,
				Vertex = .() { Shader = .(vertShader, "main"), Buffers = vertexLayouts },
				Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = depthState,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			if (device.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mTriPipelineOverlay = pipeline;
		}
	}

	// ==================== Text Resources ====================

	private Result<void> InitializeTextResources()
	{
		let device = Renderer.Device;

		// Create font texture
		uint8[] fontData = DebugFont.GenerateTextureData();
		defer delete fontData;

		TextureDescriptor texDesc = TextureDescriptor.Texture2D(
			(uint32)DebugFont.TextureWidth,
			(uint32)DebugFont.TextureHeight,
			.R8Unorm,
			.Sampled | .CopyDst
		);
		texDesc.Label = "DebugFont";

		switch (device.CreateTexture(&texDesc))
		{
		case .Ok(let tex):
			mFontTexture = tex;
		case .Err:
			return .Err;
		}

		// Upload font data
		TextureDataLayout dataLayout = .()
		{
			Offset = 0,
			BytesPerRow = (uint32)DebugFont.TextureWidth,
			RowsPerImage = (uint32)DebugFont.TextureHeight
		};
		Extent3D extent = .((uint32)DebugFont.TextureWidth, (uint32)DebugFont.TextureHeight, 1);
		Span<uint8> dataSpan = .(fontData.Ptr, fontData.Count);
		device.Queue.WriteTexture(mFontTexture, dataSpan, &dataLayout, &extent);

		// Create texture view
		TextureViewDescriptor viewDesc = .()
		{
			Format = .R8Unorm,
			Dimension = .Texture2D,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1,
			Label = "DebugFontView"
		};
		switch (device.CreateTextureView(mFontTexture, &viewDesc))
		{
		case .Ok(let view):
			mFontTextureView = view;
		case .Err:
			return .Err;
		}

		// Create sampler
		SamplerDescriptor samplerDesc = .()
		{
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge,
			MagFilter = .Linear,
			MinFilter = .Linear
		};
		switch (device.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler):
			mFontSampler = sampler;
		case .Err:
			return .Err;
		}

		// Create text bind group layout
		BindGroupLayoutEntry[3] textLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor textLayoutDesc = .(textLayoutEntries);
		switch (device.CreateBindGroupLayout(&textLayoutDesc))
		{
		case .Ok(let layout):
			mTextBindGroupLayout = layout;
		case .Err:
			return .Err;
		}

		// Create text pipeline layout
		IBindGroupLayout[1] textLayouts = .(mTextBindGroupLayout);
		PipelineLayoutDescriptor textPipelineLayoutDesc = .(textLayouts);
		switch (device.CreatePipelineLayout(&textPipelineLayoutDesc))
		{
		case .Ok(let layout):
			mTextPipelineLayout = layout;
		case .Err:
			return .Err;
		}

		// Create per-frame text resources
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			BufferDescriptor textVertexDesc = .((uint64)(MAX_VERTICES * DebugTextVertex.SizeInBytes), .Vertex, .Upload);
			switch (device.CreateBuffer(&textVertexDesc))
			{
			case .Ok(let buffer):
				mTextVertexBuffers[i] = buffer;
			case .Err:
				return .Err;
			}

			BindGroupEntry[3] textEntries = .(
				BindGroupEntry.Buffer(0, mUniformBuffers[i]),
				BindGroupEntry.Texture(0, mFontTextureView),
				BindGroupEntry.Sampler(0, mFontSampler)
			);
			BindGroupDescriptor textBindGroupDesc = .(mTextBindGroupLayout, textEntries);
			switch (device.CreateBindGroup(&textBindGroupDesc))
			{
			case .Ok(let group):
				mTextBindGroups[i] = group;
			case .Err:
				return .Err;
			}
		}

		return .Ok;
	}

	private void CreateTextPipelines()
	{
		let shaderSystem = Renderer.ShaderSystem;
		if (shaderSystem == null || mTextPipelineLayout == null)
			return;

		let shaderPair = shaderSystem.GetShaderPair("debug_text", .None);
		if (shaderPair case .Err)
		{
			Console.WriteLine("[DebugRenderFeature] Failed to load debug_text shaders");
			return;
		}

		let vertShader = shaderPair.Value.vert.Module;
		let fragShader = shaderPair.Value.frag.Module;

		// Text vertex layout
		VertexAttribute[3] textAttrs = .(
			.(VertexFormat.Float3, 0, 0),
			.(VertexFormat.Float2, 12, 1),
			.(VertexFormat.UByte4Normalized, 20, 2)
		);
		VertexBufferLayout[1] textVertexLayouts = .(
			.((uint32)DebugTextVertex.SizeInBytes, textAttrs, .Vertex)
		);

		ColorTargetState[1] colorTargets = .(
			.()
			{
				Format = mColorFormat,
				Blend = .()
				{
					Color = .(.Add, .SrcAlpha, .OneMinusSrcAlpha),
					Alpha = .(.Add, .One, .OneMinusSrcAlpha)
				},
				WriteMask = .All
			}
		);

		let device = Renderer.Device;

		// Depth-tested text pipeline
		{
			DepthStencilState depthState = .()
			{
				Format = mDepthFormat,
				DepthTestEnabled = true,
				DepthWriteEnabled = false,
				DepthCompare = .LessEqual
			};

			RenderPipelineDescriptor desc = .()
			{
				Layout = mTextPipelineLayout,
				Vertex = .() { Shader = .(vertShader, "main"), Buffers = textVertexLayouts },
				Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = depthState,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			if (device.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mTextPipelineDepth = pipeline;
		}

		// Overlay text pipeline
		{
			DepthStencilState depthState = .()
			{
				Format = mDepthFormat,
				DepthTestEnabled = false,
				DepthWriteEnabled = false,
				DepthCompare = .Always
			};

			RenderPipelineDescriptor desc = .()
			{
				Layout = mTextPipelineLayout,
				Vertex = .() { Shader = .(vertShader, "main"), Buffers = textVertexLayouts },
				Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
				Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
				DepthStencil = depthState,
				Multisample = .() { Count = 1, Mask = uint32.MaxValue }
			};

			if (device.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mTextPipelineOverlay = pipeline;
		}
	}

	// ==================== 2D Text Resources ====================

	private Result<void> InitializeText2DResources()
	{
		let device = Renderer.Device;

		// Create 2D text bind group layout
		BindGroupLayoutEntry[3] text2DLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor text2DLayoutDesc = .(text2DLayoutEntries);
		switch (device.CreateBindGroupLayout(&text2DLayoutDesc))
		{
		case .Ok(let layout):
			mText2DBindGroupLayout = layout;
		case .Err:
			return .Err;
		}

		// Create 2D text pipeline layout
		IBindGroupLayout[1] text2DLayouts = .(mText2DBindGroupLayout);
		PipelineLayoutDescriptor text2DPipelineLayoutDesc = .(text2DLayouts);
		switch (device.CreatePipelineLayout(&text2DPipelineLayoutDesc))
		{
		case .Ok(let layout):
			mText2DPipelineLayout = layout;
		case .Err:
			return .Err;
		}

		// Create per-frame 2D text resources
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			BufferDescriptor screenParamDesc = .((uint64)sizeof(float[4]), .Uniform, .Upload);
			switch (device.CreateBuffer(&screenParamDesc))
			{
			case .Ok(let buffer):
				mScreenParamBuffers[i] = buffer;
			case .Err:
				return .Err;
			}

			BufferDescriptor text2DVertexDesc = .((uint64)(MAX_VERTICES * DebugText2DVertex.SizeInBytes), .Vertex, .Upload);
			switch (device.CreateBuffer(&text2DVertexDesc))
			{
			case .Ok(let buffer):
				mText2DVertexBuffers[i] = buffer;
			case .Err:
				return .Err;
			}

			BindGroupEntry[3] text2DEntries = .(
				BindGroupEntry.Buffer(0, mScreenParamBuffers[i]),
				BindGroupEntry.Texture(0, mFontTextureView),
				BindGroupEntry.Sampler(0, mFontSampler)
			);
			BindGroupDescriptor text2DBindGroupDesc = .(mText2DBindGroupLayout, text2DEntries);
			switch (device.CreateBindGroup(&text2DBindGroupDesc))
			{
			case .Ok(let group):
				mText2DBindGroups[i] = group;
			case .Err:
				return .Err;
			}
		}

		return .Ok;
	}

	private void CreateText2DPipeline()
	{
		let shaderSystem = Renderer.ShaderSystem;
		if (shaderSystem == null || mText2DPipelineLayout == null)
			return;

		let vertShader = shaderSystem.GetShader("debug_text_2d", .Vertex, .None);
		let fragShader = shaderSystem.GetShader("debug_text", .Fragment, .None);

		if (vertShader case .Err)
		{
			Console.WriteLine("[DebugRenderFeature] Failed to load debug_text_2d vertex shader");
			return;
		}
		if (fragShader case .Err)
		{
			Console.WriteLine("[DebugRenderFeature] Failed to load debug_text fragment shader");
			return;
		}

		let vertModule = vertShader.Value.Module;
		let fragModule = fragShader.Value.Module;

		VertexAttribute[3] text2DAttrs = .(
			.(VertexFormat.Float2, 0, 0),
			.(VertexFormat.Float2, 8, 1),
			.(VertexFormat.UByte4Normalized, 16, 2)
		);
		VertexBufferLayout[1] text2DVertexLayouts = .(
			.((uint32)DebugText2DVertex.SizeInBytes, text2DAttrs, .Vertex)
		);

		ColorTargetState[1] colorTargets = .(
			.()
			{
				Format = mColorFormat,
				Blend = .()
				{
					Color = .(.Add, .SrcAlpha, .OneMinusSrcAlpha),
					Alpha = .(.Add, .One, .OneMinusSrcAlpha)
				},
				WriteMask = .All
			}
		);

		DepthStencilState depthState = .()
		{
			Format = mDepthFormat,
			DepthTestEnabled = false,
			DepthWriteEnabled = false,
			DepthCompare = .Always
		};

		RenderPipelineDescriptor desc = .()
		{
			Layout = mText2DPipelineLayout,
			Vertex = .() { Shader = .(vertModule, "main"), Buffers = text2DVertexLayouts },
			Fragment = .() { Shader = .(fragModule, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = depthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Renderer.Device.CreateRenderPipeline(&desc) case .Ok(let pipeline))
			mText2DPipeline = pipeline;
	}
}

namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Mathematics;

/// Render mode for debug primitives.
enum DebugRenderMode
{
	/// Depth-tested, integrates with scene geometry.
	DepthTest,
	/// Always rendered on top, ignores depth.
	Overlay
}

/// Low-level debug renderer for lines and triangles.
/// Batches primitives and renders them efficiently.
class DebugRenderer
{
	private const int32 MAX_VERTICES = 65536;
	private const int32 MAX_FRAMES = 3;

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;

	// Pipelines
	private IRenderPipeline mLinePipelineDepth;
	private IRenderPipeline mLinePipelineOverlay;
	private IRenderPipeline mTriPipelineDepth;
	private IRenderPipeline mTriPipelineOverlay;
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;

	// Per-frame resources
	private IBuffer[MAX_FRAMES] mVertexBuffers;
	private IBuffer[MAX_FRAMES] mUniformBuffers;
	private IBindGroup[MAX_FRAMES] mBindGroups;

	// Batching state
	private List<DebugVertex> mLineVerticesDepth = new .() ~ delete _;
	private List<DebugVertex> mLineVerticesOverlay = new .() ~ delete _;
	private List<DebugVertex> mTriVerticesDepth = new .() ~ delete _;
	private List<DebugVertex> mTriVerticesOverlay = new .() ~ delete _;

	// Text rendering
	private IRenderPipeline mTextPipelineDepth;
	private IRenderPipeline mTextPipelineOverlay;
	private IBindGroupLayout mTextBindGroupLayout;
	private IPipelineLayout mTextPipelineLayout;
	private IBuffer[MAX_FRAMES] mTextVertexBuffers;
	private IBindGroup[MAX_FRAMES] mTextBindGroups;
	private ITexture mFontTexture;
	private ITextureView mFontTextureView;
	private ISampler mFontSampler;
	private List<DebugTextVertex> mTextVerticesDepth = new .() ~ delete _;
	private List<DebugTextVertex> mTextVerticesOverlay = new .() ~ delete _;
	private int32 mTextDepthCount;
	private int32 mTextOverlayCount;

	// Font metrics (8x8 bitmap font, 16 chars per row, 6 rows for ASCII 32-127)
	private const int32 FONT_CHAR_WIDTH = 8;
	private const int32 FONT_CHAR_HEIGHT = 8;
	private const int32 FONT_CHARS_PER_ROW = 16;
	private const int32 FONT_TEXTURE_WIDTH = 128;  // 16 * 8
	private const int32 FONT_TEXTURE_HEIGHT = 48;  // 6 * 8 (for chars 32-127)

	// 2D screen-space text rendering
	private IRenderPipeline mText2DPipeline;
	private IBindGroupLayout mText2DBindGroupLayout;
	private IPipelineLayout mText2DPipelineLayout;
	private IBuffer[MAX_FRAMES] mText2DVertexBuffers;
	private IBuffer[MAX_FRAMES] mScreenParamBuffers;
	private IBindGroup[MAX_FRAMES] mText2DBindGroups;
	private List<DebugText2DVertex> mText2DVertices = new .() ~ delete _;
	private int32 mText2DCount;
	private uint32 mScreenWidth;
	private uint32 mScreenHeight;
	private float mFlipY;  // 1.0 for Vulkan (Y down in NDC), 0.0 otherwise

	// Saved counts after PrepareGPU (for use in Render after lists are cleared)
	private int32 mLineDepthCount;
	private int32 mLineOverlayCount;
	private int32 mTriDepthCount;
	private int32 mTriOverlayCount;

	// Current frame's view-projection matrix
	private Matrix mViewProjection;

	// Formats (set during initialization)
	private TextureFormat mColorFormat;
	private TextureFormat mDepthFormat;

	public this(IDevice device, ShaderLibrary shaderLibrary)
	{
		mDevice = device;
		mShaderLibrary = shaderLibrary;
	}

	public ~this()
	{
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			delete mBindGroups[i];
			delete mVertexBuffers[i];
			delete mUniformBuffers[i];
			delete mTextBindGroups[i];
			delete mTextVertexBuffers[i];
			delete mText2DBindGroups[i];
			delete mText2DVertexBuffers[i];
			delete mScreenParamBuffers[i];
		}

		delete mLinePipelineDepth;
		delete mLinePipelineOverlay;
		delete mTriPipelineDepth;
		delete mTriPipelineOverlay;
		delete mPipelineLayout;
		delete mBindGroupLayout;

		delete mTextPipelineDepth;
		delete mTextPipelineOverlay;
		delete mTextPipelineLayout;
		delete mTextBindGroupLayout;
		delete mFontSampler;
		delete mFontTextureView;
		delete mFontTexture;

		delete mText2DPipeline;
		delete mText2DPipelineLayout;
		delete mText2DBindGroupLayout;
	}

	/// Initializes the debug renderer with the given formats.
	public Result<void> Initialize(TextureFormat colorFormat, TextureFormat depthFormat)
	{
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		// Create bind group layout (camera uniform buffer)
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor layoutDesc = .(layoutEntries);
		switch (mDevice.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout):
			mBindGroupLayout = layout;
		case .Err:
			return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		switch (mDevice.CreatePipelineLayout(&pipelineLayoutDesc))
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
			switch (mDevice.CreateBuffer(&uniformDesc))
			{
			case .Ok(let buffer):
				mUniformBuffers[i] = buffer;
			case .Err:
				return .Err;
			}

			// Vertex buffer (large enough for all primitives)
			BufferDescriptor vertexDesc = .((uint64)(MAX_VERTICES * DebugVertex.SizeInBytes), .Vertex, .Upload);
			switch (mDevice.CreateBuffer(&vertexDesc))
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
			switch (mDevice.CreateBindGroup(&bindGroupDesc))
			{
			case .Ok(let group):
				mBindGroups[i] = group;
			case .Err:
				return .Err;
			}
		}

		// Create pipelines (deferred until first use to compile shaders)

		// Initialize text rendering resources
		if (InitializeTextResources() case .Err)
			return .Err;

		// Initialize 2D text resources
		if (InitializeText2DResources() case .Err)
			return .Err;

		// Set Y-flip flag based on backend (Vulkan needs Y flip)
		mFlipY = mDevice.FlipProjectionRequired ? 1.0f : 0.0f;

		return .Ok;
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

	/// Adds 3D text to the batch.
	/// The text is rendered as billboards facing the camera (requires view matrix).
	/// @param text The string to render.
	/// @param position World-space position of the text origin.
	/// @param color Text color.
	/// @param scale Size multiplier (1.0 = default size, roughly 0.1 world units per character).
	/// @param right Camera right vector for billboarding.
	/// @param up Camera up vector for billboarding.
	/// @param mode Depth test or overlay mode.
	public void AddText(StringView text, Vector3 position, Color color, float scale, Vector3 right, Vector3 up, DebugRenderMode mode = .DepthTest)
	{
		if (mFontTexture == null)
			return;

		let list = (mode == .DepthTest) ? mTextVerticesDepth : mTextVerticesOverlay;

		// Character size in world units
		let charWorldWidth = scale * 0.1f;
		let charWorldHeight = scale * 0.1f;

		var cursorX = 0.0f;

		for (let c in text.DecodedChars)
		{
			float u0, v0, u1, v1;
			if (!DebugFont.GetCharUV(c, out u0, out v0, out u1, out v1))
			{
				// Unknown character, skip with space
				cursorX += charWorldWidth;
				continue;
			}

			// Calculate quad corners (billboard facing camera)
			let xOffset = right * cursorX;
			let p0 = position + xOffset;                                           // bottom-left
			let p1 = position + xOffset + right * charWorldWidth;                  // bottom-right
			let p2 = position + xOffset + right * charWorldWidth + up * charWorldHeight; // top-right
			let p3 = position + xOffset + up * charWorldHeight;                    // top-left

			// Add two triangles for the quad (CCW winding)
			// Triangle 1: p0, p1, p2
			list.Add(.(p0, .(u0, v1), color));  // bottom-left
			list.Add(.(p1, .(u1, v1), color));  // bottom-right
			list.Add(.(p2, .(u1, v0), color));  // top-right

			// Triangle 2: p0, p2, p3
			list.Add(.(p0, .(u0, v1), color));  // bottom-left
			list.Add(.(p2, .(u1, v0), color));  // top-right
			list.Add(.(p3, .(u0, v0), color));  // top-left

			cursorX += charWorldWidth;
		}
	}

	/// Adds 3D text centered at the given position.
	public void AddTextCentered(StringView text, Vector3 position, Color color, float scale, Vector3 right, Vector3 up, DebugRenderMode mode = .DepthTest)
	{
		// Calculate text width
		let charWorldWidth = scale * 0.1f;
		let charWorldHeight = scale * 0.1f;
		let textWidth = text.Length * charWorldWidth;
		let textHeight = charWorldHeight;

		// Offset position to center
		let centeredPos = position - right * (textWidth * 0.5f) - up * (textHeight * 0.5f);
		AddText(text, centeredPos, color, scale, right, up, mode);
	}

	/// Sets the screen size for 2D text rendering.
	public void SetScreenSize(uint32 width, uint32 height)
	{
		mScreenWidth = width;
		mScreenHeight = height;
	}

	/// Adds 2D screen-space text.
	/// @param text The string to render.
	/// @param x X position in pixels (from left edge).
	/// @param y Y position in pixels (from top edge).
	/// @param color Text color.
	/// @param scale Size multiplier (1.0 = 8 pixels per character).
	public void AddText2D(StringView text, float x, float y, Color color, float scale = 1.0f)
	{
		if (mFontTexture == null)
			return;

		// Character size in pixels
		let charPixelWidth = (float)FONT_CHAR_WIDTH * scale;
		let charPixelHeight = (float)FONT_CHAR_HEIGHT * scale;

		var cursorX = x;

		for (let c in text.DecodedChars)
		{
			float u0, v0, u1, v1;
			if (!DebugFont.GetCharUV(c, out u0, out v0, out u1, out v1))
			{
				// Unknown character, skip with space
				cursorX += charPixelWidth;
				continue;
			}

			// Calculate quad corners (top-left origin, Y down)
			let left = cursorX;
			let right = cursorX + charPixelWidth;
			let top = y;
			let bottom = y + charPixelHeight;

			// Add two triangles for the quad (CCW winding)
			// Triangle 1: top-left, bottom-left, bottom-right
			mText2DVertices.Add(.(left, top, u0, v0, color));      // top-left
			mText2DVertices.Add(.(left, bottom, u0, v1, color));   // bottom-left
			mText2DVertices.Add(.(right, bottom, u1, v1, color));  // bottom-right

			// Triangle 2: top-left, bottom-right, top-right
			mText2DVertices.Add(.(left, top, u0, v0, color));      // top-left
			mText2DVertices.Add(.(right, bottom, u1, v1, color));  // bottom-right
			mText2DVertices.Add(.(right, top, u1, v0, color));     // top-right

			cursorX += charPixelWidth;
		}
	}

	/// Adds 2D screen-space text aligned to the right edge.
	/// @param text The string to render.
	/// @param rightMargin Pixels from the right edge.
	/// @param y Y position in pixels (from top edge).
	/// @param color Text color.
	/// @param scale Size multiplier.
	public void AddText2DRight(StringView text, float rightMargin, float y, Color color, float scale = 1.0f)
	{
		let charPixelWidth = (float)FONT_CHAR_WIDTH * scale;
		let textWidth = text.Length * charPixelWidth;
		let x = (float)mScreenWidth - rightMargin - textWidth;
		AddText2D(text, x, y, color, scale);
	}

	/// Uploads batched data to GPU and prepares for rendering.
	public void PrepareGPU(int32 frameIndex)
	{
		// Save counts for Render() (lists may be cleared after this)
		mLineDepthCount = (int32)mLineVerticesDepth.Count;
		mLineOverlayCount = (int32)mLineVerticesOverlay.Count;
		mTriDepthCount = (int32)mTriVerticesDepth.Count;
		mTriOverlayCount = (int32)mTriVerticesOverlay.Count;
		mTextDepthCount = (int32)mTextVerticesDepth.Count;
		mTextOverlayCount = (int32)mTextVerticesOverlay.Count;

		// Validate frame index
		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		if (mDevice?.Queue == null || mUniformBuffers[frameIndex] == null)
			return;

		// Upload view-projection matrix
		var vp = mViewProjection;
		Span<uint8> vpSpan = .((uint8*)&vp, sizeof(Matrix));
		var uniformBuf = mUniformBuffers[frameIndex];
		mDevice.Queue.WriteBuffer(uniformBuf, 0, vpSpan);

		// Calculate total vertices needed
		int totalVertices = mLineDepthCount + mLineOverlayCount + mTriDepthCount + mTriOverlayCount;

		// Upload line/triangle vertices
		if (totalVertices > 0 && mVertexBuffers[frameIndex] != null)
		{
			// Build combined vertex array
			List<DebugVertex> allVertices = scope .();
			allVertices.AddRange(mLineVerticesDepth);
			allVertices.AddRange(mLineVerticesOverlay);
			allVertices.AddRange(mTriVerticesDepth);
			allVertices.AddRange(mTriVerticesOverlay);

			let dataSize = (uint64)(allVertices.Count * DebugVertex.SizeInBytes);
			Span<uint8> vertexSpan = .((uint8*)allVertices.Ptr, (int)dataSize);
			var vertexBuf = mVertexBuffers[frameIndex];
			mDevice.Queue.WriteBuffer(vertexBuf, 0, vertexSpan);
		}

		// Upload text vertices
		int totalTextVertices = mTextDepthCount + mTextOverlayCount;
		if (totalTextVertices > 0 && mTextVertexBuffers[frameIndex] != null)
		{
			List<DebugTextVertex> allTextVertices = scope .();
			allTextVertices.AddRange(mTextVerticesDepth);
			allTextVertices.AddRange(mTextVerticesOverlay);

			let dataSize = (uint64)(allTextVertices.Count * DebugTextVertex.SizeInBytes);
			Span<uint8> textVertexSpan = .((uint8*)allTextVertices.Ptr, (int)dataSize);
			var textVertexBuf = mTextVertexBuffers[frameIndex];
			mDevice.Queue.WriteBuffer(textVertexBuf, 0, textVertexSpan);
		}

		// Upload 2D text vertices and screen params
		mText2DCount = (int32)mText2DVertices.Count;
		if (mText2DCount > 0 && mText2DVertexBuffers[frameIndex] != null && mScreenParamBuffers[frameIndex] != null)
		{
			// Upload screen size parameters (screenWidth, screenHeight, flipY, padding)
			float[4] screenParams = .((float)mScreenWidth, (float)mScreenHeight, mFlipY, 0);
			Span<uint8> screenSpan = .((uint8*)&screenParams, sizeof(float[4]));
			mDevice.Queue.WriteBuffer(mScreenParamBuffers[frameIndex], 0, screenSpan);

			// Upload 2D text vertices
			let dataSize = (uint64)(mText2DVertices.Count * DebugText2DVertex.SizeInBytes);
			Span<uint8> text2DSpan = .((uint8*)mText2DVertices.Ptr, (int)dataSize);
			mDevice.Queue.WriteBuffer(mText2DVertexBuffers[frameIndex], 0, text2DSpan);
		}
	}

	/// Renders all batched primitives.
	/// Uses counts saved from PrepareGPU (lists may have been cleared).
	public void Render(IRenderPassEncoder renderPass, int32 frameIndex, uint32 width, uint32 height)
	{
		// Ensure pipelines are created
		if (mLinePipelineDepth == null)
			CreatePipelines();

		if (mLinePipelineDepth == null)
			return; // Failed to create pipelines

		// Validate frame index
		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		// Extract array elements to local variables (workaround for Beef bug)
		var bindGroup = mBindGroups[frameIndex];
		var vertexBuffer = mVertexBuffers[frameIndex];

		renderPass.SetViewport(0, 0, width, height, 0, 1);
		renderPass.SetScissorRect(0, 0, width, height);

		uint32 vertexOffset = 0;

		// Render depth-tested lines
		if (mLineDepthCount > 0 && mLinePipelineDepth != null)
		{
			renderPass.SetPipeline(mLinePipelineDepth);
			renderPass.SetBindGroup(0, bindGroup);
			renderPass.SetVertexBuffer(0, vertexBuffer, 0);
			renderPass.Draw((uint32)mLineDepthCount, 1, vertexOffset, 0);
			vertexOffset += (uint32)mLineDepthCount;
		}

		// Render overlay lines
		if (mLineOverlayCount > 0 && mLinePipelineOverlay != null)
		{
			renderPass.SetPipeline(mLinePipelineOverlay);
			renderPass.SetBindGroup(0, bindGroup);
			renderPass.SetVertexBuffer(0, vertexBuffer, 0);
			renderPass.Draw((uint32)mLineOverlayCount, 1, vertexOffset, 0);
			vertexOffset += (uint32)mLineOverlayCount;
		}

		// Render depth-tested triangles
		if (mTriDepthCount > 0 && mTriPipelineDepth != null)
		{
			renderPass.SetPipeline(mTriPipelineDepth);
			renderPass.SetBindGroup(0, bindGroup);
			renderPass.SetVertexBuffer(0, vertexBuffer, 0);
			renderPass.Draw((uint32)mTriDepthCount, 1, vertexOffset, 0);
			vertexOffset += (uint32)mTriDepthCount;
		}

		// Render overlay triangles
		if (mTriOverlayCount > 0 && mTriPipelineOverlay != null)
		{
			renderPass.SetPipeline(mTriPipelineOverlay);
			renderPass.SetBindGroup(0, bindGroup);
			renderPass.SetVertexBuffer(0, vertexBuffer, 0);
			renderPass.Draw((uint32)mTriOverlayCount, 1, vertexOffset, 0);
		}

		// Render text (uses separate pipeline with texture)
		RenderText(renderPass, frameIndex);

		// Render 2D screen-space text
		RenderText2D(renderPass, frameIndex);
	}

	/// Renders text primitives.
	private void RenderText(IRenderPassEncoder renderPass, int32 frameIndex)
	{
		if (mTextPipelineDepth == null)
			CreateTextPipelines();

		if (mTextPipelineDepth == null || mTextBindGroups[frameIndex] == null)
			return;

		var textBindGroup = mTextBindGroups[frameIndex];
		var textVertexBuffer = mTextVertexBuffers[frameIndex];

		uint32 textVertexOffset = 0;

		// Render depth-tested text
		if (mTextDepthCount > 0)
		{
			renderPass.SetPipeline(mTextPipelineDepth);
			renderPass.SetBindGroup(0, textBindGroup);
			renderPass.SetVertexBuffer(0, textVertexBuffer, 0);
			renderPass.Draw((uint32)mTextDepthCount, 1, textVertexOffset, 0);
			textVertexOffset += (uint32)mTextDepthCount;
		}

		// Render overlay text
		if (mTextOverlayCount > 0 && mTextPipelineOverlay != null)
		{
			renderPass.SetPipeline(mTextPipelineOverlay);
			renderPass.SetBindGroup(0, textBindGroup);
			renderPass.SetVertexBuffer(0, textVertexBuffer, 0);
			renderPass.Draw((uint32)mTextOverlayCount, 1, textVertexOffset, 0);
		}
	}

	/// Renders 2D screen-space text primitives.
	private void RenderText2D(IRenderPassEncoder renderPass, int32 frameIndex)
	{
		if (mText2DCount == 0)
			return;

		if (mText2DPipeline == null)
			CreateText2DPipeline();

		if (mText2DPipeline == null || mText2DBindGroups[frameIndex] == null || mText2DVertexBuffers[frameIndex] == null)
			return;

		renderPass.SetPipeline(mText2DPipeline);
		renderPass.SetBindGroup(0, mText2DBindGroups[frameIndex]);
		renderPass.SetVertexBuffer(0, mText2DVertexBuffers[frameIndex], 0);
		renderPass.Draw((uint32)mText2DCount, 1, 0, 0);
	}

	/// Returns true if there are any primitives to render.
	public bool HasPrimitives =>
		mLineVerticesDepth.Count > 0 || mLineVerticesOverlay.Count > 0 ||
		mTriVerticesDepth.Count > 0 || mTriVerticesOverlay.Count > 0 ||
		mTextVerticesDepth.Count > 0 || mTextVerticesOverlay.Count > 0 ||
		mText2DVertices.Count > 0;

	// ==================== Pipeline Creation ====================

	private void CreatePipelines()
	{
		if (mShaderLibrary == null)
			return;

		// Load shaders from external files
		let shaderPair = mShaderLibrary.GetShaderPair("debug");
		if (shaderPair case .Err)
		{
			Console.WriteLine("[DebugRenderer] Failed to load debug shaders");
			return;
		}

		let vertShader = shaderPair.Value.vert.Module;
		let fragShader = shaderPair.Value.frag.Module;

		// Vertex layout
		VertexAttribute[2] attrs = .(
			.(VertexFormat.Float3, 0, 0),  // Position
			.(VertexFormat.UByte4Normalized, 12, 1) // Color (RGBA8)
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

		// Depth-tested line pipeline
		{
			DepthStencilState depthState = .()
			{
				Format = mDepthFormat,
				DepthTestEnabled = true,
				DepthWriteEnabled = false,
				DepthCompare = .Less
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

			if (mDevice.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mLinePipelineDepth = pipeline;
		}

		// Overlay line pipeline (no depth test)
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

			if (mDevice.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mLinePipelineOverlay = pipeline;
		}

		// Depth-tested triangle pipeline
		{
			DepthStencilState depthState = .()
			{
				Format = mDepthFormat,
				DepthTestEnabled = true,
				DepthWriteEnabled = false,
				DepthCompare = .Less
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

			if (mDevice.CreateRenderPipeline(&desc) case .Ok(let pipeline))
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

			if (mDevice.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mTriPipelineOverlay = pipeline;
		}
	}

	// ==================== Text Rendering Resources ====================

	private Result<void> InitializeTextResources()
	{
		// Create font texture from embedded font data
		uint8[] fontData = DebugFont.GenerateTextureData();
		defer delete fontData;

		TextureDescriptor texDesc = TextureDescriptor.Texture2D(
			(uint32)DebugFont.TextureWidth,
			(uint32)DebugFont.TextureHeight,
			.R8Unorm,
			.Sampled | .CopyDst
		);

		switch (mDevice.CreateTexture(&texDesc))
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
		mDevice.Queue.WriteTexture(mFontTexture, dataSpan, &dataLayout, &extent);

		// Create texture view
		TextureViewDescriptor viewDesc = .()
		{
			Format = .R8Unorm,
			Dimension = .Texture2D,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1
		};
		switch (mDevice.CreateTextureView(mFontTexture, &viewDesc))
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
		switch (mDevice.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler):
			mFontSampler = sampler;
		case .Err:
			return .Err;
		}

		// Create text bind group layout (camera + texture + sampler)
		BindGroupLayoutEntry[3] textLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),           // b0: camera
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),        // t0: font texture
			BindGroupLayoutEntry.Sampler(0, .Fragment)                // s0: font sampler
		);
		BindGroupLayoutDescriptor textLayoutDesc = .(textLayoutEntries);
		switch (mDevice.CreateBindGroupLayout(&textLayoutDesc))
		{
		case .Ok(let layout):
			mTextBindGroupLayout = layout;
		case .Err:
			return .Err;
		}

		// Create text pipeline layout
		IBindGroupLayout[1] textLayouts = .(mTextBindGroupLayout);
		PipelineLayoutDescriptor textPipelineLayoutDesc = .(textLayouts);
		switch (mDevice.CreatePipelineLayout(&textPipelineLayoutDesc))
		{
		case .Ok(let layout):
			mTextPipelineLayout = layout;
		case .Err:
			return .Err;
		}

		// Create per-frame text resources
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			// Text vertex buffer
			BufferDescriptor textVertexDesc = .((uint64)(MAX_VERTICES * DebugTextVertex.SizeInBytes), .Vertex, .Upload);
			switch (mDevice.CreateBuffer(&textVertexDesc))
			{
			case .Ok(let buffer):
				mTextVertexBuffers[i] = buffer;
			case .Err:
				return .Err;
			}

			// Text bind group (reuses uniform buffer from main debug renderer)
			BindGroupEntry[3] textEntries = .(
				BindGroupEntry.Buffer(0, mUniformBuffers[i]),
				BindGroupEntry.Texture(0, mFontTextureView),
				BindGroupEntry.Sampler(0, mFontSampler)
			);
			BindGroupDescriptor textBindGroupDesc = .(mTextBindGroupLayout, textEntries);
			switch (mDevice.CreateBindGroup(&textBindGroupDesc))
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
		if (mShaderLibrary == null || mTextPipelineLayout == null)
			return;

		// Load text shaders
		let shaderPair = mShaderLibrary.GetShaderPair("debug_text");
		if (shaderPair case .Err)
		{
			Console.WriteLine("[DebugRenderer] Failed to load debug_text shaders");
			return;
		}

		let vertShader = shaderPair.Value.vert.Module;
		let fragShader = shaderPair.Value.frag.Module;

		// Text vertex layout: Position (float3), TexCoord (float2), Color (ubyte4)
		VertexAttribute[3] textAttrs = .(
			.(VertexFormat.Float3, 0, 0),           // Position
			.(VertexFormat.Float2, 12, 1),          // TexCoord
			.(VertexFormat.UByte4Normalized, 20, 2) // Color
		);
		VertexBufferLayout[1] textVertexLayouts = .(
			.((uint32)DebugTextVertex.SizeInBytes, textAttrs, .Vertex)
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

		// Depth-tested text pipeline
		{
			DepthStencilState depthState = .()
			{
				Format = mDepthFormat,
				DepthTestEnabled = true,
				DepthWriteEnabled = false,
				DepthCompare = .Less
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

			if (mDevice.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mTextPipelineDepth = pipeline;
		}

		// Overlay text pipeline (no depth test)
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

			if (mDevice.CreateRenderPipeline(&desc) case .Ok(let pipeline))
				mTextPipelineOverlay = pipeline;
		}
	}

	// ==================== 2D Text Resources ====================

	private Result<void> InitializeText2DResources()
	{
		// Create 2D text bind group layout (screen params + texture + sampler)
		BindGroupLayoutEntry[3] text2DLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),      // b0: screen params
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),   // t0: font texture
			BindGroupLayoutEntry.Sampler(0, .Fragment)           // s0: font sampler
		);
		BindGroupLayoutDescriptor text2DLayoutDesc = .(text2DLayoutEntries);
		switch (mDevice.CreateBindGroupLayout(&text2DLayoutDesc))
		{
		case .Ok(let layout):
			mText2DBindGroupLayout = layout;
		case .Err:
			return .Err;
		}

		// Create 2D text pipeline layout
		IBindGroupLayout[1] text2DLayouts = .(mText2DBindGroupLayout);
		PipelineLayoutDescriptor text2DPipelineLayoutDesc = .(text2DLayouts);
		switch (mDevice.CreatePipelineLayout(&text2DPipelineLayoutDesc))
		{
		case .Ok(let layout):
			mText2DPipelineLayout = layout;
		case .Err:
			return .Err;
		}

		// Create per-frame 2D text resources
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			// Screen params uniform buffer
			BufferDescriptor screenParamDesc = .((uint64)sizeof(float[4]), .Uniform, .Upload);
			switch (mDevice.CreateBuffer(&screenParamDesc))
			{
			case .Ok(let buffer):
				mScreenParamBuffers[i] = buffer;
			case .Err:
				return .Err;
			}

			// 2D text vertex buffer
			BufferDescriptor text2DVertexDesc = .((uint64)(MAX_VERTICES * DebugText2DVertex.SizeInBytes), .Vertex, .Upload);
			switch (mDevice.CreateBuffer(&text2DVertexDesc))
			{
			case .Ok(let buffer):
				mText2DVertexBuffers[i] = buffer;
			case .Err:
				return .Err;
			}

			// 2D text bind group
			BindGroupEntry[3] text2DEntries = .(
				BindGroupEntry.Buffer(0, mScreenParamBuffers[i]),
				BindGroupEntry.Texture(0, mFontTextureView),
				BindGroupEntry.Sampler(0, mFontSampler)
			);
			BindGroupDescriptor text2DBindGroupDesc = .(mText2DBindGroupLayout, text2DEntries);
			switch (mDevice.CreateBindGroup(&text2DBindGroupDesc))
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
		if (mShaderLibrary == null || mText2DPipelineLayout == null)
			return;

		// Load 2D text shaders
		let vertShader = mShaderLibrary.GetShader("debug_text_2d", .Vertex);
		let fragShader = mShaderLibrary.GetShader("debug_text", .Fragment);  // Reuse the same fragment shader

		if (vertShader case .Err)
		{
			Console.WriteLine("[DebugRenderer] Failed to load debug_text_2d vertex shader");
			return;
		}
		if (fragShader case .Err)
		{
			Console.WriteLine("[DebugRenderer] Failed to load debug_text fragment shader");
			return;
		}

		let vertModule = vertShader.Value.Module;
		let fragModule = fragShader.Value.Module;

		// 2D text vertex layout: Position (float2), TexCoord (float2), Color (ubyte4)
		VertexAttribute[3] text2DAttrs = .(
			.(VertexFormat.Float2, 0, 0),            // Position (2D)
			.(VertexFormat.Float2, 8, 1),            // TexCoord
			.(VertexFormat.UByte4Normalized, 16, 2)  // Color
		);
		VertexBufferLayout[1] text2DVertexLayouts = .(
			.((uint32)DebugText2DVertex.SizeInBytes, text2DAttrs, .Vertex)
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

		// 2D text pipeline (no depth test, always overlay)
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

		if (mDevice.CreateRenderPipeline(&desc) case .Ok(let pipeline))
			mText2DPipeline = pipeline;
	}

}

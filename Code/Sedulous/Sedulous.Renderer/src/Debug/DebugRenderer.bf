namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
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
		}

		delete mLinePipelineDepth;
		delete mLinePipelineOverlay;
		delete mTriPipelineDepth;
		delete mTriPipelineOverlay;
		delete mPipelineLayout;
		delete mBindGroupLayout;
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
		return .Ok;
	}

	/// Begins a new frame, clearing previous batches.
	public void BeginFrame()
	{
		mLineVerticesDepth.Clear();
		mLineVerticesOverlay.Clear();
		mTriVerticesDepth.Clear();
		mTriVerticesOverlay.Clear();
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

	/// Uploads batched data to GPU and prepares for rendering.
	public void PrepareGPU(int32 frameIndex)
	{
		// Save counts for Render() (lists may be cleared after this)
		mLineDepthCount = (int32)mLineVerticesDepth.Count;
		mLineOverlayCount = (int32)mLineVerticesOverlay.Count;
		mTriDepthCount = (int32)mTriVerticesDepth.Count;
		mTriOverlayCount = (int32)mTriVerticesOverlay.Count;

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

		if (totalVertices == 0 || mVertexBuffers[frameIndex] == null)
			return;

		// Build combined vertex array
		List<DebugVertex> allVertices = scope .();
		allVertices.AddRange(mLineVerticesDepth);
		allVertices.AddRange(mLineVerticesOverlay);
		allVertices.AddRange(mTriVerticesDepth);
		allVertices.AddRange(mTriVerticesOverlay);

		// Upload vertices
		if (allVertices.Count > 0)
		{
			let dataSize = (uint64)(allVertices.Count * DebugVertex.SizeInBytes);
			Span<uint8> vertexSpan = .((uint8*)allVertices.Ptr, (int)dataSize);
			var vertexBuf = mVertexBuffers[frameIndex];
			mDevice.Queue.WriteBuffer(vertexBuf, 0, vertexSpan);
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
	}

	/// Returns true if there are any primitives to render.
	public bool HasPrimitives =>
		mLineVerticesDepth.Count > 0 || mLineVerticesOverlay.Count > 0 ||
		mTriVerticesDepth.Count > 0 || mTriVerticesOverlay.Count > 0;

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

}

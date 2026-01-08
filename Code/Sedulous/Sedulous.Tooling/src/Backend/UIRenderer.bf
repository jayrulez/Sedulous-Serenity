namespace Sedulous.Tooling;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.UI;

/// Vertex structure for UI rendering.
[Packed]
struct UIRenderVertex
{
	public Vector2 Position;
	public Vector2 TexCoord;
	public uint32 Color;

	public this(Vector2 pos, Vector2 uv, Color color)
	{
		Position = pos;
		TexCoord = uv;
		// Pack color as ABGR
		Color = ((uint32)color.A << 24) | ((uint32)color.B << 16) | ((uint32)color.G << 8) | color.R;
	}

	public this(float x, float y, float u, float v, Color color)
	{
		Position = Vector2(x, y);
		TexCoord = Vector2(u, v);
		Color = ((uint32)color.A << 24) | ((uint32)color.B << 16) | ((uint32)color.G << 8) | color.R;
	}
}

/// Renders UI batches using RHI.
class UIRenderer
{
	private const int32 MAX_VERTICES = 65536;
	private const int32 MAX_INDICES = MAX_VERTICES * 3;

	private IDevice mDevice;
	private bool mInitialized = false;

	// Buffers
	private IBuffer mVertexBuffer ~ delete _;
	private IBuffer mIndexBuffer ~ delete _;
	private IBuffer mUniformBuffer ~ delete _;

	// Pipeline resources
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IRenderPipeline mPipeline ~ delete _;
	private IBindGroup mBindGroup ~ delete _;
	private ISampler mSampler ~ delete _;

	// White texture for solid colors
	private ITexture mWhiteTexture ~ delete _;
	private ITextureView mWhiteTextureView ~ delete _;

	// CPU-side vertex/index buffers
	private List<UIRenderVertex> mVertices = new .() ~ delete _;
	private List<uint16> mIndices = new .() ~ delete _;

	// Uniform data
	private Vector2 mViewportSize;

	/// Creates a UI renderer.
	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Initializes the renderer with shaders.
	public Result<void> Initialize(TextureFormat colorFormat)
	{
		if (mDevice == null)
			return .Err;

		// Create buffers
		if (CreateBuffers() case .Err)
			return .Err;

		// Create sampler
		SamplerDescriptor samplerDesc = .();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Linear;
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		if (mDevice.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mSampler = sampler;
		else
			return .Err;

		// Create white texture
		if (CreateWhiteTexture() case .Err)
			return .Err;

		// Create pipeline (simplified - assumes shaders are available)
		// In a real implementation, you'd load UI shaders here
		// For now, mark as initialized with a placeholder approach

		mInitialized = true;
		return .Ok;
	}

	private Result<void> CreateBuffers()
	{
		// Vertex buffer
		let vertexSize = (uint64)(sizeof(UIRenderVertex) * MAX_VERTICES);
		BufferDescriptor vertDesc = .(vertexSize, .Vertex, .Upload);
		if (mDevice.CreateBuffer(&vertDesc) case .Ok(let vertBuf))
			mVertexBuffer = vertBuf;
		else
			return .Err;

		// Index buffer
		let indexSize = (uint64)(sizeof(uint16) * MAX_INDICES);
		BufferDescriptor indexDesc = .(indexSize, .Index, .Upload);
		if (mDevice.CreateBuffer(&indexDesc) case .Ok(let idxBuf))
			mIndexBuffer = idxBuf;
		else
			return .Err;

		// Uniform buffer (just viewport size for now)
		let uniformSize = (uint64)16; // vec4 for viewport
		BufferDescriptor uniformDesc = .(uniformSize, .Uniform, .Upload);
		if (mDevice.CreateBuffer(&uniformDesc) case .Ok(let uniBuf))
			mUniformBuffer = uniBuf;
		else
			return .Err;

		return .Ok;
	}

	private Result<void> CreateWhiteTexture()
	{
		TextureDescriptor texDesc = .();
		texDesc.Width = 1;
		texDesc.Height = 1;
		texDesc.Depth = 1;
		texDesc.Format = .RGBA8Unorm;
		texDesc.Usage = .Sampled | .CopyDst;
		texDesc.MipLevelCount = 1;
		texDesc.SampleCount = 1;
		texDesc.Dimension = .Texture2D;

		if (mDevice.CreateTexture(&texDesc) case .Ok(let tex))
			mWhiteTexture = tex;
		else
			return .Err;

		TextureViewDescriptor viewDesc = .();
		if (mDevice.CreateTextureView(mWhiteTexture, &viewDesc) case .Ok(let view))
			mWhiteTextureView = view;
		else
			return .Err;

		// Upload white pixel
		// Note: In actual implementation, need to handle texture data copy properly
		// This is simplified

		return .Ok;
	}

	/// Renders a draw batch.
	public void Render(IRenderPassEncoder renderPass, DrawBatch batch, Vector2 viewportSize)
	{
		if (!mInitialized || batch == null || batch.IsEmpty)
			return;

		mViewportSize = viewportSize;

		// Clear CPU buffers
		mVertices.Clear();
		mIndices.Clear();

		// Process draw commands and generate geometry
		ProcessBatch(batch);

		if (mVertices.Count == 0)
			return;

		// Upload vertex data
		let vertexData = Span<uint8>((uint8*)mVertices.Ptr, mVertices.Count * sizeof(UIRenderVertex));
		mDevice.Queue.WriteBuffer(mVertexBuffer, 0, vertexData);

		// Upload index data
		let indexData = Span<uint8>((uint8*)mIndices.Ptr, mIndices.Count * sizeof(uint16));
		mDevice.Queue.WriteBuffer(mIndexBuffer, 0, indexData);

		// Update uniforms
		float[4] uniforms = .(viewportSize.X, viewportSize.Y, 0, 0);
		let uniformData = Span<uint8>((uint8*)&uniforms[0], 16);
		mDevice.Queue.WriteBuffer(mUniformBuffer, 0, uniformData);

		// Set pipeline and draw
		// Note: In a full implementation, you'd set the pipeline, bind groups,
		// and iterate through draw calls with scissor rect changes

		if (mPipeline != null)
		{
			renderPass.SetPipeline(mPipeline);
			// renderPass.SetBindGroup(0, mBindGroup);
			renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
			renderPass.SetIndexBuffer(mIndexBuffer, .UInt16, 0);
			renderPass.DrawIndexed((uint32)mIndices.Count, 1, 0, 0, 0);
		}
	}

	private void ProcessBatch(DrawBatch batch)
	{
		for (let cmd in batch.Commands)
		{
			switch (cmd.Type)
			{
			case .FillRect:
				AddFilledRect(cmd.Bounds, cmd.Color);
			case .FillRoundedRect:
				// Simplified: draw as regular rect
				AddFilledRect(cmd.Bounds, cmd.Color);
			case .FillCircle:
				// Simplified: draw as rect for now
				AddFilledRect(cmd.Bounds, cmd.Color);
			case .DrawRect:
				AddStrokedRect(cmd.Bounds, cmd.Color, cmd.StrokeWidth);
			case .DrawRoundedRect:
				AddStrokedRect(cmd.Bounds, cmd.Color, cmd.StrokeWidth);
			case .DrawCircle:
				// Simplified: draw as stroked rect
				AddStrokedRect(cmd.Bounds, cmd.Color, cmd.StrokeWidth);
			case .DrawLine:
				if (cmd.VertexCount >= 2)
				{
					let v0 = batch.Vertices[(int)cmd.VertexOffset];
					let v1 = batch.Vertices[(int)cmd.VertexOffset + 1];
					AddLine(v0.Position, v1.Position, cmd.Color, cmd.StrokeWidth);
				}
			case .Image:
				AddTexturedRect(cmd.Bounds, cmd.SourceRect, cmd.Color);
			case .Text:
				// Text rendering would be handled separately by the font system
				// For now, skip
			case .FillPath:
				// Use provided vertices
				AddPathFill(batch, cmd);
			case .DrawPath:
				// Simplified: skip for now
			case .NineSlice:
				// Simplified: draw as regular rect
				AddTexturedRect(cmd.Bounds, RectangleF(0, 0, 1, 1), cmd.Color);
			}
		}
	}

	private void AddFilledRect(RectangleF rect, Color color)
	{
		let baseIndex = (uint16)mVertices.Count;

		// Add 4 vertices
		mVertices.Add(UIRenderVertex(rect.X, rect.Y, 0, 0, color));
		mVertices.Add(UIRenderVertex(rect.Right, rect.Y, 1, 0, color));
		mVertices.Add(UIRenderVertex(rect.Right, rect.Bottom, 1, 1, color));
		mVertices.Add(UIRenderVertex(rect.X, rect.Bottom, 0, 1, color));

		// Add 6 indices (2 triangles)
		mIndices.Add(baseIndex);
		mIndices.Add((uint16)(baseIndex + 1));
		mIndices.Add((uint16)(baseIndex + 2));
		mIndices.Add(baseIndex);
		mIndices.Add((uint16)(baseIndex + 2));
		mIndices.Add((uint16)(baseIndex + 3));
	}

	private void AddTexturedRect(RectangleF rect, RectangleF uv, Color color)
	{
		let baseIndex = (uint16)mVertices.Count;

		mVertices.Add(UIRenderVertex(rect.X, rect.Y, uv.X, uv.Y, color));
		mVertices.Add(UIRenderVertex(rect.Right, rect.Y, uv.Right, uv.Y, color));
		mVertices.Add(UIRenderVertex(rect.Right, rect.Bottom, uv.Right, uv.Bottom, color));
		mVertices.Add(UIRenderVertex(rect.X, rect.Bottom, uv.X, uv.Bottom, color));

		mIndices.Add(baseIndex);
		mIndices.Add((uint16)(baseIndex + 1));
		mIndices.Add((uint16)(baseIndex + 2));
		mIndices.Add(baseIndex);
		mIndices.Add((uint16)(baseIndex + 2));
		mIndices.Add((uint16)(baseIndex + 3));
	}

	private void AddStrokedRect(RectangleF rect, Color color, float thickness)
	{
		let hw = thickness * 0.5f;

		// Top edge
		AddFilledRect(RectangleF(rect.X - hw, rect.Y - hw, rect.Width + thickness, thickness), color);
		// Bottom edge
		AddFilledRect(RectangleF(rect.X - hw, rect.Bottom - hw, rect.Width + thickness, thickness), color);
		// Left edge
		AddFilledRect(RectangleF(rect.X - hw, rect.Y + hw, thickness, rect.Height - thickness), color);
		// Right edge
		AddFilledRect(RectangleF(rect.Right - hw, rect.Y + hw, thickness, rect.Height - thickness), color);
	}

	private void AddLine(Vector2 start, Vector2 end, Color color, float thickness)
	{
		let dir = end - start;
		let len = dir.Length();
		if (len < 0.001f)
			return;

		let normal = Vector2(-dir.Y / len, dir.X / len) * (thickness * 0.5f);

		let baseIndex = (uint16)mVertices.Count;

		mVertices.Add(UIRenderVertex(start + normal, Vector2(0, 0), color));
		mVertices.Add(UIRenderVertex(end + normal, Vector2(1, 0), color));
		mVertices.Add(UIRenderVertex(end - normal, Vector2(1, 1), color));
		mVertices.Add(UIRenderVertex(start - normal, Vector2(0, 1), color));

		mIndices.Add(baseIndex);
		mIndices.Add((uint16)(baseIndex + 1));
		mIndices.Add((uint16)(baseIndex + 2));
		mIndices.Add(baseIndex);
		mIndices.Add((uint16)(baseIndex + 2));
		mIndices.Add((uint16)(baseIndex + 3));
	}

	private void AddPathFill(DrawBatch batch, DrawCommand cmd)
	{
		if (cmd.IndexCount == 0)
			return;

		let baseIndex = (uint16)mVertices.Count;

		// Copy vertices
		for (uint32 i = 0; i < cmd.VertexCount; i++)
		{
			let v = batch.Vertices[(int)(cmd.VertexOffset + i)];
			mVertices.Add(UIRenderVertex(v.Position, v.TexCoord, v.Color));
		}

		// Copy indices with offset
		for (uint32 i = 0; i < cmd.IndexCount; i++)
		{
			let idx = batch.Indices[(int)(cmd.IndexOffset + i)];
			mIndices.Add((uint16)(baseIndex + idx));
		}
	}

	/// Gets whether the renderer is initialized.
	public bool IsInitialized => mInitialized;
}

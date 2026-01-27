namespace Sedulous.Drawing.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Profiler;

/// Uniform buffer data for projection matrix.
[CRepr]
struct DrawingUniforms
{
	public Matrix Projection;
}

/// Per-instance data for instanced sprite rendering.
/// Must match the shader's InstanceInput struct layout.
[CRepr]
public struct DrawingSpriteInstance
{
	public Vector2 Position;    // Screen position (top-left)
	public Vector2 Size;        // Width, height in pixels
	public Vector4 UVRect;      // minU, minV, maxU, maxV
	public Color Color;         // RGBA color
	public float Rotation;      // Rotation in radians
	public float _Pad0;         // Padding to 48 bytes
	public float _Pad1;
	public float _Pad2;

	public this(Vector2 position, Vector2 size, Vector4 uvRect, Color color, float rotation = 0)
	{
		Position = position;
		Size = size;
		UVRect = uvRect;
		Color = color;
		Rotation = rotation;
		_Pad0 = 0;
		_Pad1 = 0;
		_Pad2 = 0;
	}
}

/// Renders DrawContext/DrawBatch content using RHI.
/// Supports both per-vertex rendering (shapes, text) and GPU-instanced sprites.
/// Creates GPU textures on demand from ITexture.PixelData.
/// Does NOT own the device or swapchain - caller manages those.
public class DrawingRenderer : IDisposable
{
	private IDevice mDevice;
	private int32 mFrameCount;
	private TextureFormat mTargetFormat;
	private NewShaderSystem mShaderSystem;  // Borrowed, not owned

	// Standard pipeline (per-vertex)
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;
	private IRenderPipeline mMsaaPipeline;

	// Instanced pipeline
	private IShaderModule mInstancedVertShader;
	private IShaderModule mInstancedFragShader;
	private IRenderPipeline mInstancedPipeline;
	private IRenderPipeline mInstancedMsaaPipeline;

	private uint32 mMsaaSampleCount = 4;

	// Per-frame resources for standard rendering
	private IBuffer[] mVertexBuffers;
	private IBuffer[] mIndexBuffers;
	private IBuffer[] mUniformBuffers;

	// Per-frame resources for instanced rendering
	private IBuffer[] mInstanceBuffers;
	private IBindGroup[] mInstancedBindGroups;

	// Sampler for texture sampling
	private ISampler mSampler;

	// Texture cache - maps Drawing.ITexture to GPU resources
	// Using list since ITexture doesn't implement IHashable
	private List<CachedTexture> mTextureCache = new .() ~ { for (var e in _) { e.Dispose(mFrameCount); delete e; } delete _; };

	// Textures from current batch (stored for bind group creation)
	private List<Sedulous.Drawing.IImageData> mBatchTextures = new .() ~ delete _;

	/// Cached GPU resources for a Drawing.ITexture
	private class CachedTexture
	{
		public Sedulous.Drawing.IImageData SourceTexture;
		public Sedulous.RHI.ITexture GpuTexture;
		public ITextureView GpuTextureView;
		public IBindGroup[] BindGroups;

		public void Dispose(int32 frameCount)
		{
			if (BindGroups != null)
			{
				for (int i = 0; i < frameCount; i++)
					if (BindGroups[i] != null) delete BindGroups[i];
				delete BindGroups;
			}
			if (GpuTextureView != null) delete GpuTextureView;
			if (GpuTexture != null) delete GpuTexture;
		}
	}

	// Batch data converted for GPU (standard mode)
	private List<DrawingRenderVertex> mVertices = new .() ~ delete _;
	private List<uint16> mIndices = new .() ~ delete _;
	private List<DrawCommand> mDrawCommands = new .() ~ delete _;

	// Instance data for instanced sprite rendering
	private List<DrawingSpriteInstance> mSpriteInstances = new .() ~ delete _;

	// Buffer sizes
	private const int32 MAX_VERTICES = 65536;
	private const int32 MAX_INDICES = 65536 * 3;
	private const int32 MAX_SPRITE_INSTANCES = 16384;

	public bool IsInitialized { get; private set; }

	/// Initialize the renderer with a shader system.
	/// The shader system should be initialized with the path to shader files.
	public Result<void> Initialize(
		IDevice device,
		TextureFormat targetFormat,
		int32 frameCount,
		NewShaderSystem shaderSystem)
	{
		using (SProfiler.Begin("DrawingRenderer.Initialize"))
		{
			mDevice = device;
			mTargetFormat = targetFormat;
			mFrameCount = frameCount;
			mShaderSystem = shaderSystem;

			// Load shaders from files
			if (LoadShaders() case .Err)
				return .Err;

			// Create sampler
			if (CreateSampler() case .Err)
				return .Err;

			// Create bind group layout and pipeline layout
			if (CreateLayouts() case .Err)
				return .Err;

			// Create pipelines (standard and instanced)
			if (CreatePipelines() case .Err)
				return .Err;

			// Create per-frame resources
			if (CreatePerFrameResources() case .Err)
				return .Err;

			IsInitialized = true;
			return .Ok;
		}
	}

	/// Convert Drawing.PixelFormat to RHI.TextureFormat
	private TextureFormat ToRHIFormat(PixelFormat format)
	{
		switch (format)
		{
		case .R8: return .R8Unorm;
		case .RGBA8: return .RGBA8Unorm;
		case .BGRA8: return .BGRA8Unorm;
		}
	}

	/// Get or create cached GPU resources for a Drawing.ITexture
	private CachedTexture GetOrCreateCachedTexture(Sedulous.Drawing.IImageData texture)
	{
		if (texture == null)
			return null;

		// Check cache first
		for (let cached in mTextureCache)
		{
			if (cached.SourceTexture == texture)
				return cached;
		}

		// Create new GPU texture from pixel data
		let pixelData = texture.PixelData;
		if (pixelData.Length == 0)
			return null;

		let width = texture.Width;
		let height = texture.Height;
		let format = ToRHIFormat(texture.Format);

		// Create GPU texture
		TextureDescriptor textureDesc = TextureDescriptor.Texture2D(
			width, height, format, TextureUsage.Sampled | TextureUsage.CopyDst
		);

		Sedulous.RHI.ITexture gpuTexture;
		if (mDevice.CreateTexture(&textureDesc) case .Ok(let tex))
			gpuTexture = tex;
		else
			return null;

		// Upload pixel data
		TextureDataLayout dataLayout = .()
		{
			Offset = 0,
			BytesPerRow = width * GetBytesPerPixel(texture.Format),
			RowsPerImage = height
		};
		Extent3D writeSize = .(width, height, 1);
		mDevice.Queue.WriteTexture(gpuTexture, pixelData, &dataLayout, &writeSize);

		// Create texture view
		TextureViewDescriptor viewDesc = .() { Format = format };
		ITextureView gpuTextureView;
		if (mDevice.CreateTextureView(gpuTexture, &viewDesc) case .Ok(let view))
			gpuTextureView = view;
		else
		{
			delete gpuTexture;
			return null;
		}

		// Create and cache entry
		let cached = new CachedTexture();
		cached.SourceTexture = texture;
		cached.GpuTexture = gpuTexture;
		cached.GpuTextureView = gpuTextureView;
		cached.BindGroups = new IBindGroup[mFrameCount];
		mTextureCache.Add(cached);

		return cached;
	}

	/// Get bytes per pixel for a format
	private uint32 GetBytesPerPixel(PixelFormat format)
	{
		switch (format)
		{
		case .R8: return 1;
		case .RGBA8, .BGRA8: return 4;
		}
	}

	/// Clear all cached textures
	public void ClearTextureCache()
	{
		for (var cached in mTextureCache)
		{
			cached.Dispose(mFrameCount);
			delete cached;
		}
		mTextureCache.Clear();
	}

	/// Prepare batch data for standard (per-vertex) rendering.
	/// Call this after drawing to DrawContext and before the render pass.
	public void Prepare(DrawBatch batch, int32 frameIndex)
	{
		using (SProfiler.Begin("DrawingRenderer.Prepare"))
		{
			// Convert vertices
			mVertices.Clear();
			for (let v in batch.Vertices)
				mVertices.Add(.(v));

			// Copy indices
			mIndices.Clear();
			for (let i in batch.Indices)
				mIndices.Add(i);

			// Copy draw commands
			mDrawCommands.Clear();
			for (let cmd in batch.Commands)
				mDrawCommands.Add(cmd);

			// Store batch textures for multi-texture rendering
			mBatchTextures.Clear();
			for (let tex in batch.Textures)
				mBatchTextures.Add(tex);

			// Upload to GPU buffers
			if (mVertices.Count > 0)
			{
				let vertexData = Span<uint8>((uint8*)mVertices.Ptr, mVertices.Count * sizeof(DrawingRenderVertex));
				mDevice.Queue.WriteBuffer(mVertexBuffers[frameIndex], 0, vertexData);

				let indexData = Span<uint8>((uint8*)mIndices.Ptr, mIndices.Count * sizeof(uint16));
				mDevice.Queue.WriteBuffer(mIndexBuffers[frameIndex], 0, indexData);
			}

			// Ensure GPU textures are created and bind groups are ready
			for (int32 texIdx = 0; texIdx < mBatchTextures.Count; texIdx++)
				UpdateTextureBindGroup(texIdx, frameIndex);
		}
	}

	/// Prepare sprite instances for instanced rendering.
	/// Call this with sprite instance data before rendering.
	public void PrepareInstanced(Span<DrawingSpriteInstance> instances, int32 frameIndex)
	{
		using (SProfiler.Begin("DrawingRenderer.PrepareInstanced"))
		{
			mSpriteInstances.Clear();
			for (let inst in instances)
				mSpriteInstances.Add(inst);

			// Upload to GPU instance buffer
			if (mSpriteInstances.Count > 0 && mInstanceBuffers != null)
			{
				let instanceData = Span<uint8>((uint8*)mSpriteInstances.Ptr, mSpriteInstances.Count * sizeof(DrawingSpriteInstance));
				mDevice.Queue.WriteBuffer(mInstanceBuffers[frameIndex], 0, instanceData);
			}

			// Update instanced bind group
			UpdateInstancedBindGroup(frameIndex);
		}
	}

	/// Update the projection matrix for the given viewport size.
	public void UpdateProjection(uint32 width, uint32 height, int32 frameIndex)
	{
		using (SProfiler.Begin("DrawingRenderer.UpdateProjection"))
		{
			// Y-down orthographic projection (origin at top-left)
			// Check if device requires flipped projection (Vulkan vs OpenGL/D3D)
			Matrix projection;
			if (mDevice.FlipProjectionRequired)
				projection = Matrix.CreateOrthographicOffCenter(0, (float)width, 0, (float)height, -1, 1);
			else
				projection = Matrix.CreateOrthographicOffCenter(0, (float)width, (float)height, 0, -1, 1);

			DrawingUniforms uniforms = .() { Projection = projection };
			let uniformData = Span<uint8>((uint8*)&uniforms, sizeof(DrawingUniforms));
			mDevice.Queue.WriteBuffer(mUniformBuffers[frameIndex], 0, uniformData);
		}
	}

	/// Render standard (per-vertex) content to the current render pass.
	/// The render pass should already be begun.
	public void Render(IRenderPassEncoder renderPass, uint32 width, uint32 height, int32 frameIndex, bool useMsaa = false)
	{
		using (SProfiler.Begin("DrawingRenderer.Render"))
		{
			if (mIndices.Count == 0 || mDrawCommands.Count == 0)
				return;

			renderPass.SetViewport(0, 0, width, height, 0, 1);
			renderPass.SetPipeline(useMsaa ? mMsaaPipeline : mPipeline);
			renderPass.SetVertexBuffer(0, mVertexBuffers[frameIndex], 0);
			renderPass.SetIndexBuffer(mIndexBuffers[frameIndex], .UInt16, 0);

			// Track current texture to minimize bind group switches
			// Use -2 as sentinel to force first bind group set
			int32 currentTextureIndex = -2;

			// Process each draw command with its own scissor rect
			for (let cmd in mDrawCommands)
			{
				if (cmd.IndexCount == 0)
					continue;

				// Switch bind group if texture changed
				// Note: texIdx of -1 (solid color) maps to texture 0 in GetBindGroupForTexture
				let texIdx = cmd.TextureIndex;
				if (texIdx != currentTextureIndex)
				{
					let bindGroup = GetBindGroupForTexture(texIdx, frameIndex);
					if (bindGroup != null)
						renderPass.SetBindGroup(0, bindGroup);
					currentTextureIndex = texIdx;
				}

				// Set scissor rect based on clip mode
				if (cmd.ClipMode == .Scissor && cmd.ClipRect.Width > 0 && cmd.ClipRect.Height > 0)
				{
					// Conservative scissor rect calculation
					let startX = (int32)Math.Ceiling(Math.Max(0f, cmd.ClipRect.X));
					let startY = (int32)Math.Ceiling(Math.Max(0f, cmd.ClipRect.Y));
					let endX = (int32)Math.Floor(Math.Min(cmd.ClipRect.X + cmd.ClipRect.Width, (float)width));
					let endY = (int32)Math.Floor(Math.Min(cmd.ClipRect.Y + cmd.ClipRect.Height, (float)height));
					let w = (uint32)Math.Max(0, endX - startX);
					let h = (uint32)Math.Max(0, endY - startY);
					renderPass.SetScissorRect(startX, startY, w, h);
				}
				else
				{
					renderPass.SetScissorRect(0, 0, width, height);
				}

				renderPass.DrawIndexed((uint32)cmd.IndexCount, 1, (uint32)cmd.StartIndex, 0, 0);
			}
		}
	}

	/// Render instanced sprites to the current render pass.
	/// Call PrepareInstanced() before this.
	public void RenderInstanced(IRenderPassEncoder renderPass, uint32 width, uint32 height, int32 frameIndex, bool useMsaa = false)
	{
		using (SProfiler.Begin("DrawingRenderer.RenderInstanced"))
		{
			if (mSpriteInstances.Count == 0 || mInstancedPipeline == null)
				return;

			renderPass.SetViewport(0, 0, width, height, 0, 1);
			renderPass.SetScissorRect(0, 0, width, height);
			renderPass.SetPipeline(useMsaa ? mInstancedMsaaPipeline : mInstancedPipeline);
			renderPass.SetBindGroup(0, mInstancedBindGroups[frameIndex]);
			renderPass.SetVertexBuffer(0, mInstanceBuffers[frameIndex], 0);

			// Draw 6 vertices per sprite (2 triangles), N instances
			renderPass.Draw(6, (uint32)mSpriteInstances.Count, 0, 0);
		}
	}

	private Result<void> LoadShaders()
	{
		if (mShaderSystem == null)
			return .Err;

		// Load standard shaders (no instancing)
		let standardResult = mShaderSystem.GetShaderPair("drawing", .None);
		if (standardResult case .Ok(let stdShaders))
		{
			mVertShader = stdShaders.vert.Module;
			mFragShader = stdShaders.frag.Module;
		}
		else
		{
			Console.WriteLine("Failed to load standard drawing shaders");
			return .Err;
		}

		// Load instanced shaders
		let instancedResult = mShaderSystem.GetShaderPair("drawing", .Instanced);
		if (instancedResult case .Ok(let instShaders))
		{
			mInstancedVertShader = instShaders.vert.Module;
			mInstancedFragShader = instShaders.frag.Module;
		}
		else
		{
			Console.WriteLine("Failed to load instanced drawing shaders");
			return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateSampler()
	{
		SamplerDescriptor samplerDesc = .();
		// Default values are already ClampToEdge and Linear

		if (mDevice.CreateSampler(&samplerDesc) case .Ok(let sampler))
		{
			mSampler = sampler;
			return .Ok;
		}
		return .Err;
	}

	private Result<void> CreateLayouts()
	{
		// Bind group layout: uniform buffer (b0), texture (t0), sampler (s0)
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindGroupLayoutDesc) case .Ok(let layout))
			mBindGroupLayout = layout;
		else
			return .Err;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) case .Ok(let pipelineLayout))
			mPipelineLayout = pipelineLayout;
		else
			return .Err;

		return .Ok;
	}

	private Result<void> CreatePipelines()
	{
		// Create standard pipeline
		if (CreateStandardPipeline() case .Err)
			return .Err;

		// Create instanced pipeline
		if (CreateInstancedPipeline() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateStandardPipeline()
	{
		// Vertex layout: position (float2), texcoord (float2), color (float4)
		VertexAttribute[3] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),   // Position
			.(VertexFormat.Float2, 8, 1),   // TexCoord
			.(VertexFormat.Float4, 16, 2)   // Color
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(DrawingRenderVertex), vertexAttributes)
		);

		ColorTargetState[1] colorTargets = .(.(mTargetFormat, .AlphaBlend));

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(mVertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(mFragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = null,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue,
				AlphaToCoverageEnabled = false
			}
		};

		// Create standard pipeline
		if (mDevice.CreateRenderPipeline(&pipelineDesc) case .Ok(let pipeline))
			mPipeline = pipeline;
		else
			return .Err;

		// Create MSAA pipeline variant
		pipelineDesc.Multisample.Count = mMsaaSampleCount;
		if (mDevice.CreateRenderPipeline(&pipelineDesc) case .Ok(let msaaPipeline))
			mMsaaPipeline = msaaPipeline;
		else
			return .Err;

		return .Ok;
	}

	private Result<void> CreateInstancedPipeline()
	{
		if (mInstancedVertShader == null || mInstancedFragShader == null)
			return .Ok;  // Skip if instanced shaders not loaded

		// Instance layout: position (float2), size (float2), uvRect (float4), color (unorm8x4), rotation (float), padding
		VertexAttribute[8] instanceAttributes = .(
			.(VertexFormat.Float2, 0, 0),              // Position
			.(VertexFormat.Float2, 8, 1),              // Size
			.(VertexFormat.Float4, 16, 2),             // UVRect
			.(VertexFormat.UByte4Normalized, 32, 3),   // Color
			.(VertexFormat.Float, 36, 4),              // Rotation
			.(VertexFormat.Float, 40, 5),              // Pad0
			.(VertexFormat.Float, 44, 6),              // Pad1
			.(VertexFormat.Float, 48, 7)               // Pad2
		);
		VertexBufferLayout[1] instanceBuffers = .(
			.((uint64)sizeof(DrawingSpriteInstance), instanceAttributes, .Instance)
		);

		ColorTargetState[1] colorTargets = .(.(mTargetFormat, .AlphaBlend));

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(mInstancedVertShader, "main"),
				Buffers = instanceBuffers
			},
			Fragment = .()
			{
				Shader = .(mInstancedFragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = null,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue,
				AlphaToCoverageEnabled = false
			}
		};

		// Create instanced pipeline
		if (mDevice.CreateRenderPipeline(&pipelineDesc) case .Ok(let pipeline))
			mInstancedPipeline = pipeline;
		else
			return .Err;

		// Create instanced MSAA pipeline variant
		pipelineDesc.Multisample.Count = mMsaaSampleCount;
		if (mDevice.CreateRenderPipeline(&pipelineDesc) case .Ok(let msaaPipeline))
			mInstancedMsaaPipeline = msaaPipeline;
		else
			return .Err;

		return .Ok;
	}

	private Result<void> CreatePerFrameResources()
	{
		mVertexBuffers = new IBuffer[mFrameCount];
		mIndexBuffers = new IBuffer[mFrameCount];
		mUniformBuffers = new IBuffer[mFrameCount];
		mInstanceBuffers = new IBuffer[mFrameCount];
		mInstancedBindGroups = new IBindGroup[mFrameCount];

		for (int32 i = 0; i < mFrameCount; i++)
		{
			// Vertex buffer (host-visible for fast CPU writes)
			BufferDescriptor vertexDesc = .()
			{
				Size = (uint64)(MAX_VERTICES * sizeof(DrawingRenderVertex)),
				Usage = .Vertex,
				MemoryAccess = .Upload
			};
			if (mDevice.CreateBuffer(&vertexDesc) case .Ok(let vb))
				mVertexBuffers[i] = vb;
			else
				return .Err;

			// Index buffer (host-visible for fast CPU writes)
			BufferDescriptor indexDesc = .()
			{
				Size = (uint64)(MAX_INDICES * sizeof(uint16)),
				Usage = .Index,
				MemoryAccess = .Upload
			};
			if (mDevice.CreateBuffer(&indexDesc) case .Ok(let ib))
				mIndexBuffers[i] = ib;
			else
				return .Err;

			// Uniform buffer (host-visible for fast CPU writes)
			BufferDescriptor uniformDesc = .()
			{
				Size = (uint64)sizeof(DrawingUniforms),
				Usage = .Uniform,
				MemoryAccess = .Upload
			};
			if (mDevice.CreateBuffer(&uniformDesc) case .Ok(let ub))
				mUniformBuffers[i] = ub;
			else
				return .Err;

			// Instance buffer for instanced sprites
			BufferDescriptor instanceDesc = .()
			{
				Size = (uint64)(MAX_SPRITE_INSTANCES * sizeof(DrawingSpriteInstance)),
				Usage = .Vertex,
				MemoryAccess = .Upload
			};
			if (mDevice.CreateBuffer(&instanceDesc) case .Ok(let instBuf))
				mInstanceBuffers[i] = instBuf;
			else
				return .Err;
		}

		return .Ok;
	}

	private void UpdateTextureBindGroup(int32 textureIndex, int32 frameIndex)
	{
		if (textureIndex >= mBatchTextures.Count)
			return;

		let texture = mBatchTextures[textureIndex];
		if (texture == null)
			return;

		// Get or create cached GPU texture
		let cached = GetOrCreateCachedTexture(texture);
		if (cached == null || cached.GpuTextureView == null)
			return;

		// Skip if bind group already exists for this frame
		if (cached.BindGroups[frameIndex] != null)
			return;

		// Create bind group
		BindGroupEntry[3] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffers[frameIndex]),
			BindGroupEntry.Texture(0, cached.GpuTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (mDevice.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
			cached.BindGroups[frameIndex] = group;
	}

	private IBindGroup GetBindGroupForTexture(int32 textureIndex, int32 frameIndex)
	{
		if (mBatchTextures.Count == 0)
			return null;

		// For solid color drawing (index -1), use texture 0 which contains the white pixel
		let effectiveIndex = (textureIndex < 0) ? 0 : textureIndex;
		if (effectiveIndex >= mBatchTextures.Count)
			return null;

		let texture = mBatchTextures[effectiveIndex];
		if (texture == null)
			return null;

		// Find cached texture
		for (let cached in mTextureCache)
		{
			if (cached.SourceTexture == texture)
				return cached.BindGroups[frameIndex];
		}
		return null;
	}

	private void UpdateInstancedBindGroup(int32 frameIndex)
	{
		// Skip if bind group is already valid
		if (mInstancedBindGroups[frameIndex] != null)
			return;

		// For instanced rendering, use the first texture from batch if available
		if (mBatchTextures.Count == 0)
			return;

		let cached = GetOrCreateCachedTexture(mBatchTextures[0]);
		if (cached == null || cached.GpuTextureView == null)
			return;

		BindGroupEntry[3] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffers[frameIndex]),
			BindGroupEntry.Texture(0, cached.GpuTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (mDevice.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
			mInstancedBindGroups[frameIndex] = group;
	}

	public void Dispose()
	{
		// Texture cache (includes bind groups)
		ClearTextureCache();

		// Per-frame resources
		DisposeBufferArray(ref mInstancedBindGroups);
		DisposeBufferArray(ref mUniformBuffers);
		DisposeBufferArray(ref mIndexBuffers);
		DisposeBufferArray(ref mVertexBuffers);
		DisposeBufferArray(ref mInstanceBuffers);

		// Instanced pipeline resources
		if (mInstancedMsaaPipeline != null) { delete mInstancedMsaaPipeline; mInstancedMsaaPipeline = null; }
		if (mInstancedPipeline != null) { delete mInstancedPipeline; mInstancedPipeline = null; }

		// Standard pipeline resources
		if (mMsaaPipeline != null) { delete mMsaaPipeline; mMsaaPipeline = null; }
		if (mPipeline != null) { delete mPipeline; mPipeline = null; }
		if (mPipelineLayout != null) { delete mPipelineLayout; mPipelineLayout = null; }
		if (mBindGroupLayout != null) { delete mBindGroupLayout; mBindGroupLayout = null; }

		// Sampler
		if (mSampler != null) { delete mSampler; mSampler = null; }

		// Note: Shader modules are owned by the shader system cache, not by us

		IsInitialized = false;
	}

	private void DisposeBufferArray<T>(ref T[] buffers) where T : IDisposable, delete
	{
		if (buffers != null)
		{
			for (let buf in buffers)
				if (buf != null) delete buf;
			delete buffers;
			buffers = null;
		}
	}
}

namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RHI.HLSLShaderCompiler;
using Sedulous.Mathematics;

/// Uniform data for trail rendering.
[CRepr]
struct TrailUniforms
{
	/// x = useTexture, y = softEdge, z = unused, w = unused
	public Vector4 Params;

	public static Self Default => .()
	{
		Params = .(0, 0.3f, 0, 0)  // No texture, soft edges
	};
}

/// Renderer for particle trails and ribbons.
/// Creates continuous ribbon geometry from trail point data.
class TrailRenderer
{
	private const int32 MAX_FRAMES = 2;
	private const int32 MAX_TRAIL_VERTICES = 8192;  // Max vertices per frame

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;

	// Bind group layouts
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;

	// Pipelines for different blend modes
	private IRenderPipeline mAlphaBlendPipeline ~ delete _;
	private IRenderPipeline mAdditivePipeline ~ delete _;

	// Per-frame resources
	private IBuffer[MAX_FRAMES] mTrailUniformBuffers ~ { for (var buf in _) delete buf; };
	private IBuffer[MAX_FRAMES] mVertexBuffers ~ { for (var buf in _) delete buf; };
	private IBindGroup[MAX_FRAMES] mBindGroups ~ { for (var bg in _) delete bg; };

	// Default white texture for non-textured trails
	private ITexture mDefaultTexture ~ delete _;
	private ITextureView mDefaultTextureView ~ delete _;
	private ISampler mDefaultSampler ~ delete _;

	// Per-frame camera buffers (references, not owned)
	private IBuffer[MAX_FRAMES] mCameraBuffers;

	// CPU-side vertex staging
	private TrailVertex[] mStagingVertices = new TrailVertex[MAX_TRAIL_VERTICES] ~ delete _;

	// Per-frame vertex offset tracking (to avoid overwriting data still being drawn)
	private int32[MAX_FRAMES] mCurrentVertexOffset;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mInitialized = false;

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Initializes the trail renderer with pipeline resources.
	public Result<void> Initialize(ShaderLibrary shaderLibrary,
		IBuffer[MAX_FRAMES] cameraBuffers, TextureFormat colorFormat, TextureFormat depthFormat)
	{
		if (mDevice == null)
			return .Err;

		mShaderLibrary = shaderLibrary;
		mCameraBuffers = cameraBuffers;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		if (CreateDefaultTexture() case .Err)
			return .Err;

		if (CreateBindGroupLayouts() case .Err)
			return .Err;

		if (CreateBuffers() case .Err)
			return .Err;

		if (CreateBindGroups() case .Err)
			return .Err;

		if (CreatePipelines() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	private Result<void> CreateDefaultTexture()
	{
		// Create a 1x1 white texture for non-textured trails
		TextureDescriptor texDesc = TextureDescriptor.Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);

		if (mDevice.CreateTexture(&texDesc) not case .Ok(let texture))
			return .Err;
		mDefaultTexture = texture;

		// Upload white pixel
		uint8[4] whitePixel = .(255, 255, 255, 255);
		TextureDataLayout dataLayout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
		Extent3D writeSize = .(1, 1, 1);
		mDevice.Queue.WriteTexture(mDefaultTexture, Span<uint8>(&whitePixel, 4), &dataLayout, &writeSize);

		// Create texture view
		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
		if (mDevice.CreateTextureView(mDefaultTexture, &viewDesc) not case .Ok(let view))
			return .Err;
		mDefaultTextureView = view;

		// Create default sampler
		SamplerDescriptor samplerDesc = .()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge
		};
		if (mDevice.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return .Err;
		mDefaultSampler = sampler;

		return .Ok;
	}

	private Result<void> CreateBindGroupLayouts()
	{
		// Bind group layout: b0 = camera, b1 = trail uniforms, t0 = texture, s0 = sampler
		BindGroupLayoutEntry[4] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),   // b0: camera
			BindGroupLayoutEntry.UniformBuffer(1, .Fragment),              // b1: trail uniforms
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),             // t0: texture
			BindGroupLayoutEntry.Sampler(0, .Fragment)                     // s0: sampler
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mBindGroupLayout = layout;

		// Pipeline layout with single bind group
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mPipelineLayout = pipelineLayout;

		return .Ok;
	}

	private Result<void> CreateBuffers()
	{
		uint64 uniformSize = sizeof(TrailUniforms);
		uint64 vertexBufferSize = (uint64)(sizeof(TrailVertex) * MAX_TRAIL_VERTICES);

		for (int i = 0; i < MAX_FRAMES; i++)
		{
			// Uniform buffer
			BufferDescriptor uniformDesc = .(uniformSize, .Uniform, .Upload);
			if (mDevice.CreateBuffer(&uniformDesc) not case .Ok(let buffer))
				return .Err;
			mTrailUniformBuffers[i] = buffer;

			// Vertex buffer
			BufferDescriptor vertexDesc = .(vertexBufferSize, .Vertex, .Upload);
			if (mDevice.CreateBuffer(&vertexDesc) not case .Ok(let vbuffer))
				return .Err;
			mVertexBuffers[i] = vbuffer;
		}

		return .Ok;
	}

	private Result<void> CreateBindGroups()
	{
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			BindGroupEntry[4] entries = .(
				BindGroupEntry.Buffer(0, mCameraBuffers[i]),        // b0: camera
				BindGroupEntry.Buffer(1, mTrailUniformBuffers[i]),  // b1: trail uniforms
				BindGroupEntry.Texture(0, mDefaultTextureView),     // t0: texture
				BindGroupEntry.Sampler(0, mDefaultSampler)          // s0: sampler
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			if (mDevice.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mBindGroups[i] = group;
		}

		return .Ok;
	}

	private Result<void> CreatePipelines()
	{
		// Load trail shaders
		let vertResult = mShaderLibrary.GetShader("particle_trail", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShaderInfo = vertResult.Get();

		let fragResult = mShaderLibrary.GetShader("particle_trail", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShaderInfo = fragResult.Get();

		// TrailVertex layout: Position(12) + TexCoord(8) + Color(4) = 24 bytes
		Sedulous.RHI.VertexAttribute[3] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),              // Position
			.(VertexFormat.Float2, 12, 1),             // TexCoord
			.(VertexFormat.UByte4Normalized, 20, 2)    // Color
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(24, vertexAttrs, .Vertex)
		);

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;  // Trails don't write to depth
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		// Alpha blend pipeline
		ColorTargetState[1] alphaTargets = .(
			ColorTargetState(mColorFormat, BlendState.AlphaBlend)
		);
		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, depthState, alphaTargets) not case .Ok(let alphaPipeline))
			return .Err;
		mAlphaBlendPipeline = alphaPipeline;

		// Additive blend pipeline
		BlendState additiveBlend = .();
		additiveBlend.Color = .(.Add, .SrcAlpha, .One);
		additiveBlend.Alpha = .(.Add, .One, .One);
		ColorTargetState[1] additiveTargets = .(
			ColorTargetState(mColorFormat, additiveBlend)
		);
		if (CreatePipelineWithTargets(vertShaderInfo.Module, fragShaderInfo.Module, vertexBuffers, depthState, additiveTargets) not case .Ok(let additivePipeline))
			return .Err;
		mAdditivePipeline = additivePipeline;

		return .Ok;
	}

	private Result<IRenderPipeline> CreatePipelineWithTargets(
		IShaderModule vertShader, IShaderModule fragShader,
		Span<VertexBufferLayout> vertexBuffers,
		DepthStencilState depthState,
		Span<ColorTargetState> colorTargets)
	{
		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleStrip,  // Trail uses triangle strip
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (mDevice.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return .Err;
		return .Ok(pipeline);
	}

	private IRenderPipeline GetPipelineForBlendMode(ParticleBlendMode blendMode)
	{
		switch (blendMode)
		{
		case .Additive: return mAdditivePipeline;
		default: return mAlphaBlendPipeline;
		}
	}

	/// Resets the vertex buffer offset for a new frame.
	/// Call this at the start of each frame before rendering any trails.
	public void BeginFrame(int32 frameIndex)
	{
		if (frameIndex >= 0 && frameIndex < MAX_FRAMES)
			mCurrentVertexOffset[frameIndex] = 0;
	}

	/// Updates the trail uniform buffer.
	public void UpdateUniforms(int32 frameIndex, bool useTexture, float softEdge)
	{
		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		TrailUniforms uniforms = .();
		uniforms.Params = .(useTexture ? 1.0f : 0.0f, softEdge, 0, 0);

		Span<uint8> data = .((uint8*)&uniforms, sizeof(TrailUniforms));
		mDevice.Queue.WriteBuffer(mTrailUniformBuffers[frameIndex], 0, data);
	}

	/// Renders a single trail.
	/// Returns the number of vertices rendered.
	public int32 RenderTrail(IRenderPassEncoder renderPass, int32 frameIndex,
		ParticleTrail trail, Vector3 cameraPosition,
		TrailSettings settings, ParticleBlendMode blendMode, float currentTime)
	{
		if (!mInitialized || trail == null || !trail.HasPoints)
			return 0;

		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return 0;

		// Get current offset for this frame
		int32 vertexOffset = mCurrentVertexOffset[frameIndex];

		// Check if we have room in the buffer
		int32 remainingSpace = MAX_TRAIL_VERTICES - vertexOffset;
		if (remainingSpace < 4)
			return 0;  // Not enough space for even a minimal trail

		// Generate vertices into staging buffer
		int32 vertexCount = trail.GenerateVertices(
			Span<TrailVertex>(mStagingVertices, 0, remainingSpace),
			cameraPosition,
			settings.WidthStart,
			settings.WidthEnd,
			currentTime,
			settings.MaxAge
		);

		if (vertexCount < 4)  // Need at least 2 segments (4 vertices) for a triangle strip
			return 0;

		// Upload vertices at current offset
		uint64 byteOffset = (uint64)(vertexOffset * sizeof(TrailVertex));
		Span<uint8> vertexData = .((uint8*)mStagingVertices.Ptr, sizeof(TrailVertex) * vertexCount);
		mDevice.Queue.WriteBuffer(mVertexBuffers[frameIndex], byteOffset, vertexData);

		// Update offset for next trail
		mCurrentVertexOffset[frameIndex] = vertexOffset + vertexCount;

		// Update uniforms
		UpdateUniforms(frameIndex, false, 0.3f);

		// Render with vertex buffer offset
		let pipeline = GetPipelineForBlendMode(blendMode);
		renderPass.SetPipeline(pipeline);
		renderPass.SetBindGroup(0, mBindGroups[frameIndex]);
		renderPass.SetVertexBuffer(0, mVertexBuffers[frameIndex], byteOffset);
		renderPass.Draw((uint32)vertexCount, 1, 0, 0);

		return vertexCount;
	}

	/// Batch render multiple trails.
	/// Collects all trail vertices into a single draw call for efficiency.
	public int32 RenderTrails(IRenderPassEncoder renderPass, int32 frameIndex,
		List<ParticleTrail> trails, Vector3 cameraPosition,
		TrailSettings settings, ParticleBlendMode blendMode, float currentTime)
	{
		if (!mInitialized || trails == null || trails.Count == 0)
			return 0;

		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return 0;

		int32 totalVertices = 0;
		int32 trailsRendered = 0;

		// Note: For proper batching, we would need to use primitive restart or
		// render each trail separately. For now, render each trail separately.
		for (let trail in trails)
		{
			if (trail == null || !trail.HasPoints)
				continue;

			int32 verts = RenderTrail(renderPass, frameIndex, trail, cameraPosition,
				settings, blendMode, currentTime);
			if (verts > 0)
			{
				totalVertices += verts;
				trailsRendered++;
			}
		}

		return totalVertices;
	}

	/// Returns true if the renderer is fully initialized.
	public bool IsInitialized => mInitialized && mAlphaBlendPipeline != null;
}

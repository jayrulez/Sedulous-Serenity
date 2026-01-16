namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders2;

/// Key for trail pipeline caching.
struct TrailPipelineKey : IHashable
{
	public ParticleBlendMode BlendMode;
	public bool HasDepth;

	public int GetHashCode()
	{
		int hash = (int)BlendMode;
		hash = hash * 31 + (HasDepth ? 1 : 0);
		return hash;
	}
}

/// Draw batch for trails.
struct TrailDrawBatch
{
	public TrailEmitter Trail;
	public uint32 VertexOffset;
	public uint32 VertexCount;
	public ParticleBlendMode BlendMode;
}

/// Statistics for trail rendering.
struct TrailStats
{
	public int32 TrailCount;
	public int32 VertexCount;
	public int32 DrawCalls;
	public int32 PipelineSwitches;
	public uint64 VertexBytesUsed;
}

/// Manages trail rendering with transient buffers and parametric pipelines.
class TrailDrawSystem : IDisposable
{
	private const int32 MAX_TRAIL_VERTICES = 16384;

	private IDevice mDevice;
	private Renderer mRenderer;

	// Pipeline cache (blend mode × depth)
	private Dictionary<TrailPipelineKey, IRenderPipeline> mPipelineCache = new .() ~ {
		for (let kv in _)
			delete kv.value;
		delete _;
	};

	// Layouts
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;

	// Default resources
	private ITexture mDefaultTexture ~ delete _;
	private ITextureView mDefaultTextureView ~ delete _;
	private ISampler mDefaultSampler ~ delete _;

	// Uniform buffer
	private IBuffer mUniformBuffer ~ delete _;

	// CPU-side vertex staging
	private TrailVertex[] mStagingVertices = new TrailVertex[MAX_TRAIL_VERTICES] ~ delete _;

	// Per-frame data
	private List<TrailDrawBatch> mBatches = new .() ~ delete _;
	private TransientAllocation mVertexAllocation;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mInitialized = false;

	// Current frame state
	private float mCurrentTime = 0;

	// Statistics
	public TrailStats Stats { get; private set; }

	public this(Renderer renderer)
	{
		mRenderer = renderer;
		mDevice = null;
	}

	/// Initializes the trail draw system.
	public Result<void> Initialize(IDevice device, TextureFormat colorFormat, TextureFormat depthFormat)
	{
		mDevice = device;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		if (CreateDefaultResources() case .Err)
			return .Err;

		if (CreateBindGroupLayout() case .Err)
			return .Err;

		if (CreateUniformBuffer() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	private Result<void> CreateDefaultResources()
	{
		// Create 1x1 white texture
		var texDesc = TextureDescriptor.Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);
		switch (mDevice.CreateTexture(&texDesc))
		{
		case .Ok(let tex): mDefaultTexture = tex;
		case .Err: return .Err;
		}

		uint8[4] whitePixel = .(255, 255, 255, 255);
		TextureDataLayout dataLayout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
		Extent3D writeSize = .(1, 1, 1);
		mDevice.Queue.WriteTexture(mDefaultTexture, Span<uint8>(&whitePixel, 4), &dataLayout, &writeSize);

		var viewDesc = TextureViewDescriptor();
		viewDesc.Format = .RGBA8Unorm;
		switch (mDevice.CreateTextureView(mDefaultTexture, &viewDesc))
		{
		case .Ok(let view): mDefaultTextureView = view;
		case .Err: return .Err;
		}

		var samplerDesc = SamplerDescriptor();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		switch (mDevice.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler): mDefaultSampler = sampler;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateBindGroupLayout()
	{
		// b0 = scene uniforms, b1 = trail uniforms
		// t0 = trail texture, s0 = sampler
		BindGroupLayoutEntry[4] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(1, .Fragment),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);

		var layoutDesc = BindGroupLayoutDescriptor(layoutEntries);
		switch (mDevice.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		var pipelineLayoutDesc = PipelineLayoutDescriptor(layouts);
		switch (mDevice.CreatePipelineLayout(&pipelineLayoutDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateUniformBuffer()
	{
		var bufDesc = BufferDescriptor(TrailUniforms.Size, .Uniform, .Upload);
		switch (mDevice.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mUniformBuffer = buf;
		case .Err: return .Err;
		}
		return .Ok;
	}

	/// Gets or creates a pipeline for the given configuration.
	private Result<IRenderPipeline> GetOrCreatePipeline(TrailPipelineKey key, IShaderModule vertShader, IShaderModule fragShader)
	{
		if (mPipelineCache.TryGetValue(key, let existing))
			return .Ok(existing);

		let pipeline = CreatePipeline(key, vertShader, fragShader);
		if (pipeline case .Err)
			return .Err;

		mPipelineCache[key] = pipeline.Get();
		return pipeline;
	}

	private Result<IRenderPipeline> CreatePipeline(TrailPipelineKey key, IShaderModule vertShader, IShaderModule fragShader)
	{
		// TrailVertex layout: Position(12) + TexCoord(8) + Color(4) = 24 bytes
		Sedulous.RHI.VertexAttribute[3] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),              // Position
			.(VertexFormat.Float2, 12, 1),             // TexCoord
			.(VertexFormat.UByte4Normalized, 20, 2)    // Color
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(TrailVertex.Stride, vertexAttrs, .Vertex)
		);

		// Depth state
		DepthStencilState depthState = .();
		if (key.HasDepth)
		{
			depthState.DepthTestEnabled = true;
			depthState.DepthWriteEnabled = false; // Trails don't write depth
			depthState.DepthCompare = .Less;
			depthState.Format = mDepthFormat;
		}
		else
		{
			depthState.DepthTestEnabled = false;
			depthState.DepthWriteEnabled = false;
			depthState.Format = .Undefined;
		}

		// Blend state based on mode
		BlendState blendState = GetBlendState(key.BlendMode);

		ColorTargetState[1] colorTargets = .(ColorTargetState(mColorFormat, blendState));

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

		switch (mDevice.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): return .Ok(pipeline);
		case .Err: return .Err;
		}
	}

	private BlendState GetBlendState(ParticleBlendMode mode)
	{
		switch (mode)
		{
		case .Additive:
			BlendState additive = .();
			additive.Color = .(.Add, .SrcAlpha, .One);
			additive.Alpha = .(.Add, .One, .One);
			return additive;

		case .Multiply:
			BlendState multiply = .();
			multiply.Color = .(.Add, .Dst, .Zero);
			multiply.Alpha = .(.Add, .DstAlpha, .Zero);
			return multiply;

		case .PremultipliedAlpha:
			BlendState premult = .();
			premult.Color = .(.Add, .One, .OneMinusSrcAlpha);
			premult.Alpha = .(.Add, .One, .OneMinusSrcAlpha);
			return premult;

		default: // AlphaBlend
			return .AlphaBlend;
		}
	}

	/// Begins trail collection for a new frame.
	public void BeginFrame(float currentTime)
	{
		mBatches.Clear();
		mVertexAllocation = .();
		mCurrentTime = currentTime;
		Stats = .();
	}

	/// Prepares a trail emitter for rendering.
	public void PrepareTrail(TrailEmitter trail)
	{
		if (trail == null || !trail.HasPoints || trail.PointCount < 2)
			return;

		// Generate vertices to staging buffer
		int32 vertexCount = trail.WriteVertices(mStagingVertices, mCurrentTime);
		if (vertexCount < 4)  // Need at least 2 segments for a strip
			return;

		// Allocate from transient pool
		let allocation = mRenderer.TransientBuffers.AllocateVertices<TrailVertex>(vertexCount);
		if (!allocation.IsValid)
			return;

		// Copy vertices to transient buffer
		let ptr = allocation.GetPtr<TrailVertex>();
		Internal.MemCpy(ptr, mStagingVertices.Ptr, sizeof(TrailVertex) * vertexCount);

		// Create batch
		TrailDrawBatch batch;
		batch.Trail = trail;
		batch.VertexOffset = allocation.Offset;
		batch.VertexCount = (uint32)vertexCount;
		batch.BlendMode = trail.Settings.BlendMode;

		mBatches.Add(batch);

		var stats = Stats;
		stats.TrailCount++;
		stats.VertexCount += vertexCount;
		stats.VertexBytesUsed += allocation.Size;
		Stats = stats;
	}

	/// Prepares multiple trails from a trail manager.
	public void PrepareTrails(TrailManager manager)
	{
		if (manager == null)
			return;

		for (let trail in manager.Trails)
			PrepareTrail(trail);
	}

	/// Updates uniform buffer.
	public void UpdateUniforms(bool useTexture, float softEdge)
	{
		TrailUniforms uniforms = .();
		uniforms.Params = .(useTexture ? 1.0f : 0.0f, softEdge, 0, 0);

		Span<uint8> data = .((uint8*)&uniforms, (int)TrailUniforms.Size);
		mDevice.Queue.WriteBuffer(mUniformBuffer, 0, data);
	}

	/// Renders all prepared trails.
	public void Render(IRenderPassEncoder renderPass, IBindGroup bindGroup, bool hasDepth = true,
					   IShaderModule vertShader = null, IShaderModule fragShader = null)
	{
		if (!mInitialized || mBatches.Count == 0)
			return;

		if (vertShader == null || fragShader == null)
			return;

		// Sort batches by blend mode
		mBatches.Sort(scope (a, b) => (int)a.BlendMode <=> (int)b.BlendMode);

		ParticleBlendMode currentBlend = .AlphaBlend;
		IRenderPipeline currentPipeline = null;
		bool firstBatch = true;

		// Set bind group once
		if (bindGroup != null)
			renderPass.SetBindGroup(0, bindGroup, .());

		for (let batch in mBatches)
		{
			// Switch pipeline if needed
			if (firstBatch || batch.BlendMode != currentBlend)
			{
				TrailPipelineKey key;
				key.BlendMode = batch.BlendMode;
				key.HasDepth = hasDepth;

				let pipelineResult = GetOrCreatePipeline(key, vertShader, fragShader);
				if (pipelineResult case .Err)
					continue;

				let pipeline = pipelineResult.Get();
				if (pipeline != currentPipeline)
				{
					renderPass.SetPipeline(pipeline);
					currentPipeline = pipeline;
					Stats.PipelineSwitches++;
				}

				currentBlend = batch.BlendMode;
				firstBatch = false;
			}

			// Set vertex buffer from transient pool
			let vertexBuffer = mRenderer.TransientBuffers.VertexBuffer.Buffer;
			renderPass.SetVertexBuffer(0, vertexBuffer, batch.VertexOffset);

			// Draw triangle strip
			renderPass.Draw(batch.VertexCount, 1, 0, 0);
			Stats.DrawCalls++;
		}
	}

	/// Gets the bind group layout for external bind group creation.
	public IBindGroupLayout BindGroupLayout => mBindGroupLayout;

	/// Gets default texture view.
	public ITextureView DefaultTextureView => mDefaultTextureView;

	/// Gets default sampler.
	public ISampler DefaultSampler => mDefaultSampler;

	/// Gets uniform buffer.
	public IBuffer UniformBuffer => mUniformBuffer;

	/// Returns true if initialized.
	public bool IsInitialized => mInitialized;

	/// Gets statistics string.
	public void GetStats(String outStats)
	{
		let stats = Stats;
		outStats.AppendF("Trail Draw System:\n");
		outStats.AppendF("  Trails: {}\n", stats.TrailCount);
		outStats.AppendF("  Vertices: {}\n", stats.VertexCount);
		outStats.AppendF("  Draw calls: {}\n", stats.DrawCalls);
		outStats.AppendF("  Pipeline switches: {}\n", stats.PipelineSwitches);
		outStats.AppendF("  Vertex bytes: {}\n", stats.VertexBytesUsed);
	}

	public void Dispose()
	{
		// Resources cleaned up by destructor
	}

	// ========================================================================
	// Render Graph Integration
	// ========================================================================

	/// Data for trail pass execution.
	private struct TrailPassData
	{
		public TrailDrawSystem DrawSystem;
		public IBindGroup BindGroup;
		public IShaderModule VertexShader;
		public IShaderModule FragmentShader;
		public bool HasDepth;
	}

	/// Adds a trail rendering pass to the render graph.
	/// Trails are rendered as transparent with depth read (no write).
	public PassBuilder AddPass(
		RenderGraph graph,
		RGResourceHandle colorTarget,
		RGResourceHandle depthTarget,
		IBindGroup bindGroup,
		IShaderModule vertShader,
		IShaderModule fragShader)
	{
		TrailPassData passData;
		passData.DrawSystem = this;
		passData.BindGroup = bindGroup;
		passData.VertexShader = vertShader;
		passData.FragmentShader = fragShader;
		passData.HasDepth = true;

		return graph.AddGraphicsPass("Trails")
			.SetColorAttachment(0, colorTarget, .Load, .Store)
			.SetDepthAttachmentReadOnly(depthTarget)
			.SetFlags(.NeverCull)
			.SetExecute(new (encoder) => {
				passData.DrawSystem.Render(
					encoder,
					passData.BindGroup,
					passData.HasDepth,
					passData.VertexShader,
					passData.FragmentShader);
			});
	}

	/// Adds a trail rendering pass without depth testing.
	public PassBuilder AddPassNoDepth(
		RenderGraph graph,
		RGResourceHandle colorTarget,
		IBindGroup bindGroup,
		IShaderModule vertShader,
		IShaderModule fragShader)
	{
		TrailPassData passData;
		passData.DrawSystem = this;
		passData.BindGroup = bindGroup;
		passData.VertexShader = vertShader;
		passData.FragmentShader = fragShader;
		passData.HasDepth = false;

		return graph.AddGraphicsPass("TrailsNoDepth")
			.SetColorAttachment(0, colorTarget, .Load, .Store)
			.SetFlags(.NeverCull)
			.SetExecute(new (encoder) => {
				passData.DrawSystem.Render(
					encoder,
					passData.BindGroup,
					passData.HasDepth,
					passData.VertexShader,
					passData.FragmentShader);
			});
	}
}

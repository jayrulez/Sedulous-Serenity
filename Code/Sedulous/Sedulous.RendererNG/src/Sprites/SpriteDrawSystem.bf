namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Manages sprite rendering with texture batching and transient buffers.
class SpriteDrawSystem : IDisposable
{
	private IDevice mDevice;
	private Renderer mRenderer;

	// Pipeline cache (blend mode × depth)
	private Dictionary<SpritePipelineKey, IRenderPipeline> mPipelineCache = new .() ~ {
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

	// Shared index buffer (quad indices for max sprites)
	private IBuffer mSharedIndexBuffer ~ delete _;
	private int32 mMaxSpritesInIndexBuffer;

	// Per-frame data
	private List<SpriteProxy> mSprites = new .() ~ delete _;
	private List<SpriteDrawBatch> mBatches = new .() ~ delete _;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mInitialized = false;

	// Statistics
	public SpriteStats Stats { get; private set; }

	public const int32 DefaultMaxSprites = 10000;

	public this(Renderer renderer)
	{
		mRenderer = renderer;
		mDevice = null;
	}

	/// Initializes the sprite draw system.
	public Result<void> Initialize(IDevice device, TextureFormat colorFormat, TextureFormat depthFormat)
	{
		mDevice = device;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		if (CreateDefaultResources() case .Err)
			return .Err;

		if (CreateBindGroupLayout() case .Err)
			return .Err;

		if (CreateSharedIndexBuffer(DefaultMaxSprites) case .Err)
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
		// b0 = scene uniforms, b1 = sprite uniforms
		// t0 = sprite texture, s0 = sampler
		BindGroupLayoutEntry[4] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),
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

	private Result<void> CreateSharedIndexBuffer(int32 maxSprites)
	{
		mMaxSpritesInIndexBuffer = maxSprites;
		let indexCount = maxSprites * 6;
		let indexSize = (uint64)(sizeof(uint16) * indexCount);

		var bufDesc = BufferDescriptor(indexSize, .Index, .Upload);
		switch (mDevice.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mSharedIndexBuffer = buf;
		case .Err: return .Err;
		}

		uint16[] indices = new uint16[indexCount];
		defer delete indices;

		for (int32 i = 0; i < maxSprites; i++)
		{
			int32 baseVertex = i * 4;
			int32 baseIndex = i * 6;
			indices[baseIndex + 0] = (uint16)(baseVertex + 0);
			indices[baseIndex + 1] = (uint16)(baseVertex + 1);
			indices[baseIndex + 2] = (uint16)(baseVertex + 2);
			indices[baseIndex + 3] = (uint16)(baseVertex + 2);
			indices[baseIndex + 4] = (uint16)(baseVertex + 1);
			indices[baseIndex + 5] = (uint16)(baseVertex + 3);
		}

		Span<uint8> data = .((uint8*)indices.Ptr, (int)indexSize);
		mDevice.Queue.WriteBuffer(mSharedIndexBuffer, 0, data);

		return .Ok;
	}

	/// Gets or creates a pipeline for the given configuration.
	private Result<IRenderPipeline> GetOrCreatePipeline(SpritePipelineKey key, IShaderModule vertShader, IShaderModule fragShader)
	{
		if (mPipelineCache.TryGetValue(key, let existing))
			return .Ok(existing);

		let pipeline = CreatePipeline(key, vertShader, fragShader);
		if (pipeline case .Err)
			return .Err;

		mPipelineCache[key] = pipeline.Get();
		return pipeline;
	}

	private Result<IRenderPipeline> CreatePipeline(SpritePipelineKey key, IShaderModule vertShader, IShaderModule fragShader)
	{
		// Vertex layout (48 bytes per sprite vertex)
		Sedulous.RHI.VertexAttribute[6] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),              // Position
			.(VertexFormat.Float2, 12, 1),            // Size
			.(VertexFormat.UByte4Normalized, 20, 2),  // Color
			.(VertexFormat.Float, 24, 3),             // Rotation
			.(VertexFormat.Float4, 28, 4),            // UVRect
			.(VertexFormat.UInt, 44, 5)               // Flags
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(SpriteVertex.Stride, vertexAttrs, .Instance)
		);

		// Depth state
		DepthStencilState depthState = .();
		if (key.HasDepth)
		{
			depthState.DepthTestEnabled = true;
			depthState.DepthWriteEnabled = false; // Sprites don't write depth
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
				Topology = .TriangleList,
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

	/// Begins sprite collection for a new frame.
	public void BeginFrame()
	{
		mSprites.Clear();
		mBatches.Clear();
		Stats = .();
	}

	/// Adds a sprite for rendering.
	public void AddSprite(SpriteProxy sprite)
	{
		if (!sprite.IsVisible)
			return;

		mSprites.Add(sprite);
	}

	/// Adds multiple sprites for rendering.
	public void AddSprites(Span<SpriteProxy> sprites)
	{
		for (let sprite in sprites)
		{
			if (sprite.IsVisible)
				mSprites.Add(sprite);
		}
	}

	/// Prepares all collected sprites for rendering.
	/// Call this after adding all sprites and before Render().
	public void Prepare(Vector3 cameraPosition)
	{
		if (mSprites.Count == 0)
			return;

		// Sort sprites: first by blend mode, then by texture for batching
		mSprites.Sort(scope (a, b) =>
		{
			// Sort by blend mode first
			int blendCmp = (int)a.BlendMode <=> (int)b.BlendMode;
			if (blendCmp != 0)
				return blendCmp;

			// Then by texture
			int texCmp = (int)a.TextureHandle <=> (int)b.TextureHandle;
			if (texCmp != 0)
				return texCmp;

			// Then by sort key
			return (int)a.SortKey <=> (int)b.SortKey;
		});

		// Create batches grouped by texture and blend mode
		int batchStart = 0;
		uint32 currentTexture = mSprites[0].TextureHandle;
		ParticleBlendMode currentBlend = mSprites[0].BlendMode;

		for (int i = 1; i <= mSprites.Count; i++)
		{
			bool endBatch = (i == mSprites.Count);
			if (!endBatch)
			{
				let sprite = mSprites[i];
				if (sprite.TextureHandle != currentTexture || sprite.BlendMode != currentBlend)
					endBatch = true;
			}

			if (endBatch)
			{
				int batchCount = i - batchStart;

				// Allocate vertex space from transient pool
				let allocation = mRenderer.TransientBuffers.AllocateVertices<SpriteVertex>(batchCount);
				if (!allocation.IsValid)
				{
					batchStart = i;
					if (i < mSprites.Count)
					{
						currentTexture = mSprites[i].TextureHandle;
						currentBlend = mSprites[i].BlendMode;
					}
					continue;
				}

				// Write vertices
				let ptr = allocation.GetPtr<SpriteVertex>();
				for (int j = 0; j < batchCount; j++)
				{
					ptr[j] = SpriteVertex(mSprites[batchStart + j]);
				}

				// Create batch
				SpriteDrawBatch batch;
				batch.TextureHandle = currentTexture;
				batch.VertexOffset = allocation.Offset;
				batch.SpriteCount = (uint32)batchCount;
				batch.BlendMode = currentBlend;
				mBatches.Add(batch);

				var stats = Stats;
				stats.SpriteCount += (int32)batchCount;
				stats.BatchCount++;
				stats.VertexBytesUsed += allocation.Size;
				Stats = stats;

				batchStart = i;
				if (i < mSprites.Count)
				{
					currentTexture = mSprites[i].TextureHandle;
					currentBlend = mSprites[i].BlendMode;
				}
			}
		}
	}

	/// Renders all prepared sprites.
	public void Render(IRenderPassEncoder renderPass, IBuffer sceneBuffer, bool hasDepth = true,
					   IShaderModule vertShader = null, IShaderModule fragShader = null)
	{
		if (!mInitialized || mBatches.Count == 0)
			return;

		if (vertShader == null || fragShader == null)
			return;

		ParticleBlendMode currentBlend = .AlphaBlend;
		IRenderPipeline currentPipeline = null;
		bool firstBatch = true;

		for (let batch in mBatches)
		{
			// Switch pipeline if blend mode changed
			if (firstBatch || batch.BlendMode != currentBlend)
			{
				SpritePipelineKey key;
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
			renderPass.SetIndexBuffer(mSharedIndexBuffer, .UInt16, 0);

			// Draw
			renderPass.DrawIndexed(6, batch.SpriteCount, 0, 0, 0);
			Stats.DrawCalls++;
		}
	}

	/// Gets the bind group layout for external bind group creation.
	public IBindGroupLayout BindGroupLayout => mBindGroupLayout;

	/// Gets default texture view.
	public ITextureView DefaultTextureView => mDefaultTextureView;

	/// Gets default sampler.
	public ISampler DefaultSampler => mDefaultSampler;

	/// Returns true if initialized.
	public bool IsInitialized => mInitialized;

	/// Gets statistics string.
	public void GetStats(String outStats)
	{
		let stats = Stats;
		outStats.AppendF("Sprite Draw System:\n");
		outStats.AppendF("  Sprites: {}\n", stats.SpriteCount);
		outStats.AppendF("  Batches: {}\n", stats.BatchCount);
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

	/// Adds a sprite rendering pass to the render graph.
	/// Sprites are rendered as transparent with depth read (no write).
	public PassBuilder AddPass(
		RenderGraph graph,
		RGResourceHandle colorTarget,
		RGResourceHandle depthTarget,
		IBuffer sceneBuffer,
		IShaderModule vertShader,
		IShaderModule fragShader)
	{
		SpritePassData passData;
		passData.DrawSystem = this;
		passData.SceneBuffer = sceneBuffer;
		passData.VertexShader = vertShader;
		passData.FragmentShader = fragShader;
		passData.HasDepth = true;

		return graph.AddGraphicsPass("Sprites")
			.SetColorAttachment(0, colorTarget, .Load, .Store)
			.SetDepthAttachmentReadOnly(depthTarget)
			.SetFlags(.NeverCull)
			.SetExecute(new (encoder) => {
				passData.DrawSystem.Render(
					encoder,
					passData.SceneBuffer,
					passData.HasDepth,
					passData.VertexShader,
					passData.FragmentShader);
			});
	}

	/// Adds a sprite rendering pass without depth testing (for UI/2D sprites).
	public PassBuilder AddPassNoDepth(
		RenderGraph graph,
		RGResourceHandle colorTarget,
		IBuffer sceneBuffer,
		IShaderModule vertShader,
		IShaderModule fragShader)
	{
		SpritePassData passData;
		passData.DrawSystem = this;
		passData.SceneBuffer = sceneBuffer;
		passData.VertexShader = vertShader;
		passData.FragmentShader = fragShader;
		passData.HasDepth = false;

		return graph.AddGraphicsPass("SpritesNoDepth")
			.SetColorAttachment(0, colorTarget, .Load, .Store)
			.SetFlags(.NeverCull)
			.SetExecute(new (encoder) => {
				passData.DrawSystem.Render(
					encoder,
					passData.SceneBuffer,
					passData.HasDepth,
					passData.VertexShader,
					passData.FragmentShader);
			});
	}
}

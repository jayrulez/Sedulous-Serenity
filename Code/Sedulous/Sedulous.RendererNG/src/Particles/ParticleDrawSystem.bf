namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Key for particle pipeline caching.
struct ParticlePipelineKey : IHashable
{
	public ParticleBlendMode BlendMode;
	public bool HasDepth;
	public bool SoftParticles;

	public int GetHashCode()
	{
		int hash = (int)BlendMode;
		hash = hash * 31 + (HasDepth ? 1 : 0);
		hash = hash * 31 + (SoftParticles ? 1 : 0);
		return hash;
	}
}

/// Draw batch for particles.
struct ParticleDrawBatch
{
	public ParticleEmitter Emitter;
	public uint32 VertexOffset;
	public uint32 VertexCount;
	public uint32 IndexOffset;
	public ParticleBlendMode BlendMode;
	public bool SoftParticles;
}

/// Statistics for particle rendering.
struct ParticleStats
{
	public int32 EmitterCount;
	public int32 ParticleCount;
	public int32 DrawCalls;
	public int32 PipelineSwitches;
	public uint64 VertexBytesUsed;
}

/// Manages particle rendering with transient buffers and parametric pipelines.
class ParticleDrawSystem : IDisposable
{
	private IDevice mDevice;
	private Renderer mRenderer;

	// Pipeline cache (blend mode × depth × soft particles)
	private Dictionary<ParticlePipelineKey, IRenderPipeline> mPipelineCache = new .() ~ {
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

	// Uniform buffer for particle settings
	private IBuffer mUniformBuffer ~ delete _;

	// Depth sampler for soft particles
	private ISampler mDepthSampler ~ delete _;

	// Shared index buffer (quad indices for max particles)
	private IBuffer mSharedIndexBuffer ~ delete _;
	private int32 mMaxParticlesInIndexBuffer;

	// Per-frame data
	private List<ParticleDrawBatch> mBatches = new .() ~ delete _;
	private TransientAllocation mVertexAllocation;
	private TransientAllocation mUniformAllocation;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mInitialized = false;

	// Statistics
	public ParticleStats Stats { get; private set; }

	public const int32 DefaultMaxParticles = 50000;

	public this(Renderer renderer)
	{
		mRenderer = renderer;
		mDevice = null;
	}

	/// Initializes the particle draw system.
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

		if (CreateSharedIndexBuffer(DefaultMaxParticles) case .Err)
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

		// Create depth sampler for soft particles (nearest filtering for depth)
		var depthSamplerDesc = SamplerDescriptor();
		depthSamplerDesc.MinFilter = .Nearest;
		depthSamplerDesc.MagFilter = .Nearest;
		depthSamplerDesc.AddressModeU = .ClampToEdge;
		depthSamplerDesc.AddressModeV = .ClampToEdge;
		switch (mDevice.CreateSampler(&depthSamplerDesc))
		{
		case .Ok(let sampler): mDepthSampler = sampler;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateUniformBuffer()
	{
		var bufDesc = BufferDescriptor(ParticleUniforms.Size, .Uniform, .Upload);
		switch (mDevice.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mUniformBuffer = buf;
		case .Err: return .Err;
		}
		return .Ok;
	}

	private Result<void> CreateBindGroupLayout()
	{
		// b0 = scene uniforms, b1 = particle uniforms
		// t0 = particle texture, s0 = sampler
		// t1 = depth texture (soft particles), s1 = depth sampler
		BindGroupLayoutEntry[6] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),
			BindGroupLayoutEntry.Sampler(0, .Fragment),
			BindGroupLayoutEntry.SampledTexture(1, .Fragment),
			BindGroupLayoutEntry.Sampler(1, .Fragment)
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

	private Result<void> CreateSharedIndexBuffer(int32 maxParticles)
	{
		mMaxParticlesInIndexBuffer = maxParticles;
		let indexCount = maxParticles * 6;
		let indexSize = (uint64)(sizeof(uint16) * indexCount);

		var bufDesc = BufferDescriptor(indexSize, .Index, .Upload);
		switch (mDevice.CreateBuffer(&bufDesc))
		{
		case .Ok(let buf): mSharedIndexBuffer = buf;
		case .Err: return .Err;
		}

		uint16[] indices = new uint16[indexCount];
		defer delete indices;

		for (int32 i = 0; i < maxParticles; i++)
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
	private Result<IRenderPipeline> GetOrCreatePipeline(ParticlePipelineKey key, IShaderModule vertShader, IShaderModule fragShader)
	{
		if (mPipelineCache.TryGetValue(key, let existing))
			return .Ok(existing);

		// Create pipeline
		let pipeline = CreatePipeline(key, vertShader, fragShader);
		if (pipeline case .Err)
			return .Err;

		mPipelineCache[key] = pipeline.Get();
		return pipeline;
	}

	private Result<IRenderPipeline> CreatePipeline(ParticlePipelineKey key, IShaderModule vertShader, IShaderModule fragShader)
	{
		// Vertex layout (52 bytes per particle vertex)
		Sedulous.RHI.VertexAttribute[7] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),              // Position
			.(VertexFormat.Float2, 12, 1),             // Size
			.(VertexFormat.UByte4Normalized, 20, 2),   // Color
			.(VertexFormat.Float, 24, 3),              // Rotation
			.(VertexFormat.Float2, 28, 4),             // TexCoordOffset
			.(VertexFormat.Float2, 36, 5),             // TexCoordScale
			.(VertexFormat.Float2, 44, 6)              // Velocity2D
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(ParticleVertex.Stride, vertexAttrs, .Instance)
		);

		// Depth state
		DepthStencilState depthState = .();
		if (key.HasDepth)
		{
			depthState.DepthTestEnabled = true;
			depthState.DepthWriteEnabled = false; // Particles don't write depth
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

	/// Begins particle collection for a new frame.
	public void BeginFrame()
	{
		mBatches.Clear();
		mVertexAllocation = .();
		mUniformAllocation = .();
		Stats = .();
	}

	/// Prepares an emitter for rendering. Call for each visible emitter.
	public void PrepareEmitter(ParticleEmitter emitter)
	{
		if (emitter == null || emitter.ParticleCount == 0)
			return;

		let config = emitter.Config;
		if (config == null)
			return;

		// Sort if needed
		if (config.SortParticles && config.BlendMode == .AlphaBlend)
			emitter.SortByDistance();

		// Allocate vertex space from transient pool
		let vertexCount = (uint32)emitter.ParticleCount;

		let allocation = mRenderer.TransientBuffers.AllocateVertices<ParticleVertex>(emitter.ParticleCount);
		if (!allocation.IsValid)
			return;

		// Write vertices to transient buffer
		let ptr = allocation.GetPtr<ParticleVertex>();
		Span<ParticleVertex> vertexSpan = .(ptr, emitter.ParticleCount);
		emitter.WriteVertices(vertexSpan);

		// Create batch
		ParticleDrawBatch batch;
		batch.Emitter = emitter;
		batch.VertexOffset = allocation.Offset;
		batch.VertexCount = vertexCount;
		batch.IndexOffset = 0;
		batch.BlendMode = config.BlendMode;
		batch.SoftParticles = config.SoftParticles;

		mBatches.Add(batch);

		var stats = Stats;
		stats.EmitterCount++;
		stats.ParticleCount += emitter.ParticleCount;
		stats.VertexBytesUsed += allocation.Size;
		Stats = stats;
	}

	/// Renders all prepared particles.
	public void Render(IRenderPassEncoder renderPass, IBuffer sceneBuffer, bool hasDepth = true,
					   ITextureView depthTexture = null, IShaderModule vertShader = null, IShaderModule fragShader = null)
	{
		if (!mInitialized || mBatches.Count == 0)
			return;

		if (vertShader == null || fragShader == null)
			return; // Need shaders

		// Sort batches by blend mode to minimize pipeline switches
		mBatches.Sort(scope (a, b) => (int)a.BlendMode <=> (int)b.BlendMode);

		ParticleBlendMode currentBlend = .AlphaBlend;
		bool currentSoft = false;
		IRenderPipeline currentPipeline = null;
		bool firstBatch = true;

		for (let batch in mBatches)
		{
			// Switch pipeline if needed
			if (firstBatch || batch.BlendMode != currentBlend || batch.SoftParticles != currentSoft)
			{
				ParticlePipelineKey key;
				key.BlendMode = batch.BlendMode;
				key.HasDepth = hasDepth;
				key.SoftParticles = batch.SoftParticles;

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
				currentSoft = batch.SoftParticles;
				firstBatch = false;
			}

			// Set vertex buffer from transient pool
			let vertexBuffer = mRenderer.TransientBuffers.VertexBuffer.Buffer;
			renderPass.SetVertexBuffer(0, vertexBuffer, batch.VertexOffset);
			renderPass.SetIndexBuffer(mSharedIndexBuffer, .UInt16, 0);

			// Draw
			renderPass.DrawIndexed(6, batch.VertexCount, 0, 0, 0);
			Stats.DrawCalls++;
		}
	}

	/// Gets the bind group layout for external bind group creation.
	public IBindGroupLayout BindGroupLayout => mBindGroupLayout;

	/// Gets default texture view (for particles without custom texture).
	public ITextureView DefaultTextureView => mDefaultTextureView;

	/// Gets default sampler.
	public ISampler DefaultSampler => mDefaultSampler;

	/// Gets depth sampler for soft particles.
	public ISampler DepthSampler => mDepthSampler;

	/// Gets uniform buffer.
	public IBuffer UniformBuffer => mUniformBuffer;

	/// Returns true if initialized.
	public bool IsInitialized => mInitialized;

	// ========================================================================
	// Soft Particle Support
	// ========================================================================

	/// Updates particle uniforms. Call before rendering each frame.
	public void UpdateUniforms(ParticleRenderMode renderMode, float stretchFactor, float minStretchLength,
							   bool useTexture, bool softParticlesEnabled, float softParticleDistance,
							   float nearPlane, float farPlane)
	{
		ParticleUniforms uniforms = .();
		uniforms.RenderMode = (uint32)renderMode;
		uniforms.StretchFactor = stretchFactor;
		uniforms.MinStretchLength = minStretchLength;
		uniforms.UseTexture = useTexture ? 1u : 0u;
		uniforms.SoftParticlesEnabled = softParticlesEnabled ? 1u : 0u;
		uniforms.SoftParticleDistance = softParticleDistance;
		uniforms.NearPlane = nearPlane;
		uniforms.FarPlane = farPlane;

		Span<uint8> data = .((uint8*)&uniforms, (int)ParticleUniforms.Size);
		mDevice.Queue.WriteBuffer(mUniformBuffer, 0, data);
	}

	/// Updates uniforms with default values and soft particle settings.
	public void UpdateUniformsDefault(bool softParticlesEnabled = false, float softParticleDistance = 0.5f,
									  float nearPlane = 0.1f, float farPlane = 1000.0f)
	{
		UpdateUniforms(.Billboard, 1.0f, 0.1f, false, softParticlesEnabled, softParticleDistance, nearPlane, farPlane);
	}

	/// Creates a bind group for particle rendering without soft particles.
	public Result<IBindGroup> CreateBindGroup(IBuffer sceneBuffer, ITextureView particleTexture = null)
	{
		let tex = particleTexture != null ? particleTexture : mDefaultTextureView;

		BindGroupEntry[6] entries = .(
			BindGroupEntry.Buffer(0, sceneBuffer),       // b0: scene uniforms
			BindGroupEntry.Buffer(1, mUniformBuffer),    // b1: particle uniforms
			BindGroupEntry.Texture(0, tex),              // t0: particle texture
			BindGroupEntry.Sampler(0, mDefaultSampler),  // s0: texture sampler
			BindGroupEntry.Texture(1, mDefaultTextureView), // t1: depth (placeholder)
			BindGroupEntry.Sampler(1, mDepthSampler)     // s1: depth sampler
		);

		BindGroupDescriptor desc = .(mBindGroupLayout, entries);
		switch (mDevice.CreateBindGroup(&desc))
		{
		case .Ok(let group): return .Ok(group);
		case .Err: return .Err;
		}
	}

	/// Creates a bind group for particle rendering with soft particles.
	/// depthTexture: The scene depth texture for soft particle fading.
	public Result<IBindGroup> CreateBindGroupWithDepth(IBuffer sceneBuffer, ITextureView depthTexture,
													   ITextureView particleTexture = null)
	{
		let tex = particleTexture != null ? particleTexture : mDefaultTextureView;

		BindGroupEntry[6] entries = .(
			BindGroupEntry.Buffer(0, sceneBuffer),       // b0: scene uniforms
			BindGroupEntry.Buffer(1, mUniformBuffer),    // b1: particle uniforms
			BindGroupEntry.Texture(0, tex),              // t0: particle texture
			BindGroupEntry.Sampler(0, mDefaultSampler),  // s0: texture sampler
			BindGroupEntry.Texture(1, depthTexture),     // t1: depth texture for soft particles
			BindGroupEntry.Sampler(1, mDepthSampler)     // s1: depth sampler
		);

		BindGroupDescriptor desc = .(mBindGroupLayout, entries);
		switch (mDevice.CreateBindGroup(&desc))
		{
		case .Ok(let group): return .Ok(group);
		case .Err: return .Err;
		}
	}

	/// Renders particles with a pre-created bind group.
	/// Use this overload when you need soft particles and have created the bind group with CreateBindGroupWithDepth.
	public void RenderWithBindGroup(IRenderPassEncoder renderPass, IBindGroup bindGroup, bool hasDepth = true,
									IShaderModule vertShader = null, IShaderModule fragShader = null)
	{
		if (!mInitialized || mBatches.Count == 0)
			return;

		if (vertShader == null || fragShader == null)
			return;

		// Sort batches by blend mode
		mBatches.Sort(scope (a, b) => (int)a.BlendMode <=> (int)b.BlendMode);

		ParticleBlendMode currentBlend = .AlphaBlend;
		bool currentSoft = false;
		IRenderPipeline currentPipeline = null;
		bool firstBatch = true;
		bool bindGroupSet = false;

		for (let batch in mBatches)
		{
			// Switch pipeline if needed
			if (firstBatch || batch.BlendMode != currentBlend || batch.SoftParticles != currentSoft)
			{
				ParticlePipelineKey key;
				key.BlendMode = batch.BlendMode;
				key.HasDepth = hasDepth;
				key.SoftParticles = batch.SoftParticles;

				let pipelineResult = GetOrCreatePipeline(key, vertShader, fragShader);
				if (pipelineResult case .Err)
					continue;

				let pipeline = pipelineResult.Get();
				if (pipeline != currentPipeline)
				{
					renderPass.SetPipeline(pipeline);
					currentPipeline = pipeline;
					Stats.PipelineSwitches++;

					// Set bind group after first pipeline is bound
					if (!bindGroupSet)
					{
						renderPass.SetBindGroup(0, bindGroup, .());
						bindGroupSet = true;
					}
				}

				currentBlend = batch.BlendMode;
				currentSoft = batch.SoftParticles;
				firstBatch = false;
			}

			// Set vertex buffer from transient pool
			let vertexBuffer = mRenderer.TransientBuffers.VertexBuffer.Buffer;
			renderPass.SetVertexBuffer(0, vertexBuffer, batch.VertexOffset);
			renderPass.SetIndexBuffer(mSharedIndexBuffer, .UInt16, 0);

			// Draw
			renderPass.DrawIndexed(6, batch.VertexCount, 0, 0, 0);
			Stats.DrawCalls++;
		}
	}

	/// Gets statistics string.
	public void GetStats(String outStats)
	{
		let stats = Stats;
		outStats.AppendF("Particle Draw System:\n");
		outStats.AppendF("  Emitters: {}\n", stats.EmitterCount);
		outStats.AppendF("  Particles: {}\n", stats.ParticleCount);
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

	/// Adds a particle rendering pass to the render graph.
	/// Particles are rendered as transparent with depth read (no write).
	public PassBuilder AddPass(
		RenderGraph graph,
		RGResourceHandle colorTarget,
		RGResourceHandle depthTarget,
		IBuffer sceneBuffer,
		IShaderModule vertShader,
		IShaderModule fragShader,
		ITextureView depthTextureForSoft = null)
	{
		ParticlePassData passData;
		passData.DrawSystem = this;
		passData.SceneBuffer = sceneBuffer;
		passData.VertexShader = vertShader;
		passData.FragmentShader = fragShader;
		passData.DepthTexture = depthTextureForSoft;
		passData.HasDepth = true;

		var builder = graph.AddGraphicsPass("Particles")
			.SetColorAttachment(0, colorTarget, .Load, .Store)
			.SetDepthAttachmentReadOnly(depthTarget)
			.SetFlags(.NeverCull);

		// If using soft particles, declare depth texture as shader read
		if (depthTextureForSoft != null)
			builder.ReadTexture(depthTarget, .ShaderRead);

		return builder.SetExecute(new (encoder) => {
			passData.DrawSystem.Render(
				encoder,
				passData.SceneBuffer,
				passData.HasDepth,
				passData.DepthTexture,
				passData.VertexShader,
				passData.FragmentShader);
		});
	}

	/// Adds a particle rendering pass without depth testing (for UI/overlay particles).
	public PassBuilder AddPassNoDepth(
		RenderGraph graph,
		RGResourceHandle colorTarget,
		IBuffer sceneBuffer,
		IShaderModule vertShader,
		IShaderModule fragShader)
	{
		ParticlePassData passData;
		passData.DrawSystem = this;
		passData.SceneBuffer = sceneBuffer;
		passData.VertexShader = vertShader;
		passData.FragmentShader = fragShader;
		passData.DepthTexture = null;
		passData.HasDepth = false;

		return graph.AddGraphicsPass("ParticlesNoDepth")
			.SetColorAttachment(0, colorTarget, .Load, .Store)
			.SetFlags(.NeverCull)
			.SetExecute(new (encoder) => {
				passData.DrawSystem.Render(
					encoder,
					passData.SceneBuffer,
					passData.HasDepth,
					null,
					passData.VertexShader,
					passData.FragmentShader);
			});
	}

	/// Data for soft particle pass execution (with bind group).
	private struct SoftParticlePassData
	{
		public ParticleDrawSystem DrawSystem;
		public IBindGroup BindGroup;
		public IShaderModule VertexShader;
		public IShaderModule FragmentShader;
		public bool HasDepth;
	}

	/// Adds a soft particle rendering pass to the render graph.
	/// This pass reads the depth buffer to fade particles near geometry.
	/// Usage:
	/// 1. Render opaque geometry first (writes to depth)
	/// 2. Call this pass (reads depth for soft particle fading)
	public PassBuilder AddSoftParticlePass(
		RenderGraph graph,
		RGResourceHandle colorTarget,
		RGResourceHandle depthTarget,
		IBindGroup bindGroup,
		IShaderModule vertShader,
		IShaderModule fragShader)
	{
		SoftParticlePassData passData;
		passData.DrawSystem = this;
		passData.BindGroup = bindGroup;
		passData.VertexShader = vertShader;
		passData.FragmentShader = fragShader;
		passData.HasDepth = true;

		return graph.AddGraphicsPass("SoftParticles")
			.SetColorAttachment(0, colorTarget, .Load, .Store)
			.SetDepthAttachmentReadOnly(depthTarget)
			.ReadTexture(depthTarget, .ShaderRead)
			.SetFlags(.NeverCull)
			.SetExecute(new (encoder) => {
				passData.DrawSystem.RenderWithBindGroup(
					encoder,
					passData.BindGroup,
					passData.HasDepth,
					passData.VertexShader,
					passData.FragmentShader);
			});
	}
}

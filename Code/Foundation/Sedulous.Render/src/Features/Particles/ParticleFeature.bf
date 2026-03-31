namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.Profiler;
using Sedulous.RenderGraph;

/// Unified particle render feature.
/// Supports both GPU compute and CPU simulation backends.
public class ParticleFeature : RenderFeatureBase
{
	// Compute pipelines (GPU backend)
	private IComputePipeline mSpawnPipeline;
	private IComputePipeline mUpdatePipeline;
	private IComputePipeline mCompactPipeline;
	private IComputePipeline mCounterResetPipeline;

	// GPU render pipelines (one per blend mode)
	private IRenderPipeline mGPURenderPipelineAlpha;
	private IRenderPipeline mGPURenderPipelineAdditive;
	private IRenderPipeline mGPURenderPipelinePremultiplied;
	private IRenderPipeline mGPURenderPipelineMultiply;

	// CPU render pipelines (one per blend mode, different vertex input)
	private IRenderPipeline mCPURenderPipelineAlpha;
	private IRenderPipeline mCPURenderPipelineAdditive;
	private IRenderPipeline mCPURenderPipelinePremultiplied;
	private IRenderPipeline mCPURenderPipelineMultiply;

	// Trail render pipelines (per-vertex input, reuses CPU bind group layout)
	private IRenderPipeline mTrailRenderPipelineAlpha;
	private IRenderPipeline mTrailRenderPipelineAdditive;

	// Bind groups
	private IBindGroupLayout mComputeBindGroupLayout;
	private IBindGroupLayout mGPURenderBindGroupLayout;
	private IBindGroupLayout mCPURenderBindGroupLayout;

	// Default particle resources
	private ITexture mDefaultParticleTexture;
	private ITextureView mDefaultParticleTextureView;
	private ISampler mDefaultSampler;

	// Fallback lighting buffers (used when ForwardOpaqueFeature lighting isn't available)
	private IBuffer mFallbackLightingBuffer;
	private IBuffer mFallbackLightDataBuffer;
	private IBuffer mFallbackClusterInfoBuffer;
	private IBuffer mFallbackLightIndexBuffer;

	// Emitter params dynamic uniform buffer (per-emitter, dynamic offset)
	private const uint64 EmitterParamAlignment = 256; // Vulkan minUniformBufferOffsetAlignment
	private const int32 MaxActiveEmitters = 64;
	private IBuffer mEmitterParamsBuffer;
	private Dictionary<ParticleEmitterProxyHandle, int32> mEmitterParamIndices = new .() ~ delete _;
	private Dictionary<TrailEmitterProxyHandle, int32> mTrailParamIndices = new .() ~ delete _;
	private int32 mEmitterParamCount;
	private RGHandle mDepthHandle = .Invalid;

	// Per-emitter GPU resources
	private Dictionary<ParticleEmitterProxyHandle, GPUParticleSystem> mGPUParticleSystems = new .() ~ DeleteDictionaryAndValues!(_);

	// Per-emitter CPU simulation state (owned by this feature, not the proxy)
	private Dictionary<ParticleEmitterProxyHandle, CPUParticleEmitter> mCPUEmitters = new .() ~ DeleteDictionaryAndValues!(_);

	// Deferred deletion for CPU emitters with in-flight GPU resources
	struct PendingEmitterDeletion
	{
		public CPUParticleEmitter Emitter;
		public int32 FramesRemaining;
	}
	private List<PendingEmitterDeletion> mPendingEmitterDeletions = new .() ~ {
		for (let pending in _)
			delete pending.Emitter;
		delete _;
	};

	// Per-frame active emitters
	private List<ParticleEmitterProxyHandle> mActiveGPUEmitters = new .() ~ delete _;
	private List<ParticleEmitterProxyHandle> mActiveCPUEmitters = new .() ~ delete _;
	private List<TrailEmitterProxyHandle> mActiveTrails = new .() ~ delete _;

	// Per-frame view dimensions
	private uint32 mViewWidth;
	private uint32 mViewHeight;
	private float mViewportX;
	private float mViewportY;

	// Per-frame/view cached context (set at start of AddPasses, used in render methods)
	private int32 mFrameIndex;
	private int32 mBindGroupIndex;
	private IBuffer mSceneUniformBuffer;
	private float mDeltaTime;
	private float mTotalTime;
	private float mNearPlane;
	private float mFarPlane;

	// Per-frame/view CPU emitter bind groups (per-emitter, per-frame, per-view)
	private Dictionary<ParticleEmitterProxyHandle, IBindGroup>[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mCPURenderBindGroups;

	// Per-frame/view bind groups for standalone trails (uses default texture, same layout)
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mTrailBindGroups;

	// RNG for sub-emitter probability checks
	private Random mSubEmitterRandom = new .() ~ delete _;

	public override void PrepareFrame(Span<RenderView> views, RenderWorld world, int32 frameIndex)
	{
		// Process deferred CPU emitter deletions
		for (int32 i = (int32)mPendingEmitterDeletions.Count - 1; i >= 0; i--)
		{
			var pending = ref mPendingEmitterDeletions[i];
			pending.FramesRemaining--;
			if (pending.FramesRemaining <= 0)
			{
				delete pending.Emitter;
				mPendingEmitterDeletions.RemoveAt(i);
			}
		}

		// Detect stale CPU emitter handles (proxy was destroyed) and queue deferred deletion
		{
			let staleHandles = scope List<ParticleEmitterProxyHandle>();
			for (let kv in mCPUEmitters)
			{
				if (world.GetParticleEmitter(kv.key) == null)
					staleHandles.Add(kv.key);
			}
			for (let handle in staleHandles)
			{
				if (mCPUEmitters.GetAndRemove(handle) case .Ok(let pair))
				{
					var pending = PendingEmitterDeletion();
					pending.Emitter = pair.value;
					pending.FramesRemaining = RenderConfig.FrameBufferCount + 1;
					mPendingEmitterDeletions.Add(pending);
				}
			}
		}

	}

	private void InitCPUBindGroupDicts()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
			mCPURenderBindGroups[i] = new .();
	}

	private void CleanupCPUBindGroupDicts()
	{
		let device = Renderer.Device;
		for (int i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mCPURenderBindGroups[i] != null)
			{
				for (let kv in mCPURenderBindGroups[i])
				{
					var bg = kv.value;
					device.DestroyBindGroup(ref bg);
				}
				delete mCPURenderBindGroups[i];
				mCPURenderBindGroups[i] = null;
			}
		}
	}

	/// Feature name.
	public override StringView Name => "Particles";

	/// Particles render after transparent.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardOpaque");
		//outDependencies.Add("ForwardTransparent");
	}

	protected override Result<void> OnInitialize(InitContext initCtx)
	{
		InitCPUBindGroupDicts();

		if (CreateDefaultResources(initCtx.TransferBatch) case .Err)
			return .Err;

		if (CreateComputePipelines() case .Err)
			return .Err;

		if (CreateRenderPipeline() case .Err)
			return .Err;

		if (CreateShaderPipelines() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateDefaultResources(ITransferBatch transferBatch)
	{
		// Create default white particle texture (64x64 soft circle)
		const int32 TexSize = 64;
		const int32 TexBytes = TexSize * TexSize * 4;

		TextureDesc texDesc = .()
		{
			Label = "Default Particle Texture",
			Width = TexSize,
			Height = TexSize,
			Depth = 1,
			Format = .RGBA8Unorm,
			MipLevelCount = 1,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (Renderer.Device.CreateTexture(texDesc))
		{
		case .Ok(let tex): mDefaultParticleTexture = tex;
		case .Err: return .Err;
		}

		// Fill with white pixels with soft Gaussian-like falloff
		uint8[] pixels = scope uint8[TexBytes];
		float center = (float)(TexSize - 1) * 0.5f;

		for (int32 y = 0; y < TexSize; y++)
		{
			for (int32 x = 0; x < TexSize; x++)
			{
				float dx = ((float)x - center) / center;
				float dy = ((float)y - center) / center;
				float distSq = dx * dx + dy * dy;

				float dist = Math.Sqrt(distSq);
				float alpha;
				if (dist >= 1.0f)
				{
					alpha = 0.0f;
				}
				else
				{
					float t = 1.0f - distSq;
					alpha = t * t;
				}

				uint8 a = (uint8)(alpha * 255.0f);

				int32 idx = (y * TexSize + x) * 4;
				pixels[idx] = 255;     // R
				pixels[idx + 1] = 255; // G
				pixels[idx + 2] = 255; // B
				pixels[idx + 3] = a;   // A
			}
		}

		var layout = TextureDataLayout() { BytesPerRow = TexSize * 4, RowsPerImage = TexSize };
		var writeSize = Extent3D(TexSize, TexSize, 1);
		transferBatch.WriteTexture(mDefaultParticleTexture, Span<uint8>(&pixels[0], TexBytes), layout, writeSize);

		// Create texture view
		TextureViewDesc viewDesc = .()
		{
			Label = "Default Particle Texture View",
			Dimension = .Texture2D
		};

		switch (Renderer.Device.CreateTextureView(mDefaultParticleTexture, viewDesc))
		{
		case .Ok(let view): mDefaultParticleTextureView = view;
		case .Err: return .Err;
		}

		// Create default sampler (linear, clamp)
		SamplerDesc samplerDesc = .()
		{
			Label = "Particle Sampler",
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge,
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear
		};

		switch (Renderer.Device.CreateSampler(samplerDesc))
		{
		case .Ok(let sampler): mDefaultSampler = sampler;
		case .Err: return .Err;
		}

		// Create emitter params dynamic uniform buffer (256-byte aligned slots for per-emitter params)
		BufferDesc emitterParamsDesc = .()
		{
			Label = "Emitter Params (Dynamic UBO)",
			Size = EmitterParamAlignment * MaxActiveEmitters,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(emitterParamsDesc))
		{
		case .Ok(let buf): mEmitterParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Create fallback lighting buffers (zeroed = 0 lights, no clusters)
		// Used when ForwardOpaqueFeature lighting isn't available yet
		BufferDesc fallbackLightingDesc = .()
		{
			Label = "Fallback Lighting UBO",
			Size = (uint64)LightingUniforms.Size,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};
		switch (Renderer.Device.CreateBuffer(fallbackLightingDesc))
		{
		case .Ok(let buf): mFallbackLightingBuffer = buf;
		case .Err: return .Err;
		}

		BufferDesc fallbackLightDataDesc = .()
		{
			Label = "Fallback Light Data",
			Size = 64,
			Usage = .Storage,
			Memory = .CpuToGpu
		};
		switch (Renderer.Device.CreateBuffer(fallbackLightDataDesc))
		{
		case .Ok(let buf): mFallbackLightDataBuffer = buf;
		case .Err: return .Err;
		}

		BufferDesc fallbackClusterInfoDesc = .()
		{
			Label = "Fallback Cluster Info",
			Size = 8,
			Usage = .Storage,
			Memory = .CpuToGpu
		};
		switch (Renderer.Device.CreateBuffer(fallbackClusterInfoDesc))
		{
		case .Ok(let buf): mFallbackClusterInfoBuffer = buf;
		case .Err: return .Err;
		}

		BufferDesc fallbackLightIndexDesc = .()
		{
			Label = "Fallback Light Index",
			Size = 4,
			Usage = .Storage,
			Memory = .CpuToGpu
		};
		switch (Renderer.Device.CreateBuffer(fallbackLightIndexDesc))
		{
		case .Ok(let buf): mFallbackLightIndexBuffer = buf;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private IPipelineLayout mComputePipelineLayout;
	private IPipelineLayout mGPURenderPipelineLayout;
	private IPipelineLayout mCPURenderPipelineLayout;

	private Result<void> CreateShaderPipelines()
	{
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Create compute pipeline layout
		IBindGroupLayout[1] computeLayouts = .(mComputeBindGroupLayout);
		PipelineLayoutDesc computeLayoutDesc = .(computeLayouts);
		switch (Renderer.Device.CreatePipelineLayout(computeLayoutDesc))
		{
		case .Ok(let layout): mComputePipelineLayout = layout;
		case .Err: return .Err;
		}

		// Load spawn compute shader
		let spawnResult = Renderer.ShaderSystem.GetShader("particle_spawn", .Compute);
		if (spawnResult case .Ok(let spawnShader))
		{
			ComputePipelineDesc spawnDesc = .(mComputePipelineLayout, spawnShader.Module);
			spawnDesc.Label = "Particle Spawn Pipeline";

			switch (Renderer.Device.CreateComputePipeline(spawnDesc))
			{
			case .Ok(let pipeline): mSpawnPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		// Load update compute shader
		let updateResult = Renderer.ShaderSystem.GetShader("particle_update", .Compute);
		if (updateResult case .Ok(let updateShader))
		{
			ComputePipelineDesc updateDesc = .(mComputePipelineLayout, updateShader.Module);
			updateDesc.Label = "Particle Update Pipeline";

			switch (Renderer.Device.CreateComputePipeline(updateDesc))
			{
			case .Ok(let pipeline): mUpdatePipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		// Load compact compute shader
		let compactResult = Renderer.ShaderSystem.GetShader("particle_compact", .Compute);
		if (compactResult case .Ok(let compactShader))
		{
			ComputePipelineDesc compactDesc = .(mComputePipelineLayout, compactShader.Module);
			compactDesc.Label = "Particle Compact Pipeline";

			switch (Renderer.Device.CreateComputePipeline(compactDesc))
			{
			case .Ok(let pipeline): mCompactPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		// Load counter reset compute shader (GPU-side reset avoids CPU/GPU race)
		let resetResult = Renderer.ShaderSystem.GetShader("particle_counter_reset", .Compute);
		if (resetResult case .Ok(let resetShader))
		{
			ComputePipelineDesc resetDesc = .(mComputePipelineLayout, resetShader.Module);
			resetDesc.Label = "Particle Counter Reset Pipeline";

			switch (Renderer.Device.CreateComputePipeline(resetDesc))
			{
			case .Ok(let pipeline): mCounterResetPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		// Create GPU render pipeline layout
		IBindGroupLayout[1] gpuRenderLayouts = .(mGPURenderBindGroupLayout);
		PipelineLayoutDesc gpuRenderLayoutDesc = .(gpuRenderLayouts);
		switch (Renderer.Device.CreatePipelineLayout(gpuRenderLayoutDesc))
		{
		case .Ok(let layout): mGPURenderPipelineLayout = layout;
		case .Err: return .Err;
		}

		Console.WriteLine(scope $"[Particles] Compute pipelines: Spawn={mSpawnPipeline != null} Update={mUpdatePipeline != null} Compact={mCompactPipeline != null} Reset={mCounterResetPipeline != null}");

		// Load GPU render shaders and create pipelines for each blend mode
		let gpuRenderResult = Renderer.ShaderSystem.GetShaderPair("particle");
		if (gpuRenderResult case .Ok(let shaders))
		{
			delegate void(BlendState, StringView, ref IRenderPipeline) createGPURenderPipeline = scope (blendMode, label, pipeline) => {
				ColorTargetState[1] colorTargets = .(
					.(.RGBA16Float, blendMode)
				);

				RenderPipelineDesc renderDesc = .()
				{
					Label = scope :: $"Particle GPU Render Pipeline ({label})",
					Layout = mGPURenderPipelineLayout,
					Vertex = .()
					{
						Shader = .(shaders.vert.Module, "main"),
						Buffers = default
					},
					Fragment = .()
					{
						Shader = .(shaders.frag.Module, "main"),
						Targets = colorTargets
					},
					Primitive = .()
					{
						Topology = .TriangleList,
						FrontFace = .CCW,
						CullMode = .None
					},
					DepthStencil = DepthStencilState.DepthReadOnly(Renderer.DepthFormat),
					Multisample = .()
					{
						Count = 1,
						Mask = uint32.MaxValue
					}
				};

				switch (Renderer.Device.CreateRenderPipeline(renderDesc))
				{
				case .Ok(let createdPipeline): pipeline = createdPipeline;
				case .Err: // Non-fatal
				}
			};

			createGPURenderPipeline(.AlphaBlend, "Alpha", ref mGPURenderPipelineAlpha);
			createGPURenderPipeline(.Additive, "Additive", ref mGPURenderPipelineAdditive);
			createGPURenderPipeline(.PremultipliedAlpha, "Premultiplied", ref mGPURenderPipelinePremultiplied);
			createGPURenderPipeline(.Multiply, "Multiply", ref mGPURenderPipelineMultiply);
			Console.WriteLine(scope $"[Particles] GPU render pipelines: Alpha={mGPURenderPipelineAlpha != null} Add={mGPURenderPipelineAdditive != null} Pre={mGPURenderPipelinePremultiplied != null} Mul={mGPURenderPipelineMultiply != null}");
		}
		else
		{
			Console.WriteLine("[Particles] GPU render shader pair 'particle' not found");
		}

		// Create CPU render pipeline layout
		if (mCPURenderBindGroupLayout != null)
		{
			IBindGroupLayout[1] cpuRenderLayouts = .(mCPURenderBindGroupLayout);
			PipelineLayoutDesc cpuRenderLayoutDesc = .(cpuRenderLayouts);
			switch (Renderer.Device.CreatePipelineLayout(cpuRenderLayoutDesc))
			{
			case .Ok(let layout): mCPURenderPipelineLayout = layout;
			case .Err: return .Err;
			}

			// Load CPU particle render shaders
			let cpuRenderResult = Renderer.ShaderSystem.GetShaderPair("cpu_particle");
			if (cpuRenderResult case .Ok(let cpuShaders))
			{
				// CPU particles use instance buffer with vertex attributes
				VertexBufferLayout[1] cpuVertexBuffers = .(
					.()
					{
						Stride = (uint32)CPUParticleVertex.SizeInBytes,
						StepMode = .Instance,
						Attributes = VertexAttribute[6](
							.() { Format = .Float3,           Offset = 0,  ShaderLocation = 0 },  // Position
							.() { Format = .Float2,           Offset = 12, ShaderLocation = 1 },  // Size
							.() { Format = .UByte4Normalized, Offset = 20, ShaderLocation = 2 },  // Color
							.() { Format = .Float,            Offset = 24, ShaderLocation = 3 },  // Rotation
							.() { Format = .Float4,           Offset = 28, ShaderLocation = 4 },  // TexCoordOffset+Scale
							.() { Format = .Float2,           Offset = 44, ShaderLocation = 5 }   // Velocity2D
						)
					}
				);

				delegate void(BlendState, StringView, ref IRenderPipeline) createCPURenderPipeline = scope (blendMode, label, pipeline) => {
					ColorTargetState[1] colorTargets = .(
						.(.RGBA16Float, blendMode)
					);

					RenderPipelineDesc renderDesc = .()
					{
						Label = scope :: $"Particle CPU Render Pipeline ({label})",
						Layout = mCPURenderPipelineLayout,
						Vertex = .()
						{
							Shader = .(cpuShaders.vert.Module, "main"),
							Buffers = cpuVertexBuffers
						},
						Fragment = .()
						{
							Shader = .(cpuShaders.frag.Module, "main"),
							Targets = colorTargets
						},
						Primitive = .()
						{
							Topology = .TriangleList,
							FrontFace = .CCW,
							CullMode = .None
						},
						DepthStencil = DepthStencilState.DepthReadOnly(Renderer.DepthFormat),
						Multisample = .()
						{
							Count = 1,
							Mask = uint32.MaxValue
						}
					};

					switch (Renderer.Device.CreateRenderPipeline(renderDesc))
					{
					case .Ok(let createdPipeline): pipeline = createdPipeline;
					case .Err: // Non-fatal
					}
				};

				createCPURenderPipeline(.AlphaBlend, "Alpha", ref mCPURenderPipelineAlpha);
				createCPURenderPipeline(.Additive, "Additive", ref mCPURenderPipelineAdditive);
				createCPURenderPipeline(.PremultipliedAlpha, "Premultiplied", ref mCPURenderPipelinePremultiplied);
				createCPURenderPipeline(.Multiply, "Multiply", ref mCPURenderPipelineMultiply);
			}

			// Create trail render pipelines (same bind group, per-vertex input)
			let trailRenderResult = Renderer.ShaderSystem.GetShaderPair("cpu_particle_trail");
			if (trailRenderResult case .Ok(let trailShaders))
			{
				VertexBufferLayout[1] trailVertexBuffers = .(
					.()
					{
						Stride = (uint32)TrailVertex.SizeInBytes,
						StepMode = .Vertex,
						Attributes = VertexAttribute[3](
							.() { Format = .Float3,           Offset = 0,  ShaderLocation = 0 },  // Position
							.() { Format = .Float2,           Offset = 12, ShaderLocation = 1 },  // TexCoord
							.() { Format = .UByte4Normalized, Offset = 20, ShaderLocation = 2 }   // Color
						)
					}
				);

				delegate void(BlendState, StringView, ref IRenderPipeline) createTrailPipeline = scope (blendMode, label, pipeline) => {
					ColorTargetState[1] colorTargets = .(
						.(.RGBA16Float, blendMode)
					);

					RenderPipelineDesc renderDesc = .()
					{
						Label = scope :: $"Particle Trail Pipeline ({label})",
						Layout = mCPURenderPipelineLayout,
						Vertex = .()
						{
							Shader = .(trailShaders.vert.Module, "main"),
							Buffers = trailVertexBuffers
						},
						Fragment = .()
						{
							Shader = .(trailShaders.frag.Module, "main"),
							Targets = colorTargets
						},
						Primitive = .()
						{
							Topology = .TriangleList,
							FrontFace = .CCW,
							CullMode = .None
						},
						DepthStencil = DepthStencilState.DepthReadOnly(Renderer.DepthFormat),
						Multisample = .()
						{
							Count = 1,
							Mask = uint32.MaxValue
						}
					};

					switch (Renderer.Device.CreateRenderPipeline(renderDesc))
					{
					case .Ok(let createdPipeline): pipeline = createdPipeline;
					case .Err: // Non-fatal
					}
				};

				createTrailPipeline(.AlphaBlend, "Alpha", ref mTrailRenderPipelineAlpha);
				createTrailPipeline(.Additive, "Additive", ref mTrailRenderPipelineAdditive);
			}
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
		let device = Renderer.Device;

		for (let kv in mGPUParticleSystems)
			kv.value.Destroy(device);
		DeleteDictionaryAndValues!(mGPUParticleSystems);
		mGPUParticleSystems = new .();

		// Clean up owned CPU emitters
		DeleteDictionaryAndValues!(mCPUEmitters);
		mCPUEmitters = new .();

		// Clean up pending deferred deletions
		for (let pending in mPendingEmitterDeletions)
			delete pending.Emitter;
		mPendingEmitterDeletions.Clear();

		CleanupCPUBindGroupDicts();

		for (int i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mTrailBindGroups[i] != null)
			{
				var bg = mTrailBindGroups[i];
				device.DestroyBindGroup(ref bg);
				mTrailBindGroups[i] = null;
			}
		}

		// Destroy compute pipelines
		device.DestroyComputePipeline(ref mSpawnPipeline);
		device.DestroyComputePipeline(ref mUpdatePipeline);
		device.DestroyComputePipeline(ref mCompactPipeline);
		device.DestroyComputePipeline(ref mCounterResetPipeline);

		// Destroy render pipelines
		device.DestroyRenderPipeline(ref mGPURenderPipelineAlpha);
		device.DestroyRenderPipeline(ref mGPURenderPipelineAdditive);
		device.DestroyRenderPipeline(ref mGPURenderPipelinePremultiplied);
		device.DestroyRenderPipeline(ref mGPURenderPipelineMultiply);
		device.DestroyRenderPipeline(ref mCPURenderPipelineAlpha);
		device.DestroyRenderPipeline(ref mCPURenderPipelineAdditive);
		device.DestroyRenderPipeline(ref mCPURenderPipelinePremultiplied);
		device.DestroyRenderPipeline(ref mCPURenderPipelineMultiply);
		device.DestroyRenderPipeline(ref mTrailRenderPipelineAlpha);
		device.DestroyRenderPipeline(ref mTrailRenderPipelineAdditive);

		// Destroy pipeline layouts
		device.DestroyPipelineLayout(ref mComputePipelineLayout);
		device.DestroyPipelineLayout(ref mGPURenderPipelineLayout);
		device.DestroyPipelineLayout(ref mCPURenderPipelineLayout);

		// Destroy bind group layouts
		device.DestroyBindGroupLayout(ref mComputeBindGroupLayout);
		device.DestroyBindGroupLayout(ref mGPURenderBindGroupLayout);
		device.DestroyBindGroupLayout(ref mCPURenderBindGroupLayout);

		// Destroy default resources
		device.DestroyTextureView(ref mDefaultParticleTextureView);
		device.DestroyTexture(ref mDefaultParticleTexture);
		device.DestroySampler(ref mDefaultSampler);

		// Destroy buffers
		device.DestroyBuffer(ref mFallbackLightingBuffer);
		device.DestroyBuffer(ref mFallbackLightDataBuffer);
		device.DestroyBuffer(ref mFallbackClusterInfoBuffer);
		device.DestroyBuffer(ref mFallbackLightIndexBuffer);
		device.DestroyBuffer(ref mEmitterParamsBuffer);
	}

	public override void AddPasses(RenderGraph graph, ViewContext view, RenderWorld world)
	{
		mActiveGPUEmitters.Clear();
		mActiveCPUEmitters.Clear();
		mActiveTrails.Clear();

		// Cache view context values for use in render methods (called from execute lambdas)
		mFrameIndex = view.FrameIndex;
		mBindGroupIndex = view.GetBindGroupIndex();
		mSceneUniformBuffer = view.SceneUniformBuffer;
		mDeltaTime = view.DeltaTime;
		mTotalTime = view.TotalTime;
		mNearPlane = view.NearPlane;
		mFarPlane = view.FarPlane;

		// Invalidate cached render bind groups for current frame only
		// (depth texture may have changed on resize, but other frame's bind groups may still be in-flight)
		let frameIndex = view.FrameIndex;
		InvalidateRenderBindGroups(frameIndex);

		// Iterate all particle emitters and categorize by backend
		using (SProfiler.Begin("Particles.Simulate"))
		{
			world.ForEachParticleEmitter(scope [&] (handle, proxy) =>
			{
				if (proxy.IsEnabled && proxy.IsEmitting)
				{
					let emitterHandle = ParticleEmitterProxyHandle() { Handle = handle };

					if (proxy.Backend == .GPU)
					{
						mActiveGPUEmitters.Add(emitterHandle);

						// Ensure GPU particle system exists
						GPUParticleSystem system;
						if (!mGPUParticleSystems.TryGetValue(emitterHandle, out system))
						{
							system = CreateGPUParticleSystem(&proxy);
							if (system != null)
								mGPUParticleSystems[emitterHandle] = system;
						}

						if (system != null)
							UpdateGPUEmitterParams(system, &proxy);
					}
					else // CPU
					{
						mActiveCPUEmitters.Add(emitterHandle);

						// Lazily create CPU emitter on first use
						CPUParticleEmitter cpuEmitter;
						if (!mCPUEmitters.TryGetValue(emitterHandle, out cpuEmitter))
						{
							cpuEmitter = new CPUParticleEmitter(Renderer.Device, (int32)proxy.MaxParticles);
							mCPUEmitters[emitterHandle] = cpuEmitter;
						}
						cpuEmitter.Update(view.DeltaTime, &proxy, view.CameraPosition);
					}
				}
			});

			// Process sub-emitter events (after all emitters have been simulated)
			ProcessSubEmitterEvents(world);
		}

		// Collect standalone trail emitters (instances owned by RenderWorld)
		world.ForEachTrailEmitter(scope [&] (handle, proxy) =>
		{
			if (proxy.IsEnabled && proxy.IsActive)
			{
				let trailHandle = TrailEmitterProxyHandle() { Handle = handle };
				mActiveTrails.Add(trailHandle);
			}
		});

		if (mActiveGPUEmitters.Count == 0 && mActiveCPUEmitters.Count == 0 && mActiveTrails.Count == 0)
			return;

		// Upload per-emitter params to dynamic uniform buffer (before render pass)
		using (SProfiler.Begin("Particles.EmitterParams"))
		{
			mEmitterParamIndices.Clear();
			mTrailParamIndices.Clear();
			mEmitterParamCount = 0;

			for (let handle in mActiveGPUEmitters)
			{
				let proxy = world.GetParticleEmitter(handle);
				if (proxy != null && mEmitterParamCount < MaxActiveEmitters)
				{
					mEmitterParamIndices[handle] = mEmitterParamCount;
					WriteEmitterParams(mEmitterParamCount, proxy);
					mEmitterParamCount++;
				}
			}

			for (let handle in mActiveCPUEmitters)
			{
				let proxy = world.GetParticleEmitter(handle);
				if (proxy != null && mEmitterParamCount < MaxActiveEmitters)
				{
					mEmitterParamIndices[handle] = mEmitterParamCount;
					WriteEmitterParams(mEmitterParamCount, proxy);
					mEmitterParamCount++;
				}
			}

			for (let handle in mActiveTrails)
			{
				let proxy = world.GetTrailEmitter(handle);
				if (proxy != null && mEmitterParamCount < MaxActiveEmitters)
				{
					mTrailParamIndices[handle] = mEmitterParamCount;
					WriteTrailEmitterParams(mEmitterParamCount, proxy);
					mEmitterParamCount++;
				}
			}
		}

		// GPU simulation pass
		if (mActiveGPUEmitters.Count > 0)
		{
			graph.AddComputePass("ParticleSimulation", scope (builder) => {
					builder.NeverCull();
					builder.SetComputeExecute(new [&] (encoder) => {
						ExecuteGPUSimulationPass(encoder, mActiveGPUEmitters);
					});
				});
		}

		// Upload CPU particle vertex data (particles + trails)
		using (SProfiler.Begin("Particles.Upload"))
		{
			if (mActiveCPUEmitters.Count > 0)
			{
				let cameraPos = view.CameraPosition;

				for (let handle in mActiveCPUEmitters)
				{
					let proxy = world.GetParticleEmitter(handle);
					if (proxy == null) continue;
					CPUParticleEmitter cpuEmitter;
					if (!mCPUEmitters.TryGetValue(handle, out cpuEmitter)) continue;

					let bufIdx = (uint32)(frameIndex % CPUParticleEmitter.FrameBufferCount);
					cpuEmitter.Upload(bufIdx, cameraPos, proxy);

					// Upload trail vertices if trails are active
					if (proxy.Trail.IsActive)
						cpuEmitter.UploadTrails(bufIdx, cameraPos, proxy);
				}
			}

			// Update and upload standalone trail vertex data
			if (mActiveTrails.Count > 0)
			{
				let cameraPos = view.CameraPosition;
				let deltaTime = view.DeltaTime;

				for (let handle in mActiveTrails)
				{
					let proxy = Renderer.ActiveWorld?.GetTrailEmitter(handle);
					if (proxy == null) continue;
					let trailEmitter = Renderer.ActiveWorld?.GetTrailEmitterInstance(handle);
					if (trailEmitter == null) continue;

					trailEmitter.Update(deltaTime);
					trailEmitter.Upload((uint32)frameIndex, cameraPos, proxy);
				}
			}
		}

		// Get existing resources
		let colorHandle = graph.GetResource("SceneColor");
		let depthHandle = graph.GetResource("SceneDepth");

		if (!colorHandle.IsValid || !depthHandle.IsValid)
			return;

		mDepthHandle = depthHandle;

		mViewWidth = view.Width;
		mViewHeight = view.Height;
		mViewportX = view.ViewportX;
		mViewportY = view.ViewportY;

		// Single render pass for all particles (both backends)
		graph.AddRenderPass("ParticleRender", scope (builder) => {
				builder.SetColorTarget(0, colorHandle, .Load, .Store);
				builder.ReadDepth(depthHandle);
				builder.ReadTexture(depthHandle); // Also sampled in fragment shader for soft particles
				builder.NeverCull();
				builder.SetExecute(new [&] (encoder) => {
					ExecuteRenderPass(encoder, mViewWidth, mViewHeight);
				});
			});
	}

	/// Processes sub-emitter events: for each parent emitter with sub-emitter config,
	/// checks death/birth events and injects particles into child emitters.
	private void ProcessSubEmitterEvents(RenderWorld world)
	{
		for (let parentHandle in mActiveCPUEmitters)
		{
			let parentProxy = world.GetParticleEmitter(parentHandle);
			if (parentProxy == null || parentProxy.SubEmitterCount <= 0)
				continue;
			CPUParticleEmitter cpuEmitter;
			if (!mCPUEmitters.TryGetValue(parentHandle, out cpuEmitter))
				continue;

			for (int32 subIdx = 0; subIdx < parentProxy.SubEmitterCount; subIdx++)
			{
				let entry = parentProxy.SubEmitters[subIdx];
				if (!entry.ChildEmitter.IsValid)
					continue;

				let childProxy = world.GetParticleEmitter(entry.ChildEmitter);
				if (childProxy == null)
					continue;
				CPUParticleEmitter childEmitter;
				if (!mCPUEmitters.TryGetValue(entry.ChildEmitter, out childEmitter))
					continue;

				// Select event buffer based on trigger type
				Span<ParticleEvent> events;
				switch (entry.Trigger)
				{
				case .OnBirth:
					events = cpuEmitter.BirthEvents;
				case .OnDeath:
					events = cpuEmitter.DeathEvents;
				}

				// Process each event
				for (let evt in events)
				{
					// Probability check
					if (entry.Probability < 1.0f)
					{
						if ((float)mSubEmitterRandom.NextDouble() > entry.Probability)
							continue;
					}

					// Spawn particles in child emitter
					let spawnPos = entry.InheritPosition ? evt.Position : childProxy.Position;

					for (int32 s = 0; s < entry.SpawnCount; s++)
					{
						childEmitter.InjectParticle(
							spawnPos,
							evt.Velocity,
							evt.Color,
							entry.VelocityInheritFactor,
							entry.InheritVelocity,
							entry.InheritColor,
							childProxy
						);
					}
				}
			}
		}
	}

	private Result<void> CreateComputePipelines()
	{
		BindGroupLayoutEntry[6] computeEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadWrite },
			.() { Binding = 1, Visibility = .Compute, Type = .StorageBufferReadWrite },
			.() { Binding = 2, Visibility = .Compute, Type = .StorageBufferReadWrite },
			.() { Binding = 3, Visibility = .Compute, Type = .StorageBufferReadWrite },
			.() { Binding = 4, Visibility = .Compute, Type = .StorageBufferReadWrite }  // AliveListAlt (u4)
		);

		BindGroupLayoutDesc computeLayoutDesc = .()
		{
			Label = "Particle Compute BindGroup Layout",
			Entries = computeEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(computeLayoutDesc))
		{
		case .Ok(let layout): mComputeBindGroupLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateRenderPipeline()
	{
		// GPU render bind group layout
		BindGroupLayoutEntry[8] gpuRenderEntries = .(
			.() { Binding = 0, Visibility = .Vertex, Type = .UniformBuffer },      // CameraUniforms (b0)
			.() { Binding = 1, Visibility = .Vertex, Type = .UniformBuffer },      // ParticleParams (b1)
			.() { Binding = 0, Visibility = .Vertex, Type = .StorageBufferReadOnly },      // Particles (t0)
			.() { Binding = 1, Visibility = .Vertex, Type = .StorageBufferReadOnly },      // AliveList (t1)
			.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture },   // ParticleTexture (t2)
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler },          // LinearSampler (s0)
			.() { Binding = 3, Visibility = .Fragment, Type = .SampledTexture },   // DepthTexture (t3)
			.() { Binding = 2, Visibility = .Fragment, Type = .UniformBuffer, HasDynamicOffset = true }  // EmitterParams (b2, dynamic)
		);

		BindGroupLayoutDesc gpuRenderLayoutDesc = .()
		{
			Label = "Particle GPU Render BindGroup Layout",
			Entries = gpuRenderEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(gpuRenderLayoutDesc))
		{
		case .Ok(let layout): mGPURenderBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// CPU render bind group layout (includes lighting buffers for lit particles)
		BindGroupLayoutEntry[9] cpuRenderEntries = .(
			.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer },  // CameraUniforms (b0)
			.() { Binding = 0, Visibility = .Fragment, Type = .SampledTexture },           // ParticleTexture (t0)
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler },                  // LinearSampler (s0)
			.() { Binding = 1, Visibility = .Fragment, Type = .SampledTexture },           // DepthTexture (t1)
			.() { Binding = 1, Visibility = .Vertex | .Fragment, Type = .UniformBuffer, HasDynamicOffset = true },  // EmitterParams (b1, dynamic)
			.() { Binding = 3, Visibility = .Fragment, Type = .UniformBuffer },            // LightingUniforms (b3)
			.() { Binding = 4, Visibility = .Fragment, Type = .StorageBufferReadOnly },            // Lights (t4)
			.() { Binding = 5, Visibility = .Fragment, Type = .StorageBufferReadOnly },            // ClusterLightInfo (t5)
			.() { Binding = 6, Visibility = .Fragment, Type = .StorageBufferReadOnly }             // LightIndices (t6)
		);

		BindGroupLayoutDesc cpuRenderLayoutDesc = .()
		{
			Label = "Particle CPU Render BindGroup Layout",
			Entries = cpuRenderEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(cpuRenderLayoutDesc))
		{
		case .Ok(let layout): mCPURenderBindGroupLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private void ExecuteGPUSimulationPass(IComputePassEncoder encoder, List<ParticleEmitterProxyHandle> emitters)
	{
		for (let handle in emitters)
		{
			GPUParticleSystem system;
			if (!mGPUParticleSystems.TryGetValue(handle, out system))
				continue;

			if (system.ComputeBindGroupA == null || system.ComputeBindGroupB == null)
				continue;

			// Reset Counters[0] on GPU timeline (avoids CPU/GPU race on Upload memory)
			if (mCounterResetPipeline != null)
			{
				encoder.SetPipeline(mCounterResetPipeline);
				encoder.SetBindGroup(0, system.CompactBindGroup, default);
				encoder.Dispatch(1, 1, 1);
				Renderer.Stats.ComputeDispatches++;
			}

			// Barrier: reset must finish before compact writes via InterlockedAdd
			encoder.ComputeBarrier();

			// Compact pass: read old alive list, write compacted entries to new alive list
			if (mCompactPipeline != null)
			{
				encoder.SetPipeline(mCompactPipeline);
				encoder.SetBindGroup(0, system.CompactBindGroup, default);
				encoder.Dispatch((system.MaxParticles + 63) / 64, 1, 1);
				Renderer.Stats.ComputeDispatches++;
			}

			// Barrier: compact must finish before spawn reads Counters[0] and writes alive list
			encoder.ComputeBarrier();

			// Switch to the spawn/update bind group (new alive list at u1)
			let spawnUpdateBG = system.SpawnUpdateBindGroup;

			// Spawn pass: append new particles to the compacted alive list
			if (mSpawnPipeline != null && system.PendingSpawnCount > 0)
			{
				encoder.SetPipeline(mSpawnPipeline);
				encoder.SetBindGroup(0, spawnUpdateBG, default);
				encoder.Dispatch((system.PendingSpawnCount + 63) / 64, 1, 1);
				Renderer.Stats.ComputeDispatches++;
			}

			// Barrier: spawn must finish before update reads the alive list
			encoder.ComputeBarrier();

			// Update pass: update physics, mark dead particles
			if (mUpdatePipeline != null && system.EstimatedAliveCount > 0)
			{
				encoder.SetPipeline(mUpdatePipeline);
				encoder.SetBindGroup(0, spawnUpdateBG, default);
				encoder.Dispatch((system.EstimatedAliveCount + 63) / 64, 1, 1);
				Renderer.Stats.ComputeDispatches++;
			}

			// Note: swap happens at the start of next frame's UpdateGPUEmitterParams,
			// so the render pass (which runs after sim) sees the correct alive list.
		}
	}

	private void ExecuteRenderPass(IRenderPassEncoder encoder, uint32 viewWidth, uint32 viewHeight)
	{
		if (viewWidth == 0 || viewHeight == 0)
			return;

		// Render to per-view SceneColor texture at (0,0), not swapchain offset
		encoder.SetViewport(0, 0, (float)viewWidth, (float)viewHeight, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, viewWidth, viewHeight);

		// Resolve depth-only texture view for soft particles (depth aspect only for shader sampling)
		let depthView = Renderer.RenderGraph?.GetDepthOnlyTextureView(mDepthHandle);

		// Render GPU particles
		RenderGPUParticles(encoder, depthView);

		// Render CPU particles
		RenderCPUParticles(encoder, depthView);

		// Render particle trails
		RenderParticleTrails(encoder, depthView);

		// Render trail emitters
		RenderTrails(encoder, depthView);
	}

	private void RenderGPUParticles(IRenderPassEncoder encoder, ITextureView depthView)
	{
		if (mGPURenderPipelineAlpha == null && mGPURenderPipelineAdditive == null &&
			mGPURenderPipelinePremultiplied == null && mGPURenderPipelineMultiply == null)
			return;

		let frameIndex = mFrameIndex;

		for (let handle in mActiveGPUEmitters)
		{
			GPUParticleSystem system;
			if (mGPUParticleSystems.TryGetValue(handle, out system))
			{
				// Ensure render bind group exists for this frame
				let bindGroup = GetOrCreateGPURenderBindGroup(system, frameIndex, depthView);
				if (bindGroup == null)
					continue;

				IRenderPipeline pipeline = null;
				switch (system.BlendMode)
				{
				case .Alpha: pipeline = mGPURenderPipelineAlpha;
				case .Additive: pipeline = mGPURenderPipelineAdditive;
				case .Premultiplied: pipeline = mGPURenderPipelinePremultiplied;
				case .Multiply: pipeline = mGPURenderPipelineMultiply;
				}

				if (pipeline == null)
					continue;

				encoder.SetPipeline(pipeline);

				uint32[4] particleParams = .(system.EstimatedAliveCount, 0, 0, 0);
				TransferHelper.WriteMappedBuffer(
					system.ParticleParams, 0,
					Span<uint8>((uint8*)&particleParams[0], 16)
				);

				// Use dynamic offset for this emitter's params
				int32 emitterIndex = 0;
				mEmitterParamIndices.TryGetValue(handle, out emitterIndex);
				uint32[1] dynamicOffsets = .((uint32)((int64)emitterIndex * (int64)EmitterParamAlignment));
				encoder.SetBindGroup(0, bindGroup, dynamicOffsets);

				let instanceCount = Math.Min(system.EstimatedAliveCount, system.MaxParticles);
				if (instanceCount > 0)
				{
					encoder.Draw(6, instanceCount, 0, 0);
					Renderer.Stats.DrawCalls++;
					Renderer.Stats.InstanceCount += (int32)instanceCount;
				}
			}
		}
	}

	private IBindGroup GetOrCreateGPURenderBindGroup(GPUParticleSystem system, int32 frameIndex, ITextureView depthView)
	{
		let bindGroupIndex = mBindGroupIndex;

		// Check if existing bind group is still valid
		if (system.RenderBindGroups[bindGroupIndex] != null)
			return system.RenderBindGroups[bindGroupIndex];

		if (mGPURenderBindGroupLayout == null || mDefaultParticleTextureView == null || mDefaultSampler == null)
			return null;
		if (depthView == null || mEmitterParamsBuffer == null)
			return null;

		let cameraBuffer = mSceneUniformBuffer;
		if (cameraBuffer == null)
			return null;

		BindGroupEntry[8] renderEntries = .(
			BindGroupEntry.Buffer(/*0,*/cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Buffer(/*1,*/system.ParticleParams, 0, 16),
			BindGroupEntry.Buffer(/*0,*/system.ParticleBuffer, 0, (uint64)(system.MaxParticles * GPUParticle.SizeInBytes)),
			BindGroupEntry.Buffer(/*1,*/system.CurrentAliveList, 0, (uint64)(system.MaxParticles * 4)),
			BindGroupEntry.Texture(/*2,*/mDefaultParticleTextureView),
			BindGroupEntry.Sampler(/*0,*/mDefaultSampler),
			BindGroupEntry.Texture(/*3,*/depthView, .DepthStencilRead),
			BindGroupEntry.Buffer(/*2,*/mEmitterParamsBuffer, 0, EmitterParamAlignment)
		);

		BindGroupDesc renderBgDesc = .()
		{
			Label = "Particle GPU Render BindGroup",
			Layout = mGPURenderBindGroupLayout,
			Entries = renderEntries
		};

		switch (Renderer.Device.CreateBindGroup(renderBgDesc))
		{
		case .Ok(let bg):
			system.RenderBindGroups[bindGroupIndex] = bg;
			return bg;
		case .Err:
			return null;
		}
	}

	private void RenderCPUParticles(IRenderPassEncoder encoder, ITextureView depthView)
	{
		if (mCPURenderPipelineAlpha == null && mCPURenderPipelineAdditive == null &&
			mCPURenderPipelinePremultiplied == null && mCPURenderPipelineMultiply == null)
			return;

		let frameIndex = mFrameIndex;
		let frameDict = mCPURenderBindGroups[mBindGroupIndex];

		for (let handle in mActiveCPUEmitters)
		{
			let proxy = Renderer.ActiveWorld?.GetParticleEmitter(handle);
			if (proxy == null)
				continue;
			CPUParticleEmitter emitter;
			if (!mCPUEmitters.TryGetValue(handle, out emitter))
				continue;

			let aliveCount = emitter.GetAliveCount();
			if (aliveCount == 0)
				continue;

			let vertexBuffer = emitter.GetVertexBuffer((uint32)frameIndex);
			if (vertexBuffer == null)
				continue;

			IRenderPipeline pipeline = null;
			switch (proxy.BlendMode)
			{
			case .Alpha: pipeline = mCPURenderPipelineAlpha;
			case .Additive: pipeline = mCPURenderPipelineAdditive;
			case .Premultiplied: pipeline = mCPURenderPipelinePremultiplied;
			case .Multiply: pipeline = mCPURenderPipelineMultiply;
			}

			if (pipeline == null)
				continue;

			encoder.SetPipeline(pipeline);

			// Get or create per-frame bind group for this emitter
			IBindGroup bindGroup = null;
			if (!frameDict.TryGetValue(handle, out bindGroup))
			{
				bindGroup = CreateCPURenderBindGroup(proxy, depthView);
				if (bindGroup != null)
					frameDict[handle] = bindGroup;
			}

			if (bindGroup == null)
				continue;

			// Use dynamic offset for this emitter's params
			int32 emitterIndex = 0;
			mEmitterParamIndices.TryGetValue(handle, out emitterIndex);
			uint32[1] dynamicOffsets = .((uint32)((int64)emitterIndex * (int64)EmitterParamAlignment));
			encoder.SetBindGroup(0, bindGroup, dynamicOffsets);
			encoder.SetVertexBuffer(0, vertexBuffer, 0);
			encoder.Draw(6, (uint32)aliveCount, 0, 0);
			Renderer.Stats.DrawCalls++;
			Renderer.Stats.InstanceCount += (int32)aliveCount;
		}
	}

	private void RenderParticleTrails(IRenderPassEncoder encoder, ITextureView depthView)
	{
		if (mTrailRenderPipelineAlpha == null && mTrailRenderPipelineAdditive == null)
			return;

		let frameIndex = mFrameIndex;
		let frameDict = mCPURenderBindGroups[mBindGroupIndex];

		for (let handle in mActiveCPUEmitters)
		{
			let proxy = Renderer.ActiveWorld?.GetParticleEmitter(handle);
			if (proxy == null)
				continue;

			// Skip emitters without trails
			if (!proxy.Trail.IsActive)
				continue;

			CPUParticleEmitter emitter;
			if (!mCPUEmitters.TryGetValue(handle, out emitter))
				continue;
			let trailVertexCount = emitter.GetTrailVertexCount();
			if (trailVertexCount == 0)
				continue;

			let trailBuffer = emitter.GetTrailVertexBuffer((uint32)frameIndex);
			if (trailBuffer == null)
				continue;

			// Select pipeline based on blend mode
			IRenderPipeline pipeline = null;
			switch (proxy.BlendMode)
			{
			case .Alpha: pipeline = mTrailRenderPipelineAlpha;
			case .Additive: pipeline = mTrailRenderPipelineAdditive;
			default: pipeline = mTrailRenderPipelineAlpha; // Fallback to alpha
			}

			if (pipeline == null)
				continue;

			encoder.SetPipeline(pipeline);

			// Reuse the same bind group as CPU particles (same layout)
			IBindGroup bindGroup = null;
			if (!frameDict.TryGetValue(handle, out bindGroup))
			{
				bindGroup = CreateCPURenderBindGroup(proxy, depthView);
				if (bindGroup != null)
					frameDict[handle] = bindGroup;
			}

			if (bindGroup == null)
				continue;

			// Use dynamic offset for this emitter's params
			int32 emitterIndex = 0;
			mEmitterParamIndices.TryGetValue(handle, out emitterIndex);
			uint32[1] dynamicOffsets = .((uint32)((int64)emitterIndex * (int64)EmitterParamAlignment));
			encoder.SetBindGroup(0, bindGroup, dynamicOffsets);
			encoder.SetVertexBuffer(0, trailBuffer, 0);
			encoder.Draw((uint32)trailVertexCount, 1, 0, 0);
			Renderer.Stats.DrawCalls++;
		}
	}

	private void RenderTrails(IRenderPassEncoder encoder, ITextureView depthView)
	{
		if (mTrailRenderPipelineAlpha == null && mTrailRenderPipelineAdditive == null)
			return;

		if (mActiveTrails.Count == 0)
			return;

		let frameIndex = mFrameIndex;
		let bindGroupIndex = mBindGroupIndex;

		// Ensure per-frame/view bind group exists
		if (mTrailBindGroups[bindGroupIndex] == null)
		{
			mTrailBindGroups[bindGroupIndex] = CreateTrailBindGroup(depthView);
			if (mTrailBindGroups[bindGroupIndex] == null)
				return;
		}

		for (let handle in mActiveTrails)
		{
			let proxy = Renderer.ActiveWorld?.GetTrailEmitter(handle);
			if (proxy == null)
				continue;
			let trailEmitter = Renderer.ActiveWorld?.GetTrailEmitterInstance(handle);
			if (trailEmitter == null)
				continue;

			let vertexCount = trailEmitter.VertexCount;
			if (vertexCount == 0)
				continue;

			let trailBuffer = trailEmitter.GetVertexBuffer((uint32)frameIndex);
			if (trailBuffer == null)
				continue;

			// Select pipeline based on blend mode
			IRenderPipeline pipeline = null;
			switch (proxy.BlendMode)
			{
			case .Alpha: pipeline = mTrailRenderPipelineAlpha;
			case .Additive: pipeline = mTrailRenderPipelineAdditive;
			default: pipeline = mTrailRenderPipelineAlpha;
			}

			if (pipeline == null)
				continue;

			encoder.SetPipeline(pipeline);

			// Use dynamic offset for this trail's params
			int32 emitterIndex = 0;
			mTrailParamIndices.TryGetValue(handle, out emitterIndex);
			uint32[1] dynamicOffsets = .((uint32)((int64)emitterIndex * (int64)EmitterParamAlignment));
			encoder.SetBindGroup(0, mTrailBindGroups[bindGroupIndex], dynamicOffsets);
			encoder.SetVertexBuffer(0, trailBuffer, 0);
			encoder.Draw((uint32)vertexCount, 1, 0, 0);
			Renderer.Stats.DrawCalls++;
		}
	}

	private IBindGroup CreateTrailBindGroup(ITextureView depthView)
	{
		if (mCPURenderBindGroupLayout == null || mDefaultParticleTextureView == null || mDefaultSampler == null)
			return null;
		if (depthView == null || mEmitterParamsBuffer == null)
			return null;

		let cameraBuffer = mSceneUniformBuffer;
		if (cameraBuffer == null)
			return null;

		// Get lighting buffers (same as CPU particles)
		let frameIndex = mFrameIndex;
		IBuffer lightingBuffer = null;
		IBuffer lightDataBuffer = null;
		IBuffer clusterInfoBuffer = null;
		IBuffer lightIndexBuffer = null;
		uint64 lightDataSize = 64;
		uint64 clusterInfoSize = 8;
		uint64 lightIndexSize = 4;

		if (Renderer.LightingSystem != null)
		{
				lightingBuffer = Renderer.LightingSystem.LightBuffer?.GetUniformBuffer(frameIndex);
				lightDataBuffer = Renderer.LightingSystem.LightBuffer?.GetLightDataBuffer(frameIndex);
				clusterInfoBuffer = Renderer.LightingSystem.ClusterGrid?.GetClusterLightInfoBuffer(frameIndex);
				lightIndexBuffer = Renderer.LightingSystem.ClusterGrid?.GetLightIndexBuffer(frameIndex);

				if (Renderer.LightingSystem.LightBuffer != null)
					lightDataSize = (uint64)(Renderer.LightingSystem.LightBuffer.MaxLights * GPULight.Size);
				if (Renderer.LightingSystem.ClusterGrid != null)
				{
					let config = Renderer.LightingSystem.ClusterGrid.Config;
					clusterInfoSize = (uint64)(config.TotalClusters * 8);
					lightIndexSize = (uint64)(config.MaxLightsPerCluster * config.TotalClusters * 4);
				}
		}

		// Use fallback buffers when lighting isn't available
		if (lightingBuffer == null) lightingBuffer = mFallbackLightingBuffer;
		if (lightDataBuffer == null) { lightDataBuffer = mFallbackLightDataBuffer; lightDataSize = 64; }
		if (clusterInfoBuffer == null) { clusterInfoBuffer = mFallbackClusterInfoBuffer; clusterInfoSize = 8; }
		if (lightIndexBuffer == null) { lightIndexBuffer = mFallbackLightIndexBuffer; lightIndexSize = 4; }

		BindGroupEntry[9] entries = .(
			BindGroupEntry.Buffer(/*0,*/cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Texture(/*0,*/mDefaultParticleTextureView),
			BindGroupEntry.Sampler(/*0,*/mDefaultSampler),
			BindGroupEntry.Texture(/*1,*/depthView, .DepthStencilRead),
			BindGroupEntry.Buffer(/*1,*/mEmitterParamsBuffer, 0, EmitterParamAlignment),
			BindGroupEntry.Buffer(/*3,*/lightingBuffer, 0, (uint64)LightingUniforms.Size),
			BindGroupEntry.Buffer(/*4,*/lightDataBuffer, 0, lightDataSize),
			BindGroupEntry.Buffer(/*5,*/clusterInfoBuffer, 0, clusterInfoSize),
			BindGroupEntry.Buffer(/*6,*/lightIndexBuffer, 0, lightIndexSize)
		);

		BindGroupDesc bgDesc = .()
		{
			Label = "Standalone Trail Render BindGroup",
			Layout = mCPURenderBindGroupLayout,
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg): return bg;
		case .Err: return null;
		}
	}

	private IBindGroup CreateCPURenderBindGroup(ParticleEmitterProxy* proxy, ITextureView depthView)
	{
		if (mCPURenderBindGroupLayout == null || mDefaultParticleTextureView == null || mDefaultSampler == null)
			return null;
		if (depthView == null || mEmitterParamsBuffer == null)
			return null;

		let cameraBuffer = mSceneUniformBuffer;
		if (cameraBuffer == null)
			return null;

		let textureView = proxy.ParticleTexture != null ? proxy.ParticleTexture : mDefaultParticleTextureView;

		// Get lighting buffers from ForwardOpaqueFeature
		let frameIndex = mFrameIndex;
		IBuffer lightingBuffer = null;
		IBuffer lightDataBuffer = null;
		IBuffer clusterInfoBuffer = null;
		IBuffer lightIndexBuffer = null;
		uint64 lightDataSize = 64;
		uint64 clusterInfoSize = 8;
		uint64 lightIndexSize = 4;

		if (Renderer.LightingSystem != null)
		{
				lightingBuffer = Renderer.LightingSystem.LightBuffer?.GetUniformBuffer(frameIndex);
				lightDataBuffer = Renderer.LightingSystem.LightBuffer?.GetLightDataBuffer(frameIndex);
				clusterInfoBuffer = Renderer.LightingSystem.ClusterGrid?.GetClusterLightInfoBuffer(frameIndex);
				lightIndexBuffer = Renderer.LightingSystem.ClusterGrid?.GetLightIndexBuffer(frameIndex);

				if (Renderer.LightingSystem.LightBuffer != null)
					lightDataSize = (uint64)(Renderer.LightingSystem.LightBuffer.MaxLights * GPULight.Size);
				if (Renderer.LightingSystem.ClusterGrid != null)
				{
					let config = Renderer.LightingSystem.ClusterGrid.Config;
					clusterInfoSize = (uint64)(config.TotalClusters * 8);
					lightIndexSize = (uint64)(config.MaxLightsPerCluster * config.TotalClusters * 4);
				}
		}

		// Use fallback buffers when lighting isn't available
		if (lightingBuffer == null) lightingBuffer = mFallbackLightingBuffer;
		if (lightDataBuffer == null) { lightDataBuffer = mFallbackLightDataBuffer; lightDataSize = 64; }
		if (clusterInfoBuffer == null) { clusterInfoBuffer = mFallbackClusterInfoBuffer; clusterInfoSize = 8; }
		if (lightIndexBuffer == null) { lightIndexBuffer = mFallbackLightIndexBuffer; lightIndexSize = 4; }

		BindGroupEntry[9] entries = .(
			BindGroupEntry.Buffer(/*0,*/cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Texture(/*0,*/textureView),
			BindGroupEntry.Sampler(/*0,*/mDefaultSampler),
			BindGroupEntry.Texture(/*1,*/depthView, .DepthStencilRead),
			BindGroupEntry.Buffer(/*1,*/mEmitterParamsBuffer, 0, EmitterParamAlignment),
			BindGroupEntry.Buffer(/*3,*/lightingBuffer, 0, (uint64)LightingUniforms.Size),
			BindGroupEntry.Buffer(/*4,*/lightDataBuffer, 0, lightDataSize),
			BindGroupEntry.Buffer(/*5,*/clusterInfoBuffer, 0, clusterInfoSize),
			BindGroupEntry.Buffer(/*6,*/lightIndexBuffer, 0, lightIndexSize)
		);

		BindGroupDesc bgDesc = .()
		{
			Label = "CPU Particle Render BindGroup",
			Layout = mCPURenderBindGroupLayout,
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg): return bg;
		case .Err: return null;
		}
	}

	private void InvalidateRenderBindGroups(int32 frameIndex)
	{
		// Only invalidate the current frame's bind groups (for all views).
		// The other frame slot's bind groups may still be in use by the GPU
		// (its fence hasn't been waited yet).

		let device = Renderer.Device;

		for (int32 viewIdx = 0; viewIdx < RenderConfig.MaxViews; viewIdx++)
		{
			let bindGroupIndex = frameIndex * RenderConfig.MaxViews + viewIdx;

			// Clear GPU particle render bind groups for this frame/view
			for (let kv in mGPUParticleSystems)
			{
				let system = kv.value;
				if (system.RenderBindGroups[bindGroupIndex] != null)
				{
					var bg = system.RenderBindGroups[bindGroupIndex];
					device.DestroyBindGroup(ref bg);
					system.RenderBindGroups[bindGroupIndex] = null;
				}
			}

			// Clear CPU particle render bind groups for this frame/view
			if (mCPURenderBindGroups[bindGroupIndex] != null)
			{
				for (let kv in mCPURenderBindGroups[bindGroupIndex])
				{
					var bg = kv.value;
					device.DestroyBindGroup(ref bg);
				}
				mCPURenderBindGroups[bindGroupIndex].Clear();
			}

			// Clear standalone trail bind group for this frame/view
			if (mTrailBindGroups[bindGroupIndex] != null)
			{
				var bg = mTrailBindGroups[bindGroupIndex];
				device.DestroyBindGroup(ref bg);
				mTrailBindGroups[bindGroupIndex] = null;
			}
		}
	}

	private void WriteEmitterParams(int32 emitterIndex, ParticleEmitterProxy* proxy)
	{
		if (mEmitterParamsBuffer == null || emitterIndex >= MaxActiveEmitters)
			return;

		float[8] emitterParams = .(
			proxy.SoftParticleDistance,
			mNearPlane,
			mFarPlane,
			(float)proxy.RenderMode.Underlying,
			proxy.StretchFactor,
			proxy.Lit ? 1.0f : 0.0f,
			0.0f, 0.0f
		);

		let offset = (uint64)emitterIndex * EmitterParamAlignment;
		TransferHelper.WriteMappedBuffer(
			mEmitterParamsBuffer, offset,
			Span<uint8>((uint8*)&emitterParams[0], 32)
		);
	}

	private void WriteTrailEmitterParams(int32 emitterIndex, TrailEmitterProxy* proxy)
	{
		if (mEmitterParamsBuffer == null || emitterIndex >= MaxActiveEmitters)
			return;

		float[8] emitterParams = .(
			proxy.SoftParticleDistance,
			mNearPlane,
			mFarPlane,
			0.0f,  // RenderMode: Billboard (irrelevant for trail vertex shader)
			1.0f,  // StretchFactor
			0.0f,  // Lit: unlit
			0.0f, 0.0f
		);

		let offset = (uint64)emitterIndex * EmitterParamAlignment;
		TransferHelper.WriteMappedBuffer(
			mEmitterParamsBuffer, offset,
			Span<uint8>((uint8*)&emitterParams[0], 32)
		);
	}

	private GPUParticleSystem CreateGPUParticleSystem(ParticleEmitterProxy* proxy)
	{
		let system = new GPUParticleSystem();
		system.MaxParticles = proxy.MaxParticles;
		system.BlendMode = proxy.BlendMode;

		BufferDesc particleBufferDesc = .()
		{
			Label = "Particles",
			Size = (uint64)(proxy.MaxParticles * GPUParticle.SizeInBytes),
			Usage = .Storage
		};

		switch (Renderer.Device.CreateBuffer(particleBufferDesc))
		{
		case .Ok(let buf): system.ParticleBuffer = buf;
		case .Err:
			system.Destroy(Renderer.Device);
			delete system;
			return null;
		}

		BufferDesc indexBufferDesc = .()
		{
			Label = "Particle Indices",
			Size = (uint64)(proxy.MaxParticles * 4),
			Usage = .Storage,
			Memory = .CpuToGpu
		};

		// Two alive list buffers for ping-pong compaction
		switch (Renderer.Device.CreateBuffer(indexBufferDesc))
		{
		case .Ok(let buf): system.AliveListA = buf;
		case .Err:
			system.Destroy(Renderer.Device);
			delete system;
			return null;
		}

		switch (Renderer.Device.CreateBuffer(indexBufferDesc))
		{
		case .Ok(let buf): system.AliveListB = buf;
		case .Err:
			system.Destroy(Renderer.Device);
			delete system;
			return null;
		}

		switch (Renderer.Device.CreateBuffer(indexBufferDesc))
		{
		case .Ok(let buf): system.DeadList = buf;
		case .Err:
			system.Destroy(Renderer.Device);
			delete system;
			return null;
		}

		BufferDesc countersDesc = .()
		{
			Label = "Particle Counters",
			Size = 8,
			Usage = .Storage,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(countersDesc))
		{
		case .Ok(let buf): system.Counters = buf;
		case .Err:
			system.Destroy(Renderer.Device);
			delete system;
			return null;
		}

		// Initialize both alive lists to 0xFFFFFFFF (empty)
		{
			uint32[] emptyIndices = scope uint32[proxy.MaxParticles];
			for (uint32 i = 0; i < proxy.MaxParticles; i++)
				emptyIndices[i] = 0xFFFFFFFF;
			let data = Span<uint8>((uint8*)&emptyIndices[0], (int)(proxy.MaxParticles * 4));
			TransferHelper.WriteMappedBuffer(system.AliveListA, 0, data);
			TransferHelper.WriteMappedBuffer(system.AliveListB, 0, data);
		}

		// Initialize dead list: all particles start dead
		{
			uint32[] deadIndices = scope uint32[proxy.MaxParticles];
			for (uint32 i = 0; i < proxy.MaxParticles; i++)
				deadIndices[i] = i;
			TransferHelper.WriteMappedBuffer(
				system.DeadList, 0,
				Span<uint8>((uint8*)&deadIndices[0], (int)(proxy.MaxParticles * 4))
			);
		}

		// Initialize counters: [0] = 0 alive, [1] = MaxParticles dead
		{
			uint32[2] counters = .(0, proxy.MaxParticles);
			TransferHelper.WriteMappedBuffer(
				system.Counters, 0,
				Span<uint8>((uint8*)&counters[0], 8)
			);
		}

		BufferDesc paramsDesc = .()
		{
			Label = "Emitter Params",
			Size = (uint64)GPUEmitterParams.SizeInBytes,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(paramsDesc))
		{
		case .Ok(let buf): system.EmitterParams = buf;
		case .Err:
			system.Destroy(Renderer.Device);
			delete system;
			return null;
		}

		BufferDesc particleParamsDesc = .()
		{
			Label = "Particle Params",
			Size = 16,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};

		switch (Renderer.Device.CreateBuffer(particleParamsDesc))
		{
		case .Ok(let buf): system.ParticleParams = buf;
		case .Err:
			system.Destroy(Renderer.Device);
			delete system;
			return null;
		}

		// Create two compute bind groups for ping-pong:
		// BindGroupA: AliveListA at u1, AliveListB at u4
		// BindGroupB: AliveListB at u1, AliveListA at u4
		if (mComputeBindGroupLayout != null)
		{
			let bufSize = (uint64)(proxy.MaxParticles * 4);
			let particleBufSize = (uint64)(proxy.MaxParticles * GPUParticle.SizeInBytes);

			BindGroupEntry[6] entriesA = .(
				BindGroupEntry.Buffer(/*0,*/system.EmitterParams, 0, (uint64)GPUEmitterParams.SizeInBytes),
				BindGroupEntry.Buffer(/*0,*/system.ParticleBuffer, 0, particleBufSize),
				BindGroupEntry.Buffer(/*1,*/system.AliveListA, 0, bufSize),
				BindGroupEntry.Buffer(/*2,*/system.DeadList, 0, bufSize),
				BindGroupEntry.Buffer(/*3,*/system.Counters, 0, 8),
				BindGroupEntry.Buffer(/*4,*/system.AliveListB, 0, bufSize)
			);

			BindGroupDesc bgDescA = .()
			{
				Label = "Particle Compute BindGroup A",
				Layout = mComputeBindGroupLayout,
				Entries = entriesA
			};

			switch (Renderer.Device.CreateBindGroup(bgDescA))
			{
			case .Ok(let bg): system.ComputeBindGroupA = bg;
			case .Err:
			}

			BindGroupEntry[6] entriesB = .(
				BindGroupEntry.Buffer(/*0,*/system.EmitterParams, 0, (uint64)GPUEmitterParams.SizeInBytes),
				BindGroupEntry.Buffer(/*0,*/system.ParticleBuffer, 0, particleBufSize),
				BindGroupEntry.Buffer(/*1,*/system.AliveListB, 0, bufSize),
				BindGroupEntry.Buffer(/*2,*/system.DeadList, 0, bufSize),
				BindGroupEntry.Buffer(/*3,*/system.Counters, 0, 8),
				BindGroupEntry.Buffer(/*4,*/system.AliveListA, 0, bufSize)
			);

			BindGroupDesc bgDescB = .()
			{
				Label = "Particle Compute BindGroup B",
				Layout = mComputeBindGroupLayout,
				Entries = entriesB
			};

			switch (Renderer.Device.CreateBindGroup(bgDescB))
			{
			case .Ok(let bg): system.ComputeBindGroupB = bg;
			case .Err:
			}
		}

		// Render bind groups are created lazily in RenderGPUParticles
		// (requires depth texture view which isn't available until pass execution)

		return system;
	}

	private void UpdateGPUEmitterParams(GPUParticleSystem system, ParticleEmitterProxy* proxy)
	{
		let deltaTime = mDeltaTime;
		let avgLifetime = proxy.ParticleLifetime;

		// Swap alive lists — last frame's sim wrote to the "new" list,
		// which the render pass then read. Now that list becomes "old" for this frame's compact.
		system.SwapAliveList();

		system.BlendMode = proxy.BlendMode;

		system.AccumulatedSpawn += proxy.SpawnRate * deltaTime;
		let spawnedThisFrame = (uint32)system.AccumulatedSpawn;
		system.AccumulatedSpawn -= (float)spawnedThisFrame;
		system.PendingSpawnCount = spawnedThisFrame;

		let deathRate = (float)system.EstimatedAliveCount / Math.Max(avgLifetime, 0.1f);
		let deadThisFrame = (uint32)(deathRate * deltaTime);

		let newAlive = system.EstimatedAliveCount + spawnedThisFrame - Math.Min(deadThisFrame, system.EstimatedAliveCount);
		system.EstimatedAliveCount = (uint32)Math.Min((int64)newAlive, (int64)system.MaxParticles);
		system.EstimatedAliveCount = Math.Max(system.EstimatedAliveCount, spawnedThisFrame);

		GPUEmitterParams emitterParams = default;
		emitterParams.Position = proxy.Position;
		emitterParams.SpawnRate = proxy.SpawnRate;
		emitterParams.Direction = proxy.InitialVelocity;
		emitterParams.SpawnRadius = proxy.Shape.Size.X;
		emitterParams.Velocity = proxy.InitialVelocity;
		emitterParams.VelocityRandomness = proxy.VelocityRandomness.X;
		emitterParams.ColorStart = proxy.StartColor;
		emitterParams.ColorEnd = proxy.EndColor;
		emitterParams.SizeStart = proxy.StartSize;
		emitterParams.SizeEnd = proxy.EndSize;
		emitterParams.LifetimeMin = proxy.ParticleLifetime * 0.5f;
		emitterParams.LifetimeMax = proxy.ParticleLifetime * 1.5f;
		emitterParams.Gravity = proxy.GravityMultiplier;
		emitterParams.Drag = proxy.Drag;
		emitterParams.MaxParticles = proxy.MaxParticles;
		emitterParams.AliveCount = system.EstimatedAliveCount;
		emitterParams.DeltaTime = deltaTime;
		emitterParams.TotalTime = mTotalTime;
		emitterParams.SpawnCount = system.PendingSpawnCount;

		// Emission shape parameters
		emitterParams.ShapeType = (uint32)proxy.Shape.Type;
		emitterParams.ShapeSizeX = proxy.Shape.Size.X;
		emitterParams.ShapeSizeY = proxy.Shape.Size.Y;
		emitterParams.ShapeSizeZ = proxy.Shape.Size.Z;
		emitterParams.ShapeConeAngle = proxy.Shape.ConeAngle;
		emitterParams.ShapeArc = proxy.Shape.Arc;
		emitterParams.ShapeEmitFromSurface = proxy.Shape.EmitFromSurface ? 1u : 0u;

		TransferHelper.WriteMappedBuffer(
			system.EmitterParams, 0,
			Span<uint8>((uint8*)&emitterParams, GPUEmitterParams.SizeInBytes)
		);
	}
}

namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// Unified particle render feature.
/// Supports both GPU compute and CPU simulation backends.
public class ParticleFeature : RenderFeatureBase
{
	// Compute pipelines (GPU backend)
	private IComputePipeline mSpawnPipeline ~ delete _;
	private IComputePipeline mUpdatePipeline ~ delete _;

	// GPU render pipelines (one per blend mode)
	private IRenderPipeline mGPURenderPipelineAlpha ~ delete _;
	private IRenderPipeline mGPURenderPipelineAdditive ~ delete _;
	private IRenderPipeline mGPURenderPipelinePremultiplied ~ delete _;
	private IRenderPipeline mGPURenderPipelineMultiply ~ delete _;

	// CPU render pipelines (one per blend mode, different vertex input)
	private IRenderPipeline mCPURenderPipelineAlpha ~ delete _;
	private IRenderPipeline mCPURenderPipelineAdditive ~ delete _;
	private IRenderPipeline mCPURenderPipelinePremultiplied ~ delete _;
	private IRenderPipeline mCPURenderPipelineMultiply ~ delete _;

	// Trail render pipelines (per-vertex input, reuses CPU bind group layout)
	private IRenderPipeline mTrailRenderPipelineAlpha ~ delete _;
	private IRenderPipeline mTrailRenderPipelineAdditive ~ delete _;

	// Bind groups
	private IBindGroupLayout mComputeBindGroupLayout ~ delete _;
	private IBindGroupLayout mGPURenderBindGroupLayout ~ delete _;
	private IBindGroupLayout mCPURenderBindGroupLayout ~ delete _;

	// Default particle resources
	private ITexture mDefaultParticleTexture ~ delete _;
	private ITextureView mDefaultParticleTextureView ~ delete _;
	private ISampler mDefaultSampler ~ delete _;

	// Soft particle resources
	private IBuffer mSoftParamsBuffer ~ delete _;
	private RGResourceHandle mDepthHandle;

	// Per-emitter GPU resources
	private Dictionary<ParticleEmitterProxyHandle, GPUParticleSystem> mGPUParticleSystems = new .() ~ DeleteDictionaryAndValues!(_);

	// Per-frame active emitters
	private List<ParticleEmitterProxyHandle> mActiveGPUEmitters = new .() ~ delete _;
	private List<ParticleEmitterProxyHandle> mActiveCPUEmitters = new .() ~ delete _;

	// Per-frame view dimensions
	private uint32 mViewWidth;
	private uint32 mViewHeight;

	// Per-frame CPU emitter bind groups (per-emitter, per-frame)
	private Dictionary<ParticleEmitterProxyHandle, IBindGroup>[RenderConfig.FrameBufferCount] mCPURenderBindGroups;

	private void InitCPUBindGroupDicts()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			mCPURenderBindGroups[i] = new .();
	}

	private void CleanupCPUBindGroupDicts()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mCPURenderBindGroups[i] != null)
			{
				DeleteDictionaryAndValues!(mCPURenderBindGroups[i]);
				mCPURenderBindGroups[i] = null;
			}
		}
	}

	/// Feature name.
	public override StringView Name => "Particles";

	/// Particles render after transparent.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardTransparent");
	}

	protected override Result<void> OnInitialize()
	{
		InitCPUBindGroupDicts();

		if (CreateDefaultResources() case .Err)
			return .Err;

		if (CreateComputePipelines() case .Err)
			return .Err;

		if (CreateRenderPipeline() case .Err)
			return .Err;

		if (CreateShaderPipelines() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateDefaultResources()
	{
		// Create default white particle texture (64x64 soft circle)
		const int32 TexSize = 64;
		const int32 TexBytes = TexSize * TexSize * 4;

		TextureDescriptor texDesc = .()
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

		switch (Renderer.Device.CreateTexture(&texDesc))
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
		Renderer.Device.Queue.WriteTexture(mDefaultParticleTexture, Span<uint8>(&pixels[0], TexBytes), &layout, &writeSize);

		// Create texture view
		TextureViewDescriptor viewDesc = .()
		{
			Label = "Default Particle Texture View",
			Dimension = .Texture2D
		};

		switch (Renderer.Device.CreateTextureView(mDefaultParticleTexture, &viewDesc))
		{
		case .Ok(let view): mDefaultParticleTextureView = view;
		case .Err: return .Err;
		}

		// Create default sampler (linear, clamp)
		SamplerDescriptor samplerDesc = .()
		{
			Label = "Particle Sampler",
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge,
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear
		};

		switch (Renderer.Device.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler): mDefaultSampler = sampler;
		case .Err: return .Err;
		}

		// Create emitter params buffer (32 bytes: SoftDistance, Near, Far, RenderMode, StretchFactor, padding)
		BufferDescriptor softParamsDesc = .()
		{
			Label = "Emitter Params",
			Size = 32,
			Usage = .Uniform | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&softParamsDesc))
		{
		case .Ok(let buf): mSoftParamsBuffer = buf;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private IPipelineLayout mComputePipelineLayout ~ delete _;
	private IPipelineLayout mGPURenderPipelineLayout ~ delete _;
	private IPipelineLayout mCPURenderPipelineLayout ~ delete _;

	private Result<void> CreateShaderPipelines()
	{
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Create compute pipeline layout
		IBindGroupLayout[1] computeLayouts = .(mComputeBindGroupLayout);
		PipelineLayoutDescriptor computeLayoutDesc = .(computeLayouts);
		switch (Renderer.Device.CreatePipelineLayout(&computeLayoutDesc))
		{
		case .Ok(let layout): mComputePipelineLayout = layout;
		case .Err: return .Err;
		}

		// Load spawn compute shader
		let spawnResult = Renderer.ShaderSystem.GetShader("particle_spawn", .Compute);
		if (spawnResult case .Ok(let spawnShader))
		{
			ComputePipelineDescriptor spawnDesc = .(mComputePipelineLayout, spawnShader.Module);
			spawnDesc.Label = "Particle Spawn Pipeline";

			switch (Renderer.Device.CreateComputePipeline(&spawnDesc))
			{
			case .Ok(let pipeline): mSpawnPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		// Load update compute shader
		let updateResult = Renderer.ShaderSystem.GetShader("particle_update", .Compute);
		if (updateResult case .Ok(let updateShader))
		{
			ComputePipelineDescriptor updateDesc = .(mComputePipelineLayout, updateShader.Module);
			updateDesc.Label = "Particle Update Pipeline";

			switch (Renderer.Device.CreateComputePipeline(&updateDesc))
			{
			case .Ok(let pipeline): mUpdatePipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		// Create GPU render pipeline layout
		IBindGroupLayout[1] gpuRenderLayouts = .(mGPURenderBindGroupLayout);
		PipelineLayoutDescriptor gpuRenderLayoutDesc = .(gpuRenderLayouts);
		switch (Renderer.Device.CreatePipelineLayout(&gpuRenderLayoutDesc))
		{
		case .Ok(let layout): mGPURenderPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Load GPU render shaders and create pipelines for each blend mode
		let gpuRenderResult = Renderer.ShaderSystem.GetShaderPair("particle");
		if (gpuRenderResult case .Ok(let shaders))
		{
			delegate void(BlendState, StringView, ref IRenderPipeline) createGPURenderPipeline = scope (blendMode, label, pipeline) => {
				ColorTargetState[1] colorTargets = .(
					.(.RGBA16Float, blendMode)
				);

				RenderPipelineDescriptor renderDesc = .()
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
					DepthStencil = .Transparent,
					Multisample = .()
					{
						Count = 1,
						Mask = uint32.MaxValue
					}
				};

				switch (Renderer.Device.CreateRenderPipeline(&renderDesc))
				{
				case .Ok(let createdPipeline): pipeline = createdPipeline;
				case .Err: // Non-fatal
				}
			};

			createGPURenderPipeline(.AlphaBlend, "Alpha", ref mGPURenderPipelineAlpha);
			createGPURenderPipeline(.Additive, "Additive", ref mGPURenderPipelineAdditive);
			createGPURenderPipeline(.PremultipliedAlpha, "Premultiplied", ref mGPURenderPipelinePremultiplied);
			createGPURenderPipeline(.Multiply, "Multiply", ref mGPURenderPipelineMultiply);
		}

		// Create CPU render pipeline layout
		if (mCPURenderBindGroupLayout != null)
		{
			IBindGroupLayout[1] cpuRenderLayouts = .(mCPURenderBindGroupLayout);
			PipelineLayoutDescriptor cpuRenderLayoutDesc = .(cpuRenderLayouts);
			switch (Renderer.Device.CreatePipelineLayout(&cpuRenderLayoutDesc))
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
						ArrayStride = (uint64)CPUParticleVertex.SizeInBytes,
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

					RenderPipelineDescriptor renderDesc = .()
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
						DepthStencil = .Transparent,
						Multisample = .()
						{
							Count = 1,
							Mask = uint32.MaxValue
						}
					};

					switch (Renderer.Device.CreateRenderPipeline(&renderDesc))
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
						ArrayStride = (uint64)TrailVertex.SizeInBytes,
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

					RenderPipelineDescriptor renderDesc = .()
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
						DepthStencil = .Transparent,
						Multisample = .()
						{
							Count = 1,
							Mask = uint32.MaxValue
						}
					};

					switch (Renderer.Device.CreateRenderPipeline(&renderDesc))
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
		for (let kv in mGPUParticleSystems)
			delete kv.value;
		mGPUParticleSystems.Clear();

		CleanupCPUBindGroupDicts();
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		mActiveGPUEmitters.Clear();
		mActiveCPUEmitters.Clear();

		// Invalidate cached render bind groups (depth texture may have changed on resize)
		InvalidateRenderBindGroups();

		// Iterate all particle emitters and categorize by backend
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

					// Update CPU emitter simulation
					if (proxy.CPUEmitter != null)
					{
						proxy.CPUEmitter.Update(Renderer.RenderFrameContext.DeltaTime, &proxy, view.CameraPosition);
					}
				}
			}
		});

		if (mActiveGPUEmitters.Count == 0 && mActiveCPUEmitters.Count == 0)
			return;

		// GPU simulation pass
		if (mActiveGPUEmitters.Count > 0)
		{
			graph.AddComputePass("ParticleSimulation")
				.NeverCull()
				.SetComputeCallback(new [&] (encoder) => {
					ExecuteGPUSimulationPass(encoder, mActiveGPUEmitters);
				});
		}

		// Upload CPU particle vertex data (particles + trails)
		if (mActiveCPUEmitters.Count > 0)
		{
			let frameContext = Renderer.RenderFrameContext;
			let cameraPos = frameContext != null ? frameContext.SceneUniforms.CameraPosition : Vector3.Zero;
			let frameIndex = frameContext != null ? frameContext.FrameIndex : (int32)0;

			world.ForEachParticleEmitter(scope [&] (handle, proxy) =>
			{
				if (proxy.IsEnabled && proxy.IsEmitting && proxy.Backend == .CPU && proxy.CPUEmitter != null)
				{
					let bufIdx = (uint32)(frameIndex % CPUParticleEmitter.FrameBufferCount);
					proxy.CPUEmitter.Upload(bufIdx, cameraPos, &proxy);

					// Upload trail vertices if trails are active
					if (proxy.Trail.IsActive)
						proxy.CPUEmitter.UploadTrails(bufIdx, cameraPos, &proxy);
				}
			});
		}

		// Get existing resources
		let colorHandle = graph.GetResource("SceneColor");
		let depthHandle = graph.GetResource("SceneDepth");

		if (!colorHandle.IsValid || !depthHandle.IsValid)
			return;

		mDepthHandle = depthHandle;

		mViewWidth = view.Width;
		mViewHeight = view.Height;

		// Single render pass for all particles (both backends)
		graph.AddGraphicsPass("ParticleRender")
			.WriteColor(colorHandle, .Load, .Store)
			.ReadDepth(depthHandle)
			.NeverCull()
			.SetExecuteCallback(new [&] (encoder) => {
				ExecuteRenderPass(encoder, mViewWidth, mViewHeight);
			});
	}

	private Result<void> CreateComputePipelines()
	{
		BindGroupLayoutEntry[5] computeEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadWrite },
			.() { Binding = 1, Visibility = .Compute, Type = .StorageBufferReadWrite },
			.() { Binding = 2, Visibility = .Compute, Type = .StorageBufferReadWrite },
			.() { Binding = 3, Visibility = .Compute, Type = .StorageBufferReadWrite }
		);

		BindGroupLayoutDescriptor computeLayoutDesc = .()
		{
			Label = "Particle Compute BindGroup Layout",
			Entries = computeEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&computeLayoutDesc))
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
			.() { Binding = 0, Visibility = .Vertex, Type = .StorageBuffer },      // Particles (t0)
			.() { Binding = 1, Visibility = .Vertex, Type = .StorageBuffer },      // AliveList (t1)
			.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture },   // ParticleTexture (t2)
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler },          // LinearSampler (s0)
			.() { Binding = 3, Visibility = .Fragment, Type = .SampledTexture },   // DepthTexture (t3)
			.() { Binding = 2, Visibility = .Fragment, Type = .UniformBuffer }     // SoftParticleParams (b2)
		);

		BindGroupLayoutDescriptor gpuRenderLayoutDesc = .()
		{
			Label = "Particle GPU Render BindGroup Layout",
			Entries = gpuRenderEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&gpuRenderLayoutDesc))
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
			.() { Binding = 1, Visibility = .Vertex | .Fragment, Type = .UniformBuffer },  // EmitterParams (b1)
			.() { Binding = 3, Visibility = .Fragment, Type = .UniformBuffer },            // LightingUniforms (b3)
			.() { Binding = 4, Visibility = .Fragment, Type = .StorageBuffer },            // Lights (t4)
			.() { Binding = 5, Visibility = .Fragment, Type = .StorageBuffer },            // ClusterLightInfo (t5)
			.() { Binding = 6, Visibility = .Fragment, Type = .StorageBuffer }             // LightIndices (t6)
		);

		BindGroupLayoutDescriptor cpuRenderLayoutDesc = .()
		{
			Label = "Particle CPU Render BindGroup Layout",
			Entries = cpuRenderEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&cpuRenderLayoutDesc))
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

			if (system.ComputeBindGroup == null)
				continue;

			if (mSpawnPipeline != null && system.PendingSpawnCount > 0)
			{
				encoder.SetPipeline(mSpawnPipeline);
				encoder.SetBindGroup(0, system.ComputeBindGroup, default);
				encoder.Dispatch((system.PendingSpawnCount + 63) / 64, 1, 1);
				Renderer.Stats.ComputeDispatches++;
			}

			if (mUpdatePipeline != null && system.EstimatedAliveCount > 0)
			{
				encoder.SetPipeline(mUpdatePipeline);
				encoder.SetBindGroup(0, system.ComputeBindGroup, default);
				encoder.Dispatch((system.EstimatedAliveCount + 63) / 64, 1, 1);
				Renderer.Stats.ComputeDispatches++;
			}
		}
	}

	private void ExecuteRenderPass(IRenderPassEncoder encoder, uint32 viewWidth, uint32 viewHeight)
	{
		if (viewWidth == 0 || viewHeight == 0)
			return;

		encoder.SetViewport(0, 0, (float)viewWidth, (float)viewHeight, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, viewWidth, viewHeight);

		// Resolve depth-only texture view for soft particles (depth aspect only for shader sampling)
		let depthView = Renderer.RenderGraph?.GetDepthOnlyTextureView(mDepthHandle);

		// Render GPU particles
		RenderGPUParticles(encoder, depthView);

		// Render CPU particles
		RenderCPUParticles(encoder, depthView);

		// Render particle trails
		RenderTrails(encoder, depthView);
	}

	private void RenderGPUParticles(IRenderPassEncoder encoder, ITextureView depthView)
	{
		if (mGPURenderPipelineAlpha == null && mGPURenderPipelineAdditive == null &&
			mGPURenderPipelinePremultiplied == null && mGPURenderPipelineMultiply == null)
			return;

		let frameIndex = Renderer.RenderFrameContext.FrameIndex;

		for (let handle in mActiveGPUEmitters)
		{
			GPUParticleSystem system;
			if (mGPUParticleSystems.TryGetValue(handle, out system))
			{
				let proxy = Renderer.ActiveWorld?.GetParticleEmitter(handle);

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
				Renderer.Device.Queue.WriteBuffer(
					system.ParticleParams, 0,
					Span<uint8>((uint8*)&particleParams[0], 16)
				);

				// Update emitter params for this emitter
				let softDistance = proxy != null ? proxy.SoftParticleDistance : 0.0f;
				let renderMode = proxy != null ? proxy.RenderMode : ParticleRenderMode.Billboard;
				let stretchFactor = proxy != null ? proxy.StretchFactor : 1.0f;
				let lit = proxy != null ? proxy.Lit : false;
				WriteEmitterParams(softDistance, renderMode, stretchFactor, lit);

				encoder.SetBindGroup(0, bindGroup, default);

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
		// Check if existing bind group is still valid
		if (system.RenderBindGroups[frameIndex] != null)
			return system.RenderBindGroups[frameIndex];

		if (mGPURenderBindGroupLayout == null || mDefaultParticleTextureView == null || mDefaultSampler == null)
			return null;
		if (depthView == null || mSoftParamsBuffer == null)
			return null;

		let cameraBuffer = Renderer.RenderFrameContext?.GetSceneUniformBuffer(frameIndex);
		if (cameraBuffer == null)
			return null;

		BindGroupEntry[8] renderEntries = .(
			BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Buffer(1, system.ParticleParams, 0, 16),
			BindGroupEntry.Buffer(0, system.ParticleBuffer, 0, (uint64)(system.MaxParticles * GPUParticle.SizeInBytes)),
			BindGroupEntry.Buffer(1, system.AliveList, 0, (uint64)(system.MaxParticles * 4)),
			BindGroupEntry.Texture(2, mDefaultParticleTextureView),
			BindGroupEntry.Sampler(0, mDefaultSampler),
			BindGroupEntry.Texture(3, depthView, .DepthStencilReadOnly),
			BindGroupEntry.Buffer(2, mSoftParamsBuffer, 0, 32)
		);

		BindGroupDescriptor renderBgDesc = .()
		{
			Label = "Particle GPU Render BindGroup",
			Layout = mGPURenderBindGroupLayout,
			Entries = renderEntries
		};

		switch (Renderer.Device.CreateBindGroup(&renderBgDesc))
		{
		case .Ok(let bg):
			system.RenderBindGroups[frameIndex] = bg;
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

		let frameIndex = Renderer.RenderFrameContext.FrameIndex;
		let frameDict = mCPURenderBindGroups[frameIndex];

		for (let handle in mActiveCPUEmitters)
		{
			let proxy = Renderer.ActiveWorld?.GetParticleEmitter(handle);
			if (proxy == null || proxy.CPUEmitter == null)
				continue;

			let emitter = proxy.CPUEmitter;
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

			// Update emitter params for this emitter
			WriteEmitterParams(proxy.SoftParticleDistance, proxy.RenderMode, proxy.StretchFactor, proxy.Lit);

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

			encoder.SetBindGroup(0, bindGroup, default);
			encoder.SetVertexBuffer(0, vertexBuffer, 0);
			encoder.Draw(6, (uint32)aliveCount, 0, 0);
			Renderer.Stats.DrawCalls++;
			Renderer.Stats.InstanceCount += (int32)aliveCount;
		}
	}

	private void RenderTrails(IRenderPassEncoder encoder, ITextureView depthView)
	{
		if (mTrailRenderPipelineAlpha == null && mTrailRenderPipelineAdditive == null)
			return;

		let frameIndex = Renderer.RenderFrameContext.FrameIndex;
		let frameDict = mCPURenderBindGroups[frameIndex];

		for (let handle in mActiveCPUEmitters)
		{
			let proxy = Renderer.ActiveWorld?.GetParticleEmitter(handle);
			if (proxy == null || proxy.CPUEmitter == null)
				continue;

			// Skip emitters without trails
			if (!proxy.Trail.IsActive)
				continue;

			let emitter = proxy.CPUEmitter;
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

			// Update emitter params
			WriteEmitterParams(proxy.SoftParticleDistance, proxy.RenderMode, proxy.StretchFactor, proxy.Lit);

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

			encoder.SetBindGroup(0, bindGroup, default);
			encoder.SetVertexBuffer(0, trailBuffer, 0);
			encoder.Draw((uint32)trailVertexCount, 1, 0, 0);
			Renderer.Stats.DrawCalls++;
		}
	}

	private IBindGroup CreateCPURenderBindGroup(ParticleEmitterProxy* proxy, ITextureView depthView)
	{
		if (mCPURenderBindGroupLayout == null || mDefaultParticleTextureView == null || mDefaultSampler == null)
			return null;
		if (depthView == null || mSoftParamsBuffer == null)
			return null;

		let cameraBuffer = Renderer.RenderFrameContext?.SceneUniformBuffer;
		if (cameraBuffer == null)
			return null;

		let textureView = proxy.ParticleTexture != null ? proxy.ParticleTexture : mDefaultParticleTextureView;

		// Get lighting buffers from ForwardOpaqueFeature
		let frameIndex = Renderer.RenderFrameContext.FrameIndex;
		IBuffer lightingBuffer = null;
		IBuffer lightDataBuffer = null;
		IBuffer clusterInfoBuffer = null;
		IBuffer lightIndexBuffer = null;
		uint64 lightDataSize = 64;
		uint64 clusterInfoSize = 8;
		uint64 lightIndexSize = 4;

		if (let forwardFeature = Renderer.GetFeature<ForwardOpaqueFeature>())
		{
			if (forwardFeature.Lighting != null)
			{
				lightingBuffer = forwardFeature.Lighting.LightBuffer?.GetUniformBuffer(frameIndex);
				lightDataBuffer = forwardFeature.Lighting.LightBuffer?.GetLightDataBuffer(frameIndex);
				clusterInfoBuffer = forwardFeature.Lighting.ClusterGrid?.GetClusterLightInfoBuffer(frameIndex);
				lightIndexBuffer = forwardFeature.Lighting.ClusterGrid?.GetLightIndexBuffer(frameIndex);

				if (forwardFeature.Lighting.LightBuffer != null)
					lightDataSize = (uint64)(forwardFeature.Lighting.LightBuffer.MaxLights * GPULight.Size);
				if (forwardFeature.Lighting.ClusterGrid != null)
				{
					let config = forwardFeature.Lighting.ClusterGrid.Config;
					clusterInfoSize = (uint64)(config.TotalClusters * 8);
					lightIndexSize = (uint64)(config.MaxLightsPerCluster * config.TotalClusters * 4);
				}
			}
		}

		// All lighting buffers must be available for the bind group
		if (lightingBuffer == null || lightDataBuffer == null ||
			clusterInfoBuffer == null || lightIndexBuffer == null)
			return null;

		BindGroupEntry[9] entries = .(
			BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Texture(0, textureView),
			BindGroupEntry.Sampler(0, mDefaultSampler),
			BindGroupEntry.Texture(1, depthView, .DepthStencilReadOnly),
			BindGroupEntry.Buffer(1, mSoftParamsBuffer, 0, 32),
			BindGroupEntry.Buffer(3, lightingBuffer, 0, (uint64)LightingUniforms.Size),
			BindGroupEntry.Buffer(4, lightDataBuffer, 0, lightDataSize),
			BindGroupEntry.Buffer(5, clusterInfoBuffer, 0, clusterInfoSize),
			BindGroupEntry.Buffer(6, lightIndexBuffer, 0, lightIndexSize)
		);

		BindGroupDescriptor bgDesc = .()
		{
			Label = "CPU Particle Render BindGroup",
			Layout = mCPURenderBindGroupLayout,
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroup(&bgDesc))
		{
		case .Ok(let bg): return bg;
		case .Err: return null;
		}
	}

	private void InvalidateRenderBindGroups()
	{
		// Clear GPU particle render bind groups
		for (let kv in mGPUParticleSystems)
		{
			let system = kv.value;
			for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			{
				if (system.RenderBindGroups[i] != null)
				{
					delete system.RenderBindGroups[i];
					system.RenderBindGroups[i] = null;
				}
			}
		}

		// Clear CPU particle render bind groups
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mCPURenderBindGroups[i] != null)
			{
				for (let kv in mCPURenderBindGroups[i])
					delete kv.value;
				mCPURenderBindGroups[i].Clear();
			}
		}
	}

	private void WriteEmitterParams(float softDistance, ParticleRenderMode renderMode, float stretchFactor, bool lit)
	{
		if (mSoftParamsBuffer == null)
			return;

		let frameContext = Renderer.RenderFrameContext;
		float[8] emitterParams = .(
			softDistance,
			frameContext != null ? frameContext.SceneUniforms.NearPlane : 0.1f,
			frameContext != null ? frameContext.SceneUniforms.FarPlane : 1000.0f,
			(float)renderMode.Underlying,  // RenderMode as float
			stretchFactor,
			lit ? 1.0f : 0.0f,            // Lit flag
			0.0f, 0.0f                    // padding
		);

		Renderer.Device.Queue.WriteBuffer(
			mSoftParamsBuffer, 0,
			Span<uint8>((uint8*)&emitterParams[0], 32)
		);
	}

	private GPUParticleSystem CreateGPUParticleSystem(ParticleEmitterProxy* proxy)
	{
		let system = new GPUParticleSystem();
		system.MaxParticles = proxy.MaxParticles;
		system.BlendMode = proxy.BlendMode;

		BufferDescriptor particleBufferDesc = .()
		{
			Label = "Particles",
			Size = (uint64)(proxy.MaxParticles * GPUParticle.SizeInBytes),
			Usage = .Storage
		};

		switch (Renderer.Device.CreateBuffer(&particleBufferDesc))
		{
		case .Ok(let buf): system.ParticleBuffer = buf;
		case .Err:
			delete system;
			return null;
		}

		BufferDescriptor indexBufferDesc = .()
		{
			Label = "Particle Indices",
			Size = (uint64)(proxy.MaxParticles * 4),
			Usage = .Storage | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&indexBufferDesc))
		{
		case .Ok(let buf): system.AliveList = buf;
		case .Err:
			delete system;
			return null;
		}

		switch (Renderer.Device.CreateBuffer(&indexBufferDesc))
		{
		case .Ok(let buf): system.DeadList = buf;
		case .Err:
			delete system;
			return null;
		}

		BufferDescriptor countersDesc = .()
		{
			Label = "Particle Counters",
			Size = 8,
			Usage = .Storage | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&countersDesc))
		{
		case .Ok(let buf): system.Counters = buf;
		case .Err:
			delete system;
			return null;
		}

		// Initialize dead list
		{
			uint32[] deadIndices = scope uint32[proxy.MaxParticles];
			for (uint32 i = 0; i < proxy.MaxParticles; i++)
				deadIndices[i] = i;
			Renderer.Device.Queue.WriteBuffer(
				system.DeadList, 0,
				Span<uint8>((uint8*)&deadIndices[0], (int)(proxy.MaxParticles * 4))
			);
		}

		// Initialize counters
		{
			uint32[2] counters = .(0, proxy.MaxParticles);
			Renderer.Device.Queue.WriteBuffer(
				system.Counters, 0,
				Span<uint8>((uint8*)&counters[0], 8)
			);
		}

		BufferDescriptor paramsDesc = .()
		{
			Label = "Emitter Params",
			Size = (uint64)GPUEmitterParams.SizeInBytes,
			Usage = .Uniform | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&paramsDesc))
		{
		case .Ok(let buf): system.EmitterParams = buf;
		case .Err:
			delete system;
			return null;
		}

		BufferDescriptor particleParamsDesc = .()
		{
			Label = "Particle Params",
			Size = 16,
			Usage = .Uniform | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&particleParamsDesc))
		{
		case .Ok(let buf): system.ParticleParams = buf;
		case .Err:
			delete system;
			return null;
		}

		// Create compute bind group
		if (mComputeBindGroupLayout != null)
		{
			BindGroupEntry[5] computeEntries = .(
				BindGroupEntry.Buffer(0, system.EmitterParams, 0, (uint64)GPUEmitterParams.SizeInBytes),
				BindGroupEntry.Buffer(0, system.ParticleBuffer, 0, (uint64)(proxy.MaxParticles * GPUParticle.SizeInBytes)),
				BindGroupEntry.Buffer(1, system.AliveList, 0, (uint64)(proxy.MaxParticles * 4)),
				BindGroupEntry.Buffer(2, system.DeadList, 0, (uint64)(proxy.MaxParticles * 4)),
				BindGroupEntry.Buffer(3, system.Counters, 0, 8)
			);

			BindGroupDescriptor computeBgDesc = .()
			{
				Label = "Particle Compute BindGroup",
				Layout = mComputeBindGroupLayout,
				Entries = computeEntries
			};

			switch (Renderer.Device.CreateBindGroup(&computeBgDesc))
			{
			case .Ok(let bg): system.ComputeBindGroup = bg;
			case .Err:
			}
		}

		// Render bind groups are created lazily in RenderGPUParticles
		// (requires depth texture view which isn't available until pass execution)

		return system;
	}

	private void UpdateGPUEmitterParams(GPUParticleSystem system, ParticleEmitterProxy* proxy)
	{
		let deltaTime = Renderer.RenderFrameContext.DeltaTime;
		let avgLifetime = proxy.ParticleLifetime;

		system.BlendMode = proxy.BlendMode;
		system.TimeSinceReset += deltaTime;

		let resetInterval = 30.0f;
		let writeIndexNearCapacity = system.GPUAliveWriteIndex > (system.MaxParticles * 8 / 10);
		if (system.TimeSinceReset >= resetInterval || writeIndexNearCapacity || system.NeedsReset)
		{
			ResetGPUParticleSystem(system, proxy);
		}

		system.AccumulatedSpawn += proxy.SpawnRate * deltaTime;
		let spawnedThisFrame = (uint32)system.AccumulatedSpawn;
		system.AccumulatedSpawn -= (float)spawnedThisFrame;
		system.PendingSpawnCount = spawnedThisFrame;
		system.GPUAliveWriteIndex += spawnedThisFrame;

		let deathRate = (float)system.EstimatedAliveCount / Math.Max(avgLifetime, 0.1f);
		let deadThisFrame = (uint32)(deathRate * deltaTime);

		let newAlive = system.EstimatedAliveCount + spawnedThisFrame - Math.Min(deadThisFrame, system.EstimatedAliveCount);
		system.EstimatedAliveCount = (uint32)Math.Min((int64)newAlive, (int64)system.MaxParticles);
		system.EstimatedAliveCount = Math.Max(system.EstimatedAliveCount, spawnedThisFrame);

		GPUEmitterParams emitterParams = default;
		emitterParams.Position = proxy.Position;
		emitterParams.SpawnRate = proxy.SpawnRate;
		emitterParams.Direction = proxy.InitialVelocity;
		emitterParams.SpawnRadius = 0.5f;
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
		emitterParams.TotalTime = Renderer.RenderFrameContext.TotalTime;
		emitterParams.SpawnCount = system.PendingSpawnCount;

		Renderer.Device.Queue.WriteBuffer(
			system.EmitterParams, 0,
			Span<uint8>((uint8*)&emitterParams, GPUEmitterParams.SizeInBytes)
		);
	}

	private void ResetGPUParticleSystem(GPUParticleSystem system, ParticleEmitterProxy* proxy)
	{
		{
			uint32[] deadIndices = scope uint32[system.MaxParticles];
			for (uint32 i = 0; i < system.MaxParticles; i++)
				deadIndices[i] = i;
			Renderer.Device.Queue.WriteBuffer(
				system.DeadList, 0,
				Span<uint8>((uint8*)&deadIndices[0], (int)(system.MaxParticles * 4))
			);
		}

		{
			uint32[2] counters = .(0, system.MaxParticles);
			Renderer.Device.Queue.WriteBuffer(
				system.Counters, 0,
				Span<uint8>((uint8*)&counters[0], 8)
			);
		}

		{
			uint32[] aliveIndices = scope uint32[system.MaxParticles];
			for (uint32 i = 0; i < system.MaxParticles; i++)
				aliveIndices[i] = 0xFFFFFFFF;
			Renderer.Device.Queue.WriteBuffer(
				system.AliveList, 0,
				Span<uint8>((uint8*)&aliveIndices[0], (int)(system.MaxParticles * 4))
			);
		}

		system.EstimatedAliveCount = 0;
		system.AccumulatedSpawn = 0;
		system.GPUAliveWriteIndex = 0;
		system.TimeSinceReset = 0;
		system.NeedsReset = false;
	}
}

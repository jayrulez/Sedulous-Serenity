namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// GPU particle data.
[CRepr]
public struct GPUParticle
{
	public Vector3 Position;
	public float Age;

	public Vector3 Velocity;
	public float Lifetime;

	public Vector4 Color;

	public Vector2 ParticleSize;
	public float Rotation;
	public float RotationSpeed;

	/// Size in bytes.
	public static int SizeInBytes => 64;
}

/// Particle emitter GPU data.
[CRepr]
public struct GPUEmitterParams
{
	public Vector3 Position;
	public float SpawnRate;

	public Vector3 Direction;
	public float SpawnRadius;

	public Vector3 Velocity;
	public float VelocityRandomness;

	public Vector4 ColorStart;
	public Vector4 ColorEnd;

	public Vector2 SizeStart;
	public Vector2 SizeEnd;

	public float LifetimeMin;
	public float LifetimeMax;
	public float Gravity;
	public float Drag;

	public uint32 MaxParticles;
	public uint32 AliveCount; // Current alive particles (update shader reads this)
	public float DeltaTime;
	public float TotalTime;
	public uint32 SpawnCount; // Particles to spawn this frame (spawn shader reads this)
	public uint32 _Padding;

	/// Size in bytes.
	public static int SizeInBytes => 144;
}

/// GPU particle render feature.
/// Uses compute shaders for simulation and forward rendering for billboards.
public class ParticleFeature : RenderFeatureBase
{
	// Compute pipelines
	private IComputePipeline mSpawnPipeline ~ delete _;
	private IComputePipeline mUpdatePipeline ~ delete _;

	// Render pipelines (one per blend mode)
	private IRenderPipeline mRenderPipelineAlpha ~ delete _;
	private IRenderPipeline mRenderPipelineAdditive ~ delete _;
	private IRenderPipeline mRenderPipelinePremultiplied ~ delete _;

	// Bind groups
	private IBindGroupLayout mComputeBindGroupLayout ~ delete _;
	private IBindGroupLayout mRenderBindGroupLayout ~ delete _;

	// Default particle resources
	private ITexture mDefaultParticleTexture ~ delete _;
	private ITextureView mDefaultParticleTextureView ~ delete _;
	private ISampler mDefaultSampler ~ delete _;

	// Per-emitter resources
	private Dictionary<ParticleEmitterProxyHandle, ParticleSystem> mParticleSystems = new .() ~ DeleteDictionaryAndValues!(_);

	// Per-frame active emitters (avoids heap allocation in closures)
	private List<ParticleEmitterProxyHandle> mActiveEmitters = new .() ~ delete _;

	// Per-frame view dimensions (stored for use in callbacks)
	private uint32 mViewWidth;
	private uint32 mViewHeight;

	/// Feature name.
	public override StringView Name => "Particles";

	/// Particles render after transparent.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("ForwardTransparent");
	}

	protected override Result<void> OnInitialize()
	{
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
				// Normalized distance from center (0 at center, 1 at edge)
				float dx = ((float)x - center) / center;
				float dy = ((float)y - center) / center;
				float distSq = dx * dx + dy * dy;

				// Smooth falloff using 1 - smoothstep for soft edges
				// This creates a nice soft circular gradient
				float dist = Math.Sqrt(distSq);
				float alpha;
				if (dist >= 1.0f)
				{
					alpha = 0.0f;
				}
				else
				{
					// Quadratic falloff with smooth edges: (1 - dist²)²
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

		return .Ok;
	}

	private IPipelineLayout mComputePipelineLayout ~ delete _;
	private IPipelineLayout mRenderPipelineLayout ~ delete _;

	private Result<void> CreateShaderPipelines()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Create compute pipeline layout (shared by spawn and update)
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

		// Create render pipeline layout
		IBindGroupLayout[1] renderLayouts = .(mRenderBindGroupLayout);
		PipelineLayoutDescriptor renderLayoutDesc = .(renderLayouts);
		switch (Renderer.Device.CreatePipelineLayout(&renderLayoutDesc))
		{
		case .Ok(let layout): mRenderPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Load render shaders and create pipelines for each blend mode
		let renderResult = Renderer.ShaderSystem.GetShaderPair("particle");
		if (renderResult case .Ok(let shaders))
		{
			// Create pipeline for each blend mode

			delegate void(BlendState, StringView, ref IRenderPipeline) createRenderPipeline = scope (blendMode, label, pipeline) => {
				ColorTargetState[1] colorTargets = .(
					.(.RGBA16Float, blendMode)
				);

				RenderPipelineDescriptor renderDesc = .()
				{
					Label = scope :: $"Particle Render Pipeline ({label})",
					Layout = mRenderPipelineLayout,
					Vertex = .()
					{
						Shader = .(shaders.vert.Module, "main"),
						Buffers = default // No vertex buffers - SV_VertexID/SV_InstanceID
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

			createRenderPipeline(.AlphaBlend, "Alpha", ref mRenderPipelineAlpha);
			createRenderPipeline(.Additive, "Additive", ref mRenderPipelineAdditive);
			createRenderPipeline(.PremultipliedAlpha, "Premultiplied", ref mRenderPipelinePremultiplied);

			/*
			// Don't remove this commented code, it is meant for a Beef bug report

			BlendState[3] blendModes = .(.AlphaBlend, .Additive, .PremultipliedAlpha);
			StringView[3] blendLabels = .("Alpha", "Additive", "Premultiplied");
			IRenderPipeline*[3] pipelineTargets = .(&mRenderPipelineAlpha, &mRenderPipelineAdditive, &mRenderPipelinePremultiplied);

			for (int i < 3)
			{
				ColorTargetState[1] colorTargets = .(
					.(.RGBA16Float, blendModes[i])
				);

				RenderPipelineDescriptor renderDesc = .()
				{
					Label = scope :: $"Particle Render Pipeline ({blendLabels[i]})",
					Layout = mRenderPipelineLayout,
					Vertex = .()
					{
						Shader = .(shaders.vert.Module, "main"),
						Buffers = default // No vertex buffers - SV_VertexID/SV_InstanceID
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
				case .Ok(let pipeline): *pipelineTargets[i] = pipeline;
				case .Err: // Non-fatal
				}
			}*/
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
		for (let kv in mParticleSystems)
			delete kv.value;
		mParticleSystems.Clear();
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		// Clear and rebuild active emitters list each frame
		mActiveEmitters.Clear();

		// Iterate all particle emitters in the world and update params while world is valid
		world.ForEachParticleEmitter(scope [&] (handle, proxy) =>
		{
			if (proxy.IsEnabled && proxy.IsEmitting)
			{
				let emitterHandle = ParticleEmitterProxyHandle() { Handle = handle };
				mActiveEmitters.Add(emitterHandle);

				// Ensure particle system exists for this emitter
				ParticleSystem system;
				if (!mParticleSystems.TryGetValue(emitterHandle, out system))
				{
					system = CreateParticleSystem(&proxy);
					if (system != null)
						mParticleSystems[emitterHandle] = system;
				}

				// Update emitter params now while proxy is valid
				if (system != null)
					UpdateEmitterParams(system, &proxy);
			}
		});

		if (mActiveEmitters.Count == 0)
			return;

		// Add particle simulation pass
		// NeverCull because compute passes don't write to tracked render graph resources
		graph.AddComputePass("ParticleSimulation")
			.NeverCull()
			.SetComputeCallback(new [&] (encoder) => {
				ExecuteSimulationPass(encoder, mActiveEmitters);
			});

		// Get existing resources
		let colorHandle = graph.GetResource("SceneColor");
		let depthHandle = graph.GetResource("SceneDepth");

		if (!colorHandle.IsValid || !depthHandle.IsValid)
			return;

		// Store view dimensions as member variables for callback access
		mViewWidth = view.Width;
		mViewHeight = view.Height;

		// Add particle rendering pass
		// Note: Must be NeverCull because render graph culling only preserves FirstWriter,
		// and ForwardOpaque is the first writer of SceneColor
		graph.AddGraphicsPass("ParticleRender")
			.WriteColor(colorHandle, .Load, .Store)
			.ReadDepth(depthHandle)
			.NeverCull()
			.SetExecuteCallback(new [&] (encoder) => {
				ExecuteRenderPass(encoder, mViewWidth, mViewHeight, mActiveEmitters);
			});
	}

	private Result<void> CreateComputePipelines()
	{
		// Bind group layout for compute shaders (both spawn and update use same bindings)
		// - cbuffer EmitterParams : register(b0) -> binding 0, UniformBuffer
		// - RWStructuredBuffer<Particle> Particles : register(u0) -> binding 0, StorageBufferReadWrite (shift 2000)
		// - RWStructuredBuffer<uint> AliveList : register(u1) -> binding 1, StorageBufferReadWrite (shift 2001)
		// - RWStructuredBuffer<uint> DeadList : register(u2) -> binding 2, StorageBufferReadWrite (shift 2002)
		// - RWStructuredBuffer<uint> Counters : register(u3) -> binding 3, StorageBufferReadWrite (shift 2003)
		BindGroupLayoutEntry[5] computeEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer },          // b0: EmitterParams
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadWrite }, // u0: Particles
			.() { Binding = 1, Visibility = .Compute, Type = .StorageBufferReadWrite }, // u1: AliveList
			.() { Binding = 2, Visibility = .Compute, Type = .StorageBufferReadWrite }, // u2: DeadList
			.() { Binding = 3, Visibility = .Compute, Type = .StorageBufferReadWrite }  // u3: Counters
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

		// Note: Compute pipelines are created in CreateShaderPipelines() when shaders are available
		return .Ok;
	}

	private Result<void> CreateRenderPipeline()
	{
		// Bind group layout for rendering
		// particle.vert.hlsl bindings:
		// - cbuffer CameraUniforms : register(b0) -> binding 0, UniformBuffer
		// - StructuredBuffer<Particle> Particles : register(t0) -> binding 0, StorageBuffer (shift 1000)
		// - StructuredBuffer<uint> AliveList : register(t1) -> binding 1, StorageBuffer (shift 1001)
		// - cbuffer ParticleParams : register(b1) -> binding 1, UniformBuffer
		// particle.frag.hlsl bindings:
		// - Texture2D ParticleTexture : register(t2) -> binding 2, SampledTexture (shift 1002)
		// - SamplerState LinearSampler : register(s0) -> binding 0, Sampler (shift 3000)
		BindGroupLayoutEntry[6] renderEntries = .(
			.() { Binding = 0, Visibility = .Vertex, Type = .UniformBuffer },         // b0: CameraUniforms
			.() { Binding = 1, Visibility = .Vertex, Type = .UniformBuffer },         // b1: ParticleParams
			.() { Binding = 0, Visibility = .Vertex, Type = .StorageBuffer },         // t0: Particles (read-only)
			.() { Binding = 1, Visibility = .Vertex, Type = .StorageBuffer },         // t1: AliveList (read-only)
			.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture },      // t2: ParticleTexture
			.() { Binding = 0, Visibility = .Fragment, Type = .Sampler }              // s0: LinearSampler
		);

		BindGroupLayoutDescriptor renderLayoutDesc = .()
		{
			Label = "Particle Render BindGroup Layout",
			Entries = renderEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&renderLayoutDesc))
		{
		case .Ok(let layout): mRenderBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Note: Render pipeline is created in CreateShaderPipelines() when shaders are available
		return .Ok;
	}

	private void ExecuteSimulationPass(IComputePassEncoder encoder, List<ParticleEmitterProxyHandle> emitters)
	{
		for (let handle in emitters)
		{
			ParticleSystem system;
			if (!mParticleSystems.TryGetValue(handle, out system))
				continue;

			if (system.ComputeBindGroup == null)
				continue;

			// Spawn new particles
			if (mSpawnPipeline != null && system.PendingSpawnCount > 0)
			{
				encoder.SetPipeline(mSpawnPipeline);
				encoder.SetBindGroup(0, system.ComputeBindGroup, default);

				encoder.Dispatch((system.PendingSpawnCount + 63) / 64, 1, 1);
				Renderer.Stats.ComputeDispatches++;
			}

			// Update existing particles
			if (mUpdatePipeline != null && system.EstimatedAliveCount > 0)
			{
				encoder.SetPipeline(mUpdatePipeline);
				encoder.SetBindGroup(0, system.ComputeBindGroup, default);

				encoder.Dispatch((system.EstimatedAliveCount + 63) / 64, 1, 1);
				Renderer.Stats.ComputeDispatches++;
			}
		}
	}

	private void ExecuteRenderPass(IRenderPassEncoder encoder, uint32 viewWidth, uint32 viewHeight, List<ParticleEmitterProxyHandle> emitters)
	{
		// Guard against zero dimensions
		if (viewWidth == 0 || viewHeight == 0)
			return;

		// Set viewport
		encoder.SetViewport(0, 0, (float)viewWidth, (float)viewHeight, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, viewWidth, viewHeight);

		// Check that at least one pipeline is available
		if (mRenderPipelineAlpha == null && mRenderPipelineAdditive == null && mRenderPipelinePremultiplied == null)
			return;

		for (let handle in emitters)
		{
			ParticleSystem system;
			if (mParticleSystems.TryGetValue(handle, out system))
			{
				if (system.RenderBindGroup != null)
				{
					// Select pipeline based on blend mode
					IRenderPipeline pipeline = null;
					switch (system.BlendMode)
					{
					case .Alpha:
						pipeline = mRenderPipelineAlpha;
					case .Additive:
						pipeline = mRenderPipelineAdditive;
					case .Premultiplied:
						pipeline = mRenderPipelinePremultiplied;
					}

					if (pipeline == null)
						continue;

					encoder.SetPipeline(pipeline);

					// Update ParticleParams with estimated alive count
					// (Proper GPU readback would require indirect draw, using estimate for now)
					uint32[4] particleParams = .(system.EstimatedAliveCount, 0, 0, 0);
					Renderer.Device.Queue.WriteBuffer(
						system.ParticleParams, 0,
						Span<uint8>((uint8*)&particleParams[0], 16)
					);

					encoder.SetBindGroup(0, system.RenderBindGroup, default);

					// Draw all potentially alive particles, shader will cull those beyond AliveCount
					let instanceCount = Math.Min(system.EstimatedAliveCount, system.MaxParticles);
					if (instanceCount > 0)
					{
						encoder.Draw(6, instanceCount, 0, 0); // 6 vertices per quad
						Renderer.Stats.DrawCalls++;
						Renderer.Stats.InstanceCount += (int32)instanceCount;
					}
				}
			}
		}
	}

	private ParticleSystem CreateParticleSystem(ParticleEmitterProxy* proxy)
	{
		let system = new ParticleSystem();
		system.MaxParticles = proxy.MaxParticles;
		system.BlendMode = proxy.BlendMode;

		// Create particle buffer
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

		// Create alive/dead index lists (need CopyDst for initialization)
		BufferDescriptor indexBufferDesc = .()
		{
			Label = "Particle Indices",
			Size = (uint64)(proxy.MaxParticles * 4), // uint32 per particle
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

		// Create counters buffer (2 uint32: [0] = alive count, [1] = dead count)
		BufferDescriptor countersDesc = .()
		{
			Label = "Particle Counters",
			Size = 8, // 2 * sizeof(uint32)
			Usage = .Storage | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&countersDesc))
		{
		case .Ok(let buf): system.Counters = buf;
		case .Err:
			delete system;
			return null;
		}

		// Initialize dead list with all particle indices (0, 1, 2, ... MaxParticles-1)
		{
			uint32[] deadIndices = scope uint32[proxy.MaxParticles];
			for (uint32 i = 0; i < proxy.MaxParticles; i++)
				deadIndices[i] = i;
			Renderer.Device.Queue.WriteBuffer(
				system.DeadList, 0,
				Span<uint8>((uint8*)&deadIndices[0], (int)(proxy.MaxParticles * 4))
			);
		}

		// Initialize counters: [0] = 0 alive, [1] = MaxParticles dead
		{
			uint32[2] counters = .(0, proxy.MaxParticles);
			Renderer.Device.Queue.WriteBuffer(
				system.Counters, 0,
				Span<uint8>((uint8*)&counters[0], 8)
			);
		}

		// Create emitter params buffer
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

		// Create particle params buffer for render shader (AliveCount)
		BufferDescriptor particleParamsDesc = .()
		{
			Label = "Particle Params",
			Size = 16, // uint32 AliveCount + padding
			Usage = .Uniform | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&particleParamsDesc))
		{
		case .Ok(let buf): system.ParticleParams = buf;
		case .Err:
			delete system;
			return null;
		}

		// Create compute bind group (entries must match layout order)
		// Layout: b0:EmitterParams, u0:Particles, u1:AliveList, u2:DeadList, u3:Counters
		if (mComputeBindGroupLayout != null)
		{
			BindGroupEntry[5] computeEntries = .(
				BindGroupEntry.Buffer(0, system.EmitterParams, 0, (uint64)GPUEmitterParams.SizeInBytes),  // b0
				BindGroupEntry.Buffer(0, system.ParticleBuffer, 0, (uint64)(proxy.MaxParticles * GPUParticle.SizeInBytes)), // u0
				BindGroupEntry.Buffer(1, system.AliveList, 0, (uint64)(proxy.MaxParticles * 4)),   // u1
				BindGroupEntry.Buffer(2, system.DeadList, 0, (uint64)(proxy.MaxParticles * 4)),    // u2
				BindGroupEntry.Buffer(3, system.Counters, 0, 8)                                    // u3
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
			case .Err: // Non-fatal, will skip simulation
			}
		}

		// Create render bind group (entries must match layout order)
		// Layout: b0:CameraUniforms, b1:ParticleParams, t0:Particles, t1:AliveList, t2:ParticleTexture, s0:LinearSampler
		if (mRenderBindGroupLayout != null && mDefaultParticleTextureView != null && mDefaultSampler != null)
		{
			// Get camera buffer from frame context
			let cameraBuffer = Renderer.RenderFrameContext?.SceneUniformBuffer;
			if (cameraBuffer != null)
			{
				BindGroupEntry[6] renderEntries = .(
					BindGroupEntry.Buffer(0, cameraBuffer, 0, SceneUniforms.Size),                       // b0
					BindGroupEntry.Buffer(1, system.ParticleParams, 0, 16),                              // b1
					BindGroupEntry.Buffer(0, system.ParticleBuffer, 0, (uint64)(proxy.MaxParticles * GPUParticle.SizeInBytes)), // t0
					BindGroupEntry.Buffer(1, system.AliveList, 0, (uint64)(proxy.MaxParticles * 4)),     // t1
					BindGroupEntry.Texture(2, mDefaultParticleTextureView),                              // t2
					BindGroupEntry.Sampler(0, mDefaultSampler)                                           // s0
				);

				BindGroupDescriptor renderBgDesc = .()
				{
					Label = "Particle Render BindGroup",
					Layout = mRenderBindGroupLayout,
					Entries = renderEntries
				};

				switch (Renderer.Device.CreateBindGroup(&renderBgDesc))
				{
				case .Ok(let bg): system.RenderBindGroup = bg;
				case .Err: // Non-fatal, will skip rendering
				}
			}
		}

		return system;
	}

	private void UpdateEmitterParams(ParticleSystem system, ParticleEmitterProxy* proxy)
	{
		let deltaTime = Renderer.RenderFrameContext.DeltaTime;
		let avgLifetime = proxy.ParticleLifetime;

		// Sync blend mode (in case it changed at runtime)
		system.BlendMode = proxy.BlendMode;

		// Track time since last reset
		system.TimeSinceReset += deltaTime;

		// Periodic reset: when the alive list fills up with holes
		// This is a workaround for the lack of list compaction - use a long interval
		// to minimize visible disruption (30 seconds or when GPU write index approaches capacity)
		let resetInterval = 30.0f;
		let writeIndexNearCapacity = system.GPUAliveWriteIndex > (system.MaxParticles * 8 / 10); // 80% of max
		if (system.TimeSinceReset >= resetInterval || writeIndexNearCapacity || system.NeedsReset)
		{
			ResetParticleSystem(system, proxy);
		}

		// Update CPU-side estimate of alive particles
		// Spawn rate particles per second, particles die after avgLifetime seconds
		system.AccumulatedSpawn += proxy.SpawnRate * deltaTime;
		let spawnedThisFrame = (uint32)system.AccumulatedSpawn;
		system.AccumulatedSpawn -= (float)spawnedThisFrame;
		system.PendingSpawnCount = spawnedThisFrame;

		// Track estimated GPU write position (spawns increment, but we don't decrement on death)
		system.GPUAliveWriteIndex += spawnedThisFrame;

		// Estimate deaths: particles die after avgLifetime seconds
		let deathRate = (float)system.EstimatedAliveCount / Math.Max(avgLifetime, 0.1f);
		let deadThisFrame = (uint32)(deathRate * deltaTime);

		// Update estimate
		let newAlive = system.EstimatedAliveCount + spawnedThisFrame - Math.Min(deadThisFrame, system.EstimatedAliveCount);
		system.EstimatedAliveCount = (uint32)Math.Min((int64)newAlive, (int64)system.MaxParticles);

		// Ensure at least spawned this frame are visible
		system.EstimatedAliveCount = Math.Max(system.EstimatedAliveCount, spawnedThisFrame);

		GPUEmitterParams emitterParams = default;
		emitterParams.Position = proxy.Position;
		emitterParams.SpawnRate = proxy.SpawnRate;
		emitterParams.Direction = proxy.InitialVelocity; // Use initial velocity as direction
		emitterParams.SpawnRadius = 0.5f; // Default spawn radius
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

	/// Resets the particle system GPU buffers to clean state.
	/// This clears all particles and reinitializes the dead list.
	private void ResetParticleSystem(ParticleSystem system, ParticleEmitterProxy* proxy)
	{
		// Reinitialize dead list with all particle indices (0, 1, 2, ... MaxParticles-1)
		{
			uint32[] deadIndices = scope uint32[system.MaxParticles];
			for (uint32 i = 0; i < system.MaxParticles; i++)
				deadIndices[i] = i;
			Renderer.Device.Queue.WriteBuffer(
				system.DeadList, 0,
				Span<uint8>((uint8*)&deadIndices[0], (int)(system.MaxParticles * 4))
			);
		}

		// Reinitialize counters: [0] = 0 alive, [1] = MaxParticles dead
		{
			uint32[2] counters = .(0, system.MaxParticles);
			Renderer.Device.Queue.WriteBuffer(
				system.Counters, 0,
				Span<uint8>((uint8*)&counters[0], 8)
			);
		}

		// Clear alive list (all invalid entries)
		{
			uint32[] aliveIndices = scope uint32[system.MaxParticles];
			for (uint32 i = 0; i < system.MaxParticles; i++)
				aliveIndices[i] = 0xFFFFFFFF; // Invalid marker
			Renderer.Device.Queue.WriteBuffer(
				system.AliveList, 0,
				Span<uint8>((uint8*)&aliveIndices[0], (int)(system.MaxParticles * 4))
			);
		}

		// Reset CPU-side tracking
		system.EstimatedAliveCount = 0;
		system.AccumulatedSpawn = 0;
		system.GPUAliveWriteIndex = 0;
		system.TimeSinceReset = 0;
		system.NeedsReset = false;
	}

	/// Per-emitter particle system resources.
	private class ParticleSystem
	{
		public IBuffer ParticleBuffer ~ delete _;
		public IBuffer AliveList ~ delete _;
		public IBuffer DeadList ~ delete _;
		public IBuffer Counters ~ delete _;      // [0] = alive count, [1] = dead count
		public IBuffer EmitterParams ~ delete _;
		public IBuffer ParticleParams ~ delete _; // For render shader b1
		public IBindGroup ComputeBindGroup ~ delete _;
		public IBindGroup RenderBindGroup ~ delete _;
		public uint32 MaxParticles;
		public uint32 ActiveCount;

		// CPU-side estimate of alive particles (since GPU readback is expensive)
		public uint32 EstimatedAliveCount;
		public float AccumulatedSpawn; // Fractional spawn accumulator
		public uint32 PendingSpawnCount; // Particles to spawn this frame

		// Track GPU alive list write position (may diverge from EstimatedAliveCount due to holes)
		public uint32 GPUAliveWriteIndex;
		public float TimeSinceReset; // Time since last buffer reset
		public bool NeedsReset; // Flag to trigger reset on next update

		// Blend mode for this emitter's particles
		public ParticleBlendMode BlendMode;
	}
}

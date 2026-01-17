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
	public uint32 ActiveParticles;
	public float DeltaTime;
	public float TotalTime;

	/// Size in bytes.
	public static int SizeInBytes => 128;
}

/// GPU particle render feature.
/// Uses compute shaders for simulation and forward rendering for billboards.
public class ParticleFeature : RenderFeatureBase
{
	// Compute pipelines
	private IComputePipeline mSpawnPipeline ~ delete _;
	private IComputePipeline mUpdatePipeline ~ delete _;

	// Render pipeline
	private IRenderPipeline mRenderPipeline ~ delete _;

	// Bind groups
	private IBindGroupLayout mComputeBindGroupLayout ~ delete _;
	private IBindGroupLayout mRenderBindGroupLayout ~ delete _;

	// Default particle resources
	private ITexture mDefaultParticleTexture ~ delete _;
	private ITextureView mDefaultParticleTextureView ~ delete _;
	private ISampler mDefaultSampler ~ delete _;

	// Per-emitter resources
	private Dictionary<ParticleEmitterProxyHandle, ParticleSystem> mParticleSystems = new .() ~ {
		for (let kv in _)
			kv.value.Dispose();
		delete _;
	};

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
		// Create default white particle texture (4x4)
		TextureDescriptor texDesc = .()
		{
			Label = "Default Particle Texture",
			Width = 4,
			Height = 4,
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

		// Fill with white pixels with radial falloff (soft circle)
		uint8[64] pixels = default; // 4x4 * 4 bytes
		for (int32 y = 0; y < 4; y++)
		{
			for (int32 x = 0; x < 4; x++)
			{
				float dx = (float)(x - 1.5f) / 1.5f;
				float dy = (float)(y - 1.5f) / 1.5f;
				float dist = Math.Sqrt(dx * dx + dy * dy);
				float alpha = Math.Clamp(1.0f - dist, 0.0f, 1.0f);
				uint8 a = (uint8)(alpha * 255.0f);

				int32 idx = (y * 4 + x) * 4;
				pixels[idx] = 255;     // R
				pixels[idx + 1] = 255; // G
				pixels[idx + 2] = 255; // B
				pixels[idx + 3] = a;   // A
			}
		}

		var layout = TextureDataLayout() { BytesPerRow = 16, RowsPerImage = 4 };
		var writeSize = Extent3D(4, 4, 1);
		Renderer.Device.Queue.WriteTexture(mDefaultParticleTexture, Span<uint8>(&pixels[0], 64), &layout, &writeSize);

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

		// Create render pipeline layout
		IBindGroupLayout[1] renderLayouts = .(mRenderBindGroupLayout);
		PipelineLayoutDescriptor renderLayoutDesc = .(renderLayouts);
		switch (Renderer.Device.CreatePipelineLayout(&renderLayoutDesc))
		{
		case .Ok(let layout): mRenderPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Load render shaders
		let renderResult = Renderer.ShaderSystem.GetShaderPair("particle");
		if (renderResult case .Ok(let shaders))
		{
			// Color targets with alpha blending
			ColorTargetState[1] colorTargets = .(
				.(.RGBA16Float, .AlphaBlend)
			);

			RenderPipelineDescriptor renderDesc = .()
			{
				Label = "Particle Render Pipeline",
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
			case .Ok(let pipeline): mRenderPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
		for (let kv in mParticleSystems)
			kv.value.Dispose();
		mParticleSystems.Clear();
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		// Find active emitters from existing particle systems
		List<ParticleEmitterProxyHandle> activeEmitters = scope .();

		for (let kv in mParticleSystems)
		{
			if (kv.value.ActiveCount > 0)
				activeEmitters.Add(kv.key);
		}

		if (activeEmitters.Count == 0)
			return;

		// Copy to heap for closure capture
		List<ParticleEmitterProxyHandle> emittersCopy = new .();
		emittersCopy.AddRange(activeEmitters);

		// Add particle simulation pass
		graph.AddComputePass("ParticleSimulation")
			.SetComputeCallback(new (encoder) => {
				ExecuteSimulationPass(encoder, world, emittersCopy);
				delete emittersCopy;
			});

		// Get existing resources
		let colorHandle = graph.GetResource("SceneColor");
		let depthHandle = graph.GetResource("SceneDepth");

		if (!colorHandle.IsValid || !depthHandle.IsValid)
			return;

		// Copy again for render pass
		List<ParticleEmitterProxyHandle> renderEmittersCopy = new .();
		renderEmittersCopy.AddRange(activeEmitters);

		// Add particle rendering pass
		graph.AddGraphicsPass("ParticleRender")
			.WriteColor(colorHandle, .Load, .Store)
			.ReadDepth(depthHandle)
			.SetExecuteCallback(new (encoder) => {
				ExecuteRenderPass(encoder, world, view, renderEmittersCopy);
				delete renderEmittersCopy;
			});
	}

	private Result<void> CreateComputePipelines()
	{
		// Bind group layout for compute
		BindGroupLayoutEntry[4] computeEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBuffer }, // Particle buffer
			.() { Binding = 1, Visibility = .Compute, Type = .StorageBuffer }, // Alive list
			.() { Binding = 2, Visibility = .Compute, Type = .StorageBuffer }, // Dead list
			.() { Binding = 3, Visibility = .Compute, Type = .UniformBuffer }  // Emitter params
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
		BindGroupLayoutEntry[4] renderEntries = .(
			.() { Binding = 0, Visibility = .Vertex, Type = .StorageBuffer }, // Particles (read-only in shader)
			.() { Binding = 1, Visibility = .Vertex, Type = .UniformBuffer },         // Camera
			.() { Binding = 2, Visibility = .Fragment, Type = .SampledTexture },      // Particle texture
			.() { Binding = 3, Visibility = .Fragment, Type = .Sampler }              // Sampler
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

	private void ExecuteSimulationPass(IComputePassEncoder encoder, RenderWorld world, List<ParticleEmitterProxyHandle> emitters)
	{
		for (let handle in emitters)
		{
			if (let proxy = world.GetParticleEmitter(handle))
			{
				// Get or create particle system
				ParticleSystem system;
				if (!mParticleSystems.TryGetValue(handle, out system))
				{
					system = CreateParticleSystem(proxy);
					if (system == null)
						continue;
					mParticleSystems[handle] = system;
				}

				// Update emitter params
				UpdateEmitterParams(system, proxy);

				// Spawn new particles
				if (mSpawnPipeline != null)
				{
					encoder.SetPipeline(mSpawnPipeline);
					encoder.SetBindGroup(0, system.ComputeBindGroup, default);

					let spawnCount = (uint32)(proxy.SpawnRate * Renderer.RenderFrameContext.DeltaTime);
					if (spawnCount > 0)
					{
						encoder.Dispatch((spawnCount + 63) / 64, 1, 1);
						Renderer.Stats.ComputeDispatches++;
					}
				}

				// Update existing particles
				if (mUpdatePipeline != null)
				{
					encoder.SetPipeline(mUpdatePipeline);
					encoder.SetBindGroup(0, system.ComputeBindGroup, default);

					let activeCount = system.ActiveCount;
					if (activeCount > 0)
					{
						encoder.Dispatch((activeCount + 63) / 64, 1, 1);
						Renderer.Stats.ComputeDispatches++;
					}
				}
			}
		}
	}

	private void ExecuteRenderPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view, List<ParticleEmitterProxyHandle> emitters)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, (uint32)view.Width, (uint32)view.Height);

		if (mRenderPipeline != null)
			encoder.SetPipeline(mRenderPipeline);

		for (let handle in emitters)
		{
			ParticleSystem system;
			if (mParticleSystems.TryGetValue(handle, out system))
			{
				if (system.ActiveCount > 0 && system.RenderBindGroup != null)
				{
					encoder.SetBindGroup(0, system.RenderBindGroup, default);

					// Draw particles as point sprites or quads
					// Using instanced rendering with particle count
					encoder.Draw(6, system.ActiveCount, 0, 0); // 6 vertices per quad
					Renderer.Stats.DrawCalls++;
					Renderer.Stats.InstanceCount += (int32)system.ActiveCount;
				}
			}
		}
	}

	private ParticleSystem CreateParticleSystem(ParticleEmitterProxy* proxy)
	{
		let system = new ParticleSystem();
		system.MaxParticles = proxy.MaxParticles;

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

		// Create alive/dead index lists
		BufferDescriptor indexBufferDesc = .()
		{
			Label = "Particle Indices",
			Size = (uint64)(proxy.MaxParticles * 4), // uint32 per particle
			Usage = .Storage
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

		// Create compute bind group
		if (mComputeBindGroupLayout != null)
		{
			BindGroupEntry[4] computeEntries = .(
				BindGroupEntry.Buffer(0, system.ParticleBuffer, 0, (uint64)(proxy.MaxParticles * GPUParticle.SizeInBytes)),
				BindGroupEntry.Buffer(1, system.AliveList, 0, (uint64)(proxy.MaxParticles * 4)),
				BindGroupEntry.Buffer(2, system.DeadList, 0, (uint64)(proxy.MaxParticles * 4)),
				BindGroupEntry.Buffer(3, system.EmitterParams, 0, (uint64)GPUEmitterParams.SizeInBytes)
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

		// Create render bind group
		if (mRenderBindGroupLayout != null && mDefaultParticleTextureView != null && mDefaultSampler != null)
		{
			// Get camera buffer from frame context
			let cameraBuffer = Renderer.RenderFrameContext?.SceneUniformBuffer;
			if (cameraBuffer != null)
			{
				BindGroupEntry[4] renderEntries = .(
					BindGroupEntry.Buffer(0, system.ParticleBuffer, 0, (uint64)(proxy.MaxParticles * GPUParticle.SizeInBytes)),
					BindGroupEntry.Buffer(1, cameraBuffer, 0, SceneUniforms.Size),
					BindGroupEntry.Texture(2, mDefaultParticleTextureView),
					BindGroupEntry.Sampler(3, mDefaultSampler)
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
		emitterParams.ActiveParticles = system.ActiveCount;
		emitterParams.DeltaTime = Renderer.RenderFrameContext.DeltaTime;
		emitterParams.TotalTime = Renderer.RenderFrameContext.TotalTime;

		Renderer.Device.Queue.WriteBuffer(
			system.EmitterParams, 0,
			Span<uint8>((uint8*)&emitterParams, GPUEmitterParams.SizeInBytes)
		);
	}

	/// Per-emitter particle system resources.
	private class ParticleSystem
	{
		public IBuffer ParticleBuffer ~ delete _;
		public IBuffer AliveList ~ delete _;
		public IBuffer DeadList ~ delete _;
		public IBuffer EmitterParams ~ delete _;
		public IBindGroup ComputeBindGroup ~ delete _;
		public IBindGroup RenderBindGroup ~ delete _;
		public uint32 MaxParticles;
		public uint32 ActiveCount;

		public void Dispose()
		{
			// Handled by destructors
		}
	}
}

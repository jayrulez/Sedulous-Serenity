namespace RendererParticles;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Renderer;
using Sedulous.Shell.Input;
using SampleFramework;

/// Particle system sample demonstrating:
/// - GPU particle rendering with multiple blend modes
/// - Multiple particle effects (fountain, fire, smoke, sparks)
/// - Color and size curves over lifetime
/// - Gravity simulation and emission shapes
/// - LOD (Level of Detail) system
/// - Sub-emitters (fireworks)
/// - Per-particle sorting for alpha blending
/// - First-person camera controls
///
/// Controls:
///   WASD/QE = Move camera
///   Right-click+Drag = Look around
///   Tab = Toggle mouse capture
///   1-5 = Switch particle effect
///   Space = Spawn firework
class RendererParticlesSample : RHISampleApp
{
	// Renderer components
	private ParticleSystem mParticleSystem;
	private ParticleSystem mFireworkSystem;
	private ParticleEmitterConfig mFireworkConfig ~ delete _; // Owned separately since ParticleSystem doesn't own external configs
	private SkyboxRenderer mSkyboxRenderer;

	// Common resources
	private IBuffer mCameraUniformBuffer;
	private IBuffer mParticleUniformBuffer;

	// Default texture resources for non-textured particles
	private ITexture mDefaultTexture;
	private ITextureView mDefaultTextureView;
	private ISampler mDefaultSampler;

	// Particle pipeline
	private IBindGroupLayout mParticleBindGroupLayout;
	private IBindGroup mParticleBindGroup;
	private IPipelineLayout mParticlePipelineLayout;
	private IRenderPipeline mParticlePipeline;

	// Skybox pipeline
	private IBindGroupLayout mSkyboxBindGroupLayout;
	private IBindGroup mSkyboxBindGroup;
	private IPipelineLayout mSkyboxPipelineLayout;
	private IRenderPipeline mSkyboxPipeline;

	// Camera
	private Camera mCamera;
	private float mCameraYaw = 0.0f;
	private float mCameraPitch = 0.0f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 5.0f;
	private float mCameraLookSpeed = 0.003f;

	// Current effect
	private int32 mCurrentEffect = 0;
	private String[] mEffectNames = new .("Fountain", "Fire", "Smoke", "Sparks", "Magic") ~ delete _;
	private float mFireworkCooldown = 0;

	public this() : base(.()
	{
		Title = "Renderer Particles - Fountain Effect",
		Width = 1024,
		Height = 768,
		ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f),
		EnableDepth = true
	})
	{
	}

	protected override bool OnInitialize()
	{
		// Setup camera
		mCamera = .();
		mCamera.Position = .(0, 3, 8);
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);

		mCameraYaw = Math.PI_f;
		mCameraPitch = -0.15f;
		UpdateCameraDirection();

		if (!CreateBuffers())
			return false;

		if (!CreateDefaultTexture())
			return false;

		if (!CreateSkybox())
			return false;

		if (!CreateParticleSystem())
			return false;

		if (!CreateSkyboxPipeline())
			return false;

		if (!CreateParticlePipeline())
			return false;

		// Create firework system with sub-emitters
		if (!CreateFireworkSystem())
			return false;

		Console.WriteLine("RendererParticles sample initialized");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Right-click+Drag=Look, Tab=Toggle mouse capture");
		Console.WriteLine("         1-5=Switch effect, Space=Spawn firework");
		return true;
	}

	private void UpdateCameraDirection()
	{
		float cosP = Math.Cos(mCameraPitch);
		mCamera.Forward = Vector3.Normalize(.(
			Math.Sin(mCameraYaw) * cosP,
			Math.Sin(mCameraPitch),
			Math.Cos(mCameraYaw) * cosP
		));
	}

	protected override void OnInput()
	{
		let keyboard = Shell.InputManager.Keyboard;
		let mouse = Shell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mCameraYaw -= mouse.DeltaX * mCameraLookSpeed;
			mCameraPitch -= mouse.DeltaY * mCameraLookSpeed;
			mCameraPitch = Math.Clamp(mCameraPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
			UpdateCameraDirection();
		}

		let forward = mCamera.Forward;
		let right = mCamera.Right;
		let up = Vector3(0, 1, 0);
		float speed = mCameraMoveSpeed * DeltaTime;

		if (keyboard.IsKeyDown(.W)) mCamera.Position = mCamera.Position + forward * speed;
		if (keyboard.IsKeyDown(.S)) mCamera.Position = mCamera.Position - forward * speed;
		if (keyboard.IsKeyDown(.A)) mCamera.Position = mCamera.Position - right * speed;
		if (keyboard.IsKeyDown(.D)) mCamera.Position = mCamera.Position + right * speed;
		if (keyboard.IsKeyDown(.Q)) mCamera.Position = mCamera.Position - up * speed;
		if (keyboard.IsKeyDown(.E)) mCamera.Position = mCamera.Position + up * speed;

		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
		{
			if (keyboard.IsKeyDown(.W)) mCamera.Position = mCamera.Position + forward * speed;
			if (keyboard.IsKeyDown(.S)) mCamera.Position = mCamera.Position - forward * speed;
			if (keyboard.IsKeyDown(.A)) mCamera.Position = mCamera.Position - right * speed;
			if (keyboard.IsKeyDown(.D)) mCamera.Position = mCamera.Position + right * speed;
			if (keyboard.IsKeyDown(.Q)) mCamera.Position = mCamera.Position - up * speed;
			if (keyboard.IsKeyDown(.E)) mCamera.Position = mCamera.Position + up * speed;
		}

		// Switch effects with number keys
		if (keyboard.IsKeyPressed(.Num1)) SwitchEffect(0);
		if (keyboard.IsKeyPressed(.Num2)) SwitchEffect(1);
		if (keyboard.IsKeyPressed(.Num3)) SwitchEffect(2);
		if (keyboard.IsKeyPressed(.Num4)) SwitchEffect(3);
		if (keyboard.IsKeyPressed(.Num5)) SwitchEffect(4);

		// Spawn firework with space
		if (keyboard.IsKeyPressed(.Space) && mFireworkCooldown <= 0)
		{
			SpawnFirework();
			mFireworkCooldown = 0.3f;
		}
	}

	private void SwitchEffect(int32 effect)
	{
		if (effect == mCurrentEffect)
			return;

		mCurrentEffect = effect;
		mParticleSystem.Clear();

		let config = mParticleSystem.Config;

		switch (effect)
		{
		case 0: // Fountain
			config.EmissionRate = 150;
			config.SetConeEmission(30);
			config.InitialSpeed = .(6.0f, 10.0f);
			config.InitialSize = .(0.1f, 0.25f);
			config.Lifetime = .(2.0f, 3.5f);
			config.StartColor = .(Color(255, 200, 50, 255));
			config.EndColor = .(Color(255, 50, 0, 100));
			config.Gravity = .(0, -8.0f, 0);
			config.BlendMode = .AlphaBlend;
			config.SetSizeOverLifetime(1.0f, 0.3f);
			mParticleSystem.Position = .(0, 0, 0);

		case 1: // Fire
			config.EmissionRate = 80;
			config.SetConeEmission(15);
			config.InitialSpeed = .(2.0f, 4.0f);
			config.InitialSize = .(0.3f, 0.6f);
			config.Lifetime = .(0.8f, 1.5f);
			config.StartColor = .(Color(255, 200, 50, 255));
			config.EndColor = .(Color(255, 30, 0, 0));
			config.Gravity = .(0, 2.0f, 0);  // Fire rises
			config.BlendMode = .Additive;
			config.SetSizeOverLifetime(1.0f, 2.5f);  // Grow as they rise
			mParticleSystem.Position = .(0, 0, 0);

		case 2: // Smoke
			config.EmissionRate = 30;
			config.SetConeEmission(20);
			config.InitialSpeed = .(1.0f, 2.0f);
			config.InitialSize = .(0.5f, 1.0f);
			config.Lifetime = .(3.0f, 5.0f);
			config.StartColor = .(Color(80, 80, 80, 200));
			config.EndColor = .(Color(50, 50, 50, 0));
			config.Gravity = .(0, 0.5f, 0);
			config.BlendMode = .AlphaBlend;
			config.SetSizeOverLifetime(1.0f, 4.0f);  // Expand as they rise
			mParticleSystem.Position = .(0, 0, 0);

		case 3: // Sparks
			config.EmissionRate = 200;
			config.SetSphereEmission(0.3f);
			config.InitialSpeed = .(5.0f, 12.0f);
			config.InitialSize = .(0.03f, 0.08f);
			config.Lifetime = .(0.5f, 1.5f);
			config.StartColor = .(Color(255, 220, 100, 255));
			config.EndColor = .(Color(255, 100, 0, 0));
			config.Gravity = .(0, -15.0f, 0);
			config.BlendMode = .Additive;
			config.SetSizeOverLifetime(1.0f, 0.1f);
			mParticleSystem.Position = .(0, 2, 0);

		case 4: // Magic
			config.EmissionRate = 50;
			config.SetSphereEmission(1.5f, true);  // Emit from sphere surface
			config.InitialSpeed = .(0.5f, 1.5f);
			config.InitialSize = .(0.15f, 0.3f);
			config.Lifetime = .(2.0f, 4.0f);
			config.StartColor = .(Color(100, 150, 255, 255));
			config.EndColor = .(Color(200, 50, 255, 0));
			config.Gravity = .(0, 0.3f, 0);
			config.BlendMode = .Additive;
			config.SetSizeOverLifetime(0.5f, 1.5f);
			mParticleSystem.Position = .(0, 1.5f, 0);
		}

		Console.WriteLine($"Switched to effect: {mEffectNames[effect]}");
	}

	private void SpawnFirework()
	{
		// Random position above ground
		let x = (float)gRand.NextDouble() * 6 - 3;
		let z = (float)gRand.NextDouble() * 6 - 3;
		mFireworkSystem.Position = .(x, 0, z);
		mFireworkSystem.Burst(1);
		Console.WriteLine("Firework spawned!");
	}

	private static Random gRand = new .() ~ delete _;

	private bool CreateBuffers()
	{
		BufferDescriptor cameraDesc = .(256, .Uniform, .Upload);
		if (Device.CreateBuffer(&cameraDesc) case .Ok(let camBuf))
			mCameraUniformBuffer = camBuf;
		else
			return false;

		BufferDescriptor particleUniformDesc = .((uint64)sizeof(Sedulous.Renderer.ParticleUniforms), .Uniform, .Upload);
		if (Device.CreateBuffer(&particleUniformDesc) case .Ok(let particleBuf))
			mParticleUniformBuffer = particleBuf;
		else
			return false;

		return true;
	}

	private bool CreateDefaultTexture()
	{
		// Create a 1x1 white texture for non-textured particles
		TextureDescriptor texDesc = TextureDescriptor.Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);

		if (Device.CreateTexture(&texDesc) not case .Ok(let texture))
			return false;
		mDefaultTexture = texture;

		// Upload white pixel
		uint8[4] whitePixel = .(255, 255, 255, 255);
		TextureDataLayout dataLayout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
		Extent3D writeSize = .(1, 1, 1);
		Device.Queue.WriteTexture(mDefaultTexture, Span<uint8>(&whitePixel, 4), &dataLayout, &writeSize);

		// Create texture view
		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
		if (Device.CreateTextureView(mDefaultTexture, &viewDesc) not case .Ok(let view))
			return false;
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
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return false;
		mDefaultSampler = sampler;

		return true;
	}

	private bool CreateSkybox()
	{
		mSkyboxRenderer = new SkyboxRenderer(Device);

		let topColor = Color(20, 20, 40, 255);      // Very dark purple-blue
		let bottomColor = Color(10, 10, 20, 255);  // Almost black

		if (!mSkyboxRenderer.CreateGradientSky(topColor, bottomColor, 32))
		{
			Console.WriteLine("Failed to create skybox");
			return false;
		}

		Console.WriteLine("Skybox created");
		return true;
	}

	private bool CreateParticleSystem()
	{
		mParticleSystem = new ParticleSystem(Device, 2000);

		// Configure as fountain effect using the new config API
		let config = mParticleSystem.Config;
		config.EmissionRate = 150;
		config.SetConeEmission(30);  // Emit in a cone
		config.InitialSpeed = .(6.0f, 10.0f);
		config.InitialSize = .(0.1f, 0.25f);
		config.Lifetime = .(2.0f, 3.5f);
		config.StartColor = .(Color(255, 200, 50, 255));    // Bright yellow-orange
		config.EndColor = .(Color(255, 50, 0, 100));        // Red-orange, transparent
		config.Gravity = .(0, -8.0f, 0);
		config.SetSizeOverLifetime(1.0f, 0.3f);  // Shrink to 30%

		// Enable LOD for distance-based optimization
		config.EnableLOD = true;
		config.LODStartDistance = 15.0f;
		config.LODEndDistance = 50.0f;

		// Enable particle sorting for alpha blending
		config.SortParticles = true;

		// Position emitter at origin
		mParticleSystem.Position = .(0.0f, 0.0f, 0.0f);

		Console.WriteLine("Particle system created with LOD and sorting enabled");
		return true;
	}

	private bool CreateFireworkSystem()
	{
		// Create firework particle system using preset
		// Store config separately since ParticleSystem doesn't take ownership of external configs
		mFireworkConfig = ParticleEmitterConfig.CreateFirework();
		mFireworkSystem = new ParticleSystem(Device, mFireworkConfig, 500);
		mFireworkSystem.IsEmitting = false;  // Manual bursts only
		mFireworkSystem.Position = .(0, 0, 0);

		Console.WriteLine("Firework system created with sub-emitters");
		return true;
	}

	private bool CreateSkyboxPipeline()
	{
		let shaderPath = GetAssetPath("framework/shaders/skybox", .. scope .());
		let shaderResult = ShaderUtils.LoadShaderPair(Device, shaderPath);
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load skybox shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .TextureCube),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mSkyboxBindGroupLayout = layout;

		IBindGroupLayout[1] layouts = .(mSkyboxBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mSkyboxPipelineLayout = pipelineLayout;

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Texture(0, mSkyboxRenderer.CubemapView),
			BindGroupEntry.Sampler(0, mSkyboxRenderer.Sampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mSkyboxBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mSkyboxBindGroup = group;

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .LessEqual;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSkyboxPipelineLayout,
			Vertex = .() { Shader = .(vertShader, "main"), Buffers = .() },
			Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = depthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
		{
			Console.WriteLine("Failed to create skybox pipeline");
			return false;
		}
		mSkyboxPipeline = pipeline;

		Console.WriteLine("Skybox pipeline created");
		return true;
	}

	private bool CreateParticlePipeline()
	{
		let shaderPath = GetAssetPath("framework/shaders/particle", .. scope .());
		let shaderResult = ShaderUtils.LoadShaderPair(Device, shaderPath);
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load particle shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout matching shader:
		// b0=camera, b1=particle uniforms, t0=texture, s0=sampler, t1=depth texture, s1=depth sampler
		BindGroupLayoutEntry[6] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),   // b0: camera
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),   // b1: particle uniforms
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),            // t0: texture
			BindGroupLayoutEntry.Sampler(0, .Fragment),                   // s0: sampler
			BindGroupLayoutEntry.SampledTexture(1, .Fragment),            // t1: depth texture (for soft particles)
			BindGroupLayoutEntry.Sampler(1, .Fragment)                    // s1: depth sampler
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mParticleBindGroupLayout = layout;

		IBindGroupLayout[1] layouts = .(mParticleBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mParticlePipelineLayout = pipelineLayout;

		BindGroupEntry[6] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),         // b0: camera
			BindGroupEntry.Buffer(1, mParticleUniformBuffer),       // b1: particle uniforms
			BindGroupEntry.Texture(0, mDefaultTextureView),         // t0: texture
			BindGroupEntry.Sampler(0, mDefaultSampler),             // s0: sampler
			BindGroupEntry.Texture(1, mDefaultTextureView),         // t1: depth texture (using default for non-soft)
			BindGroupEntry.Sampler(1, mDefaultSampler)              // s1: depth sampler
		);
		BindGroupDescriptor bindGroupDesc = .(mParticleBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mParticleBindGroup = group;

		// Updated ParticleVertex layout: 52 bytes
		// Position(12) + Size(8) + Color(4) + Rotation(4) + TexCoordOffset(8) + TexCoordScale(8) + Velocity2D(8)
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
			VertexBufferLayout(52, vertexAttrs, .Instance)
		);

		ColorTargetState[1] colorTargets = .(
			ColorTargetState(SwapChain.Format, BlendState.AlphaBlend)
		);

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mParticlePipelineLayout,
			Vertex = .() { Shader = .(vertShader, "main"), Buffers = vertexBuffers },
			Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = depthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
		{
			Console.WriteLine("Failed to create particle pipeline");
			return false;
		}
		mParticlePipeline = pipeline;

		Console.WriteLine("Particle pipeline created");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Update firework cooldown
		if (mFireworkCooldown > 0)
			mFireworkCooldown -= deltaTime;

		// Set camera position for sorting and LOD
		mParticleSystem.CameraPosition = mCamera.Position;
		mFireworkSystem.CameraPosition = mCamera.Position;

		// Update particle systems
		mParticleSystem.Update(deltaTime);
		mParticleSystem.Upload();

		mFireworkSystem.Update(deltaTime);
		mFireworkSystem.Upload();

		var projection = mCamera.ProjectionMatrix;
		let view = mCamera.ViewMatrix;

		if (Device.FlipProjectionRequired)
			projection.M22 = -projection.M22;

		BillboardCameraUniforms cameraData = .();
		cameraData.ViewProjection = view * projection;
		cameraData.View = view;
		cameraData.Projection = projection;
		cameraData.CameraPosition = mCamera.Position;

		Span<uint8> camData = .((uint8*)&cameraData, sizeof(BillboardCameraUniforms));
		Device.Queue.WriteBuffer(mCameraUniformBuffer, 0, camData);

		// Write particle uniforms
		Sedulous.Renderer.ParticleUniforms particleUniforms = Sedulous.Renderer.ParticleUniforms.Default;
		Span<uint8> particleData = .((uint8*)&particleUniforms, sizeof(Sedulous.Renderer.ParticleUniforms));
		Device.Queue.WriteBuffer(mParticleUniformBuffer, 0, particleData);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// Render skybox first
		if (mSkyboxPipeline != null && mSkyboxBindGroup != null && mSkyboxRenderer.IsValid)
		{
			renderPass.SetPipeline(mSkyboxPipeline);
			renderPass.SetBindGroup(0, mSkyboxBindGroup);
			renderPass.Draw(3, 1, 0, 0);
		}

		// Render particles
		if (mParticlePipeline != null && mParticleBindGroup != null)
		{
			renderPass.SetPipeline(mParticlePipeline);
			renderPass.SetBindGroup(0, mParticleBindGroup);

			// Render main particle system
			let particleCount = mParticleSystem.ParticleCount;
			if (particleCount > 0)
			{
				renderPass.SetVertexBuffer(0, mParticleSystem.VertexBuffer, 0);
				renderPass.SetIndexBuffer(mParticleSystem.IndexBuffer, .UInt16, 0);
				renderPass.DrawIndexed(6, (uint32)particleCount, 0, 0, 0);
			}

			// Render firework main particles
			let fireworkCount = mFireworkSystem.ParticleCount;
			if (fireworkCount > 0)
			{
				renderPass.SetVertexBuffer(0, mFireworkSystem.VertexBuffer, 0);
				renderPass.SetIndexBuffer(mFireworkSystem.IndexBuffer, .UInt16, 0);
				renderPass.DrawIndexed(6, (uint32)fireworkCount, 0, 0, 0);
			}

			// Render firework sub-emitter particles
			if (mFireworkSystem.HasActiveSubEmitters)
			{
				for (let instance in mFireworkSystem.SubEmitters.ActiveInstances)
				{
					let subSystem = instance.System;
					if (subSystem != null && subSystem.ParticleCount > 0)
					{
						renderPass.SetVertexBuffer(0, subSystem.VertexBuffer, 0);
						renderPass.SetIndexBuffer(subSystem.IndexBuffer, .UInt16, 0);
						renderPass.DrawIndexed(6, (uint32)subSystem.ParticleCount, 0, 0, 0);
					}
				}
			}
		}
	}

	protected override void OnCleanup()
	{
		if (mParticlePipeline != null) delete mParticlePipeline;
		if (mParticlePipelineLayout != null) delete mParticlePipelineLayout;
		if (mParticleBindGroup != null) delete mParticleBindGroup;
		if (mParticleBindGroupLayout != null) delete mParticleBindGroupLayout;

		if (mSkyboxPipeline != null) delete mSkyboxPipeline;
		if (mSkyboxPipelineLayout != null) delete mSkyboxPipelineLayout;
		if (mSkyboxBindGroup != null) delete mSkyboxBindGroup;
		if (mSkyboxBindGroupLayout != null) delete mSkyboxBindGroupLayout;

		if (mCameraUniformBuffer != null) delete mCameraUniformBuffer;
		if (mParticleUniformBuffer != null) delete mParticleUniformBuffer;

		if (mDefaultSampler != null) delete mDefaultSampler;
		if (mDefaultTextureView != null) delete mDefaultTextureView;
		if (mDefaultTexture != null) delete mDefaultTexture;

		if (mParticleSystem != null) delete mParticleSystem;
		if (mFireworkSystem != null) delete mFireworkSystem;
		if (mSkyboxRenderer != null) delete mSkyboxRenderer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RendererParticlesSample();
		return app.Run();
	}
}

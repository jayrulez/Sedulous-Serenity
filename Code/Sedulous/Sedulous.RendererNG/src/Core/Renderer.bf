namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Scene uniform data matching common.hlsli SceneUniforms (b0).
[Packed, CRepr]
struct SceneUniformData
{
	public Matrix ViewMatrix;
	public Matrix ProjectionMatrix;
	public Matrix ViewProjectionMatrix;
	public Matrix InverseViewMatrix;
	public Matrix InverseProjectionMatrix;
	public Matrix PreviousViewProjectionMatrix;

	public Vector3 CameraPosition;
	public float Time;

	public Vector3 CameraForward;
	public float DeltaTime;

	public Vector2 ScreenSize;
	public float NearPlane;
	public float FarPlane;

	public static Self Default => .()
	{
		ViewMatrix = .Identity,
		ProjectionMatrix = .Identity,
		ViewProjectionMatrix = .Identity,
		InverseViewMatrix = .Identity,
		InverseProjectionMatrix = .Identity,
		PreviousViewProjectionMatrix = .Identity,
		CameraPosition = .Zero,
		CameraForward = .(0, 0, -1),
		Time = 0,
		DeltaTime = 0.016f,
		ScreenSize = .(1280, 720),
		NearPlane = 0.1f,
		FarPlane = 1000.0f
	};
}

/// Directional light data.
[Packed, CRepr]
struct DirectionalLightData
{
	public Vector3 Direction;
	public float Intensity;
	public Vector3 Color;
	public float Padding;

	public static Self Default => .()
	{
		Direction = Vector3.Normalize(.(0.5f, -1.0f, 0.3f)),
		Intensity = 1.0f,
		Color = .(1.0f, 0.95f, 0.9f),
		Padding = 0
	};
}

/// Point light data.
[Packed, CRepr]
struct PointLightData
{
	public Vector3 Position;
	public float Range;
	public Vector3 Color;
	public float Intensity;

	public static Self Default => .()
	{
		Position = .Zero,
		Range = 10.0f,
		Color = .(1.0f, 1.0f, 1.0f),
		Intensity = 1.0f
	};
}

/// Lighting uniform data matching mesh.frag.hlsl LightingUniforms (b1).
[Packed, CRepr]
struct LightingUniformData
{
	public DirectionalLightData SunLight;
	public Vector3 AmbientColor;
	public float AmbientIntensity;
	public PointLightData[RenderConfig.MAX_POINT_LIGHTS] PointLights;
	public int32 ActivePointLights;
	public Vector3 _LightingPadding;

	public static Self Default => .()
	{
		SunLight = .Default,
		AmbientColor = .(0.3f, 0.35f, 0.4f),
		AmbientIntensity = 0.3f,
		PointLights = default,
		ActivePointLights = 0,
		_LightingPadding = .Zero
	};
}


/// Main entry point for the RendererNG system.
/// Owns all rendering subsystems and orchestrates frame rendering.
class Renderer : IDisposable
{
	private IDevice mDevice;
	private bool mInitialized = false;
	private uint32 mFrameNumber = 0;

	// Core systems
	private ResourcePool mResourcePool ~ delete _;
	private TransientBufferPool mTransientBuffers ~ delete _;
	private ShaderSystem mShaderSystem ~ delete _;
	private PipelineFactory mPipelineFactory ~ delete _;
	private BindGroupLayoutCache mLayoutCache ~ delete _;
	private MaterialSystem mMaterialSystem ~ delete _;
	// private RenderGraph mRenderGraph;

	// Pipeline layouts and pipelines
	private IPipelineLayout mMeshPipelineLayout ~ delete _;
	private IRenderPipeline mMeshPipeline; // Owned by PipelineFactory cache

	// Default material for meshes without a material assigned
	private Material mDefaultMaterial ~ delete _;
	private MaterialInstance mDefaultMaterialInstance ~ delete _;
	private IBindGroupLayout mDefaultMaterialLayout ~ delete _;
	private IBindGroup mDefaultMaterialBindGroup; // Managed by MaterialSystem

	// Draw systems
	private MeshDrawSystem mMeshDrawSystem ~ delete _;
	private SkyboxDrawSystem mSkyboxDrawSystem ~ delete _;
	private ParticleDrawSystem mParticleDrawSystem ~ delete _;
	// private SpriteDrawSystem mSpriteDrawSystem;
	// private ShadowDrawSystem mShadowDrawSystem;

	// Skybox bind group (scene + skybox uniforms + cubemap)
	private IBindGroup mSkyboxBindGroup ~ delete _;

	// Particle shaders and bind group
	private IShaderModule mParticleVertShader;
	private IShaderModule mParticleFragShader;
	private IBindGroup mParticleBindGroup ~ delete _;

	// Scene uniform buffer data
	private IBuffer mSceneUniformBuffer ~ delete _;
	private IBuffer mLightingUniformBuffer ~ delete _;
	private IBindGroup mSceneBindGroup ~ delete _;

	// Scene uniform bind group layout
	private IBindGroupLayout mSceneBindGroupLayout ~ delete _;

	// Statistics
	private RenderStats mStats;
	private RenderStatsAccumulator mStatsAccumulator = new .() ~ delete _;

	// Shader base path
	private String mShaderBasePath ~ delete _;

	// Render target formats
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;

	/// Gets the graphics device.
	public IDevice Device => mDevice;

	/// Gets whether the renderer has been initialized.
	public bool IsInitialized => mInitialized;

	/// Gets the resource pool.
	public ResourcePool Resources => mResourcePool;

	/// Gets the transient buffer pool.
	public TransientBufferPool TransientBuffers => mTransientBuffers;

	/// Gets the shader system.
	public ShaderSystem Shaders => mShaderSystem;

	/// Gets the pipeline factory.
	public PipelineFactory Pipelines => mPipelineFactory;

	/// Gets the bind group layout cache.
	public BindGroupLayoutCache LayoutCache => mLayoutCache;

	/// Gets the material system.
	public MaterialSystem Materials => mMaterialSystem;

	/// Gets the mesh draw system.
	public MeshDrawSystem MeshDraw => mMeshDrawSystem;

	/// Gets the skybox draw system.
	public SkyboxDrawSystem SkyboxDraw => mSkyboxDrawSystem;

	/// Gets the particle draw system.
	public ParticleDrawSystem ParticleDraw => mParticleDrawSystem;

	/// Gets the current frame statistics.
	public ref RenderStats Stats => ref mStats;

	/// Gets the statistics accumulator.
	public RenderStatsAccumulator StatsAccumulator => mStatsAccumulator;

	/// Gets the current frame number.
	public uint32 FrameNumber => mFrameNumber;

	/// Initializes the renderer with a graphics device.
	/// @param device The RHI device to use for rendering.
	/// @param shaderBasePath Base path for shader files.
	/// @param colorFormat The color target format for rendering.
	/// @param depthFormat The depth target format for rendering.
	/// @returns Success or error.
	public Result<void> Initialize(IDevice device, StringView shaderBasePath = "shaders",
								   TextureFormat colorFormat = .BGRA8UnormSrgb,
								   TextureFormat depthFormat = .Depth24PlusStencil8)
	{
		if (device == null)
			return .Err;

		if (mInitialized)
			return .Err; // Already initialized

		mDevice = device;
		mShaderBasePath = new String(shaderBasePath);
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		// Initialize core systems
		mResourcePool = new ResourcePool(device);
		mTransientBuffers = new TransientBufferPool(device);

		// Initialize shader system
		mShaderSystem = new ShaderSystem();
		if (mShaderSystem.Initialize(device, shaderBasePath) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize ShaderSystem");
			return .Err;
		}

		// Initialize bind group layout cache
		mLayoutCache = new BindGroupLayoutCache();
		mLayoutCache.Initialize(device);

		// Initialize pipeline factory
		mPipelineFactory = new PipelineFactory();
		if (mPipelineFactory.Initialize(device, mShaderSystem) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize PipelineFactory");
			return .Err;
		}

		// Initialize material system
		mMaterialSystem = new MaterialSystem();
		if (mMaterialSystem.Initialize(device, mResourcePool) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize MaterialSystem");
			return .Err;
		}

		// Create scene uniform buffers
		if (!CreateSceneBuffers())
		{
			Console.WriteLine("ERROR: Failed to create scene buffers");
			return .Err;
		}

		// Initialize mesh draw system (needs MeshPool from caller later)
		mMeshDrawSystem = new MeshDrawSystem();

		// Initialize skybox draw system
		mSkyboxDrawSystem = new SkyboxDrawSystem(this);
		if (mSkyboxDrawSystem.Initialize(device, colorFormat, depthFormat) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize SkyboxDrawSystem");
			return .Err;
		}

		// Initialize particle draw system
		mParticleDrawSystem = new ParticleDrawSystem(this);
		if (mParticleDrawSystem.Initialize(device, colorFormat, depthFormat) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize ParticleDrawSystem");
			return .Err;
		}

		mInitialized = true;
		Console.WriteLine("Renderer initialized with shader path: {}", shaderBasePath);
		return .Ok;
	}

	/// Initializes the mesh draw system with a mesh pool.
	/// Call after Initialize() when the MeshPool is ready.
	public void InitializeMeshSystem(MeshPool meshPool)
	{
		if (mMeshDrawSystem == null || meshPool == null)
			return;

		mMeshDrawSystem.Initialize(mDevice, meshPool, mTransientBuffers, mPipelineFactory, mLayoutCache);
	}

	/// Creates scene uniform buffers (Set 0: scene + lighting).
	private bool CreateSceneBuffers()
	{
		// Scene uniform buffer (matches SceneUniforms in common.hlsli)
		BufferDescriptor sceneDesc = .()
		{
			Size = (uint64)sizeof(SceneUniformData),
			Usage = .Uniform | .CopyDst
		};

		if (mDevice.CreateBuffer(&sceneDesc) case .Ok(let sceneBuffer))
			mSceneUniformBuffer = sceneBuffer;
		else
			return false;

		// Lighting uniform buffer
		BufferDescriptor lightDesc = .()
		{
			Size = (uint64)sizeof(LightingUniformData),
			Usage = .Uniform | .CopyDst
		};

		if (mDevice.CreateBuffer(&lightDesc) case .Ok(let lightBuffer))
			mLightingUniformBuffer = lightBuffer;
		else
			return false;

		// Create bind group layout for scene data (set 0 / space0)
		// b0: SceneUniforms, b1: LightingUniforms
		// Material uniforms are in set 1 / space1, managed by MaterialSystem
		BindGroupLayoutEntry[2] sceneEntries = .(
			.UniformBuffer(0, .Vertex | .Fragment), // SceneUniforms (b0, space0)
			.UniformBuffer(1, .Fragment)            // LightingUniforms (b1, space0)
		);

		if (mDevice.CreateBindGroupLayout(&BindGroupLayoutDescriptor() { Entries = sceneEntries }) case .Ok(let layout))
			mSceneBindGroupLayout = layout;
		else
			return false;

		// Create the bind group
		BindGroupEntry[2] bindEntries = .(
			.Buffer(0, mSceneUniformBuffer, 0, (uint64)sizeof(SceneUniformData)),
			.Buffer(1, mLightingUniformBuffer, 0, (uint64)sizeof(LightingUniformData))
		);

		if (mDevice.CreateBindGroup(&BindGroupDescriptor() { Layout = mSceneBindGroupLayout, Entries = bindEntries }) case .Ok(let group))
			mSceneBindGroup = group;
		else
			return false;

		return true;
	}

	/// Shuts down the renderer and releases resources.
	public void Shutdown()
	{
		if (!mInitialized)
			return;

		// Shutdown draw systems (reverse order)
		// delete mShadowDrawSystem; mShadowDrawSystem = null;
		// delete mSkyboxDrawSystem; mSkyboxDrawSystem = null;
		// delete mSpriteDrawSystem; mSpriteDrawSystem = null;
		// delete mParticleDrawSystem; mParticleDrawSystem = null;

		// Note: mMeshDrawSystem, mPipelineFactory, mLayoutCache, mShaderSystem
		// are deleted via ~ destructor pattern

		// Shutdown resource pool (flushes pending deletions)
		if (mResourcePool != null)
			mResourcePool.Shutdown();

		mDevice = null;
		mInitialized = false;
	}

	/// Begins a new frame.
	/// @param frameIndex Current frame index (for multi-buffering).
	/// @param deltaTime Time since last frame in seconds.
	/// @param totalTime Total elapsed time in seconds.
	public void BeginFrame(uint32 frameIndex, float deltaTime, float totalTime)
	{
		if (!mInitialized)
			return;

		mFrameNumber++;

		// Reset per-frame statistics
		mStats.Reset();

		// Reset transient buffers for this frame
		mTransientBuffers.BeginFrame((int32)frameIndex);

		// Begin frame on subsystems
		mPipelineFactory.BeginFrame(mFrameNumber);

		if (mMeshDrawSystem != null)
			mMeshDrawSystem.BeginFrame();

		if (mParticleDrawSystem != null)
			mParticleDrawSystem.BeginFrame();
	}

	/// Updates scene uniforms from a camera proxy.
	/// Call after BeginFrame and before rendering.
	public void PrepareFrame(CameraProxy* camera, float totalTime, float deltaTime, uint32 screenWidth, uint32 screenHeight)
	{
		if (!mInitialized || camera == null)
			return;

		// Build view matrix from camera
		let viewMatrix = Matrix.CreateLookAt(camera.Position, camera.Position + camera.Forward, camera.Up);
		var projMatrix = Matrix.CreatePerspectiveFieldOfView(
			camera.FieldOfView, camera.AspectRatio, camera.NearPlane, camera.FarPlane);
		// Flip Y for backends that require it (Vulkan has Y pointing down in NDC)
		if (mDevice.FlipProjectionRequired)
			projMatrix.M22 = -projMatrix.M22;
		let viewProj = viewMatrix * projMatrix;

		// Build scene uniform data
		var sceneData = SceneUniformData();
		sceneData.ViewMatrix = viewMatrix;
		sceneData.ProjectionMatrix = projMatrix;
		sceneData.ViewProjectionMatrix = viewProj;
		Matrix.Invert(viewMatrix, out sceneData.InverseViewMatrix);
		Matrix.Invert(projMatrix, out sceneData.InverseProjectionMatrix);
		sceneData.PreviousViewProjectionMatrix = viewProj; // TODO: track previous frame
		sceneData.CameraPosition = camera.Position;
		sceneData.CameraForward = camera.Forward;
		sceneData.Time = totalTime;
		sceneData.DeltaTime = deltaTime;
		sceneData.ScreenSize = .((float)screenWidth, (float)screenHeight);
		sceneData.NearPlane = camera.NearPlane;
		sceneData.FarPlane = camera.FarPlane;

		// Upload scene uniforms
		mDevice.Queue.WriteBuffer(mSceneUniformBuffer, 0, Span<uint8>((uint8*)&sceneData, sizeof(SceneUniformData)));

		// Update skybox uniforms (needs view/projection for inverse VP calculation)
		if (mSkyboxDrawSystem != null)
			mSkyboxDrawSystem.UpdateUniforms(viewMatrix, projMatrix);
	}

	/// Updates lighting uniforms from a render world.
	public void PrepareLighting(RenderWorld world)
	{
		if (!mInitialized || world == null)
			return;

		var lightingData = LightingUniformData.Default;
		int32 pointLightIndex = 0;

		// Collect lights from render world
		world.ForEachLight(scope [&lightingData, &pointLightIndex] (handle, light) => {
			if (!light.IsEnabled)
				return;

			if (light.Type == .Directional)
			{
				// Use first directional light as sun
				lightingData.SunLight.Direction = light.Direction;
				lightingData.SunLight.Color = light.Color;
				lightingData.SunLight.Intensity = light.Intensity;
			}
			else if (light.Type == .Point && pointLightIndex < RenderConfig.MAX_POINT_LIGHTS)
			{
				lightingData.PointLights[pointLightIndex].Position = light.Position;
				lightingData.PointLights[pointLightIndex].Range = light.Range;
				lightingData.PointLights[pointLightIndex].Color = light.Color;
				lightingData.PointLights[pointLightIndex].Intensity = light.Intensity;
				pointLightIndex++;
			}
		});

		lightingData.ActivePointLights = pointLightIndex;

		// Upload lighting uniforms
		mDevice.Queue.WriteBuffer(mLightingUniformBuffer, 0, Span<uint8>((uint8*)&lightingData, sizeof(LightingUniformData)));
	}

	/// Ends the current frame and records statistics.
	public void EndFrame()
	{
		if (!mInitialized)
			return;

		// Process deferred resource deletions
		mResourcePool.ProcessDeletions(mFrameNumber);

		// Record statistics
		mStatsAccumulator.RecordFrame(mStats);
	}

	/// Creates a new RenderWorld for a scene.
	/// @returns A new RenderWorld instance owned by the caller.
	public RenderWorld CreateRenderWorld()
	{
		return new RenderWorld();
	}

	/// Gets the scene bind group for rendering.
	public IBindGroup SceneBindGroup => mSceneBindGroup;

	/// Gets the scene bind group layout.
	public IBindGroupLayout SceneBindGroupLayout => mSceneBindGroupLayout;

	/// Renders all visible meshes from a RenderWorld.
	/// Call this from within a render pass.
	public void RenderMeshes(IRenderPassEncoder renderPass, RenderWorld world, MeshPool meshPool)
	{
		if (!mInitialized || world == null || meshPool == null)
			return;

		// Ensure we have the mesh pipeline
		if (mMeshPipeline == null)
		{
			if (!CreateMeshPipeline())
			{
				Console.WriteLine("ERROR: Failed to create mesh pipeline");
				return;
			}
		}

		// Collect visible static meshes
		world.ForEachStaticMesh(scope [&] (handle, proxy) => {
			if (proxy.IsVisible)
			{
				mMeshDrawSystem.AddFromProxy(proxy, meshPool, null); // null material for now
			}
		});

		// Build draw batches
		mMeshDrawSystem.BuildBatches();

		if (mMeshDrawSystem.BatchCount == 0)
			return;

		// Bind pipeline and bind groups
		renderPass.SetPipeline(mMeshPipeline);
		renderPass.SetBindGroup(0, mSceneBindGroup);           // Set 0: Scene + Lighting
		renderPass.SetBindGroup(1, mDefaultMaterialBindGroup); // Set 1: Material

		// Render all batches
		mMeshDrawSystem.Render(renderPass, mMeshPipelineLayout);

		// Update stats
		mStats.DrawCalls += (int32)mMeshDrawSystem.BatchCount;
	}

	/// Creates the standard mesh render pipeline with default PBR material.
	private bool CreateMeshPipeline()
	{
		// Create default PBR material if not already created
		if (mDefaultMaterial == null)
		{
			mDefaultMaterial = CreateDefaultPBRMaterial();
			if (mDefaultMaterial == null)
			{
				Console.WriteLine("ERROR: Failed to create default material");
				return false;
			}

			// Create material instance
			mDefaultMaterialInstance = new MaterialInstance(mDefaultMaterial);
			mDefaultMaterialInstance.SetColor("BaseColor", .(0.8f, 0.8f, 0.8f, 1.0f));
			mDefaultMaterialInstance.SetFloat("Metallic", 0.0f);
			mDefaultMaterialInstance.SetFloat("Roughness", 0.5f);
			mDefaultMaterialInstance.SetFloat("AO", 1.0f);
			mDefaultMaterialInstance.SetFloat("AlphaCutoff", 0.5f);
			mDefaultMaterialInstance.SetColor("EmissiveColor", .(0, 0, 0, 0));

			// Get bind group layout for material
			if (mMaterialSystem.GetOrCreateLayout(mDefaultMaterial) case .Ok(let layout))
				mDefaultMaterialLayout = layout;
			else
			{
				Console.WriteLine("ERROR: Failed to create material bind group layout");
				return false;
			}

			// Prepare material instance (creates bind group)
			if (mMaterialSystem.PrepareInstance(mDefaultMaterialInstance, mDefaultMaterialLayout) case .Ok(let bg))
				mDefaultMaterialBindGroup = bg;
			else
			{
				Console.WriteLine("ERROR: Failed to create material bind group");
				return false;
			}
		}

		// Create pipeline layout with scene and material bind groups
		if (mMeshPipelineLayout == null)
		{
			IBindGroupLayout[2] layouts = .(mSceneBindGroupLayout, mDefaultMaterialLayout);
			PipelineLayoutDescriptor layoutDesc = .()
			{
				BindGroupLayouts = layouts
			};

			if (mDevice.CreatePipelineLayout(&layoutDesc) case .Ok(let layout))
				mMeshPipelineLayout = layout;
			else
				return false;
		}

		// Create pipeline config for opaque instanced mesh
		var config = PipelineConfig.ForOpaqueMesh("mesh", .Instanced);
		config.ColorFormat = mColorFormat;
		config.DepthFormat = mDepthFormat;

		// Get or create pipeline
		if (mPipelineFactory.GetOrCreatePipeline(config, mMeshPipelineLayout) case .Ok(let pipeline))
		{
			mMeshPipeline = pipeline;
			Console.WriteLine("Mesh pipeline created successfully");
			return true;
		}

		return false;
	}

	/// Creates the default PBR material definition.
	private Material CreateDefaultPBRMaterial()
	{
		// Use MaterialBuilder to create a PBR material matching mesh.frag.hlsl
		let builder = scope MaterialBuilder("DefaultPBR");
		builder
			.Shader("mesh")
			.Flags(.Instanced)
			.VertexLayout(.PositionNormalUV)
			// Uniform properties (must match MaterialUniforms in mesh.frag.hlsl)
			.Color("BaseColor", .(1, 1, 1, 1))
			.Float("Metallic", 0.0f)
			.Float("Roughness", 0.5f)
			.Float("AO", 1.0f)
			.Float("AlphaCutoff", 0.5f)
			.Color("EmissiveColor", .(0, 0, 0, 0))
			// Textures (set default textures from MaterialSystem)
			.Texture("AlbedoMap", mMaterialSystem.WhiteTexture)
			.Texture("NormalMap", mMaterialSystem.NormalTexture)
			.Texture("MetallicRoughnessMap", mMaterialSystem.WhiteTexture)
			.Texture("EmissiveMap", mMaterialSystem.BlackTexture)
			.Texture("AOMap", mMaterialSystem.WhiteTexture)
			.Sampler("MaterialSampler", mMaterialSystem.DefaultSampler);

		return builder.Build();
	}

	/// Initializes the skybox system with shaders.
	/// Call after Initialize() to enable skybox rendering.
	/// @returns True if successful.
	public bool InitializeSkybox()
	{
		if (!mInitialized || mSkyboxDrawSystem == null)
			return false;

		// Get skybox shaders
		IShaderModule vertShader = null;
		IShaderModule fragShader = null;

		if (mShaderSystem.GetShader("skybox", .Vertex, .None) case .Ok(let vsModule))
		{
			if (vsModule.GetRhiModule(mDevice) case .Ok(let rhi))
				vertShader = rhi;
		}

		if (mShaderSystem.GetShader("skybox", .Fragment, .None) case .Ok(let fsModule))
		{
			if (fsModule.GetRhiModule(mDevice) case .Ok(let rhi))
				fragShader = rhi;
		}

		if (vertShader == null || fragShader == null)
		{
			Console.WriteLine("ERROR: Failed to get skybox shaders");
			return false;
		}

		// Create skybox pipeline
		if (mSkyboxDrawSystem.CreatePipeline(vertShader, fragShader) case .Err)
		{
			Console.WriteLine("ERROR: Failed to create skybox pipeline");
			return false;
		}

		// Create skybox bind group
		if (!CreateSkyboxBindGroup())
		{
			Console.WriteLine("ERROR: Failed to create skybox bind group");
			return false;
		}

		Console.WriteLine("Skybox system initialized");
		return true;
	}

	/// Creates the skybox bind group (scene + skybox uniforms + cubemap).
	private bool CreateSkyboxBindGroup()
	{
		if (mSkyboxDrawSystem == null)
			return false;

		// Bind group entries: b0=scene, b1=skybox, t0=cubemap, s0=sampler
		BindGroupEntry[4] entries = .(
			.Buffer(0, mSceneUniformBuffer, 0, (uint64)sizeof(SceneUniformData)),
			.Buffer(1, mSkyboxDrawSystem.UniformBuffer, 0, SkyboxUniforms.Size),
			.Texture(0, mSkyboxDrawSystem.CurrentCubemap),
			.Sampler(0, mSkyboxDrawSystem.CubemapSampler)
		);

		BindGroupDescriptor bgDesc = .(mSkyboxDrawSystem.BindGroupLayout, entries);
		if (mDevice.CreateBindGroup(&bgDesc) case .Ok(let bg))
		{
			if (mSkyboxBindGroup != null)
				delete mSkyboxBindGroup;
			mSkyboxBindGroup = bg;
			return true;
		}

		return false;
	}

	/// Sets the skybox cubemap texture.
	/// Pass null to use default black cubemap.
	public void SetSkyboxCubemap(ITextureView cubemap)
	{
		if (mSkyboxDrawSystem != null)
		{
			mSkyboxDrawSystem.SetCubemap(cubemap);
			// Recreate bind group with new cubemap
			CreateSkyboxBindGroup();
		}
	}

	/// Sets the skybox exposure (for HDR cubemaps).
	public void SetSkyboxExposure(float exposure)
	{
		if (mSkyboxDrawSystem != null)
			mSkyboxDrawSystem.SetExposure(exposure);
	}

	/// Sets the skybox rotation around the Y axis (radians).
	public void SetSkyboxRotation(float rotation)
	{
		if (mSkyboxDrawSystem != null)
			mSkyboxDrawSystem.SetRotation(rotation);
	}

	/// Renders the skybox.
	/// Call this after rendering opaque geometry (skybox uses depth test LessEqual).
	public void RenderSkybox(IRenderPassEncoder renderPass)
	{
		if (!mInitialized || mSkyboxDrawSystem == null || !mSkyboxDrawSystem.HasPipeline)
			return;

		mSkyboxDrawSystem.Render(renderPass, mSkyboxBindGroup);
		mStats.DrawCalls++;
	}

	// ========================================================================
	// Particle System
	// ========================================================================

	/// Initializes the particle system with shaders.
	/// Call after Initialize() to enable particle rendering.
	/// @returns True if successful.
	public bool InitializeParticles()
	{
		if (!mInitialized || mParticleDrawSystem == null)
			return false;

		// Get particle shaders
		if (mShaderSystem.GetShader("particle", .Vertex, .None) case .Ok(let vsModule))
		{
			if (vsModule.GetRhiModule(mDevice) case .Ok(let rhi))
				mParticleVertShader = rhi;
		}

		if (mShaderSystem.GetShader("particle", .Fragment, .None) case .Ok(let fsModule))
		{
			if (fsModule.GetRhiModule(mDevice) case .Ok(let rhi))
				mParticleFragShader = rhi;
		}

		if (mParticleVertShader == null || mParticleFragShader == null)
		{
			Console.WriteLine("ERROR: Failed to get particle shaders");
			return false;
		}

		// Create particle bind group
		if (!CreateParticleBindGroup())
		{
			Console.WriteLine("ERROR: Failed to create particle bind group");
			return false;
		}

		Console.WriteLine("Particle system initialized");
		return true;
	}

	/// Creates the particle bind group.
	private bool CreateParticleBindGroup()
	{
		if (mParticleDrawSystem == null)
			return false;

		// Update uniforms with defaults
		mParticleDrawSystem.UpdateUniformsDefault();

		// Create bind group
		if (mParticleDrawSystem.CreateBindGroup(mSceneUniformBuffer) case .Ok(let bg))
		{
			if (mParticleBindGroup != null)
				delete mParticleBindGroup;
			mParticleBindGroup = bg;
			return true;
		}

		return false;
	}

	/// Prepares a particle emitter for rendering.
	/// Call this for each visible emitter during the update phase.
	public void PrepareParticleEmitter(ParticleEmitter emitter)
	{
		if (!mInitialized || mParticleDrawSystem == null)
			return;

		mParticleDrawSystem.PrepareEmitter(emitter);
	}

	/// Renders all prepared particles.
	/// Call this after opaque geometry but before UI.
	public void RenderParticles(IRenderPassEncoder renderPass)
	{
		if (!mInitialized || mParticleDrawSystem == null || mParticleBindGroup == null)
			return;

		if (mParticleVertShader == null || mParticleFragShader == null)
			return;

		mParticleDrawSystem.RenderWithBindGroup(renderPass, mParticleBindGroup, true,
			mParticleVertShader, mParticleFragShader);

		mStats.DrawCalls += mParticleDrawSystem.Stats.DrawCalls;
	}

	/// Gets particle rendering statistics.
	public ParticleStats ParticleStats => mParticleDrawSystem?.Stats ?? .();

	public void Dispose()
	{
		Shutdown();
	}
}

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

/// Lighting uniform data matching mesh.frag.hlsl LightingUniforms (b1).
[Packed, CRepr]
struct LightingUniformData
{
	public DirectionalLightData SunLight;
	public Vector3 AmbientColor;
	public float AmbientIntensity;

	public static Self Default => .()
	{
		SunLight = .Default,
		AmbientColor = .(0.3f, 0.35f, 0.4f),
		AmbientIntensity = 0.3f
	};
}

/// Material uniform data matching mesh.frag.hlsl MaterialUniforms (b2).
[Packed, CRepr]
struct MaterialUniformData
{
	public Vector4 BaseColor;
	public float Metallic;
	public float Roughness;
	public float AO;
	public float AlphaCutoff;
	public Vector4 EmissiveColor;

	public static Self Default => .()
	{
		BaseColor = .(0.8f, 0.8f, 0.8f, 1.0f),
		Metallic = 0.0f,
		Roughness = 0.5f,
		AO = 1.0f,
		AlphaCutoff = 0.5f,
		EmissiveColor = .(0, 0, 0, 0)
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
	// private RenderGraph mRenderGraph;

	// Pipeline layouts and pipelines
	private IPipelineLayout mMeshPipelineLayout ~ delete _;
	private IRenderPipeline mMeshPipeline; // Owned by PipelineFactory cache

	// Draw systems
	private MeshDrawSystem mMeshDrawSystem ~ delete _;
	// private ParticleDrawSystem mParticleDrawSystem;
	// private SpriteDrawSystem mSpriteDrawSystem;
	// private SkyboxDrawSystem mSkyboxDrawSystem;
	// private ShadowDrawSystem mShadowDrawSystem;

	// Scene uniform buffer data
	private IBuffer mSceneUniformBuffer ~ delete _;
	private IBuffer mLightingUniformBuffer ~ delete _;
	private IBuffer mMaterialUniformBuffer ~ delete _;
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

	/// Gets the mesh draw system.
	public MeshDrawSystem MeshDraw => mMeshDrawSystem;

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

		// Create scene uniform buffers
		if (!CreateSceneBuffers())
		{
			Console.WriteLine("ERROR: Failed to create scene buffers");
			return .Err;
		}

		// Initialize mesh draw system (needs MeshPool from caller later)
		mMeshDrawSystem = new MeshDrawSystem();

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

	/// Creates scene uniform buffers.
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

		// Material uniform buffer (default material)
		BufferDescriptor materialDesc = .()
		{
			Size = (uint64)sizeof(MaterialUniformData),
			Usage = .Uniform | .CopyDst
		};

		if (mDevice.CreateBuffer(&materialDesc) case .Ok(let materialBuffer))
			mMaterialUniformBuffer = materialBuffer;
		else
			return false;

		// Upload default material values
		var defaultMaterial = MaterialUniformData.Default;
		mDevice.Queue.WriteBuffer(mMaterialUniformBuffer, 0, Span<uint8>((uint8*)&defaultMaterial, sizeof(MaterialUniformData)));

		// Create bind group layout for scene data (set 0)
		// b0: SceneUniforms, b1: LightingUniforms, b2: MaterialUniforms
		BindGroupLayoutEntry[3] sceneEntries = .(
			.UniformBuffer(0, .Vertex | .Fragment), // SceneUniforms
			.UniformBuffer(1, .Fragment),           // LightingUniforms
			.UniformBuffer(2, .Fragment)            // MaterialUniforms
		);

		if (mDevice.CreateBindGroupLayout(&BindGroupLayoutDescriptor() { Entries = sceneEntries }) case .Ok(let layout))
			mSceneBindGroupLayout = layout;
		else
			return false;

		// Create the bind group
		BindGroupEntry[3] bindEntries = .(
			.Buffer(0, mSceneUniformBuffer, 0, (uint64)sizeof(SceneUniformData)),
			.Buffer(1, mLightingUniformBuffer, 0, (uint64)sizeof(LightingUniformData)),
			.Buffer(2, mMaterialUniformBuffer, 0, (uint64)sizeof(MaterialUniformData))
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
	}

	/// Updates lighting uniforms from a render world.
	public void PrepareLighting(RenderWorld world)
	{
		if (!mInitialized || world == null)
			return;

		var lightingData = LightingUniformData.Default;

		// Find first directional light for sun
		world.ForEachLight(scope [&lightingData] (handle, light) => {
			if (light.Type == .Directional && light.IsEnabled)
			{
				lightingData.SunLight.Direction = light.Direction;
				lightingData.SunLight.Color = light.Color;
				lightingData.SunLight.Intensity = light.Intensity;
			}
		});

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

		// Bind pipeline and scene uniforms
		renderPass.SetPipeline(mMeshPipeline);
		renderPass.SetBindGroup(0, mSceneBindGroup);

		// Render all batches
		mMeshDrawSystem.Render(renderPass, mMeshPipelineLayout);

		// Update stats
		mStats.DrawCalls += (int32)mMeshDrawSystem.BatchCount;
	}

	/// Creates the standard mesh render pipeline.
	private bool CreateMeshPipeline()
	{
		// Create pipeline layout with scene bind group
		if (mMeshPipelineLayout == null)
		{
			IBindGroupLayout[1] layouts = .(mSceneBindGroupLayout);
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

	public void Dispose()
	{
		Shutdown();
	}
}

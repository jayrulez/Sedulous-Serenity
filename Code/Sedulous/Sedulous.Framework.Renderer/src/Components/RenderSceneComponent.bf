namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.Framework.Core;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;

/// Per-frame GPU resources to avoid GPU/CPU synchronization issues.
struct SceneFrameResources
{
	public IBuffer CameraBuffer;
	public IBuffer InstanceBuffer;
	public IBindGroup BindGroup;

	public void Dispose() mut
	{
		delete CameraBuffer;
		delete InstanceBuffer;
		delete BindGroup;
		this = default;
	}
}

/// Scene component that manages rendering for a scene.
/// Owns the RenderWorld (proxy pool), VisibilityResolver, GPU resources,
/// and coordinates entity-to-proxy synchronization.
class RenderSceneComponent : ISceneComponent
{
	private const int32 MAX_FRAMES_IN_FLIGHT = 2;
	private const int32 MAX_INSTANCES = 4096;

	private RendererService mRendererService;
	private Scene mScene;
	private RenderWorld mRenderWorld ~ delete _;
	private VisibilityResolver mVisibilityResolver ~ delete _;

	// Entity → Proxy mapping for each proxy type
	private Dictionary<EntityId, ProxyHandle> mMeshProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mLightProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mCameraProxies = new .() ~ delete _;

	// Cached lists for iteration
	private List<MeshProxy*> mVisibleMeshes = new .() ~ delete _;
	private List<LightProxy*> mActiveLights = new .() ~ delete _;

	// Particle emitters and sprites
	private List<ParticleEmitterComponent> mParticleEmitters = new .() ~ delete _;
	private List<SpriteComponent> mSprites = new .() ~ delete _;
	private SpriteRenderer mSpriteRenderer ~ delete _;

	// Skinned meshes
	private List<SkinnedMeshRendererComponent> mSkinnedMeshes = new .() ~ delete _;

	// Main camera handle
	private ProxyHandle mMainCamera = .Invalid;

	// ==================== GPU Rendering Infrastructure ====================

	// Per-frame resources
	private SceneFrameResources[MAX_FRAMES_IN_FLIGHT] mFrameResources = .();
	private int32 mCurrentFrameIndex = 0;

	// Pipeline resources (shared across frames)
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IRenderPipeline mPipeline ~ delete _;

	// Billboard pipeline resources (particles, sprites)
	private IBuffer[MAX_FRAMES_IN_FLIGHT] mBillboardCameraBuffers = .();
	private IBindGroupLayout mBillboardBindGroupLayout ~ delete _;
	private IPipelineLayout mBillboardPipelineLayout ~ delete _;
	private IBindGroup[MAX_FRAMES_IN_FLIGHT] mBillboardBindGroups = .();
	private IRenderPipeline mParticlePipeline ~ delete _;
	private IRenderPipeline mSpritePipeline ~ delete _;

	// Skinned mesh pipeline resources
	private IBindGroupLayout mSkinnedBindGroupLayout ~ delete _;
	private IPipelineLayout mSkinnedPipelineLayout ~ delete _;
	private IRenderPipeline mSkinnedPipeline ~ delete _;
	private IBuffer mSkinnedObjectBuffer ~ delete _;
	private ISampler mDefaultSampler ~ delete _;
	private ITexture mWhiteTexture ~ delete _;
	private ITextureView mWhiteTextureView ~ delete _;

	// CPU-side instance data (built in OnUpdate, uploaded in PrepareGPU)
	private RenderSceneInstanceData[] mInstanceData ~ delete _;
	private int32 mInstanceCount = 0;

	// Rendering state
	private bool mRenderingInitialized = false;
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mFlipProjection = false;

	// ==================== Properties ====================

	/// Gets the renderer service.
	public RendererService RendererService => mRendererService;

	/// Gets the render world for proxy management.
	public RenderWorld RenderWorld => mRenderWorld;

	/// Gets the visibility resolver.
	public VisibilityResolver VisibilityResolver => mVisibilityResolver;

	/// Gets or sets the main camera proxy handle.
	public ProxyHandle MainCamera
	{
		get => mMainCamera;
		set
		{
			mMainCamera = value;
			if (mRenderWorld != null)
				mRenderWorld.SetMainCamera(value);
		}
	}

	/// Gets the scene this component is attached to.
	public Scene Scene => mScene;

	/// Gets the list of visible meshes after culling.
	public List<MeshProxy*> VisibleMeshes => mVisibleMeshes;

	/// Gets the list of active lights.
	public List<LightProxy*> ActiveLights => mActiveLights;

	/// Gets the main camera proxy.
	public CameraProxy* GetMainCameraProxy() => mRenderWorld.MainCamera;

	/// Gets mesh count for statistics.
	public uint32 MeshCount => mRenderWorld.MeshCount;

	/// Gets light count for statistics.
	public uint32 LightCount => mRenderWorld.LightCount;

	/// Gets camera count for statistics.
	public uint32 CameraCount => mRenderWorld.CameraCount;

	/// Gets visible instance count for statistics.
	public int32 VisibleInstanceCount => mInstanceCount;

	// ==================== Constructor ====================

	/// Creates a new RenderSceneComponent.
	/// The RendererService must be initialized before passing here.
	public this(RendererService rendererService)
	{
		mRendererService = rendererService;
		mRenderWorld = new RenderWorld();
		mVisibilityResolver = new VisibilityResolver();
		mInstanceData = new RenderSceneInstanceData[MAX_INSTANCES];
	}

	// ==================== ISceneComponent Implementation ====================

	/// Called when the component is attached to a scene.
	public void OnAttach(Scene scene)
	{
		mScene = scene;
	}

	/// Called when the component is detached from a scene.
	public void OnDetach()
	{
		CleanupRendering();
		mRenderWorld.Clear();
		mMeshProxies.Clear();
		mLightProxies.Clear();
		mCameraProxies.Clear();
		mScene = null;
	}

	/// Called each frame to update the component.
	/// Syncs entity transforms to proxies, performs visibility culling,
	/// and builds CPU-side instance data.
	public void OnUpdate(float deltaTime)
	{
		if (mScene == null)
			return;

		// Sync entity transforms to proxies
		SyncProxies();

		// Prepare render world for this frame
		mRenderWorld.BeginFrame();

		// Perform visibility determination and build instance data
		if (let camera = mRenderWorld.MainCamera)
		{
			// Resolve visibility (frustum culling, LOD selection, sorting)
			mVisibilityResolver.Resolve(mRenderWorld, camera);

			// Get visible meshes
			mVisibleMeshes.Clear();
			mVisibleMeshes.AddRange(mVisibilityResolver.OpaqueMeshes);
			mVisibleMeshes.AddRange(mVisibilityResolver.TransparentMeshes);

			// Build CPU-side instance data from visible meshes
			BuildInstanceData();
		}

		// Gather active lights
		mRenderWorld.GetValidLightProxies(mActiveLights);
	}

	/// Called when the scene state changes.
	public void OnSceneStateChanged(SceneState oldState, SceneState newState)
	{
		if (newState == .Unloaded)
		{
			CleanupRendering();
			mRenderWorld.Clear();
			mMeshProxies.Clear();
			mLightProxies.Clear();
			mCameraProxies.Clear();
		}
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// RenderSceneComponent doesn't serialize its proxies - they're recreated
		// from entity components when the scene loads
		return .Ok;
	}

	// ==================== Rendering Initialization ====================

	/// Initializes GPU rendering resources.
	/// Call this after the swap chain is created to set up pipelines and buffers.
	public Result<void> InitializeRendering(TextureFormat colorFormat, TextureFormat depthFormat, bool flipProjection = false)
	{
		if (mRenderingInitialized)
			return .Ok;

		if (mRendererService?.Device == null)
			return .Err;

		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;
		mFlipProjection = flipProjection;

		let device = mRendererService.Device;

		// Create per-frame buffers
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			// Camera uniform buffer
			BufferDescriptor cameraDesc = .((uint64)sizeof(SceneCameraUniforms), .Uniform, .Upload);
			if (device.CreateBuffer(&cameraDesc) case .Ok(let buf))
				mFrameResources[i].CameraBuffer = buf;
			else
				return .Err;

			// Instance buffer
			uint64 instanceBufferSize = (uint64)(sizeof(RenderSceneInstanceData) * MAX_INSTANCES);
			BufferDescriptor instanceDesc = .(instanceBufferSize, .Vertex, .Upload);
			if (device.CreateBuffer(&instanceDesc) case .Ok(let instBuf))
				mFrameResources[i].InstanceBuffer = instBuf;
			else
				return .Err;
		}

		// Create pipeline
		if (CreatePipeline() case .Err)
			return .Err;

		// Create billboard camera buffers and pipelines for particles/sprites
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BufferDescriptor billboardCamDesc = .((uint64)sizeof(BillboardCameraUniforms), .Uniform, .Upload);
			if (device.CreateBuffer(&billboardCamDesc) case .Ok(let buf))
				mBillboardCameraBuffers[i] = buf;
			else
				return .Err;
		}

		if (CreateBillboardPipelines() case .Err)
			return .Err;

		// Create sprite renderer
		mSpriteRenderer = new SpriteRenderer(device);

		mRenderingInitialized = true;
		return .Ok;
	}

	private Result<void> CreatePipeline()
	{
		let device = mRendererService.Device;
		let shaderLibrary = mRendererService.ShaderLibrary;

		// Load shaders from Framework.Renderer shaders folder
		let vertResult = shaderLibrary.GetShader("scene_instanced", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = shaderLibrary.GetShader("scene_instanced", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// Bind group layout
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mPipelineLayout = pipelineLayout;

		// Create per-frame bind groups
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BindGroupEntry[1] entries = .(
				BindGroupEntry.Buffer(0, mFrameResources[i].CameraBuffer)
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			if (device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mFrameResources[i].BindGroup = group;
		}

		// Vertex layouts - mesh attributes
		Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float2, 24, 2)   // UV
		);

		// Instance attributes
		Sedulous.RHI.VertexAttribute[5] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 3),   // Row0
			.(VertexFormat.Float4, 16, 4),  // Row1
			.(VertexFormat.Float4, 32, 5),  // Row2
			.(VertexFormat.Float4, 48, 6),  // Row3
			.(VertexFormat.Float4, 64, 7)   // Color
		);

		VertexBufferLayout[2] vertexBuffers = .(
			.(48, meshAttrs, .Vertex),
			.(80, instanceAttrs, .Instance)
		);

		ColorTargetState[1] colorTargets = .(.(mColorFormat));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
			},
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return .Err;
		mPipeline = pipeline;

		return .Ok;
	}

	private Result<void> CreateBillboardPipelines()
	{
		let device = mRendererService.Device;

		// Billboard bind group layout (shared between particle and sprite pipelines)
		BindGroupLayoutEntry[1] billboardLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor billboardLayoutDesc = .(billboardLayoutEntries);
		if (device.CreateBindGroupLayout(&billboardLayoutDesc) not case .Ok(let layout))
			return .Err;
		mBillboardBindGroupLayout = layout;

		// Billboard pipeline layout
		IBindGroupLayout[1] billboardLayouts = .(mBillboardBindGroupLayout);
		PipelineLayoutDescriptor billboardPipelineLayoutDesc = .(billboardLayouts);
		if (device.CreatePipelineLayout(&billboardPipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mBillboardPipelineLayout = pipelineLayout;

		// Create per-frame billboard bind groups
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BindGroupEntry[1] entries = .(
				BindGroupEntry.Buffer(0, mBillboardCameraBuffers[i])
			);
			BindGroupDescriptor bindGroupDesc = .(mBillboardBindGroupLayout, entries);
			if (device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mBillboardBindGroups[i] = group;
		}

		// Create particle pipeline
		if (CreateParticlePipeline() case .Err)
			return .Err;

		// Create sprite pipeline
		if (CreateSpritePipeline() case .Err)
			return .Err;

		// Create skinned mesh pipeline resources
		if (CreateSkinnedPipeline() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateParticlePipeline()
	{
		let device = mRendererService.Device;
		let shaderLibrary = mRendererService.ShaderLibrary;

		// Load particle shaders
		let vertResult = shaderLibrary.GetShader("particle", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = shaderLibrary.GetShader("particle", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// ParticleVertex: Position(12) + Size(8) + Color(4) + Rotation(4) = 28 bytes
		Sedulous.RHI.VertexAttribute[4] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),          // Position
			.(VertexFormat.Float2, 12, 1),         // Size
			.(VertexFormat.UByte4Normalized, 20, 2), // Color
			.(VertexFormat.Float, 24, 3)           // Rotation
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(28, vertexAttrs, .Instance)
		);

		ColorTargetState[1] colorTargets = .(
			ColorTargetState(mColorFormat, .AlphaBlend)
		);

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;  // Particles don't write to depth
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mBillboardPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
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

		if (device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return .Err;
		mParticlePipeline = pipeline;

		return .Ok;
	}

	private Result<void> CreateSpritePipeline()
	{
		let device = mRendererService.Device;
		let shaderLibrary = mRendererService.ShaderLibrary;

		// Load sprite shaders
		let vertResult = shaderLibrary.GetShader("sprite", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = shaderLibrary.GetShader("sprite", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// SpriteInstance: Position(12) + Size(8) + UVRect(16) + Color(4) = 40 bytes
		Sedulous.RHI.VertexAttribute[4] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),          // Position
			.(VertexFormat.Float2, 12, 1),         // Size
			.(VertexFormat.Float4, 20, 2),         // UVRect
			.(VertexFormat.UByte4Normalized, 36, 3) // Color
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(40, vertexAttrs, .Instance)
		);

		ColorTargetState[1] colorTargets = .(
			ColorTargetState(mColorFormat, .AlphaBlend)
		);

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;  // Sprites don't write to depth
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mBillboardPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
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

		if (device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return .Err;
		mSpritePipeline = pipeline;

		return .Ok;
	}

	private Result<void> CreateSkinnedPipeline()
	{
		let device = mRendererService.Device;
		let shaderLibrary = mRendererService.ShaderLibrary;

		// Load skinned mesh shaders
		let vertResult = shaderLibrary.GetShader("skinned", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = shaderLibrary.GetShader("skinned", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// Bind group layout: b0=camera, b1=object, b2=bones, t0=texture, s0=sampler
		BindGroupLayoutEntry[5] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),  // Camera
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),  // Object
			BindGroupLayoutEntry.UniformBuffer(2, .Vertex),              // Bones
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mSkinnedBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mSkinnedBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mSkinnedPipelineLayout = pipelineLayout;

		// Create object uniform buffer
		BufferDescriptor objectDesc = .(128, .Uniform, .Upload);
		if (device.CreateBuffer(&objectDesc) case .Ok(let buf))
			mSkinnedObjectBuffer = buf;
		else
			return .Err;

		// Create default sampler
		SamplerDescriptor samplerDesc = .();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Linear;
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		if (device.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mDefaultSampler = sampler;
		else
			return .Err;

		// Create 1x1 white texture fallback
		TextureDescriptor texDesc = .Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);
		if (device.CreateTexture(&texDesc) case .Ok(let tex))
		{
			mWhiteTexture = tex;
			uint8[4] white = .(255, 255, 255, 255);
			TextureDataLayout texLayout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
			Extent3D size = .(1, 1, 1);
			Span<uint8> data = .(&white, 4);
			device.Queue.WriteTexture(mWhiteTexture, data, &texLayout, &size, 0, 0);

			TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D, MipLevelCount = 1, ArrayLayerCount = 1 };
			if (device.CreateTextureView(mWhiteTexture, &viewDesc) case .Ok(let view))
				mWhiteTextureView = view;
			else
				return .Err;
		}
		else
			return .Err;

		// SkinnedVertex layout: Position(12) + Normal(12) + UV(8) + Color(4) + Tangent(12) + Joints(8) + Weights(16) = 72 bytes
		Sedulous.RHI.VertexAttribute[7] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),              // Position
			.(VertexFormat.Float3, 12, 1),             // Normal
			.(VertexFormat.Float2, 24, 2),             // TexCoord
			.(VertexFormat.UByte4Normalized, 32, 3),   // Color
			.(VertexFormat.Float3, 36, 4),             // Tangent
			.(VertexFormat.UShort4, 48, 5),            // Joints
			.(VertexFormat.Float4, 56, 6)              // Weights
		);
		VertexBufferLayout[1] vertexBuffers = .(.(72, vertexAttrs));

		ColorTargetState[1] colorTargets = .(.(mColorFormat));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSkinnedPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
			},
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return .Err;
		mSkinnedPipeline = pipeline;

		return .Ok;
	}

	private void CleanupRendering()
	{
		if (!mRenderingInitialized)
			return;

		// Delete per-frame resources
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			mFrameResources[i].Dispose();

			// Billboard resources
			delete mBillboardCameraBuffers[i];
			mBillboardCameraBuffers[i] = null;
			delete mBillboardBindGroups[i];
			mBillboardBindGroups[i] = null;
		}

		mRenderingInitialized = false;
	}

	// ==================== Frame Rendering ====================

	/// Builds CPU-side instance data from visible meshes.
	/// Called during OnUpdate.
	private void BuildInstanceData()
	{
		mInstanceCount = 0;

		for (let proxy in mVisibleMeshes)
		{
			if (mInstanceCount >= MAX_INSTANCES)
				break;

			// Get color based on material ID (simple palette for now)
			let color = GetColorForMaterial(proxy.GetMaterial(0));
			mInstanceData[mInstanceCount] = .(proxy.Transform, color);
			mInstanceCount++;
		}
	}

	private Vector4 GetColorForMaterial(uint32 materialId)
	{
		// Simple color palette based on material ID
		switch (materialId % 8)
		{
		case 0: return .(0.9f, 0.3f, 0.3f, 1.0f);  // Red
		case 1: return .(0.3f, 0.9f, 0.3f, 1.0f);  // Green
		case 2: return .(0.3f, 0.3f, 0.9f, 1.0f);  // Blue
		case 3: return .(0.9f, 0.9f, 0.3f, 1.0f);  // Yellow
		case 4: return .(0.9f, 0.3f, 0.9f, 1.0f);  // Magenta
		case 5: return .(0.3f, 0.9f, 0.9f, 1.0f);  // Cyan
		case 6: return .(0.9f, 0.6f, 0.3f, 1.0f);  // Orange
		case 7: return .(0.7f, 0.7f, 0.7f, 1.0f);  // Gray
		default: return .(1.0f, 1.0f, 1.0f, 1.0f);
		}
	}

	/// Uploads per-frame GPU data.
	/// Call this in OnPrepareFrame after the fence wait.
	public void PrepareGPU(int32 frameIndex)
	{
		if (!mRenderingInitialized || mRendererService?.Device == null)
			return;

		mCurrentFrameIndex = frameIndex;
		ref SceneFrameResources frame = ref mFrameResources[frameIndex];
		let device = mRendererService.Device;

		// Upload instance data
		if (mInstanceCount > 0)
		{
			uint64 dataSize = (uint64)(sizeof(RenderSceneInstanceData) * mInstanceCount);
			Span<uint8> data = .((uint8*)mInstanceData.Ptr, (int)dataSize);
			device.Queue.WriteBuffer(frame.InstanceBuffer, 0, data);
		}

		// Upload camera uniforms
		if (let cameraProxy = mRenderWorld.MainCamera)
		{
			var projection = cameraProxy.ProjectionMatrix;
			let view = cameraProxy.ViewMatrix;

			if (mFlipProjection)
				projection.M22 = -projection.M22;

			// Scene camera uniforms (for mesh rendering)
			SceneCameraUniforms cameraData = .();
			cameraData.ViewProjection = view * projection;
			cameraData.CameraPosition = cameraProxy.Position;

			// DEBUG: Print camera info on first few frames
			static int32 debugCount = 0;
			if (debugCount < 3)
			{
				debugCount++;
				Console.WriteLine($"[CAM DEBUG] Pos=({cameraProxy.Position.X:F2},{cameraProxy.Position.Y:F2},{cameraProxy.Position.Z:F2}) Fwd=({cameraProxy.Forward.X:F2},{cameraProxy.Forward.Y:F2},{cameraProxy.Forward.Z:F2})");
				Console.WriteLine($"  View M11={view.M11:F4} M22={view.M22:F4} M33={view.M33:F4} M43={view.M43:F4}");
				Console.WriteLine($"  Proj M11={projection.M11:F4} M22={projection.M22:F4}");
			}

			Span<uint8> camData = .((uint8*)&cameraData, sizeof(SceneCameraUniforms));
			device.Queue.WriteBuffer(frame.CameraBuffer, 0, camData);

			// Billboard camera uniforms (for particles/sprites)
			BillboardCameraUniforms billboardCamData = .();
			billboardCamData.ViewProjection = view * projection;
			billboardCamData.View = view;
			billboardCamData.Projection = projection;
			billboardCamData.CameraPosition = cameraProxy.Position;

			Span<uint8> billboardCam = .((uint8*)&billboardCamData, sizeof(BillboardCameraUniforms));
			var buf = mBillboardCameraBuffers[frameIndex];// beef bug to access in function call
			device.Queue.WriteBuffer(buf, 0, billboardCam);
		}

		// Upload particle data
		for (let emitter in mParticleEmitters)
		{
			if (emitter.Visible && emitter.ParticleSystem != null)
				emitter.ParticleSystem.Upload();
		}

		// Build and upload sprite data
		if (mSpriteRenderer != null && mSprites.Count > 0)
		{
			mSpriteRenderer.Begin();
			for (let sprite in mSprites)
			{
				if (sprite.Visible)
					mSpriteRenderer.AddSprite(sprite.GetSpriteInstance());
			}
			mSpriteRenderer.End();
		}
	}

	/// Renders the scene to the given render pass.
	/// Call this in OnRender.
	public void Render(IRenderPassEncoder renderPass, uint32 viewportWidth, uint32 viewportHeight)
	{
		if (!mRenderingInitialized)
			return;

		renderPass.SetViewport(0, 0, viewportWidth, viewportHeight, 0, 1);
		renderPass.SetScissorRect(0, 0, viewportWidth, viewportHeight);

		ref SceneFrameResources frame = ref mFrameResources[mCurrentFrameIndex];

		// Render meshes
		if (mInstanceCount > 0)
		{
			renderPass.SetPipeline(mPipeline);
			renderPass.SetBindGroup(0, frame.BindGroup);

			let resourceManager = mRendererService.ResourceManager;
			if (resourceManager != null)
			{
				// Simple approach: draw all visible meshes using their GPU mesh
				int32 instanceOffset = 0;
				GPUMeshHandle lastMesh = .Invalid;

				for (int32 i = 0; i < mInstanceCount; i++)
				{
					let proxy = mVisibleMeshes[i];
					let meshHandle = proxy.MeshHandle;

					// When mesh changes, draw the batch
					if (i > 0 && !meshHandle.Equals(lastMesh))
					{
						DrawMeshBatch(renderPass, resourceManager, lastMesh, frame.InstanceBuffer, instanceOffset, i - instanceOffset);
						instanceOffset = i;
					}

					lastMesh = meshHandle;
				}

				// Draw final batch
				if (mInstanceCount > instanceOffset)
				{
					DrawMeshBatch(renderPass, resourceManager, lastMesh, frame.InstanceBuffer, instanceOffset, mInstanceCount - instanceOffset);
				}
			}
		}

		// Render particles
		if (mParticlePipeline != null && mBillboardBindGroups[mCurrentFrameIndex] != null)
		{
			renderPass.SetPipeline(mParticlePipeline);
			renderPass.SetBindGroup(0, mBillboardBindGroups[mCurrentFrameIndex]);

			for (let emitter in mParticleEmitters)
			{
				if (!emitter.Visible)
					continue;

				let particleSystem = emitter.ParticleSystem;
				if (particleSystem == null)
					continue;

				let particleCount = particleSystem.ParticleCount;
				if (particleCount > 0)
				{
					renderPass.SetVertexBuffer(0, particleSystem.VertexBuffer, 0);
					renderPass.SetIndexBuffer(particleSystem.IndexBuffer, .UInt16, 0);
					renderPass.DrawIndexed(6, (uint32)particleCount, 0, 0, 0);
				}
			}
		}

		// Render sprites
		if (mSpritePipeline != null && mSpriteRenderer != null && mBillboardBindGroups[mCurrentFrameIndex] != null)
		{
			let spriteCount = mSpriteRenderer.SpriteCount;
			if (spriteCount > 0)
			{
				renderPass.SetPipeline(mSpritePipeline);
				renderPass.SetBindGroup(0, mBillboardBindGroups[mCurrentFrameIndex]);
				renderPass.SetVertexBuffer(0, mSpriteRenderer.InstanceBuffer, 0);
				renderPass.Draw(6, (uint32)spriteCount, 0, 0);
			}
		}

		// Render skinned meshes
		RenderSkinnedMeshes(renderPass);

		// End frame on render world
		mRenderWorld.EndFrame();
	}

	private void DrawMeshBatch(IRenderPassEncoder renderPass, GPUResourceManager resourceManager,
		GPUMeshHandle meshHandle, IBuffer instanceBuffer, int32 instanceOffset, int32 instanceCount)
	{
		let gpuMesh = resourceManager.GetMesh(meshHandle);
		if (gpuMesh == null)
			return;

		renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);
		renderPass.SetVertexBuffer(1, instanceBuffer, (uint64)(instanceOffset * sizeof(RenderSceneInstanceData)));

		if (gpuMesh.IndexBuffer != null)
		{
			renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
			renderPass.DrawIndexed(gpuMesh.IndexCount, (uint32)instanceCount, 0, 0, 0);
		}
		else
		{
			renderPass.Draw(gpuMesh.VertexCount, (uint32)instanceCount, 0, 0);
		}
	}

	private void RenderSkinnedMeshes(IRenderPassEncoder renderPass)
	{
		if (mSkinnedPipeline == null || mSkinnedMeshes.Count == 0)
			return;

		let device = mRendererService.Device;
		let resourceManager = mRendererService.ResourceManager;
		if (device == null || resourceManager == null)
			return;

		renderPass.SetPipeline(mSkinnedPipeline);

		for (let skinnedComp in mSkinnedMeshes)
		{
			if (!skinnedComp.Visible)
				continue;

			let meshHandle = skinnedComp.GPUMeshHandle;
			if (!meshHandle.IsValid)
				continue;

			let gpuMesh = resourceManager.GetSkinnedMesh(meshHandle);
			if (gpuMesh == null)
				continue;

			let boneBuffer = skinnedComp.BoneMatrixBuffer;
			if (boneBuffer == null)
				continue;

			// Create or update bind group for this skinned mesh
			if (skinnedComp.BindGroup == null)
			{
				let cameraBuffer = mFrameResources[mCurrentFrameIndex].CameraBuffer;
				ITextureView textureView = skinnedComp.TextureView;
				if (textureView == null)
					textureView = mWhiteTextureView;

				BindGroupEntry[5] entries = .(
					BindGroupEntry.Buffer(0, cameraBuffer),
					BindGroupEntry.Buffer(1, mSkinnedObjectBuffer),
					BindGroupEntry.Buffer(2, boneBuffer),
					BindGroupEntry.Texture(0, textureView),
					BindGroupEntry.Sampler(0, mDefaultSampler)
				);
				BindGroupDescriptor bindGroupDesc = .(mSkinnedBindGroupLayout, entries);
				if (device.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
					skinnedComp.BindGroup = group;
				else
					continue;
			}

			// Update object buffer with this mesh's transform
			Matrix modelMatrix = .Identity;
			if (skinnedComp.Entity != null)
				modelMatrix = skinnedComp.Entity.Transform.WorldMatrix;
			Vector4 baseColor = .(1, 1, 1, 1);

			// ObjectUniforms: Model (64 bytes) + BaseColor (16 bytes) = 80 bytes
			uint8[80] objectData = .();
			Internal.MemCpy(&objectData[0], &modelMatrix, sizeof(Matrix));
			Internal.MemCpy(&objectData[64], &baseColor, sizeof(Vector4));
			Span<uint8> objSpan = .(&objectData, 80);
			device.Queue.WriteBuffer(mSkinnedObjectBuffer, 0, objSpan);

			renderPass.SetBindGroup(0, skinnedComp.BindGroup);
			renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);

			if (gpuMesh.IndexBuffer != null)
			{
				renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
				renderPass.DrawIndexed(gpuMesh.IndexCount, 1, 0, 0, 0);
			}
			else
			{
				renderPass.Draw(gpuMesh.VertexCount, 1, 0, 0);
			}
		}
	}

	/// Ends the current frame.
	/// Call this after rendering is complete (called automatically by Render).
	public void EndFrame()
	{
		mRenderWorld.EndFrame();
	}

	// ==================== Proxy Management ====================

	/// Creates a mesh proxy for an entity.
	public ProxyHandle CreateMeshProxy(EntityId entityId, GPUMeshHandle mesh, Matrix transform, BoundingBox bounds)
	{
		// Remove existing proxy if any
		if (mMeshProxies.TryGetValue(entityId, let existing))
		{
			mRenderWorld.DestroyMeshProxy(existing);
			mMeshProxies.Remove(entityId);
		}

		let handle = mRenderWorld.CreateMeshProxy(mesh, transform, bounds);
		if (handle.IsValid)
			mMeshProxies[entityId] = handle;

		return handle;
	}

	/// Creates a directional light proxy for an entity.
	public ProxyHandle CreateDirectionalLight(EntityId entityId, Vector3 direction, Vector3 color, float intensity)
	{
		RemoveLightProxy(entityId);
		let handle = mRenderWorld.CreateDirectionalLight(direction, color, intensity);
		if (handle.IsValid)
			mLightProxies[entityId] = handle;
		return handle;
	}

	/// Creates a point light proxy for an entity.
	public ProxyHandle CreatePointLight(EntityId entityId, Vector3 position, Vector3 color, float intensity, float range)
	{
		RemoveLightProxy(entityId);
		let handle = mRenderWorld.CreatePointLight(position, color, intensity, range);
		if (handle.IsValid)
			mLightProxies[entityId] = handle;
		return handle;
	}

	/// Creates a spot light proxy for an entity.
	public ProxyHandle CreateSpotLight(EntityId entityId, Vector3 position, Vector3 direction, Vector3 color,
		float intensity, float range, float innerAngle, float outerAngle)
	{
		RemoveLightProxy(entityId);
		let handle = mRenderWorld.CreateSpotLight(position, direction, color, intensity, range, innerAngle, outerAngle);
		if (handle.IsValid)
			mLightProxies[entityId] = handle;
		return handle;
	}

	/// Creates a camera proxy for an entity.
	public ProxyHandle CreateCameraProxy(EntityId entityId, Camera camera, uint32 viewportWidth, uint32 viewportHeight, bool isMain = false)
	{
		RemoveCameraProxy(entityId);
		let handle = mRenderWorld.CreateCamera(camera, viewportWidth, viewportHeight, isMain);
		if (handle.IsValid)
		{
			mCameraProxies[entityId] = handle;
			if (isMain)
				mMainCamera = handle;
		}
		return handle;
	}

	/// Destroys a mesh proxy for an entity.
	public void DestroyMeshProxy(EntityId entityId)
	{
		if (mMeshProxies.TryGetValue(entityId, let handle))
		{
			mRenderWorld.DestroyMeshProxy(handle);
			mMeshProxies.Remove(entityId);
		}
	}

	/// Destroys a light proxy for an entity.
	public void RemoveLightProxy(EntityId entityId)
	{
		if (mLightProxies.TryGetValue(entityId, let handle))
		{
			mRenderWorld.DestroyLightProxy(handle);
			mLightProxies.Remove(entityId);
		}
	}

	/// Destroys a camera proxy for an entity.
	public void RemoveCameraProxy(EntityId entityId)
	{
		if (mCameraProxies.TryGetValue(entityId, let handle))
		{
			if (mMainCamera.Equals(handle))
				mMainCamera = .Invalid;
			mRenderWorld.DestroyCameraProxy(handle);
			mCameraProxies.Remove(entityId);
		}
	}

	/// Gets the mesh proxy handle for an entity.
	public ProxyHandle GetMeshProxy(EntityId entityId)
	{
		if (mMeshProxies.TryGetValue(entityId, let handle))
			return handle;
		return .Invalid;
	}

	/// Gets the light proxy handle for an entity.
	public ProxyHandle GetLightProxy(EntityId entityId)
	{
		if (mLightProxies.TryGetValue(entityId, let handle))
			return handle;
		return .Invalid;
	}

	/// Gets the camera proxy handle for an entity.
	public ProxyHandle GetCameraProxy(EntityId entityId)
	{
		if (mCameraProxies.TryGetValue(entityId, let handle))
			return handle;
		return .Invalid;
	}

	// ==================== Particle & Sprite Management ====================

	/// Registers a particle emitter component.
	public void RegisterParticleEmitter(ParticleEmitterComponent emitter)
	{
		if (!mParticleEmitters.Contains(emitter))
			mParticleEmitters.Add(emitter);
	}

	/// Unregisters a particle emitter component.
	public void UnregisterParticleEmitter(ParticleEmitterComponent emitter)
	{
		mParticleEmitters.Remove(emitter);
	}

	/// Registers a sprite component.
	public void RegisterSprite(SpriteComponent sprite)
	{
		if (!mSprites.Contains(sprite))
			mSprites.Add(sprite);
	}

	/// Unregisters a sprite component.
	public void UnregisterSprite(SpriteComponent sprite)
	{
		mSprites.Remove(sprite);
	}

	/// Gets the list of registered particle emitters.
	public List<ParticleEmitterComponent> ParticleEmitters => mParticleEmitters;

	/// Gets the list of registered sprites.
	public List<SpriteComponent> Sprites => mSprites;

	/// Registers a skinned mesh component.
	public void RegisterSkinnedMesh(SkinnedMeshRendererComponent skinnedMesh)
	{
		if (!mSkinnedMeshes.Contains(skinnedMesh))
			mSkinnedMeshes.Add(skinnedMesh);
	}

	/// Unregisters a skinned mesh component.
	public void UnregisterSkinnedMesh(SkinnedMeshRendererComponent skinnedMesh)
	{
		mSkinnedMeshes.Remove(skinnedMesh);
	}

	/// Gets the list of registered skinned meshes.
	public List<SkinnedMeshRendererComponent> SkinnedMeshes => mSkinnedMeshes;

	/// Gets the sprite renderer.
	public SpriteRenderer SpriteRenderer => mSpriteRenderer;

	// ==================== Frame Sync ====================

	/// Synchronizes all entity transforms to their proxies.
	/// Called each frame during OnUpdate.
	private void SyncProxies()
	{
		if (mScene == null)
			return;

		// Iterate all entities and sync transforms
		for (let entity in mScene.EntityManager)
		{
			let worldMatrix = entity.Transform.WorldMatrix;
			let entityId = entity.Id;

			// Sync mesh proxies
			if (mMeshProxies.TryGetValue(entityId, let meshHandle))
			{
				if (let proxy = mRenderWorld.GetMeshProxy(meshHandle))
				{
					proxy.Transform = worldMatrix;
					proxy.UpdateWorldBounds();
					proxy.Flags |= .Dirty;
				}
			}

			// Sync light proxies
			if (mLightProxies.TryGetValue(entityId, let lightHandle))
			{
				if (let proxy = mRenderWorld.GetLightProxy(lightHandle))
				{
					proxy.Position = entity.Transform.WorldPosition;
					// For directional/spot lights, update direction from forward vector
					if (proxy.Type == .Directional || proxy.Type == .Spot)
						proxy.Direction = entity.Transform.Forward;
				}
			}

			// Sync camera proxies
			if (mCameraProxies.TryGetValue(entityId, let cameraHandle))
			{
				if (let proxy = mRenderWorld.GetCameraProxy(cameraHandle))
				{
					proxy.Position = entity.Transform.WorldPosition;
					proxy.Forward = entity.Transform.Forward;
					proxy.Up = entity.Transform.Up;
					proxy.Right = entity.Transform.Right;
					proxy.UpdateMatrices();
				}
			}
		}
	}
}

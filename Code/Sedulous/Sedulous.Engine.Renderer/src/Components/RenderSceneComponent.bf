namespace Sedulous.Engine.Renderer;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;

/// Per-frame GPU resources to avoid GPU/CPU synchronization issues.
struct SceneFrameResources
{
	public IBuffer CameraBuffer;
	public IBindGroup BindGroup;

	public void Dispose() mut
	{
		delete CameraBuffer;
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
	private const int32 SHADOW_MAP_SIZE = 2048;

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

	// Main camera handle
	private ProxyHandle mMainCamera = .Invalid;

	// ==================== GPU Rendering Infrastructure ====================

	// Lighting system for shadows and clustered lighting
	private LightingSystem mLightingSystem ~ delete _;
	private bool mShadowsEnabled = true;

	// Dedicated renderers
	private StaticMeshRenderer mStaticMeshRenderer ~ delete _;
	private ShadowRenderer mShadowRenderer ~ delete _;
	private SkinnedMeshRenderer mSkinnedMeshRenderer ~ delete _;

	// Per-frame resources
	private SceneFrameResources[MAX_FRAMES_IN_FLIGHT] mFrameResources = .();
	private int32 mCurrentFrameIndex = 0;

	// Pipeline resources (shared across frames)
	private IBindGroupLayout mBindGroupLayout ~ delete _;

	// Billboard camera buffers (shared by particle and sprite renderers)
	private IBuffer[MAX_FRAMES_IN_FLIGHT] mBillboardCameraBuffers = .();
	private ParticleRenderer mParticleRenderer ~ delete _;

	// Skybox resources
	private SkyboxRenderer mSkyboxRenderer ~ delete _;
	private bool mSkyboxEnabled = true;

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

	/// Gets visible instance count for statistics (static + skinned meshes).
	public int32 VisibleInstanceCount => (mStaticMeshRenderer?.VisibleMeshCount ?? 0) + (mSkinnedMeshRenderer?.VisibleMeshCount ?? 0);

	/// Gets the lighting system (for shadow rendering).
	public LightingSystem LightingSystem => mLightingSystem;

	/// Gets or sets whether shadows are enabled.
	public bool ShadowsEnabled
	{
		get => mShadowsEnabled;
		set => mShadowsEnabled = value;
	}

	/// Gets whether the lighting system has directional shadows this frame.
	public bool HasDirectionalShadows => mLightingSystem?.HasDirectionalShadows ?? false;

	/// Gets the skybox renderer.
	public SkyboxRenderer SkyboxRenderer => mSkyboxRenderer;

	/// Gets or sets whether skybox rendering is enabled.
	public bool SkyboxEnabled
	{
		get => mSkyboxEnabled;
		set => mSkyboxEnabled = value;
	}

	// ==================== Constructor ====================

	/// Creates a new RenderSceneComponent.
	/// The RendererService must be initialized before passing here.
	public this(RendererService rendererService)
	{
		mRendererService = rendererService;
		mRenderWorld = new RenderWorld();
		mVisibilityResolver = new VisibilityResolver();
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

			// Build batches using dedicated renderers
			if (mStaticMeshRenderer != null)
				mStaticMeshRenderer.BuildBatches(mVisibleMeshes);

			if (mSkinnedMeshRenderer != null)
				mSkinnedMeshRenderer.BuildBatches();
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

		// Create lighting system
		mLightingSystem = new LightingSystem(device);

		// Create per-frame buffers
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			// Camera uniform buffer
			BufferDescriptor cameraDesc = .((uint64)sizeof(SceneCameraUniforms), .Uniform, .Upload);
			if (device.CreateBuffer(&cameraDesc) case .Ok(let buf))
				mFrameResources[i].CameraBuffer = buf;
			else
				return .Err;
		}

		// Create scene bind groups (used by material renderers)
		if (CreateSceneBindGroups() case .Err)
			return .Err;

		// Create billboard camera buffers (shared by particle and sprite renderers)
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BufferDescriptor billboardCamDesc = .((uint64)sizeof(BillboardCameraUniforms), .Uniform, .Upload);
			if (device.CreateBuffer(&billboardCamDesc) case .Ok(let buf))
				mBillboardCameraBuffers[i] = buf;
			else
				return .Err;
		}

		// Initialize dedicated renderers
		mStaticMeshRenderer = new StaticMeshRenderer();
		if (mStaticMeshRenderer.Initialize(device, mRendererService.ShaderLibrary,
			mRendererService.ResourceManager, mRendererService.MaterialSystem, mRendererService.PipelineCache,
			mBindGroupLayout, colorFormat, depthFormat) case .Err)
			return .Err;

		mShadowRenderer = new ShadowRenderer();
		if (mShadowRenderer.Initialize(device, mRendererService.ShaderLibrary,
			mLightingSystem, mRendererService.ResourceManager) case .Err)
			return .Err;

		mSkinnedMeshRenderer = new SkinnedMeshRenderer();
		if (mSkinnedMeshRenderer.Initialize(device, mRendererService.ShaderLibrary,
			mRendererService.MaterialSystem, mRendererService.ResourceManager, mRendererService.PipelineCache,
			mBindGroupLayout, colorFormat, depthFormat) case .Err)
			return .Err;

		// Create default skybox (gradient sky)
		mSkyboxRenderer = new SkyboxRenderer(device);
		let topColor = Color(70, 130, 200, 255);     // Sky blue
		let bottomColor = Color(180, 210, 240, 255); // Horizon light blue
		if (!mSkyboxRenderer.CreateGradientSky(topColor, bottomColor, 32))
			return .Err;

		// Initialize skybox renderer with pipeline
		IBuffer[2] cameraBuffers = .(mFrameResources[0].CameraBuffer, mFrameResources[1].CameraBuffer);
		if (mSkyboxRenderer.Initialize(mRendererService.ShaderLibrary, cameraBuffers, colorFormat, depthFormat) case .Err)
			return .Err;

		// Create and initialize sprite renderer
		IBuffer[2] billboardCameraBuffers = .(mBillboardCameraBuffers[0], mBillboardCameraBuffers[1]);
		mSpriteRenderer = new SpriteRenderer(device);
		if (mSpriteRenderer.Initialize(mRendererService.ShaderLibrary, billboardCameraBuffers, colorFormat, depthFormat) case .Err)
			return .Err;

		// Create and initialize particle renderer
		mParticleRenderer = new ParticleRenderer(device);
		if (mParticleRenderer.Initialize(mRendererService.ShaderLibrary, billboardCameraBuffers, colorFormat, depthFormat) case .Err)
			return .Err;

		mRenderingInitialized = true;
		return .Ok;
	}

	/// Creates the scene bind group layout and per-frame bind groups.
	/// These are shared by all material-based renderers (StaticMeshRenderer, etc).
	private Result<void> CreateSceneBindGroups()
	{
		let device = mRendererService.Device;

		// Bind group layout with lighting and shadow resources
		BindGroupLayoutEntry[7] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),    // Camera uniforms (b0)
			BindGroupLayoutEntry.UniformBuffer(2, .Fragment),               // Lighting uniforms (b2)
			BindGroupLayoutEntry.StorageBuffer(0, .Fragment),               // Light buffer (t0)
			BindGroupLayoutEntry.UniformBuffer(3, .Fragment),               // Shadow uniforms (b3)
			BindGroupLayoutEntry.SampledTexture(1, .Fragment, .Texture2DArray),  // Cascade shadow map (t1)
			BindGroupLayoutEntry.SampledTexture(2, .Fragment, .Texture2D),       // Shadow atlas (t2)
			BindGroupLayoutEntry.Sampler(0, .Fragment)                           // Shadow sampler (s0)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mBindGroupLayout = layout;

		// Create per-frame bind groups with lighting resources
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BindGroupEntry[7] entries = .(
				BindGroupEntry.Buffer(0, mFrameResources[i].CameraBuffer),
				BindGroupEntry.Buffer(2, mLightingSystem.GetLightingUniformBuffer((int32)i)),
				BindGroupEntry.Buffer(0, mLightingSystem.GetLightBuffer((int32)i)),
				BindGroupEntry.Buffer(3, mLightingSystem.GetShadowUniformBuffer((int32)i)),
				BindGroupEntry.Texture(1, mLightingSystem.CascadeShadowMapView),
				BindGroupEntry.Texture(2, mLightingSystem.ShadowAtlasView),
				BindGroupEntry.Sampler(0, mLightingSystem.ShadowSampler)
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			if (device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mFrameResources[i].BindGroup = group;
		}

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

			// Billboard camera buffers (bind groups owned by renderers)
			delete mBillboardCameraBuffers[i];
			mBillboardCameraBuffers[i] = null;
		}

		mRenderingInitialized = false;
	}

	// ==================== Frame Rendering ====================

	/// Uploads per-frame GPU data.
	/// Call this in OnPrepareFrame after the fence wait.
	public void PrepareGPU(int32 frameIndex)
	{
		if (!mRenderingInitialized || mRendererService?.Device == null)
			return;

		mCurrentFrameIndex = frameIndex;
		ref SceneFrameResources frame = ref mFrameResources[frameIndex];
		let device = mRendererService.Device;

		// Upload instance data using static mesh renderer
		if (mStaticMeshRenderer != null)
			mStaticMeshRenderer.PrepareGPU(frameIndex);

		// Update lighting system with camera and lights
		if (mLightingSystem != null && mShadowsEnabled)
		{
			if (let cameraProxy = mRenderWorld.MainCamera)
			{
				mLightingSystem.Update(cameraProxy, mActiveLights, frameIndex);
				mLightingSystem.PrepareShadows(cameraProxy);
				mLightingSystem.UploadShadowUniforms(frameIndex);
			}
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
			cameraData.View = view;
			cameraData.Projection = projection;
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

	/// Renders shadow passes for all cascades.
	/// Call this BEFORE beginning the main render pass (requires ICommandEncoder, not IRenderPassEncoder).
	/// Returns true if shadows were rendered and a texture barrier is needed.
	public bool RenderShadows(ICommandEncoder encoder, int32 frameIndex)
	{
		if (!mRenderingInitialized || !mShadowsEnabled || mLightingSystem == null)
			return false;

		if (mShadowRenderer == null || mStaticMeshRenderer == null || mSkinnedMeshRenderer == null)
			return false;

		return mShadowRenderer.RenderShadows(encoder, frameIndex, mStaticMeshRenderer, mSkinnedMeshRenderer);
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

		// Render skybox first (behind all geometry)
		if (mSkyboxEnabled && mSkyboxRenderer != null && mSkyboxRenderer.IsInitialized)
			mSkyboxRenderer.Render(renderPass, mCurrentFrameIndex);

		// Render static meshes using material renderer
		if (mStaticMeshRenderer != null)
		{
			mStaticMeshRenderer.RenderMaterials(renderPass, frame.BindGroup, mCurrentFrameIndex);
		}

		// Render particles
		if (mParticleRenderer != null && mParticleRenderer.IsInitialized)
			mParticleRenderer.RenderEmitters(renderPass, mCurrentFrameIndex, mParticleEmitters);

		// Render sprites
		if (mSpriteRenderer != null && mSpriteRenderer.IsInitialized)
			mSpriteRenderer.Render(renderPass, mCurrentFrameIndex);

		// Render skinned meshes
		if (mSkinnedMeshRenderer != null)
			mSkinnedMeshRenderer.Render(renderPass, frame.CameraBuffer, frame.BindGroup, mCurrentFrameIndex);

		// End frame on render world
		mRenderWorld.EndFrame();
	}

	/// Ends the current frame.
	/// Call this after rendering is complete (called automatically by Render).
	public void EndFrame()
	{
		mRenderWorld.EndFrame();
	}

	// ==================== Proxy Management ====================

	/// Creates a mesh proxy for an entity.
	///
	/// Note: Static meshes use the proxy system (RenderWorld + VisibilityResolver) which
	/// efficiently handles frustum culling, LOD selection, and batching by (mesh, material).
	/// The StaticMeshRenderer receives visible meshes each frame via BuildBatches().
	/// See RegisterSkinnedMesh() for why skinned meshes use a different pattern.
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
	///
	/// Note: Skinned meshes use direct component registration (via SkinnedMeshRenderer)
	/// rather than the proxy system used by static meshes. This is because:
	/// - Static meshes are instanced and batched by (mesh, material) - the proxy system
	///   with VisibilityResolver efficiently handles culling and batch building
	/// - Skinned meshes are rendered individually with unique bone transforms and
	///   per-component GPU resources (bone buffers, object uniform buffers)
	public void RegisterSkinnedMesh(SkinnedMeshComponent skinnedMesh)
	{
		if (mSkinnedMeshRenderer != null)
			mSkinnedMeshRenderer.Register(skinnedMesh);
	}

	/// Unregisters a skinned mesh component.
	public void UnregisterSkinnedMesh(SkinnedMeshComponent skinnedMesh)
	{
		if (mSkinnedMeshRenderer != null)
			mSkinnedMeshRenderer.Unregister(skinnedMesh);
	}

	/// Gets the list of registered skinned meshes.
	public List<SkinnedMeshComponent> SkinnedMeshes => mSkinnedMeshRenderer?.SkinnedMeshes;

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

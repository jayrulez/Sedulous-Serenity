namespace Sedulous.Engine.Renderer;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;
using Sedulous.Renderer;

/// Scene component that manages rendering for a scene.
/// Owns the RenderWorld (proxy pool) and coordinates entity-to-proxy synchronization.
/// Delegates actual rendering to RenderSystem.
class RenderSceneComponent : ISceneComponent
{
	private const int32 MAX_FRAMES_IN_FLIGHT = 2;

	private RendererService mRendererService;
	private Scene mScene;
	private RenderWorld mRenderWorld ~ delete _;
	private RenderSystem mRenderSystem ~ delete _;

	// Entity → Proxy mapping for each proxy type
	private Dictionary<EntityId, ProxyHandle> mMeshProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mLightProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mCameraProxies = new .() ~ delete _;

	// Cached lists for iteration
	private List<StaticMeshProxy*> mVisibleMeshes = new .() ~ delete _;
	private List<LightProxy*> mActiveLights = new .() ~ delete _;
	private List<SkinnedMeshProxy*> mVisibleSkinnedMeshes = new .() ~ delete _;

	// Particle emitters and sprites (component lists for updates)
	private List<ParticleEmitterComponent> mParticleEmitters = new .() ~ delete _;
	private List<SpriteComponent> mSprites = new .() ~ delete _;

	// Main camera handle
	private ProxyHandle mMainCamera = .Invalid;

	// Rendering state
	private bool mRenderingInitialized = false;
	private int32 mCurrentFrameIndex = 0;
	private bool mFlipProjection = false;
	private RenderView mMainView;

	// ==================== Properties ====================

	/// Gets the renderer service.
	public RendererService RendererService => mRendererService;

	/// Gets the render world for proxy management.
	public RenderWorld RenderWorld => mRenderWorld;

	/// Gets the render system.
	public RenderSystem RenderSystem => mRenderSystem;

	/// Gets the visibility resolver.
	public VisibilityResolver VisibilityResolver => mRenderSystem?.Visibility;

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
	public List<StaticMeshProxy*> VisibleMeshes => mVisibleMeshes;

	/// Gets the list of active lights.
	public List<LightProxy*> ActiveLights => mActiveLights;

	/// Gets the main camera proxy.
	public CameraProxy* GetMainCameraProxy() => mRenderWorld.MainCamera;

	/// Gets mesh count for statistics.
	public uint32 MeshCount => mRenderWorld.StaticMeshCount;

	/// Gets light count for statistics.
	public uint32 LightCount => mRenderWorld.LightCount;

	/// Gets camera count for statistics.
	public uint32 CameraCount => mRenderWorld.CameraCount;

	/// Gets visible instance count for statistics (static + skinned meshes).
	public int32 VisibleInstanceCount => (mRenderSystem?.StaticMeshRenderer?.VisibleMeshCount ?? 0) + (mRenderSystem?.SkinnedMeshRenderer?.VisibleMeshCount ?? 0);

	/// Gets the lighting system (for shadow rendering).
	public LightingSystem LightingSystem => mRenderSystem?.LightingSystem;

	/// Gets or sets whether shadows are enabled.
	public bool ShadowsEnabled
	{
		get => mRenderSystem?.ShadowsEnabled ?? false;
		set { if (mRenderSystem != null) mRenderSystem.ShadowsEnabled = value; }
	}

	/// Gets whether the lighting system has directional shadows this frame.
	public bool HasDirectionalShadows => mRenderSystem?.LightingSystem?.HasDirectionalShadows ?? false;

	/// Gets the skybox renderer.
	public SkyboxRenderer SkyboxRenderer => mRenderSystem?.SkyboxRenderer;

	/// Gets or sets whether skybox rendering is enabled.
	public bool SkyboxEnabled
	{
		get => mRenderSystem?.SkyboxEnabled ?? false;
		set { if (mRenderSystem != null) mRenderSystem.SkyboxEnabled = value; }
	}

	// ==================== Constructor ====================

	/// Creates a new RenderSceneComponent.
	/// The RendererService must be initialized before passing here.
	public this(RendererService rendererService)
	{
		mRendererService = rendererService;
		mRenderWorld = new RenderWorld();
		mRenderSystem = new RenderSystem();
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
		if (mScene == null || mRenderSystem == null)
			return;

		// Sync entity transforms to proxies
		SyncProxies();

		// Prepare render world for this frame
		mRenderWorld.BeginFrame();

		// Create RenderView from main camera (frame index will be set in PrepareGPU)
		if (let camera = mRenderWorld.MainCamera)
		{
			mMainView = RenderView.FromCameraProxy(0, camera, null, null, true);
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

		if (mRendererService?.Device == null || mRenderSystem == null)
			return .Err;

		mFlipProjection = flipProjection;

		let device = mRendererService.Device;

		// Create lighting system (RenderSystem needs it during initialization)
		let lightingSystem = new LightingSystem(device);

		// Initialize RenderSystem with all dependencies
		if (mRenderSystem.Initialize(
			device,
			mRendererService.ShaderLibrary,
			mRendererService.MaterialSystem,
			mRendererService.ResourceManager,
			mRendererService.PipelineCache,
			lightingSystem,
			colorFormat,
			depthFormat) case .Err)
		{
			delete lightingSystem;
			return .Err;
		}

		mRenderingInitialized = true;
		return .Ok;
	}

	private void CleanupRendering()
	{
		mRenderingInitialized = false;
	}

	// ==================== Frame Rendering ====================

	/// Uploads per-frame GPU data.
	/// Call this in OnPrepareFrame after the fence wait.
	public void PrepareGPU(int32 frameIndex)
	{
		if (!mRenderingInitialized || mRenderSystem == null)
			return;

		mCurrentFrameIndex = frameIndex;

		// Begin frame with correct frame index and perform visibility
		mRenderSystem.BeginFrame(frameIndex, mMainView);
		mRenderSystem.PrepareVisibility(mRenderWorld);

		// Get visible meshes for local reference
		mVisibleMeshes.Clear();
		if (mRenderSystem.OpaqueMeshes != null)
			mVisibleMeshes.AddRange(mRenderSystem.OpaqueMeshes);
		if (mRenderSystem.TransparentMeshes != null)
			mVisibleMeshes.AddRange(mRenderSystem.TransparentMeshes);

		// Delegate to RenderSystem for GPU preparation
		mRenderSystem.PrepareGPU(mRenderWorld, mFlipProjection);

		// Upload component-specific data (particles, sprites)
		for (let emitter in mParticleEmitters)
		{
			if (emitter.Visible && emitter.ParticleSystem != null)
				emitter.ParticleSystem.Upload();
		}

		// Build and upload sprite data
		if (mRenderSystem.SpriteRenderer != null && mSprites.Count > 0)
		{
			mRenderSystem.SpriteRenderer.Begin();
			for (let sprite in mSprites)
			{
				if (sprite.Visible)
					mRenderSystem.SpriteRenderer.AddSprite(sprite.GetSpriteInstance());
			}
			mRenderSystem.SpriteRenderer.End();
		}
	}

	/// Renders shadow passes for all cascades.
	/// Call this BEFORE beginning the main render pass (requires ICommandEncoder, not IRenderPassEncoder).
	/// Returns true if shadows were rendered and a texture barrier is needed.
	public bool RenderShadows(ICommandEncoder encoder, int32 frameIndex)
	{
		if (!mRenderingInitialized || mRenderSystem == null)
			return false;

		return mRenderSystem.RenderShadows(encoder, mRenderWorld);
	}

	/// Renders the scene to the given render pass.
	/// Call this in OnRender.
	public void Render(IRenderPassEncoder renderPass, uint32 viewportWidth, uint32 viewportHeight)
	{
		if (!mRenderingInitialized || mRenderSystem == null)
			return;

		// Delegate to RenderSystem for rendering
		mRenderSystem.Render(renderPass, mRenderWorld);
		mRenderSystem.EndFrame(mRenderWorld);
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
			mRenderWorld.DestroyStaticMeshProxy(existing);
			mMeshProxies.Remove(entityId);
		}

		let handle = mRenderWorld.CreateStaticMeshProxy(mesh, transform, bounds);
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
			mRenderWorld.DestroyStaticMeshProxy(handle);
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
		if (mRenderSystem?.SkinnedMeshRenderer != null && mRenderWorld != null)
		{
			// Get the proxy from the component and register with renderer
			if (let proxy = mRenderWorld.GetSkinnedMeshProxy(skinnedMesh.ProxyHandle))
				mRenderSystem.SkinnedMeshRenderer.Register(proxy);
		}
	}

	/// Unregisters a skinned mesh component.
	public void UnregisterSkinnedMesh(SkinnedMeshComponent skinnedMesh)
	{
		if (mRenderSystem?.SkinnedMeshRenderer != null && mRenderWorld != null)
		{
			if (let proxy = mRenderWorld.GetSkinnedMeshProxy(skinnedMesh.ProxyHandle))
				mRenderSystem.SkinnedMeshRenderer.Unregister(proxy);
		}
	}

	/// Gets the list of registered skinned mesh proxies.
	public List<SkinnedMeshProxy*> SkinnedMeshProxies => mRenderSystem?.SkinnedMeshRenderer?.SkinnedMeshes;

	/// Gets the sprite renderer.
	public SpriteRenderer SpriteRenderer => mRenderSystem?.SpriteRenderer;

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
				if (let proxy = mRenderWorld.GetStaticMeshProxy(meshHandle))
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

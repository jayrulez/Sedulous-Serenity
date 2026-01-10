namespace Sedulous.Engine.Renderer;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;
using Sedulous.Renderer;

/// Scene component that manages rendering for a scene.
/// Owns the RenderContext (which contains RenderWorld + LightingSystem).
/// Coordinates entity-to-proxy synchronization.
/// Delegates actual rendering to the shared RenderPipeline.
class RenderSceneComponent : ISceneComponent
{
	private RendererService mRendererService;
	private Scene mScene;
	private RenderContext mContext ~ delete _;

	// Entity → Proxy mapping for each proxy type
	private Dictionary<EntityId, ProxyHandle> mMeshProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mSkinnedMeshProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mLightProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mCameraProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mSpriteProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mParticleEmitterProxies = new .() ~ delete _;

	// Particle emitter component list (for per-frame updates like Upload)
	private List<ParticleEmitterComponent> mParticleEmitters = new .() ~ delete _;

	// Main camera handle
	private ProxyHandle mMainCamera = .Invalid;

	// Rendering state
	private bool mRenderingInitialized = false;
	private ITextureView* mColorTarget;
	private ITextureView* mDepthTarget;

	// ==================== Properties ====================

	/// Gets the renderer service.
	public RendererService RendererService => mRendererService;

	/// Gets the render context for this scene.
	public RenderContext Context => mContext;

	/// Gets the render world for proxy management.
	public RenderWorld RenderWorld => mContext?.World;

	/// Gets the render pipeline (shared across all scenes).
	public RenderPipeline Pipeline => mRendererService?.Pipeline;

	/// Gets the visibility resolver.
	public VisibilityResolver VisibilityResolver => mContext?.Visibility;

	/// Gets or sets the main camera proxy handle.
	public ProxyHandle MainCamera
	{
		get => mMainCamera;
		set
		{
			mMainCamera = value;
			if (mContext?.World != null)
				mContext.World.SetMainCamera(value);
		}
	}

	/// Gets the scene this component is attached to.
	public Scene Scene => mScene;

	/// Gets the list of visible meshes after culling.
	public List<StaticMeshProxy*> VisibleMeshes => mContext?.VisibleMeshes;

	/// Gets the list of active lights.
	public List<LightProxy*> ActiveLights => mContext?.ActiveLights;

	/// Gets the main camera proxy.
	public CameraProxy* GetMainCameraProxy() => mContext?.World?.MainCamera;

	/// Gets mesh count for statistics.
	public uint32 MeshCount => mContext?.World?.StaticMeshCount ?? 0;

	/// Gets light count for statistics.
	public uint32 LightCount => mContext?.World?.LightCount ?? 0;

	/// Gets camera count for statistics.
	public uint32 CameraCount => mContext?.World?.CameraCount ?? 0;

	/// Gets visible instance count for statistics.
	public int32 VisibleInstanceCount =>
		(Pipeline?.StaticMeshRenderer?.VisibleMeshCount ?? 0) +
		(Pipeline?.SkinnedMeshRenderer?.VisibleMeshCount ?? 0);

	/// Gets the lighting system.
	public LightingSystem LightingSystem => mContext?.Lighting;

	/// Gets whether the lighting system has directional shadows this frame.
	public bool HasDirectionalShadows => mContext?.Lighting?.HasDirectionalShadows ?? false;

	/// Gets the skybox renderer.
	public SkyboxRenderer SkyboxRenderer => Pipeline?.SkyboxRenderer;

	/// Gets the sprite renderer.
	public SpriteRenderer SpriteRenderer => Pipeline?.SpriteRenderer;

	/// Gets the list of registered skinned mesh proxies.
	public List<SkinnedMeshProxy*> SkinnedMeshProxies => Pipeline?.SkinnedMeshRenderer?.SkinnedMeshes;

	/// Gets the list of registered particle emitters.
	public List<ParticleEmitterComponent> ParticleEmitters => mParticleEmitters;

	/// Gets sprite count for statistics.
	public uint32 SpriteCount => mContext?.World?.SpriteCount ?? 0;

	// ==================== Constructor ====================

	/// Creates a new RenderSceneComponent.
	/// The RendererService must be initialized before passing here.
	public this(RendererService rendererService)
	{
		mRendererService = rendererService;
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
		mContext?.World?.Clear();
		mMeshProxies.Clear();
		mSkinnedMeshProxies.Clear();
		mLightProxies.Clear();
		mCameraProxies.Clear();
		mSpriteProxies.Clear();
		mParticleEmitterProxies.Clear();
		mScene = null;
	}

	/// Called each frame to update the component.
	/// Syncs entity transforms to proxies.
	public void OnUpdate(float deltaTime)
	{
		if (mScene == null || mContext == null)
			return;

		// Sync entity transforms to proxies
		SyncProxies();
	}

	/// Called when the scene state changes.
	public void OnSceneStateChanged(SceneState oldState, SceneState newState)
	{
		if (newState == .Unloaded)
		{
			CleanupRendering();
			mContext?.World?.Clear();
			mMeshProxies.Clear();
			mSkinnedMeshProxies.Clear();
			mLightProxies.Clear();
			mCameraProxies.Clear();
			mSpriteProxies.Clear();
			mParticleEmitterProxies.Clear();
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
	public Result<void> InitializeRendering(TextureFormat colorFormat, TextureFormat depthFormat)
	{
		if (mRenderingInitialized)
			return .Ok;

		if (mRendererService?.Device == null || mRendererService.Pipeline == null)
			return .Err;

		let device = mRendererService.Device;
		let pipeline = mRendererService.Pipeline;

		// Create render context (owns RenderWorld + LightingSystem + VisibilityResolver)
		if (RenderContext.Create(device) case .Ok(let context))
			mContext = context;
		else
			return .Err;

		// Initialize pipeline's sub-renderers with this context's lighting system
		// (only needed once per pipeline - check if StaticMeshRenderer exists)
		if (pipeline.StaticMeshRenderer == null)
		{
			if (pipeline.InitializeRenderers(mContext.Lighting) case .Err)
				return .Err;
		}

		mRenderingInitialized = true;
		return .Ok;
	}

	/// Sets the render targets for this scene.
	/// Call this when swap chain is resized or targets change.
	public void SetRenderTargets(ITextureView* colorTarget, ITextureView* depthTarget)
	{
		mColorTarget = colorTarget;
		mDepthTarget = depthTarget;
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
		if (!mRenderingInitialized || mContext == null)
			return;

		let pipeline = mRendererService.Pipeline;
		if (pipeline == null)
			return;

		// Begin frame with context
		mContext.BeginFrame(frameIndex);

		// Add main camera view
		if (let camera = mContext.World.MainCamera)
		{
			let mainView = RenderView.FromCameraProxy(0, camera, mColorTarget, mDepthTarget, true);
			mContext.AddView(mainView);
			mContext.SetMainView(0);
		}

		// Add shadow cascade views
		mContext.AddShadowCascadeViews();

		// Prepare visibility and GPU resources
		pipeline.PrepareVisibility(mContext);
		pipeline.PrepareGPU(mContext);

		// Upload component-specific data (particles)
		for (let emitter in mParticleEmitters)
		{
			if (emitter.Visible && emitter.ParticleSystem != null)
				emitter.ParticleSystem.Upload();
		}

		// Build and upload sprite data from proxies
		if (pipeline.SpriteRenderer != null && mContext.World.SpriteCount > 0)
		{
			pipeline.SpriteRenderer.Begin();
			// Collect sprites from proxies
			List<SpriteProxy*> sprites = scope .();
			mContext.World.GetValidSpriteProxies(sprites);
			for (let spriteProxy in sprites)
			{
				pipeline.SpriteRenderer.AddSprite(spriteProxy.ToSpriteInstance());
			}
			pipeline.SpriteRenderer.End();
		}
	}

	/// Renders shadow passes for all cascades.
	/// Call this BEFORE beginning the main render pass.
	/// Returns true if shadows were rendered and a texture barrier is needed.
	public bool RenderShadows(ICommandEncoder encoder, int32 frameIndex)
	{
		if (!mRenderingInitialized || mContext == null)
			return false;

		return mRendererService.Pipeline?.RenderShadows(mContext, encoder) ?? false;
	}

	/// Renders the scene to the given render pass.
	/// Call this in OnRender.
	public void Render(IRenderPassEncoder renderPass, uint32 viewportWidth, uint32 viewportHeight)
	{
		if (!mRenderingInitialized || mContext == null)
			return;

		// Render all views
		mRendererService.Pipeline?.RenderViews(mContext, renderPass);

		// End frame
		mContext.EndFrame();
	}

	/// Ends the current frame.
	/// Note: Called automatically by Render, only call explicitly if skipping Render.
	public void EndFrame()
	{
		mContext?.EndFrame();
	}

	// ==================== Proxy Management ====================

	/// Creates a mesh proxy for an entity.
	public ProxyHandle CreateStaticMeshProxy(EntityId entityId, GPUMeshHandle mesh, Matrix transform, BoundingBox bounds)
	{
		if (mContext?.World == null)
			return .Invalid;

		// Remove existing proxy if any
		if (mMeshProxies.TryGetValue(entityId, let existing))
		{
			mContext.World.DestroyStaticMeshProxy(existing);
			mMeshProxies.Remove(entityId);
		}

		let handle = mContext.World.CreateStaticMeshProxy(mesh, transform, bounds);
		if (handle.IsValid)
			mMeshProxies[entityId] = handle;

		return handle;
	}

	/// Creates a directional light proxy for an entity.
	public ProxyHandle CreateDirectionalLight(EntityId entityId, Vector3 direction, Vector3 color, float intensity)
	{
		if (mContext?.World == null)
			return .Invalid;

		DestroyLightProxy(entityId);
		let handle = mContext.World.CreateDirectionalLight(direction, color, intensity);
		if (handle.IsValid)
			mLightProxies[entityId] = handle;
		return handle;
	}

	/// Creates a point light proxy for an entity.
	public ProxyHandle CreatePointLight(EntityId entityId, Vector3 position, Vector3 color, float intensity, float range)
	{
		if (mContext?.World == null)
			return .Invalid;

		DestroyLightProxy(entityId);
		let handle = mContext.World.CreatePointLight(position, color, intensity, range);
		if (handle.IsValid)
			mLightProxies[entityId] = handle;
		return handle;
	}

	/// Creates a spot light proxy for an entity.
	public ProxyHandle CreateSpotLight(EntityId entityId, Vector3 position, Vector3 direction, Vector3 color,
		float intensity, float range, float innerAngle, float outerAngle)
	{
		if (mContext?.World == null)
			return .Invalid;

		DestroyLightProxy(entityId);
		let handle = mContext.World.CreateSpotLight(position, direction, color, intensity, range, innerAngle, outerAngle);
		if (handle.IsValid)
			mLightProxies[entityId] = handle;
		return handle;
	}

	/// Creates a camera proxy for an entity.
	public ProxyHandle CreateCameraProxy(EntityId entityId, Camera camera, uint32 viewportWidth, uint32 viewportHeight, bool isMain = false)
	{
		if (mContext?.World == null)
			return .Invalid;

		DestroyCameraProxy(entityId);
		let handle = mContext.World.CreateCamera(camera, viewportWidth, viewportHeight, isMain);
		if (handle.IsValid)
		{
			mCameraProxies[entityId] = handle;
			if (isMain)
				mMainCamera = handle;
		}
		return handle;
	}

	/// Destroys a mesh proxy for an entity.
	public void DestroyStaticMeshProxy(EntityId entityId)
	{
		if (mMeshProxies.TryGetValue(entityId, let handle))
		{
			mContext?.World?.DestroyStaticMeshProxy(handle);
			mMeshProxies.Remove(entityId);
		}
	}

	/// Destroys a light proxy for an entity.
	public void DestroyLightProxy(EntityId entityId)
	{
		if (mLightProxies.TryGetValue(entityId, let handle))
		{
			mContext?.World?.DestroyLightProxy(handle);
			mLightProxies.Remove(entityId);
		}
	}

	/// Destroys a camera proxy for an entity.
	public void DestroyCameraProxy(EntityId entityId)
	{
		if (mCameraProxies.TryGetValue(entityId, let handle))
		{
			if (mMainCamera.Equals(handle))
				mMainCamera = .Invalid;
			mContext?.World?.DestroyCameraProxy(handle);
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

	/// Creates a sprite proxy for an entity.
	public ProxyHandle CreateSpriteProxy(EntityId entityId, Vector3 position, Vector2 size, Color color = .White)
	{
		if (mContext?.World == null)
			return .Invalid;

		DestroySpriteProxy(entityId);
		let handle = mContext.World.CreateSpriteProxy(position, size, color);
		if (handle.IsValid)
			mSpriteProxies[entityId] = handle;
		return handle;
	}

	/// Creates a sprite proxy with UV rect.
	public ProxyHandle CreateSpriteProxy(EntityId entityId, Vector3 position, Vector2 size, Vector4 uvRect, Color color)
	{
		if (mContext?.World == null)
			return .Invalid;

		DestroySpriteProxy(entityId);
		let handle = mContext.World.CreateSpriteProxy(position, size, uvRect, color);
		if (handle.IsValid)
			mSpriteProxies[entityId] = handle;
		return handle;
	}

	/// Destroys a sprite proxy for an entity.
	public void DestroySpriteProxy(EntityId entityId)
	{
		if (mSpriteProxies.TryGetValue(entityId, let handle))
		{
			mContext?.World?.DestroySpriteProxy(handle);
			mSpriteProxies.Remove(entityId);
		}
	}

	/// Gets the sprite proxy handle for an entity.
	public ProxyHandle GetSpriteProxy(EntityId entityId)
	{
		if (mSpriteProxies.TryGetValue(entityId, let handle))
			return handle;
		return .Invalid;
	}

	/// Creates a particle emitter proxy for an entity.
	public ProxyHandle CreateParticleEmitterProxy(EntityId entityId, ParticleSystem system, Vector3 position)
	{
		if (mContext?.World == null)
			return .Invalid;

		// Remove existing proxy if any
		DestroyParticleEmitterProxy(entityId);

		let handle = mContext.World.CreateParticleEmitterProxy(system, position);
		if (handle.IsValid)
			mParticleEmitterProxies[entityId] = handle;

		return handle;
	}

	/// Destroys a particle emitter proxy for an entity.
	public void DestroyParticleEmitterProxy(EntityId entityId)
	{
		if (mParticleEmitterProxies.TryGetValue(entityId, let handle))
		{
			mContext?.World?.DestroyParticleEmitterProxy(handle);
			mParticleEmitterProxies.Remove(entityId);
		}
	}

	/// Gets the particle emitter proxy handle for an entity.
	public ProxyHandle GetParticleEmitterProxy(EntityId entityId)
	{
		if (mParticleEmitterProxies.TryGetValue(entityId, let handle))
			return handle;
		return .Invalid;
	}

	/// Creates a skinned mesh proxy for an entity.
	public ProxyHandle CreateSkinnedMeshProxy(EntityId entityId, GPUSkinnedMeshHandle mesh, Matrix transform, BoundingBox bounds)
	{
		if (mContext?.World == null)
			return .Invalid;

		// Remove existing proxy if any
		if (mSkinnedMeshProxies.TryGetValue(entityId, let existing))
		{
			// Unregister from renderer
			if (Pipeline?.SkinnedMeshRenderer != null)
			{
				if (let proxy = mContext.World.GetSkinnedMeshProxy(existing))
					Pipeline.SkinnedMeshRenderer.Unregister(proxy);
			}
			mContext.World.DestroySkinnedMeshProxy(existing);
			mSkinnedMeshProxies.Remove(entityId);
		}

		let handle = mContext.World.CreateSkinnedMeshProxy(mesh, transform, bounds);
		if (handle.IsValid)
		{
			mSkinnedMeshProxies[entityId] = handle;

			// Register with renderer
			if (Pipeline?.SkinnedMeshRenderer != null)
			{
				if (let proxy = mContext.World.GetSkinnedMeshProxy(handle))
					Pipeline.SkinnedMeshRenderer.Register(proxy);
			}
		}

		return handle;
	}

	/// Destroys a skinned mesh proxy for an entity.
	public void DestroySkinnedMeshProxy(EntityId entityId)
	{
		if (mSkinnedMeshProxies.TryGetValue(entityId, let handle))
		{
			// Unregister from renderer
			if (Pipeline?.SkinnedMeshRenderer != null && mContext?.World != null)
			{
				if (let proxy = mContext.World.GetSkinnedMeshProxy(handle))
					Pipeline.SkinnedMeshRenderer.Unregister(proxy);
			}
			mContext?.World?.DestroySkinnedMeshProxy(handle);
			mSkinnedMeshProxies.Remove(entityId);
		}
	}

	/// Gets the skinned mesh proxy handle for an entity.
	public ProxyHandle GetSkinnedMeshProxyHandle(EntityId entityId)
	{
		if (mSkinnedMeshProxies.TryGetValue(entityId, let handle))
			return handle;
		return .Invalid;
	}

	// ==================== Frame Sync ====================

	/// Synchronizes all entity transforms to their proxies.
	/// Called each frame during OnUpdate.
	private void SyncProxies()
	{
		if (mScene == null || mContext?.World == null)
			return;

		let world = mContext.World;

		// Iterate all entities and sync transforms
		for (let entity in mScene.EntityManager)
		{
			let worldMatrix = entity.Transform.WorldMatrix;
			let entityId = entity.Id;

			// Sync mesh proxies
			if (mMeshProxies.TryGetValue(entityId, let meshHandle))
			{
				if (let proxy = world.GetStaticMeshProxy(meshHandle))
				{
					proxy.Transform = worldMatrix;
					proxy.UpdateWorldBounds();
					proxy.Flags |= .Dirty;
				}
			}

			// Sync light proxies
			if (mLightProxies.TryGetValue(entityId, let lightHandle))
			{
				if (let proxy = world.GetLightProxy(lightHandle))
				{
					proxy.Position = entity.Transform.WorldPosition;
					if (proxy.Type == .Directional || proxy.Type == .Spot)
						proxy.Direction = entity.Transform.Forward;
				}
			}

			// Sync camera proxies
			if (mCameraProxies.TryGetValue(entityId, let cameraHandle))
			{
				if (let proxy = world.GetCameraProxy(cameraHandle))
				{
					proxy.Position = entity.Transform.WorldPosition;
					proxy.Forward = entity.Transform.Forward;
					proxy.Up = entity.Transform.Up;
					proxy.Right = entity.Transform.Right;
					proxy.UpdateMatrices();
				}
			}

			// Sync sprite proxies
			if (mSpriteProxies.TryGetValue(entityId, let spriteHandle))
			{
				if (let proxy = world.GetSpriteProxy(spriteHandle))
				{
					proxy.SetPosition(entity.Transform.WorldPosition);
				}
			}
		}
	}
}

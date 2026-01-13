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

	// Trail component list (for rendering)
	private List<TrailComponent> mTrailComponents = new .() ~ delete _;

	// Main camera handle
	private ProxyHandle mMainCamera = .Invalid;

	// Rendering state
	private bool mRenderingInitialized = false;
	private ITextureView* mColorTarget;
	private ITextureView* mDepthTarget;

	// Soft particles - readable depth texture view (for depth sampling)
	private ITextureView mReadableDepthTexture = null;

	// Soft particles - enable split passes for proper depth reading
	private bool mEnableSoftParticles = false;

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

	/// Gets or sets the readable depth texture view for soft particles.
	/// This should be a sampled view of the depth texture.
	/// When EnableSoftParticles is true, rendering is split into opaque and transparent passes
	/// to allow depth sampling in the transparent pass.
	public ITextureView ReadableDepthTexture
	{
		get => mReadableDepthTexture;
		set => mReadableDepthTexture = value;
	}

	/// Gets or sets whether soft particles are enabled.
	/// When enabled, rendering is split into separate opaque and transparent passes
	/// to allow particles to sample the depth buffer for soft fading near surfaces.
	public bool EnableSoftParticles
	{
		get => mEnableSoftParticles;
		set => mEnableSoftParticles = value;
	}

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
	/// Called automatically by RendererService when scene is created.
	public Result<void> InitializeRendering()
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

	// ==================== Render Graph Integration ====================

	/// Adds render passes to the render graph for this scene.
	/// Called by RendererService.BeginFrame().
	public void AddRenderPasses(RenderGraph graph, ResourceHandle swapChain, ResourceHandle depth)
	{
		if (!mRenderingInitialized || mContext == null)
			return;

		let pipeline = mRendererService.Pipeline;
		if (pipeline == null)
			return;

		let frameIndex = (int32)mRendererService.FrameIndex;

		// PrepareGPU - upload uniforms, visibility
		PrepareGPU(frameIndex);

		// Add shadow passes and get shadow map handle for Scene3D to read
		ResourceHandle shadowMapHandle = default;
		let shadowCascadeCount = AddShadowPasses(graph, out shadowMapHandle);

		let clearColor = Color(0.08f, 0.1f, 0.12f, 1.0f);

		// When soft particles are enabled, we split into two passes:
		// 1. Opaque pass: renders skybox, static meshes, skinned meshes (depth write)
		// 2. Transparent pass: renders particles with depth sampling (depth test only)
		if (mEnableSoftParticles && mReadableDepthTexture != null)
		{
			AddSplitPasses(graph, swapChain, depth, shadowMapHandle, shadowCascadeCount, clearColor);
		}
		else
		{
			// Single pass: everything in one go (no soft particles)
			AddSinglePass(graph, swapChain, depth, shadowMapHandle, shadowCascadeCount, clearColor);
		}

		// Note: UISceneComponent adds its own pass via RendererService
	}

	/// Adds a single combined pass for rendering (no soft particles).
	private void AddSinglePass(RenderGraph graph, ResourceHandle swapChain, ResourceHandle depth,
		ResourceHandle shadowMapHandle, int32 shadowCascadeCount, Color clearColor)
	{
		let context = mContext;
		let pipelineRef = mRendererService.Pipeline;
		let trailComponents = mTrailComponents;

		var passBuilder = graph.AddGraphicsPass("Scene3D")
			.SetColorAttachment(0, swapChain, .Clear, .Store, clearColor)
			.SetDepthAttachment(depth, .Clear, .Store, 1.0f);

		// Add shadow cascade dependencies
		for (int32 i = 0; i < shadowCascadeCount; i++)
			passBuilder.AddDependency(scope $"ShadowCascade{i}");

		// Add world UI dependencies
		for (int32 i = 0; i < 16; i++)
			passBuilder.AddDependency(scope $"WorldUI_{i}");

		if (shadowMapHandle.IsValid)
			passBuilder.Read(shadowMapHandle, .ShaderReadOnly);

		passBuilder.SetExecute(new [=](ctx) => {
				// Render everything in one pass (no depth sampling for particles)
				pipelineRef.RenderViews(context, ctx.RenderPass, true, true, true, null);

				// Render trail components
				RenderTrailComponents(ctx.RenderPass, pipelineRef, context, trailComponents);

				context.EndFrame();
			});
	}

	/// Adds split passes for soft particles (opaque + transparent).
	private void AddSplitPasses(RenderGraph graph, ResourceHandle swapChain, ResourceHandle depth,
		ResourceHandle shadowMapHandle, int32 shadowCascadeCount, Color clearColor)
	{
		let context = mContext;
		let pipelineRef = mRendererService.Pipeline;
		let trailComponents = mTrailComponents;
		let readableDepth = mReadableDepthTexture;

		// === Pass 1: Scene3D_Opaque ===
		// Renders skybox, static meshes, skinned meshes
		// Clears and writes to depth buffer
		var opaquePass = graph.AddGraphicsPass("Scene3D_Opaque")
			.SetColorAttachment(0, swapChain, .Clear, .Store, clearColor)
			.SetDepthAttachment(depth, .Clear, .Store, 1.0f);

		for (int32 i = 0; i < shadowCascadeCount; i++)
			opaquePass.AddDependency(scope $"ShadowCascade{i}");

		for (int32 i = 0; i < 16; i++)
			opaquePass.AddDependency(scope $"WorldUI_{i}");

		if (shadowMapHandle.IsValid)
			opaquePass.Read(shadowMapHandle, .ShaderReadOnly);

		opaquePass.SetExecute(new [=](ctx) => {
				// Render skybox, static meshes, skinned meshes only (no particles/sprites)
				pipelineRef.RenderViews(context, ctx.RenderPass,
					true,   // renderSkybox
					false,  // renderParticles - disabled for opaque pass
					false,  // renderSprites - disabled for opaque pass
					null    // no depth texture needed
				);
			});

		// === Pass 2: Scene3D_Transparent ===
		// Renders particles and sprites with depth sampling for soft particles
		// No depth attachment - particles don't need depth testing when using soft fade
		// The depth texture is only sampled (not used as attachment) for soft particle fade
		var transparentPass = graph.AddGraphicsPass("Scene3D_Transparent")
			.SetColorAttachment(0, swapChain, .Load, .Store, clearColor)
			// No depth attachment - we sample depth texture for soft particles instead
			.AddDependency("Scene3D_Opaque")
			// Read depth texture with ShaderReadOnly layout for sampling in soft particles
			// This triggers a layout transition from DepthStencilAttachment (opaque pass) to ShaderReadOnly
			.Read(depth, .ShaderReadOnly);

		transparentPass.SetExecute(new [=](ctx) => {
				// Render particles and sprites only, with depth sampling
				pipelineRef.RenderViews(context, ctx.RenderPass,
					false,  // renderSkybox - already rendered
					true,   // renderParticles
					true,   // renderSprites
					readableDepth  // pass readable depth texture
				);

				// Render trail components (use no-depth pipelines for transparent pass)
				RenderTrailComponents(ctx.RenderPass, pipelineRef, context, trailComponents, true);

				context.EndFrame();
			});
	}

	/// Helper to render trail components.
	private void RenderTrailComponents(IRenderPassEncoder renderPass, RenderPipeline pipeline,
		RenderContext context, List<TrailComponent> trailComponents, bool useNoDepthPipelines = false)
	{
		if (trailComponents.Count == 0 || pipeline.TrailRenderer == null || !pipeline.TrailRenderer.IsInitialized)
			return;

		// Get camera position for billboard orientation
		Vector3 cameraPos = .Zero;
		if (let camera = context.World?.MainCamera)
			cameraPos = camera.Position;

		for (let trailComp in trailComponents)
		{
			if (trailComp.HasPoints)
			{
				let trail = trailComp.Trail;
				let settings = trailComp.GetTrailSettings();
				pipeline.TrailRenderer.RenderTrail(
					renderPass,
					context.FrameIndex,
					trail,
					cameraPos,
					settings,
					trailComp.BlendMode,
					trailComp.CurrentTime,
					useNoDepthPipelines
				);
			}
		}
	}

	/// Adds shadow cascade passes to the render graph.
	/// Returns the number of cascade passes added.
	/// Outputs the shadow map array handle for Scene3D to read from.
	private int32 AddShadowPasses(RenderGraph graph, out ResourceHandle shadowMapArrayHandle)
	{
		shadowMapArrayHandle = default;

		if (mContext?.Lighting == null)
			return 0;

		let lighting = mContext.Lighting;
		let pipeline = mRendererService.Pipeline;
		if (pipeline == null)
			return 0;

		let shadowRenderer = pipeline.ShadowRenderer;
		if (shadowRenderer == null || !shadowRenderer.HasShadows)
			return 0;

		let shadowMapTexture = lighting.CascadeShadowMapTexture;
		let shadowMapArrayView = lighting.CascadeShadowMapView;
		if (shadowMapTexture == null || shadowMapArrayView == null)
			return 0;

		let frameIndex = (int32)mRendererService.FrameIndex;

		// Clean up temporary bind groups for this frame
		shadowRenderer.BeginFrame(frameIndex);

		// Import the shadow map array view (used for sampling in Scene3D)
		shadowMapArrayHandle = graph.ImportTexture("ShadowMapArray", shadowMapTexture, shadowMapArrayView, .Undefined);

		int32 cascadesAdded = 0;

		// Add a pass for each shadow cascade
		for (int32 cascade = 0; cascade < shadowRenderer.CascadeCount; cascade++)
		{
			let cascadeView = lighting.GetCascadeRenderView(cascade);
			if (cascadeView == null)
				continue;

			// Prepare uniform data for this cascade
			shadowRenderer.PrepareCascade(frameIndex, cascade);

			// Import this cascade's slice view (for rendering to)
			String cascadeName = scope $"ShadowCascade{cascade}";
			let cascadeHandle = graph.ImportTexture(cascadeName, shadowMapTexture, cascadeView, .Undefined);

			// Capture values for lambda
			let shadowRendererRef = shadowRenderer;
			let pipelineRef = pipeline;
			let cascadeIdx = cascade;
			let frame = frameIndex;

			// Create pass for this cascade
			String passName = scope $"ShadowCascade{cascade}";
			graph.AddGraphicsPass(passName)
				.SetDepthAttachment(cascadeHandle, .Clear, .Store, 1.0f)
				.SetExecute(new [=](ctx) => {
					shadowRendererRef.RenderCascadeShadows(
						ctx.RenderPass, frame, cascadeIdx,
						pipelineRef.StaticMeshRenderer, pipelineRef.SkinnedMeshRenderer);
				});

			cascadesAdded++;
		}

		return cascadesAdded;
	}

	// ==================== Frame Rendering (Legacy) ====================

	/// Uploads per-frame GPU data.
	/// Call this in OnPrepareFrame after the fence wait.
	/// Note: When using RenderGraph, this is called automatically by AddRenderPasses.
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

		// Prepare soft particle bind groups BEFORE any command recording
		// This must happen during PrepareGPU, not during rendering
		if (mEnableSoftParticles && mReadableDepthTexture != null)
		{
			pipeline.PrepareSoftParticleBindGroups(frameIndex, mReadableDepthTexture);
		}

		// Build and upload sprite data from proxies (supports multiple textures via batching)
		if (pipeline.SpriteRenderer != null && mContext.World.SpriteCount > 0)
		{
			// Collect sprites from proxies
			List<SpriteProxy*> sprites = scope .();
			mContext.World.GetValidSpriteProxies(sprites);

			if (sprites.Count > 0)
			{
				pipeline.SpriteRenderer.Begin();

				// Add each sprite with its texture (batching is handled internally)
				for (let spriteProxy in sprites)
					pipeline.SpriteRenderer.AddSprite(spriteProxy.ToSpriteInstance(), spriteProxy.Texture);

				pipeline.SpriteRenderer.End();
			}
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

		// Render all views (with soft particle depth if available)
		mRendererService.Pipeline?.RenderViews(mContext, renderPass, true, true, true, mReadableDepthTexture);

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

	/// Registers a trail component for rendering.
	public void RegisterTrailComponent(TrailComponent trail)
	{
		if (!mTrailComponents.Contains(trail))
			mTrailComponents.Add(trail);
	}

	/// Unregisters a trail component.
	public void UnregisterTrailComponent(TrailComponent trail)
	{
		mTrailComponents.Remove(trail);
	}

	/// Gets the list of registered trail components.
	public List<TrailComponent> TrailComponents => mTrailComponents;

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

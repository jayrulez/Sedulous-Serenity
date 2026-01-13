namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RHI.HLSLShaderCompiler;

/// Stateless rendering orchestrator. Shared across all scenes.
/// Given a RenderContext, performs all rendering operations.
///
/// RenderPipeline owns:
/// - Sub-renderers (StaticMesh, SkinnedMesh, Shadow, Particle, Sprite, Skybox)
/// - Per-frame camera buffers (shared across all contexts)
/// - Scene bind group layout (contexts create instances using this layout)
///
/// RenderPipeline does NOT own:
/// - LightingSystem (owned by RenderContext)
/// - VisibilityResolver (owned by RenderContext)
/// - RenderWorld (owned by RenderContext)
/// - Frame state (managed by RenderContext)
class RenderPipeline
{
	private const int32 MAX_FRAMES = 2;
	private const int32 MAX_VIEWS = 4;  // Maximum simultaneous camera views per frame

	// ==================== Borrowed Services ====================

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;
	private MaterialSystem mMaterialSystem;
	private GPUResourceManager mResourceManager;
	private PipelineCache mPipelineCache;

	// ==================== Sub-Renderers ====================

	private StaticMeshRenderer mStaticMeshRenderer ~ delete _;
	private SkinnedMeshRenderer mSkinnedMeshRenderer ~ delete _;
	private ShadowRenderer mShadowRenderer ~ delete _;
	private ParticleRenderer mParticleRenderer ~ delete _;
	private SpriteRenderer mSpriteRenderer ~ delete _;
	private SkyboxRenderer mSkyboxRenderer ~ delete _;
	private TrailRenderer mTrailRenderer ~ delete _;

	// ==================== Per-Frame GPU Resources ====================

	// Primary camera buffers (view slot 0) - backward compatible
	private IBuffer[MAX_FRAMES] mCameraBuffers ~ { for (let b in _) delete b; };
	private IBuffer[MAX_FRAMES] mBillboardCameraBuffers ~ { for (let b in _) delete b; };

	// Additional view slots for multi-view rendering (view slots 1-3)
	private IBuffer[MAX_FRAMES * (MAX_VIEWS - 1)] mMultiViewCameraBuffers ~ { for (let b in _) delete b; };
	private IBuffer[MAX_FRAMES * (MAX_VIEWS - 1)] mMultiViewBillboardBuffers ~ { for (let b in _) delete b; };

	private IBindGroupLayout mSceneBindGroupLayout ~ delete _;

	// ==================== State ====================

	private bool mInitialized;
	private TextureFormat mColorFormat;
	private TextureFormat mDepthFormat;

	// ==================== Temporary Lists ====================

	private List<ParticleEmitterProxy*> mVisibleParticles = new .() ~ delete _;
	private List<ParticleTrail> mTempParticleTrails = new .() ~ delete _;  // For per-particle trail rendering
	private List<RenderView*> mSortedViews = new .() ~ delete _;

	// ==================== Public Accessors ====================

	/// Gets the static mesh renderer.
	public StaticMeshRenderer StaticMeshRenderer => mStaticMeshRenderer;

	/// Gets the skinned mesh renderer.
	public SkinnedMeshRenderer SkinnedMeshRenderer => mSkinnedMeshRenderer;

	/// Gets the shadow renderer.
	public ShadowRenderer ShadowRenderer => mShadowRenderer;

	/// Gets the particle renderer.
	public ParticleRenderer ParticleRenderer => mParticleRenderer;

	/// Gets the sprite renderer.
	public SpriteRenderer SpriteRenderer => mSpriteRenderer;

	/// Gets the skybox renderer.
	public SkyboxRenderer SkyboxRenderer => mSkyboxRenderer;

	/// Gets the trail renderer.
	public TrailRenderer TrailRenderer => mTrailRenderer;

	/// Gets the scene bind group layout (for contexts to create bind groups).
	public IBindGroupLayout SceneBindGroupLayout => mSceneBindGroupLayout;

	/// Gets the camera buffer for a frame (view slot 0).
	public IBuffer GetCameraBuffer(int32 frameIndex) => mCameraBuffers[frameIndex];

	/// Gets the billboard camera buffer for a frame (view slot 0).
	public IBuffer GetBillboardCameraBuffer(int32 frameIndex) => mBillboardCameraBuffers[frameIndex];

	/// Gets the camera buffer for a specific frame and view slot.
	/// viewSlot 0 returns the primary camera buffer.
	/// viewSlots 1-3 return additional multi-view buffers.
	public IBuffer GetCameraBuffer(int32 frameIndex, int32 viewSlot)
	{
		if (viewSlot == 0)
			return mCameraBuffers[frameIndex];
		if (viewSlot > 0 && viewSlot < MAX_VIEWS)
		{
			int32 index = frameIndex * (MAX_VIEWS - 1) + (viewSlot - 1);
			return mMultiViewCameraBuffers[index];
		}
		return null;
	}

	/// Gets the billboard camera buffer for a specific frame and view slot.
	public IBuffer GetBillboardCameraBuffer(int32 frameIndex, int32 viewSlot)
	{
		if (viewSlot == 0)
			return mBillboardCameraBuffers[frameIndex];
		if (viewSlot > 0 && viewSlot < MAX_VIEWS)
		{
			int32 index = frameIndex * (MAX_VIEWS - 1) + (viewSlot - 1);
			return mMultiViewBillboardBuffers[index];
		}
		return null;
	}

	/// Gets the camera buffers array (for context bind group creation).
	public IBuffer[MAX_FRAMES] CameraBuffers => mCameraBuffers;

	/// Gets the maximum number of simultaneous view slots.
	public int32 MaxViewSlots => MAX_VIEWS;

	/// Gets whether the pipeline is initialized.
	public bool IsInitialized => mInitialized;

	// ==================== Initialization ====================

	/// Initializes the render pipeline with shared services.
	public Result<void> Initialize(
		IDevice device,
		ShaderLibrary shaderLibrary,
		MaterialSystem materialSystem,
		GPUResourceManager resourceManager,
		PipelineCache pipelineCache,
		TextureFormat colorFormat,
		TextureFormat depthFormat)
	{
		if (mInitialized)
			return .Ok;

		mDevice = device;
		mShaderLibrary = shaderLibrary;
		mMaterialSystem = materialSystem;
		mResourceManager = resourceManager;
		mPipelineCache = pipelineCache;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		// Create per-frame camera buffers (primary view slot 0)
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			// Scene camera buffer
			BufferDescriptor cameraDesc = .((uint64)sizeof(SceneCameraUniforms), .Uniform, .Upload);
			if (device.CreateBuffer(&cameraDesc) case .Ok(let cameraBuf))
				mCameraBuffers[i] = cameraBuf;
			else
				return .Err;

			// Billboard camera buffer
			BufferDescriptor billboardDesc = .((uint64)sizeof(BillboardCameraUniforms), .Uniform, .Upload);
			if (device.CreateBuffer(&billboardDesc) case .Ok(let billboardBuf))
				mBillboardCameraBuffers[i] = billboardBuf;
			else
				return .Err;
		}

		// Create additional multi-view camera buffers (view slots 1-3)
		for (int i = 0; i < MAX_FRAMES * (MAX_VIEWS - 1); i++)
		{
			BufferDescriptor cameraDesc = .((uint64)sizeof(SceneCameraUniforms), .Uniform, .Upload);
			if (device.CreateBuffer(&cameraDesc) case .Ok(let cameraBuf))
				mMultiViewCameraBuffers[i] = cameraBuf;
			else
				return .Err;

			BufferDescriptor billboardDesc = .((uint64)sizeof(BillboardCameraUniforms), .Uniform, .Upload);
			if (device.CreateBuffer(&billboardDesc) case .Ok(let billboardBuf))
				mMultiViewBillboardBuffers[i] = billboardBuf;
			else
				return .Err;
		}

		// Create scene bind group layout
		if (CreateSceneBindGroupLayout() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	/// Initializes sub-renderers. Call after Initialize() and after a context is available
	/// (since we need a LightingSystem for ShadowRenderer).
	public Result<void> InitializeRenderers(LightingSystem lightingSystem)
	{
		if (!mInitialized)
			return .Err;

		// Initialize static mesh renderer
		mStaticMeshRenderer = new StaticMeshRenderer();
		if (mStaticMeshRenderer.Initialize(mDevice, mShaderLibrary, mResourceManager, mMaterialSystem,
			mPipelineCache, mSceneBindGroupLayout, mColorFormat, mDepthFormat) case .Err)
			return .Err;

		// Initialize skinned mesh renderer
		mSkinnedMeshRenderer = new SkinnedMeshRenderer();
		if (mSkinnedMeshRenderer.Initialize(mDevice, mShaderLibrary, mMaterialSystem, mResourceManager,
			mPipelineCache, mSceneBindGroupLayout, mColorFormat, mDepthFormat) case .Err)
			return .Err;

		// Initialize shadow renderer (needs lighting system for shadow maps)
		mShadowRenderer = new ShadowRenderer();
		if (mShadowRenderer.Initialize(mDevice, mShaderLibrary, lightingSystem, mResourceManager) case .Err)
			return .Err;

		// Initialize skybox renderer
		mSkyboxRenderer = new SkyboxRenderer(mDevice);
		let topColor = Color(70, 130, 200, 255);
		let bottomColor = Color(180, 210, 240, 255);
		if (!mSkyboxRenderer.CreateGradientSky(topColor, bottomColor, 32))
			return .Err;

		IBuffer[MAX_FRAMES] cameraBuffersArray = .(mCameraBuffers[0], mCameraBuffers[1]);
		if (mSkyboxRenderer.Initialize(mShaderLibrary, cameraBuffersArray, mColorFormat, mDepthFormat) case .Err)
			return .Err;

		// Initialize particle renderer
		mParticleRenderer = new ParticleRenderer(mDevice);
		IBuffer[MAX_FRAMES] billboardBuffersArray = .(mBillboardCameraBuffers[0], mBillboardCameraBuffers[1]);
		if (mParticleRenderer.Initialize(mShaderLibrary, billboardBuffersArray, mColorFormat, mDepthFormat) case .Err)
			return .Err;

		// Initialize sprite renderer
		mSpriteRenderer = new SpriteRenderer(mDevice);
		if (mSpriteRenderer.Initialize(mShaderLibrary, billboardBuffersArray, mColorFormat, mDepthFormat) case .Err)
			return .Err;

		// Initialize trail renderer
		mTrailRenderer = new TrailRenderer(mDevice);
		if (mTrailRenderer.Initialize(mShaderLibrary, billboardBuffersArray, mColorFormat, mDepthFormat) case .Err)
			return .Err;

		return .Ok;
	}

	/// Creates the scene bind group layout.
	private Result<void> CreateSceneBindGroupLayout()
	{
		// Bind group layout with camera, lighting, and shadow resources
		BindGroupLayoutEntry[7] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),         // Camera uniforms (b0)
			BindGroupLayoutEntry.UniformBuffer(2, .Fragment),                    // Lighting uniforms (b2)
			BindGroupLayoutEntry.StorageBuffer(0, .Fragment),                    // Light buffer (t0)
			BindGroupLayoutEntry.UniformBuffer(3, .Fragment),                    // Shadow uniforms (b3)
			BindGroupLayoutEntry.SampledTexture(1, .Fragment, .Texture2DArray),  // Cascade shadow map (t1)
			BindGroupLayoutEntry.SampledTexture(2, .Fragment, .Texture2D),       // Shadow atlas (t2)
			BindGroupLayoutEntry.Sampler(0, .Fragment)                           // Shadow sampler (s0)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mSceneBindGroupLayout = layout;

		return .Ok;
	}

	// ==================== Main Rendering Entry Points ====================

	/// Prepares visibility for all camera views.
	/// Automatically handles single-view and multi-view scenarios.
	/// Builds batches for static and skinned mesh renderers.
	public void PrepareVisibility(RenderContext context)
	{
		if (!mInitialized)
			return;

		// Resolve visibility (auto-detects single vs multi-view)
		context.ResolveVisibility();

		// Build batches for static meshes
		mStaticMeshRenderer?.BuildBatches(context.VisibleMeshes);

		// Build batches for skinned meshes
		mSkinnedMeshRenderer?.BuildBatches();
	}

	/// Prepares GPU resources for rendering.
	/// Uploads instance data, lighting uniforms, and camera uniforms for all views.
	public void PrepareGPU(RenderContext context)
	{
		if (!mInitialized)
			return;

		let frameIndex = context.FrameIndex;
		let mainView = context.MainView;
		let lighting = context.Lighting;

		// Upload static mesh instance data
		mStaticMeshRenderer?.PrepareGPU(frameIndex);

		// Update lighting system from main view
		if (lighting != null && mainView != null)
		{
			lighting.UpdateFromView(mainView, context.ActiveLights, frameIndex);
			lighting.PrepareShadowsFromView(mainView);
			lighting.UploadShadowUniforms(frameIndex);
		}

		// Upload camera uniforms for ALL camera views, each to its own slot
		int32 viewSlot = 0;
		let views = context.GetViews();
		for (int i = 0; i < views.Length && viewSlot < MAX_VIEWS; i++)
		{
			if (views[i].Type == .MainCamera || views[i].Type == .SecondaryCamera)
			{
				UploadCameraUniforms(&views[i], frameIndex, viewSlot);
				UploadBillboardCameraUniforms(&views[i], frameIndex, viewSlot);
				viewSlot++;
			}
		}

		// Ensure context has bind groups for all camera views
		context.CreateViewBindGroups(mSceneBindGroupLayout, this, viewSlot);
	}

	/// Renders shadow passes for all cascades.
	/// Returns true if shadows were rendered.
	public bool RenderShadows(RenderContext context, ICommandEncoder encoder)
	{
		if (!mInitialized)
			return false;

		if (mShadowRenderer == null || context.Lighting == null)
			return false;

		if (!context.Lighting.HasDirectionalShadows)
			return false;

		return mShadowRenderer.RenderShadows(encoder, context.FrameIndex,
			mStaticMeshRenderer, mSkinnedMeshRenderer);
	}

	/// Renders all views in the context.
	/// Views are rendered in priority order (shadows first, then cameras).
	/// Each camera view uses its own bind group with its own camera buffer.
	/// Note: Shadow views are handled by RenderShadows(), this only renders camera views.
	public void RenderViews(RenderContext context, IRenderPassEncoder renderPass,
		bool renderSkybox = true, bool renderParticles = true, bool renderSprites = true)
	{
		if (!mInitialized)
			return;

		let frameIndex = context.FrameIndex;

		// Reset trail renderer vertex offset for this frame
		if (mTrailRenderer != null)
			mTrailRenderer.BeginFrame(frameIndex);

		// Get all enabled views sorted by priority
		context.GetEnabledSortedViews(mSortedViews);

		// Render each camera view with its corresponding bind group
		int32 viewSlot = 0;
		for (let view in mSortedViews)
		{
			// Only render camera views in this pass
			if (view.Type != .MainCamera && view.Type != .SecondaryCamera)
				continue;

			// Skip views with invalid dimensions
			if (view.ViewportWidth == 0 || view.ViewportHeight == 0)
				continue;

			// Get the bind group for this view slot
			let bindGroup = context.GetViewBindGroup(frameIndex, viewSlot);
			if (bindGroup == null)
				continue;

			// Render the view
			RenderViewInternal(context, view, renderPass, bindGroup, viewSlot, renderSkybox, renderParticles, renderSprites);
			viewSlot++;
		}
	}

	/// Renders a single view using its assigned view slot.
	/// For advanced usage when you need to render a specific view.
	public void RenderView(RenderContext context, RenderView* view, IRenderPassEncoder renderPass,
		int32 viewSlot = 0,
		bool renderSkybox = true, bool renderParticles = true, bool renderSprites = true)
	{
		if (!mInitialized || view == null)
			return;

		let bindGroup = context.GetViewBindGroup(context.FrameIndex, viewSlot);
		if (bindGroup != null)
			RenderViewInternal(context, view, renderPass, bindGroup, viewSlot, renderSkybox, renderParticles, renderSprites);
	}

	/// Internal render view implementation.
	private void RenderViewInternal(RenderContext context, RenderView* view, IRenderPassEncoder renderPass,
		IBindGroup sceneBindGroup, int32 viewSlot,
		bool renderSkybox = true, bool renderParticles = true, bool renderSprites = true)
	{
		if (!mInitialized || view == null)
			return;

		let frameIndex = context.FrameIndex;

		// Set viewport from view
		renderPass.SetViewport(view.ViewportX, view.ViewportY,
			view.ViewportWidth, view.ViewportHeight, 0, 1);
		renderPass.SetScissorRect(view.ScissorX, view.ScissorY,
			view.ScissorWidth, view.ScissorHeight);

		// Skybox (behind all geometry)
		if (renderSkybox && mSkyboxRenderer != null && mSkyboxRenderer.IsInitialized)
			mSkyboxRenderer.Render(renderPass, frameIndex);

		// Static meshes
		if (mStaticMeshRenderer != null)
			mStaticMeshRenderer.RenderMaterials(renderPass, sceneBindGroup, frameIndex);

		// Particles
		if (renderParticles && mParticleRenderer != null && mParticleRenderer.IsInitialized)
		{
			context.World.GetValidParticleEmitterProxies(mVisibleParticles);
			mParticleRenderer.RenderEmitters(renderPass, frameIndex, mVisibleParticles);

			// Render per-particle trails after particles
			if (mTrailRenderer != null && mTrailRenderer.IsInitialized)
			{
				// Get camera position from view
				Vector3 cameraPos = view != null ? view.Position : .Zero;

				for (let proxy in mVisibleParticles)
				{
					if (!proxy.IsVisible || proxy.System == null)
						continue;

					let particleSystem = proxy.System;
					if (!particleSystem.TrailsEnabled)
						continue;

					// Get trails from this particle system
					particleSystem.GetActiveTrails(mTempParticleTrails);
					if (mTempParticleTrails.Count == 0)
						continue;

					let settings = particleSystem.TrailSettings;
					let config = particleSystem.Config;
					let blendMode = config?.BlendMode ?? .AlphaBlend;

					// Render each trail
					for (let trail in mTempParticleTrails)
					{
						mTrailRenderer.RenderTrail(
							renderPass,
							frameIndex,
							trail,
							cameraPos,
							settings,
							blendMode,
							particleSystem.CurrentTime
						);
					}
				}
			}
		}

		// Sprites
		if (renderSprites && mSpriteRenderer != null && mSpriteRenderer.IsInitialized)
			mSpriteRenderer.Render(renderPass, frameIndex);

		// Skinned meshes - use view-slot-specific camera buffer
		if (mSkinnedMeshRenderer != null)
		{
			let cameraBuffer = GetCameraBuffer(frameIndex, viewSlot);
			mSkinnedMeshRenderer.Render(renderPass, cameraBuffer, sceneBindGroup, frameIndex);
		}
	}

	// ==================== Camera Uniform Upload ====================

	/// Uploads scene camera uniforms from a view to the primary buffer (view slot 0).
	/// Call this BEFORE starting a render pass for proper GPU visibility.
	/// For multi-view rendering, use the viewSlot overload instead.
	public void UploadCameraUniforms(RenderView* view, int32 frameIndex)
	{
		UploadCameraUniforms(view, frameIndex, 0);
	}

	/// Uploads scene camera uniforms from a view to a specific view slot.
	/// Call this BEFORE starting a render pass for proper GPU visibility.
	/// For multi-view rendering, each view should use a different slot (0-3).
	public void UploadCameraUniforms(RenderView* view, int32 frameIndex, int32 viewSlot)
	{
		if (view == null || mDevice?.Queue == null)
			return;

		let buffer = GetCameraBuffer(frameIndex, viewSlot);
		if (buffer == null)
			return;

		var projection = view.ProjectionMatrix;
		let viewMatrix = view.ViewMatrix;

		// Query flip projection directly from device
		if (mDevice.FlipProjectionRequired)
			projection.M22 = -projection.M22;

		SceneCameraUniforms cameraData = .();
		cameraData.ViewProjection = viewMatrix * projection;
		cameraData.View = viewMatrix;
		cameraData.Projection = projection;
		cameraData.CameraPosition = view.Position;

		Span<uint8> data = .((uint8*)&cameraData, sizeof(SceneCameraUniforms));
		mDevice.Queue.WriteBuffer(buffer, 0, data);
	}

	/// Uploads billboard camera uniforms from a view to the primary buffer (view slot 0).
	/// Call this BEFORE starting a render pass for proper GPU visibility.
	public void UploadBillboardCameraUniforms(RenderView* view, int32 frameIndex)
	{
		UploadBillboardCameraUniforms(view, frameIndex, 0);
	}

	/// Uploads billboard camera uniforms from a view to a specific view slot.
	/// Call this BEFORE starting a render pass for proper GPU visibility.
	/// For multi-view rendering, each view should use a different slot (0-3).
	public void UploadBillboardCameraUniforms(RenderView* view, int32 frameIndex, int32 viewSlot)
	{
		if (view == null || mDevice?.Queue == null)
			return;

		let buffer = GetBillboardCameraBuffer(frameIndex, viewSlot);
		if (buffer == null)
			return;

		var projection = view.ProjectionMatrix;
		let viewMatrix = view.ViewMatrix;

		// Query flip projection directly from device
		if (mDevice.FlipProjectionRequired)
			projection.M22 = -projection.M22;

		BillboardCameraUniforms billboardData = .();
		billboardData.ViewProjection = viewMatrix * projection;
		billboardData.View = viewMatrix;
		billboardData.Projection = projection;
		billboardData.CameraPosition = view.Position;

		Span<uint8> data = .((uint8*)&billboardData, sizeof(BillboardCameraUniforms));
		mDevice.Queue.WriteBuffer(buffer, 0, data);
	}
}

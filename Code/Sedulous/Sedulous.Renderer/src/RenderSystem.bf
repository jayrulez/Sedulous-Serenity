namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Centralizes frame rendering orchestration for the renderer.
/// Owns all sub-renderers, manages per-frame GPU resources, and coordinates
/// visibility resolution and rendering through the RenderView abstraction.
class RenderSystem
{
	private const int32 MAX_FRAMES = 2;

	// ==================== External Dependencies ====================

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;
	private MaterialSystem mMaterialSystem;
	private GPUResourceManager mResourceManager;
	private PipelineCache mPipelineCache;
	private LightingSystem mLightingSystem ~ delete _;

	// ==================== Sub-Renderers ====================

	private StaticMeshRenderer mStaticMeshRenderer ~ delete _;
	private SkinnedMeshRenderer mSkinnedMeshRenderer ~ delete _;
	private ShadowRenderer mShadowRenderer ~ delete _;
	private ParticleRenderer mParticleRenderer ~ delete _;
	private SpriteRenderer mSpriteRenderer ~ delete _;
	private SkyboxRenderer mSkyboxRenderer ~ delete _;

	// ==================== Visibility ====================

	private VisibilityResolver mVisibilityResolver ~ delete _;

	// ==================== Per-Frame Resources ====================

	private IBuffer[MAX_FRAMES] mCameraBuffers ~ { for (let b in _) delete b; };
	private IBuffer[MAX_FRAMES] mBillboardCameraBuffers ~ { for (let b in _) delete b; };
	private IBindGroup[MAX_FRAMES] mSceneBindGroups ~ { for (let g in _) delete g; };
	private IBindGroupLayout mSceneBindGroupLayout ~ delete _;

	// ==================== Frame State ====================

	private int32 mFrameIndex;
	private RenderView mMainView;
	private bool mInitialized;
	private TextureFormat mColorFormat;
	private TextureFormat mDepthFormat;
	private bool mShadowsEnabled = true;
	private bool mSkyboxEnabled = true;

	// ==================== Temporary Lists ====================

	private List<StaticMeshProxy*> mVisibleMeshes = new .() ~ delete _;
	private List<LightProxy*> mActiveLights = new .() ~ delete _;
	private List<ParticleEmitterProxy*> mVisibleParticles = new .() ~ delete _;

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

	/// Gets the visibility resolver.
	public VisibilityResolver Visibility => mVisibilityResolver;

	/// Gets the lighting system.
	public LightingSystem LightingSystem => mLightingSystem;

	/// Gets the scene bind group layout (for custom renderers).
	public IBindGroupLayout SceneBindGroupLayout => mSceneBindGroupLayout;

	/// Gets the scene bind group for a frame.
	public IBindGroup GetSceneBindGroup(int32 frameIndex) => mSceneBindGroups[frameIndex];

	/// Gets the camera buffer for a frame.
	public IBuffer GetCameraBuffer(int32 frameIndex) => mCameraBuffers[frameIndex];

	/// Gets the billboard camera buffer for a frame.
	public IBuffer GetBillboardCameraBuffer(int32 frameIndex) => mBillboardCameraBuffers[frameIndex];

	/// Gets whether the system is initialized.
	public bool IsInitialized => mInitialized;

	/// Gets or sets whether shadows are enabled.
	public bool ShadowsEnabled
	{
		get => mShadowsEnabled;
		set => mShadowsEnabled = value;
	}

	/// Gets or sets whether skybox rendering is enabled.
	public bool SkyboxEnabled
	{
		get => mSkyboxEnabled;
		set => mSkyboxEnabled = value;
	}

	/// Gets the current frame index.
	public int32 FrameIndex => mFrameIndex;

	/// Gets the current main view.
	public RenderView MainView => mMainView;

	/// Gets the visible mesh count after visibility resolution.
	public int32 VisibleMeshCount => (int32)mVisibleMeshes.Count;

	/// Gets the active light count.
	public int32 ActiveLightCount => (int32)mActiveLights.Count;

	// ==================== Initialization ====================

	/// Initializes the render system with all required dependencies.
	public Result<void> Initialize(
		IDevice device,
		ShaderLibrary shaderLibrary,
		MaterialSystem materialSystem,
		GPUResourceManager resourceManager,
		PipelineCache pipelineCache,
		LightingSystem lightingSystem,
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
		mLightingSystem = lightingSystem;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		// Create visibility resolver
		mVisibilityResolver = new VisibilityResolver();

		// Create per-frame camera buffers
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

		// Create scene bind group layout and bind groups
		if (CreateSceneBindGroups() case .Err)
			return .Err;

		// Initialize static mesh renderer
		mStaticMeshRenderer = new StaticMeshRenderer();
		if (mStaticMeshRenderer.Initialize(device, shaderLibrary, resourceManager, materialSystem,
			pipelineCache, mSceneBindGroupLayout, colorFormat, depthFormat) case .Err)
			return .Err;

		// Initialize skinned mesh renderer
		mSkinnedMeshRenderer = new SkinnedMeshRenderer();
		if (mSkinnedMeshRenderer.Initialize(device, shaderLibrary, materialSystem, resourceManager,
			pipelineCache, mSceneBindGroupLayout, colorFormat, depthFormat) case .Err)
			return .Err;

		// Initialize shadow renderer
		mShadowRenderer = new ShadowRenderer();
		if (mShadowRenderer.Initialize(device, shaderLibrary, lightingSystem, resourceManager) case .Err)
			return .Err;

		// Initialize skybox renderer
		mSkyboxRenderer = new SkyboxRenderer(device);
		// Create default gradient sky
		let topColor = Color(70, 130, 200, 255);
		let bottomColor = Color(180, 210, 240, 255);
		if (!mSkyboxRenderer.CreateGradientSky(topColor, bottomColor, 32))
			return .Err;

		IBuffer[MAX_FRAMES] cameraBuffersArray = .(mCameraBuffers[0], mCameraBuffers[1]);
		if (mSkyboxRenderer.Initialize(shaderLibrary, cameraBuffersArray, colorFormat, depthFormat) case .Err)
			return .Err;

		// Initialize particle renderer
		mParticleRenderer = new ParticleRenderer(device);
		IBuffer[MAX_FRAMES] billboardBuffersArray = .(mBillboardCameraBuffers[0], mBillboardCameraBuffers[1]);
		if (mParticleRenderer.Initialize(shaderLibrary, billboardBuffersArray, colorFormat, depthFormat) case .Err)
			return .Err;

		// Initialize sprite renderer
		mSpriteRenderer = new SpriteRenderer(device);
		if (mSpriteRenderer.Initialize(shaderLibrary, billboardBuffersArray, colorFormat, depthFormat) case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	/// Creates the scene bind group layout and per-frame bind groups.
	private Result<void> CreateSceneBindGroups()
	{
		// Bind group layout with lighting and shadow resources
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

		// Create per-frame bind groups with lighting resources
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			BindGroupEntry[7] entries = .(
				BindGroupEntry.Buffer(0, mCameraBuffers[i]),
				BindGroupEntry.Buffer(2, mLightingSystem.GetLightingUniformBuffer((int32)i)),
				BindGroupEntry.Buffer(0, mLightingSystem.GetLightBuffer((int32)i)),
				BindGroupEntry.Buffer(3, mLightingSystem.GetShadowUniformBuffer((int32)i)),
				BindGroupEntry.Texture(1, mLightingSystem.CascadeShadowMapView),
				BindGroupEntry.Texture(2, mLightingSystem.ShadowAtlasView),
				BindGroupEntry.Sampler(0, mLightingSystem.ShadowSampler)
			);
			BindGroupDescriptor bindGroupDesc = .(mSceneBindGroupLayout, entries);
			if (mDevice.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mSceneBindGroups[i] = group;
		}

		return .Ok;
	}

	// ==================== Frame Lifecycle ====================

	/// Begins a new frame with the given frame index and main view.
	public void BeginFrame(int32 frameIndex, RenderView mainView)
	{
		mFrameIndex = frameIndex;
		mMainView = mainView;
	}

	/// Performs visibility resolution using the current main view.
	public void PrepareVisibility(RenderWorld world)
	{
		if (!mInitialized || !mMainView.IsValid)
			return;

		// Use RenderView for visibility resolution with layer masks
		mVisibilityResolver.ResolveForView(world, &mMainView);

		// Collect visible meshes
		mVisibleMeshes.Clear();
		mVisibleMeshes.AddRange(mVisibilityResolver.OpaqueMeshes);
		mVisibleMeshes.AddRange(mVisibilityResolver.TransparentMeshes);

		// Build batches for static meshes
		mStaticMeshRenderer?.BuildBatches(mVisibleMeshes);

		// Build batches for skinned meshes
		mSkinnedMeshRenderer?.BuildBatches();

		// Gather active lights
		world.GetValidLightProxies(mActiveLights);
	}

	/// Uploads per-frame GPU data (instance buffers, camera uniforms, lighting).
	public void PrepareGPU(RenderWorld world, bool flipProjection = false)
	{
		if (!mInitialized)
			return;

		// Upload static mesh instance data
		mStaticMeshRenderer?.PrepareGPU(mFrameIndex);

		// Update lighting system
		if (mLightingSystem != null && mShadowsEnabled)
		{
			// Use view-based lighting update
			mLightingSystem.UpdateFromView(&mMainView, mActiveLights, mFrameIndex);
			mLightingSystem.PrepareShadowsFromView(&mMainView);
			mLightingSystem.UploadShadowUniforms(mFrameIndex);
		}

		// Upload camera uniforms from main view
		UploadCameraUniforms(flipProjection);
		UploadBillboardCameraUniforms(flipProjection);
	}

	/// Uploads scene camera uniforms from the main view.
	private void UploadCameraUniforms(bool flipProjection)
	{
		if (!mMainView.IsValid || mDevice?.Queue == null)
			return;

		var projection = mMainView.ProjectionMatrix;
		let view = mMainView.ViewMatrix;

		if (flipProjection)
			projection.M22 = -projection.M22;

		SceneCameraUniforms cameraData = .();
		cameraData.ViewProjection = view * projection;
		cameraData.View = view;
		cameraData.Projection = projection;
		cameraData.CameraPosition = mMainView.Position;

		Span<uint8> data = .((uint8*)&cameraData, sizeof(SceneCameraUniforms));
		mDevice.Queue.WriteBuffer(mCameraBuffers[mFrameIndex], 0, data);
	}

	/// Uploads billboard camera uniforms from the main view.
	private void UploadBillboardCameraUniforms(bool flipProjection)
	{
		if (!mMainView.IsValid || mDevice?.Queue == null)
			return;

		var projection = mMainView.ProjectionMatrix;
		let view = mMainView.ViewMatrix;

		if (flipProjection)
			projection.M22 = -projection.M22;

		BillboardCameraUniforms billboardData = .();
		billboardData.ViewProjection = view * projection;
		billboardData.View = view;
		billboardData.Projection = projection;
		billboardData.CameraPosition = mMainView.Position;

		Span<uint8> data = .((uint8*)&billboardData, sizeof(BillboardCameraUniforms));
		mDevice.Queue.WriteBuffer(mBillboardCameraBuffers[mFrameIndex], 0, data);
	}

	// ==================== Rendering ====================

	/// Renders shadow passes for all cascades.
	/// Call before the main render pass (requires ICommandEncoder).
	/// Returns true if shadows were rendered and a texture barrier is needed.
	public bool RenderShadows(ICommandEncoder encoder, RenderWorld world)
	{
		if (!mInitialized || !mShadowsEnabled)
			return false;

		if (mShadowRenderer == null || mLightingSystem == null)
			return false;

		if (!mLightingSystem.HasDirectionalShadows)
			return false;

		return mShadowRenderer.RenderShadows(encoder, mFrameIndex,
			mStaticMeshRenderer, mSkinnedMeshRenderer);
	}

	/// Renders the scene to the given render pass.
	public void Render(IRenderPassEncoder renderPass, RenderWorld world)
	{
		Render(renderPass, world, mSkyboxEnabled, true, true);
	}

	/// Renders the scene with configurable passes.
	public void Render(IRenderPassEncoder renderPass, RenderWorld world,
		bool renderSkybox, bool renderParticles, bool renderSprites)
	{
		if (!mInitialized)
			return;

		// Set viewport from main view
		renderPass.SetViewport(mMainView.ViewportX, mMainView.ViewportY,
			mMainView.ViewportWidth, mMainView.ViewportHeight, 0, 1);
		renderPass.SetScissorRect(mMainView.ScissorX, mMainView.ScissorY,
			mMainView.ScissorWidth, mMainView.ScissorHeight);

		let bindGroup = mSceneBindGroups[mFrameIndex];

		// Skybox (behind all geometry)
		if (renderSkybox && mSkyboxRenderer != null && mSkyboxRenderer.IsInitialized)
			mSkyboxRenderer.Render(renderPass, mFrameIndex);

		// Static meshes
		if (mStaticMeshRenderer != null)
			mStaticMeshRenderer.RenderMaterials(renderPass, bindGroup, mFrameIndex);

		// Particles
		if (renderParticles && mParticleRenderer != null && mParticleRenderer.IsInitialized)
		{
			world.GetValidParticleEmitterProxies(mVisibleParticles);
			mParticleRenderer.RenderEmitters(renderPass, mFrameIndex, mVisibleParticles);
		}

		// Sprites
		if (renderSprites && mSpriteRenderer != null && mSpriteRenderer.IsInitialized)
			mSpriteRenderer.Render(renderPass, mFrameIndex);

		// Skinned meshes
		if (mSkinnedMeshRenderer != null)
			mSkinnedMeshRenderer.Render(renderPass, mCameraBuffers[mFrameIndex], bindGroup, mFrameIndex);
	}

	/// Ends the current frame.
	public void EndFrame(RenderWorld world)
	{
		world.EndFrame();
	}

	// ==================== Utility Methods ====================

	/// Creates a main camera view from a camera proxy.
	public RenderView CreateMainCameraView(CameraProxy* camera)
	{
		if (camera == null)
			return .Invalid;

		return RenderView.FromCameraProxy(0, camera, null, null, true);
	}

	/// Gets the visible opaque meshes from the last visibility pass.
	public List<StaticMeshProxy*> OpaqueMeshes => mVisibilityResolver?.OpaqueMeshes;

	/// Gets the visible transparent meshes from the last visibility pass.
	public List<StaticMeshProxy*> TransparentMeshes => mVisibilityResolver?.TransparentMeshes;

	/// Gets the shadow casters from the last visibility pass.
	public List<StaticMeshProxy*> ShadowCasters => mVisibilityResolver?.ShadowCasters;

	/// Gets the active lights for this frame.
	public List<LightProxy*> ActiveLights => mActiveLights;
}

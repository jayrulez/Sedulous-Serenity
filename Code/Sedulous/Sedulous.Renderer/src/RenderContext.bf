namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Per-scene rendering context. Owns all scene-specific render state.
/// Created by engine layer, used by RenderPipeline for stateless rendering.
///
/// RenderContext consolidates:
/// - RenderWorld (proxy storage for meshes, lights, cameras, particles)
/// - LightingSystem (clustered lighting + shadow maps)
/// - VisibilityResolver (frustum culling)
/// - Per-frame views (main camera, shadow cascades, etc.)
///
/// Usage:
///   let context = RenderContext.Create(device);
///   context.BeginFrame(frameIndex);
///   context.AddView(mainCameraView);
///   context.Lighting.AddShadowViews(context);
///   pipeline.Render(context, renderPass);
///   context.EndFrame();
class RenderContext
{
	private const int32 MAX_FRAMES = 2;
	private const int32 MAX_VIEWS = 4;  // Maximum simultaneous camera views per frame

	// ==================== Owned Systems ====================

	/// The render world containing all proxies.
	private RenderWorld mWorld ~ delete _;

	/// The lighting system for this context.
	private LightingSystem mLighting ~ delete _;

	/// The visibility resolver for frustum culling.
	private VisibilityResolver mVisibility ~ delete _;

	// ==================== Per-Context GPU Resources ====================

	/// Per-view bind groups for all views.
	/// Index = frameIndex * MAX_VIEWS + viewSlot.
	/// Each view slot has its own bind group pointing to its own camera buffer.
	private IBindGroup[MAX_FRAMES * MAX_VIEWS] mViewBindGroups ~ { for (let g in _) if (g != null) delete g; };

	/// Number of bind groups created per frame.
	private int32 mBindGroupsPerFrame = 0;

	/// Reference to pipeline for camera buffer access.
	private RenderPipeline mPipeline;

	// ==================== Frame State ====================

	/// Current frame index for double buffering.
	private int32 mFrameIndex;

	/// List of render views for this frame.
	private List<RenderView> mViews = new .() ~ delete _;

	/// Index of the main view in the views list (-1 if not set).
	private int32 mMainViewIndex = -1;

	/// Next view ID for this frame.
	private uint32 mNextViewId = 0;

	/// Cached list of active lights for this frame.
	private List<LightProxy*> mActiveLights = new .() ~ delete _;

	/// Cached list of visible static meshes for this frame.
	private List<StaticMeshProxy*> mVisibleMeshes = new .() ~ delete _;

	/// Whether the context has been initialized.
	private bool mInitialized = false;

	/// Device reference for GPU operations.
	private IDevice mDevice;

	// ==================== Public Accessors ====================

	/// Gets the render world containing all proxies.
	public RenderWorld World => mWorld;

	/// Gets the lighting system.
	public LightingSystem Lighting => mLighting;

	/// Gets the visibility resolver.
	public VisibilityResolver Visibility => mVisibility;

	/// Gets the current frame index.
	public int32 FrameIndex => mFrameIndex;

	/// Gets the number of views for this frame.
	public int32 ViewCount => (int32)mViews.Count;

	/// Gets the main view for this frame (null if not set).
	public RenderView* MainView
	{
		get
		{
			if (mMainViewIndex >= 0 && mMainViewIndex < mViews.Count)
				return &mViews[mMainViewIndex];
			return null;
		}
	}

	/// Gets whether the context is initialized.
	public bool IsInitialized => mInitialized;

	/// Gets the active lights list (populated during frame).
	public List<LightProxy*> ActiveLights => mActiveLights;

	/// Gets the visible meshes list (populated after visibility resolution).
	public List<StaticMeshProxy*> VisibleMeshes => mVisibleMeshes;

	/// Gets the bind group for a specific view slot.
	/// Each camera view has its own bind group with its own camera buffer.
	public IBindGroup GetViewBindGroup(int32 frameIndex, int32 viewSlot)
	{
		if (frameIndex >= 0 && frameIndex < MAX_FRAMES && viewSlot >= 0 && viewSlot < MAX_VIEWS)
		{
			int index = frameIndex * MAX_VIEWS + viewSlot;
			return mViewBindGroups[index];
		}
		return null;
	}

	/// Gets the bind group for view slot 0 (main/default view).
	public IBindGroup GetSceneBindGroup(int32 frameIndex)
	{
		return GetViewBindGroup(frameIndex, 0);
	}

	// ==================== Factory ====================

	/// Creates a new render context with all systems initialized.
	public static Result<RenderContext> Create(IDevice device)
	{
		let context = new RenderContext();
		context.Initialize(device);
		return .Ok(context);
	}

	/// Initializes the render context.
	private void Initialize(IDevice device)
	{
		mDevice = device;

		// Create render world
		mWorld = new RenderWorld();

		// Create lighting system (initializes in constructor)
		mLighting = new LightingSystem(device);

		// Create visibility resolver
		mVisibility = new VisibilityResolver();

		mInitialized = true;
	}

	/// Creates bind groups for all view slots.
	/// Called by RenderPipeline during PrepareGPU.
	/// Each view slot gets its own bind group with its own camera buffer.
	public Result<void> CreateViewBindGroups(IBindGroupLayout layout, RenderPipeline pipeline, int32 viewCount)
	{
		mPipeline = pipeline;

		// Clamp to valid range
		int32 neededCount = Math.Min(Math.Max(viewCount, 1), MAX_VIEWS);

		// Check if we already have enough bind groups
		if (mBindGroupsPerFrame >= neededCount)
			return .Ok;

		// Create bind groups for each view slot that doesn't exist yet
		for (int32 frame = 0; frame < MAX_FRAMES; frame++)
		{
			for (int32 viewSlot = mBindGroupsPerFrame; viewSlot < neededCount; viewSlot++)
			{
				int index = frame * MAX_VIEWS + viewSlot;

				let cameraBuffer = pipeline.GetCameraBuffer(frame, viewSlot);
				if (cameraBuffer == null)
					continue;

				BindGroupEntry[7] entries = .(
					BindGroupEntry.Buffer(0, cameraBuffer),
					BindGroupEntry.Buffer(2, mLighting.GetLightingUniformBuffer(frame)),
					BindGroupEntry.Buffer(0, mLighting.GetLightBuffer(frame)),
					BindGroupEntry.Buffer(3, mLighting.GetShadowUniformBuffer(frame)),
					BindGroupEntry.Texture(1, mLighting.CascadeShadowMapView),
					BindGroupEntry.Texture(2, mLighting.ShadowAtlasView),
					BindGroupEntry.Sampler(0, mLighting.ShadowSampler)
				);

				BindGroupDescriptor desc = .(layout, entries);
				if (mDevice.CreateBindGroup(&desc) case .Ok(let group))
					mViewBindGroups[index] = group;
			}
		}

		mBindGroupsPerFrame = neededCount;
		return .Ok;
	}

	// ==================== Frame Lifecycle ====================

	/// Begins a new frame. Call at the start of PrepareGPU.
	/// This clears views and updates world state.
	public void BeginFrame(int32 frameIndex)
	{
		mFrameIndex = frameIndex;

		// Clear views from previous frame
		mViews.Clear();
		mMainViewIndex = -1;
		mNextViewId = 0;

		// Clear cached data
		mActiveLights.Clear();
		mVisibleMeshes.Clear();

		// Update render world (camera matrices, etc.)
		mWorld.BeginFrame();

		// Gather active lights
		mWorld.GetValidLightProxies(mActiveLights);
	}

	/// Adds a render view for this frame.
	/// Returns the index of the added view.
	public int32 AddView(RenderView view)
	{
		var v = view;
		v.Id = mNextViewId++;
		let index = (int32)mViews.Count;
		mViews.Add(v);
		return index;
	}

	/// Sets which view is the main camera view.
	/// The main view is used for primary rendering (lighting updates, etc.).
	public void SetMainView(int32 viewIndex)
	{
		if (viewIndex >= 0 && viewIndex < mViews.Count)
			mMainViewIndex = viewIndex;
	}

	/// Adds a main camera view from the current main camera proxy.
	/// Returns the view index, or -1 if no main camera is set.
	public int32 AddMainCameraView(ITextureView* colorTarget, ITextureView* depthTarget)
	{
		if (let camera = mWorld.MainCamera)
		{
			let view = RenderView.FromCameraProxy(mNextViewId, camera, colorTarget, depthTarget, true);
			let index = AddView(view);
			SetMainView(index);
			return index;
		}
		return -1;
	}

	/// Adds a camera view from a camera proxy handle.
	/// Returns the view index, or -1 if the handle is invalid.
	public int32 AddCameraView(ProxyHandle cameraHandle, ITextureView* colorTarget, ITextureView* depthTarget, bool isMain = false)
	{
		if (let camera = mWorld.GetCameraProxy(cameraHandle))
		{
			let view = RenderView.FromCameraProxy(mNextViewId, camera, colorTarget, depthTarget, isMain);
			let index = AddView(view);
			if (isMain)
				SetMainView(index);
			return index;
		}
		return -1;
	}

	/// Gets the view list for iteration.
	public Span<RenderView> GetViews()
	{
		return mViews;
	}

	/// Gets a view by index.
	public RenderView* GetView(int32 index)
	{
		if (index >= 0 && index < mViews.Count)
			return &mViews[index];
		return null;
	}

	/// Gets all views sorted by priority (lower priority renders first).
	/// Shadow views have negative priority, so they render before camera views.
	public void GetSortedViews(List<RenderView*> outViews)
	{
		outViews.Clear();
		for (var i < mViews.Count)
			outViews.Add(&mViews[i]);

		outViews.Sort(scope (a, b) => (int32)a.Priority - (int32)b.Priority);
	}

	/// Gets all enabled views sorted by priority.
	public void GetEnabledSortedViews(List<RenderView*> outViews)
	{
		outViews.Clear();
		for (var i < mViews.Count)
		{
			if (mViews[i].IsEnabled)
				outViews.Add(&mViews[i]);
		}

		outViews.Sort(scope (a, b) => (int32)a.Priority - (int32)b.Priority);
	}

	/// Ends the current frame. Call after rendering is complete.
	public void EndFrame()
	{
		mWorld.EndFrame();
	}

	// ==================== Shadow View Helpers ====================

	/// Adds shadow cascade views based on current lighting configuration.
	/// Returns the number of shadow views added.
	public int32 AddShadowCascadeViews()
	{
		if (mLighting == null || !mLighting.HasDirectionalShadows)
			return 0;

		int32 count = 0;
		for (int32 i = 0; i < LightingSystem.CASCADE_COUNT; i++)
		{
			let cascadeData = mLighting.GetCascadeData(i);
			ITextureView depthTarget = mLighting.GetCascadeRenderView(i);

			if (depthTarget != null)
			{
				let view = RenderView.ForShadowCascade(
					mNextViewId,
					i,
					cascadeData.ViewProjection,
					&depthTarget,
					LightingSystem.SHADOW_MAP_SIZE,
					0, 0,
					.Invalid,  // No light handle for directional cascades
					0xFFFFFFFF
				);
				AddView(view);
				count++;
			}
		}

		return count;
	}

	/// Adds shadow cascade views for a specific directional light.
	public int32 AddShadowCascadeViews(
		Span<CascadeData> cascadeData,
		Span<ITextureView*> depthTargets,
		uint32 shadowMapSize,
		ProxyHandle lightHandle,
		uint32 layerMask = 0xFFFFFFFF)
	{
		int32 count = 0;
		int32 cascadeCount = Math.Min((int32)cascadeData.Length, (int32)depthTargets.Length);

		for (int32 i = 0; i < cascadeCount; i++)
		{
			if (depthTargets[i] == null)
				continue;

			let view = RenderView.ForShadowCascade(
				mNextViewId,
				i,
				cascadeData[i].ViewProjection,
				depthTargets[i],
				shadowMapSize,
				0, 0,
				lightHandle,
				layerMask
			);
			AddView(view);
			count++;
		}

		return count;
	}

	/// Adds a local shadow view (point/spot light).
	public int32 AddLocalShadowView(
		int32 atlasSlot,
		Matrix viewProjection,
		ITextureView* depthTarget,
		int32 viewportX,
		int32 viewportY,
		uint32 tileSize,
		ProxyHandle lightHandle,
		uint32 layerMask = 0xFFFFFFFF)
	{
		if (depthTarget == null)
			return -1;

		let view = RenderView.ForLocalShadow(
			mNextViewId,
			atlasSlot,
			viewProjection,
			depthTarget,
			viewportX,
			viewportY,
			tileSize,
			lightHandle,
			layerMask
		);
		return AddView(view);
	}

	// ==================== Visibility Helpers ====================

	/// Resolves visibility for all camera views and populates VisibleMeshes.
	/// Automatically handles single-view and multi-view scenarios:
	/// - Single camera view: standard frustum culling
	/// - Multiple camera views: unions visibility from all cameras
	public void ResolveVisibility()
	{
		mVisibleMeshes.Clear();

		// Count camera views
		int32 cameraViewCount = 0;
		for (let view in mViews)
		{
			if (view.Type == .MainCamera || view.Type == .SecondaryCamera)
				cameraViewCount++;
		}

		if (cameraViewCount == 0)
			return;

		if (cameraViewCount == 1)
		{
			// Single camera - simple path
			if (let mainView = MainView)
			{
				mVisibility.ResolveForView(mWorld, mainView);
				mVisibleMeshes.AddRange(mVisibility.OpaqueMeshes);
				mVisibleMeshes.AddRange(mVisibility.TransparentMeshes);
			}
		}
		else
		{
			// Multiple cameras - union visibility from all
			HashSet<StaticMeshProxy*> visibleSet = scope .();

			for (var view in ref mViews)
			{
				if (view.Type != .MainCamera && view.Type != .SecondaryCamera)
					continue;

				mVisibility.ResolveForView(mWorld, &view);

				for (let mesh in mVisibility.OpaqueMeshes)
					visibleSet.Add(mesh);
				for (let mesh in mVisibility.TransparentMeshes)
					visibleSet.Add(mesh);
			}

			for (let mesh in visibleSet)
				mVisibleMeshes.Add(mesh);
		}
	}

	/// Resolves visibility for a specific view (for advanced usage).
	public void ResolveVisibilityForView(RenderView* view)
	{
		if (view != null)
			mVisibility.ResolveForView(mWorld, view);
	}

	// ==================== Multi-View Helpers ====================

	/// Adds a split-screen camera view.
	/// splitIndex: 0=left/top, 1=right/bottom
	/// horizontal: true for side-by-side, false for top-bottom
	/// Returns the view index, or -1 if the camera handle is invalid.
	public int32 AddSplitScreenView(
		ProxyHandle cameraHandle,
		ITextureView* colorTarget,
		ITextureView* depthTarget,
		uint32 targetWidth,
		uint32 targetHeight,
		int32 splitIndex,
		bool horizontal = true)
	{
		if (let camera = mWorld.GetCameraProxy(cameraHandle))
		{
			let view = RenderView.ForSplitScreen(
				mNextViewId,
				camera,
				colorTarget,
				depthTarget,
				targetWidth,
				targetHeight,
				splitIndex,
				horizontal
			);
			let index = AddView(view);
			if (splitIndex == 0)
				SetMainView(index);
			return index;
		}
		return -1;
	}

	/// Adds multiple camera views for 2-player split-screen.
	/// Returns the number of views added (0-2).
	public int32 AddTwoPlayerSplitScreen(
		ProxyHandle camera1Handle,
		ProxyHandle camera2Handle,
		ITextureView* colorTarget,
		ITextureView* depthTarget,
		uint32 targetWidth,
		uint32 targetHeight,
		bool horizontal = true)
	{
		int32 count = 0;

		if (AddSplitScreenView(camera1Handle, colorTarget, depthTarget,
			targetWidth, targetHeight, 0, horizontal) >= 0)
			count++;

		if (AddSplitScreenView(camera2Handle, colorTarget, depthTarget,
			targetWidth, targetHeight, 1, horizontal) >= 0)
			count++;

		return count;
	}

	/// Gets the number of camera views (excluding shadow/reflection views).
	public int32 CameraViewCount
	{
		get
		{
			int32 count = 0;
			for (let view in mViews)
			{
				if (view.Type == .MainCamera || view.Type == .SecondaryCamera)
					count++;
			}
			return count;
		}
	}

	/// Gets the number of shadow views.
	public int32 ShadowViewCount
	{
		get
		{
			int32 count = 0;
			for (let view in mViews)
			{
				if (view.Type == .ShadowCascade || view.Type == .ShadowLocal)
					count++;
			}
			return count;
		}
	}
}

namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Materials;
using Sedulous.Core.Mathematics;
using Sedulous.Profiler;
using Sedulous.RenderGraph;

/// Statistics for a single frame.
public struct RenderStats
{
	public int32 DrawCalls;
	public int32 InstanceCount;
	public int32 TriangleCount;
	public int32 VisibleMeshes;
	public int32 CulledMeshes;
	public int32 ShadowDrawCalls;
	public int32 TransparentDrawCalls;
	public int32 ComputeDispatches;
	public float GpuTimeMs;

	public void Reset() mut
	{
		this = default;
	}
}

/// Main entry point for the Sedulous.Render system.
/// Owns all rendering subsystems and orchestrates frame rendering.
public class RenderSystem : IDisposable
{
	private IDevice mDevice;
	private IQueue mGraphicsQueue;
	private bool mInitialized = false;
	private uint64 mFrameNumber = 0;

	// Core systems
	private RenderFrameContext mRenderFrameContext ~ delete _;
	private RenderGraph mRenderGraph;
	private SharedResources mSharedResources ~ delete _;
	private GPUResourceManager mResourceManager ~ delete _;
	private ShaderSystem mShaderSystem ~ delete _;
	private MaterialSystem mMaterialSystem ~ delete _;
	private RenderPipelineCache mPipelineCache ~ delete _;
	private SkinningSystem mSkinningSystem ~ delete _;
	private LightingSystem mLightingSystem ~ { _?.Dispose(); delete _; };
	private SharedBindGroupLayouts mSharedLayouts ~ delete _;
	private ShadowRenderer mShadowRenderer ~ { _?.Dispose(); delete _; };
	private ReflectionProbeSystem mProbeSystem ~ { _?.Dispose(); delete _; };
	private ViewContext mViewContext = new .() ~ delete _;
	private VisibilityResolver mVisibility = new .() ~ delete _;
	private FrustumCuller mCuller = new .() ~ delete _;
	private DrawBatcher mBatcher = new .() ~ delete _;

	// Render features
	private List<IRenderFeature> mFeatures = new .() ~ delete _;
	private Dictionary<String, IRenderFeature> mFeaturesByName = new .() ~ DeleteDictionaryAndKeys!(_);
	private List<IRenderFeature> mSortedFeatures = new .() ~ delete _;
	private bool mFeaturesSorted = false;

	// Render world (scene data)
	private RenderWorld mActiveWorld;

	// Transfer batch for init-time GPU uploads
	private ITransferBatch mTransferBatch;

	// Init context for feature initialization (valid between Initialize and first BeginFrame)
	private InitContext mInitContext ~ delete _;

	// Post-processing stack
	private PostProcessStack mPostProcessStack ~ delete _;
	private RGHandle mPostProcessOutput = .Invalid;

	// Auto-exposure (standalone, not part of PostProcessStack)
	private AutoExposureEffect mAutoExposure ~ delete _;

	// Statistics
	private RenderStats mStats;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;

	// Viewport dimensions (set externally, since RenderSystem doesn't own the swapchain)
	private uint32 mViewportWidth;
	private uint32 mViewportHeight;

	/// Gets whether the renderer is initialized.
	public bool IsInitialized => mInitialized;

	/// Gets the graphics device.
	public IDevice Device => mDevice;

	/// Gets the frame context.
	public RenderFrameContext RenderFrameContext => mRenderFrameContext;

	/// Gets the render graph.
	public RenderGraph RenderGraph => mRenderGraph;

	/// Shared default textures and samplers.
	public SharedResources SharedResources => mSharedResources;

	/// Lighting system (light buffer, cluster grid, culling).
	public LightingSystem LightingSystem => mLightingSystem;

	/// Shadow renderer (cascaded shadows, shadow atlas).
	public ShadowRenderer ShadowRenderer => mShadowRenderer;

	/// Shared bind group layouts and scene bind group creation.
	public SharedBindGroupLayouts SharedLayouts => mSharedLayouts;

	/// Reflection probe system.
	public ReflectionProbeSystem ProbeSystem => mProbeSystem;

	/// Per-view context (populated by RenderSystem before features run).
	public ViewContext ViewContext => mViewContext;

	/// Shared visibility resolver (populated by RenderSystem before features run).
	public VisibilityResolver Visibility => mVisibility;

	/// Shared draw batcher (populated by RenderSystem before features run).
	public DrawBatcher Batcher => mBatcher;

	/// Gets the GPU resource manager.
	public GPUResourceManager ResourceManager => mResourceManager;

	/// Gets the shader system.
	public ShaderSystem ShaderSystem => mShaderSystem;

	/// Gets the material system.
	public MaterialSystem MaterialSystem => mMaterialSystem;

	/// Gets the pipeline cache for dynamic pipeline creation.
	public RenderPipelineCache PipelineCache => mPipelineCache;

	/// GPU skinning system (infrastructure, not a feature)
	public SkinningSystem SkinningSystem => mSkinningSystem;

	/// Gets the current frame statistics.
	public ref RenderStats Stats => ref mStats;

	/// Gets the current frame number.
	public uint64 FrameNumber => mFrameNumber;

	/// Gets the color format.
	public TextureFormat ColorFormat => mColorFormat;

	/// Gets the depth format.
	public TextureFormat DepthFormat => mDepthFormat;

	/// Gets the active render world.
	public RenderWorld ActiveWorld => mActiveWorld;

	/// Gets the post-process stack.
	public PostProcessStack PostProcessStack => mPostProcessStack;

	/// Gets the auto-exposure effect.
	public AutoExposureEffect AutoExposure => mAutoExposure;


	/// Gets the post-process output handle for the current frame.
	/// Returns the final output from post-processing, or invalid handle if no effects are enabled.
	public RGHandle PostProcessOutput => mPostProcessOutput;

	/// Current viewport width.
	public uint32 ViewportWidth => mViewportWidth;

	/// Current viewport height.
	public uint32 ViewportHeight => mViewportHeight;

	/// Sets the viewport size. Notifies all features when dimensions change.
	public void SetViewportSize(uint32 width, uint32 height)
	{
		if (width == mViewportWidth && height == mViewportHeight)
			return;

		mViewportWidth = width;
		mViewportHeight = height;

		for (let feature in mSortedFeatures)
			feature.OnViewportResize(width, height);
	}

	/// Initializes the render system.
	public Result<void> Initialize(
		IDevice device,
		uint32 viewportWidth,
		uint32 viewportHeight,
		Span<StringView> shaderPaths = default,
		StringView? shaderCachePath = null,
		TextureFormat colorFormat = .BGRA8UnormSrgb,
		TextureFormat depthFormat = .Depth24PlusStencil8)
	{
		if (device == null)
			return .Err;

		if (mInitialized)
			return .Err;

		using (SProfiler.Begin("Render.Init"))
		{
			mDevice = device;
			mGraphicsQueue = device.GetQueue(.Graphics);
			mColorFormat = colorFormat;
			mDepthFormat = depthFormat;
			mViewportWidth = viewportWidth;
			mViewportHeight = viewportHeight;

			// Initialize frame context
			using (SProfiler.Begin("FrameContext"))
			{
				mRenderFrameContext = new RenderFrameContext();
				if (mRenderFrameContext.Initialize(device) case .Err)
					return .Err;
			}

			// Initialize render graph
			let graphConfig = RenderGraphConfig()
			{
				FrameBufferCount = RenderConfig.FrameBufferCount
			};
			mRenderGraph = new RenderGraph(device, graphConfig);

			// Initialize GPU resource manager
			using (SProfiler.Begin("ResourceManager"))
			{
				mResourceManager = new GPUResourceManager();
				if (mResourceManager.Initialize(device, mGraphicsQueue) case .Err)
					return .Err;
			}

			// Initialize shader system
			if (shaderPaths.Length > 0)
			{
				using (SProfiler.Begin("ShaderSystem"))
				{
					mShaderSystem = new ShaderSystem();
					if (mShaderSystem.Initialize(device, shaderPaths) case .Err)
						return .Err;

					if(shaderCachePath != null)
					{
						mShaderSystem.SetCachePath(shaderCachePath.Value);
					}
				}
			}

			// Initialize material system
			using (SProfiler.Begin("MaterialSystem"))
			{
				mMaterialSystem = new MaterialSystem();
				if (mMaterialSystem.Initialize(device, mGraphicsQueue) case .Err)
					return .Err;
			}

			// Initialize pipeline cache (requires shader system)
			if (mShaderSystem != null)
				mPipelineCache = new RenderPipelineCache(device, mShaderSystem);

			// Initialize lighting system (infrastructure, before features)
			using (SProfiler.Begin("LightingSystem"))
			{
				mLightingSystem = new LightingSystem();
				if (mLightingSystem.Initialize(device, .Default, mShaderSystem) case .Err)
					return .Err;
			}

			// Initialize shadow renderer (infrastructure, before features)
			using (SProfiler.Begin("ShadowRenderer"))
			{
				mShadowRenderer = new ShadowRenderer();
				if (mShadowRenderer.Initialize(device) case .Err)
					return .Err;
			}

			// Initialize shared bind group layouts (after lighting + shadows)
			mSharedLayouts = new SharedBindGroupLayouts(device, this);
			if (mSharedLayouts.Initialize() case .Err)
				return .Err;

			// Initialize skinning system (infrastructure, before features)
			using (SProfiler.Begin("SkinningSystem"))
			{
				mSkinningSystem = new SkinningSystem();
				if (mSkinningSystem.Initialize(this) case .Err)
					Console.WriteLine("[RenderSystem] Warning: Failed to initialize SkinningSystem");
			}

			// Initialize post-process stack
			mPostProcessStack = new PostProcessStack();

			// Initialize auto-exposure
			using (SProfiler.Begin("AutoExposure"))
			{
				mAutoExposure = new AutoExposureEffect(this);
				if (mAutoExposure.Initialize(device) case .Err)
					Console.WriteLine("[RenderSystem] Warning: Failed to initialize AutoExposureEffect");
			}

			// Create transfer batch for init-time uploads.
			// Features registered via RegisterFeature() will use this batch via UploadTexture/UploadBuffer.
			// Auto-flushed on first BeginFrame().
			if (mGraphicsQueue.CreateTransferBatch() case .Ok(let batch))
			{
				mTransferBatch = batch;
				mResourceManager.TransferBatch = batch;
			}

			// Create shared default textures and samplers (before features, so they can reference them)
			mSharedResources = new SharedResources(device);
			if (mSharedResources.Initialize(mTransferBatch) case .Err)
				return .Err;

			// Initialize reflection probe system
			mProbeSystem = new ReflectionProbeSystem();
			if (mProbeSystem.Initialize(device, mTransferBatch) case .Err)
				return .Err;

			// Create init context for feature initialization
			mInitContext = new InitContext();
			mInitContext.Device = device;
			mInitContext.TransferBatch = mTransferBatch;
			mInitContext.Resources = mResourceManager;
			mInitContext.SharedResources = mSharedResources;
			mInitContext.ShaderSystem = mShaderSystem;
			mInitContext.MaterialSystem = mMaterialSystem;
			mInitContext.PipelineCache = mPipelineCache;

			mInitialized = true;
		}
		return .Ok;
	}

	/// Registers a render feature.
	public Result<void> RegisterFeature(IRenderFeature feature)
	{
		if (feature == null)
			return .Err;

		let name = new String(feature.Name);
		if (mFeaturesByName.ContainsKey(name))
		{
			delete name;
			return .Err; // Already registered
		}

		using (SProfiler.Begin(feature.Name))
		{
			if (feature.Initialize(this, mInitContext) case .Err)
			{
				delete name;
				return .Err;
			}
		}

		mFeatures.Add(feature);
		mFeaturesByName[name] = feature;
		mFeaturesSorted = false;

		return .Ok;
	}

	/// Submits all batched init-time GPU transfers and releases the batch.
	/// Call once after all features are registered.
	public void FlushInitTransfers()
	{
		if (mTransferBatch != null)
		{
			using (SProfiler.Begin("Render.FlushInitTransfers"))
			{
				mResourceManager.TransferBatch = null;
				mTransferBatch.Submit();
				mGraphicsQueue.DestroyTransferBatch(ref mTransferBatch);
			}
		}

		// Init phase is over — clear InitContext
		if (mInitContext != null)
		{
			mInitContext.TransferBatch = null;
			delete mInitContext;
			mInitContext = null;
		}
	}

	/// Unregisters a render feature.
	public void UnregisterFeature(IRenderFeature feature)
	{
		if (feature == null)
			return;

		for (let kv in mFeaturesByName)
		{
			if (kv.value == feature)
			{
				let key = kv.key;
				mFeaturesByName.Remove(key);
				delete key;
				break;
			}
		}

		mFeatures.Remove(feature);
		mSortedFeatures.Remove(feature);
		feature.Shutdown();
	}

	/// Gets a feature by name.
	public IRenderFeature GetFeature(StringView name)
	{
		let nameStr = scope String(name);
		if (mFeaturesByName.TryGetValue(nameStr, let feature))
			return feature;
		return null;
	}

	/// Gets a feature by type.
	public T GetFeature<T>() where T : class
	{
		for (let feature in mFeatures)
		{
			if (feature is T)
			{
				let obj = (Object)feature;
				return (T)obj;
			}
		}
		return default;
	}

	/// Sets the active render world.
	public void SetActiveWorld(RenderWorld world)
	{
		mActiveWorld = world;
	}

	/// Creates a new render world.
	public RenderWorld CreateWorld()
	{
		return new RenderWorld(mDevice);
	}

	/// Begins a new frame.
	public void BeginFrame(float totalTime, float deltaTime)
	{
		using (SProfiler.Begin("Render.BeginFrame"))
		{
			if (!mInitialized)
				return;

			// Auto-flush any pending init-time batched transfers on first frame
			if (mTransferBatch != null)
				FlushInitTransfers();

			mFrameNumber++;
			mStats.Reset();

			// Process deferred trail emitter deletions
			mActiveWorld?.ProcessDeferredTrailDeletions();

			// Begin frame on subsystems
			mRenderFrameContext.BeginFrame(mFrameNumber, totalTime, deltaTime);
			mRenderGraph.BeginFrame(mRenderFrameContext.FrameIndex);
		}
	}

	/// Prepares camera for rendering.
	public void SetCamera(
		Vector3 position,
		Vector3 forward,
		Vector3 up,
		float fov,
		float aspectRatio,
		float nearPlane,
		float farPlane,
		uint32 screenWidth,
		uint32 screenHeight)
	{
		mRenderFrameContext.SetCamera(
			position, forward, up,
			fov, aspectRatio, nearPlane, farPlane,
			screenWidth, screenHeight,
			mDevice.FlipProjectionRequired);
	}

	/// Builds the render graph for the current frame.
	public Result<void> BuildRenderGraph(RenderView view)
	{
		using (SProfiler.Begin("Render.BuildGraph"))
		{
			if (!mInitialized || mActiveWorld == null)
				return .Err;

			// Save unjittered VP for next frame's motion vectors BEFORE applying TAA jitter.
			// PrevViewProjectionMatrix must be unjittered so motion vectors correctly capture
			// the jitter offset, enabling TAA to converge at pixel centers.
			mRenderFrameContext.SaveViewProjection();

			// Advance TAA jitter and override VP in scene uniforms.
			// SetCamera() builds VP from raw params without jitter.
			// We override VP here with the jittered VP from RenderView.
			if (mActiveWorld.AAMode == .TAA)
			{
				view.PostProcess.EnableTAA = true;
				view.AdvanceTAAJitter();
				view.UpdateMatrices(mDevice.FlipProjectionRequired);
				// Override VP with jittered version. ProjectionMatrix/InvProjectionMatrix
				// stay unjittered (correct for depth reconstruction).
				mRenderFrameContext.SceneUniforms.ViewProjectionMatrix = view.ViewProjectionMatrix;
			}
			else
			{
				view.PostProcess.EnableTAA = false;
				view.TAAJitter.Reset();
			}

			// Sort features by dependencies if needed
			if (!mFeaturesSorted)
			{
				SortFeatures();
				mFeaturesSorted = true;
			}

			// Populate ViewContext from the (possibly jitter-updated) RenderView
			mViewContext.Update(view);
			mViewContext.FrameIndex = mRenderFrameContext.FrameIndex;
			mViewContext.ActiveViewIndex = mRenderFrameContext.ActiveViewIndex;
			mViewContext.ViewCount = mRenderFrameContext.ViewCount;
			mViewContext.SceneUniformBuffer = mRenderFrameContext.SceneUniformBuffer;
			mViewContext.PrevViewProjectionMatrix = mRenderFrameContext.SceneUniforms.PrevViewProjectionMatrix;
			mViewContext.Exposure = mActiveWorld != null ? mActiveWorld.Exposure : 1.0f;
			mViewContext.DeltaTime = mRenderFrameContext.DeltaTime;
			mViewContext.TotalTime = mRenderFrameContext.TotalTime;

			// PrepareFrame: per-frame feature lifecycle (deferred deletions, resource registration)
			using (SProfiler.Begin("Features.PrepareFrame"))
			{
				RenderView[1] views = .(view);
				for (let feature in mSortedFeatures)
					feature.PrepareFrame(views, mActiveWorld, mRenderFrameContext.FrameIndex);
			}

			// Resolve visibility and build draw batches (shared across all features)
			if (mRenderFrameContext.ViewCount <= 1)
			{
				using (SProfiler.Begin("Visibility.Resolve"))
				{
					mVisibility.SetLODBias(mActiveWorld.LODBias);
					mCuller.SetFrustum(mViewContext.ViewProjectionMatrix);
					mVisibility.Clear();
					mVisibility.Resolve(mActiveWorld, mViewContext.ViewProjectionMatrix, mViewContext.CameraPosition);
				}

				using (SProfiler.Begin("Batcher.Build"))
				{
					mBatcher.Clear();
					mBatcher.Build(mActiveWorld, mVisibility);
				}
			}

			// Reset post-process output
			mPostProcessOutput = .Invalid;

			// Add skinning compute pass (infrastructure, before features)
			if (mSkinningSystem != null && mSkinningSystem.IsInitialized)
				mSkinningSystem.AddPasses(mRenderGraph, mViewContext, mActiveWorld);

			// Let each feature add its passes (except FinalOutput which we handle specially)
			using (SProfiler.Begin("Features.AddPasses"))
			{
				for (let feature in mSortedFeatures)
				{
					// Skip FinalOutput - we'll add it after post-processing
					if (feature.Name == "FinalOutput")
						continue;

					using (SProfiler.Begin(feature.Name))
						feature.AddPasses(mRenderGraph, mViewContext, mActiveWorld);
				}
			}

			// Add auto-exposure compute passes if enabled
			if (mAutoExposure != null && mActiveWorld.ExposureMode == .Auto)
			{
				using (SProfiler.Begin("AutoExposure.AddPasses"))
				{
					// Read back previous frame's result first (1 frame latency)
					mAutoExposure.ReadbackExposure(mActiveWorld);
					// Add compute passes for this frame
					mAutoExposure.AddPasses(mRenderGraph, mViewContext, mActiveWorld);
				}
			}

			// Add post-processing passes if any effects are enabled
			if (mPostProcessStack != null && mPostProcessStack.HasEnabledEffects)
			{
				using (SProfiler.Begin("PostProcess.AddPasses"))
				{
					let sceneColorHandle = mRenderGraph.GetResource("SceneColor");
					let depthHandle = mRenderGraph.GetResource("SceneDepth");

					if (sceneColorHandle.IsValid && depthHandle.IsValid)
					{
						mPostProcessOutput = mPostProcessStack.AddPasses(
							mRenderGraph, mViewContext, sceneColorHandle, depthHandle);
					}
				}
			}

			// Now add FinalOutput pass
			let finalOutputFeature = GetFeature("FinalOutput");
			if (finalOutputFeature != null)
			{
				finalOutputFeature.AddPasses(mRenderGraph, mViewContext, mActiveWorld);
			}

			// Compile the graph
			using (SProfiler.Begin("Graph.Compile"))
				return mRenderGraph.Compile();
		}
	}

	/// Executes the render graph.
	public Result<void> Execute(ICommandEncoder commandEncoder)
	{
		using (SProfiler.Begin("Render.Execute"))
		{
			if (!mInitialized)
				return .Err;

			// Upload scene uniforms (VP is already jittered if TAA is active)
			using (SProfiler.Begin("UploadUniforms"))
			{
				mRenderFrameContext.UploadSceneUniforms();
			}

			// Execute the render graph
			using (SProfiler.Begin("Graph.Execute"))
			{
				let result = mRenderGraph.Execute(commandEncoder);

				// Queue auto-exposure readback after graph execution
				if (mAutoExposure != null && mActiveWorld != null && mActiveWorld.ExposureMode == .Auto)
					mAutoExposure.QueueReadback(commandEncoder);

				return result;
			}
		}
	}

	/// Renders multiple views in a single frame (split-screen).
	/// Call between BeginFrame() and EndFrame().
	/// Replaces the SetCamera → BuildRenderGraph → Execute sequence for multi-view.
	public Result<void> RenderViews(Span<RenderView> views, ICommandEncoder encoder)
	{
		using (SProfiler.Begin("Render.RenderViews"))
		{
			if (!mInitialized || mActiveWorld == null || views.Length == 0)
				return .Err;

			mRenderFrameContext.SetViewCount((int32)views.Length);

			// Sort features if needed
			if (!mFeaturesSorted) { SortFeatures(); mFeaturesSorted = true; }

			let frameIndex = mRenderFrameContext.FrameIndex;

			// Populate ViewContext from main view for PrepareFrame
			mViewContext.Update(views[0]);
			mViewContext.FrameIndex = frameIndex;
			mViewContext.ActiveViewIndex = 0;
			mViewContext.ViewCount = (int32)views.Length;
			mViewContext.SceneUniformBuffer = mRenderFrameContext.SceneUniformBuffer;
			mViewContext.PrevViewProjectionMatrix = mRenderFrameContext.SceneUniforms.PrevViewProjectionMatrix;
			mViewContext.Exposure = mActiveWorld != null ? mActiveWorld.Exposure : 1.0f;
			mViewContext.DeltaTime = mRenderFrameContext.DeltaTime;
			mViewContext.TotalTime = mRenderFrameContext.TotalTime;

			// Resolve union visibility across all views (shared)
			using (SProfiler.Begin("Visibility.Resolve"))
			{
				mVisibility.SetLODBias(mActiveWorld.LODBias);
				mVisibility.Clear();
				for (let v in views)
				{
					mCuller.SetFrustum(v.ViewProjectionMatrix);
					mVisibility.ResolveAccumulate(mActiveWorld, v.ViewProjectionMatrix, v.CameraPosition);
				}
			}

			using (SProfiler.Begin("Batcher.Build"))
			{
				mBatcher.Clear();
				mBatcher.Build(mActiveWorld, mVisibility);
			}

			// Phase 1: PrepareFrame (shared data, once)
			using (SProfiler.Begin("Features.PrepareFrame"))
			{
				for (let feature in mSortedFeatures)
					feature.PrepareFrame(views, mActiveWorld, frameIndex);
			}

			// Phase 2: Per-view rendering
			for (int32 i = 0; i < (int32)views.Length; i++)
			{
				let view = views[i];
				mRenderFrameContext.SetActiveView(i);

				using (SProfiler.Begin("View.SetCamera"))
				{
					SetCamera(view.CameraPosition, view.CameraForward, view.CameraUp,
						view.FieldOfView, view.AspectRatio, view.NearPlane, view.FarPlane,
						view.Width, view.Height);

					// Save unjittered VP before applying TAA jitter (same fix as single-view path)
					mRenderFrameContext.SaveViewProjection();

					// TAA jitter override (same as in BuildRenderGraph single-view path)
					if (mActiveWorld.AAMode == .TAA)
					{
						view.PostProcess.EnableTAA = true;
						view.AdvanceTAAJitter();
						view.UpdateMatrices(mDevice.FlipProjectionRequired);
						mRenderFrameContext.SceneUniforms.ViewProjectionMatrix = view.ViewProjectionMatrix;
					}
					else
					{
						view.PostProcess.EnableTAA = false;
						view.TAAJitter.Reset();
					}
				}

				using (SProfiler.Begin("View.BuildGraph"))
				{
					if (BuildRenderGraph(view) case .Err)
						continue;
				}

				using (SProfiler.Begin("View.Execute"))
				{
					mRenderFrameContext.UploadSceneUniforms();
					mRenderGraph.Execute(encoder);
				}

				// Reset graph for next view (if not the last)
				if (i < (int32)views.Length - 1)
					mRenderGraph.Reset();
			}

			// Reset active view for EndFrame
			mRenderFrameContext.SetActiveView(0);
			return .Ok;
		}
	}

	/// Ends the current frame.
	public void EndFrame()
	{
		using (SProfiler.Begin("Render.EndFrame"))
		{
			if (!mInitialized)
				return;

			mRenderFrameContext.EndFrame();
			mRenderGraph.EndFrame();

			// Process deferred resource deletions
			mResourceManager.ProcessDeletions(mFrameNumber);
		}
	}

	/// Shuts down the render system.
	public void Shutdown()
	{
		if (!mInitialized)
			return;

		// Wait for GPU to finish
		mDevice.WaitIdle();

		// Flush any pending init-time transfers
		if (mTransferBatch != null)
			FlushInitTransfers();

		// Shutdown auto-exposure
		if (mAutoExposure != null)
			mAutoExposure.Shutdown();

		// Shutdown post-process effects (before features since effects may reference features)
		if (mPostProcessStack != null)
			mPostProcessStack.Shutdown();

		// Shutdown and delete features in reverse order
		for (int i = mFeatures.Count - 1; i >= 0; i--)
		{
			let feature = mFeatures[i];
			feature.Shutdown();
			delete feature;
		}
		mFeatures.Clear();
		mSortedFeatures.Clear();

		// Dispose resources before deletion
		if (mRenderFrameContext != null)
			mRenderFrameContext.Dispose();

		if (mRenderGraph != null)
		{
			delete mRenderGraph;
			mRenderGraph = null;
		}

		if (mResourceManager != null)
			mResourceManager.Dispose();

		if (mSkinningSystem != null)
			mSkinningSystem.Shutdown();

		if (mMaterialSystem != null)
			mMaterialSystem.Dispose();

		if (mPipelineCache != null)
			mPipelineCache.Clear();

		if (mShaderSystem != null)
			mShaderSystem.Dispose();

		mInitialized = false;
		mDevice = null;
	}

	/// Sorts features by dependencies using topological sort.
	private void SortFeatures()
	{
		mSortedFeatures.Clear();

		// Build dependency graph
		Dictionary<StringView, List<StringView>> dependsOn = scope .();
		Dictionary<StringView, int32> inDegree = scope .();

		for (let feature in mFeatures)
		{
			let name = feature.Name;
			inDegree[name] = 0;
			dependsOn[name] = scope:: .();
		}

		// Collect dependencies (only count deps on registered features)
		List<StringView> deps = scope .();
		for (let feature in mFeatures)
		{
			deps.Clear();
			feature.GetDependencies(deps);

			for (let dep in deps)
			{
				// Skip dependencies on features that aren't registered
				if (!inDegree.ContainsKey(dep))
					continue;

				if (dependsOn.TryGetValue(feature.Name, let list))
				{
					list.Add(dep);
					if (inDegree.ContainsKey(feature.Name))
						inDegree[feature.Name]++;
				}
			}
		}

		// Kahn's algorithm
		List<IRenderFeature> queue = scope .();

		for (let feature in mFeatures)
		{
			if (inDegree.TryGetValue(feature.Name, let degree) && degree == 0)
				queue.Add(feature);
		}

		while (queue.Count > 0)
		{
			let feature = queue.PopFront();
			mSortedFeatures.Add(feature);

			// Decrease in-degree for dependents
			for (let other in mFeatures)
			{
				if (dependsOn.TryGetValue(other.Name, let deps2))
				{
					for (let dep in deps2)
					{
						if (dep == feature.Name)
						{
							if (inDegree.ContainsKey(other.Name))
							{
								inDegree[other.Name]--;
								if (inDegree[other.Name] == 0)
									queue.Add(other);
							}
							break;
						}
					}
				}
			}
		}

		// If not all features were added, there's a cycle - add remaining
		if (mSortedFeatures.Count < mFeatures.Count)
		{
			for (let feature in mFeatures)
			{
				if (!mSortedFeatures.Contains(feature))
					mSortedFeatures.Add(feature);
			}
		}
	}

	public void Dispose()
	{
		Shutdown();
	}
}

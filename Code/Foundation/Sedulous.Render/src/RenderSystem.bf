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
	private bool mInitialized = false;
	private uint64 mFrameNumber = 0;

	// Core systems
	private RenderFrameContext mRenderFrameContext ~ delete _;
	private RenderGraph mRenderGraph ~ delete _;
	private TransientResourcePool mTransientPool ~ delete _;
	private GPUResourceManager mResourceManager ~ delete _;
	private ShaderSystem mShaderSystem ~ delete _;
	private MaterialSystem mMaterialSystem ~ delete _;
	private RenderPipelineCache mPipelineCache ~ delete _;

	// Render features
	private List<IRenderFeature> mFeatures = new .() ~ delete _;
	private Dictionary<String, IRenderFeature> mFeaturesByName = new .() ~ DeleteDictionaryAndKeys!(_);
	private List<IRenderFeature> mSortedFeatures = new .() ~ delete _;
	private bool mFeaturesSorted = false;

	// Render world (scene data)
	private RenderWorld mActiveWorld;

	// Post-processing stack
	private PostProcessStack mPostProcessStack ~ delete _;
	private RGResourceHandle mPostProcessOutput;

	// Auto-exposure (standalone, not part of PostProcessStack)
	private AutoExposureEffect mAutoExposure ~ delete _;

	// Statistics
	private RenderStats mStats;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;

	/// Gets whether the renderer is initialized.
	public bool IsInitialized => mInitialized;

	/// Gets the graphics device.
	public IDevice Device => mDevice;

	/// Gets the frame context.
	public RenderFrameContext RenderFrameContext => mRenderFrameContext;

	/// Gets the render graph.
	public RenderGraph RenderGraph => mRenderGraph;

	/// Gets the transient resource pool.
	public TransientResourcePool TransientPool => mTransientPool;

	/// Gets the GPU resource manager.
	public GPUResourceManager ResourceManager => mResourceManager;

	/// Gets the shader system.
	public ShaderSystem ShaderSystem => mShaderSystem;

	/// Gets the material system.
	public MaterialSystem MaterialSystem => mMaterialSystem;

	/// Gets the pipeline cache for dynamic pipeline creation.
	public RenderPipelineCache PipelineCache => mPipelineCache;

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
	public RGResourceHandle PostProcessOutput => mPostProcessOutput;

	/// Initializes the render system.
	public Result<void> Initialize(
		IDevice device,
		Span<StringView> shaderPaths = default,
		StringView? shaderCachePath = null,
		TextureFormat colorFormat = .BGRA8UnormSrgb,
		TextureFormat depthFormat = .Depth24PlusStencil8)
	{
		if (device == null)
			return .Err;

		if (mInitialized)
			return .Err;

		mDevice = device;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		// Initialize frame context
		mRenderFrameContext = new RenderFrameContext();
		if (mRenderFrameContext.Initialize(device) case .Err)
			return .Err;

		// Initialize render graph
		let graphConfig = RenderGraphConfig()
		{
			FrameBufferCount = RenderConfig.FrameBufferCount,
			TransientBufferPoolSize = RenderConfig.TransientBufferPoolSize
		};
		mRenderGraph = new RenderGraph(device, graphConfig);

		// Initialize transient resource pool
		mTransientPool = new TransientResourcePool();
		if (mTransientPool.Initialize(device, graphConfig) case .Err)
			return .Err;

		// Initialize GPU resource manager
		mResourceManager = new GPUResourceManager();
		if (mResourceManager.Initialize(device) case .Err)
			return .Err;

		// Initialize shader system
		if (shaderPaths.Length > 0)
		{
			mShaderSystem = new ShaderSystem();
			if (mShaderSystem.Initialize(device, shaderPaths) case .Err)
				return .Err;

			if(shaderCachePath != null)
			{
				mShaderSystem.SetCachePath(shaderCachePath.Value);
			}
		}

		// Initialize material system
		mMaterialSystem = new MaterialSystem();
		if (mMaterialSystem.Initialize(device) case .Err)
			return .Err;

		// Initialize pipeline cache (requires shader system)
		if (mShaderSystem != null)
			mPipelineCache = new RenderPipelineCache(device, mShaderSystem);

		// Initialize post-process stack
		mPostProcessStack = new PostProcessStack();

		// Initialize auto-exposure
		mAutoExposure = new AutoExposureEffect(this);
		if (mAutoExposure.Initialize(device) case .Err)
			Console.WriteLine("[RenderSystem] Warning: Failed to initialize AutoExposureEffect");

		mInitialized = true;
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

		if (feature.Initialize(this) case .Err)
		{
			delete name;
			return .Err;
		}

		mFeatures.Add(feature);
		mFeaturesByName[name] = feature;
		mFeaturesSorted = false;

		return .Ok;
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
		return new RenderWorld();
	}

	/// Begins a new frame.
	public void BeginFrame(float totalTime, float deltaTime)
	{
		using (SProfiler.Begin("Render.BeginFrame"))
		{
			if (!mInitialized)
				return;

			mFrameNumber++;
			mStats.Reset();

			// Process deferred GPU resource deletions
			mActiveWorld?.ProcessDeferredDeletions();

			// Begin frame on subsystems
			mRenderFrameContext.BeginFrame(mFrameNumber, totalTime, deltaTime);
			mRenderGraph.BeginFrame(mRenderFrameContext.FrameIndex);
			mTransientPool.BeginFrame(mRenderFrameContext.FrameIndex);
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

			// Reset post-process output
			mPostProcessOutput = .Invalid;

			// Let each feature add its passes (except FinalOutput which we handle specially)
			using (SProfiler.Begin("Features.AddPasses"))
			{
				for (let feature in mSortedFeatures)
				{
					// Skip FinalOutput - we'll add it after post-processing
					if (feature.Name == "FinalOutput")
						continue;

					feature.AddPasses(mRenderGraph, view, mActiveWorld);
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
					mAutoExposure.AddPasses(mRenderGraph, view, mActiveWorld);
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
							mRenderGraph, view, sceneColorHandle, depthHandle);
					}
				}
			}

			// Now add FinalOutput pass
			let finalOutputFeature = GetFeature("FinalOutput");
			if (finalOutputFeature != null)
			{
				finalOutputFeature.AddPasses(mRenderGraph, view, mActiveWorld);
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

			// Upload scene uniforms
			using (SProfiler.Begin("UploadUniforms"))
			{
				mRenderFrameContext.UploadSceneUniforms();
				mRenderFrameContext.SaveViewProjection();
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
					mRenderFrameContext.SaveViewProjection();
					mRenderGraph.Execute(encoder);
				}

				// Reset graph for next view (if not the last)
				if (i < (int32)views.Length - 1)
					mRenderGraph.ResetForNextView();
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
			mTransientPool.EndFrame();

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
		if (mRenderGraph != null)
			mRenderGraph.Dispose();

		if (mTransientPool != null)
			mTransientPool.Dispose();

		if (mResourceManager != null)
			mResourceManager.Dispose();

		if (mMaterialSystem != null)
			mMaterialSystem.Dispose();

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

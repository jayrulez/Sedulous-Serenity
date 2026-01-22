namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Materials;
using Sedulous.Mathematics;
using Sedulous.Profiler;

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
	private NewShaderSystem mShaderSystem ~ delete _;
	private MaterialSystem mMaterialSystem ~ delete _;

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
	public NewShaderSystem ShaderSystem => mShaderSystem;

	/// Gets the material system.
	public MaterialSystem MaterialSystem => mMaterialSystem;

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

	/// Gets the post-process output handle for the current frame.
	/// Returns the final output from post-processing, or invalid handle if no effects are enabled.
	public RGResourceHandle PostProcessOutput => mPostProcessOutput;

	/// Initializes the render system.
	public Result<void> Initialize(
		IDevice device,
		StringView shaderPath = default,
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
		mRenderGraph = new RenderGraph(device);

		// Initialize transient resource pool
		mTransientPool = new TransientResourcePool();
		if (mTransientPool.Initialize(device) case .Err)
			return .Err;

		// Initialize GPU resource manager
		mResourceManager = new GPUResourceManager();
		if (mResourceManager.Initialize(device) case .Err)
			return .Err;

		// Initialize shader system
		if (!shaderPath.IsEmpty)
		{
			mShaderSystem = new NewShaderSystem();
			if (mShaderSystem.Initialize(device, shaderPath) case .Err)
				return .Err;
		}

		// Initialize material system
		mMaterialSystem = new MaterialSystem();
		if (mMaterialSystem.Initialize(device) case .Err)
			return .Err;

		// Initialize post-process stack
		mPostProcessStack = new PostProcessStack();

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

			// Begin frame on subsystems
			mRenderFrameContext.BeginFrame(mFrameNumber, totalTime, deltaTime);
			mRenderGraph.BeginFrame();
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
				mRenderFrameContext.UploadSceneUniforms();

			// Execute the render graph
			using (SProfiler.Begin("Graph.Execute"))
				return mRenderGraph.Execute(commandEncoder);
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

		// Collect dependencies
		List<StringView> deps = scope .();
		for (let feature in mFeatures)
		{
			deps.Clear();
			feature.GetDependencies(deps);

			for (let dep in deps)
			{
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

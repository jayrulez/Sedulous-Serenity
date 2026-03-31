using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Profiler;
using Sedulous.Shaders;
using Sedulous.Materials;

namespace Sedulous.Renderer;

/// Main renderer orchestrator.
/// Owns all subsystems and shared resources.
/// Features register with this system and add passes to the render graph.
public class RenderSystem
{
	private IDevice mDevice;
	private IQueue mGraphicsQueue;
	private SharedResources mSharedResources ~ delete _;
	private RenderFrameContext mRenderFrameContext ~ delete _;
	private Sedulous.RenderGraph.RenderGraph mRenderGraph ~ delete _;
	private SkinningSystem mSkinningSystem ~ delete _;
	private LightingSystem mLightingSystem ~ { _?.Dispose(); delete _; };
	private GPUResourceManager mResourceManager ~ { _?.Dispose(); delete _; };
	private ShaderSystem mShaderSystem ~ { _?.Dispose(); delete _; };
	private MaterialSystem mMaterialSystem ~ { _?.Dispose(); delete _; };
	private RenderPipelineCache mPipelineCache ~ delete _;
	private SharedBindGroupLayouts mSharedLayouts ~ delete _;
	private List<IRenderFeature> mFeatures = new .() ~ { for (let f in _) delete f; delete _; };
	private ViewContext mViewContext = new .() ~ delete _;
	private VisibilityResolver mVisibility = new .() ~ delete _;
	private DrawBatcher mBatcher = new .() ~ delete _;
	private RenderWorld mActiveWorld;
	private RenderStats mStats;
	private IFence mInitFence;
	private bool mInitialized;
	private int32 mFrameIndex;
	private TextureFormat mDepthFormat = .Depth32Float;

	/// The GPU device
	public IDevice Device => mDevice;

	/// The graphics queue
	public IQueue GraphicsQueue => mGraphicsQueue;

	/// Shared default textures and samplers
	public SharedResources SharedResources => mSharedResources;

	/// Per-frame context (uniform buffers, etc.)
	public RenderFrameContext RenderFrameContext => mRenderFrameContext;

	/// The render graph
	public Sedulous.RenderGraph.RenderGraph RenderGraph => mRenderGraph;

	/// The skinning subsystem
	public SkinningSystem SkinningSystem => mSkinningSystem;

	/// Lighting system (light buffer, cluster grid, culling)
	public LightingSystem LightingSystem => mLightingSystem;

	/// GPU resource manager (meshes, textures, bone buffers)
	public GPUResourceManager ResourceManager => mResourceManager;

	/// Shader system (compilation, caching)
	public ShaderSystem ShaderSystem => mShaderSystem;

	/// Material system (layouts, instances, bind groups)
	public MaterialSystem MaterialSystem => mMaterialSystem;

	/// Pipeline cache (lazily creates pipelines per material variant)
	public RenderPipelineCache PipelineCache => mPipelineCache;

	/// Current frame index
	public int32 FrameIndex => mFrameIndex;

	/// Depth buffer format used by the renderer
	public TextureFormat DepthFormat => mDepthFormat;

	/// Shared bind group layouts and per-frame bind groups
	public SharedBindGroupLayouts SharedLayouts => mSharedLayouts;

	/// Per-view context (camera, dimensions, uniforms snapshot)
	public ViewContext ViewContext => mViewContext;

	/// The active render world
	public RenderWorld ActiveWorld => mActiveWorld;

	/// Shared visibility resolver (results available to all features)
	public VisibilityResolver Visibility => mVisibility;

	/// Shared draw batcher (results available to all features)
	public DrawBatcher Batcher => mBatcher;

	/// Per-frame rendering statistics
	public ref RenderStats Stats => ref mStats;

	/// Set the active world for rendering.
	public void SetActiveWorld(RenderWorld world)
	{
		mActiveWorld = world;
	}

	public this()
	{
	}

	/// Initialize the render system.
	/// shaderPaths: paths to shader source directories
	/// shaderCachePath: optional path for compiled shader disk cache
	/// depthFormat: depth buffer format (default Depth32Float)
	public Result<void> Initialize(
		IDevice device,
		Span<StringView> shaderPaths = default,
		StringView? shaderCachePath = null,
		TextureFormat depthFormat = .Depth32Float)
	{
		using (SProfiler.Begin("Renderer.Init"))
		{
			mDevice = device;
			mGraphicsQueue = device.GetQueue(.Graphics);
			mDepthFormat = depthFormat;

			// Create init fence for async transfer
			if (device.CreateFence(0) case .Ok(let fence))
				mInitFence = fence;
			else
				return .Err;

			// Create transfer batch for all init uploads
			let batchResult = mGraphicsQueue.CreateTransferBatch();
			if (batchResult case .Err)
				return .Err;
			var transferBatch = batchResult.Value;
			defer { mGraphicsQueue.DestroyTransferBatch(ref transferBatch); }

			// 1. Shared resources (default textures, samplers)
			mSharedResources = new SharedResources(device);
			Try!(mSharedResources.Initialize(transferBatch));

			// 2. Frame context (per-frame uniform buffers)
			mRenderFrameContext = new RenderFrameContext(device);
			Try!(mRenderFrameContext.Initialize());

			// 3. Render graph
			mRenderGraph = new Sedulous.RenderGraph.RenderGraph(device, RenderGraphConfig()
			{
				FrameBufferCount = RenderConfig.FrameBufferCount
			});

			// 4. Shared bind group layouts
			mSharedLayouts = new SharedBindGroupLayouts(device);
			Try!(mSharedLayouts.Initialize());

			// 5. GPU resource manager
			mResourceManager = new GPUResourceManager();
			mResourceManager.TransferBatch = transferBatch;
			Try!(mResourceManager.Initialize(device, mGraphicsQueue));

			// 5. Shader system
			if (shaderPaths.Length > 0)
			{
				using (SProfiler.Begin("Renderer.ShaderSystem"))
				{
					mShaderSystem = new ShaderSystem();
					if (mShaderSystem.Initialize(device, shaderPaths) case .Err)
						return .Err;

					if (shaderCachePath != null)
						mShaderSystem.SetCachePath(shaderCachePath.Value);
				}
			}

			// 6. Material system
			mMaterialSystem = new MaterialSystem();
			Try!(mMaterialSystem.Initialize(device, mGraphicsQueue));

			// 7. Pipeline cache (requires shader system)
			if (mShaderSystem != null)
				mPipelineCache = new RenderPipelineCache(device, mShaderSystem);

			// 8. Lighting system
			mLightingSystem = new LightingSystem();
			Try!(mLightingSystem.Initialize(device, .Default, mShaderSystem));

			// 7. Skinning system
			mSkinningSystem = new SkinningSystem(device);
			Try!(mSkinningSystem.Initialize(this));

			// 7. Initialize registered features
			using (SProfiler.Begin("Renderer.Features"))
			{
				for (let feature in mFeatures)
				{
					if (feature.Initialize(this) case .Err)
						return .Err;
				}
			}

			// 8. Submit all init uploads as a single async batch
			using (SProfiler.Begin("Renderer.TransferSubmit"))
			{
				transferBatch.Submit();
			}

			// Clear transfer batch reference — runtime uploads use sync path
			mResourceManager.TransferBatch = null;

			mInitialized = true;
		}

		return .Ok;
	}

	/// Register a render feature. Call before Initialize().
	public void RegisterFeature(IRenderFeature feature)
	{
		mFeatures.Add(feature);
	}

	/// Get a registered feature by type
	public T GetFeature<T>() where T : IRenderFeature, class
	{
		for (let feature in mFeatures)
		{
			if (feature.GetType() == typeof(T))
				return (T)feature;
		}
		return default;
	}

	/// Begin a new frame.
	/// frameIndex: multi-buffering slot index
	/// totalTime: seconds since application start
	/// deltaTime: seconds since last frame
	public void BeginFrame(int32 frameIndex, float totalTime = 0, float deltaTime = 0)
	{
		using (SProfiler.Begin("Renderer.BeginFrame"))
		{
			mFrameIndex = frameIndex;
			mStats.Reset();

			mRenderFrameContext.TotalTime = totalTime;
			mRenderFrameContext.DeltaTime = deltaTime;
			mRenderFrameContext.FrameNumber = (uint32)frameIndex;

			mRenderGraph.BeginFrame(frameIndex);

			// Process deferred resource deletions
			mResourceManager?.ProcessDeletions((uint64)frameIndex);
		}
	}

	/// Prepare the view for rendering.
	/// Populates ViewContext from the RenderView, uploads scene uniforms,
	/// and rebuilds shared bind groups for this frame+view.
	public void PrepareView(RenderView view, RenderWorld world = null, int32 viewIndex = 0)
	{
		using (SProfiler.Begin("Renderer.PrepareView"))
		{
			mRenderFrameContext.SetSlot(mFrameIndex, viewIndex);

			// Populate view context from the render view
			mViewContext.Update(view);

			// Resolve visibility (shared across all features)
			if (world != null)
			{
				using (SProfiler.Begin("Renderer.Visibility"))
				{
					mVisibility.SetLODBias(world.LODBias);
					mVisibility.Resolve(world, mViewContext);
				}

				using (SProfiler.Begin("Renderer.Batcher"))
				{
					mBatcher.Clear();
					mBatcher.Build(world, mVisibility);
				}
			}

			// Update lighting with visibility results
			if (world != null && mLightingSystem != null)
			{
				using (SProfiler.Begin("Renderer.UpdateLighting"))
				{
					let fi = mFrameIndex % RenderConfig.FrameBufferCount;

					mLightingSystem.LightBuffer.DebugMode = 1; // DEBUG: flat albedo (set BEFORE upload)
					// Full update: light buffer + cluster grid + CPU culling
					mLightingSystem.Update(world, mVisibility, mViewContext, fi, viewIndex);

					}
			}

			// Upload scene uniforms for this view
			mRenderFrameContext.UploadUniforms(mViewContext, world);

			// Create shared bind groups if not yet created for this frame+view slot
			if (mSharedLayouts.GetDepthPassBindGroup(mFrameIndex, viewIndex) == null)
				mSharedLayouts.RebuildDepthPassBindGroups(mFrameIndex, mRenderFrameContext.CurrentSceneBuffer, viewIndex);

			// Rebuild scene bind group (forward pass) — needs lighting buffers to be uploaded
			if (mLightingSystem != null)
			{
				mSharedLayouts.RebuildSceneBindGroups(mFrameIndex, mRenderFrameContext.CurrentSceneBuffer,
					mSharedLayouts.GetObjectUniformBuffer(mFrameIndex),
					mLightingSystem, mSharedResources, viewIndex);
			}

			// Set render graph output size to match the view
			mRenderGraph.SetOutputSize(view.Width, view.Height);
		}
	}

	/// Build the render graph for the current frame.
	/// Must call PrepareView() first to populate ViewContext.
	public void BuildGraph()
	{
		using (SProfiler.Begin("Renderer.BuildGraph"))
		{
			// Infrastructure adds passes first
			if (mActiveWorld != null)
				mSkinningSystem.AddPasses(mRenderGraph, mActiveWorld);
			else
				mSkinningSystem.AddPasses(mRenderGraph);

			// Features add passes with frame + view context
			for (let feature in mFeatures)
			{
				feature.AddPasses(mRenderGraph, mRenderFrameContext, mViewContext);
			}
		}
	}

	/// Compile and execute the render graph
	public Result<void> Execute(ICommandEncoder encoder)
	{
		using (SProfiler.Begin("Renderer.Execute"))
		{
			return mRenderGraph.Execute(encoder);
		}
	}

	/// End the current frame
	public void EndFrame()
	{
		using (SProfiler.Begin("Renderer.EndFrame"))
		{
			mRenderGraph.EndFrame();
		}
	}

	/// Set the output dimensions (for render graph SizeMode resolution)
	public void SetOutputSize(uint32 width, uint32 height)
	{
		mRenderGraph.SetOutputSize(width, height);
	}

	/// Shut down the render system
	public void Shutdown()
	{
		if (!mInitialized)
			return;

		mDevice.WaitIdle();

		// Shutdown features in reverse order
		for (int i = mFeatures.Count - 1; i >= 0; i--)
			mFeatures[i].Shutdown();

		mSkinningSystem?.Shutdown();
		mPipelineCache?.Clear();
		mLightingSystem?.Dispose();
		mMaterialSystem?.Dispose();
		mSharedLayouts?.Shutdown();
		mRenderFrameContext?.Shutdown();

		if (mInitFence != null)
			mDevice.DestroyFence(ref mInitFence);

		mInitialized = false;
	}

	public ~this()
	{
		Shutdown();
	}
}

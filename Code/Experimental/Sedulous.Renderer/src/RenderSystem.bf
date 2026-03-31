namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// Frame lifecycle orchestrator — the main entry point for the renderer.
class RenderSystem
{
	private IDevice mDevice;
	private IQueue mGraphicsQueue;
	private IQueue mComputeQueue;
	private DeferredDeletionQueue mDeferredDeletions;

	// Fallback IBL textures (used when SkyFeature is not registered)
	private ITexture mFallbackCubemap;
	private ITextureView mFallbackCubemapView;
	private ITexture mFallbackBrdfLut;
	private ITextureView mFallbackBrdfLutView;
	private bool mFallbackIBLTransitioned;

	private RenderGraph mGraph ~ { if (_ != null) { _.Destroy(); delete _; } };
	private ICommandPool[RenderConfig.FrameBufferCount] mCommandPools;
	private IFence mFrameFence;
	private uint64 mFrameFenceValue;
	private int mFrameIndex;
	private IFence mInitFence;
	private bool mInitWaited;

	private List<IRenderFeature> mFeatures = new .() ~ delete _;
	private GPUResourceManager mResources = new .() ~ delete _;
	private ShaderLibrary mShaderLibrary = new .() ~ delete _;
	private RenderPipelineCache mPipelineCache = new .() ~ delete _;
	private RenderWorld mActiveWorld;
	private FrameContext mFrameContext = new .() ~ delete _;
	private ViewContext mViewContext = new .() ~ delete _;
	private RenderView mDefaultView = new .() ~ delete _;
	private RenderStats mStats;

	// Phase 4-5: visibility, batching, per-object uniforms
	private VisibilityResolver mVisibility = new .() ~ delete _;
	private DrawBatcher mBatcher = new .() ~ delete _;
	private ObjectUniformManager mObjectUniforms = new .() ~ delete _;

	// Phase 6: lighting
	private LightingSystem mLightingSystem = new .() ~ delete _;

	// Phase 7: shadows
	private ShadowSystem mShadowSystem = new .() ~ delete _;

	// Phase 11: GPU skinning
	private SkinningSystem mSkinningSystem = new .() ~ delete _;

	// Reflection probes
	private ReflectionProbeSystem mReflectionProbeSystem = new .() ~ delete _;

	// Phase 17: GPU-driven rendering
	private GPUSceneBuffer mGPUSceneBuffer = new .() ~ delete _;
	private IndirectDrawSystem mIndirectDrawSystem = new .() ~ delete _;
	private HiZPyramid mHiZPyramid = new .() ~ delete _;

	// Shared bind group layouts and per-frame-per-view bind groups
	private IBindGroupLayout mSceneBindGroupLayout;
	private IBindGroupLayout mObjectBindGroupLayout;         // CPU path: dynamic offset UBO
	private IBindGroupLayout mGPUDrivenObjectLayout;         // GPU-driven path: storage buffer
	private IBindGroup[RenderConfig.TotalBufferSlots] mSceneBindGroups;
	private IBindGroup[RenderConfig.TotalBufferSlots] mObjectBindGroups;
	private IBindGroup[RenderConfig.FrameBufferCount] mGPUDrivenObjectBindGroups;
	private IBuffer mIdentityInstanceBuffer;                 // [0,1,2,...,N-1] for GPU-driven instance fetch
	private int mViewIndex;

	// Material instance storage
	private List<MaterialInstance> mMaterialInstances = new .() ~ DeleteContainerAndItems!(_);
	private List<int32> mFreeMaterialSlots = new .() ~ delete _;

	public IDevice Device => mDevice;
	public GPUResourceManager Resources => mResources;
	public ShaderLibrary Shaders => mShaderLibrary;
	public DeferredDeletionQueue DeferredDeletions => mDeferredDeletions;
	public RenderPipelineCache Pipelines => mPipelineCache;
	public RenderWorld ActiveWorld => mActiveWorld;
	public FrameContext FrameCtx => mFrameContext;
	public ViewContext ViewCtx => mViewContext;
	public ref RenderStats Stats => ref mStats;
	public RenderGraph Graph => mGraph;

	// Phase 5: shared state exposed to features
	public DrawBatcher Batcher => mBatcher;
	public ObjectUniformManager ObjectUniforms => mObjectUniforms;
	public IBindGroup SceneBindGroup => mSceneBindGroups[CurrentBufferSlot];
	public IBindGroup ObjectBindGroup => mObjectBindGroups[CurrentBufferSlot];
	public IBindGroupLayout SceneBindGroupLayout => mSceneBindGroupLayout;
	public IBindGroupLayout ObjectBindGroupLayout => mObjectBindGroupLayout;
	public IBindGroupLayout GPUDrivenObjectLayout => mGPUDrivenObjectLayout;
	public IBindGroup GPUDrivenObjectBindGroup => mGPUDrivenObjectBindGroups[mFrameIndex];
	public IBuffer IdentityInstanceBuffer => mIdentityInstanceBuffer;
	public int FrameIndex => mFrameIndex;
	public int ViewIndex => mViewIndex;
	public int CurrentBufferSlot => RenderConfig.BufferSlot(mFrameIndex, mViewIndex);
	public LightingSystem Lighting => mLightingSystem;
	public ShadowSystem Shadows => mShadowSystem;
	public SkinningSystem Skinning => mSkinningSystem;
	public ReflectionProbeSystem ReflectionProbes => mReflectionProbeSystem;
	public GPUSceneBuffer GPUScene => mGPUSceneBuffer;
	public IndirectDrawSystem IndirectDraws => mIndirectDrawSystem;
	public HiZPyramid HiZ => mHiZPyramid;
	public VisibilityResolver Visibility => mVisibility;

	/// Initializes the render system. Call once after device creation.
	public Result<void> Initialize(IDevice device, IQueue graphicsQueue, IQueue computeQueue = null)
	{
		mDevice = device;
		mGraphicsQueue = graphicsQueue;
		mComputeQueue = computeQueue;
		mDeferredDeletions = new DeferredDeletionQueue(device);

		// Create render graph
		mGraph = new RenderGraph();

		// Create per-frame command pools
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			let poolResult = device.CreateCommandPool(.Graphics);
			if (poolResult case .Err)
				return .Err;
			mCommandPools[i] = poolResult.Value;
		}

		let fenceResult = device.CreateFence(0);
		if (fenceResult case .Err)
			return .Err;
		mFrameFence = fenceResult.Value;

		// Create init fence
		let initFenceResult = device.CreateFence(0);
		if (initFenceResult case .Err)
			return .Err;
		mInitFence = initFenceResult.Value;

		// Initialize frame context (scene uniform buffers)
		if (mFrameContext.Initialize(device) case .Err)
			return .Err;

		// Create shared transfer batch for feature initialization
		let batchResult = graphicsQueue.CreateTransferBatch();
		if (batchResult case .Err)
			return .Err;
		var transferBatch = batchResult.Value;

		// Initialize GPU resource manager (creates fallback textures via transfer batch)
		if (mResources.Initialize(device, graphicsQueue, transferBatch) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}

		// Initialize shader library and pipeline cache
		mShaderLibrary.Initialize(device);
		if (mPipelineCache.Initialize(device, mShaderLibrary) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}

		// Create shared bind group layouts
		if (CreateSharedLayouts(device) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}

		// Initialize object uniform manager
		if (mObjectUniforms.Initialize(device) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}

		// Initialize lighting system
		if (mLightingSystem.Initialize(device, mShaderLibrary) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}

		// Initialize shadow system
		if (mShadowSystem.Initialize(device, mShaderLibrary, mObjectBindGroupLayout) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}

		// Initialize skinning system
		if (mSkinningSystem.Initialize(device, mShaderLibrary) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}

		// Initialize reflection probe system
		if (mReflectionProbeSystem.Initialize(device) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}

		// Initialize GPU-driven rendering systems
		if (mGPUSceneBuffer.Initialize(device) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}
		if (mIndirectDrawSystem.Initialize(device, mShaderLibrary) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}
		if (mHiZPyramid.Initialize(device, mShaderLibrary) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}

		// Initialize all registered features
		let initCtx = scope InitContext();
		initCtx.Device = device;
		initCtx.TransferBatch = transferBatch;
		initCtx.Resources = mResources;
		initCtx.Shaders = mShaderLibrary;
		initCtx.Pipelines = mPipelineCache;
		initCtx.System = this;

		for (let feature in mFeatures)
		{
			if (feature.OnInitialize(initCtx) case .Err)
			{
				graphicsQueue.DestroyTransferBatch(ref transferBatch);
				return .Err;
			}
		}

		// Submit all queued uploads asynchronously — one submit for all features
		if (transferBatch.SubmitAsync(mInitFence, 1) case .Err)
		{
			graphicsQueue.DestroyTransferBatch(ref transferBatch);
			return .Err;
		}
		graphicsQueue.DestroyTransferBatch(ref transferBatch);

		return .Ok;
	}

	/// Sets the shader compiler. Must be called before Initialize().
	public void SetShaderCompiler(IShaderCompiler compiler)
	{
		mShaderLibrary.SetCompiler(compiler);
	}

	/// Registers a feature. Must be called before Initialize().
	public void RegisterFeature(IRenderFeature feature)
	{
		mFeatures.Add(feature);
	}

	/// Gets a registered feature by type.
	public T GetFeature<T>() where T : class, IRenderFeature
	{
		for (let feature in mFeatures)
		{
			if (feature.GetType() == typeof(T))
				return (T)feature;
		}
		return default;
	}

	/// Sets the active render world.
	public void SetActiveWorld(RenderWorld world)
	{
		mActiveWorld = world;
	}

	/// Called at the start of each frame.
	public void BeginFrame(float totalTime, float deltaTime)
	{
		// Wait for init fence on first frame
		if (!mInitWaited)
		{
			mInitFence.Wait(1);
			mInitWaited = true;
			mDevice.DestroyFence(ref mInitFence);
		}

		// Advance frame index (selects which command pool to use)
		mFrameIndex = (int)(mFrameContext.FrameNumber % RenderConfig.FrameBufferCount);

		// Wait for the frame that last used this command pool slot to complete.
		// With FrameBufferCount=2: frame N waits for frame N-2's submission.
		if (mFrameFenceValue >= (uint64)RenderConfig.FrameBufferCount)
		{
			let waitValue = mFrameFenceValue - (uint64)RenderConfig.FrameBufferCount + 1;
			mFrameFence.Wait(waitValue);
		}

		// Process deferred GPU resource deletions
		mResources.ProcessDeletions(mFrameContext.FrameNumber);
		mDeferredDeletions.ProcessDeletions(mFrameContext.FrameNumber);

		mStats.Reset();
		mFrameContext.TotalTime = totalTime;
		mFrameContext.DeltaTime = deltaTime;
		mFrameContext.FrameNumber++;
	}

	/// Renders one view through the full pipeline, submits, and presents.
	public void Render(RenderView view, ISwapChain swapChain, int viewIndex = 0)
	{
		mViewIndex = viewIndex;

		// Populate view context from the render view
		mViewContext.Update(view);

		// Apply pre-graph effects (e.g., TAA jitter) before uniform upload
		let postStack = GetFeature<PostProcessStack>();
		if (postStack != null)
			postStack.ApplyPreGraph(mViewContext, mFrameContext);

		// Acquire next swap chain image
		if (swapChain.AcquireNextImage() case .Err)
			return;

		// Import backbuffer into render graph
		let backbuffer = mGraph.ImportTexture(
			"Backbuffer",
			swapChain.CurrentTexture,
			swapChain.CurrentTextureView,
			.Present
		);

		// Make render target available to features
		mViewContext.RenderTarget = backbuffer;

		// Select buffer slot for this frame + view combination
		mFrameContext.SetSlot(mFrameIndex, mViewIndex);

		// Update shadow atlas FIRST (allocates tiles, computes VP matrices)
		// so shadow indices are available when LightingSystem uploads GPULightData.
		mShadowSystem.UpdateAtlas(mActiveWorld, mFrameIndex);

		// Upload light data (queries shadow system for atlas shadow indices)
		mLightingSystem.Update(mActiveWorld, mFrameIndex, mShadowSystem);
		mFrameContext.LightCount = (uint32)mLightingSystem.ActiveLightCount;

		// Update cascade shadow system (compute cascade matrices for this view)
		mShadowSystem.Update(mActiveWorld, mViewContext, CurrentBufferSlot);
		mFrameContext.ShadowCascadeCount = mShadowSystem.HasShadowCaster ? (uint32)RenderConfig.ShadowCascadeCount : 0;

		// Update reflection probes (sync proxy data, upload uniforms)
		if (mActiveWorld != null)
		{
			mReflectionProbeSystem.Update(mActiveWorld, mFrameIndex);
			mFrameContext.ProbeCount = mReflectionProbeSystem.ActiveProbeCount;
		}

		// Upload scene uniforms for this view
		let uniforms = mFrameContext.UploadUniforms(mViewContext, mActiveWorld);
		mViewContext.Uniforms = uniforms;
		mViewContext.SceneUniformBuffer = mFrameContext.CurrentUniformBuffer;

		// Reset object uniforms BEFORE rebuilding bind groups so the bind group
		// references the correct frame's buffer (not the previous frame's).
		mObjectUniforms.Reset(mFrameIndex, mViewIndex);

		// Rebuild per-frame bind groups (scene + object uniform buffers change each view)
		RebuildPerFrameBindGroups();

		// Phase 4-5: resolve visibility, build draw batches
		if (mActiveWorld != null)
		{
			mVisibility.Resolve(mActiveWorld, mViewContext);
			mBatcher.Build(mActiveWorld, mResources, mVisibility,
				scope (h) => GetMaterialInstance(h));
		}

		// Phase 17: Upload GPU scene buffer + build draw groups for GPU-driven rendering
		mGPUSceneBuffer.Update(mActiveWorld, mResources, mFrameIndex);
		mIndirectDrawSystem.BuildDrawGroups(mActiveWorld, mResources);

		// Let features add their passes
		for (let feature in mFeatures)
			feature.OnAddPasses(mGraph, mFrameContext, mViewContext);

		// If no features added passes, add a default clear pass
		if (mGraph.PassCount == 0)
			AddClearPass(backbuffer);

		// Compile the render graph (topo sort, pass culling, aliasing, barriers)
		mGraph.Compile();

		// Allocate transient GPU resources, wire them, and re-solve barriers
		// with concrete handles. Normally Execute() does this, but we record
		// passes manually for control over the present barrier.
		mGraph.PrepareExecution(mDevice);

		// Execute passes manually (gives us control over present barrier)
		let cmdPool = mCommandPools[mFrameIndex];
		cmdPool.Reset();
		let encoder = cmdPool.CreateEncoder().Value;
		let registry = scope ResourceRegistry(mGraph);

		// Copy light data from staging → GPU, then dispatch cluster culling
		encoder.BeginDebugLabel("LightUpload+Cull", 0.6f, 0.6f, 0.3f);
		mLightingSystem.RecordUpload(encoder, mFrameIndex);
		mLightingSystem.RecordCull(encoder, mFrameIndex, mFrameContext.CurrentUniformBuffer);
		encoder.EndDebugLabel();

		// Record GPU scene buffer upload + GPU frustum culling dispatch
		encoder.BeginDebugLabel("GPUScene+Cull", 0.6f, 0.6f, 0.3f);
		mGPUSceneBuffer.RecordUpload(encoder, mFrameIndex);
		mIndirectDrawSystem.RecordCull(encoder, mFrameIndex, mGPUSceneBuffer, mResources, mViewContext, mHiZPyramid);
		encoder.EndDebugLabel();

		// Record GPU skinning compute dispatches (before shadows so output VBs are ready)
		encoder.BeginDebugLabel("GPUSkinning", 0.6f, 0.6f, 0.3f);
		mSkinningSystem.RecordSkinning(encoder, mFrameIndex, mActiveWorld, mResources, mVisibility,
			scope (h) => GetMaterialInstance(h));
		encoder.EndDebugLabel();

		// Record shadow cascade depth passes (pre-graph)
		encoder.BeginDebugLabel("ShadowCascades", 0.3f, 0.3f, 0.6f);
		mShadowSystem.RecordShadowPasses(encoder, mFrameIndex, mActiveWorld, mResources, mBatcher, mObjectUniforms, ObjectBindGroup, mSkinningSystem);
		encoder.EndDebugLabel();

		// Record shadow atlas passes (point/spot lights, pre-graph)
		encoder.BeginDebugLabel("ShadowAtlas", 0.3f, 0.3f, 0.6f);
		mShadowSystem.RecordAtlasShadowPasses(encoder, mFrameIndex, mActiveWorld, mResources, mBatcher, mObjectUniforms, ObjectBindGroup, mSkinningSystem);
		encoder.EndDebugLabel();

		// First-frame: transition fallback IBL textures to ShaderRead
		if (!mFallbackIBLTransitioned && mFallbackCubemap != null)
		{
			TextureBarrier[2] barriers = .(
				.() { Texture = mFallbackCubemap, OldState = mFallbackCubemap.InitialState, NewState = .ShaderRead },
				.() { Texture = mFallbackBrdfLut, OldState = mFallbackBrdfLut.InitialState, NewState = .ShaderRead }
			);
			encoder.Barrier(BarrierGroup() { TextureBarriers = Span<TextureBarrier>(&barriers[0], 2) });
			mFallbackIBLTransitioned = true;
		}

		// Pre-graph GPU work from features (IBL baking, etc.)
		for (let feature in mFeatures)
			feature.OnRecordPreGraph(encoder);

		for (int i = 0; i < mGraph.ScheduledPassCount; i++)
		{
			let pass = mGraph.GetScheduledPass(i);

			// Emit barriers
			let barriers = mGraph.GetBarriersForPass(i);
			if (barriers.HasValue)
				EmitBarriers(encoder, barriers.Value);

			// Debug label for RenderDoc
			encoder.BeginDebugLabel(pass.Name, 0.4f, 0.7f, 1.0f);

			// Execute
			if (pass.ExecuteCallback != null)
				pass.ExecuteCallback(encoder, registry);

			encoder.EndDebugLabel();
		}

		// Transition backbuffer to Present
		var texBarrier = TextureBarrier()
		{
			Texture = swapChain.CurrentTexture,
			OldState = .RenderTarget,
			NewState = .Present
		};
		encoder.Barrier(BarrierGroup()
		{
			TextureBarriers = Span<TextureBarrier>(&texBarrier, 1)
		});

		// Submit
		var cmdBuf = encoder.Finish();
		mFrameFenceValue++;
		mGraphicsQueue.Submit(Span<ICommandBuffer>(&cmdBuf, 1), mFrameFence, mFrameFenceValue);

		// Release encoder
		var enc = encoder;
		cmdPool.DestroyEncoder(ref enc);

		// Present
		swapChain.Present(mGraphicsQueue);

		mStats.PassCount = (int32)mGraph.ScheduledPassCount;

		// Post-render callbacks
		for (let feature in mFeatures)
			feature.OnPostRender();

		// Reset graph for next frame
		mGraph.Reset();
	}

	/// Convenience: renders with the default view built from the active world's main camera.
	public void RenderFromWorld(ISwapChain swapChain)
	{
		if (mActiveWorld == null)
			return;

		let camHandle = mActiveWorld.MainCamera;
		if (!camHandle.IsValid)
			return;

		CameraProxy* cameraPtr;
		if (!mActiveWorld.Cameras.TryGet(camHandle.Handle, out cameraPtr))
			return;

		mDefaultView.FromCamera(ref *cameraPtr, swapChain.Width, swapChain.Height);
		Render(mDefaultView, swapChain);
	}

	/// Bakes all dirty reflection probes by rendering the scene from each probe position.
	/// Call after the scene is set up (e.g., at level load). Uses WaitIdle for synchronization.
	public void BakeReflectionProbes()
	{
		if (mActiveWorld == null || mDevice == null) return;

		// Ensure GPU is idle before we start using resources
		mDevice.WaitIdle();

		let probeSystem = mReflectionProbeSystem;
		let probeView = new RenderView();
		probeView.Name = new String("ProbeCapture");
		defer delete probeView;
		probeView.Width = ReflectionProbeSystem.CubemapSize;
		probeView.Height = ReflectionProbeSystem.CubemapSize;
		probeView.FieldOfView = Math.PI_f / 2.0f;  // 90° FOV
		probeView.NearPlane = 0.1f;
		probeView.FarPlane = 1000.0f;

		// Allocate layers and find dirty probes
		probeSystem.Update(mActiveWorld, mFrameIndex);

		// Ensure IBL and other pre-graph resources are ready before probe capture.
		// SkyFeature bakes IBL in OnRecordPreGraph — call it now so the prefiltered
		// cubemap is in ShaderRead state when the forward pass samples it.
		{
			let prePoolResult = mDevice.CreateCommandPool(.Graphics);
			if (prePoolResult case .Ok(var prePool))
			{
				let preEncResult = prePool.CreateEncoder();
				if (preEncResult case .Ok(var preEnc))
				{
					// Transition textures that are in UNDEFINED layout but bound in scene bind group
					int barrierCount = 0;
					TextureBarrier[4] initBarriers = default;

					let shadowAtlasTex = mShadowSystem.GetAtlasTexture();
					if (shadowAtlasTex != null)
						initBarriers[barrierCount++] = .() { Texture = shadowAtlasTex, OldState = shadowAtlasTex.InitialState, NewState = .ShaderRead };

					let cascadeTex = mShadowSystem.GetCascadeTexture();
					if (cascadeTex != null)
						initBarriers[barrierCount++] = .() { Texture = cascadeTex, OldState = cascadeTex.InitialState, NewState = .ShaderRead };

					let probeCubemapTex = probeSystem.CubemapArrayTexture;
					if (probeCubemapTex != null)
						initBarriers[barrierCount++] = .() { Texture = probeCubemapTex, OldState = .Undefined, NewState = .ShaderRead };

					if (barrierCount > 0)
						preEnc.Barrier(BarrierGroup() { TextureBarriers = Span<TextureBarrier>(&initBarriers[0], barrierCount) });

					for (let feature in mFeatures)
						feature.OnRecordPreGraph(preEnc);
					let preCmdBuf = preEnc.Finish();
					ICommandBuffer[1] preCmdBufs = .(preCmdBuf);
					mGraphicsQueue.Submit(Span<ICommandBuffer>(&preCmdBufs[0], 1));
					mDevice.WaitIdle();
					prePool.Reset();
					prePool.DestroyEncoder(ref preEnc);
				}
				mDevice.DestroyCommandPool(ref prePool);
			}
		}

		mActiveWorld.ReflectionProbes.ForEach(scope [&](handle, proxy) =>
		{
			if (!proxy.Enabled || !proxy.IsDirty || proxy.CubemapLayer < 0) return;

			Console.WriteLine(scope $"Baking reflection probe (layer {proxy.CubemapLayer}) at ({proxy.Position.X:0.1}, {proxy.Position.Y:0.1}, {proxy.Position.Z:0.1})");

			let poolResult = mDevice.CreateCommandPool(.Graphics);
			if (poolResult case .Err) return;
			var cmdPool = poolResult.Value;

			for (int face = 0; face < 6; face++)
			{
				// Set up camera for this cubemap face
				Vector3 forward, up;
				ReflectionProbeSystem.GetFaceCamera(face, out forward, out up);

				probeView.CameraPosition = proxy.Position;
				probeView.CameraForward = forward;
				probeView.CameraUp = up;
				probeView.UpdateMatrices();

				// Set up view context
				mViewContext.Update(probeView);
				mFrameContext.SetSlot(mFrameIndex, 0);

				// Update systems for this view
				mLightingSystem.Update(mActiveWorld, mFrameIndex, mShadowSystem);
				mFrameContext.LightCount = (uint32)mLightingSystem.ActiveLightCount;
				mShadowSystem.Update(mActiveWorld, mViewContext, CurrentBufferSlot);
				mFrameContext.ShadowCascadeCount = mShadowSystem.HasShadowCaster ? (uint32)RenderConfig.ShadowCascadeCount : 0;
				mFrameContext.ProbeCount = 0;  // Don't sample probes during probe baking

				let uniforms = mFrameContext.UploadUniforms(mViewContext, mActiveWorld);
				mViewContext.Uniforms = uniforms;
				mViewContext.SceneUniformBuffer = mFrameContext.CurrentUniformBuffer;
				mObjectUniforms.Reset(mFrameIndex, 0);
				RebuildPerFrameBindGroups();

				// Rebuild visibility and batches for this view
				mVisibility.Resolve(mActiveWorld, mViewContext);
				mBatcher.Build(mActiveWorld, mResources, mVisibility,
					scope (h) => GetMaterialInstance(h));
				mGPUSceneBuffer.Update(mActiveWorld, mResources, mFrameIndex);
				mIndirectDrawSystem.BuildDrawGroups(mActiveWorld, mResources);

				// Features create their own transient render targets (SceneColor, SceneDepth).
				// We'll copy the final SceneColor to tempTex after graph execution.
				mViewContext.RenderTarget = default;

				// Add only features that support probe capture
				for (let feature in mFeatures)
				{
					if (feature.SupportsProbeCapture)
						feature.OnAddPasses(mGraph, mFrameContext, mViewContext);
				}

				mGraph.Compile();
				mGraph.PrepareExecution(mDevice);

				let encoderResult = cmdPool.CreateEncoder();
				if (encoderResult case .Err) { mGraph.Reset(); continue; }
				var encoder = encoderResult.Value;
				let registry = scope ResourceRegistry(mGraph);

				encoder.BeginDebugLabel(scope $"ProbeBake_Face{face}", 1.0f, 0.5f, 0.0f);

				// Pre-graph GPU work
				mLightingSystem.RecordUpload(encoder, mFrameIndex);
				mLightingSystem.RecordCull(encoder, mFrameIndex, mFrameContext.CurrentUniformBuffer);
				mGPUSceneBuffer.RecordUpload(encoder, mFrameIndex);
				mIndirectDrawSystem.RecordCull(encoder, mFrameIndex, mGPUSceneBuffer, mResources, mViewContext, mHiZPyramid);

				// Execute graph passes (renders to tempTex)
				for (int i = 0; i < mGraph.ScheduledPassCount; i++)
				{
					let pass = mGraph.GetScheduledPass(i);
					let barriers = mGraph.GetBarriersForPass(i);
					if (barriers.HasValue)
						EmitBarriers(encoder, barriers.Value);
					encoder.BeginDebugLabel(pass.Name, 0.4f, 0.7f, 1.0f);
					if (pass.ExecuteCallback != null)
						pass.ExecuteCallback(encoder, registry);
					encoder.EndDebugLabel();
				}

				// Copy the graph's SceneColor → cubemap array layer
				let forwardFeature = GetFeature<ForwardOpaqueFeature>();
				let sceneColorView = (forwardFeature != null) ? registry.GetTextureView(forwardFeature.SceneColorTexture) : null;
				if (sceneColorView != null && sceneColorView.Texture != null)
				{
					let srcTex = sceneColorView.Texture;
					let dstLayer = (uint32)(proxy.CubemapLayer * 6 + face);

					encoder.Barrier(BarrierGroup()
					{
						TextureBarriers = .(scope TextureBarrier[2](
							.() { Texture = srcTex, OldState = .RenderTarget, NewState = .CopySrc },
							.() { Texture = probeSystem.CubemapArrayTexture, OldState = .ShaderRead, NewState = .CopyDst }
						))
					});

					encoder.CopyTextureToTexture(srcTex, probeSystem.CubemapArrayTexture, TextureCopyRegion()
					{
						SrcMipLevel = 0, SrcArrayLayer = 0,
						DstMipLevel = 0, DstArrayLayer = dstLayer,
						Extent = .(ReflectionProbeSystem.CubemapSize, ReflectionProbeSystem.CubemapSize, 1)
					});

					encoder.Barrier(BarrierGroup()
					{
						TextureBarriers = .(scope TextureBarrier[2](
							.() { Texture = srcTex, OldState = .CopySrc, NewState = .RenderTarget },
							.() { Texture = probeSystem.CubemapArrayTexture, OldState = .CopyDst, NewState = .ShaderRead }
						))
					});
				}

				encoder.EndDebugLabel(); // ProbeBake_FaceN

				let cmdBuf = encoder.Finish();
				ICommandBuffer[1] cmdBufs = .(cmdBuf);
				mGraphicsQueue.Submit(Span<ICommandBuffer>(&cmdBufs[0], 1));
				mDevice.WaitIdle();

				cmdPool.Reset();
				cmdPool.DestroyEncoder(ref encoder);
				mGraph.Reset();
			}

			proxy.IsDirty = false;
			mDevice.DestroyCommandPool(ref cmdPool);
		});

		Console.WriteLine("Reflection probe baking complete");
	}

	/// Shuts down the render system and releases all GPU resources.
	public void Shutdown()
	{
		if (mDevice == null)
			return;

		mDevice.WaitIdle();

		// Flush deferred deletions (GPU is idle now)
		if (mDeferredDeletions != null)
		{
			mDeferredDeletions.Flush();
			delete mDeferredDeletions;
			mDeferredDeletions = null;
		}

		// Shutdown features in reverse order
		for (int i = mFeatures.Count - 1; i >= 0; i--)
			mFeatures[i].OnShutdown(mDevice);

		// Shutdown pipeline cache, shader library, then resource manager
		mPipelineCache.Shutdown();
		mShaderLibrary.Shutdown();
		mResources.Shutdown();

		// Shutdown object uniform manager, lighting system, and shadow system
		mObjectUniforms.Shutdown();
		mLightingSystem.Shutdown();
		mShadowSystem.Shutdown();
		mSkinningSystem.Shutdown();
		mReflectionProbeSystem.Shutdown(mDevice);
		mHiZPyramid.Shutdown();
		mIndirectDrawSystem.Shutdown();
		mGPUSceneBuffer.Shutdown();

		// Destroy per-frame-per-view bind groups and shared layouts
		for (int i = 0; i < RenderConfig.TotalBufferSlots; i++)
		{
			if (mObjectBindGroups[i] != null)
				mDevice.DestroyBindGroup(ref mObjectBindGroups[i]);
			if (mSceneBindGroups[i] != null)
				mDevice.DestroyBindGroup(ref mSceneBindGroups[i]);
		}
		// Destroy bind groups BEFORE their layouts (DX12 use-after-free)
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mGPUDrivenObjectBindGroups[i] != null)
				mDevice.DestroyBindGroup(ref mGPUDrivenObjectBindGroups[i]);
		}
		if (mObjectBindGroupLayout != null)
			mDevice.DestroyBindGroupLayout(ref mObjectBindGroupLayout);
		if (mGPUDrivenObjectLayout != null)
			mDevice.DestroyBindGroupLayout(ref mGPUDrivenObjectLayout);
		if (mIdentityInstanceBuffer != null)
		{
			mIdentityInstanceBuffer.Unmap();
			mDevice.DestroyBuffer(ref mIdentityInstanceBuffer);
		}
		if (mSceneBindGroupLayout != null)
			mDevice.DestroyBindGroupLayout(ref mSceneBindGroupLayout);

		// Fallback IBL textures
		if (mFallbackBrdfLutView != null) mDevice.DestroyTextureView(ref mFallbackBrdfLutView);
		if (mFallbackBrdfLut != null) mDevice.DestroyTexture(ref mFallbackBrdfLut);
		if (mFallbackCubemapView != null) mDevice.DestroyTextureView(ref mFallbackCubemapView);
		if (mFallbackCubemap != null) mDevice.DestroyTexture(ref mFallbackCubemap);

		mFrameContext.Shutdown();

		if (mFrameFence != null)
			mDevice.DestroyFence(ref mFrameFence);
		if (mInitFence != null)
			mDevice.DestroyFence(ref mInitFence);
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mCommandPools[i] != null)
				mDevice.DestroyCommandPool(ref mCommandPools[i]);
		}

		if (mGraph != null)
		{
			mGraph.Destroy();
			delete mGraph;
			mGraph = null;
		}
	}

	// --- Material Instance Management ---

	/// Creates a material instance from a definition. Returns a handle for binding.
	public Result<MaterialInstanceHandle> CreateMaterialInstance(MaterialDefinition definition)
	{
		let matInst = new MaterialInstance();
		if (matInst.Initialize(mDevice, definition) case .Err)
		{
			delete matInst;
			return .Err;
		}

		uint32 index;
		uint32 generation;
		if (mFreeMaterialSlots.Count > 0)
		{
			index = (uint32)mFreeMaterialSlots.PopBack();
			let old = mMaterialInstances[(int)index];
			generation = old.Generation + 1;
			delete old;
			mMaterialInstances[(int)index] = matInst;
		}
		else
		{
			index = (uint32)mMaterialInstances.Count;
			generation = 1;
			mMaterialInstances.Add(matInst);
		}

		matInst.Generation = generation;
		matInst.RefCount = 1;
		matInst.IsActive = true;

		return .Ok(.() { Index = index, Generation = generation });
	}

	/// Gets a material instance by handle. Returns null if invalid.
	public MaterialInstance GetMaterialInstance(MaterialInstanceHandle handle)
	{
		if (!handle.IsValid || handle.Index >= (uint32)mMaterialInstances.Count)
			return null;

		let inst = mMaterialInstances[(int)handle.Index];
		if (!inst.IsActive || inst.Generation != handle.Generation)
			return null;

		return inst;
	}

	/// Destroys a material instance.
	public void DestroyMaterialInstance(MaterialInstanceHandle handle)
	{
		if (let inst = GetMaterialInstance(handle))
		{
			inst.Release(mDevice);
			mFreeMaterialSlots.Add((int32)handle.Index);
		}
	}

	// --- Internal ---

	private Result<void> CreateSharedLayouts(IDevice device)
	{
		// Scene bind group layout (Set 0):
		//   binding 0: SceneUniforms UBO
		//   binding 1: LightBuffer (storage, read-only)
		//   binding 2: ClusterGrid (storage, read-only)
		//   binding 3: LightIndexBuffer (storage, read-only)
		//   binding 4: ShadowUniforms UBO (cascade matrices + params)
		//   binding 5: CascadeShadowMap (Texture2DArray, sampled)
		//   binding 6: ShadowSampler (comparison sampler)
		//   binding 7: ShadowAtlas (Texture2D, sampled)
		//   binding 8: ShadowData (storage, read-only — StructuredBuffer<GPUShadowData>)
		//   binding 9: IrradianceCubemap (TextureCube, sampled)
		//   binding 10: PrefilteredCubemap (TextureCube, sampled)
		//   binding 11: BRDFLut (Texture2D, sampled)
		//   binding 12: ReflectionProbe cubemap array (TextureCubeArray, sampled)
		//   binding 13: ReflectionProbe data (StructuredBuffer<GPUProbeData>)
		BindGroupLayoutEntry[14] sceneEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.StorageBuffer(1, .Fragment, readWrite: false),
			BindGroupLayoutEntry.StorageBuffer(2, .Fragment, readWrite: false),
			BindGroupLayoutEntry.StorageBuffer(3, .Fragment, readWrite: false),
			BindGroupLayoutEntry.UniformBuffer(4, .Fragment),
			BindGroupLayoutEntry.SampledTexture(5, .Fragment, .Texture2DArray),
			BindGroupLayoutEntry.ComparisonSampler(6, .Fragment),
			BindGroupLayoutEntry.SampledTexture(7, .Fragment, .Texture2D),
			BindGroupLayoutEntry.StorageBuffer(8, .Fragment, readWrite: false),
			BindGroupLayoutEntry.SampledTexture(9, .Fragment, .TextureCube),
			BindGroupLayoutEntry.SampledTexture(10, .Fragment, .TextureCube),
			BindGroupLayoutEntry.SampledTexture(11, .Fragment, .Texture2D),
			BindGroupLayoutEntry.SampledTexture(12, .Fragment, .TextureCubeArray),
			BindGroupLayoutEntry.UniformBuffer(13, .Fragment)
		);
		let sceneLayoutResult = device.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = Span<BindGroupLayoutEntry>(&sceneEntries[0], 14),
			Label = "SceneBindGroupLayout"
		});
		if (sceneLayoutResult case .Err)
			return .Err;
		mSceneBindGroupLayout = sceneLayoutResult.Value;

		// Object bind group layout (Set 2 for forward, Set 1 for depth): single dynamic UBO
		var objectEntry = BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment, dynamicOffset: true);
		let objectLayoutResult = device.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = Span<BindGroupLayoutEntry>(&objectEntry, 1),
			Label = "ObjectBindGroupLayout"
		});
		if (objectLayoutResult case .Err)
			return .Err;
		mObjectBindGroupLayout = objectLayoutResult.Value;

		// GPU-driven object bind group layout (Set 2): storage buffer for per-object data
		var gpuDrivenEntry = BindGroupLayoutEntry.StorageBuffer(0, .Vertex | .Fragment, readWrite: false);
		let gpuDrivenLayoutResult = device.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = Span<BindGroupLayoutEntry>(&gpuDrivenEntry, 1),
			Label = "GPUDrivenObjectLayout"
		});
		if (gpuDrivenLayoutResult case .Err)
			return .Err;
		mGPUDrivenObjectLayout = gpuDrivenLayoutResult.Value;

		// Identity instance buffer: [0, 1, 2, ..., MaxOpaqueObjects-1]
		// Used as vertex slot 1 (per-instance) — hardware fetches entry[firstInstance + instanceIdx]
		// CpuToGpu memory: write-once at init, no staging/copy needed.
		{
			let maxObj = (uint32)RenderConfig.MaxOpaqueObjects;
			let bufSize = (uint64)(maxObj * sizeof(uint32));
			let bufResult = device.CreateBuffer(BufferDesc()
			{
				Size = bufSize,
				Usage = .Vertex,
				Memory = .CpuToGpu,
				Label = "IdentityInstanceBuffer"
			});
			if (bufResult case .Err) return .Err;
			mIdentityInstanceBuffer = bufResult.Value;

			let ptr = (uint32*)mIdentityInstanceBuffer.Map();
			if (ptr != null)
			{
				for (uint32 i = 0; i < maxObj; i++)
					ptr[i] = i;
			}
		}

		// Create fallback IBL textures for when SkyFeature is not registered
		if (CreateFallbackIBLTextures(device) case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateFallbackIBLTextures(IDevice device)
	{
		// 1x1 black cubemap (6 layers)
		let cubeResult = device.CreateTexture(TextureDesc.Tex2DArray(
			.RGBA16Float, 1, 1, 6, .Sampled | .CopyDst, label: "FallbackCubemap"));
		if (cubeResult case .Err) return .Err;
		mFallbackCubemap = cubeResult.Value;

		let cubeViewResult = device.CreateTextureView(mFallbackCubemap, TextureViewDesc()
		{
			Dimension = .TextureCube,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6,
			Label = "FallbackCubemap_View"
		});
		if (cubeViewResult case .Err) return .Err;
		mFallbackCubemapView = cubeViewResult.Value;

		// 1x1 BRDF LUT (RG16Float, value doesn't matter — IBL will be zero anyway)
		let brdfResult = device.CreateTexture(TextureDesc.Tex2D(
			.RG16Float, 1, 1, .Sampled | .CopyDst, label: "FallbackBRDFLut"));
		if (brdfResult case .Err) return .Err;
		mFallbackBrdfLut = brdfResult.Value;

		let brdfViewResult = device.CreateTextureView(mFallbackBrdfLut, TextureViewDesc()
		{
			Label = "FallbackBRDFLut_View"
		});
		if (brdfViewResult case .Err) return .Err;
		mFallbackBrdfLutView = brdfViewResult.Value;

		return .Ok;
	}

	private void RebuildPerFrameBindGroups()
	{
		let slot = CurrentBufferSlot;
		let fi = mFrameIndex;

		// Destroy this slot's old bind groups (safe — the fence wait in
		// BeginFrame guarantees this slot's prior GPU work has completed).
		if (mSceneBindGroups[slot] != null)
			mDevice.DestroyBindGroup(ref mSceneBindGroups[slot]);
		if (mObjectBindGroups[slot] != null)
			mDevice.DestroyBindGroup(ref mObjectBindGroups[slot]);

		// Scene bind group: SceneUniforms + lighting + cascades + atlas + IBL + probes
		let sceneBuffer = mFrameContext.CurrentUniformBuffer;
		let skyFeature = GetFeature<SkyFeature>();

		if (sceneBuffer != null && mSceneBindGroupLayout != null)
		{
			// IBL texture views: from SkyFeature if registered, otherwise use fallbacks
			let irradianceView = (skyFeature != null) ? skyFeature.IrradianceCubemapView : mFallbackCubemapView;
			let prefilteredView = (skyFeature != null) ? skyFeature.PrefilteredCubemapView : mFallbackCubemapView;
			let brdfLutView = (skyFeature != null) ? skyFeature.BrdfLutView : mFallbackBrdfLutView;

			BindGroupEntry[14] sceneEntries = .(
				BindGroupEntry.Buffer(sceneBuffer, 0, (uint64)sizeof(SceneUniforms)),
				BindGroupEntry.Buffer(mLightingSystem.GetLightBuffer(fi), 0, 0),
				BindGroupEntry.Buffer(mLightingSystem.GetClusterBuffer(fi), 0, 0),
				BindGroupEntry.Buffer(mLightingSystem.GetLightIndexBuffer(fi), 0, 0),
				BindGroupEntry.Buffer(mShadowSystem.GetShadowUniformBuffer(slot), 0, (uint64)sizeof(ShadowUniforms)),
				BindGroupEntry.Texture(mShadowSystem.GetCascadeTextureView()),
				BindGroupEntry.Sampler(mShadowSystem.GetShadowSampler()),
				BindGroupEntry.Texture(mShadowSystem.GetAtlasTextureView()),
				BindGroupEntry.Buffer(mShadowSystem.GetAtlasDataBuffer(fi), 0, 0),
				BindGroupEntry.Texture(irradianceView),
				BindGroupEntry.Texture(prefilteredView),
				BindGroupEntry.Texture(brdfLutView),
				BindGroupEntry.Texture(mReflectionProbeSystem.CubemapArrayView),
				BindGroupEntry.Buffer(mReflectionProbeSystem.GetUniformBuffer(fi), 0, (uint64)sizeof(GPUProbeUniforms))
			);
			let result = mDevice.CreateBindGroup(BindGroupDesc()
			{
				Layout = mSceneBindGroupLayout,
				Entries = Span<BindGroupEntry>(&sceneEntries[0], 14),
				Label = "SceneBindGroup"
			});
			if (result case .Ok(let bg))
				mSceneBindGroups[slot] = bg;
		}

		// Object bind group: binds to the current slot's object uniform buffer
		let objectBuffer = mObjectUniforms.CurrentBuffer;
		if (objectBuffer != null && mObjectBindGroupLayout != null)
		{
			var objectEntry = BindGroupEntry.Buffer(objectBuffer, 0, (uint64)sizeof(ObjectUniforms));
			let result = mDevice.CreateBindGroup(BindGroupDesc()
			{
				Layout = mObjectBindGroupLayout,
				Entries = Span<BindGroupEntry>(&objectEntry, 1),
				Label = "ObjectBindGroup"
			});
			if (result case .Ok(let bg))
				mObjectBindGroups[slot] = bg;
		}

		// GPU-driven object bind group: binds the GPUSceneBuffer as storage (per frame, not per view)
		if (mGPUDrivenObjectBindGroups[fi] != null)
			mDevice.DestroyBindGroup(ref mGPUDrivenObjectBindGroups[fi]);

		let gpuSceneBuffer = mGPUSceneBuffer.GetBuffer(fi);
		if (gpuSceneBuffer != null && mGPUDrivenObjectLayout != null)
		{
			var gpuObjEntry = BindGroupEntry.Buffer(gpuSceneBuffer);
			let result = mDevice.CreateBindGroup(BindGroupDesc()
			{
				Layout = mGPUDrivenObjectLayout,
				Entries = Span<BindGroupEntry>(&gpuObjEntry, 1),
				Label = "GPUDrivenObjectBindGroup"
			});
			if (result case .Ok(let bg))
				mGPUDrivenObjectBindGroups[fi] = bg;
		}
	}

	private void AddClearPass(RGTexture backbuffer)
	{
		mGraph.AddPass("Clear", .Graphics, scope [&] (builder) =>
		{
			builder.WriteRenderTarget(backbuffer, 0, .Clear, .Store,
				ClearColor(0.1f, 0.1f, 0.15f, 1.0f));
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);
				rp.End();
			});
		});
	}

	private static void EmitBarriers(ICommandEncoder encoder, BarrierSolver.PassBarriers pb)
	{
		let texCount = pb.TextureBarriers != null ? pb.TextureBarriers.Count : 0;
		let bufCount = pb.BufferBarriers != null ? pb.BufferBarriers.Count : 0;
		let memCount = pb.MemoryBarriers != null ? pb.MemoryBarriers.Count : 0;

		if (texCount == 0 && bufCount == 0 && memCount == 0)
			return;

		BarrierGroup group = .();

		if (texCount > 0)
		{
			let texBarriers = scope :: TextureBarrier[texCount];
			for (int i = 0; i < texCount; i++)
				texBarriers[i] = pb.TextureBarriers[i];
			group.TextureBarriers = texBarriers;
		}

		if (bufCount > 0)
		{
			let bufBarriers = scope :: BufferBarrier[bufCount];
			for (int i = 0; i < bufCount; i++)
				bufBarriers[i] = pb.BufferBarriers[i];
			group.BufferBarriers = bufBarriers;
		}

		encoder.Barrier(group);
	}
}

namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using System.Collections;

using internal Sedulous.Renderer;

/// HDRI sky rendering feature.
/// Loads an equirectangular HDR image and renders it as a skybox background
/// wherever the depth buffer is 1.0 (no geometry drawn).
class SkyFeature : IRenderFeature
{
	private IDevice mDevice;
	private RenderSystem mSystem;

	// GPU resources — sky rendering
	private ITexture mHdriTexture;
	private ITextureView mHdriTextureView;
	private ISampler mHdriSampler;
	private IRenderPipeline mPipeline;
	private IPipelineLayout mPipelineLayout;
	private IBindGroupLayout mSkyBindGroupLayout;
	private IBindGroup[RenderConfig.FrameBufferCount] mSkyBindGroups;

	// IBL resources (owned by this feature)
	private ITexture mIrradianceCubemap;
	private ITextureView mIrradianceCubemapView;
	private ITexture mPrefilteredCubemap;
	private ITextureView mPrefilteredCubemapView;
	private ITextureView mBrdfLutView;  // Not owned — caller provides
	private ITexture mFallbackBrdfLut;       // Owned — 1x1 white fallback
	private ITextureView mFallbackBrdfLutView;
	private ISampler mIBLSampler;

	// IBL compute resources
	private IComputePipeline mIrradiancePipeline;
	private IComputePipeline mPrefilterPipeline;
	private IPipelineLayout mIBLComputeLayout;
	private IBindGroupLayout mIBLComputeBindGroupLayout;
	private bool mIBLBaked;
	private bool mIBLBakedOnce;       // True after first successful bake (for barrier old state)
	private bool mIBLInitBarrierDone; // True after initial Undefined→ShaderRead barrier

	// Temp resources from IBL baking — must survive until GPU finishes
	private List<ITextureView> mBakeTempViews = new .() ~ delete _;
	private List<IBindGroup> mBakeTempBindGroups = new .() ~ delete _;

	[CRepr]
	struct IBLPushParams
	{
		public uint32 FaceIndex;
		public uint32 CubemapSize;
		public float Roughness;
		public float _pad;
	}

	private bool mLoaded;

	public StringView Name => "Sky";
	public bool SupportsProbeCapture => true;

	/// Gets the irradiance cubemap view for scene bind group (null if not baked).
	public ITextureView IrradianceCubemapView => mIrradianceCubemapView;

	/// Gets the prefiltered specular cubemap view for scene bind group (null if not baked).
	public ITextureView PrefilteredCubemapView => mPrefilteredCubemapView;

	/// Gets the BRDF LUT view for scene bind group. Returns fallback if not set.
	public ITextureView BrdfLutView => (mBrdfLutView != null) ? mBrdfLutView : mFallbackBrdfLutView;

	/// Marks IBL cubemaps as dirty, triggering re-bake on the next frame.
	public void MarkIBLDirty()
	{
		mIBLBaked = false;
	}

	/// Updates HDRI/BRDF references from the active world's environment.
	private void SyncFromWorld()
	{
		let world = mSystem.ActiveWorld;
		let env = world?.Environment;
		if (env == null)
		{
			mHdriTextureView = null;
			mBrdfLutView = null;
			mLoaded = false;
			return;
		}

		// Detect HDRI change → trigger re-bake
		if (env.HdriTexture != mHdriTextureView)
		{
			mHdriTextureView = env.HdriTexture;
			mLoaded = (mHdriTextureView != null);
			if (mLoaded && mIBLBakedOnce)
				MarkIBLDirty();
		}

		mBrdfLutView = env.BrdfLutTexture;
	}

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;
		mSystem = initCtx.System;

		// Register shader
		if (initCtx.Shaders.RegisterShader("sky_hdri") case .Err)
			return .Err;

		// Sampler for HDRI texture
		let samplerResult = mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear,
			AddressU = .Repeat,    // Wrap horizontally for seamless panorama
			AddressV = .ClampToEdge, // Clamp vertically (poles)
			AddressW = .ClampToEdge,
			Label = "Sky_HdriSampler"
		});
		if (samplerResult case .Err)
			return .Err;
		mHdriSampler = samplerResult.Value;

		// Create bind group layout: HDRI texture + sampler + depth texture
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),   // t0: HDRI texture
			BindGroupLayoutEntry.Sampler(1, .Fragment),          // s1: HDRI sampler
			BindGroupLayoutEntry.SampledTexture(2, .Fragment)    // t2: depth texture
		);
		let layoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = layoutEntries,
			Label = "Sky_BindGroupLayout"
		});
		if (layoutResult case .Err)
			return .Err;
		mSkyBindGroupLayout = layoutResult.Value;

		// Pipeline layout: Set 0 = scene, Set 1 = sky resources
		IBindGroupLayout[2] layouts = .(mSystem.SceneBindGroupLayout, mSkyBindGroupLayout);
		let pipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = layouts,
			Label = "Sky_PipelineLayout"
		});
		if (pipeLayoutResult case .Err)
			return .Err;
		mPipelineLayout = pipeLayoutResult.Value;

		// Compile shaders and create pipeline
		let vsResult = initCtx.Shaders.GetCompiledShader("sky_hdri", .Vertex);
		if (vsResult case .Err)
			return .Err;
		let psResult = initCtx.Shaders.GetCompiledShader("sky_hdri", .Fragment);
		if (psResult case .Err)
			return .Err;

		var colorTarget = ColorTargetState() { Format = .RGBA16Float };
		let pipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mPipelineLayout,
			Vertex = .() { Shader = .(vsResult.Value, "VSMain" ) },
			Fragment = .() { Shader = .(psResult.Value, "PSMain"), Targets = Span<ColorTargetState>(&colorTarget, 1) },
			Primitive = PrimitiveState() { Topology = .TriangleList, CullMode = .None },
			Label = "Sky_Pipeline"
		});
		if (pipeResult case .Err)
			return .Err;
		mPipeline = pipeResult.Value;

		// --- IBL resources ---
		if (CreateIBLResources(initCtx) case .Err)
			Console.WriteLine("WARNING: Failed to create IBL resources");

		return .Ok;
	}

	private Result<void> CreateIBLResources(InitContext initCtx)
	{
		// IBL sampler (linear, clamp)
		let samplerResult = mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear,
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge,
			Label = "IBL_Sampler"
		});
		if (samplerResult case .Err) return .Err;
		mIBLSampler = samplerResult.Value;

		// Irradiance cubemap (32x32 per face, RGBA16Float)
		let irradResult = mDevice.CreateTexture(TextureDesc.Tex2DArray(
			.RGBA16Float, 32, 32, 6,
			.Sampled | .Storage | .CopyDst,
			label: "IBL_Irradiance"
		));
		if (irradResult case .Err) return .Err;
		mIrradianceCubemap = irradResult.Value;

		let irradViewResult = mDevice.CreateTextureView(mIrradianceCubemap, TextureViewDesc()
		{
			Dimension = .TextureCube,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6,
			Label = "IBL_Irradiance_CubeView"
		});
		if (irradViewResult case .Err) return .Err;
		mIrradianceCubemapView = irradViewResult.Value;

		// Prefiltered cubemap (128x128 per face, 5 mip levels, RGBA16Float)
		let prefiltResult = mDevice.CreateTexture(TextureDesc.Tex2DArray(
			.RGBA16Float, 128, 128, 6,
			.Sampled | .Storage | .CopyDst,
			mipLevels: 5,
			label: "IBL_Prefiltered"
		));
		if (prefiltResult case .Err) return .Err;
		mPrefilteredCubemap = prefiltResult.Value;

		let prefiltViewResult = mDevice.CreateTextureView(mPrefilteredCubemap, TextureViewDesc()
		{
			Dimension = .TextureCube,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6,
			MipLevelCount = 5,
			Label = "IBL_Prefiltered_CubeView"
		});
		if (prefiltViewResult case .Err) return .Err;
		mPrefilteredCubemapView = prefiltViewResult.Value;

		// Fallback 1x1 BRDF LUT (white = no IBL attenuation)
		let fallbackResult = mDevice.CreateTexture(TextureDesc.Tex2D(
			.RG16Float, 1, 1, .Sampled | .CopyDst, label: "IBL_FallbackBRDFLut"));
		if (fallbackResult case .Err) return .Err;
		mFallbackBrdfLut = fallbackResult.Value;

		let fallbackViewResult = mDevice.CreateTextureView(mFallbackBrdfLut, TextureViewDesc()
		{
			Label = "IBL_FallbackBRDFLut_View"
		});
		if (fallbackViewResult case .Err) return .Err;
		mFallbackBrdfLutView = fallbackViewResult.Value;

		// Register compute shaders
		if (initCtx.Shaders.RegisterShader("ibl_irradiance") case .Err) return .Err;
		if (initCtx.Shaders.RegisterShader("ibl_prefilter") case .Err) return .Err;

		// IBL compute bind group layout: HDRI texture + sampler + output UAV
		BindGroupLayoutEntry[3] iblEntries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Compute),
			BindGroupLayoutEntry.Sampler(1, .Compute),
			BindGroupLayoutEntry.StorageTexture(2, .Compute, .RGBA16Float, readWrite: true)
		);
		let iblLayoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = iblEntries,
			Label = "IBL_ComputeLayout"
		});
		if (iblLayoutResult case .Err) return .Err;
		mIBLComputeBindGroupLayout = iblLayoutResult.Value;

		// Pipeline layout with push constants for per-dispatch params (16 bytes)
		IBindGroupLayout[1] iblLayouts = .(mIBLComputeBindGroupLayout);
		PushConstantRange[1] pushRanges = .(.() { Offset = 0, Size = 16, Stages = .Compute });
		let iblPipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = iblLayouts,
			PushConstantRanges = pushRanges,
			Label = "IBL_ComputePipelineLayout"
		});
		if (iblPipeLayoutResult case .Err) return .Err;
		mIBLComputeLayout = iblPipeLayoutResult.Value;

		// Irradiance compute pipeline
		let irradCS = initCtx.Shaders.GetCompiledShader("ibl_irradiance", .Compute);
		if (irradCS case .Err) return .Err;
		let irradPipeResult = mDevice.CreateComputePipeline(ComputePipelineDesc()
		{
			Layout = mIBLComputeLayout,
			Compute = ProgrammableStage() { Module = irradCS.Value, EntryPoint = "CSMain" },
			Label = "IBL_IrradiancePipeline"
		});
		if (irradPipeResult case .Err) return .Err;
		mIrradiancePipeline = irradPipeResult.Value;

		// Prefilter compute pipeline
		let prefiltCS = initCtx.Shaders.GetCompiledShader("ibl_prefilter", .Compute);
		if (prefiltCS case .Err) return .Err;
		let prefiltPipeResult = mDevice.CreateComputePipeline(ComputePipelineDesc()
		{
			Layout = mIBLComputeLayout,
			Compute = ProgrammableStage() { Module = prefiltCS.Value, EntryPoint = "CSMain" },
			Label = "IBL_PrefilterPipeline"
		});
		if (prefiltPipeResult case .Err) return .Err;
		mPrefilterPipeline = prefiltPipeResult.Value;

		return .Ok;
	}

	/// Bakes IBL cubemaps from the loaded HDRI. Call after SetHdriTexture and
	/// after the HDRI texture is uploaded to the GPU.
	/// Requires a command encoder (pre-graph).
	public void BakeIBL(ICommandEncoder encoder)
	{
		if (!mLoaded || mIrradiancePipeline == null || mPrefilterPipeline == null || mIBLBaked)
			return;

		// Queue previous bake's temp resources for deferred deletion
		let frameNum = mSystem.FrameCtx.FrameNumber;
		let deletionQueue = mSystem.DeferredDeletions;
		for (let bg in mBakeTempBindGroups)
			deletionQueue.Enqueue(frameNum, bg);
		mBakeTempBindGroups.Clear();
		for (let view in mBakeTempViews)
			deletionQueue.Enqueue(frameNum, view);
		mBakeTempViews.Clear();

		// Barrier: InitialState (first bake) or ShaderRead (re-bake) → ShaderWrite
		int preBarrierCount = 2;
		TextureBarrier[3] preBarriers = .(
			.() { Texture = mIrradianceCubemap,
				OldState = mIBLBakedOnce ? ResourceState.ShaderRead : mIrradianceCubemap.InitialState,
				NewState = .ShaderWrite },
			.() { Texture = mPrefilteredCubemap,
				OldState = mIBLBakedOnce ? ResourceState.ShaderRead : mPrefilteredCubemap.InitialState,
				NewState = .ShaderWrite },
			default
		);
		// First bake: also transition fallback BRDF LUT to ShaderRead (it's bound in scene bind group)
		if (!mIBLBakedOnce && mFallbackBrdfLut != null)
		{
			preBarriers[2] = .() { Texture = mFallbackBrdfLut, OldState = mFallbackBrdfLut.InitialState, NewState = .ShaderRead };
			preBarrierCount = 3;
		}
		encoder.Barrier(BarrierGroup()
		{
			TextureBarriers = Span<TextureBarrier>(&preBarriers[0], preBarrierCount)
		});

		// Create one UAV per unique mip level (irradiance has 1 mip, prefiltered has 5)
		// Irradiance: single UAV for mip 0
		let irradUAV = CreateUAV(mIrradianceCubemap, 0);

		// --- Bake irradiance cubemap (32x32, 6 faces) ---
		if (irradUAV != null)
		{
			let bg = CreateBakeBindGroup(irradUAV);
			if (bg != null)
			{
				for (uint32 face = 0; face < 6; face++)
				{
					IBLPushParams p = .() { FaceIndex = face, CubemapSize = 32, Roughness = 0.0f };
					let cp = encoder.BeginComputePass("IBL_Irradiance");
					cp.SetPipeline(mIrradiancePipeline);
					cp.SetBindGroup(0, bg);
					cp.SetPushConstants(.Compute, 0, (uint32)sizeof(IBLPushParams), &p);
					cp.Dispatch(4, 4); // 32/8 = 4
					cp.End();
				}
			}
		}

		// --- Bake prefiltered cubemap (128x128, 5 mip levels, 6 faces) ---
		for (uint32 mip = 0; mip < 5; mip++)
		{
			let mipSize = (uint32)(128 >> mip);
			let roughness = (float)mip / 4.0f;

			let prefiltUAV = CreateUAV(mPrefilteredCubemap, mip);
			if (prefiltUAV == null) continue;

			let bg = CreateBakeBindGroup(prefiltUAV);
			if (bg == null) continue;

			for (uint32 face = 0; face < 6; face++)
			{
				IBLPushParams p = .() { FaceIndex = face, CubemapSize = mipSize, Roughness = roughness };
				let cp = encoder.BeginComputePass("IBL_Prefilter");
				cp.SetPipeline(mPrefilterPipeline);
				cp.SetBindGroup(0, bg);
				cp.SetPushConstants(.Compute, 0, (uint32)sizeof(IBLPushParams), &p);
				let groups = Math.Max((mipSize + 7) / 8, 1u);
				cp.Dispatch(groups, groups);
				cp.End();
			}
		}

		// Barrier: ShaderWrite → ShaderRead for both cubemaps
		TextureBarrier[2] postBarriers = .(
			.() { Texture = mIrradianceCubemap, OldState = .ShaderWrite, NewState = .ShaderRead },
			.() { Texture = mPrefilteredCubemap, OldState = .ShaderWrite, NewState = .ShaderRead }
		);
		encoder.Barrier(BarrierGroup()
		{
			TextureBarriers = Span<TextureBarrier>(&postBarriers[0], 2)
		});

		mIBLBaked = true;
		mIBLBakedOnce = true;
	}

	private ITextureView CreateUAV(ITexture tex, uint32 mipLevel)
	{
		let result = mDevice.CreateTextureView(tex, TextureViewDesc()
		{
			Dimension = .Texture2DArray,
			BaseMipLevel = mipLevel,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 6,
			Label = "IBL_UAV"
		});
		if (result case .Ok(let view))
		{
			mBakeTempViews.Add(view);
			return view;
		}
		return null;
	}

	private IBindGroup CreateBakeBindGroup(ITextureView uavView)
	{
		BindGroupEntry[3] entries = .(
			BindGroupEntry.Texture(mHdriTextureView),
			BindGroupEntry.Sampler(mHdriSampler),
			BindGroupEntry.Texture(uavView)
		);
		let result = mDevice.CreateBindGroup(BindGroupDesc()
		{
			Layout = mIBLComputeBindGroupLayout,
			Entries = entries,
			Label = "IBL_ComputeBindGroup"
		});
		if (result case .Ok(let bg))
		{
			mBakeTempBindGroups.Add(bg);
			return bg;
		}
		return null;
	}

	public void OnRecordPreGraph(ICommandEncoder encoder)
	{
		SyncFromWorld();

		// First frame without HDRI: transition IBL cubemaps to ShaderRead so
		// they're in a valid state for the scene bind group.
		// Skip when BakeIBL will run (mLoaded=true) — it handles its own transitions.
		if (!mIBLBakedOnce && !mIBLInitBarrierDone && !mLoaded)
		{
			TextureBarrier[3] initBarriers = .();
			int count = 0;
			if (mIrradianceCubemap != null)
				initBarriers[count++] = .() { Texture = mIrradianceCubemap, OldState = mIrradianceCubemap.InitialState, NewState = .ShaderRead };
			if (mPrefilteredCubemap != null)
				initBarriers[count++] = .() { Texture = mPrefilteredCubemap, OldState = mPrefilteredCubemap.InitialState, NewState = .ShaderRead };
			if (mFallbackBrdfLut != null)
				initBarriers[count++] = .() { Texture = mFallbackBrdfLut, OldState = mFallbackBrdfLut.InitialState, NewState = .ShaderRead };
			if (count > 0)
				encoder.Barrier(BarrierGroup() { TextureBarriers = Span<TextureBarrier>(&initBarriers[0], count) });
			mIBLInitBarrierDone = true;
		}

		BakeIBL(encoder);
	}

	public void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx)
	{
		if (!mLoaded || mPipeline == null) return;

		let opaqueFeature = mSystem.GetFeature<ForwardOpaqueFeature>();
		if (opaqueFeature == null) return;
		let sceneColor = opaqueFeature.SceneColorTexture;
		if (!sceneColor.IsValid) return;

		let depthPrepass = mSystem.GetFeature<DepthPrepassFeature>();
		if (depthPrepass == null) return;
		let depthTex = depthPrepass.DepthTexture;
		if (!depthTex.IsValid) return;

		let system = mSystem;
		let device = mDevice;
		let pipeline = mPipeline;
		let hdriTextureView = mHdriTextureView;
		let hdriSampler = mHdriSampler;
		let skyBindGroupLayout = mSkyBindGroupLayout;
		let renderW = viewCtx.RenderWidth;
		let renderH = viewCtx.RenderHeight;
		let frameIndex = system.FrameIndex;

		graph.AddPass("Sky", .Graphics, scope [&] (builder) =>
		{
			// Write on top of scene color (Load existing opaque/transparent content)
			builder.WriteRenderTarget(sceneColor, 0, .Load, .Store);
			// Read depth to discard non-sky pixels
			builder.ReadTexture(depthTex, .Fragment);
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				// Build sky bind group with resolved depth texture
				let resolvedDepthView = registry.GetTextureView(depthTex);
				if (resolvedDepthView == null) return;

				if (mSkyBindGroups[frameIndex] != null)
					device.DestroyBindGroup(ref mSkyBindGroups[frameIndex]);

				BindGroupEntry[3] entries = .(
					BindGroupEntry.Texture(hdriTextureView),
					BindGroupEntry.Sampler(hdriSampler),
					BindGroupEntry.Texture(resolvedDepthView)
				);
				let bgResult = device.CreateBindGroup(BindGroupDesc()
				{
					Layout = skyBindGroupLayout,
					Entries = entries,
					Label = "Sky_BindGroup"
				});
				if (bgResult case .Err) return;
				mSkyBindGroups[frameIndex] = bgResult.Value;

				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);

				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
				rp.SetScissor(0, 0, renderW, renderH);
				rp.SetPipeline(pipeline);

				if (system.SceneBindGroup != null)
					rp.SetBindGroup(0, system.SceneBindGroup);
				rp.SetBindGroup(1, mSkyBindGroups[frameIndex]);

				// Full-screen triangle
				rp.Draw(3, 1, 0, 0);

				rp.End();
			});
		});
	}

	public void OnPostRender() { }

	public void OnShutdown(IDevice device)
	{
		// Clean up bake temp resources directly (GPU is idle at shutdown)
		for (let bg in mBakeTempBindGroups)
		{
			var bgRef = bg;
			device.DestroyBindGroup(ref bgRef);
		}
		mBakeTempBindGroups.Clear();
		for (let view in mBakeTempViews)
		{
			var viewRef = view;
			device.DestroyTextureView(ref viewRef);
		}
		mBakeTempViews.Clear();

		if (mPipeline != null) device.DestroyRenderPipeline(ref mPipeline);
		if (mPipelineLayout != null) device.DestroyPipelineLayout(ref mPipelineLayout);
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			if (mSkyBindGroups[i] != null) device.DestroyBindGroup(ref mSkyBindGroups[i]);
		if (mSkyBindGroupLayout != null) device.DestroyBindGroupLayout(ref mSkyBindGroupLayout);
		if (mHdriSampler != null) device.DestroySampler(ref mHdriSampler);
		// mHdriTextureView, mHdriTexture, and mBrdfLutView are owned by the caller

		// IBL resources (owned)
		if (mPrefilterPipeline != null) device.DestroyComputePipeline(ref mPrefilterPipeline);
		if (mIrradiancePipeline != null) device.DestroyComputePipeline(ref mIrradiancePipeline);
		if (mIBLComputeLayout != null) device.DestroyPipelineLayout(ref mIBLComputeLayout);
		if (mIBLComputeBindGroupLayout != null) device.DestroyBindGroupLayout(ref mIBLComputeBindGroupLayout);
		if (mIBLSampler != null) device.DestroySampler(ref mIBLSampler);
		if (mPrefilteredCubemapView != null) device.DestroyTextureView(ref mPrefilteredCubemapView);
		if (mPrefilteredCubemap != null) device.DestroyTexture(ref mPrefilteredCubemap);
		if (mIrradianceCubemapView != null) device.DestroyTextureView(ref mIrradianceCubemapView);
		if (mIrradianceCubemap != null) device.DestroyTexture(ref mIrradianceCubemap);
		if (mFallbackBrdfLutView != null) device.DestroyTextureView(ref mFallbackBrdfLutView);
		if (mFallbackBrdfLut != null) device.DestroyTexture(ref mFallbackBrdfLut);
	}
}

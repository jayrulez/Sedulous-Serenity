namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// Hi-Z params uploaded per mip level dispatch.
[CRepr]
struct HiZParams
{
	public uint32[2] OutputSize;
	public uint32[2] InputSize;
	public uint32 MipLevel;
	public uint32[3] _pad;
}

/// Generates a hierarchical-Z (Hi-Z) depth pyramid from the depth prepass output.
/// Each mip level stores the max depth in a 2x2 texel group (conservative).
/// Used by GPU occlusion culling to quickly reject objects behind large occluders.
class HiZPyramid
{
	private IDevice mDevice;

	// Compute pipelines — two variants:
	// Mip 0: reads depth as SampledTexture (HIZ_MIP0 define)
	// Mip 1+: reads previous Hi-Z mip as StorageTexture
	private IComputePipeline mPipelineMip0;
	private IComputePipeline mPipelineMipN;
	private IBindGroupLayout mLayoutMip0;     // t1=SampledTexture, u2=StorageTexture
	private IBindGroupLayout mLayoutMipN;     // u1=StorageTexture, u2=StorageTexture
	private IPipelineLayout mPipeLayoutMip0;
	private IPipelineLayout mPipeLayoutMipN;

	// Hi-Z texture with full mip chain
	private ITexture mHiZTexture;
	private ITextureView mHiZFullView;         // SRV for all mips (used by cull compute)
	private ITextureView[] mMipViews ~ delete _;  // Per-mip SRVs for reading previous level
	private ISampler mPointSampler;

	// Per-mip dispatch bind groups (rebuilt each frame with correct input/output views)
	private IBindGroup[] mDispatchBindGroups ~ delete _;

	// Per-mip params UBOs (CpuToGpu, one per mip to avoid GPU read-after-CPU-write races)
	private IBuffer[] mParamsBuffers ~ delete _;
	private void*[] mParamsPtrs ~ delete _;

	private uint32 mWidth;
	private uint32 mHeight;
	private uint32 mMipCount;
	private bool mInitialized;
	/// True after first successful Hi-Z generation (texture is in ShaderRead state).
	public bool Generated;

	/// The Hi-Z texture view (all mips) for binding in the cull compute shader.
	public ITextureView HiZView => mHiZFullView;

	/// The Hi-Z texture for barrier management.
	public ITexture HiZTexture => mHiZTexture;

	/// Number of mip levels in the pyramid.
	public uint32 MipCount => mMipCount;

	/// Point sampler for Hi-Z reads (exposed for cull compute bind group).
	public ISampler PointSampler => mPointSampler;

	public Result<void> Initialize(IDevice device, ShaderLibrary shaderLib)
	{
		mDevice = device;

		if (shaderLib.RegisterShader("hiz_generate") case .Err)
			return .Err;

		// Point sampler (used by cull compute for Hi-Z reads)
		let samplerResult = device.CreateSampler(SamplerDesc()
		{
			MinFilter = .Nearest, MagFilter = .Nearest, MipmapFilter = .Nearest,
			AddressU = .ClampToEdge, AddressV = .ClampToEdge, AddressW = .ClampToEdge,
			Label = "HiZ_PointSampler"
		});
		if (samplerResult case .Err) return .Err;
		mPointSampler = samplerResult.Value;

		// --- Mip 0 layout: b0=UBO, t1=SampledTexture(depth), u2=StorageTexture(output) ---
		BindGroupLayoutEntry[3] mip0Entries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Compute),
			BindGroupLayoutEntry.SampledTexture(1, .Compute, .Texture2D),
			BindGroupLayoutEntry.StorageTexture(2, .Compute, .R32Float, readWrite: true, .Texture2D)
		);
		let layout0Result = device.CreateBindGroupLayout(BindGroupLayoutDesc()
			{ Entries = mip0Entries, Label = "HiZ_Mip0Layout" });
		if (layout0Result case .Err) return .Err;
		mLayoutMip0 = layout0Result.Value;

		IBindGroupLayout[1] bg0 = .(mLayoutMip0);
		let pipeLayout0Result = device.CreatePipelineLayout(PipelineLayoutDesc()
			{ BindGroupLayouts = bg0, Label = "HiZ_Mip0PipeLayout" });
		if (pipeLayout0Result case .Err) return .Err;
		mPipeLayoutMip0 = pipeLayout0Result.Value;

		// --- Mip N layout: b0=UBO, u1=StorageTexture(input), u2=StorageTexture(output) ---
		BindGroupLayoutEntry[3] mipNEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Compute),
			BindGroupLayoutEntry.StorageTexture(1, .Compute, .R32Float, readWrite: true, .Texture2D),
			BindGroupLayoutEntry.StorageTexture(2, .Compute, .R32Float, readWrite: true, .Texture2D)
		);
		let layoutNResult = device.CreateBindGroupLayout(BindGroupLayoutDesc()
			{ Entries = mipNEntries, Label = "HiZ_MipNLayout" });
		if (layoutNResult case .Err) return .Err;
		mLayoutMipN = layoutNResult.Value;

		IBindGroupLayout[1] bgN = .(mLayoutMipN);
		let pipeLayoutNResult = device.CreatePipelineLayout(PipelineLayoutDesc()
			{ BindGroupLayouts = bgN, Label = "HiZ_MipNPipeLayout" });
		if (pipeLayoutNResult case .Err) return .Err;
		mPipeLayoutMipN = pipeLayoutNResult.Value;

		// --- Compile two pipeline variants ---
		let mip0Module = shaderLib.GetCompiledShader("hiz_generate", .Compute, .HiZMip0);
		if (mip0Module case .Err) return .Err;
		let mipNModule = shaderLib.GetCompiledShader("hiz_generate", .Compute);
		if (mipNModule case .Err) return .Err;

		let pipe0Result = device.CreateComputePipeline(ComputePipelineDesc()
		{
			Layout = mPipeLayoutMip0,
			Compute = ProgrammableStage() { Module = mip0Module.Value, EntryPoint = "CSMain" },
			Label = "HiZ_Mip0Pipeline"
		});
		if (pipe0Result case .Err) return .Err;
		mPipelineMip0 = pipe0Result.Value;

		let pipeNResult = device.CreateComputePipeline(ComputePipelineDesc()
		{
			Layout = mPipeLayoutMipN,
			Compute = ProgrammableStage() { Module = mipNModule.Value, EntryPoint = "CSMain" },
			Label = "HiZ_MipNPipeline"
		});
		if (pipeNResult case .Err) return .Err;
		mPipelineMipN = pipeNResult.Value;

		mInitialized = true;
		return .Ok;
	}

	/// Creates or recreates the Hi-Z texture when the depth buffer size changes.
	public Result<void> EnsureTexture(uint32 depthWidth, uint32 depthHeight)
	{
		// Hi-Z is half the depth buffer resolution (mip 0 = half res)
		let hizW = Math.Max(depthWidth / 2, 1);
		let hizH = Math.Max(depthHeight / 2, 1);

		if (mHiZTexture != null && mWidth == hizW && mHeight == hizH)
			return .Ok; // Already correct size

		// Cleanup old resources
		DestroyTextureResources();

		mWidth = hizW;
		mHeight = hizH;
		Generated = false;
		mMipCount = CalculateMipCount(hizW, hizH);

		// Create Hi-Z texture with mip chain
		let texResult = mDevice.CreateTexture(TextureDesc()
		{
			Dimension = .Texture2D,
			Format = .R32Float,
			Width = hizW,
			Height = hizH,
			ArrayLayerCount = 1,
			MipLevelCount = mMipCount,
			SampleCount = 1,
			Usage = .Sampled | .Storage,
			Label = "HiZ_Pyramid"
		});
		if (texResult case .Err) return .Err;
		mHiZTexture = texResult.Value;

		// Full view (all mips) for cull compute SRV
		let fullViewResult = mDevice.CreateTextureView(mHiZTexture, TextureViewDesc()
		{
			Format = .R32Float,
			Dimension = .Texture2D,
			MipLevelCount = mMipCount,
			Label = "HiZ_FullView"
		});
		if (fullViewResult case .Err) return .Err;
		mHiZFullView = fullViewResult.Value;

		// Per-mip views for reading previous level as SRV
		mMipViews = new ITextureView[mMipCount];
		for (uint32 i = 0; i < mMipCount; i++)
		{
			let viewResult = mDevice.CreateTextureView(mHiZTexture, TextureViewDesc()
			{
				Format = .R32Float,
				Dimension = .Texture2D,
				BaseMipLevel = i,
				MipLevelCount = 1,
				Label = "HiZ_MipView"
			});
			if (viewResult case .Err) return .Err;
			mMipViews[i] = viewResult.Value;
		}

		// Pre-allocate dispatch bind groups and per-mip params buffers
		mDispatchBindGroups = new IBindGroup[mMipCount];
		mParamsBuffers = new IBuffer[mMipCount];
		mParamsPtrs = new void*[mMipCount];
		for (uint32 i = 0; i < mMipCount; i++)
		{
			let paramsResult = mDevice.CreateBuffer(BufferDesc()
			{
				Size = (uint64)sizeof(HiZParams),
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "HiZ_Params"
			});
			if (paramsResult case .Err) return .Err;
			mParamsBuffers[i] = paramsResult.Value;
			mParamsPtrs[i] = mParamsBuffers[i].Map();
		}

		return .Ok;
	}

	/// Adds a render graph compute pass that generates the Hi-Z pyramid
	/// from the depth prepass output. Call from DepthPrepassFeature.OnAddPasses.
	public void AddGraphPass(RenderGraph graph, RGTexture depthTexture,
		uint32 depthWidth, uint32 depthHeight)
	{
		if (!mInitialized || mPipelineMip0 == null) return;

		// Ensure Hi-Z texture matches depth buffer dimensions
		if (EnsureTexture(depthWidth, depthHeight) case .Err) return;

		graph.AddPass("HiZGenerate", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(depthTexture, .Compute);
			builder.HasSideEffects();

			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let depthView = registry.GetTextureView(depthTexture);
				if (depthView == null) return;
				RecordGenerate(encoder, depthView);
			});
		});
	}

	/// Records the Hi-Z pyramid generation passes.
	/// Call after the depth prepass has completed.
	/// depthView: the resolved depth buffer texture view from the depth prepass.
	public void RecordGenerate(ICommandEncoder encoder, ITextureView depthView)
	{
		if (!mInitialized || mHiZTexture == null || mPipelineMip0 == null || mPipelineMipN == null || depthView == null || mParamsBuffers == null)
			return;

		// Transition entire Hi-Z texture to ShaderWrite (GENERAL on Vulkan).
		// Mip 1+ input and output both use GENERAL layout (StorageTexture).
		{
			TextureBarrier[1] barrier = .(.()
			{
				Texture = mHiZTexture,
				OldState = Generated ? .ShaderRead : .Undefined,
				NewState = .ShaderWrite
			});
			encoder.Barrier(BarrierGroup()
			{
				TextureBarriers = Span<TextureBarrier>(&barrier[0], 1)
			});
		}

		uint32 inputW = mWidth * 2;
		uint32 inputH = mHeight * 2;

		for (uint32 mip = 0; mip < mMipCount; mip++)
		{
			let outputW = Math.Max(mWidth >> mip, (uint32)1);
			let outputH = Math.Max(mHeight >> mip, (uint32)1);

			if (mParamsPtrs[mip] != null)
			{
				var hizParams = HiZParams();
				hizParams.OutputSize = .(outputW, outputH);
				hizParams.InputSize = .(inputW, inputH);
				hizParams.MipLevel = mip;
				Internal.MemCpy(mParamsPtrs[mip], &hizParams, sizeof(HiZParams));
			}

			if (mDispatchBindGroups[mip] != null)
				mDevice.DestroyBindGroup(ref mDispatchBindGroups[mip]);

			if (mip == 0)
			{
				// Mip 0: read depth as SampledTexture, write Hi-Z mip 0 as StorageTexture
				BindGroupEntry[3] bgEntries = .(
					BindGroupEntry.Buffer(mParamsBuffers[mip]),
					BindGroupEntry.Texture(depthView),          // t1: depth SRV
					BindGroupEntry.Texture(mMipViews[0])        // u2: output UAV
				);
				let bgResult = mDevice.CreateBindGroup(BindGroupDesc()
					{ Layout = mLayoutMip0, Entries = bgEntries, Label = "HiZ_Mip0BindGroup" });
				if (bgResult case .Err) continue;
				mDispatchBindGroups[0] = bgResult.Value;

				let cp = encoder.BeginComputePass("HiZMip0");
				cp.SetPipeline(mPipelineMip0);
				cp.SetBindGroup(0, mDispatchBindGroups[0]);
				cp.Dispatch((outputW + 7) / 8, (outputH + 7) / 8);
				cp.End();
			}
			else
			{
				// Mip N: read previous mip as StorageTexture, write current mip as StorageTexture
				// Both in GENERAL layout — no layout transition needed between dispatches
				BindGroupEntry[3] bgEntries = .(
					BindGroupEntry.Buffer(mParamsBuffers[mip]),
					BindGroupEntry.Texture(mMipViews[mip - 1]),  // u1: prev mip UAV
					BindGroupEntry.Texture(mMipViews[mip])       // u2: output UAV
				);
				let bgResult = mDevice.CreateBindGroup(BindGroupDesc()
					{ Layout = mLayoutMipN, Entries = bgEntries, Label = "HiZ_MipNBindGroup" });
				if (bgResult case .Err) continue;
				mDispatchBindGroups[mip] = bgResult.Value;

				let cp = encoder.BeginComputePass("HiZMipN");
				cp.SetPipeline(mPipelineMipN);
				cp.SetBindGroup(0, mDispatchBindGroups[mip]);
				cp.Dispatch((outputW + 7) / 8, (outputH + 7) / 8);
				cp.End();
			}

			// Memory barrier between mip dispatches
			if (mip + 1 < mMipCount)
			{
				TextureBarrier[1] barrier = .(.()
				{
					Texture = mHiZTexture,
					OldState = .ShaderWrite,
					NewState = .ShaderWrite
				});
				encoder.Barrier(BarrierGroup()
				{
					TextureBarriers = Span<TextureBarrier>(&barrier[0], 1)
				});
			}

			inputW = outputW;
			inputH = outputH;
		}

		// Final: entire texture ShaderWrite → ShaderRead (for cull compute next frame)
		{
			TextureBarrier[1] barrier = .(.()
			{
				Texture = mHiZTexture,
				OldState = .ShaderWrite,
				NewState = .ShaderRead
			});
			encoder.Barrier(BarrierGroup()
			{
				TextureBarriers = Span<TextureBarrier>(&barrier[0], 1)
			});
		}

		Generated = true;
	}

	private void DestroyTextureResources()
	{
		if (mDispatchBindGroups != null)
		{
			for (int i = 0; i < mDispatchBindGroups.Count; i++)
			{
				if (mDispatchBindGroups[i] != null)
					mDevice.DestroyBindGroup(ref mDispatchBindGroups[i]);
			}
			DeleteAndNullify!(mDispatchBindGroups);
		}

		if (mParamsBuffers != null)
		{
			for (int i = 0; i < mParamsBuffers.Count; i++)
			{
				if (mParamsBuffers[i] != null)
				{
					mParamsBuffers[i].Unmap();
					mDevice.DestroyBuffer(ref mParamsBuffers[i]);
				}
			}
			DeleteAndNullify!(mParamsBuffers);
			DeleteAndNullify!(mParamsPtrs);
		}

		if (mMipViews != null)
		{
			for (int i = 0; i < mMipViews.Count; i++)
			{
				if (mMipViews[i] != null)
					mDevice.DestroyTextureView(ref mMipViews[i]);
			}
			DeleteAndNullify!(mMipViews);
		}

		if (mHiZFullView != null)
			mDevice.DestroyTextureView(ref mHiZFullView);
		if (mHiZTexture != null)
			mDevice.DestroyTexture(ref mHiZTexture);
	}

	private static uint32 CalculateMipCount(uint32 width, uint32 height)
	{
		let maxDim = Math.Max(width, height);
		uint32 mips = 1;
		uint32 dim = maxDim;
		while (dim > 1) { dim >>= 1; mips++; }
		return mips;
	}

	public void Shutdown()
	{
		DestroyTextureResources();

		if (mPipelineMip0 != null) mDevice.DestroyComputePipeline(ref mPipelineMip0);
		if (mPipelineMipN != null) mDevice.DestroyComputePipeline(ref mPipelineMipN);
		if (mPipeLayoutMip0 != null) mDevice.DestroyPipelineLayout(ref mPipeLayoutMip0);
		if (mPipeLayoutMipN != null) mDevice.DestroyPipelineLayout(ref mPipeLayoutMipN);
		if (mLayoutMip0 != null) mDevice.DestroyBindGroupLayout(ref mLayoutMip0);
		if (mLayoutMipN != null) mDevice.DestroyBindGroupLayout(ref mLayoutMipN);
		if (mPointSampler != null) mDevice.DestroySampler(ref mPointSampler);
	}
}

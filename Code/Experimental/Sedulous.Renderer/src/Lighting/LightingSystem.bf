namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;

using internal Sedulous.Renderer;

/// Manages GPU light data and clustered light culling for the renderer.
/// Owned by RenderSystem as shared scene-level infrastructure.
/// Uploads light proxy data to storage buffers each frame, then dispatches
/// a compute pass to assign lights to clusters for Forward+ rendering.
class LightingSystem
{
	private IDevice mDevice;

	// --- Light data buffers ---
	// Staging buffers (CpuToGpu) — CPU writes light data here
	private IBuffer[RenderConfig.FrameBufferCount] mStagingBuffers;
	private void*[RenderConfig.FrameBufferCount] mMappedPtrs;
	// GPU storage buffers (GpuOnly) — shaders read from here
	private IBuffer[RenderConfig.FrameBufferCount] mLightBuffers;

	// --- Cluster culling buffers (per-frame) ---
	private IBuffer[RenderConfig.FrameBufferCount] mClusterBuffers;
	private IBuffer[RenderConfig.FrameBufferCount] mLightIndexBuffers;
	private IBuffer[RenderConfig.FrameBufferCount] mAtomicCounterBuffers;
	// Small staging buffer with a zero uint32 for clearing the atomic counter
	private IBuffer mZeroStagingBuffer;
	private void* mZeroStagingPtr;

	// --- Compute pipeline ---
	private IBindGroupLayout mCullBindGroupLayout;
	private IPipelineLayout mCullPipelineLayout;
	private IComputePipeline mCullPipeline;
	private IBindGroup[RenderConfig.FrameBufferCount] mCullBindGroups;

	private int mActiveLightCount;
	private bool mFirstFrame = true;

	private const int TotalClusters = RenderConfig.ClusterCountX * RenderConfig.ClusterCountY * RenderConfig.ClusterCountZ;

	/// Number of lights uploaded this frame.
	public int ActiveLightCount => mActiveLightCount;

	/// Gets the light data storage buffer for the given frame index.
	public IBuffer GetLightBuffer(int frameIndex) => mLightBuffers[frameIndex];

	/// Gets the cluster grid buffer for the given frame index.
	public IBuffer GetClusterBuffer(int frameIndex) => mClusterBuffers[frameIndex];

	/// Gets the light index buffer for the given frame index.
	public IBuffer GetLightIndexBuffer(int frameIndex) => mLightIndexBuffers[frameIndex];

	public Result<void> Initialize(IDevice device, ShaderLibrary shaderLib)
	{
		mDevice = device;

		// --- Light data buffers ---
		let lightBufSize = (uint64)(RenderConfig.MaxLights * sizeof(GPULightData));
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			// Staging buffer — CPU-writable
			let stagingResult = device.CreateBuffer(BufferDesc()
			{
				Size = lightBufSize,
				Usage = .CopySrc,
				Memory = .CpuToGpu,
				Label = "LightBuffer_Staging"
			});
			if (stagingResult case .Err)
				return .Err;
			mStagingBuffers[i] = stagingResult.Value;
			mMappedPtrs[i] = mStagingBuffers[i].Map();

			// GPU storage buffer — shader-readable
			let gpuResult = device.CreateBuffer(BufferDesc()
			{
				Size = lightBufSize,
				Usage = .Storage | .CopyDst,
				Memory = .GpuOnly,
				Label = "LightBuffer"
			});
			if (gpuResult case .Err)
				return .Err;
			mLightBuffers[i] = gpuResult.Value;
		}

		// --- Cluster culling buffers ---
		let clusterBufSize = (uint64)(TotalClusters * 8); // 2 x uint32 per cluster
		let lightIndexBufSize = (uint64)(TotalClusters * RenderConfig.MaxLightsPerCluster * sizeof(uint32));
		let counterSize = (uint64)sizeof(uint32);

		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			let clusterResult = device.CreateBuffer(BufferDesc()
			{
				Size = clusterBufSize,
				Usage = .Storage | .CopyDst,
				Memory = .GpuOnly,
				Label = "ClusterGrid"
			});
			if (clusterResult case .Err)
				return .Err;
			mClusterBuffers[i] = clusterResult.Value;

			let indexResult = device.CreateBuffer(BufferDesc()
			{
				Size = lightIndexBufSize,
				Usage = .Storage,
				Memory = .GpuOnly,
				Label = "LightIndexList"
			});
			if (indexResult case .Err)
				return .Err;
			mLightIndexBuffers[i] = indexResult.Value;

			let counterResult = device.CreateBuffer(BufferDesc()
			{
				Size = counterSize,
				Usage = .Storage | .CopyDst,
				Memory = .GpuOnly,
				Label = "AtomicCounter"
			});
			if (counterResult case .Err)
				return .Err;
			mAtomicCounterBuffers[i] = counterResult.Value;
		}

		// Zero staging buffer for clearing the atomic counter
		{
			let result = device.CreateBuffer(BufferDesc()
			{
				Size = counterSize,
				Usage = .CopySrc,
				Memory = .CpuToGpu,
				Label = "ZeroStaging"
			});
			if (result case .Err)
				return .Err;
			mZeroStagingBuffer = result.Value;
			mZeroStagingPtr = mZeroStagingBuffer.Map();
			if (mZeroStagingPtr != null)
				*(uint32*)mZeroStagingPtr = 0;
		}

		// --- Compute pipeline ---
		if (CreateComputePipeline(device, shaderLib) case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateComputePipeline(IDevice device, ShaderLibrary shaderLib)
	{
		// Bind group layout for compute culling pass
		BindGroupLayoutEntry[5] entries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Compute),                       // SceneUniforms
			BindGroupLayoutEntry.StorageBuffer(1, .Compute, readWrite: false),     // LightBuffer (read)
			BindGroupLayoutEntry.StorageBuffer(2, .Compute, readWrite: true),      // ClusterGrid (write)
			BindGroupLayoutEntry.StorageBuffer(3, .Compute, readWrite: true),      // LightIndexList (write)
			BindGroupLayoutEntry.StorageBuffer(4, .Compute, readWrite: true)       // AtomicCounter (rw)
		);

		let layoutResult = device.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = entries,
			Label = "CullBindGroupLayout"
		});
		if (layoutResult case .Err)
			return .Err;
		mCullBindGroupLayout = layoutResult.Value;

		// Pipeline layout
		IBindGroupLayout[1] bgLayouts = .(mCullBindGroupLayout);
		let pipeLayoutResult = device.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = bgLayouts,
			Label = "CullPipelineLayout"
		});
		if (pipeLayoutResult case .Err)
			return .Err;
		mCullPipelineLayout = pipeLayoutResult.Value;

		// Compile compute shader
		if (shaderLib.RegisterShader("light_cull") case .Err)
			return .Err;

		let shaderModule = shaderLib.GetCompiledShader("light_cull", .Compute);
		if (shaderModule case .Err)
			return .Err;

		// Create compute pipeline
		let pipeResult = device.CreateComputePipeline(ComputePipelineDesc()
		{
			Layout = mCullPipelineLayout,
			Compute = ProgrammableStage()
			{
				Module = shaderModule.Value,
				EntryPoint = "CSMain"
			},
			Label = "LightCullPipeline"
		});
		if (pipeResult case .Err)
			return .Err;
		mCullPipeline = pipeResult.Value;

		return .Ok;
	}

	/// Writes light data from the render world to the staging buffer.
	/// Call before UploadUniforms so LightCount is available.
	/// shadowSystem is used to query atlas shadow indices for point/spot lights.
	public void Update(RenderWorld world, int frameIndex, ShadowSystem shadowSystem = null)
	{
		mActiveLightCount = 0;

		if (world == null)
			return;

		let ptr = (GPULightData*)mMappedPtrs[frameIndex];
		if (ptr == null)
			return;

		world.Lights.ForEach(scope [&] (handle, proxy) =>
		{
			if (mActiveLightCount >= RenderConfig.MaxLights)
				return;

			uint32 atlasShadowIndex = uint32.MaxValue;
			if (shadowSystem != null && proxy.CastShadows && proxy.Type != .Directional)
				atlasShadowIndex = shadowSystem.GetAtlasShadowIndex((uint64)handle.Index);

			ptr[mActiveLightCount] = GPULightData.FromProxy(ref proxy, atlasShadowIndex);
			mActiveLightCount++;
		});
	}

	/// Records the staging→GPU copy command. Call on the frame's command encoder.
	public void RecordUpload(ICommandEncoder encoder, int frameIndex)
	{
		if (mActiveLightCount == 0)
			return;

		let copySize = (uint64)(mActiveLightCount * sizeof(GPULightData));
		encoder.CopyBufferToBuffer(mStagingBuffers[frameIndex], 0, mLightBuffers[frameIndex], 0, copySize);
	}

	/// Records the compute light culling pass. Call after RecordUpload.
	public void RecordCull(ICommandEncoder encoder, int frameIndex, IBuffer sceneUniformBuffer)
	{
		// Rebuild bind group for this frame's buffers
		RebuildCullBindGroup(frameIndex, sceneUniformBuffer);

		// Clear atomic counter to 0
		encoder.CopyBufferToBuffer(mZeroStagingBuffer, 0, mAtomicCounterBuffers[frameIndex], 0, (uint64)sizeof(uint32));

		// Pre-compute barriers: transition buffers for compute access
		{
			BufferBarrier[4] barriers = .();
			barriers[0] = BufferBarrier()
			{
				Buffer = mLightBuffers[frameIndex],
				OldState = .CopyDst,
				NewState = .ShaderRead
			};
			barriers[1] = BufferBarrier()
			{
				Buffer = mClusterBuffers[frameIndex],
				OldState = mFirstFrame ? .Undefined : .ShaderRead,
				NewState = .ShaderWrite
			};
			barriers[2] = BufferBarrier()
			{
				Buffer = mLightIndexBuffers[frameIndex],
				OldState = mFirstFrame ? .Undefined : .ShaderRead,
				NewState = .ShaderWrite
			};
			barriers[3] = BufferBarrier()
			{
				Buffer = mAtomicCounterBuffers[frameIndex],
				OldState = .CopyDst,
				NewState = .ShaderWrite
			};
			encoder.Barrier(BarrierGroup()
			{
				BufferBarriers = Span<BufferBarrier>(&barriers[0], 4)
			});
		}

		// Dispatch compute
		let cp = encoder.BeginComputePass("LightCull");
		cp.SetPipeline(mCullPipeline);
		cp.SetBindGroup(0, mCullBindGroups[frameIndex]);
		cp.Dispatch((uint32)((TotalClusters + 63) / 64));
		cp.End();

		// Post-compute barriers: transition cluster/index buffers for fragment reads
		{
			BufferBarrier[2] barriers = .();
			barriers[0] = BufferBarrier()
			{
				Buffer = mClusterBuffers[frameIndex],
				OldState = .ShaderWrite,
				NewState = .ShaderRead
			};
			barriers[1] = BufferBarrier()
			{
				Buffer = mLightIndexBuffers[frameIndex],
				OldState = .ShaderWrite,
				NewState = .ShaderRead
			};
			encoder.Barrier(BarrierGroup()
			{
				BufferBarriers = Span<BufferBarrier>(&barriers[0], 2)
			});
		}

		mFirstFrame = false;
	}

	private void RebuildCullBindGroup(int frameIndex, IBuffer sceneUniformBuffer)
	{
		// Destroy previous bind group for this frame slot
		if (mCullBindGroups[frameIndex] != null)
			mDevice.DestroyBindGroup(ref mCullBindGroups[frameIndex]);

		BindGroupEntry[5] entries = .(
			BindGroupEntry.Buffer(sceneUniformBuffer),
			BindGroupEntry.Buffer(mLightBuffers[frameIndex]),
			BindGroupEntry.Buffer(mClusterBuffers[frameIndex]),
			BindGroupEntry.Buffer(mLightIndexBuffers[frameIndex]),
			BindGroupEntry.Buffer(mAtomicCounterBuffers[frameIndex])
		);

		let result = mDevice.CreateBindGroup(BindGroupDesc()
		{
			Layout = mCullBindGroupLayout,
			Entries = entries,
			Label = "CullBindGroup"
		});

		if (result case .Ok(let bg))
			mCullBindGroups[frameIndex] = bg;
	}

	public void Shutdown()
	{
		if (mDevice == null)
			return;

		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			// Light data buffers
			if (mStagingBuffers[i] != null)
			{
				mStagingBuffers[i].Unmap();
				mMappedPtrs[i] = null;
				mDevice.DestroyBuffer(ref mStagingBuffers[i]);
			}
			if (mLightBuffers[i] != null)
				mDevice.DestroyBuffer(ref mLightBuffers[i]);

			// Cluster culling buffers
			if (mClusterBuffers[i] != null)
				mDevice.DestroyBuffer(ref mClusterBuffers[i]);
			if (mLightIndexBuffers[i] != null)
				mDevice.DestroyBuffer(ref mLightIndexBuffers[i]);
			if (mAtomicCounterBuffers[i] != null)
				mDevice.DestroyBuffer(ref mAtomicCounterBuffers[i]);

			// Compute bind groups
			if (mCullBindGroups[i] != null)
				mDevice.DestroyBindGroup(ref mCullBindGroups[i]);
		}

		// Zero staging buffer
		if (mZeroStagingBuffer != null)
		{
			mZeroStagingBuffer.Unmap();
			mZeroStagingPtr = null;
			mDevice.DestroyBuffer(ref mZeroStagingBuffer);
		}

		// Compute pipeline resources
		if (mCullPipeline != null)
			mDevice.DestroyComputePipeline(ref mCullPipeline);
		if (mCullPipelineLayout != null)
			mDevice.DestroyPipelineLayout(ref mCullPipelineLayout);
		if (mCullBindGroupLayout != null)
			mDevice.DestroyBindGroupLayout(ref mCullBindGroupLayout);
	}
}

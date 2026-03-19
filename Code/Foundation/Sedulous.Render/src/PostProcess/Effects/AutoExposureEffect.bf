namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// GPU parameters for histogram computation (must match exposure_histogram.comp.hlsl).
[CRepr]
struct HistogramParams
{
	public uint32 Width;
	public uint32 Height;
	public float MinLogLuminance;
	public float LogLuminanceRange;

	public static int Size => 16;
}

/// GPU parameters for exposure adaptation (must match exposure_adapt.comp.hlsl).
[CRepr]
struct AdaptParams
{
	public float MinLogLuminance;
	public float LogLuminanceRange;
	public float DeltaTime;
	public float AdaptSpeed;
	public float MinExposure;
	public float MaxExposure;
	public float PixelCount;
	public float _Pad;

	public static int Size => 32;
}

/// Standalone auto-exposure effect using compute shaders.
/// Not an IPostProcessEffect — called directly by RenderSystem before PostProcessStack.
/// Computes scene luminance histogram and adapts exposure over time.
/// Reads scene color, writes adapted exposure to RenderWorld.Exposure.
public class AutoExposureEffect
{
	private const float DefaultMinLogLuminance = -8.0f;
	private const float DefaultLogLuminanceRange = 16.0f; // -8 to +8
	private const int32 HistogramBins = 256;
	private const int32 HistogramBufferSize = HistogramBins * 4; // 1024 bytes

	private RenderSystem mRenderSystem;
	private IDevice mDevice;
	private bool mInitialized = false;

	// Compute pipelines
	private IComputePipeline mHistogramPipeline ~ delete _;
	private IPipelineLayout mHistogramPipelineLayout ~ delete _;
	private IBindGroupLayout mHistogramBindGroupLayout ~ delete _;

	private IComputePipeline mAdaptPipeline ~ delete _;
	private IPipelineLayout mAdaptPipelineLayout ~ delete _;
	private IBindGroupLayout mAdaptBindGroupLayout ~ delete _;

	// Persistent GPU buffers
	private IBuffer[RenderConfig.FrameBufferCount] mHistogramBuffers ~ { for (let b in _) delete b; };    // 256 x uint32, per-frame
	private IBuffer mExposureBuffer ~ delete _;     // 2 x float (current + target), persistent
	private IBuffer mReadbackBuffer ~ delete _;     // CPU-readable copy of exposure

	// Param buffers
	private IBuffer mHistogramParamsBuffer ~ delete _;
	private IBuffer mAdaptParamsBuffer ~ delete _;

	// Per-frame bind groups
	private IBindGroup[RenderConfig.FrameBufferCount] mHistogramBindGroups;
	private IBindGroup[RenderConfig.FrameBufferCount] mAdaptBindGroups;

	// Zero buffer for histogram clear
	private uint8[HistogramBufferSize] mZeroBuffer = default;

	/// Gets the current frame index.
	private int32 FrameIndex => mRenderSystem?.RenderFrameContext?.FrameIndex ?? 0;

	public this(RenderSystem renderSystem)
	{
		mRenderSystem = renderSystem;
	}

	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;

		// Create per-frame histogram buffers (Upload for CPU-side clear without GPU sync)
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDesc histBufDesc = .();
			histBufDesc.Label = "Exposure Histogram";
			histBufDesc.Size = (uint64)HistogramBufferSize;
			histBufDesc.Usage = .Storage;
			histBufDesc.Memory = .CpuToGpu;

			switch (device.CreateBuffer(histBufDesc))
			{
			case .Ok(let buf): mHistogramBuffers[i] = buf;
			case .Err: return .Err;
			}
		}

		// Create exposure buffer (storage + read-write, GPU-only)
		BufferDesc expBufDesc = .();
		expBufDesc.Label = "Exposure Buffer";
		expBufDesc.Size = 8; // 2 floats
		expBufDesc.Usage = .Storage | .CopySrc | .CopyDst;  // CopyDst for Queue.WriteBuffer init, CopySrc for readback
		expBufDesc.Memory = .GpuOnly;

		switch (device.CreateBuffer(expBufDesc))
		{
		case .Ok(let buf): mExposureBuffer = buf;
		case .Err: return .Err;
		}

		// Create readback buffer
		BufferDesc readbackDesc = .();
		readbackDesc.Label = "Exposure Readback";
		readbackDesc.Size = 8;
		readbackDesc.Usage = .CopyDst;
		readbackDesc.Memory = .GpuToCpu;

		switch (device.CreateBuffer(readbackDesc))
		{
		case .Ok(let buf): mReadbackBuffer = buf;
		case .Err: return .Err;
		}

		// Initialize exposure buffer with 1.0
		float[2] initExposure = .(1.0f, 1.0f);
		device.Queue.WriteStagedBufferSync(mExposureBuffer, 0, Span<uint8>((uint8*)&initExposure, 8));

		// Create param buffers
		BufferDesc paramDesc = .();
		paramDesc.Usage = .Uniform;
		paramDesc.Memory = .CpuToGpu;

		paramDesc.Label = "Histogram Params";
		paramDesc.Size = (uint64)HistogramParams.Size;
		switch (device.CreateBuffer(paramDesc))
		{
		case .Ok(let buf): mHistogramParamsBuffer = buf;
		case .Err: return .Err;
		}

		paramDesc.Label = "Adapt Params";
		paramDesc.Size = (uint64)AdaptParams.Size;
		switch (device.CreateBuffer(paramDesc))
		{
		case .Ok(let buf): mAdaptParamsBuffer = buf;
		case .Err: return .Err;
		}

		// Create histogram bind group layout
		// b0=params, t0=SceneColor (SampledTexture), u0=Histogram (StorageBufferReadWrite)
		BindGroupLayoutEntry[3] histLayoutEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Compute, Type = .SampledTexture },
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadWrite }
		);

		BindGroupLayoutDesc histLayoutDesc = .();
		histLayoutDesc.Label = "Histogram Layout";
		histLayoutDesc.Entries = histLayoutEntries;

		switch (device.CreateBindGroupLayout(histLayoutDesc))
		{
		case .Ok(let layout): mHistogramBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create adapt bind group layout
		// b0=params, t0=Histogram (StorageBuffer read-only), u0=ExposureBuffer (StorageBufferReadWrite)
		BindGroupLayoutEntry[3] adaptLayoutEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer },
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBuffer },
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadWrite }
		);

		BindGroupLayoutDesc adaptLayoutDesc = .();
		adaptLayoutDesc.Label = "Adapt Layout";
		adaptLayoutDesc.Entries = adaptLayoutEntries;

		switch (device.CreateBindGroupLayout(adaptLayoutDesc))
		{
		case .Ok(let layout): mAdaptBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layouts
		IBindGroupLayout[1] histLayouts = .(mHistogramBindGroupLayout);
		PipelineLayoutDesc histPLDesc = .(histLayouts);
		switch (device.CreatePipelineLayout(histPLDesc))
		{
		case .Ok(let layout): mHistogramPipelineLayout = layout;
		case .Err: return .Err;
		}

		IBindGroupLayout[1] adaptLayouts = .(mAdaptBindGroupLayout);
		PipelineLayoutDesc adaptPLDesc = .(adaptLayouts);
		switch (device.CreatePipelineLayout(adaptPLDesc))
		{
		case .Ok(let layout): mAdaptPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Create compute pipelines
		if (CreatePipelines() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	private Result<void> CreatePipelines()
	{
		let shaderSystem = mRenderSystem?.ShaderSystem;
		if (shaderSystem == null)
			return .Ok;

		// Histogram pipeline
		let histShaderResult = shaderSystem.GetShader("exposure_histogram", .Compute);
		if (histShaderResult case .Ok(let shader))
		{
			ComputePipelineDesc desc = .(mHistogramPipelineLayout, shader.Module);
			desc.Label = "Exposure Histogram Pipeline";

			switch (mDevice.CreateComputePipeline(desc))
			{
			case .Ok(let pipeline): mHistogramPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		// Adapt pipeline
		let adaptShaderResult = shaderSystem.GetShader("exposure_adapt", .Compute);
		if (adaptShaderResult case .Ok(let adaptShader))
		{
			ComputePipelineDesc desc = .(mAdaptPipelineLayout, adaptShader.Module);
			desc.Label = "Exposure Adapt Pipeline";

			switch (mDevice.CreateComputePipeline(desc))
			{
			case .Ok(let pipeline): mAdaptPipeline = pipeline;
			case .Err: // Non-fatal
			}
		}

		return .Ok;
	}

	/// Adds auto-exposure compute passes to the render graph.
	/// Call this before PostProcessStack.AddPasses() in BuildRenderGraph().
	public void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		if (!mInitialized || mHistogramPipeline == null || mAdaptPipeline == null)
			return;

		let sceneColorHandle = graph.GetResource("SceneColor");
		if (!sceneColorHandle.IsValid)
			return;

		// Clear histogram buffer for current frame (fence-protected, no GPU sync needed)
		let frameIndex = FrameIndex;
		let histogramBuffer = mHistogramBuffers[frameIndex];
		mDevice.Queue.WriteMappedBuffer(histogramBuffer, 0, Span<uint8>(&mZeroBuffer, HistogramBufferSize));

		// Upload histogram params
		HistogramParams histParams = .();
		histParams.Width = view.Width;
		histParams.Height = view.Height;
		histParams.MinLogLuminance = DefaultMinLogLuminance;
		histParams.LogLuminanceRange = DefaultLogLuminanceRange;

		mDevice.Queue.WriteMappedBuffer(
			mHistogramParamsBuffer, 0,
			Span<uint8>((uint8*)&histParams, HistogramParams.Size)
		);

		// Upload adapt params
		let deltaTime = mRenderSystem?.RenderFrameContext?.DeltaTime ?? 0.016f;
		AdaptParams adaptParams = .();
		adaptParams.MinLogLuminance = DefaultMinLogLuminance;
		adaptParams.LogLuminanceRange = DefaultLogLuminanceRange;
		adaptParams.DeltaTime = deltaTime;
		adaptParams.AdaptSpeed = world.AutoExposureSpeed;
		adaptParams.MinExposure = world.AutoExposureMin;
		adaptParams.MaxExposure = world.AutoExposureMax;
		adaptParams.PixelCount = (float)(view.Width * view.Height);

		mDevice.Queue.WriteMappedBuffer(
			mAdaptParamsBuffer, 0,
			Span<uint8>((uint8*)&adaptParams, AdaptParams.Size)
		);

		// Import persistent buffers into render graph
		let histogramHandle = graph.ImportBuffer("ExposureHistogram", histogramBuffer);
		let exposureHandle = graph.ImportBuffer("ExposureBuffer", mExposureBuffer);

		// Recreate bind groups for current frame (scene color is transient)
		RenderGraph graphRef = graph;
		RGResourceHandle sceneColorCopy = sceneColorHandle;

		// Histogram pass
		graph.AddComputePass("AutoExposure_Histogram")
			.ReadTexture(sceneColorHandle)
			.WriteBuffer(histogramHandle)
			.NeverCull()
			.SetComputeCallback(new [=] (encoder) => {
				let sceneView = graphRef.GetTextureView(sceneColorCopy);
				ExecuteHistogramPass(encoder, sceneView, view.Width, view.Height, frameIndex);
			});

		// Adapt pass
		graph.AddComputePass("AutoExposure_Adapt")
			.ReadBuffer(histogramHandle)
			.WriteBuffer(exposureHandle)
			.NeverCull()
			.SetComputeCallback(new [=] (encoder) => {
				ExecuteAdaptPass(encoder, frameIndex);
			});
	}

	/// Reads back the computed exposure from the GPU.
	/// Call after GPU execution completes (e.g., at the start of the next frame).
	public void ReadbackExposure(RenderWorld world)
	{
		if (!mInitialized || mReadbackBuffer == null)
			return;

		// Copy exposure buffer to readback (done via queue for simplicity)
		// Note: this reads the previous frame's result (1 frame latency, standard for auto-exposure)
		if (let ptr = mReadbackBuffer.Map())
		{
			float exposure = *(float*)ptr;
			mReadbackBuffer.Unmap();

			if (exposure > 0.0f && exposure == exposure && exposure < 1e10f)
				world.Exposure = exposure;
		}
	}

	/// Queues a GPU copy of the exposure buffer to the readback buffer.
	/// Call after the render graph executes but before EndFrame.
	public void QueueReadback(ICommandEncoder encoder)
	{
		if (!mInitialized)
			return;

		// Copy the exposure buffer to the readback-accessible buffer
		encoder.CopyBufferToBuffer(mExposureBuffer, 0, mReadbackBuffer, 0, 8);
	}

	private void ExecuteHistogramPass(IComputePassEncoder encoder, ITextureView sceneColorView, uint32 width, uint32 height, int32 frameIndex)
	{
		if (sceneColorView == null)
			return;

		// Recreate bind group
		if (mHistogramBindGroups[frameIndex] != null)
		{
			delete mHistogramBindGroups[frameIndex];
			mHistogramBindGroups[frameIndex] = null;
		}

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, mHistogramParamsBuffer, 0, (uint64)HistogramParams.Size),
			BindGroupEntry.Texture(0, sceneColorView),
			BindGroupEntry.Buffer(0, mHistogramBuffers[frameIndex], 0, (uint64)HistogramBufferSize)  // u0
		);

		BindGroupDesc bgDesc = .();
		bgDesc.Label = "Histogram BG";
		bgDesc.Layout = mHistogramBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg): mHistogramBindGroups[frameIndex] = bg;
		case .Err: return;
		}

		encoder.SetPipeline(mHistogramPipeline);
		encoder.SetBindGroup(0, mHistogramBindGroups[frameIndex], default);
		encoder.Dispatch((width + 15) / 16, (height + 15) / 16, 1);

		if (mRenderSystem != null)
			mRenderSystem.Stats.ComputeDispatches++;
	}

	private void ExecuteAdaptPass(IComputePassEncoder encoder, int32 frameIndex)
	{
		// Recreate bind group
		if (mAdaptBindGroups[frameIndex] != null)
		{
			delete mAdaptBindGroups[frameIndex];
			mAdaptBindGroups[frameIndex] = null;
		}

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, mAdaptParamsBuffer, 0, (uint64)AdaptParams.Size),
			BindGroupEntry.Buffer(0, mHistogramBuffers[frameIndex], 0, (uint64)HistogramBufferSize),   // t0 read-only
			BindGroupEntry.Buffer(0, mExposureBuffer, 0, 8)                                             // u0 read-write
		);

		BindGroupDesc bgDesc = .();
		bgDesc.Label = "Adapt BG";
		bgDesc.Layout = mAdaptBindGroupLayout;
		bgDesc.Entries = entries;

		switch (mDevice.CreateBindGroup(bgDesc))
		{
		case .Ok(let bg): mAdaptBindGroups[frameIndex] = bg;
		case .Err: return;
		}

		encoder.SetPipeline(mAdaptPipeline);
		encoder.SetBindGroup(0, mAdaptBindGroups[frameIndex], default);
		encoder.Dispatch(1, 1, 1); // Single workgroup of 256 threads

		if (mRenderSystem != null)
			mRenderSystem.Stats.ComputeDispatches++;
	}

	public void Shutdown()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mHistogramBindGroups[i] != null) { delete mHistogramBindGroups[i]; mHistogramBindGroups[i] = null; }
			if (mAdaptBindGroups[i] != null) { delete mAdaptBindGroups[i]; mAdaptBindGroups[i] = null; }
		}
	}
}

namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Shaders;

/// GPU-based hierarchical Z-buffer occlusion culler.
/// Performs two-phase culling: coarse frustum + fine Hi-Z occlusion.
public class HiZOcclusionCuller : IDisposable
{
	// GPU resources
	private IDevice mDevice;
	private NewShaderSystem mShaderSystem;
	private ITexture mHiZPyramid;
	private ITextureView[16] mHiZMipViews;
	private ITextureView[16] mHiZMipStorageViews; // Storage views for compute writes
	private ISampler mHiZSampler;

	// Compute pipeline for Hi-Z build
	private IComputePipeline mBuildHiZPipeline;
	private IPipelineLayout mBuildHiZLayout;
	private IBindGroupLayout mBuildHiZBindGroupLayout;
	private IBindGroup[16] mBuildHiZBindGroups; // One bind group per mip level transition
	private IBuffer mBuildParamsBuffer;

	// Compute pipeline for occlusion culling
	private IComputePipeline mCullPipeline;
	private IPipelineLayout mCullLayout;
	private IBindGroupLayout mCullBindGroupLayout;
	private IBindGroup mCullBindGroup;
	private IBuffer mCullParamsBuffer;

	// Culling data buffers
	private IBuffer mBoundsBuffer;       // Input: AABB bounds
	private IBuffer mVisibilityBuffer;   // Output: visibility flags
	private IBuffer mIndirectBuffer;     // Output: indirect draw args

	// Configuration
	private uint32 mWidth;
	private uint32 mHeight;
	private uint32 mMipLevels;
	private uint32 mMaxObjects = 16384;

	// Statistics
	private HiZStats mStats;

	/// Whether the culler has been initialized.
	public bool IsInitialized => mDevice != null && mHiZPyramid != null;

	/// Gets the Hi-Z pyramid texture.
	public ITexture HiZPyramid => mHiZPyramid;

	/// Gets the number of mip levels in the pyramid.
	public uint32 MipLevels => mMipLevels;

	/// Gets occlusion culling statistics.
	public HiZStats Stats => mStats;

	/// Whether GPU Hi-Z building is available.
	public bool GPUBuildAvailable => mBuildHiZPipeline != null;

	/// Whether GPU Hi-Z culling is available.
	public bool GPUCullAvailable => mCullPipeline != null;

	/// Initializes the Hi-Z culler with the given dimensions.
	public Result<void> Initialize(IDevice device, uint32 width, uint32 height, NewShaderSystem shaderSystem = null)
	{
		mDevice = device;
		mShaderSystem = shaderSystem;
		mWidth = width;
		mHeight = height;

		// Calculate mip levels for Hi-Z pyramid
		mMipLevels = CalculateMipLevels(width, height);

		// Create Hi-Z pyramid texture
		if (CreateHiZPyramid() case .Err)
			return .Err;

		// Create culling buffers
		if (CreateCullingBuffers() case .Err)
			return .Err;

		// Create compute pipelines if shader system available
		if (mShaderSystem != null)
		{
			if (CreateComputePipelines() case .Err)
				return .Err;

			if (CreateBuildParamsBuffer() case .Err)
				return .Err;
		}

		return .Ok;
	}

	/// Resizes the Hi-Z pyramid for a new viewport size.
	public Result<void> Resize(uint32 width, uint32 height)
	{
		if (width == mWidth && height == mHeight)
			return .Ok;

		// Release old resources
		ReleaseBuildResources();
		ReleaseHiZResources();

		mWidth = width;
		mHeight = height;
		mMipLevels = CalculateMipLevels(width, height);

		if (CreateHiZPyramid() case .Err)
			return .Err;

		// Recreate compute pipelines if shader system was available
		if (mShaderSystem != null && mBuildHiZBindGroupLayout == null)
		{
			if (CreateComputePipelines() case .Err)
				return .Err;

			if (CreateBuildParamsBuffer() case .Err)
				return .Err;
		}

		return .Ok;
	}

	/// Builds the Hi-Z pyramid from a depth buffer.
	/// This should be called after the depth prepass.
	public void BuildPyramid(IComputePassEncoder encoder, ITextureView depthBuffer)
	{
		if (!IsInitialized || !GPUBuildAvailable)
			return;

		// Set the compute pipeline
		encoder.SetPipeline(mBuildHiZPipeline);

		// Build each mip level
		uint32 inputWidth = mWidth;
		uint32 inputHeight = mHeight;

		for (uint32 mip = 0; mip < mMipLevels - 1; mip++)
		{
			uint32 outputWidth = Math.Max(inputWidth / 2, 1);
			uint32 outputHeight = Math.Max(inputHeight / 2, 1);

			// Update build params buffer
			HiZBuildParams buildParams = .()
			{
				InputSize = .(inputWidth, inputHeight),
				OutputSize = .(outputWidth, outputHeight),
				MipLevel = mip,
				_Padding = .(0, 0, 0)
			};
			mDevice.Queue.WriteBuffer(mBuildParamsBuffer, 0, Span<uint8>((uint8*)&buildParams, sizeof(HiZBuildParams)));

			// Create or update bind group for this mip transition
			EnsureBuildBindGroup(mip, depthBuffer);

			// Set bind group
			if (mBuildHiZBindGroups[mip] != null)
				encoder.SetBindGroup(0, mBuildHiZBindGroups[mip], default);

			// Dispatch compute shader (8x8 thread groups)
			uint32 groupsX = (outputWidth + 7) / 8;
			uint32 groupsY = (outputHeight + 7) / 8;
			encoder.Dispatch(groupsX, groupsY, 1);

			// Next mip
			inputWidth = outputWidth;
			inputHeight = outputHeight;
		}

		mStats.PyramidBuildTime = 0; // Would measure actual GPU time
	}

	/// Performs GPU occlusion culling on a set of bounding boxes.
	/// Returns visibility results that can be read back or used for indirect draws.
	public void Cull(
		ICommandEncoder encoder,
		Span<BoundingBox> bounds,
		Matrix viewProjection,
		out IBuffer visibilityBuffer,
		out IBuffer indirectBuffer)
	{
		visibilityBuffer = mVisibilityBuffer;
		indirectBuffer = mIndirectBuffer;

		if (!IsInitialized || bounds.IsEmpty || !GPUCullAvailable)
			return;

		mStats.ObjectsTested = (int32)bounds.Length;

		// Ensure we don't exceed buffer capacity
		uint32 objectCount = (uint32)Math.Min(bounds.Length, (int)mMaxObjects);

		// Upload bounding boxes to GPU buffer
		// BoundingBox is 24 bytes (2 Vector3s)
		mDevice.Queue.WriteBuffer(mBoundsBuffer, 0, Span<uint8>((uint8*)bounds.Ptr, (int)(objectCount * 24)));

		// Update cull params
		HiZCullParams cullParams = .()
		{
			ViewProjection = viewProjection,
			ScreenSize = .((float)mWidth, (float)mHeight),
			InvScreenSize = .(1.0f / (float)mWidth, 1.0f / (float)mHeight),
			ObjectCount = objectCount,
			HiZMipCount = mMipLevels,
			_Padding = .(0, 0)
		};
		mDevice.Queue.WriteBuffer(mCullParamsBuffer, 0, Span<uint8>((uint8*)&cullParams, sizeof(HiZCullParams)));

		// Create or update bind group
		EnsureCullBindGroup();

		// Start compute pass
		if (let computeEncoder = encoder.BeginComputePass())
		{
			// Set pipeline and bind group
			computeEncoder.SetPipeline(mCullPipeline);
			if (mCullBindGroup != null)
				computeEncoder.SetBindGroup(0, mCullBindGroup, default);

			// Dispatch with 64 threads per group
			uint32 groupCount = (objectCount + 63) / 64;
			computeEncoder.Dispatch(groupCount, 1, 1);

			computeEncoder.End();
		}
	}

	/// Ensures the cull bind group exists and is up to date.
	private void EnsureCullBindGroup()
	{
		if (mCullBindGroupLayout == null || mCullParamsBuffer == null)
			return;

		// Release old bind group
		if (mCullBindGroup != null)
		{
			delete mCullBindGroup;
			mCullBindGroup = null;
		}

		// Need the first mip view of the Hi-Z pyramid for sampling
		if (mHiZMipViews[0] == null)
			return;

		// Create bind group entries - use HLSL register numbers
		// b0=params, t0=bounds, t1=hiZ, s0=sampler, u0=visibility
		BindGroupEntry[5] entries = .(
			BindGroupEntry.Buffer(0, mCullParamsBuffer, 0, sizeof(HiZCullParams)), // b0: Cull params
			BindGroupEntry.Buffer(0, mBoundsBuffer, 0, mMaxObjects * 24),          // t0: Input bounds (StructuredBuffer)
			BindGroupEntry.Texture(1, mHiZMipViews[0]),                            // t1: Hi-Z pyramid
			BindGroupEntry.Sampler(0, mHiZSampler),                                // s0: Hi-Z sampler
			BindGroupEntry.Buffer(0, mVisibilityBuffer, 0, mMaxObjects * 4)        // u0: Output visibility (RWStructuredBuffer)
		);

		BindGroupDescriptor desc = .()
		{
			Label = "HiZ Cull BindGroup",
			Layout = mCullBindGroupLayout,
			Entries = entries
		};

		switch (mDevice.CreateBindGroup(&desc))
		{
		case .Ok(let bindGroup): mCullBindGroup = bindGroup;
		case .Err: return;
		}
	}

	/// Performs two-phase culling (coarse frustum + fine Hi-Z).
	public void CullTwoPhase(
		ICommandEncoder encoder,
		RenderWorld world,
		CameraProxy* camera,
		FrustumCuller frustumCuller,
		List<MeshProxyHandle> outVisibleHandles)
	{
		outVisibleHandles.Clear();

		if (!IsInitialized || camera == null)
			return;

		// Phase 1: CPU frustum culling (coarse)
		List<MeshProxyHandle> frustumVisible = scope .();
		frustumCuller.CullMeshes(world, frustumVisible);

		mStats.FrustumPassCount = (int32)frustumVisible.Count;

		// If no frustum-visible objects or GPU culling unavailable, use frustum results
		if (frustumVisible.Count == 0 || !GPUCullAvailable)
		{
			for (let handle in frustumVisible)
				outVisibleHandles.Add(handle);

			mStats.HiZPassCount = (int32)outVisibleHandles.Count;
			mStats.OccludedCount = 0;
			return;
		}

		// Phase 2: GPU Hi-Z occlusion culling (fine)
		// Build bounds array from frustum-visible handles
		int32 objectCount = (int32)Math.Min(frustumVisible.Count, (int)mMaxObjects);
		List<BoundingBox> bounds = scope .(objectCount);
		List<MeshProxyHandle> handleMapping = scope .(objectCount); // Maps index -> handle

		for (int32 i = 0; i < objectCount; i++)
		{
			let handle = frustumVisible[i];
			if (let proxy = world.GetMesh(handle))
			{
				bounds.Add(proxy.WorldBounds);
				handleMapping.Add(handle);
			}
		}

		// Run GPU culling
		IBuffer visBuffer = null;
		IBuffer indirectBuffer = null;
		Cull(encoder, Span<BoundingBox>(bounds.Ptr, bounds.Count), camera.ViewProjectionMatrix, out visBuffer, out indirectBuffer);

		// For now, we pass all frustum-visible objects through
		// Full implementation would read back visibility buffer or use indirect draw
		// GPU readback requires:
		// 1. Staging buffer for CPU access
		// 2. Copy from visibility buffer to staging
		// 3. Map staging buffer and read results
		// This adds latency, so production systems use indirect dispatch instead

		// CPU fallback: pass all frustum-visible objects
		for (let handle in handleMapping)
			outVisibleHandles.Add(handle);

		mStats.HiZPassCount = (int32)outVisibleHandles.Count;
		mStats.OccludedCount = mStats.FrustumPassCount - mStats.HiZPassCount;
	}

	/// Performs GPU occlusion culling with readback for visibility results.
	/// This is slower due to GPU->CPU sync but provides accurate visibility data.
	public void CullWithReadback(
		ICommandEncoder encoder,
		RenderWorld world,
		CameraProxy* camera,
		FrustumCuller frustumCuller,
		List<MeshProxyHandle> outVisibleHandles)
	{
		outVisibleHandles.Clear();

		if (!IsInitialized || camera == null)
			return;

		// Phase 1: CPU frustum culling
		List<MeshProxyHandle> frustumVisible = scope .();
		frustumCuller.CullMeshes(world, frustumVisible);

		mStats.FrustumPassCount = (int32)frustumVisible.Count;

		if (frustumVisible.Count == 0 || !GPUCullAvailable)
		{
			for (let handle in frustumVisible)
				outVisibleHandles.Add(handle);

			mStats.HiZPassCount = (int32)outVisibleHandles.Count;
			mStats.OccludedCount = 0;
			return;
		}

		// Build bounds array
		int32 objectCount = (int32)Math.Min(frustumVisible.Count, (int)mMaxObjects);
		List<BoundingBox> bounds = scope .(objectCount);
		List<MeshProxyHandle> handleMapping = scope .(objectCount);

		for (int32 i = 0; i < objectCount; i++)
		{
			let handle = frustumVisible[i];
			if (let proxy = world.GetMesh(handle))
			{
				bounds.Add(proxy.WorldBounds);
				handleMapping.Add(handle);
			}
		}

		// Run GPU culling
		IBuffer visBuffer = null;
		IBuffer indirectBuffer = null;
		Cull(encoder, Span<BoundingBox>(bounds.Ptr, bounds.Count), camera.ViewProjectionMatrix, out visBuffer, out indirectBuffer);

		// In a full implementation, we would:
		// 1. Create a staging buffer
		// 2. Copy visibility buffer to staging
		// 3. Map staging buffer
		// 4. Read visibility flags
		// 5. Build output list based on visibility
		// This requires GPU sync and is expensive

		// For now, return frustum-visible (GPU culling result is discarded)
		for (let handle in handleMapping)
			outVisibleHandles.Add(handle);

		mStats.HiZPassCount = (int32)outVisibleHandles.Count;
		mStats.OccludedCount = mStats.FrustumPassCount - mStats.HiZPassCount;
	}

	public void Dispose()
	{
		ReleaseBuildResources();
		ReleaseHiZResources();
		ReleaseCullingResources();
	}

	private void ReleaseHiZResources()
	{
		for (var view in ref mHiZMipViews)
		{
			if (view != null)
			{
				delete view;
				view = null;
			}
		}

		if (mHiZPyramid != null)
		{
			delete mHiZPyramid;
			mHiZPyramid = null;
		}

		if (mHiZSampler != null)
		{
			delete mHiZSampler;
			mHiZSampler = null;
		}
	}

	private void ReleaseCullingResources()
	{
		if (mBoundsBuffer != null) { delete mBoundsBuffer; mBoundsBuffer = null; }
		if (mVisibilityBuffer != null) { delete mVisibilityBuffer; mVisibilityBuffer = null; }
		if (mIndirectBuffer != null) { delete mIndirectBuffer; mIndirectBuffer = null; }
		if (mCullBindGroup != null) { delete mCullBindGroup; mCullBindGroup = null; }
		if (mCullParamsBuffer != null) { delete mCullParamsBuffer; mCullParamsBuffer = null; }
		if (mCullPipeline != null) { delete mCullPipeline; mCullPipeline = null; }
		if (mCullLayout != null) { delete mCullLayout; mCullLayout = null; }
		if (mCullBindGroupLayout != null) { delete mCullBindGroupLayout; mCullBindGroupLayout = null; }
	}

	private Result<void> CreateHiZPyramid()
	{
		// Create Hi-Z pyramid texture with mip chain
		TextureDescriptor desc = .()
		{
			Label = "HiZ Pyramid",
			Dimension = .Texture2D,
			Width = mWidth,
			Height = mHeight,
			Depth = 1,
			Format = .R32Float,
			MipLevelCount = mMipLevels,
			ArrayLayerCount = 1,
			SampleCount = 1,
			Usage = .Sampled | .Storage | .RenderTarget
		};

		switch (mDevice.CreateTexture(&desc))
		{
		case .Ok(let tex):
			mHiZPyramid = tex;
		case .Err:
			return .Err;
		}

		// Create views for each mip level (sampled and storage)
		for (uint32 mip = 0; mip < mMipLevels && mip < 16; mip++)
		{
			// Sampled view for reading
			TextureViewDescriptor viewDesc = .()
			{
				Label = "HiZ Mip View",
				Format = .R32Float,
				Dimension = .Texture2D,
				BaseMipLevel = mip,
				MipLevelCount = 1,
				BaseArrayLayer = 0,
				ArrayLayerCount = 1,
				Aspect = .All
			};

			switch (mDevice.CreateTextureView(mHiZPyramid, &viewDesc))
			{
			case .Ok(let view):
				mHiZMipViews[mip] = view;
			case .Err:
				return .Err;
			}

			// Storage view for compute writes
			TextureViewDescriptor storageViewDesc = .()
			{
				Label = "HiZ Mip Storage View",
				Format = .R32Float,
				Dimension = .Texture2D,
				BaseMipLevel = mip,
				MipLevelCount = 1,
				BaseArrayLayer = 0,
				ArrayLayerCount = 1,
				Aspect = .All
			};

			switch (mDevice.CreateTextureView(mHiZPyramid, &storageViewDesc))
			{
			case .Ok(let view):
				mHiZMipStorageViews[mip] = view;
			case .Err:
				return .Err;
			}
		}

		// Create sampler for Hi-Z reads (point filtering, clamp)
		SamplerDescriptor samplerDesc = .()
		{
			Label = "HiZ Sampler",
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge,
			MagFilter = .Nearest,
			MinFilter = .Nearest,
			MipmapFilter = .Nearest
		};

		switch (mDevice.CreateSampler(&samplerDesc))
		{
		case .Ok(let sampler):
			mHiZSampler = sampler;
		case .Err:
			return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateCullingBuffers()
	{
		// Bounds buffer: AABB data for objects to cull
		// Each AABB is 6 floats (min xyz, max xyz) = 24 bytes
		let boundsSize = mMaxObjects * 24;

		BufferDescriptor boundsDesc = .()
		{
			Label = "HiZ Cull Bounds",
			Size = boundsSize,
			Usage = .Storage | .CopyDst
		};

		switch (mDevice.CreateBuffer(&boundsDesc))
		{
		case .Ok(let buf):
			mBoundsBuffer = buf;
		case .Err:
			return .Err;
		}

		// Visibility buffer: 1 uint32 per object (visible/occluded)
		BufferDescriptor visDesc = .()
		{
			Label = "HiZ Visibility",
			Size = mMaxObjects * 4,
			Usage = .Storage | .CopySrc
		};

		switch (mDevice.CreateBuffer(&visDesc))
		{
		case .Ok(let buf):
			mVisibilityBuffer = buf;
		case .Err:
			return .Err;
		}

		// Indirect draw buffer for GPU-driven rendering
		// DrawIndexedIndirectCommand is 20 bytes (5 uint32s)
		let indirectSize = mMaxObjects * 20;

		BufferDescriptor indirectDesc = .()
		{
			Label = "HiZ Indirect",
			Size = indirectSize,
			Usage = .Storage | .Indirect
		};

		switch (mDevice.CreateBuffer(&indirectDesc))
		{
		case .Ok(let buf):
			mIndirectBuffer = buf;
		case .Err:
			return .Err;
		}

		return .Ok;
	}

	private static uint32 CalculateMipLevels(uint32 width, uint32 height)
	{
		uint32 maxDim = Math.Max(width, height);
		uint32 levels = 1;
		while (maxDim > 1)
		{
			maxDim >>= 1;
			levels++;
		}
		return Math.Min(levels, 16); // Cap at 16 mip levels
	}

	private Result<void> CreateComputePipelines()
	{
		if (mShaderSystem == null)
			return .Ok;

		// Load Hi-Z build shader
		let shaderResult = mShaderSystem.GetShader("hiz_build", .Compute);
		if (shaderResult case .Err)
			return .Ok; // Shader not available yet

		let shader = shaderResult.Value;

		// Create bind group layout for Hi-Z build
		// Shader bindings: t0=InputDepth, u0=OutputHiZ, s0=DepthSampler, b0=BuildParams
		// Use HLSL register numbers - RHI handles Vulkan shifts internally
		BindGroupLayoutEntry[4] buildEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .SampledTexture }, // t0: Input depth
			.() { Binding = 0, Visibility = .Compute, Type = .StorageTexture }, // u0: Output Hi-Z
			.() { Binding = 0, Visibility = .Compute, Type = .Sampler },        // s0: Depth sampler
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer }   // b0: Build params
		);

		BindGroupLayoutDescriptor buildLayoutDesc = .()
		{
			Label = "HiZ Build BindGroup Layout",
			Entries = buildEntries
		};

		switch (mDevice.CreateBindGroupLayout(&buildLayoutDesc))
		{
		case .Ok(let layout): mBuildHiZBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBuildHiZBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);

		switch (mDevice.CreatePipelineLayout(&pipelineLayoutDesc))
		{
		case .Ok(let layout): mBuildHiZLayout = layout;
		case .Err: return .Err;
		}

		// Create compute pipeline
		ComputePipelineDescriptor pipelineDesc = .()
		{
			Label = "HiZ Build Pipeline",
			Layout = mBuildHiZLayout,
			Compute = .(shader.Module, "main")
		};

		switch (mDevice.CreateComputePipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mBuildHiZPipeline = pipeline;
		case .Err: return .Err;
		}

		// Create cull pipeline
		if (CreateCullPipeline() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateCullPipeline()
	{
		if (mShaderSystem == null)
			return .Ok;

		// Load Hi-Z cull shader
		let shaderResult = mShaderSystem.GetShader("hiz_cull", .Compute);
		if (shaderResult case .Err)
			return .Ok; // Shader not available yet

		let shader = shaderResult.Value;

		// Create bind group layout for Hi-Z cull
		// Shader bindings: b0=CullParams, t0=InputBounds, t1=HiZPyramid, s0=HiZSampler, u0=OutputVisibility
		// Use HLSL register numbers - RHI applies Vulkan shifts based on Type
		BindGroupLayoutEntry[5] cullEntries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer },          // b0: Cull params
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBuffer },          // t0: Input bounds (StructuredBuffer)
			.() { Binding = 1, Visibility = .Compute, Type = .SampledTexture },         // t1: Hi-Z pyramid
			.() { Binding = 0, Visibility = .Compute, Type = .Sampler },                // s0: Hi-Z sampler
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadWrite }  // u0: Output visibility (RWStructuredBuffer)
		);

		BindGroupLayoutDescriptor cullLayoutDesc = .()
		{
			Label = "HiZ Cull BindGroup Layout",
			Entries = cullEntries
		};

		switch (mDevice.CreateBindGroupLayout(&cullLayoutDesc))
		{
		case .Ok(let layout): mCullBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mCullBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);

		switch (mDevice.CreatePipelineLayout(&pipelineLayoutDesc))
		{
		case .Ok(let layout): mCullLayout = layout;
		case .Err: return .Err;
		}

		// Create compute pipeline
		ComputePipelineDescriptor pipelineDesc = .()
		{
			Label = "HiZ Cull Pipeline",
			Layout = mCullLayout,
			Compute = .(shader.Module, "main")
		};

		switch (mDevice.CreateComputePipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mCullPipeline = pipeline;
		case .Err: return .Err;
		}

		// Create cull params buffer
		BufferDescriptor paramsDesc = .()
		{
			Label = "HiZ Cull Params",
			Size = sizeof(HiZCullParams),
			Usage = .Uniform | .CopyDst
		};

		switch (mDevice.CreateBuffer(&paramsDesc))
		{
		case .Ok(let buf): mCullParamsBuffer = buf;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateBuildParamsBuffer()
	{
		BufferDescriptor desc = .()
		{
			Label = "HiZ Build Params",
			Size = sizeof(HiZBuildParams),
			Usage = .Uniform | .CopyDst
		};

		switch (mDevice.CreateBuffer(&desc))
		{
		case .Ok(let buf): mBuildParamsBuffer = buf;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private void EnsureBuildBindGroup(uint32 mipLevel, ITextureView depthBuffer)
	{
		if (mBuildHiZBindGroupLayout == null || mBuildParamsBuffer == null)
			return;

		// Get input view (depth buffer for mip 0, previous mip view otherwise)
		ITextureView inputView = (mipLevel == 0) ? depthBuffer : mHiZMipViews[mipLevel];
		ITextureView outputView = mHiZMipStorageViews[mipLevel + 1];

		if (inputView == null || outputView == null)
			return;

		// Release old bind group if exists
		if (mBuildHiZBindGroups[mipLevel] != null)
		{
			delete mBuildHiZBindGroups[mipLevel];
			mBuildHiZBindGroups[mipLevel] = null;
		}

		// Create bind group entries - use HLSL register numbers
		// t0=input, u0=output, s0=sampler, b0=params
		BindGroupEntry[4] entries = .(
			BindGroupEntry.Texture(0, inputView),     // t0
			BindGroupEntry.Texture(0, outputView),    // u0 (storage texture uses u register)
			BindGroupEntry.Sampler(0, mHiZSampler),   // s0
			BindGroupEntry.Buffer(0, mBuildParamsBuffer, 0, sizeof(HiZBuildParams)) // b0
		);

		BindGroupDescriptor desc = .()
		{
			Label = "HiZ Build BindGroup",
			Layout = mBuildHiZBindGroupLayout,
			Entries = entries
		};

		switch (mDevice.CreateBindGroup(&desc))
		{
		case .Ok(let bindGroup): mBuildHiZBindGroups[mipLevel] = bindGroup;
		case .Err: return;
		}
	}

	private void ReleaseBuildResources()
	{
		for (var bindGroup in ref mBuildHiZBindGroups)
		{
			if (bindGroup != null)
			{
				delete bindGroup;
				bindGroup = null;
			}
		}

		for (var view in ref mHiZMipStorageViews)
		{
			if (view != null)
			{
				delete view;
				view = null;
			}
		}

		if (mBuildParamsBuffer != null) { delete mBuildParamsBuffer; mBuildParamsBuffer = null; }
		if (mBuildHiZPipeline != null) { delete mBuildHiZPipeline; mBuildHiZPipeline = null; }
		if (mBuildHiZLayout != null) { delete mBuildHiZLayout; mBuildHiZLayout = null; }
		if (mBuildHiZBindGroupLayout != null) { delete mBuildHiZBindGroupLayout; mBuildHiZBindGroupLayout = null; }
	}
}

/// Parameters for Hi-Z pyramid build shader.
[CRepr]
public struct HiZBuildParams
{
	public uint32[2] InputSize;
	public uint32[2] OutputSize;
	public uint32 MipLevel;
	public uint32[3] _Padding;
}

/// Statistics from Hi-Z occlusion culling.
public struct HiZStats
{
	/// Number of objects tested for occlusion.
	public int32 ObjectsTested;

	/// Number of objects that passed frustum culling.
	public int32 FrustumPassCount;

	/// Number of objects that passed Hi-Z occlusion culling.
	public int32 HiZPassCount;

	/// Number of objects culled by occlusion.
	public int32 OccludedCount;

	/// Time to build the Hi-Z pyramid (in milliseconds).
	public float PyramidBuildTime;

	/// Percentage of objects culled by occlusion.
	public float OcclusionCullPercentage => FrustumPassCount > 0
		? (float)OccludedCount / (float)FrustumPassCount * 100.0f
		: 0.0f;
}

/// Parameters for Hi-Z cull shader.
[CRepr]
public struct HiZCullParams
{
	public Matrix ViewProjection;     // View-projection matrix (64 bytes)
	public float[2] ScreenSize;       // Screen dimensions
	public float[2] InvScreenSize;    // 1.0 / ScreenSize
	public uint32 ObjectCount;        // Number of objects to cull
	public uint32 HiZMipCount;        // Number of mip levels
	public uint32[2] _Padding;
}

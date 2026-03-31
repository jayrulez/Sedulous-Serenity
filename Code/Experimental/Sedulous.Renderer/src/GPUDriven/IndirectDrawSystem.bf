namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// A draw group represents a unique (material, mesh, submesh) combination.
/// Each object in the group has its own indirect command slot.
[CRepr]
struct DrawGroup
{
	/// Material instance handle for pipeline/bind group selection.
	public MaterialInstanceHandle MaterialHandle;
	/// GPU mesh handle.
	public GPUMeshHandle MeshHandle;
	/// Submesh index within the mesh.
	public uint32 SubMeshIndex;
	/// Number of objects that belong to this group (before culling).
	public uint32 TotalObjectCount;
	/// Base offset (in command count) into the indirect command buffer.
	public uint32 CommandOffset;
}

/// Standard DrawIndexedIndirect argument structure (20 bytes).
/// Matches D3D12_DRAW_INDEXED_ARGUMENTS / VkDrawIndexedIndirectCommand.
[CRepr]
struct DrawIndexedIndirectCommand
{
	public uint32 IndexCount;
	public uint32 InstanceCount;
	public uint32 FirstIndex;
	public int32 BaseVertex;
	public uint32 FirstInstance;

	public const int Stride = 20;
}

/// GPU cull uniforms passed to the culling compute shader.
[CRepr]
struct GPUCullUniforms
{
	public Vector4[6] FrustumPlanes;    // 96 bytes
	public Matrix ViewProjection;       // 64 bytes (for Hi-Z screen projection)
	public float[2] HiZSize;            // 8 bytes (Hi-Z mip 0 dimensions)
	public uint32 ObjectCount;          // 4
	public uint32 DrawGroupCount;       // 4
	public uint32 HiZMipCount;          // 4
	public uint32 EnableOcclusion;      // 4
	public uint32[2] _pad;              // 8
	// Total: 192 bytes
}

/// GPU-driven indirect draw system.
/// Manages draw groups, indirect command buffers, and GPU culling dispatch.
/// Owned by RenderSystem as shared infrastructure.
class IndirectDrawSystem
{
	private IDevice mDevice;

	// GPU culling compute pipeline
	private IComputePipeline mCullPipeline;
	private IBindGroupLayout mCullBindGroupLayout;
	private IPipelineLayout mCullPipelineLayout;

	// Per-frame resources
	private IBuffer[RenderConfig.FrameBufferCount] mIndirectCommandBuffers;   // DrawIndexedIndirectCommand[]
	private IBuffer[RenderConfig.FrameBufferCount] mInstanceMappingBuffers;   // uint32[] objectIndex per visible instance
	private IBuffer[RenderConfig.FrameBufferCount] mCullUniformBuffers;       // CpuToGpu, GPUCullUniforms
	private void*[RenderConfig.FrameBufferCount] mCullUniformPtrs;
	private IBindGroup[RenderConfig.FrameBufferCount] mCullBindGroups;

	// Draw groups (rebuilt each frame from active proxies)
	private List<DrawGroup> mDrawGroups = new .() ~ delete _;
	private Dictionary<uint64, int32> mDrawGroupMap = new .() ~ delete _;  // hash → group index

	// Staging buffer for zeroing indirect command instanceCounts
	private IBuffer mZeroStagingBuffer;
	private void* mZeroStagingPtr;

	private uint32 mMaxObjects;
	private uint32 mMaxDrawGroups;
	private bool[RenderConfig.FrameBufferCount] mHasBeenUsed;

	/// Current frame's draw groups.
	public List<DrawGroup> DrawGroups => mDrawGroups;

	/// Gets the indirect command buffer for the given frame.
	public IBuffer GetIndirectBuffer(int frameIndex) => mIndirectCommandBuffers[frameIndex];

	/// Gets the instance mapping buffer for the given frame.
	public IBuffer GetInstanceMappingBuffer(int frameIndex) => mInstanceMappingBuffers[frameIndex];

	public Result<void> Initialize(IDevice device, ShaderLibrary shaderLib)
	{
		mDevice = device;
		mMaxObjects = (uint32)RenderConfig.MaxOpaqueObjects;
		mMaxDrawGroups = 4096; // max unique material+mesh+submesh combinations

		// --- Indirect command buffers ---
		let indirectBufSize = (uint64)(mMaxDrawGroups * DrawIndexedIndirectCommand.Stride);
		let mappingBufSize = (uint64)(mMaxObjects * sizeof(uint32));

		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			// Indirect command buffer (GPU writes instanceCount, CPU pre-fills mesh info)
			let indResult = device.CreateBuffer(BufferDesc()
			{
				Size = indirectBufSize,
				Usage = .Indirect | .Storage | .CopyDst,
				Memory = .GpuOnly,
				Label = "IndirectCommands"
			});
			if (indResult case .Err) return .Err;
			mIndirectCommandBuffers[i] = indResult.Value;

			// Instance mapping buffer (GPU writes objectIndex per visible instance)
			let mapResult = device.CreateBuffer(BufferDesc()
			{
				Size = mappingBufSize,
				Usage = .Storage | .Vertex,
				Memory = .GpuOnly,
				Label = "InstanceMapping"
			});
			if (mapResult case .Err) return .Err;
			mInstanceMappingBuffers[i] = mapResult.Value;

			// Cull uniforms (CpuToGpu, persistently mapped)
			let cullUBResult = device.CreateBuffer(BufferDesc()
			{
				Size = (uint64)sizeof(GPUCullUniforms),
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "GPUCullUniforms"
			});
			if (cullUBResult case .Err) return .Err;
			mCullUniformBuffers[i] = cullUBResult.Value;
			mCullUniformPtrs[i] = mCullUniformBuffers[i].Map();
		}

		// Zero staging buffer for clearing indirect command instanceCounts
		let zeroBufSize = indirectBufSize;
		let zeroResult = device.CreateBuffer(BufferDesc()
		{
			Size = zeroBufSize,
			Usage = .CopySrc,
			Memory = .CpuToGpu,
			Label = "IndirectZeroStaging"
		});
		if (zeroResult case .Err) return .Err;
		mZeroStagingBuffer = zeroResult.Value;
		mZeroStagingPtr = mZeroStagingBuffer.Map();
		if (mZeroStagingPtr != null)
			Internal.MemSet(mZeroStagingPtr, 0, (int)zeroBufSize);

		// --- Compute culling pipeline ---
		if (CreateCullPipeline(device, shaderLib) case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateCullPipeline(IDevice device, ShaderLibrary shaderLib)
	{
		// Register shader
		if (shaderLib.RegisterShader("gpu_cull") case .Err)
			return .Err;

		// Bind group layout:
		// b0: GPUCullUniforms
		// t1: ObjectData (GPUSceneBuffer, read-only)
		// u2: IndirectCommands (read-write)
		// u3: InstanceMapping (read-write)
		// t4: HiZPyramid (Texture2D<float>, read-only)
		// s5: HiZSampler
		BindGroupLayoutEntry[6] entries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Compute),
			BindGroupLayoutEntry.StorageBuffer(1, .Compute, readWrite: false),
			BindGroupLayoutEntry.StorageBuffer(2, .Compute, readWrite: true),
			BindGroupLayoutEntry.StorageBuffer(3, .Compute, readWrite: true),
			BindGroupLayoutEntry.SampledTexture(4, .Compute, .Texture2D),
			BindGroupLayoutEntry.Sampler(5, .Compute)
		);

		let layoutResult = device.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = entries,
			Label = "GPUCullBindGroupLayout"
		});
		if (layoutResult case .Err) return .Err;
		mCullBindGroupLayout = layoutResult.Value;

		IBindGroupLayout[1] bgLayouts = .(mCullBindGroupLayout);
		let pipeLayoutResult = device.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = bgLayouts,
			Label = "GPUCullPipelineLayout"
		});
		if (pipeLayoutResult case .Err) return .Err;
		mCullPipelineLayout = pipeLayoutResult.Value;

		let shaderModule = shaderLib.GetCompiledShader("gpu_cull", .Compute);
		if (shaderModule case .Err) return .Err;

		let pipeResult = device.CreateComputePipeline(ComputePipelineDesc()
		{
			Layout = mCullPipelineLayout,
			Compute = ProgrammableStage() { Module = shaderModule.Value, EntryPoint = "CSMain" },
			Label = "GPUCullPipeline"
		});
		if (pipeResult case .Err) return .Err;
		mCullPipeline = pipeResult.Value;

		return .Ok;
	}

	/// Builds draw groups from the current scene and pre-fills indirect commands.
	/// Call after GPUSceneBuffer.Update, before RecordCull.
	public void BuildDrawGroups(RenderWorld world, GPUResourceManager resources)
	{
		mDrawGroups.Clear();
		mDrawGroupMap.Clear();

		if (world == null) return;

		world.StaticMeshes.ForEach(scope [&] (handle, proxy) =>
		{
			if (!proxy.MeshHandle.IsValid) return;
			if (!proxy.Flags.HasFlag(.Visible)) return;

			let mesh = resources.GetMesh(proxy.MeshHandle);
			if (mesh == null) return;

			// For each submesh, find or create a draw group
			uint32 subStart = 0;
			uint32 subCount = (uint32)mesh.SubMeshes.Count;

			for (uint32 si = subStart; si < subStart + subCount; si++)
			{
				if (si >= (uint32)mesh.SubMeshes.Count) break;
				let subMesh = mesh.SubMeshes[si];
				let matSlot = subMesh.MaterialSlot;

				let materialHandle = (matSlot < proxy.MaterialCount)
					? proxy.Materials[matSlot]
					: MaterialInstanceHandle.Invalid;

				// Hash: material + mesh + submesh
				let groupKey = ((uint64)materialHandle.Index << 32) |
							   ((uint64)proxy.MeshHandle.Index << 16) |
							   (uint64)si;

				if (!mDrawGroupMap.ContainsKey(groupKey))
				{
					let groupIdx = (int32)mDrawGroups.Count;
					mDrawGroups.Add(DrawGroup()
					{
						MaterialHandle = materialHandle,
						MeshHandle = proxy.MeshHandle,
						SubMeshIndex = si,
						TotalObjectCount = 1
					});
					mDrawGroupMap[groupKey] = groupIdx;
				}
				else
				{
					let groupIdx = mDrawGroupMap[groupKey];
					var group = mDrawGroups[groupIdx];
					group.TotalObjectCount++;
					mDrawGroups[groupIdx] = group;
				}
			}
		});
	}

	/// Pre-fills indirect commands with mesh info and zeros instanceCounts.
	/// Then records GPU culling compute dispatch.
	public void RecordCull(
		ICommandEncoder encoder,
		int frameIndex,
		GPUSceneBuffer sceneBuffer,
		GPUResourceManager resources,
		ViewContext viewCtx,
		HiZPyramid hiZ = null)
	{
		let objectCount = sceneBuffer.ObjectCount(frameIndex);
		if (objectCount == 0 || mCullPipeline == null)
			return;

		// Pre-fill indirect commands on CPU and copy to GPU
		PreFillIndirectCommands(frameIndex, resources, sceneBuffer, encoder);

		// Upload cull uniforms
		UploadCullUniforms(frameIndex, viewCtx, (uint32)objectCount, hiZ);

		// Rebuild cull bind group
		RebuildCullBindGroup(frameIndex, sceneBuffer, hiZ);

		// Skip dispatch if bind group couldn't be created (no Hi-Z texture yet on first frame).
		// In this case, set all commands to visible (instanceCount=1) as fallback.
		if (mCullBindGroups[frameIndex] == null)
		{
			let fallbackPtr = (DrawIndexedIndirectCommand*)mZeroStagingPtr;
			if (fallbackPtr != null)
			{
				for (int i = 0; i < objectCount; i++)
					fallbackPtr[i].InstanceCount = 1;

				let copySize = (uint64)(objectCount * DrawIndexedIndirectCommand.Stride);
				encoder.CopyBufferToBuffer(mZeroStagingBuffer, 0, mIndirectCommandBuffers[frameIndex], 0, copySize);
			}

			// Barrier: CopyDst → IndirectArgument
			BufferBarrier[1] barriers = .(.()
			{
				Buffer = mIndirectCommandBuffers[frameIndex],
				OldState = .CopyDst,
				NewState = .IndirectArgument
			});
			encoder.Barrier(BarrierGroup()
			{
				BufferBarriers = Span<BufferBarrier>(&barriers[0], 1)
			});
			mHasBeenUsed[frameIndex] = true;
			return;
		}

		// Barriers: indirect buffer CopyDst → ShaderWrite for cull compute
		{
			BufferBarrier[1] barriers = .(
				.() {
					Buffer = mIndirectCommandBuffers[frameIndex],
					OldState = .CopyDst,
					NewState = .ShaderWrite
				}
			);
			encoder.Barrier(BarrierGroup()
			{
				BufferBarriers = Span<BufferBarrier>(&barriers[0], 1)
			});
		}

		let cp = encoder.BeginComputePass("GPUCull");
		cp.SetPipeline(mCullPipeline);
		cp.SetBindGroup(0, mCullBindGroups[frameIndex]);
		cp.Dispatch(((uint32)objectCount + 63) / 64);
		cp.End();

		// Barrier: indirect buffer ShaderWrite → IndirectArgument (ready for DrawIndexedIndirect)
		{
			BufferBarrier[1] barriers = .(
				.() {
					Buffer = mIndirectCommandBuffers[frameIndex],
					OldState = .ShaderWrite,
					NewState = .IndirectArgument
				}
			);
			encoder.Barrier(BarrierGroup()
			{
				BufferBarriers = Span<BufferBarrier>(&barriers[0], 1)
			});
		}

		mHasBeenUsed[frameIndex] = true;
	}

	private void PreFillIndirectCommands(int frameIndex, GPUResourceManager resources,
		GPUSceneBuffer sceneBuffer, ICommandEncoder encoder)
	{
		// Fill one indirect command per object (sorted by draw group in GPUSceneBuffer).
		// instanceCount=0 — GPU cull sets to 1 for visible objects.
		// firstInstance=objectIndex — identity instance buffer provides ObjectIndex attribute.
		let objectCount = sceneBuffer.ObjectCount(frameIndex);
		let cmdSize = objectCount * DrawIndexedIndirectCommand.Stride;

		let ptr = (DrawIndexedIndirectCommand*)mZeroStagingPtr;
		if (ptr == null || objectCount == 0) return;

		// Zero all commands first
		Internal.MemSet(mZeroStagingPtr, 0, Math.Min(cmdSize, (int)(mMaxDrawGroups * DrawIndexedIndirectCommand.Stride)));

		// Fill mesh info per object using draw group ranges
		for (let range in sceneBuffer.DrawGroupRanges)
		{
			let mesh = resources.GetMesh(range.MeshHandle);
			if (mesh == null) continue;
			if (range.SubMeshIndex >= (uint32)mesh.SubMeshes.Count) continue;
			let subMesh = mesh.SubMeshes[range.SubMeshIndex];

			for (uint32 i = 0; i < range.CommandCount; i++)
			{
				let cmdIdx = range.CommandOffset + i;
				if (cmdIdx >= (uint32)objectCount) break;

				ptr[cmdIdx] = .()
				{
					IndexCount = subMesh.IndexCount > 0 ? subMesh.IndexCount : mesh.VertexCount,
					InstanceCount = 0, // GPU cull sets to 1 for visible
					FirstIndex = subMesh.IndexStart,
					BaseVertex = subMesh.BaseVertex,
					FirstInstance = cmdIdx // objectIndex in GPUSceneBuffer
				};
			}
		}

		// Copy pre-filled commands to GPU indirect buffer
		let copySize = (uint64)(objectCount * DrawIndexedIndirectCommand.Stride);
		encoder.CopyBufferToBuffer(mZeroStagingBuffer, 0, mIndirectCommandBuffers[frameIndex], 0, copySize);
	}

	private void UploadCullUniforms(int frameIndex, ViewContext viewCtx, uint32 objectCount, HiZPyramid hiZ)
	{
		if (mCullUniformPtrs[frameIndex] == null) return;

		var uniforms = GPUCullUniforms();
		uniforms.ObjectCount = objectCount;
		uniforms.DrawGroupCount = (uint32)mDrawGroups.Count;

		// Extract frustum planes from view-projection matrix
		let vp = viewCtx.ViewProjectionMatrix;
		ExtractFrustumPlanes(vp, ref uniforms.FrustumPlanes);

		// Hi-Z occlusion data
		uniforms.ViewProjection = vp;
		if (hiZ != null && hiZ.HiZTexture != null && hiZ.MipCount > 0 && hiZ.Generated)
		{
			let hiZDesc = hiZ.HiZTexture.Desc;
			uniforms.HiZSize = .((float)hiZDesc.Width, (float)hiZDesc.Height);
			uniforms.HiZMipCount = hiZ.MipCount;
			uniforms.EnableOcclusion = 1;
		}
		else
		{
			uniforms.EnableOcclusion = 0;
		}

		Internal.MemCpy(mCullUniformPtrs[frameIndex], &uniforms, sizeof(GPUCullUniforms));
	}

	/// Extracts 6 frustum planes from a view-projection matrix.
	/// Planes are normalized (xyz = normal, w = distance).
	private static void ExtractFrustumPlanes(Matrix vp, ref Vector4[6] planes)
	{
		// Left: row3 + row0
		planes[0] = Vector4(vp.M14 + vp.M11, vp.M24 + vp.M21, vp.M34 + vp.M31, vp.M44 + vp.M41);
		// Right: row3 - row0
		planes[1] = Vector4(vp.M14 - vp.M11, vp.M24 - vp.M21, vp.M34 - vp.M31, vp.M44 - vp.M41);
		// Bottom: row3 + row1
		planes[2] = Vector4(vp.M14 + vp.M12, vp.M24 + vp.M22, vp.M34 + vp.M32, vp.M44 + vp.M42);
		// Top: row3 - row1
		planes[3] = Vector4(vp.M14 - vp.M12, vp.M24 - vp.M22, vp.M34 - vp.M32, vp.M44 - vp.M42);
		// Near: row3 + row2
		planes[4] = Vector4(vp.M14 + vp.M13, vp.M24 + vp.M23, vp.M34 + vp.M33, vp.M44 + vp.M43);
		// Far: row3 - row2
		planes[5] = Vector4(vp.M14 - vp.M13, vp.M24 - vp.M23, vp.M34 - vp.M33, vp.M44 - vp.M43);

		// Normalize planes
		for (int i = 0; i < 6; i++)
		{
			let len = Math.Sqrt(planes[i].X * planes[i].X + planes[i].Y * planes[i].Y + planes[i].Z * planes[i].Z);
			if (len > 0.0001f)
				planes[i] = planes[i] * (1.0f / len);
		}
	}

	private void RebuildCullBindGroup(int frameIndex, GPUSceneBuffer sceneBuffer, HiZPyramid hiZ)
	{
		if (mCullBindGroups[frameIndex] != null)
			mDevice.DestroyBindGroup(ref mCullBindGroups[frameIndex]);

		// Hi-Z view and sampler (must be valid — skip cull dispatch entirely if not ready)
		let hiZReady = hiZ != null && hiZ.Generated && hiZ.HiZView != null && hiZ.PointSampler != null;
		let hiZView = hiZReady ? hiZ.HiZView : null;
		let hiZSampler = hiZReady ? hiZ.PointSampler : null;
		if (hiZView == null || hiZSampler == null)
			return;

		BindGroupEntry[6] entries = .(
			BindGroupEntry.Buffer(mCullUniformBuffers[frameIndex]),      // b0: CullUniforms
			BindGroupEntry.Buffer(sceneBuffer.GetBuffer(frameIndex)),    // t1: ObjectData
			BindGroupEntry.Buffer(mIndirectCommandBuffers[frameIndex]),  // u2: IndirectCommands
			BindGroupEntry.Buffer(mInstanceMappingBuffers[frameIndex]),  // u3: InstanceMapping
			BindGroupEntry.Texture(hiZView),                            // t4: HiZPyramid
			BindGroupEntry.Sampler(hiZSampler)                          // s5: HiZSampler
		);

		let result = mDevice.CreateBindGroup(BindGroupDesc()
		{
			Layout = mCullBindGroupLayout,
			Entries = entries,
			Label = "GPUCullBindGroup"
		});

		if (result case .Ok(let bg))
			mCullBindGroups[frameIndex] = bg;
	}

	public void Shutdown()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mIndirectCommandBuffers[i] != null) mDevice.DestroyBuffer(ref mIndirectCommandBuffers[i]);
			if (mInstanceMappingBuffers[i] != null) mDevice.DestroyBuffer(ref mInstanceMappingBuffers[i]);
			if (mCullUniformBuffers[i] != null) { mCullUniformBuffers[i].Unmap(); mDevice.DestroyBuffer(ref mCullUniformBuffers[i]); }
			if (mCullBindGroups[i] != null) mDevice.DestroyBindGroup(ref mCullBindGroups[i]);
		}

		if (mZeroStagingBuffer != null) { mZeroStagingBuffer.Unmap(); mDevice.DestroyBuffer(ref mZeroStagingBuffer); }
		if (mCullPipeline != null) mDevice.DestroyComputePipeline(ref mCullPipeline);
		if (mCullPipelineLayout != null) mDevice.DestroyPipelineLayout(ref mCullPipelineLayout);
		if (mCullBindGroupLayout != null) mDevice.DestroyBindGroupLayout(ref mCullBindGroupLayout);
	}
}

namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// Skinning parameters uniform buffer (matches skinning_comp.hlsl cbuffer).
[CRepr]
struct SkinningParams
{
	public uint32 VertexCount;
	public uint32 BoneCount;
	public uint32[2] _Padding;
}

/// A skinned mesh draw command (post-compute, ready for render features).
struct SkinnedDraw
{
	public ProxyHandle ProxyHandle;
	public GPUMeshHandle MeshHandle;
	public MaterialInstanceHandle MaterialHandle;
	public uint32 SubMeshIndex;
	public IBuffer OutputVertexBuffer;
	/// Previous-frame skinned positions (float3 per vertex, 12 bytes). For motion vectors.
	public IBuffer PrevPositionBuffer;
	public uint64 SortKey;
}

/// GPU skinning system — uses compute shaders to transform skinned vertices
/// by bone matrices. Owned by RenderSystem as shared infrastructure.
///
/// Dispatches compute work before render graph execution. Render features
/// query OpaqueDraws/TransparentDraws to draw skinned meshes alongside
/// static mesh batches.
class SkinningSystem
{
	/// Per-mesh skinning data.
	private class SkinningInstance
	{
		/// Post-skinning vertex buffer (Storage+Vertex, 48-byte stride).
		public IBuffer OutputVertexBuffer;
		/// Previous-frame skinned positions for motion vectors (Storage, 12 bytes/vertex).
		public IBuffer PrevPositionBuffer;
		/// Skinning parameters uniform buffer (CpuToGpu, persistently mapped).
		public IBuffer ParamsBuffer;
		/// Mapped pointer to params buffer.
		public void* ParamsMappedPtr;
		/// Compute bind group (references bone buffer for current frame).
		public IBindGroup BindGroup;
		/// Last bone buffer handle (detect changes for rebind).
		public GPUBoneBufferHandle LastBoneBuffer;
		/// Last frame index the bind group was built for.
		public int LastBindGroupFrame = -1;
		/// Vertex count in the source mesh.
		public uint32 VertexCount;
		/// Whether this instance has been dispatched at least once.
		public bool HasBeenSkinned;

		/// Releases GPU resources via the device.
		public void Release(IDevice device)
		{
			if (BindGroup != null) device.DestroyBindGroup(ref BindGroup);
			if (OutputVertexBuffer != null) device.DestroyBuffer(ref OutputVertexBuffer);
			if (PrevPositionBuffer != null) device.DestroyBuffer(ref PrevPositionBuffer);
			if (ParamsBuffer != null) { ParamsBuffer.Unmap(); device.DestroyBuffer(ref ParamsBuffer); }
			ParamsMappedPtr = null;
		}
	}

	private IDevice mDevice;

	// Compute pipeline
	private IComputePipeline mPipeline;
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;

	// Per-mesh skinning instances (Release'd in Shutdown, cleaned up in destructor as fallback)
	private Dictionary<ProxyHandle, SkinningInstance> mInstances = new .() ~ {
		for (let kv in _)
		{
			if (mDevice != null) kv.value.Release(mDevice);
			delete kv.value;
		}
		delete _;
	};

	// Draw lists built each frame
	private List<SkinnedDraw> mOpaqueDraws = new .() ~ delete _;
	private List<SkinnedDraw> mTransparentDraws = new .() ~ delete _;

	/// Opaque skinned mesh draw commands for the current frame.
	public List<SkinnedDraw> OpaqueDraws => mOpaqueDraws;

	/// Transparent skinned mesh draw commands for the current frame.
	public List<SkinnedDraw> TransparentDraws => mTransparentDraws;

	/// Removes the skinning instance for a destroyed proxy.
	/// Call when a skinned mesh proxy is freed.
	public void OnProxyDestroyed(ProxyHandle handle)
	{
		if (mInstances.GetAndRemove(handle) case .Ok(let pair))
		{
			pair.value.Release(mDevice);
			delete pair.value;
		}
	}

	public Result<void> Initialize(IDevice device, ShaderLibrary shaderLib)
	{
		mDevice = device;

		// Register skinning compute shader
		if (shaderLib.RegisterShader("skinning_comp") case .Err)
			return .Err;

		// Bind group layout for compute skinning:
		// b0: SkinningParams (UBO)
		// t1: BoneMatrices (ByteAddressBuffer, raw)
		// t2: SourceVertices (ByteAddressBuffer, raw)
		// u3: OutputVertices (RWByteAddressBuffer, raw)
		// u4: PrevOutputPositions (RWByteAddressBuffer, raw)
		BindGroupLayoutEntry[5] entries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Compute),
			BindGroupLayoutEntry.StorageBuffer(1, .Compute, readWrite: false),
			BindGroupLayoutEntry.StorageBuffer(2, .Compute, readWrite: false),
			BindGroupLayoutEntry.StorageBuffer(3, .Compute, readWrite: true),
			BindGroupLayoutEntry.StorageBuffer(4, .Compute, readWrite: true)
		);

		let layoutResult = device.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = entries,
			Label = "SkinningBindGroupLayout"
		});
		if (layoutResult case .Err)
			return .Err;
		mBindGroupLayout = layoutResult.Value;

		// Pipeline layout
		IBindGroupLayout[1] bgLayouts = .(mBindGroupLayout);
		let pipeLayoutResult = device.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = bgLayouts,
			Label = "SkinningPipelineLayout"
		});
		if (pipeLayoutResult case .Err)
			return .Err;
		mPipelineLayout = pipeLayoutResult.Value;

		// Compile compute shader
		let shaderModule = shaderLib.GetCompiledShader("skinning_comp", .Compute);
		if (shaderModule case .Err)
			return .Err;

		// Create compute pipeline
		let pipeResult = device.CreateComputePipeline(ComputePipelineDesc()
		{
			Layout = mPipelineLayout,
			Compute = ProgrammableStage()
			{
				Module = shaderModule.Value,
				EntryPoint = "CSMain"
			},
			Label = "SkinningPipeline"
		});
		if (pipeResult case .Err)
			return .Err;
		mPipeline = pipeResult.Value;

		return .Ok;
	}

	/// Records compute skinning dispatches for all visible dirty skinned meshes.
	/// Call after visibility resolve, before render graph execution.
	public void RecordSkinning(
		ICommandEncoder encoder,
		int frameIndex,
		RenderWorld world,
		GPUResourceManager resources,
		VisibilityResolver visibility,
		delegate MaterialInstance(MaterialInstanceHandle) materialLookup)
	{
		mOpaqueDraws.Clear();
		mTransparentDraws.Clear();

		// Prune instances for destroyed proxies
		if (world != null && mInstances.Count > 0)
			PruneStaleInstances(world);

		if (world == null || visibility.VisibleSkinnedMeshes.Count == 0)
			return;

		// Phase 1: Ensure instances exist, update params + bind groups, collect dirty list
		List<ProxyHandle> dirtyHandles = scope .();

		for (let visible in visibility.VisibleSkinnedMeshes)
		{
			let proxy = world.SkinnedMeshes.Get(visible.Handle);
			if (proxy == null) continue;

			let gpuMesh = resources.GetMesh(visible.MeshHandle);
			if (gpuMesh == null) continue;

			// Get or create skinning instance
			SkinningInstance instance;
			if (!mInstances.TryGetValue(visible.Handle, out instance))
			{
				instance = CreateSkinningInstance(gpuMesh);
				if (instance == null) continue;
				mInstances[visible.Handle] = instance;
			}

			if (!proxy.BonesDirty) continue;

			let boneBuffer = resources.GetBoneBuffer(proxy.BoneBufferHandle);
			if (boneBuffer == null) continue;

			// Update params UBO
			if (instance.ParamsMappedPtr != null)
			{
				var sparams = SkinningParams();
				sparams.VertexCount = instance.VertexCount;
				sparams.BoneCount = proxy.BoneCount;
				Internal.MemCpy(instance.ParamsMappedPtr, &sparams, sizeof(SkinningParams));
			}

			// Rebuild bind group if bone buffer changed or new frame
			if (instance.BindGroup == null ||
				instance.LastBoneBuffer != proxy.BoneBufferHandle ||
				instance.LastBindGroupFrame != frameIndex)
			{
				RebuildBindGroup(instance, gpuMesh, boneBuffer.GetBuffer(frameIndex));
				instance.LastBoneBuffer = proxy.BoneBufferHandle;
				instance.LastBindGroupFrame = frameIndex;
			}

			if (instance.BindGroup != null)
				dirtyHandles.Add(visible.Handle);
		}

		if (dirtyHandles.Count > 0 && mPipeline != null)
		{
			// Phase 2a: Barrier bone GPU buffers → CopyDst, then copy staging → GPU
			for (let handle in dirtyHandles)
			{
				let proxy = world.SkinnedMeshes.Get(handle);
				if (proxy == null) continue;
				let boneBuffer = resources.GetBoneBuffer(proxy.BoneBufferHandle);
				if (boneBuffer == null) continue;
				if (boneBuffer.NeedsUpload[frameIndex])
				{
					// Transition GPU buffer to CopyDst before copy
					BufferBarrier[1] copyBarrier = .(.()
					{
						Buffer = boneBuffer.Buffers[frameIndex],
						OldState = boneBuffer.HasBeenUsed[frameIndex] ? .ShaderRead : .Undefined,
						NewState = .CopyDst
					});
					encoder.Barrier(BarrierGroup()
					{
						BufferBarriers = Span<BufferBarrier>(&copyBarrier[0], 1)
					});

					encoder.CopyBufferToBuffer(
						boneBuffer.StagingBuffers[frameIndex], 0,
						boneBuffer.Buffers[frameIndex], 0,
						boneBuffer.Size);
					boneBuffer.NeedsUpload[frameIndex] = false;
					boneBuffer.HasBeenUsed[frameIndex] = true;
				}
			}

			// Phase 2b: Pre-compute barriers (output VBs + prev pos → ShaderWrite, bone buffers CopyDst → ShaderRead)
			for (let handle in dirtyHandles)
			{
				let instance = mInstances[handle];
				let proxy = world.SkinnedMeshes.Get(handle);
				let boneBuffer = (proxy != null) ? resources.GetBoneBuffer(proxy.BoneBufferHandle) : null;

				int barrierCount = 2;
				BufferBarrier[3] barriers = .();
				barriers[0] = .()
				{
					Buffer = instance.OutputVertexBuffer,
					OldState = instance.HasBeenSkinned ? .VertexBuffer : .Undefined,
					NewState = .ShaderWrite
				};
				barriers[1] = .()
				{
					Buffer = instance.PrevPositionBuffer,
					OldState = instance.HasBeenSkinned ? .VertexBuffer : .Undefined,
					NewState = .ShaderWrite
				};
				if (boneBuffer != null)
				{
					barriers[2] = .()
					{
						Buffer = boneBuffer.Buffers[frameIndex],
						OldState = .CopyDst,
						NewState = .ShaderRead
					};
					barrierCount = 3;
				}
				encoder.Barrier(BarrierGroup()
				{
					BufferBarriers = Span<BufferBarrier>(&barriers[0], barrierCount)
				});
			}

			// Phase 3: Dispatch all skinning in one compute pass
			let cp = encoder.BeginComputePass("GPUSkinning");
			cp.SetPipeline(mPipeline);

			for (let handle in dirtyHandles)
			{
				let instance = mInstances[handle];
				cp.SetBindGroup(0, instance.BindGroup);
				cp.Dispatch((instance.VertexCount + 63) / 64);
				instance.HasBeenSkinned = true;
			}

			cp.End();

			// Phase 4: Post-compute barriers (output VBs + prev pos → Vertex)
			for (let handle in dirtyHandles)
			{
				let instance = mInstances[handle];
				BufferBarrier[2] barriers = .(
					.() { Buffer = instance.OutputVertexBuffer, OldState = .ShaderWrite, NewState = .VertexBuffer },
					.() { Buffer = instance.PrevPositionBuffer, OldState = .ShaderWrite, NewState = .VertexBuffer }
				);
				encoder.Barrier(BarrierGroup()
				{
					BufferBarriers = Span<BufferBarrier>(&barriers[0], 2)
				});
			}

			// Clear dirty flags
			for (let handle in dirtyHandles)
			{
				let proxy = world.SkinnedMeshes.Get(handle);
				if (proxy != null)
					proxy.BonesDirty = false;
			}
		}

		// Phase 5: Build draw lists
		BuildDrawLists(visibility, world, resources, materialLookup);
	}

	private void BuildDrawLists(
		VisibilityResolver visibility,
		RenderWorld world,
		GPUResourceManager resources,
		delegate MaterialInstance(MaterialInstanceHandle) materialLookup)
	{
		for (let visible in visibility.VisibleSkinnedMeshes)
		{
			let proxy = world.SkinnedMeshes.Get(visible.Handle);
			if (proxy == null) continue;

			SkinningInstance instance;
			if (!mInstances.TryGetValue(visible.Handle, out instance)) continue;
			if (!instance.HasBeenSkinned) continue;

			let gpuMesh = resources.GetMesh(visible.MeshHandle);
			if (gpuMesh == null) continue;

			// Determine submesh range for selected LOD
			uint32 subStart = 0;
			uint32 subCount = (uint32)gpuMesh.SubMeshes.Count;

			if (gpuMesh.LODCount > 0 && gpuMesh.LODLevels != null)
			{
				let lodIdx = Math.Min((uint32)visible.LODLevel, gpuMesh.LODCount - 1);
				let lod = gpuMesh.LODLevels[lodIdx];
				subStart = lod.SubMeshStart;
				subCount = lod.SubMeshCount;
			}

			for (uint32 si = subStart; si < subStart + subCount; si++)
			{
				if (si >= (uint32)gpuMesh.SubMeshes.Count) break;

				let subMesh = gpuMesh.SubMeshes[si];
				let matSlot = subMesh.MaterialSlot;

				let materialHandle = (matSlot < proxy.MaterialCount)
					? proxy.Materials[matSlot]
					: MaterialInstanceHandle.Invalid;

				let draw = SkinnedDraw()
				{
					ProxyHandle = visible.Handle,
					MeshHandle = visible.MeshHandle,
					MaterialHandle = materialHandle,
					SubMeshIndex = si,
					OutputVertexBuffer = instance.OutputVertexBuffer,
					PrevPositionBuffer = instance.PrevPositionBuffer,
					SortKey = visible.SortKey
				};

				// Route to opaque or transparent based on material
				bool isTransparent = false;
				if (materialLookup != null)
				{
					let matInst = materialLookup(materialHandle);
					if (matInst != null && matInst.Definition.BlendMode != .Opaque)
						isTransparent = true;
				}

				if (isTransparent)
					mTransparentDraws.Add(draw);
				else
					mOpaqueDraws.Add(draw);
			}
		}

		// Sort by material (sort key has material in high bits)
		mOpaqueDraws.Sort(scope (a, b) => a.SortKey <=> b.SortKey);
		mTransparentDraws.Sort(scope (a, b) => b.SortKey <=> a.SortKey);
	}

	/// Removes skinning instances whose proxy handles are no longer valid.
	private void PruneStaleInstances(RenderWorld world)
	{
		List<ProxyHandle> stale = scope .();
		for (let kv in mInstances)
		{
			if (world.SkinnedMeshes.Get(kv.key) == null)
				stale.Add(kv.key);
		}
		for (let handle in stale)
		{
			if (mInstances.GetAndRemove(handle) case .Ok(let pair))
			{
				pair.value.Release(mDevice);
				delete pair.value;
			}
		}
	}

	private SkinningInstance CreateSkinningInstance(GPUMesh gpuMesh)
	{
		let outputSize = (uint64)(gpuMesh.VertexCount * 48); // StaticMeshVertex stride

		// Create output vertex buffer (Storage for compute write + Vertex for rendering)
		let vbResult = mDevice.CreateBuffer(BufferDesc()
		{
			Size = outputSize,
			Usage = .Storage | .Vertex,
			Memory = .GpuOnly,
			Label = "SkinnedOutput"
		});
		if (vbResult case .Err)
			return null;

		// Create previous-frame position buffer for motion vectors (float3 per vertex)
		let prevPosSize = (uint64)(gpuMesh.VertexCount * 12);
		let prevPosResult = mDevice.CreateBuffer(BufferDesc()
		{
			Size = prevPosSize,
			Usage = .Storage | .Vertex,
			Memory = .GpuOnly,
			Label = "SkinnedPrevPos"
		});
		if (prevPosResult case .Err)
		{
			var vb = vbResult.Value;
			mDevice.DestroyBuffer(ref vb);
			return null;
		}

		// Create params UBO (CpuToGpu, persistently mapped)
		let paramsResult = mDevice.CreateBuffer(BufferDesc()
		{
			Size = (uint64)sizeof(SkinningParams),
			Usage = .Uniform,
			Memory = .CpuToGpu,
			Label = "SkinningParams"
		});
		if (paramsResult case .Err)
		{
			var vb = vbResult.Value;
			mDevice.DestroyBuffer(ref vb);
			var pp = prevPosResult.Value;
			mDevice.DestroyBuffer(ref pp);
			return null;
		}

		let instance = new SkinningInstance();
		instance.OutputVertexBuffer = vbResult.Value;
		instance.PrevPositionBuffer = prevPosResult.Value;
		instance.ParamsBuffer = paramsResult.Value;
		instance.ParamsMappedPtr = instance.ParamsBuffer.Map();
		instance.VertexCount = gpuMesh.VertexCount;
		return instance;
	}

	private void RebuildBindGroup(SkinningInstance instance, GPUMesh gpuMesh, IBuffer boneBuffer)
	{
		if (instance.BindGroup != null)
			mDevice.DestroyBindGroup(ref instance.BindGroup);

		if (gpuMesh == null || boneBuffer == null)
			return;

		BindGroupEntry[5] entries = .(
			BindGroupEntry.Buffer(instance.ParamsBuffer),       // b0: SkinningParams
			BindGroupEntry.Buffer(boneBuffer),                  // t1: BoneMatrices
			BindGroupEntry.Buffer(gpuMesh.VertexBuffer),        // t2: SourceVertices
			BindGroupEntry.Buffer(instance.OutputVertexBuffer), // u3: OutputVertices
			BindGroupEntry.Buffer(instance.PrevPositionBuffer)  // u4: PrevOutputPositions
		);

		let result = mDevice.CreateBindGroup(BindGroupDesc()
		{
			Layout = mBindGroupLayout,
			Entries = entries,
			Label = "SkinningBindGroup"
		});

		if (result case .Ok(let bg))
			instance.BindGroup = bg;
	}

	public void Shutdown()
	{
		for (let kv in mInstances)
		{
			kv.value.Release(mDevice);
			delete kv.value;
		}
		mInstances.Clear();

		if (mPipeline != null)
			mDevice.DestroyComputePipeline(ref mPipeline);
		if (mPipelineLayout != null)
			mDevice.DestroyPipelineLayout(ref mPipelineLayout);
		if (mBindGroupLayout != null)
			mDevice.DestroyBindGroupLayout(ref mBindGroupLayout);
	}
}

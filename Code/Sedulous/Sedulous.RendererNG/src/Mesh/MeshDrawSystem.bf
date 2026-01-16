namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;

/// System for rendering static and skinned meshes.
/// Handles batching, instancing, and draw call submission.
class MeshDrawSystem : IDisposable
{
	private IDevice mDevice;
	private MeshPool mMeshPool;
	private TransientBufferPool mTransientPool;
	private PipelineFactory mPipelineFactory;
	private BindGroupLayoutCache mLayoutCache;

	/// Collected instance references for current frame.
	private List<MeshInstanceRef> mInstances = new .() ~ delete _;

	/// Built batches for current frame.
	private List<MeshDrawBatch> mBatches = new .() ~ delete _;

	/// Batch lookup by key.
	private Dictionary<BatchKey, int> mBatchLookup = new .() ~ delete _;

	/// Instance data buffer allocation for current frame.
	private TransientAllocation mInstanceAllocation;

	/// Bone matrix buffer allocation for current frame (skinned meshes).
	private TransientAllocation mBoneAllocation;

	/// Maximum instances per frame.
	public const int MaxInstances = 8192;

	/// Maximum bone matrices per frame.
	public const int MaxBoneMatrices = 4096;

	/// Size of a single bone matrix in bytes.
	public const uint32 BoneMatrixSize = 64; // sizeof(Matrix)

	/// Stats
	public int InstanceCount => mInstances.Count;
	public int BatchCount => mBatches.Count;
	public int SkinnedInstanceCount { get; private set; }
	public int TotalBoneCount { get; private set; }

	/// Initializes the mesh draw system.
	public void Initialize(IDevice device, MeshPool meshPool, TransientBufferPool transientPool,
						   PipelineFactory pipelineFactory, BindGroupLayoutCache layoutCache)
	{
		mDevice = device;
		mMeshPool = meshPool;
		mTransientPool = transientPool;
		mPipelineFactory = pipelineFactory;
		mLayoutCache = layoutCache;
	}

	/// Begins a new frame, clearing previous data.
	public void BeginFrame()
	{
		mInstances.Clear();
		mBatches.Clear();
		mBatchLookup.Clear();
		mInstanceAllocation = default;
		mBoneAllocation = default;
		SkinnedInstanceCount = 0;
		TotalBoneCount = 0;
	}

	/// Adds a mesh instance for rendering.
	public void AddInstance(MeshHandle mesh, MaterialInstance material, MeshInstanceData instanceData, uint32 submeshIndex = 0)
	{
		if (mInstances.Count >= MaxInstances)
			return;

		var instance = MeshInstanceRef(mesh, material, instanceData);
		instance.SubmeshIndex = submeshIndex;
		mInstances.Add(instance);
	}

	/// Adds a skinned mesh instance for rendering.
	/// boneMatrices must remain valid until BuildBatches() is called.
	public void AddSkinnedInstance(MeshHandle mesh, MaterialInstance material, MeshInstanceData instanceData,
								   Matrix* boneMatrices, uint32 boneCount, uint32 submeshIndex = 0)
	{
		if (mInstances.Count >= MaxInstances)
			return;

		if (TotalBoneCount + (int)boneCount > MaxBoneMatrices)
			return;

		var instance = MeshInstanceRef(mesh, material, instanceData, boneMatrices, boneCount);
		instance.SubmeshIndex = submeshIndex;
		mInstances.Add(instance);

		SkinnedInstanceCount++;
		TotalBoneCount += (int)boneCount;
	}

	/// Adds a mesh instance from a static mesh proxy.
	public void AddFromProxy(StaticMeshProxy* proxy, MeshPool meshPool, MaterialInstance material)
	{
		if (proxy == null || !proxy.IsVisible)
			return;

		// Build instance data from proxy transform
		var instanceData = MeshInstanceData();
		instanceData.WorldMatrix = proxy.Transform;
		Matrix.Invert(proxy.Transform, var invWorld);
		instanceData.NormalMatrix = Matrix.Transpose(invWorld);

		// Get mesh handle
		let meshHandle = MeshHandle(proxy.MeshHandle, 1); // Assume gen 1 for now

		// Add all submeshes
		let gpuMesh = meshPool.Get(meshHandle);
		if (gpuMesh == null)
			return;

		for (uint32 i = 0; i < gpuMesh.Submeshes.Count; i++)
		{
			AddInstance(meshHandle, material, instanceData, i);
		}
	}

	/// Builds batches from collected instances.
	/// Call after all AddInstance calls, before Render.
	public void BuildBatches()
	{
		if (mInstances.Count == 0)
			return;

		// Sort instances by batch key for optimal batching
		// (In production, would use a proper sorting algorithm)

		// Build batches
		for (int i = 0; i < mInstances.Count; i++)
		{
			let instance = ref mInstances[i];
			let key = BatchKey(instance.Mesh, instance.SubmeshIndex, instance.Material);

			if (mBatchLookup.TryGetValue(key, let batchIndex))
			{
				// Add to existing batch
				mBatches[batchIndex].InstanceCount++;
				if (instance.IsSkinned)
					mBatches[batchIndex].TotalBoneCount += instance.BoneCount;
			}
			else
			{
				// Create new batch
				var batch = MeshDrawBatch();
				batch.Mesh = instance.Mesh;
				batch.SubmeshIndex = instance.SubmeshIndex;
				batch.Material = instance.Material;
				batch.InstanceCount = 1;
				batch.IsSkinned = instance.IsSkinned;
				batch.TotalBoneCount = instance.BoneCount;

				let newIndex = mBatches.Count;
				mBatches.Add(batch);
				mBatchLookup[key] = newIndex;
			}
		}

		// Compute instance offsets and allocate buffer
		uint32 totalInstances = 0;
		for (var batch in ref mBatches)
		{
			batch.InstanceOffset = totalInstances;
			totalInstances += batch.InstanceCount;
		}

		// Allocate transient buffer for instance data
		let instanceDataSize = totalInstances * MeshInstanceData.Size;
		if (instanceDataSize > 0)
		{
			let alloc = mTransientPool.AllocateRawVertex(instanceDataSize);
			if (alloc.IsValid)
			{
				mInstanceAllocation = alloc;
			}
		}

		// Allocate bone buffer for skinned meshes
		if (TotalBoneCount > 0)
		{
			// Compute bone buffer offsets per batch
			uint32 totalBoneOffset = 0;
			for (var batch in ref mBatches)
			{
				if (batch.IsSkinned && batch.TotalBoneCount > 0)
				{
					batch.BoneBufferOffset = totalBoneOffset * BoneMatrixSize;
					totalBoneOffset += batch.TotalBoneCount;
				}
			}

			// Allocate bone buffer (uses uniform buffer for shader access)
			let boneBufferSize = (uint32)TotalBoneCount * BoneMatrixSize;
			let boneAlloc = mTransientPool.AllocateRawUniform(boneBufferSize);
			if (boneAlloc.IsValid)
			{
				mBoneAllocation = boneAlloc;
			}
		}

		// Upload all data
		UploadInstanceData();
		UploadBoneData();
	}

	/// Uploads instance data to the transient buffer.
	private void UploadInstanceData()
	{
		if (!mInstanceAllocation.IsValid)
			return;

		// Fill instance data in batch order using the mapped memory
		uint32[] batchCounts = scope uint32[mBatches.Count];

		for (let instance in mInstances)
		{
			let key = BatchKey(instance.Mesh, instance.SubmeshIndex, instance.Material);
			if (mBatchLookup.TryGetValue(key, let batchIndex))
			{
				let batch = mBatches[batchIndex];
				let offset = batch.InstanceOffset + batchCounts[batchIndex];

				// Write directly to mapped memory
				let destPtr = (MeshInstanceData*)((uint8*)mInstanceAllocation.Data + offset * MeshInstanceData.Size);
				*destPtr = instance.InstanceData;
				batchCounts[batchIndex]++;
			}
		}
	}

	/// Uploads bone matrices to the transient buffer.
	private void UploadBoneData()
	{
		if (!mBoneAllocation.IsValid || TotalBoneCount == 0)
			return;

		// Track bone offset per batch
		uint32[] batchBoneOffsets = scope uint32[mBatches.Count];

		for (let instance in mInstances)
		{
			if (!instance.IsSkinned)
				continue;

			let key = BatchKey(instance.Mesh, instance.SubmeshIndex, instance.Material);
			if (mBatchLookup.TryGetValue(key, let batchIndex))
			{
				let batch = mBatches[batchIndex];

				// Compute destination offset in bone buffer
				let boneOffset = batch.BoneBufferOffset + batchBoneOffsets[batchIndex] * BoneMatrixSize;
				let destPtr = (Matrix*)((uint8*)mBoneAllocation.Data + boneOffset);

				// Copy bone matrices
				Internal.MemCpy(destPtr, instance.BoneMatrices, instance.BoneCount * BoneMatrixSize);
				batchBoneOffsets[batchIndex] += instance.BoneCount;
			}
		}
	}

	/// Renders all batched meshes.
	public void Render(IRenderPassEncoder renderPass, IPipelineLayout layout)
	{
		if (mBatches.Count == 0)
			return;

		MeshHandle lastMesh = .Invalid;

		for (let batch in mBatches)
		{
			let gpuMesh = mMeshPool.Get(batch.Mesh);
			if (gpuMesh == null || !gpuMesh.IsValid)
				continue;

			// Bind mesh buffers if changed
			if (batch.Mesh != lastMesh)
			{
				renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);
				renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
				lastMesh = batch.Mesh;
			}

			// Bind instance buffer (slot 1)
			if (mInstanceAllocation.Buffer != null)
			{
				let instanceOffset = mInstanceAllocation.Offset + batch.InstanceOffset * MeshInstanceData.Size;
				renderPass.SetVertexBuffer(1, mInstanceAllocation.Buffer, instanceOffset);
			}

			// Get submesh
			if (batch.SubmeshIndex >= gpuMesh.Submeshes.Count)
				continue;

			let submesh = gpuMesh.Submeshes[batch.SubmeshIndex];

			// Draw instanced
			renderPass.DrawIndexed(submesh.IndexCount, batch.InstanceCount, submesh.IndexOffset, 0, 0);
		}
	}

	/// Renders a single batch (for custom rendering).
	public void RenderBatch(IRenderPassEncoder renderPass, int batchIndex)
	{
		if (batchIndex < 0 || batchIndex >= mBatches.Count)
			return;

		let batch = mBatches[batchIndex];
		let gpuMesh = mMeshPool.Get(batch.Mesh);
		if (gpuMesh == null || !gpuMesh.IsValid)
			return;

		// Bind mesh buffers
		renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);
		renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);

		// Bind instance buffer
		if (mInstanceAllocation.Buffer != null)
		{
			let instanceOffset = mInstanceAllocation.Offset + batch.InstanceOffset * MeshInstanceData.Size;
			renderPass.SetVertexBuffer(1, mInstanceAllocation.Buffer, instanceOffset);
		}

		// Get submesh
		if (batch.SubmeshIndex >= gpuMesh.Submeshes.Count)
			return;

		let submesh = gpuMesh.Submeshes[batch.SubmeshIndex];

		// Draw
		renderPass.DrawIndexed(submesh.IndexCount, batch.InstanceCount, submesh.IndexOffset, 0, 0);
	}

	/// Gets statistics.
	public void GetStats(String outStats)
	{
		outStats.AppendF("Mesh Draw System:\n");
		outStats.AppendF("  Instances: {} ({} skinned)\n", mInstances.Count, SkinnedInstanceCount);
		outStats.AppendF("  Batches: {}\n", mBatches.Count);
		if (mInstanceAllocation.Buffer != null)
			outStats.AppendF("  Instance buffer: {} bytes\n", mInstances.Count * MeshInstanceData.Size);
		if (mBoneAllocation.Buffer != null)
			outStats.AppendF("  Bone buffer: {} matrices ({} bytes)\n", TotalBoneCount, TotalBoneCount * BoneMatrixSize);
	}

	/// Gets the bone buffer allocation for binding to shaders.
	public TransientAllocation BoneBuffer => mBoneAllocation;

	public void Dispose()
	{
		// Transient buffer is not owned
	}

	// ========================================================================
	// Render Graph Integration
	// ========================================================================

	/// Adds an opaque mesh rendering pass to the render graph.
	/// Opaque meshes are rendered with depth write enabled.
	public PassBuilder AddOpaquePass(
		RenderGraph graph,
		RGResourceHandle colorTarget,
		RGResourceHandle depthTarget,
		IPipelineLayout pipelineLayout)
	{
		MeshPassData passData;
		passData.DrawSystem = this;
		passData.MeshPool = mMeshPool;
		passData.PipelineLayout = pipelineLayout;
		passData.IsOpaque = true;

		return graph.AddGraphicsPass("OpaqueGeometry")
			.SetColorAttachment(0, colorTarget, .Load, .Store)
			.SetDepthAttachment(depthTarget, .Load, .Store)
			.SetFlags(.NeverCull)
			.SetExecute(new (encoder) => {
				passData.DrawSystem.RenderOpaqueBatches(encoder, passData.PipelineLayout);
			});
	}

	/// Adds a transparent mesh rendering pass to the render graph.
	/// Transparent meshes are rendered with depth test but no depth write.
	public PassBuilder AddTransparentPass(
		RenderGraph graph,
		RGResourceHandle colorTarget,
		RGResourceHandle depthTarget,
		IPipelineLayout pipelineLayout)
	{
		MeshPassData passData;
		passData.DrawSystem = this;
		passData.MeshPool = mMeshPool;
		passData.PipelineLayout = pipelineLayout;
		passData.IsOpaque = false;

		return graph.AddGraphicsPass("TransparentGeometry")
			.SetColorAttachment(0, colorTarget, .Load, .Store)
			.SetDepthAttachmentReadOnly(depthTarget)
			.SetFlags(.NeverCull)
			.SetExecute(new (encoder) => {
				passData.DrawSystem.RenderTransparentBatches(encoder, passData.PipelineLayout);
			});
	}

	/// Adds a shadow rendering pass for mesh shadow casters.
	public PassBuilder AddShadowPass(
		RenderGraph graph,
		StringView passName,
		RGResourceHandle depthTarget,
		IPipelineLayout pipelineLayout)
	{
		MeshPassData passData;
		passData.DrawSystem = this;
		passData.MeshPool = mMeshPool;
		passData.PipelineLayout = pipelineLayout;
		passData.IsOpaque = true;

		return graph.AddGraphicsPass(passName)
			.SetDepthAttachment(depthTarget, .Clear, .Store)
			.SetExecute(new (encoder) => {
				passData.DrawSystem.RenderShadowBatches(encoder, passData.PipelineLayout);
			});
	}

	/// Renders only opaque batches (for render graph pass).
	public void RenderOpaqueBatches(IRenderPassEncoder renderPass, IPipelineLayout layout)
	{
		if (mBatches.Count == 0)
			return;

		MeshHandle lastMesh = .Invalid;

		for (let batch in mBatches)
		{
			// Skip transparent batches - check if material has non-opaque blend mode
			if (batch.Material != null && batch.Material.Material.PipelineConfig.BlendMode != BlendMode.Opaque)
				continue;

			RenderSingleBatch(renderPass, batch, ref lastMesh);
		}
	}

	/// Renders only transparent batches (for render graph pass).
	public void RenderTransparentBatches(IRenderPassEncoder renderPass, IPipelineLayout layout)
	{
		if (mBatches.Count == 0)
			return;

		MeshHandle lastMesh = .Invalid;

		for (let batch in mBatches)
		{
			// Skip opaque batches - only render non-opaque materials
			if (batch.Material == null || batch.Material.Material.PipelineConfig.BlendMode == BlendMode.Opaque)
				continue;

			RenderSingleBatch(renderPass, batch, ref lastMesh);
		}
	}

	/// Renders shadow caster batches (for shadow pass).
	public void RenderShadowBatches(IRenderPassEncoder renderPass, IPipelineLayout layout)
	{
		if (mBatches.Count == 0)
			return;

		MeshHandle lastMesh = .Invalid;

		for (let batch in mBatches)
		{
			// Only render shadow casters (check ShaderFlags for CastShadows)
			if (batch.Material != null && !batch.Material.Material.ShaderFlags.HasFlag(.CastShadows))
				continue;

			RenderSingleBatch(renderPass, batch, ref lastMesh);
		}
	}

	/// Renders a single batch (helper for graph passes).
	private void RenderSingleBatch(IRenderPassEncoder renderPass, MeshDrawBatch batch, ref MeshHandle lastMesh)
	{
		let gpuMesh = mMeshPool.Get(batch.Mesh);
		if (gpuMesh == null || !gpuMesh.IsValid)
			return;

		// Bind mesh buffers if changed
		if (batch.Mesh != lastMesh)
		{
			renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);
			renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
			lastMesh = batch.Mesh;
		}

		// Bind instance buffer (slot 1)
		if (mInstanceAllocation.Buffer != null)
		{
			let instanceOffset = mInstanceAllocation.Offset + batch.InstanceOffset * MeshInstanceData.Size;
			renderPass.SetVertexBuffer(1, mInstanceAllocation.Buffer, instanceOffset);
		}

		// Get submesh
		if (batch.SubmeshIndex >= gpuMesh.Submeshes.Count)
			return;

		let submesh = gpuMesh.Submeshes[batch.SubmeshIndex];

		// Draw instanced
		renderPass.DrawIndexed(submesh.IndexCount, batch.InstanceCount, submesh.IndexOffset, 0, 0);
	}
}

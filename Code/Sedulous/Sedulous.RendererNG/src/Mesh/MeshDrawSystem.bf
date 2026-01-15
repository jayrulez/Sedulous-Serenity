namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

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

	/// Maximum instances per frame.
	public const int MaxInstances = 8192;

	/// Stats
	public int InstanceCount => mInstances.Count;
	public int BatchCount => mBatches.Count;

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
	}

	/// Adds a mesh instance for rendering.
	public void AddInstance(MeshHandle mesh, MaterialInstance* material, MeshInstanceData instanceData, uint32 submeshIndex = 0)
	{
		if (mInstances.Count >= MaxInstances)
			return;

		var instance = MeshInstanceRef(mesh, material, instanceData);
		instance.SubmeshIndex = submeshIndex;
		mInstances.Add(instance);
	}

	/// Adds a mesh instance from a static mesh proxy.
	public void AddFromProxy(StaticMeshProxy* proxy, MeshPool meshPool, MaterialInstance* material)
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
			}
			else
			{
				// Create new batch
				var batch = MeshDrawBatch();
				batch.Mesh = instance.Mesh;
				batch.SubmeshIndex = instance.SubmeshIndex;
				batch.Material = instance.Material;
				batch.InstanceCount = 1;

				let gpuMesh = mMeshPool.Get(instance.Mesh);
				if (gpuMesh != null)
					batch.IsSkinned = gpuMesh.IsSkinned;

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
				UploadInstanceData();
			}
		}
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
		outStats.AppendF("  Instances: {}\n", mInstances.Count);
		outStats.AppendF("  Batches: {}\n", mBatches.Count);
		if (mInstanceAllocation.Buffer != null)
			outStats.AppendF("  Instance buffer: {} bytes\n", mInstances.Count * MeshInstanceData.Size);
	}

	public void Dispose()
	{
		// Transient buffer is not owned
	}
}

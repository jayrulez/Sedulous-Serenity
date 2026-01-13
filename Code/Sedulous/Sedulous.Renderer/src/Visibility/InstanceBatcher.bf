namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Per-instance data uploaded to GPU.
[CRepr, Packed]
struct InstanceData
{
	/// World transform (model matrix).
	public Matrix WorldMatrix;

	/// Previous frame's world matrix (for motion vectors).
	public Matrix PreviousWorldMatrix;

	/// Material instance ID.
	public uint32 MaterialId;

	/// Object ID (for picking/selection).
	public uint32 ObjectId;

	/// Padding to 16-byte alignment.
	public uint32 Pad0;
	public uint32 Pad1;

	/// Size of this structure in bytes.
	public const int32 SizeInBytes = 160;
}

/// A batch of instances sharing the same mesh and material.
struct InstanceBatch
{
	/// GPU mesh handle.
	public GPUStaticMeshHandle MeshHandle;

	/// Primary material ID.
	public uint32 MaterialId;

	/// Sub-mesh index (-1 for all sub-meshes).
	public int32 SubMeshIndex;

	/// Number of instances in this batch.
	public int32 InstanceCount;

	/// Offset into the instance buffer.
	public int32 InstanceOffset;

	/// Is this batch for skinned meshes?
	public bool IsSkinned;

	/// Is this batch for transparent objects?
	public bool IsTransparent;
}

/// Groups similar mesh/material combinations for instanced rendering.
class InstanceBatcher
{
	/// Key for grouping instances.
	private struct BatchKey : IHashable, IEquatable<BatchKey>
	{
		public GPUStaticMeshHandle MeshHandle;
		public uint32 MaterialId;
		public int32 SubMeshIndex;
		public bool IsSkinned;

		public int GetHashCode()
		{
			int32 hash = (int32)MeshHandle.Index;
			hash = hash * 31 + (int32)MaterialId;
			hash = hash * 31 + SubMeshIndex;
			hash = hash * 31 + (IsSkinned ? 1 : 0);
			return hash;
		}

		public bool Equals(BatchKey other)
		{
			return MeshHandle.Equals(other.MeshHandle) &&
				   MaterialId == other.MaterialId &&
				   SubMeshIndex == other.SubMeshIndex &&
				   IsSkinned == other.IsSkinned;
		}
	}

	/// Per-batch instance data.
	private struct BatchData
	{
		public List<InstanceData> Instances;
		public BatchKey Key;

		public void Dispose() mut
		{
			if (Instances != null)
			{
				delete Instances;
				Instances = null;
			}
		}
	}

	private Dictionary<BatchKey, int32> mBatchLookup = new .() ~ delete _;
	private List<BatchData> mBatches = new .() ~ { for (var batch in _) batch.Dispose(); delete _; };
	private List<InstanceData> mInstanceData = new .() ~ delete _;
	private List<InstanceBatch> mOutputBatches = new .() ~ delete _;

	/// Minimum instances for batching (below this, draw individually).
	public int32 MinInstancesForBatching = 2;

	/// Maximum instances per batch.
	public int32 MaxInstancesPerBatch = 1024;

	/// Gets the generated batches.
	public List<InstanceBatch> Batches => mOutputBatches;

	/// Gets all instance data for upload.
	public List<InstanceData> InstanceData => mInstanceData;

	/// Clears all batch data.
	public void Clear()
	{
		mBatchLookup.Clear();
		for (var batch in mBatches)
			batch.Dispose();
		mBatches.Clear();
		mInstanceData.Clear();
		mOutputBatches.Clear();
	}

	/// Adds mesh proxies to batching.
	public void AddMeshes(List<StaticMeshProxy*> meshes)
	{
		for (let mesh in meshes)
		{
			// Skip skinned meshes (need individual bone data)
			if (mesh.IsSkinned)
			{
				AddSingleInstance(mesh);
				continue;
			}

			// Create key for this mesh/material combo
			BatchKey key;
			key.MeshHandle = mesh.MeshHandle;
			key.MaterialId = (mesh.MaterialCount > 0) ? mesh.MaterialIds[0] : 0;
			key.SubMeshIndex = 0; // For now, batch by first sub-mesh
			key.IsSkinned = false;

			// Find or create batch
			int32 batchIndex;
			if (!mBatchLookup.TryGetValue(key, out batchIndex))
			{
				batchIndex = (int32)mBatches.Count;
				mBatchLookup[key] = batchIndex;

				BatchData newBatch;
				newBatch.Key = key;
				newBatch.Instances = new List<InstanceData>();
				mBatches.Add(newBatch);
			}

			// Add instance data
			InstanceData instance;
			instance.WorldMatrix = mesh.Transform;
			instance.PreviousWorldMatrix = mesh.PreviousTransform;
			instance.MaterialId = key.MaterialId;
			instance.ObjectId = mesh.Id;
			instance.Pad0 = 0;
			instance.Pad1 = 0;

			mBatches[batchIndex].Instances.Add(instance);
		}
	}

	/// Adds a single instance (for skinned meshes or unbatchable objects).
	private void AddSingleInstance(StaticMeshProxy* mesh)
	{
		BatchKey key;
		key.MeshHandle = mesh.MeshHandle;
		key.MaterialId = (mesh.MaterialCount > 0) ? mesh.MaterialIds[0] : 0;
		key.SubMeshIndex = 0;
		key.IsSkinned = mesh.IsSkinned;

		// Always create a new batch for skinned meshes
		int32 batchIndex = (int32)mBatches.Count;

		BatchData newBatch;
		newBatch.Key = key;
		newBatch.Instances = new List<InstanceData>();
		mBatches.Add(newBatch);

		InstanceData instance;
		instance.WorldMatrix = mesh.Transform;
		instance.PreviousWorldMatrix = mesh.PreviousTransform;
		instance.MaterialId = key.MaterialId;
		instance.ObjectId = mesh.Id;
		instance.Pad0 = 0;
		instance.Pad1 = 0;

		mBatches[batchIndex].Instances.Add(instance);
	}

	/// Finalizes batches and prepares for rendering.
	public void FinalizeBatches()
	{
		mOutputBatches.Clear();
		mInstanceData.Clear();

		for (let batch in mBatches)
		{
			if (batch.Instances.Count == 0)
				continue;

			// Split into max-sized batches
			int32 remaining = (int32)batch.Instances.Count;
			int32 srcOffset = 0;

			while (remaining > 0)
			{
				int32 count = Math.Min(remaining, MaxInstancesPerBatch);

				InstanceBatch outputBatch;
				outputBatch.MeshHandle = batch.Key.MeshHandle;
				outputBatch.MaterialId = batch.Key.MaterialId;
				outputBatch.SubMeshIndex = batch.Key.SubMeshIndex;
				outputBatch.IsSkinned = batch.Key.IsSkinned;
				outputBatch.IsTransparent = false;
				outputBatch.InstanceCount = count;
				outputBatch.InstanceOffset = (int32)mInstanceData.Count;

				// Copy instance data
				for (int32 i = 0; i < count; i++)
					mInstanceData.Add(batch.Instances[srcOffset + i]);

				mOutputBatches.Add(outputBatch);

				srcOffset += count;
				remaining -= count;
			}
		}
	}

	/// Returns true if a batch should use instanced rendering.
	public static bool ShouldUseInstancing(InstanceBatch batch, int32 minInstances = 2)
	{
		return batch.InstanceCount >= minInstances && !batch.IsSkinned;
	}

	// ==================== Statistics ====================

	/// Total number of instances.
	public int32 TotalInstances => (int32)mInstanceData.Count;

	/// Number of batches.
	public int32 BatchCount => (int32)mOutputBatches.Count;

	/// Number of draw calls saved by batching.
	public int32 DrawCallsSaved
	{
		get
		{
			int32 saved = 0;
			for (let batch in mOutputBatches)
			{
				if (batch.InstanceCount > 1)
					saved += batch.InstanceCount - 1;
			}
			return saved;
		}
	}
}

namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;
using Sedulous.Materials;

/// A single draw command for a mesh.
public struct DrawCommand
{
	/// Handle to the mesh proxy.
	public MeshProxyHandle MeshHandle;

	/// GPU mesh handle for vertex/index data.
	public GPUMeshHandle GPUMesh;

	/// Cached material instance (avoids proxy lookups during sort/batch).
	public MaterialInstance Material;

	/// World transform matrix.
	public Matrix WorldMatrix;

	/// Previous frame world matrix (for motion vectors).
	public Matrix PrevWorldMatrix;

	/// LOD level for this draw.
	public uint8 LODLevel;
}

/// A single draw command for a skinned mesh.
public struct SkinnedDrawCommand
{
	/// Handle to the skinned mesh proxy.
	public SkinnedMeshProxyHandle MeshHandle;

	/// GPU mesh handle.
	public GPUMeshHandle GPUMesh;

	/// Bone buffer handle.
	public GPUBoneBufferHandle BoneBuffer;

	/// World transform matrix.
	public Matrix WorldMatrix;

	/// Previous frame world matrix.
	public Matrix PrevWorldMatrix;

	/// Number of bones.
	public uint16 BoneCount;

	/// LOD level.
	public uint8 LODLevel;
}

/// A batch of draws sharing the same material.
public struct DrawBatch
{
	/// Material for this batch.
	public MaterialInstance Material;

	/// Start index in the command list.
	public int32 CommandStart;

	/// Number of commands in this batch.
	public int32 CommandCount;

	/// Whether this batch contains skinned meshes.
	public bool IsSkinned;
}

/// A group of identical meshes that can be drawn with GPU instancing.
/// All instances share the same mesh and material.
public struct InstanceGroup
{
	/// GPU mesh handle (shared by all instances).
	public GPUMeshHandle GPUMesh;

	/// Material for this group.
	public MaterialInstance Material;

	/// Start index in the instance data buffer.
	public int32 InstanceStart;

	/// Number of instances in this group.
	public int32 InstanceCount;

	/// Start index in the command list (for accessing transforms).
	public int32 CommandStart;

	/// Whether this is a transparent group.
	public bool IsTransparent;

	/// LOD level for this group (all instances share the same LOD).
	public uint8 LODLevel;
}

/// Groups visible objects into batches for efficient rendering.
/// Uses dictionary-based grouping (O(n)) instead of comparison sort (O(n log n)).
public class DrawBatcher
{
	// Draw commands
	private List<DrawCommand> mDrawCommands = new .() ~ delete _;
	private List<SkinnedDrawCommand> mSkinnedCommands = new .() ~ delete _;

	// Reorder buffer for scatter-based grouping (reused across frames)
	private List<DrawCommand> mReorderBuffer = new .() ~ delete _;

	// Batches (non-instanced path)
	private List<DrawBatch> mOpaqueBatches = new .() ~ delete _;
	private List<DrawBatch> mTransparentBatches = new .() ~ delete _;
	private List<DrawBatch> mSkinnedBatches = new .() ~ delete _;

	// Instance groups (GPU instancing path)
	private List<InstanceGroup> mOpaqueInstanceGroups = new .() ~ delete _;
	private List<InstanceGroup> mTransparentInstanceGroups = new .() ~ delete _;

	// Statistics
	private BatchStats mStats;

	// Reference to the render world (valid only during Build)
	private RenderWorld mWorld;

	// Grouping key for dictionary-based auto-instancer
	private struct GroupKey : IHashable
	{
		public int MaterialPtr;
		public uint32 MeshIndex;
		public uint8 LODLevel;

		public int GetHashCode()
		{
			var hash = MaterialPtr;
			hash = hash * 397 ^ (int)MeshIndex;
			hash = hash * 397 ^ (int)LODLevel;
			return hash;
		}

		public static bool operator==(Self a, Self b) =>
			a.MaterialPtr == b.MaterialPtr && a.MeshIndex == b.MeshIndex && a.LODLevel == b.LODLevel;
	}

	// Per-group metadata for the auto-instancer
	private struct GroupInfo
	{
		public MaterialInstance Material;
		public GPUMeshHandle GPUMesh;
		public uint8 LODLevel;
		public bool IsTransparent;
		public int32 Count;
		public int32 StartOffset;
	}

	/// Gets all static mesh draw commands.
	public Span<DrawCommand> DrawCommands => mDrawCommands;

	/// Gets all skinned mesh draw commands.
	public Span<SkinnedDrawCommand> SkinnedCommands => mSkinnedCommands;

	/// Gets opaque draw batches.
	public Span<DrawBatch> OpaqueBatches => mOpaqueBatches;

	/// Gets transparent draw batches.
	public Span<DrawBatch> TransparentBatches => mTransparentBatches;

	/// Gets skinned mesh draw batches.
	public Span<DrawBatch> SkinnedBatches => mSkinnedBatches;

	/// Gets opaque instance groups (for GPU instancing).
	public Span<InstanceGroup> OpaqueInstanceGroups => mOpaqueInstanceGroups;

	/// Gets transparent instance groups (for GPU instancing).
	public Span<InstanceGroup> TransparentInstanceGroups => mTransparentInstanceGroups;

	/// Gets batching statistics.
	public BatchStats Stats => mStats;

	/// Builds batches from visibility results.
	public void Build(RenderWorld world, VisibilityResolver visibility)
	{
		Clear();

		// Store world reference for skinned material lookups
		mWorld = world;

		// Build static mesh commands
		BuildStaticMeshCommands(world, visibility);

		// Build skinned mesh commands
		BuildSkinnedMeshCommands(world, visibility);

		// Create batches and instance groups
		BuildBatches();

		// Update stats
		mStats.TotalDrawCalls = (int32)(mDrawCommands.Count + mSkinnedCommands.Count);
		mStats.OpaqueBatchCount = (int32)mOpaqueBatches.Count;
		mStats.TransparentBatchCount = (int32)mTransparentBatches.Count;
		mStats.SkinnedBatchCount = (int32)mSkinnedBatches.Count;

		// Clear world reference (not needed after build)
		mWorld = null;
	}

	/// Builds batches from visibility results, including only shadow-casting static meshes.
	public void BuildShadowCasters(RenderWorld world, VisibilityResolver visibility)
	{
		Clear();

		mWorld = world;

		// Build only shadow-casting static mesh commands
		for (let visible in visibility.VisibleMeshes)
		{
			if (let proxy = world.GetMesh(visible.Handle))
			{
				if (!proxy.CastsShadows)
					continue;

				mDrawCommands.Add(.()
				{
					MeshHandle = visible.Handle,
					GPUMesh = proxy.MeshHandle,
					Material = proxy.Materials[0],
					WorldMatrix = proxy.WorldMatrix,
					PrevWorldMatrix = proxy.PrevWorldMatrix,
	
					LODLevel = visible.LODLevel
				});
			}
		}

		// Build batches and instance groups
		BuildBatches();

		mStats.TotalDrawCalls = (int32)mDrawCommands.Count;
		mStats.OpaqueBatchCount = (int32)mOpaqueBatches.Count;
		mStats.TransparentBatchCount = (int32)mTransparentBatches.Count;

		mWorld = null;
	}

	/// Clears all batches and commands.
	public void Clear()
	{
		mDrawCommands.Clear();
		mSkinnedCommands.Clear();
		mOpaqueBatches.Clear();
		mTransparentBatches.Clear();
		mSkinnedBatches.Clear();
		mOpaqueInstanceGroups.Clear();
		mTransparentInstanceGroups.Clear();
		mStats = .();
	}

	private void BuildStaticMeshCommands(RenderWorld world, VisibilityResolver visibility)
	{
		for (let visible in visibility.VisibleMeshes)
		{
			if (let proxy = world.GetMesh(visible.Handle))
			{
				mDrawCommands.Add(.()
				{
					MeshHandle = visible.Handle,
					GPUMesh = proxy.MeshHandle,
					Material = proxy.Materials[0],
					WorldMatrix = proxy.WorldMatrix,
					PrevWorldMatrix = proxy.PrevWorldMatrix,
	
					LODLevel = visible.LODLevel
				});
			}
		}
	}

	private void BuildSkinnedMeshCommands(RenderWorld world, VisibilityResolver visibility)
	{
		for (let visible in visibility.VisibleSkinnedMeshes)
		{
			if (let proxy = world.GetSkinnedMesh(visible.Handle))
			{
				mSkinnedCommands.Add(.()
				{
					MeshHandle = visible.Handle,
					GPUMesh = proxy.MeshHandle,
					BoneBuffer = proxy.BoneBufferHandle,
					WorldMatrix = proxy.WorldMatrix,
					PrevWorldMatrix = proxy.PrevWorldMatrix,
	
					BoneCount = proxy.BoneCount,
					LODLevel = visible.LODLevel
				});
			}
		}
	}

	private void BuildBatches()
	{
		// Group static mesh commands by material+mesh+LOD (O(n) dictionary-based)
		BuildGroupedBatches();

		// Build skinned mesh batches (separate pipeline, no instancing)
		BuildSkinnedBatches();
	}

	/// Groups draw commands by (Material, Mesh, LOD) using a dictionary,
	/// reorders commands so each group is contiguous, then emits both
	/// DrawBatches (non-instanced fallback) and InstanceGroups (instancing path).
	/// O(n) total — replaces the previous O(n log n) comparison sort.
	private void BuildGroupedBatches()
	{
		if (mDrawCommands.IsEmpty)
			return;

		// Step 1: Group commands by (Material, Mesh, LOD)
		Dictionary<GroupKey, int32> keyToGroup = scope .();
		List<GroupInfo> groupInfos = scope .();

		for (int32 i = 0; i < mDrawCommands.Count; i++)
		{
			let cmd = mDrawCommands[i];
			let key = GroupKey()
			{
				MaterialPtr = (int)Internal.UnsafeCastToPtr(cmd.Material),
				MeshIndex = cmd.GPUMesh.Index,
				LODLevel = cmd.LODLevel
			};

			if (keyToGroup.TryGetValue(key, let groupIdx))
			{
				var info = groupInfos[groupIdx];
				info.Count++;
				groupInfos[groupIdx] = info;
			}
			else
			{
				keyToGroup[key] = (int32)groupInfos.Count;
				groupInfos.Add(.()
				{
					Material = cmd.Material,
					GPUMesh = cmd.GPUMesh,
					LODLevel = cmd.LODLevel,
					IsTransparent = IsMaterialTransparent(cmd.Material),
					Count = 1,
					StartOffset = 0
				});
			}
		}

		// Step 2: Compute prefix sums — opaque groups first, then transparent
		int32 offset = 0;
		for (int32 i = 0; i < groupInfos.Count; i++)
		{
			if (!groupInfos[i].IsTransparent)
			{
				var info = groupInfos[i];
				info.StartOffset = offset;
				offset += info.Count;
				groupInfos[i] = info;
			}
		}
		for (int32 i = 0; i < groupInfos.Count; i++)
		{
			if (groupInfos[i].IsTransparent)
			{
				var info = groupInfos[i];
				info.StartOffset = offset;
				offset += info.Count;
				groupInfos[i] = info;
			}
		}

		// Step 3: Scatter commands into contiguous groups
		mReorderBuffer.Clear();
		mReorderBuffer.Reserve(mDrawCommands.Count);
		for (int i = 0; i < mDrawCommands.Count; i++)
			mReorderBuffer.Add(.());

		List<int32> writePos = scope .();
		for (int32 i = 0; i < groupInfos.Count; i++)
			writePos.Add(groupInfos[i].StartOffset);

		for (int32 i = 0; i < mDrawCommands.Count; i++)
		{
			let cmd = mDrawCommands[i];
			let key = GroupKey()
			{
				MaterialPtr = (int)Internal.UnsafeCastToPtr(cmd.Material),
				MeshIndex = cmd.GPUMesh.Index,
				LODLevel = cmd.LODLevel
			};
			let groupIdx = keyToGroup[key];
			let pos = writePos[groupIdx];
			mReorderBuffer[pos] = cmd;
			writePos[groupIdx] = pos + 1;
		}

		// Copy reordered commands back
		Internal.MemCpy(mDrawCommands.Ptr, mReorderBuffer.Ptr, mDrawCommands.Count * strideof(DrawCommand));

		// Step 4: Emit batches and instance groups
		int32 opaqueInstanceStart = 0;
		int32 transparentInstanceStart = 0;

		for (int32 i = 0; i < groupInfos.Count; i++)
		{
			let info = groupInfos[i];

			// Create DrawBatch (for non-instanced fallback path)
			AddBatch(info.Material, info.StartOffset, info.Count, info.IsTransparent, false);

			// Create InstanceGroups (splitting at MaxInstancesPerDraw)
			int32 remaining = info.Count;
			int32 groupOffset = 0;

			while (remaining > 0)
			{
				int32 batchSize = Math.Min(remaining, RenderConfig.MaxInstancesPerDraw);
				int32 instanceStart = info.IsTransparent ? transparentInstanceStart : opaqueInstanceStart;

				let group = InstanceGroup()
				{
					GPUMesh = info.GPUMesh,
					Material = info.Material,
					InstanceStart = instanceStart,
					InstanceCount = batchSize,
					CommandStart = info.StartOffset + groupOffset,
					IsTransparent = info.IsTransparent,
					LODLevel = info.LODLevel
				};

				if (info.IsTransparent)
				{
					mTransparentInstanceGroups.Add(group);
					transparentInstanceStart += batchSize;
				}
				else
				{
					mOpaqueInstanceGroups.Add(group);
					opaqueInstanceStart += batchSize;
				}

				groupOffset += batchSize;
				remaining -= batchSize;
			}
		}

		// Offset transparent instance starts by total opaque count
		for (int32 i = 0; i < mTransparentInstanceGroups.Count; i++)
		{
			var group = mTransparentInstanceGroups[i];
			group.InstanceStart += opaqueInstanceStart;
			mTransparentInstanceGroups[i] = group;
		}

		// Update stats
		mStats.OpaqueInstanceGroupCount = (int32)mOpaqueInstanceGroups.Count;
		mStats.TransparentInstanceGroupCount = (int32)mTransparentInstanceGroups.Count;
		mStats.TotalInstanceCount = opaqueInstanceStart + transparentInstanceStart;

	}

	private void BuildSkinnedBatches()
	{
		if (mSkinnedCommands.IsEmpty)
			return;

		// Sort skinned commands by material (few items, comparison sort is fine)
		mSkinnedCommands.Sort(scope (a, b) =>
		{
			let matA = (int)Internal.UnsafeCastToPtr(GetSkinnedMaterial(a));
			let matB = (int)Internal.UnsafeCastToPtr(GetSkinnedMaterial(b));
			return matA <=> matB;
		});

		MaterialInstance currentMaterial = null;
		int32 batchStart = 0;

		for (int32 i = 0; i < mSkinnedCommands.Count; i++)
		{
			let cmd = mSkinnedCommands[i];
			let material = GetSkinnedMaterial(cmd);

			if (material != currentMaterial)
			{
				if (i > batchStart)
				{
					mSkinnedBatches.Add(.()
					{
						Material = currentMaterial,
						CommandStart = batchStart,
						CommandCount = i - batchStart,
						IsSkinned = true
					});
				}

				currentMaterial = material;
				batchStart = i;
			}
		}

		// Finish last batch
		if (mSkinnedCommands.Count > batchStart)
		{
			mSkinnedBatches.Add(.()
			{
				Material = currentMaterial,
				CommandStart = batchStart,
				CommandCount = (int32)mSkinnedCommands.Count - batchStart,
				IsSkinned = true
			});
		}
	}

	private void AddBatch(MaterialInstance material, int32 start, int32 count, bool isTransparent, bool isSkinned)
	{
		let batch = DrawBatch()
		{
			Material = material,
			CommandStart = start,
			CommandCount = count,
			IsSkinned = isSkinned
		};

		if (isTransparent)
			mTransparentBatches.Add(batch);
		else
			mOpaqueBatches.Add(batch);
	}

	private MaterialInstance GetSkinnedMaterial(SkinnedDrawCommand cmd)
	{
		if (mWorld == null || !cmd.MeshHandle.IsValid)
			return null;

		if (let proxy = mWorld.GetSkinnedMesh(cmd.MeshHandle))
			return proxy.Materials[0];

		return null;
	}

	private bool IsMaterialTransparent(MaterialInstance material)
	{
		if (material == null)
			return false;

		// Check material blend mode - anything not Opaque is considered transparent
		return material.BlendMode != .Opaque;
	}
}

/// Statistics from draw batching.
public struct BatchStats
{
	/// Total number of draw calls generated.
	public int32 TotalDrawCalls;

	/// Number of opaque batches.
	public int32 OpaqueBatchCount;

	/// Number of transparent batches.
	public int32 TransparentBatchCount;

	/// Number of skinned mesh batches.
	public int32 SkinnedBatchCount;

	/// Number of opaque instance groups (for GPU instancing).
	public int32 OpaqueInstanceGroupCount;

	/// Number of transparent instance groups (for GPU instancing).
	public int32 TransparentInstanceGroupCount;

	/// Total number of instances (sum of all instance counts).
	public int32 TotalInstanceCount;

	/// Average draws per batch.
	public float AverageDrawsPerBatch => (OpaqueBatchCount + TransparentBatchCount + SkinnedBatchCount) > 0
		? (float)TotalDrawCalls / (float)(OpaqueBatchCount + TransparentBatchCount + SkinnedBatchCount)
		: 0.0f;

	/// Draw call reduction ratio from instancing.
	/// Lower is better (e.g., 0.1 means 10x fewer draw calls).
	public float InstancingEfficiency
	{
		get
		{
			if (TotalInstanceCount == 0)
				return 1.0f;
			let instancedDrawCalls = OpaqueInstanceGroupCount + TransparentInstanceGroupCount;
			return (float)instancedDrawCalls / (float)TotalInstanceCount;
		}
	}
}

namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Materials;

/// A single draw command for a mesh.
public struct DrawCommand
{
	/// Handle to the mesh proxy.
	public MeshProxyHandle MeshHandle;

	/// GPU mesh handle for vertex/index data.
	public GPUMeshHandle GPUMesh;

	/// World transform matrix.
	public Matrix WorldMatrix;

	/// Previous frame world matrix (for motion vectors).
	public Matrix PrevWorldMatrix;

	/// Normal matrix (inverse transpose of world).
	public Matrix NormalMatrix;

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

	/// Normal matrix.
	public Matrix NormalMatrix;

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
}

/// Groups visible objects into batches for efficient rendering.
/// Minimizes state changes by grouping draws by material.
public class DrawBatcher
{
	// Draw commands
	private List<DrawCommand> mDrawCommands = new .() ~ delete _;
	private List<SkinnedDrawCommand> mSkinnedCommands = new .() ~ delete _;

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

		// Store world reference for material lookups
		mWorld = world;

		// Build static mesh commands
		BuildStaticMeshCommands(world, visibility);

		// Build skinned mesh commands
		BuildSkinnedMeshCommands(world, visibility);

		// Create batches grouped by material
		BuildBatches();

		// Update stats
		mStats.TotalDrawCalls = (int32)(mDrawCommands.Count + mSkinnedCommands.Count);
		mStats.OpaqueBatchCount = (int32)mOpaqueBatches.Count;
		mStats.TransparentBatchCount = (int32)mTransparentBatches.Count;
		mStats.SkinnedBatchCount = (int32)mSkinnedBatches.Count;

		// Clear world reference (not needed after build)
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
					WorldMatrix = proxy.WorldMatrix,
					PrevWorldMatrix = proxy.PrevWorldMatrix,
					NormalMatrix = proxy.NormalMatrix,
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
					NormalMatrix = proxy.NormalMatrix,
					BoneCount = proxy.BoneCount,
					LODLevel = visible.LODLevel
				});
			}
		}
	}

	private void BuildBatches()
	{
		// Sort static mesh commands by material and mesh for batching/instancing
		SortCommandsByMaterial();

		// Build static mesh batches (non-instanced path)
		BuildStaticBatches();

		// Build instance groups (GPU instancing path)
		BuildInstanceGroups();

		// Build skinned mesh batches (separate pipeline, no instancing)
		BuildSkinnedBatches();
	}

	private void SortCommandsByMaterial()
	{
		// Sort by material and mesh for optimal batching and instancing
		// Commands with same material AND mesh can be instanced together
		mDrawCommands.Sort(scope (a, b) =>
		{
			// First sort by material
			let matA = (int)Internal.UnsafeCastToPtr(GetMaterial(a));
			let matB = (int)Internal.UnsafeCastToPtr(GetMaterial(b));
			if (matA != matB)
				return matA <=> matB;

			// Then sort by GPU mesh (enables instancing of identical meshes)
			let meshA = a.GPUMesh.Index;
			let meshB = b.GPUMesh.Index;
			return meshA <=> meshB;
		});

		mSkinnedCommands.Sort(scope (a, b) =>
		{
			let matA = (int)Internal.UnsafeCastToPtr(GetSkinnedMaterial(a));
			let matB = (int)Internal.UnsafeCastToPtr(GetSkinnedMaterial(b));
			return matA <=> matB;
		});
	}

	private void BuildStaticBatches()
	{
		if (mDrawCommands.IsEmpty)
			return;

		MaterialInstance currentMaterial = null;
		int32 batchStart = 0;
		bool isCurrentTransparent = false;

		for (int32 i = 0; i < mDrawCommands.Count; i++)
		{
			let cmd = mDrawCommands[i];
			let material = GetMaterial(cmd);
			let isTransparent = IsMaterialTransparent(material);

			// Check if we need to start a new batch
			if (material != currentMaterial || isTransparent != isCurrentTransparent)
			{
				// Finish previous batch
				if (i > batchStart)
				{
					AddBatch(currentMaterial, batchStart, i - batchStart, isCurrentTransparent, false);
				}

				// Start new batch
				currentMaterial = material;
				batchStart = i;
				isCurrentTransparent = isTransparent;
			}
		}

		// Finish last batch
		if (mDrawCommands.Count > batchStart)
		{
			AddBatch(currentMaterial, batchStart, (int32)mDrawCommands.Count - batchStart, isCurrentTransparent, false);
		}
	}

	private void BuildSkinnedBatches()
	{
		if (mSkinnedCommands.IsEmpty)
			return;

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

	private void BuildInstanceGroups()
	{
		// Build instance groups from sorted draw commands
		// Commands are already sorted by material then by mesh
		// Consecutive commands with same mesh+material form an instance group

		if (mDrawCommands.IsEmpty)
			return;

		// Track separate instance starts for opaque and transparent
		// This matches how UploadInstanceData uploads: opaque first, then transparent
		int32 opaqueInstanceStart = 0;
		int32 transparentInstanceStart = 0;

		int32 groupStart = 0;
		GPUMeshHandle currentMesh = mDrawCommands[0].GPUMesh;
		MaterialInstance currentMaterial = GetMaterial(mDrawCommands[0]);
		bool isCurrentTransparent = IsMaterialTransparent(currentMaterial);

		for (int32 i = 1; i <= mDrawCommands.Count; i++)
		{
			bool endGroup = (i == mDrawCommands.Count);

			if (!endGroup)
			{
				let cmd = mDrawCommands[i];
				let material = GetMaterial(cmd);
				let isTransparent = IsMaterialTransparent(material);

				// Check if this command can be grouped with the previous one
				// Must have same mesh, same material, and same transparency mode
				endGroup = (cmd.GPUMesh.Index != currentMesh.Index) ||
				           (material != currentMaterial) ||
				           (isTransparent != isCurrentTransparent);
			}

			if (endGroup)
			{
				// Create instance group
				int32 groupCount = i - groupStart;

				// Limit group size to MaxInstancesPerDraw
				int32 remaining = groupCount;
				int32 groupOffset = 0;

				while (remaining > 0)
				{
					int32 batchSize = Math.Min(remaining, RenderConfig.MaxInstancesPerDraw);

					// Use the appropriate instance start based on transparency
					int32 instanceStart = isCurrentTransparent ? transparentInstanceStart : opaqueInstanceStart;

					let group = InstanceGroup()
					{
						GPUMesh = currentMesh,
						Material = currentMaterial,
						InstanceStart = instanceStart,
						InstanceCount = batchSize,
						CommandStart = groupStart + groupOffset,
						IsTransparent = isCurrentTransparent
					};

					if (isCurrentTransparent)
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

				// Start new group
				if (i < mDrawCommands.Count)
				{
					groupStart = i;
					currentMesh = mDrawCommands[i].GPUMesh;
					currentMaterial = GetMaterial(mDrawCommands[i]);
					isCurrentTransparent = IsMaterialTransparent(currentMaterial);
				}
			}
		}

		// Transparent instances are uploaded AFTER opaque instances in the buffer,
		// so offset all transparent InstanceStart values by the total opaque count
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

	private MaterialInstance GetMaterial(DrawCommand cmd)
	{
		if (mWorld == null || !cmd.MeshHandle.IsValid)
			return null;

		if (let proxy = mWorld.GetMesh(cmd.MeshHandle))
			return proxy.Material;

		return null;
	}

	private MaterialInstance GetSkinnedMaterial(SkinnedDrawCommand cmd)
	{
		if (mWorld == null || !cmd.MeshHandle.IsValid)
			return null;

		if (let proxy = mWorld.GetSkinnedMesh(cmd.MeshHandle))
			return proxy.Material;

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

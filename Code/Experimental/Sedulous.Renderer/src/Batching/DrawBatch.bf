namespace Sedulous.Renderer;

using System;

/// A batched draw call — may represent one or many instances.
[CRepr]
struct DrawBatch
{
	/// GPU mesh to draw.
	public GPUMeshHandle MeshHandle;
	/// Material instance.
	public MaterialInstanceHandle MaterialHandle;
	/// Submesh index within the mesh.
	public uint32 SubMeshIndex;
	/// Selected LOD level.
	public uint8 LODLevel;
	/// Number of instances (1 = non-instanced).
	public uint32 InstanceCount;
	/// Byte offset into the instance buffer (0 for single draws).
	public uint32 InstanceBufferOffset;
	/// Sort key from first element.
	public uint64 SortKey;
	/// Index into InstanceGroups — preserved across sorting.
	public int32 GroupIndex;
}

/// Key for grouping draws into batches.
/// Same material + mesh + LOD + submesh = one batch.
struct BatchKey : IHashable
{
	public MaterialInstanceHandle Material;
	public GPUMeshHandle Mesh;
	public uint32 SubMeshIndex;
	public uint8 LODLevel;

	public int GetHashCode()
	{
		var hash = (int)(Material.Index * 2654435761);
		hash ^= (int)(Mesh.Index * 2246822519);
		hash ^= (int)(SubMeshIndex * 3266489917);
		hash ^= (int)LODLevel * 668265263;
		return hash;
	}

	public static bool operator ==(Self lhs, Self rhs)
	{
		return lhs.Material == rhs.Material &&
			   lhs.Mesh == rhs.Mesh &&
			   lhs.SubMeshIndex == rhs.SubMeshIndex &&
			   lhs.LODLevel == rhs.LODLevel;
	}

	public static bool operator !=(Self lhs, Self rhs) => !(lhs == rhs);
}

/// Tracks instances within a batch during grouping.
struct InstanceGroup
{
	/// Batch key identifying what is being instanced.
	public BatchKey Key;
	/// Start index into the flat proxy handle list.
	public uint32 StartIndex;
	/// Number of instances.
	public uint32 Count;
	/// Sort key from first element.
	public uint64 SortKey;
}

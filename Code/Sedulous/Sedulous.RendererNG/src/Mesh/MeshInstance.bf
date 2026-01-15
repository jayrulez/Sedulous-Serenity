namespace Sedulous.RendererNG;

using System;
using Sedulous.Mathematics;

/// Per-instance data uploaded to GPU for instanced rendering.
/// Must match shader cbuffer layout.
[CRepr]
struct MeshInstanceData
{
	public Matrix WorldMatrix;
	public Matrix NormalMatrix; // Transpose of inverse for correct normal transformation
	public Vector4 CustomData;     // User-defined per-instance data (e.g., color tint)

	public const uint32 Size = 144; // 64 + 64 + 16

	public this()
	{
		WorldMatrix = .Identity;
		NormalMatrix = .Identity;
		CustomData = .(1, 1, 1, 1);
	}

	public this(Matrix world)
	{
		WorldMatrix = world;
		// Compute normal matrix (transpose of inverse)
		Matrix.Invert(world, var invWorld);
		NormalMatrix = Matrix.Transpose(invWorld);
		CustomData = .(1, 1, 1, 1);
	}

	public static Self FromTransform(Vector3 position, Quaternion rotation, Vector3 scale)
	{
		let world = Matrix.CreateScale(scale) *
					Matrix.CreateFromQuaternion(rotation) *
					Matrix.CreateTranslation(position);
		return Self(world);
	}
}

/// Per-instance bone data for skinned mesh rendering.
/// Contains offset into shared bone buffer and count.
[CRepr]
struct SkinnedInstanceData
{
	public uint32 BoneBufferOffset;  // Byte offset into bone matrix buffer
	public uint32 BoneCount;         // Number of bones for this instance
	public uint32 Padding0;
	public uint32 Padding1;

	public const uint32 Size = 16;

	public this()
	{
		BoneBufferOffset = 0;
		BoneCount = 0;
		Padding0 = 0;
		Padding1 = 0;
	}

	public this(uint32 offset, uint32 count)
	{
		BoneBufferOffset = offset;
		BoneCount = count;
		Padding0 = 0;
		Padding1 = 0;
	}
}

/// Combined instance data for skinned meshes.
/// Used when rendering skinned mesh instances.
[CRepr]
struct SkinnedMeshInstanceData
{
	public MeshInstanceData BaseData;
	public SkinnedInstanceData SkinData;

	public const uint32 Size = MeshInstanceData.Size + SkinnedInstanceData.Size; // 160

	public this()
	{
		BaseData = .();
		SkinData = .();
	}

	public this(MeshInstanceData baseData, uint32 boneOffset, uint32 boneCount)
	{
		BaseData = baseData;
		SkinData = .(boneOffset, boneCount);
	}
}

/// Reference to a mesh instance for rendering.
struct MeshInstanceRef
{
	public MeshHandle Mesh;
	public uint32 SubmeshIndex;
	public MaterialInstance Material; // Reference to material instance
	public MeshInstanceData InstanceData;
	public float SortKey; // For distance sorting (transparency)

	// Skinned mesh data (null for static meshes)
	public Matrix* BoneMatrices; // Pointer to caller-owned bone matrices
	public uint32 BoneCount;

	public this(MeshHandle mesh, MaterialInstance material, MeshInstanceData instanceData)
	{
		Mesh = mesh;
		SubmeshIndex = 0;
		Material = material;
		InstanceData = instanceData;
		SortKey = 0;
		BoneMatrices = null;
		BoneCount = 0;
	}

	/// Creates a skinned mesh instance reference.
	public this(MeshHandle mesh, MaterialInstance material, MeshInstanceData instanceData,
				Matrix* boneMatrices, uint32 boneCount)
	{
		Mesh = mesh;
		SubmeshIndex = 0;
		Material = material;
		InstanceData = instanceData;
		SortKey = 0;
		BoneMatrices = boneMatrices;
		BoneCount = boneCount;
	}

	public bool IsSkinned => BoneMatrices != null && BoneCount > 0;
}

/// A batch of mesh instances sharing the same mesh and material.
/// Used for instanced draw calls.
struct MeshDrawBatch
{
	public MeshHandle Mesh;
	public uint32 SubmeshIndex;
	public MaterialInstance Material;
	public uint32 InstanceOffset; // Offset into instance buffer
	public uint32 InstanceCount;
	public bool IsSkinned;

	// Bone buffer info for skinned batches
	public uint32 BoneBufferOffset;  // Byte offset into shared bone buffer
	public uint32 TotalBoneCount;    // Total bones for all instances in batch

	public this()
	{
		Mesh = .Invalid;
		SubmeshIndex = 0;
		Material = null;
		InstanceOffset = 0;
		InstanceCount = 0;
		IsSkinned = false;
		BoneBufferOffset = 0;
		TotalBoneCount = 0;
	}
}

/// Key for grouping instances into batches.
struct BatchKey : IHashable, IEquatable<BatchKey>
{
	public MeshHandle Mesh;
	public uint32 SubmeshIndex;
	public MaterialInstance Material;

	public this(MeshHandle mesh, uint32 submeshIndex, MaterialInstance material)
	{
		Mesh = mesh;
		SubmeshIndex = submeshIndex;
		Material = material;
	}

	public int GetHashCode()
	{
		int hash = Mesh.GetHashCode();
		hash = hash * 31 + (int)SubmeshIndex;
		// Use reference identity for hashing - classes use reference equality by default
		hash = hash * 31 + (Material != null ? Internal.UnsafeCastToPtr(Material).GetHashCode() : 0);
		return hash;
	}

	public bool Equals(BatchKey other)
	{
		return Mesh == other.Mesh &&
			   SubmeshIndex == other.SubmeshIndex &&
			   Material == other.Material;
	}
}

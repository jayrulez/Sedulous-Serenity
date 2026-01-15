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

/// Reference to a mesh instance for rendering.
struct MeshInstanceRef
{
	public MeshHandle Mesh;
	public uint32 SubmeshIndex;
	public MaterialInstance* Material; // Pointer to avoid ownership issues
	public MeshInstanceData InstanceData;
	public float SortKey; // For distance sorting (transparency)

	public this(MeshHandle mesh, MaterialInstance* material, MeshInstanceData instanceData)
	{
		Mesh = mesh;
		SubmeshIndex = 0;
		Material = material;
		InstanceData = instanceData;
		SortKey = 0;
	}
}

/// A batch of mesh instances sharing the same mesh and material.
/// Used for instanced draw calls.
struct MeshDrawBatch
{
	public MeshHandle Mesh;
	public uint32 SubmeshIndex;
	public MaterialInstance* Material;
	public uint32 InstanceOffset; // Offset into instance buffer
	public uint32 InstanceCount;
	public bool IsSkinned;

	public this()
	{
		Mesh = .Invalid;
		SubmeshIndex = 0;
		Material = null;
		InstanceOffset = 0;
		InstanceCount = 0;
		IsSkinned = false;
	}
}

/// Key for grouping instances into batches.
struct BatchKey : IHashable, IEquatable<BatchKey>
{
	public MeshHandle Mesh;
	public uint32 SubmeshIndex;
	public MaterialInstance* Material;

	public this(MeshHandle mesh, uint32 submeshIndex, MaterialInstance* material)
	{
		Mesh = mesh;
		SubmeshIndex = submeshIndex;
		Material = material;
	}

	public int GetHashCode()
	{
		int hash = Mesh.GetHashCode();
		hash = hash * 31 + (int)SubmeshIndex;
		hash = hash * 31 + (int)(void*)Material;
		return hash;
	}

	public bool Equals(BatchKey other)
	{
		return Mesh == other.Mesh &&
			   SubmeshIndex == other.SubmeshIndex &&
			   Material == other.Material;
	}
}

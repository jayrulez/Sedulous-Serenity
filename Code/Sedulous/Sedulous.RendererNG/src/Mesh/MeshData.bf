namespace Sedulous.RendererNG;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Materials;

/// Submesh definition within a mesh.
struct Submesh
{
	public uint32 IndexOffset;
	public uint32 IndexCount;
	public uint32 MaterialIndex;
	public BoundingBox Bounds;

	public this(uint32 indexOffset, uint32 indexCount, uint32 materialIndex = 0)
	{
		IndexOffset = indexOffset;
		IndexCount = indexCount;
		MaterialIndex = materialIndex;
		Bounds = .(.Zero, .Zero);
	}
}

/// CPU-side static mesh data.
/// Contains vertex and index data ready for GPU upload.
class StaticMesh
{
	/// Mesh name for debugging.
	public String Name = new .() ~ delete _;

	/// Vertex layout type.
	public VertexLayoutType VertexLayout = .PositionNormalUV;

	/// Raw vertex data.
	public uint8[] VertexData ~ delete _;

	/// Vertex count.
	public uint32 VertexCount;

	/// Index data (16-bit or 32-bit).
	public uint8[] IndexData ~ delete _;

	/// Index count.
	public uint32 IndexCount;

	/// Whether indices are 32-bit (vs 16-bit).
	public bool Use32BitIndices;

	/// Submeshes (for multi-material meshes).
	public List<Submesh> Submeshes = new .() ~ delete _;

	/// Overall bounding box.
	public BoundingBox Bounds;

	/// Gets vertex stride in bytes.
	public uint32 VertexStride => VertexLayouts.GetStride(VertexLayout);

	/// Gets total vertex data size in bytes.
	public uint32 VertexDataSize => VertexCount * VertexStride;

	/// Gets total index data size in bytes.
	public uint32 IndexDataSize => IndexCount * (Use32BitIndices ? 4 : 2);

	/// Creates an empty static mesh.
	public this() { }

	/// Creates a static mesh with allocated buffers.
	public this(StringView name, VertexLayoutType layout, uint32 vertexCount, uint32 indexCount, bool use32BitIndices = false)
	{
		Name.Set(name);
		VertexLayout = layout;
		VertexCount = vertexCount;
		IndexCount = indexCount;
		Use32BitIndices = use32BitIndices;

		let vertexSize = vertexCount * VertexLayouts.GetStride(layout);
		let indexSize = indexCount * (use32BitIndices ? 4 : 2);

		VertexData = new uint8[vertexSize];
		IndexData = new uint8[indexSize];
	}

	/// Gets vertex data as typed span.
	public Span<T> GetVertices<T>() where T : struct
	{
		if (VertexData == null) return default;
		return Span<T>((T*)VertexData.Ptr, (int)VertexCount);
	}

	/// Gets index data as 16-bit span.
	public Span<uint16> GetIndices16()
	{
		if (IndexData == null || Use32BitIndices) return default;
		return Span<uint16>((uint16*)IndexData.Ptr, (int)IndexCount);
	}

	/// Gets index data as 32-bit span.
	public Span<uint32> GetIndices32()
	{
		if (IndexData == null || !Use32BitIndices) return default;
		return Span<uint32>((uint32*)IndexData.Ptr, (int)IndexCount);
	}

	/// Adds a submesh.
	public void AddSubmesh(uint32 indexOffset, uint32 indexCount, uint32 materialIndex = 0)
	{
		Submeshes.Add(.(indexOffset, indexCount, materialIndex));
	}

	/// Computes bounds from vertex positions.
	public void ComputeBounds()
	{
		if (VertexData == null || VertexCount == 0)
		{
			Bounds = .(.Zero, .Zero);
			return;
		}

		let stride = VertexStride;
		Vector3 min = .(float.MaxValue);
		Vector3 max = .(float.MinValue);

		for (uint32 i = 0; i < VertexCount; i++)
		{
			let pos = *(Vector3*)(&VertexData[i * stride]);
			min = Vector3.Min(min, pos);
			max = Vector3.Max(max, pos);
		}

		Bounds = .(min, max);
	}
}

/// Bone influence for skinned vertices.
struct BoneInfluence
{
	public uint8[4] Indices;
	public float[4] Weights;

	public this()
	{
		Indices = default;
		Weights = .(1, 0, 0, 0);
	}

	public this(uint8 i0, float w0)
	{
		Indices = .(i0, 0, 0, 0);
		Weights = .(w0, 0, 0, 0);
	}

	public this(uint8 i0, float w0, uint8 i1, float w1)
	{
		Indices = .(i0, i1, 0, 0);
		Weights = .(w0, w1, 0, 0);
	}

	public this(uint8 i0, float w0, uint8 i1, float w1, uint8 i2, float w2, uint8 i3, float w3)
	{
		Indices = .(i0, i1, i2, i3);
		Weights = .(w0, w1, w2, w3);
	}

	/// Normalizes weights to sum to 1.
	public void Normalize() mut
	{
		float sum = Weights[0] + Weights[1] + Weights[2] + Weights[3];
		if (sum > 0)
		{
			float invSum = 1.0f / sum;
			Weights[0] *= invSum;
			Weights[1] *= invSum;
			Weights[2] *= invSum;
			Weights[3] *= invSum;
		}
	}
}

/// Bone definition for skeletal meshes.
class BoneInfo
{
	public String Name = new .() ~ delete _;
	public int32 ParentIndex = -1;
	public Matrix InverseBindPose = .Identity;
}

/// CPU-side skinned mesh data.
/// Extends static mesh with bone information.
class SkinnedMesh : StaticMesh
{
	/// Bone hierarchy.
	public List<BoneInfo> Bones = new .() ~ DeleteContainerAndItems!(_);

	/// Maximum bones per vertex (always 4).
	public const int MaxBonesPerVertex = 4;

	/// Maximum bones in skeleton.
	public const int MaxBones = 256;

	/// Creates an empty skinned mesh.
	public this()
	{
		VertexLayout = .Skinned;
	}

	/// Creates a skinned mesh with allocated buffers.
	public this(StringView name, uint32 vertexCount, uint32 indexCount, bool use32BitIndices = false)
		: base(name, .Skinned, vertexCount, indexCount, use32BitIndices)
	{
	}

	/// Adds a bone to the skeleton.
	public int AddBone(StringView name, int32 parentIndex, Matrix inverseBindPose)
	{
		let bone = new BoneInfo();
		bone.Name.Set(name);
		bone.ParentIndex = parentIndex;
		bone.InverseBindPose = inverseBindPose;
		let index = Bones.Count;
		Bones.Add(bone);
		return index;
	}

	/// Gets bone index by name (-1 if not found).
	public int GetBoneIndex(StringView name)
	{
		for (int i = 0; i < Bones.Count; i++)
		{
			if (Bones[i].Name == name)
				return i;
		}
		return -1;
	}
}

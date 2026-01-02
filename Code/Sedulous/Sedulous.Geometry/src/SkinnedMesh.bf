using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.Geometry;

/// Skinned vertex format for skeletal animation (72 bytes total)
[CRepr]
public struct SkinnedVertex
{
	public Vector3 Position;      // 12 bytes - Local space position
	public Vector3 Normal;        // 12 bytes - Surface normal
	public Vector2 TexCoord;      // 8 bytes  - UV coordinates
	public uint32 Color;          // 4 bytes  - Packed RGBA color
	public Vector3 Tangent;       // 12 bytes - Tangent vector
	public uint16[4] Joints;      // 8 bytes  - Bone indices (up to 4 bones)
	public Vector4 Weights;       // 16 bytes - Bone weights (should sum to 1.0)
	// Total: 72 bytes

	public this()
	{
		Position = .Zero;
		Normal = Vector3(0, 1, 0);
		TexCoord = .Zero;
		Color = 0xFFFFFFFF; // White
		Tangent = Vector3(1, 0, 0);
		Joints = .(0, 0, 0, 0);
		Weights = Vector4(1, 0, 0, 0); // Full weight on first bone
	}

	public this(Vector3 position, Vector3 normal, Vector2 texCoord, uint32 color, Vector3 tangent, uint16[4] joints, Vector4 weights)
	{
		Position = position;
		Normal = normal;
		TexCoord = texCoord;
		Color = color;
		Tangent = tangent;
		Joints = joints;
		Weights = weights;
	}
}

/// Mesh with skinning data for skeletal animation
public class SkinnedMesh
{
	private List<SkinnedVertex> mVertices ~ delete _;
	private IndexBuffer mIndices ~ delete _;
	private List<SubMesh> mSubMeshes ~ delete _;
	private BoundingBox mBounds;
	private int32 mIndexWritePos = 0;

	public List<SkinnedVertex> Vertices => mVertices;
	public IndexBuffer Indices => mIndices;
	public List<SubMesh> SubMeshes => mSubMeshes;
	public BoundingBox Bounds => mBounds;

	public int32 VertexCount => (int32)mVertices.Count;
	public int32 IndexCount => mIndices.IndexCount;
	public int32 VertexSize => sizeof(SkinnedVertex);

	public this()
	{
		mVertices = new List<SkinnedVertex>();
		mIndices = new IndexBuffer(.UInt32);
		mSubMeshes = new List<SubMesh>();
		mBounds = BoundingBox(.Zero, .Zero);
	}

	/// Get raw vertex data pointer for GPU upload
	public uint8* GetVertexData()
	{
		if (mVertices.Count == 0)
			return null;
		return (uint8*)mVertices.Ptr;
	}

	/// Get raw index data pointer for GPU upload
	public uint8* GetIndexData()
	{
		if (mIndices.IndexCount == 0)
			return null;
		return mIndices.GetRawData();
	}

	/// Add a vertex
	public void AddVertex(SkinnedVertex vertex)
	{
		mVertices.Add(vertex);
	}

	/// Set vertex at index
	public void SetVertex(int32 index, SkinnedVertex vertex)
	{
		mVertices[index] = vertex;
	}

	/// Get vertex at index
	public SkinnedVertex GetVertex(int32 index)
	{
		return mVertices[index];
	}

	/// Resize vertex buffer
	public void ResizeVertices(int32 count)
	{
		mVertices.Resize(count);
	}

	/// Reserve space for indices
	public void ReserveIndices(int32 count)
	{
		mIndices.Resize(count);
		mIndexWritePos = 0;
	}

	/// Add an index (must call ReserveIndices first)
	public void AddIndex(uint32 index)
	{
		if (mIndexWritePos < mIndices.IndexCount)
		{
			mIndices.SetIndex(mIndexWritePos, index);
			mIndexWritePos++;
		}
	}

	/// Add a triangle (3 indices) - must call ReserveIndices first
	public void AddTriangle(uint32 i0, uint32 i1, uint32 i2)
	{
		AddIndex(i0);
		AddIndex(i1);
		AddIndex(i2);
	}

	/// Set index at position
	public void SetIndex(int32 position, uint32 value)
	{
		mIndices.SetIndex(position, value);
	}

	/// Add a submesh
	public void AddSubMesh(SubMesh subMesh)
	{
		mSubMeshes.Add(subMesh);
	}

	/// Calculate bounding box from vertices
	public void CalculateBounds()
	{
		if (mVertices.Count == 0)
		{
			mBounds = BoundingBox(.Zero, .Zero);
			return;
		}

		var min = Vector3(float.MaxValue);
		var max = Vector3(float.MinValue);

		for (var vertex in mVertices)
		{
			min = Vector3.Min(min, vertex.Position);
			max = Vector3.Max(max, vertex.Position);
		}

		mBounds = BoundingBox(min, max);
	}

	/// Pack a color from Vector4 (0-1 range) to uint32
	public static uint32 PackColor(Vector4 color)
	{
		uint8 r = (uint8)(Math.Clamp(color.X, 0, 1) * 255);
		uint8 g = (uint8)(Math.Clamp(color.Y, 0, 1) * 255);
		uint8 b = (uint8)(Math.Clamp(color.Z, 0, 1) * 255);
		uint8 a = (uint8)(Math.Clamp(color.W, 0, 1) * 255);
		return (uint32)r | ((uint32)g << 8) | ((uint32)b << 16) | ((uint32)a << 24);
	}

	/// Pack a color from Color to uint32
	public static uint32 PackColor(Color color)
	{
		return PackColor(color.ToVector4());
	}
}

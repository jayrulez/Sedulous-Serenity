using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.Models;

/// Primitive topology
public enum PrimitiveTopology
{
	Triangles,
	TriangleStrip,
	Lines,
	LineStrip,
	Points
}

/// A mesh within a model containing vertex and index data
public class ModelMesh
{
	private String mName ~ delete _;
	private uint8[] mVertexData ~ delete _;
	private uint8[] mIndexData ~ delete _;
	private List<ModelMeshPart> mParts ~ delete _;
	private List<VertexElement> mVertexElements ~ delete _;

	private int32 mVertexCount;
	private int32 mVertexStride;
	private int32 mIndexCount;
	private bool mUse32BitIndices;
	private PrimitiveTopology mTopology = .Triangles;
	private BoundingBox mBounds;

	public StringView Name => mName;
	public int32 VertexCount => mVertexCount;
	public int32 VertexStride => mVertexStride;
	public int32 IndexCount => mIndexCount;
	public bool Use32BitIndices => mUse32BitIndices;
	public PrimitiveTopology Topology => mTopology;
	public BoundingBox Bounds => mBounds;
	public List<ModelMeshPart> Parts => mParts;
	public List<VertexElement> VertexElements => mVertexElements;

	public this()
	{
		mName = new String();
		mParts = new List<ModelMeshPart>();
		mVertexElements = new List<VertexElement>();
		mBounds = BoundingBox(.Zero, .Zero);
	}

	public void SetName(StringView name)
	{
		mName.Set(name);
	}

	public void SetTopology(PrimitiveTopology topology)
	{
		mTopology = topology;
	}

	/// Add a vertex element descriptor
	public void AddVertexElement(VertexElement element)
	{
		mVertexElements.Add(element);
	}

	/// Allocate vertex buffer
	public void AllocateVertices(int32 count, int32 stride)
	{
		mVertexCount = count;
		mVertexStride = stride;

		delete mVertexData;
		mVertexData = new uint8[count * stride];
	}

	/// Allocate index buffer
	public void AllocateIndices(int32 count, bool use32Bit)
	{
		mIndexCount = count;
		mUse32BitIndices = use32Bit;

		int32 indexSize = use32Bit ? 4 : 2;
		delete mIndexData;
		mIndexData = new uint8[count * indexSize];
	}

	/// Get raw vertex data pointer
	public uint8* GetVertexData()
	{
		if (mVertexData == null || mVertexData.Count == 0)
			return null;
		return &mVertexData[0];
	}

	/// Get raw index data pointer
	public uint8* GetIndexData()
	{
		if (mIndexData == null || mIndexData.Count == 0)
			return null;
		return &mIndexData[0];
	}

	/// Get vertex data size in bytes
	public int32 GetVertexDataSize() => mVertexCount * mVertexStride;

	/// Get index data size in bytes
	public int32 GetIndexDataSize() => mIndexCount * (mUse32BitIndices ? 4 : 2);

	/// Set vertex data from typed array
	public void SetVertexData<T>(T[] data) where T : struct
	{
		if (mVertexData == null || data.Count * sizeof(T) > mVertexData.Count)
			return;

		Internal.MemCpy(&mVertexData[0], &data[0], data.Count * sizeof(T));
	}

	/// Set index data from uint16 array
	public void SetIndexData(uint16[] indices)
	{
		if (mIndexData == null || !mUse32BitIndices)
		{
			if (mIndexData != null && indices.Count * 2 <= mIndexData.Count)
			{
				Internal.MemCpy(&mIndexData[0], &indices[0], indices.Count * 2);
			}
		}
	}

	/// Set index data from uint32 array
	public void SetIndexData(uint32[] indices)
	{
		if (mIndexData == null || mUse32BitIndices)
		{
			if (mIndexData != null && indices.Count * 4 <= mIndexData.Count)
			{
				Internal.MemCpy(&mIndexData[0], &indices[0], indices.Count * 4);
			}
		}
	}

	/// Add a mesh part
	public void AddPart(ModelMeshPart part)
	{
		mParts.Add(part);
	}

	/// Set bounds
	public void SetBounds(BoundingBox bounds)
	{
		mBounds = bounds;
	}

	/// Calculate bounds from position data
	public void CalculateBounds()
	{
		if (mVertexData == null || mVertexCount == 0)
		{
			mBounds = BoundingBox(.Zero, .Zero);
			return;
		}

		// Find position element
		int32 posOffset = -1;
		for (let element in mVertexElements)
		{
			if (element.Semantic == .Position)
			{
				posOffset = element.Offset;
				break;
			}
		}

		if (posOffset < 0)
		{
			mBounds = BoundingBox(.Zero, .Zero);
			return;
		}

		var min = Vector3(float.MaxValue);
		var max = Vector3(float.MinValue);

		for (int32 i = 0; i < mVertexCount; i++)
		{
			int32 offset = i * mVertexStride + posOffset;
			Vector3 pos = default;
			Internal.MemCpy(&pos, &mVertexData[offset], sizeof(Vector3));

			min = Vector3.Min(min, pos);
			max = Vector3.Max(max, pos);
		}

		mBounds = BoundingBox(min, max);
	}
}

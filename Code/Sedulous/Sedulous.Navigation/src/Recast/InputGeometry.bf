using System;
using Sedulous.Mathematics;

namespace Sedulous.Navigation.Recast;

/// Default implementation of IInputGeometryProvider that owns its data.
class InputGeometry : IInputGeometryProvider
{
	private float* mVertices;
	private int32* mTriangles;
	private uint8* mAreaFlags;
	private int32 mVertexCount;
	private int32 mTriangleCount;
	private BoundingBox mBounds;
	private bool mOwnsData;

	public int32 VertexCount => mVertexCount;
	public int32 TriangleCount => mTriangleCount;
	public float* Vertices => mVertices;
	public int32* Triangles => mTriangles;
	public BoundingBox Bounds => mBounds;
	public uint8* TriangleAreaFlags => mAreaFlags;

	/// Creates an InputGeometry from raw vertex and triangle data.
	/// Copies the data into internally owned buffers.
	public this(Span<float> vertices, Span<int32> triangles, Span<uint8> areaFlags = default)
	{
		mVertexCount = (int32)(vertices.Length / 3);
		mTriangleCount = (int32)(triangles.Length / 3);
		mOwnsData = true;

		mVertices = new float[vertices.Length]*;
		Internal.MemCpy(mVertices, vertices.Ptr, vertices.Length * sizeof(float));

		mTriangles = new int32[triangles.Length]*;
		Internal.MemCpy(mTriangles, triangles.Ptr, triangles.Length * sizeof(int32));

		if (areaFlags.Length > 0)
		{
			mAreaFlags = new uint8[areaFlags.Length]*;
			Internal.MemCpy(mAreaFlags, areaFlags.Ptr, areaFlags.Length * sizeof(uint8));
		}
		else
		{
			mAreaFlags = null;
		}

		CalculateBounds();
	}

	/// Creates an InputGeometry referencing external data (does not take ownership).
	public this(float* vertices, int32 vertexCount, int32* triangles, int32 triangleCount, uint8* areaFlags = null)
	{
		mVertices = vertices;
		mTriangles = triangles;
		mAreaFlags = areaFlags;
		mVertexCount = vertexCount;
		mTriangleCount = triangleCount;
		mOwnsData = false;
		CalculateBounds();
	}

	public ~this()
	{
		if (mOwnsData)
		{
			delete mVertices;
			delete mTriangles;
			if (mAreaFlags != null)
				delete mAreaFlags;
		}
	}

	private void CalculateBounds()
	{
		if (mVertexCount == 0)
		{
			mBounds = BoundingBox(Vector3.Zero, Vector3.Zero);
			return;
		}

		var min = Vector3(float.MaxValue, float.MaxValue, float.MaxValue);
		var max = Vector3(float.MinValue, float.MinValue, float.MinValue);

		for (int32 i = 0; i < mVertexCount; i++)
		{
			float x = mVertices[i * 3];
			float y = mVertices[i * 3 + 1];
			float z = mVertices[i * 3 + 2];

			if (x < min.X) min.X = x;
			if (y < min.Y) min.Y = y;
			if (z < min.Z) min.Z = z;
			if (x > max.X) max.X = x;
			if (y > max.Y) max.Y = y;
			if (z > max.Z) max.Z = z;
		}

		mBounds = BoundingBox(min, max);
	}
}

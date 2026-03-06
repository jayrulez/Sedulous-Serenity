namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;

/// Vertex format for curve decal strip geometry.
[CRepr]
public struct CurveDecalVertex
{
	/// World-space position.
	public Vector3 Position;

	/// Texture coordinate.
	public Vector2 TexCoord;

	/// World-space normal (up-facing for depth conformity).
	public Vector3 Normal;

	public const uint32 Stride = 32; // 12 + 8 + 12
}

/// Generates triangle strip mesh from curve decal control points.
/// All curve decal strips share a single dynamic vertex/index buffer per frame.
public class CurveDecalMeshBuilder
{
	// Per-decal mesh data
	public struct DecalMeshRange
	{
		/// Start vertex in the shared buffer.
		public int32 VertexStart;

		/// Vertex count.
		public int32 VertexCount;

		/// Start index in the shared buffer.
		public int32 IndexStart;

		/// Index count.
		public int32 IndexCount;
	}

	private List<CurveDecalVertex> mVertices = new .() ~ delete _;
	private List<uint16> mIndices = new .() ~ delete _;
	private List<DecalMeshRange> mRanges = new .() ~ delete _;

	/// Gets the combined vertex data.
	public Span<CurveDecalVertex> Vertices => mVertices;

	/// Gets the combined index data.
	public Span<uint16> Indices => mIndices;

	/// Gets per-decal mesh ranges.
	public Span<DecalMeshRange> Ranges => mRanges;

	/// Gets total vertex count.
	public int32 TotalVertexCount => (int32)mVertices.Count;

	/// Gets total index count.
	public int32 TotalIndexCount => (int32)mIndices.Count;

	/// Clears all generated mesh data.
	public void Clear()
	{
		mVertices.Clear();
		mIndices.Clear();
		mRanges.Clear();
	}

	/// Generates a triangle strip mesh from a curve decal's control points.
	/// Call once per dirty curve decal, then upload the combined buffers.
	public void BuildStrip(CurveDecalProxy* proxy)
	{
		if (proxy == null || proxy.PointCount < 2)
			return;

		let vertexStart = (int32)mVertices.Count;
		let indexStart = (int32)mIndices.Count;

		let pointCount = proxy.PointCount;
		let upVector = Vector3(0, 1, 0);

		for (int32 i = 0; i < pointCount; i++)
		{
			let point = proxy.ControlPoints[i];

			// Compute tangent direction
			Vector3 tangent;
			if (i == 0)
				tangent = Vector3.Normalize(proxy.ControlPoints[1].Position - point.Position);
			else if (i == pointCount - 1)
				tangent = Vector3.Normalize(point.Position - proxy.ControlPoints[i - 1].Position);
			else
				tangent = Vector3.Normalize(proxy.ControlPoints[i + 1].Position - proxy.ControlPoints[i - 1].Position);

			// Right vector perpendicular to tangent and world up
			var right = Vector3.Cross(tangent, upVector);
			let rightLen = right.Length();
			if (rightLen < 0.001f)
			{
				// Tangent is nearly vertical — use forward as fallback
				right = Vector3.Cross(tangent, Vector3(0, 0, 1));
			}
			right = Vector3.Normalize(right);

			let halfWidth = point.Width * 0.5f;

			// Left and right vertices
			let leftPos = point.Position - right * halfWidth;
			let rightPos = point.Position + right * halfWidth;

			// UV: U = 0 (left edge), 1 (right edge); V = along curve
			let v = point.UV_V * proxy.UVTilingV;

			mVertices.Add(.()
			{
				Position = leftPos,
				TexCoord = .(0.0f * proxy.UVTilingU, v),
				Normal = upVector
			});

			mVertices.Add(.()
			{
				Position = rightPos,
				TexCoord = .(1.0f * proxy.UVTilingU, v),
				Normal = upVector
			});
		}

		// Generate triangle strip indices
		let vertCount = pointCount * 2;
		for (int32 i = 0; i < pointCount - 1; i++)
		{
			let baseIdx = (uint16)(vertexStart + i * 2);
			// Two triangles per quad: (0, 1, 2) and (2, 1, 3)
			mIndices.Add(baseIdx);
			mIndices.Add(baseIdx + 1);
			mIndices.Add(baseIdx + 2);

			mIndices.Add(baseIdx + 2);
			mIndices.Add(baseIdx + 1);
			mIndices.Add(baseIdx + 3);
		}

		let indexCount = (int32)mIndices.Count - indexStart;

		mRanges.Add(.()
		{
			VertexStart = vertexStart,
			VertexCount = vertCount,
			IndexStart = indexStart,
			IndexCount = indexCount
		});
	}
}

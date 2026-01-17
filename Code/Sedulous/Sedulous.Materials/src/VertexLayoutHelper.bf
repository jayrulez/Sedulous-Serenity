namespace Sedulous.Materials;

using System;
using Sedulous.RHI;

/// Helper for converting VertexLayoutType to RHI vertex descriptors.
public static class VertexLayoutHelper
{
	/// Vertex attribute definitions for each layout type.

	/// PositionOnly: Position (float3)
	public static VertexAttribute[1] PositionOnlyAttributes = .(
		.(VertexFormat.Float3, 0, 0)   // Position
	);

	/// PositionUVColor: Position (float3) + UV (float2) + Color (float4)
	public static VertexAttribute[3] PositionUVColorAttributes = .(
		.(VertexFormat.Float3, 0, 0),   // Position
		.(VertexFormat.Float2, 12, 1),  // UV
		.(VertexFormat.Float4, 20, 2)   // Color
	);

	/// Mesh: Position (float3) + Normal (float3) + UV (float2) + Tangent (float4)
	public static VertexAttribute[4] MeshAttributes = .(
		.(VertexFormat.Float3, 0, 0),   // Position
		.(VertexFormat.Float3, 12, 1),  // Normal
		.(VertexFormat.Float2, 24, 2),  // UV
		.(VertexFormat.Float4, 32, 3)   // Tangent
	);

	/// Skinned: Mesh attributes + JointIndices (uint4) + JointWeights (float4)
	public static VertexAttribute[6] SkinnedAttributes = .(
		.(VertexFormat.Float3, 0, 0),   // Position
		.(VertexFormat.Float3, 12, 1),  // Normal
		.(VertexFormat.Float2, 24, 2),  // UV
		.(VertexFormat.Float4, 32, 3),  // Tangent
		.(VertexFormat.UInt4, 48, 4),   // Joint Indices
		.(VertexFormat.Float4, 64, 5)   // Joint Weights
	);

	/// Gets the vertex stride for a layout type.
	public static uint32 GetStride(VertexLayoutType layoutType)
	{
		switch (layoutType)
		{
		case .None: return 0;
		case .PositionOnly: return 12;       // float3
		case .PositionUVColor: return 36;    // float3 + float2 + float4
		case .Mesh: return 48;               // float3 + float3 + float2 + float4
		case .Skinned: return 80;            // Mesh + uint4 + float4
		case .Custom: return 0;              // Custom layouts define their own stride
		}
	}

	/// Gets the number of vertex attributes for a layout type.
	public static uint32 GetAttributeCount(VertexLayoutType layoutType)
	{
		switch (layoutType)
		{
		case .None: return 0;
		case .PositionOnly: return 1;
		case .PositionUVColor: return 3;
		case .Mesh: return 4;
		case .Skinned: return 6;
		case .Custom: return 0;
		}
	}

	/// Gets vertex attributes as a span for a layout type.
	public static Span<VertexAttribute> GetAttributes(VertexLayoutType layoutType)
	{
		switch (layoutType)
		{
		case .None: return default;
		case .PositionOnly: return PositionOnlyAttributes;
		case .PositionUVColor: return PositionUVColorAttributes;
		case .Mesh: return MeshAttributes;
		case .Skinned: return SkinnedAttributes;
		case .Custom: return default;
		}
	}

	/// Creates a VertexBufferLayout for a layout type.
	public static VertexBufferLayout CreateBufferLayout(VertexLayoutType layoutType)
	{
		let stride = GetStride(layoutType);
		let attrs = GetAttributes(layoutType);
		return .(stride, attrs);
	}

	/// Fills an output array with vertex attributes for the given layout type.
	/// Returns the number of attributes written.
	public static int FillAttributes(VertexLayoutType layoutType, Span<VertexAttribute> outAttributes)
	{
		let attrs = GetAttributes(layoutType);
		let count = Math.Min(attrs.Length, outAttributes.Length);

		for (int i = 0; i < count; i++)
			outAttributes[i] = attrs[i];

		return count;
	}

	/// Creates a vertex buffer layout array with a single layout.
	public static void CreateSingleBufferLayout(
		VertexLayoutType layoutType,
		out VertexBufferLayout[1] outLayouts)
	{
		outLayouts = .(CreateBufferLayout(layoutType));
	}
}

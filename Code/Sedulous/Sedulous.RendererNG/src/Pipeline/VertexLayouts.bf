namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Materials;

/// Standard vertex formats used by the renderer.
/// These match the VertexLayoutType enum in PipelineConfig.
static class VertexLayouts
{
	/// Position only vertex (12 bytes).
	/// Used for skybox and shadow depth passes.
	[CRepr]
	public struct VertexPosition
	{
		public Vector3 Position;

		public const uint32 Stride = 12;
		public const int AttributeCount = 1;

		public static void GetAttributes(Span<VertexAttribute> outAttribs)
		{
			outAttribs[0] = .(VertexFormat.Float3, 0, 0); // Position
		}
	}

	/// Sprite/Particle vertex (28 bytes).
	[CRepr]
	public struct VertexSprite
	{
		public Vector3 Position;
		public Vector2 TexCoord;
		public Color Color;

		public const uint32 Stride = 28;
		public const int AttributeCount = 3;

		public static void GetAttributes(Span<VertexAttribute> outAttribs)
		{
			outAttribs[0] = .(VertexFormat.Float3, 0, 0);   // Position
			outAttribs[1] = .(VertexFormat.Float2, 12, 1);  // TexCoord
			outAttribs[2] = .(VertexFormat.UByte4Normalized, 20, 2); // Color
		}
	}

	/// Standard mesh vertex format (48 bytes).
	/// Position + Normal + UV + Color + Tangent.
	[CRepr]
	public struct VertexMesh
	{
		public Vector3 Position;   // 12 bytes, offset 0
		public Vector3 Normal;     // 12 bytes, offset 12
		public Vector2 TexCoord;   // 8 bytes, offset 24
		public uint32 Color;       // 4 bytes, offset 32
		public Vector3 Tangent;    // 12 bytes, offset 36

		public const uint32 Stride = 48;
		public const int AttributeCount = 5;

		public static void GetAttributes(Span<VertexAttribute> outAttribs)
		{
			outAttribs[0] = .(VertexFormat.Float3, 0, 0);              // Position
			outAttribs[1] = .(VertexFormat.Float3, 12, 1);             // Normal
			outAttribs[2] = .(VertexFormat.Float2, 24, 2);             // TexCoord
			outAttribs[3] = .(VertexFormat.UByte4Normalized, 32, 3);   // Color
			outAttribs[4] = .(VertexFormat.Float3, 36, 4);             // Tangent
		}
	}

	/// Skinned mesh vertex format (72 bytes).
	/// Position + Normal + UV + Color + Tangent + Joints + Weights.
	[CRepr]
	public struct VertexSkinned
	{
		public Vector3 Position;   // 12 bytes, offset 0
		public Vector3 Normal;     // 12 bytes, offset 12
		public Vector2 TexCoord;   // 8 bytes, offset 24
		public uint32 Color;       // 4 bytes, offset 32
		public Vector3 Tangent;    // 12 bytes, offset 36
		public uint16[4] Joints;   // 8 bytes, offset 48
		public Vector4 Weights;    // 16 bytes, offset 56

		public const uint32 Stride = 72;
		public const int AttributeCount = 7;

		public static void GetAttributes(Span<VertexAttribute> outAttribs)
		{
			outAttribs[0] = .(VertexFormat.Float3, 0, 0);              // Position
			outAttribs[1] = .(VertexFormat.Float3, 12, 1);             // Normal
			outAttribs[2] = .(VertexFormat.Float2, 24, 2);             // TexCoord
			outAttribs[3] = .(VertexFormat.UByte4Normalized, 32, 3);   // Color
			outAttribs[4] = .(VertexFormat.Float3, 36, 4);             // Tangent
			outAttribs[5] = .(VertexFormat.UShort4, 48, 5);            // Joints (uint16x4)
			outAttribs[6] = .(VertexFormat.Float4, 56, 6);             // Weights
		}
	}

	/// Gets the stride for a vertex layout type.
	public static uint32 GetStride(VertexLayoutType layout)
	{
		switch (layout)
		{
		case .None: return 0;
		case .PositionOnly: return VertexPosition.Stride;
		case .PositionUVColor: return VertexSprite.Stride;
		case .MeshNoTangent: return 32; // Position + Normal + UV
		case .Mesh: return VertexMesh.Stride;
		case .SkinnedMesh: return VertexSkinned.Stride;
		case .Custom: return 0;
		}
	}

	/// Gets the attribute count for a vertex layout type.
	public static int GetAttributeCount(VertexLayoutType layout)
	{
		switch (layout)
		{
		case .None: return 0;
		case .PositionOnly: return VertexPosition.AttributeCount;
		case .PositionUVColor: return VertexSprite.AttributeCount;
		case .MeshNoTangent: return 3;
		case .Mesh: return VertexMesh.AttributeCount;
		case .SkinnedMesh: return VertexSkinned.AttributeCount;
		case .Custom: return 0;
		}
	}

	/// Fills vertex attributes for a layout type.
	/// Returns the number of attributes filled.
	public static int FillAttributes(VertexLayoutType layout, Span<VertexAttribute> outAttribs)
	{
		switch (layout)
		{
		case .None:
			return 0;
		case .PositionOnly:
			VertexPosition.GetAttributes(outAttribs);
			return VertexPosition.AttributeCount;
		case .PositionUVColor:
			VertexSprite.GetAttributes(outAttribs);
			return VertexSprite.AttributeCount;
		case .MeshNoTangent:
			// Position + Normal + UV only
			outAttribs[0] = .(VertexFormat.Float3, 0, 0);   // Position
			outAttribs[1] = .(VertexFormat.Float3, 12, 1);  // Normal
			outAttribs[2] = .(VertexFormat.Float2, 24, 2);  // TexCoord
			return 3;
		case .Mesh:
			VertexMesh.GetAttributes(outAttribs);
			return VertexMesh.AttributeCount;
		case .SkinnedMesh:
			VertexSkinned.GetAttributes(outAttribs);
			return VertexSkinned.AttributeCount;
		case .Custom:
			return 0;
		}
	}
}

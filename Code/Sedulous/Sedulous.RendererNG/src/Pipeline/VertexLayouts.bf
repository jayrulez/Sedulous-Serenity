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
	[CRepr]
	public struct VertexP
	{
		public Vector3 Position;

		public const uint32 Stride = 12;

		public static void GetAttributes(Span<VertexAttribute> outAttribs)
		{
			outAttribs[0] = .(VertexFormat.Float3, 0, 0); // Position
		}

		public const int AttributeCount = 1;
	}

	/// Position + Normal vertex (24 bytes).
	[CRepr]
	public struct VertexPN
	{
		public Vector3 Position;
		public Vector3 Normal;

		public const uint32 Stride = 24;

		public static void GetAttributes(Span<VertexAttribute> outAttribs)
		{
			outAttribs[0] = .(VertexFormat.Float3, 0, 0);  // Position
			outAttribs[1] = .(VertexFormat.Float3, 12, 1); // Normal
		}

		public const int AttributeCount = 2;
	}

	/// Position + Normal + UV vertex (32 bytes).
	[CRepr]
	public struct VertexPNU
	{
		public Vector3 Position;
		public Vector3 Normal;
		public Vector2 TexCoord;

		public const uint32 Stride = 32;

		public static void GetAttributes(Span<VertexAttribute> outAttribs)
		{
			outAttribs[0] = .(VertexFormat.Float3, 0, 0);  // Position
			outAttribs[1] = .(VertexFormat.Float3, 12, 1); // Normal
			outAttribs[2] = .(VertexFormat.Float2, 24, 2); // TexCoord
		}

		public const int AttributeCount = 3;
	}

	/// Position + Normal + UV + Tangent vertex (48 bytes).
	[CRepr]
	public struct VertexPNUT
	{
		public Vector3 Position;
		public Vector3 Normal;
		public Vector2 TexCoord;
		public Vector4 Tangent; // w = handedness

		public const uint32 Stride = 48;

		public static void GetAttributes(Span<VertexAttribute> outAttribs)
		{
			outAttribs[0] = .(VertexFormat.Float3, 0, 0);  // Position
			outAttribs[1] = .(VertexFormat.Float3, 12, 1); // Normal
			outAttribs[2] = .(VertexFormat.Float2, 24, 2); // TexCoord
			outAttribs[3] = .(VertexFormat.Float4, 32, 3); // Tangent
		}

		public const int AttributeCount = 4;
	}

	/// Skinned mesh vertex (72 bytes).
	[CRepr]
	public struct VertexSkinned
	{
		public Vector3 Position;
		public Vector3 Normal;
		public Vector2 TexCoord;
		public Vector4 Tangent;
		public uint8[4] BoneIndices;
		public float[4] BoneWeights;

		public const uint32 Stride = 72;

		public static void GetAttributes(Span<VertexAttribute> outAttribs)
		{
			outAttribs[0] = .(VertexFormat.Float3, 0, 0);  // Position
			outAttribs[1] = .(VertexFormat.Float3, 12, 1); // Normal
			outAttribs[2] = .(VertexFormat.Float2, 24, 2); // TexCoord
			outAttribs[3] = .(VertexFormat.Float4, 32, 3); // Tangent
			outAttribs[4] = .(VertexFormat.UByte4, 48, 4); // BoneIndices
			outAttribs[5] = .(VertexFormat.Float4, 52, 5); // BoneWeights
		}

		public const int AttributeCount = 6;
	}

	/// Sprite/Particle vertex (28 bytes).
	[CRepr]
	public struct VertexPUC
	{
		public Vector3 Position;
		public Vector2 TexCoord;
		public Color Color;

		public const uint32 Stride = 28;

		public static void GetAttributes(Span<VertexAttribute> outAttribs)
		{
			outAttribs[0] = .(VertexFormat.Float3, 0, 0);   // Position
			outAttribs[1] = .(VertexFormat.Float2, 12, 1);  // TexCoord
			outAttribs[2] = .(VertexFormat.UByte4Normalized, 20, 2); // Color
		}

		public const int AttributeCount = 3;
	}

	/// Gets the stride for a vertex layout type.
	public static uint32 GetStride(VertexLayoutType layout)
	{
		switch (layout)
		{
		case .None: return 0;
		case .PositionOnly: return VertexP.Stride;
		case .PositionNormal: return VertexPN.Stride;
		case .PositionNormalUV: return VertexPNU.Stride;
		case .PositionNormalUVTangent: return VertexPNUT.Stride;
		case .Skinned: return VertexSkinned.Stride;
		case .PositionUVColor: return VertexPUC.Stride;
		case .Custom: return 0;
		}
	}

	/// Gets the attribute count for a vertex layout type.
	public static int GetAttributeCount(VertexLayoutType layout)
	{
		switch (layout)
		{
		case .None: return 0;
		case .PositionOnly: return VertexP.AttributeCount;
		case .PositionNormal: return VertexPN.AttributeCount;
		case .PositionNormalUV: return VertexPNU.AttributeCount;
		case .PositionNormalUVTangent: return VertexPNUT.AttributeCount;
		case .Skinned: return VertexSkinned.AttributeCount;
		case .PositionUVColor: return VertexPUC.AttributeCount;
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
			VertexP.GetAttributes(outAttribs);
			return VertexP.AttributeCount;
		case .PositionNormal:
			VertexPN.GetAttributes(outAttribs);
			return VertexPN.AttributeCount;
		case .PositionNormalUV:
			VertexPNU.GetAttributes(outAttribs);
			return VertexPNU.AttributeCount;
		case .PositionNormalUVTangent:
			VertexPNUT.GetAttributes(outAttribs);
			return VertexPNUT.AttributeCount;
		case .Skinned:
			VertexSkinned.GetAttributes(outAttribs);
			return VertexSkinned.AttributeCount;
		case .PositionUVColor:
			VertexPUC.GetAttributes(outAttribs);
			return VertexPUC.AttributeCount;
		case .Custom:
			return 0;
		}
	}
}

namespace SampleFramework;

using System;
using Sedulous.RHI;

// NOTE: Do NOT create GetLayout() helper methods that return VertexBufferLayout.
// The VertexBufferLayout contains a Span<VertexAttribute> that would point to
// a stack-allocated array that goes out of scope when the method returns.
// Instead, declare vertex attributes inline in the same scope as pipeline creation.
//
// Example usage:
//   VertexAttribute[2] vertexAttributes = .(
//       .(VertexFormat.Float2, 0, 0),   // Position
//       .(VertexFormat.Float3, 8, 1)    // Color
//   );
//   VertexBufferLayout[1] vertexBuffers = .(
//       .((uint64)sizeof(VertexPositionColor), vertexAttributes)
//   );

/// Position-only vertex (2D).
/// Attributes: Position (Float2) at location 0, offset 0
[CRepr]
struct VertexPosition2D
{
	public float[2] Position;

	public this(float x, float y)
	{
		Position = .(x, y);
	}
}

/// Position + Color vertex (2D position, RGB color).
/// Attributes:
///   Position (Float2) at location 0, offset 0
///   Color (Float3) at location 1, offset 8
[CRepr]
struct VertexPositionColor
{
	public float[2] Position;
	public float[3] Color;

	public this(float x, float y, float r, float g, float b)
	{
		Position = .(x, y);
		Color = .(r, g, b);
	}
}

/// Position + TexCoord vertex (2D).
/// Attributes:
///   Position (Float2) at location 0, offset 0
///   TexCoord (Float2) at location 1, offset 8
[CRepr]
struct VertexPositionTexture
{
	public float[2] Position;
	public float[2] TexCoord;

	public this(float x, float y, float u, float v)
	{
		Position = .(x, y);
		TexCoord = .(u, v);
	}
}

/// Position + Color + TexCoord vertex (2D).
/// Attributes:
///   Position (Float2) at location 0, offset 0
///   Color (Float3) at location 1, offset 8
///   TexCoord (Float2) at location 2, offset 20
[CRepr]
struct VertexPositionColorTexture
{
	public float[2] Position;
	public float[3] Color;
	public float[2] TexCoord;

	public this(float x, float y, float r, float g, float b, float u, float v)
	{
		Position = .(x, y);
		Color = .(r, g, b);
		TexCoord = .(u, v);
	}
}

/// 3D Position + Normal + TexCoord vertex.
/// Attributes:
///   Position (Float3) at location 0, offset 0
///   Normal (Float3) at location 1, offset 12
///   TexCoord (Float2) at location 2, offset 24
[CRepr]
struct VertexPositionNormalTexture
{
	public float[3] Position;
	public float[3] Normal;
	public float[2] TexCoord;

	public this(float px, float py, float pz, float nx, float ny, float nz, float u, float v)
	{
		Position = .(px, py, pz);
		Normal = .(nx, ny, nz);
		TexCoord = .(u, v);
	}
}

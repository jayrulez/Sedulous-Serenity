namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;

/// Per-sprite instance data uploaded to GPU vertex buffer.
[CRepr]
public struct SpriteInstance
{
	/// World-space position.
	public Vector3 Position;

	/// Billboard size (width, height).
	public Vector2 Size;

	/// UV rect (minU, minV, maxU, maxV) for atlas sub-regions.
	public Vector4 UVRect;

	/// Packed RGBA color.
	public Color Color;

	/// Size in bytes.
	public static int SizeInBytes => 40;
}

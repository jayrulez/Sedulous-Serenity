namespace Sedulous.Framework.Renderer;

using Sedulous.Mathematics;
using Sedulous.RHI;
using System;

/// A single sprite instance for batched rendering.
[CRepr]
struct SpriteInstance
{
	/// World position of sprite center.
	public Vector3 Position;
	/// Width and height in world units.
	public Vector2 Size;
	/// UV rectangle (minU, minV, maxU, maxV).
	public Vector4 UVRect;
	/// Tint color (RGBA).
	public Color Color;

	public this()
	{
		Position = .Zero;
		Size = .(1, 1);
		UVRect = .(0, 0, 1, 1);
		Color = .White;
	}

	public this(Vector3 position, Vector2 size, Color color = .White)
	{
		Position = position;
		Size = size;
		UVRect = .(0, 0, 1, 1);
		Color = color;
	}

	public this(Vector3 position, Vector2 size, Vector4 uvRect, Color color)
	{
		Position = position;
		Size = size;
		UVRect = uvRect;
		Color = color;
	}
}

namespace Sedulous.Renderer;

using Sedulous.Mathematics;
using Sedulous.RHI;
using System;

/// GPU-uploadable particle vertex data.
[CRepr]
struct ParticleVertex
{
	public Vector3 Position;
	public Vector2 Size;
	public Color Color;
	public float Rotation;

	public this(Particle p)
	{
		Position = p.Position;
		Size = p.Size;
		Color = p.Color;
		Rotation = p.Rotation;
	}
}

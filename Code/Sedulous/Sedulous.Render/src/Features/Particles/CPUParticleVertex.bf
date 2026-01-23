namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;

/// Vertex data uploaded to GPU for CPU-simulated particles.
/// Used as instance data (one per particle, step rate = per instance).
[CRepr]
public struct CPUParticleVertex
{
	/// World-space position of the particle center.
	public Vector3 Position;

	/// Billboard size (width, height).
	public Vector2 Size;

	/// Packed RGBA color.
	public Color Color;

	/// Rotation angle in radians.
	public float Rotation;

	/// Texture coordinate offset (atlas sub-region).
	public Vector2 TexCoordOffset;

	/// Texture coordinate scale (atlas sub-region).
	public Vector2 TexCoordScale;

	/// Screen-space velocity for stretched billboards.
	public Vector2 Velocity2D;

	/// Size in bytes.
	public static int SizeInBytes => 52;
}

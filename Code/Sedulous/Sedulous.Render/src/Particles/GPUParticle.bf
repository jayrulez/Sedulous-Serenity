namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;

/// GPU particle data.
[CRepr]
public struct GPUParticle
{
	public Vector3 Position;
	public float Age;

	public Vector3 Velocity;
	public float Lifetime;

	public Vector4 Color;

	public Vector2 ParticleSize;
	public float Rotation;
	public float RotationSpeed;

	/// Size in bytes.
	public static int SizeInBytes => 64;
}

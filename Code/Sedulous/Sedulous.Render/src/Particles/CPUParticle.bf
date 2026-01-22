namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;

/// CPU-simulated particle data.
[CRepr]
public struct CPUParticle
{
	/// World-space position.
	public Vector3 Position;

	/// Current age in seconds.
	public float Age;

	/// Current velocity.
	public Vector3 Velocity;

	/// Total lifetime in seconds.
	public float Lifetime;

	/// Current size.
	public Vector2 Size;

	/// Current color (packed RGBA).
	public Color Color;

	/// Current rotation in radians.
	public float Rotation;

	/// Rotation speed in radians/sec.
	public float RotationSpeed;

	/// Initial velocity (saved for speed curve evaluation).
	public Vector3 StartVelocity;

	/// Size in bytes.
	public static int SizeInBytes => 64;
}

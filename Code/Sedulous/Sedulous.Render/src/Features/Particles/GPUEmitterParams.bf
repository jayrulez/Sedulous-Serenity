namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;

/// Particle emitter GPU data.
[CRepr]
public struct GPUEmitterParams
{
	public Vector3 Position;
	public float SpawnRate;

	public Vector3 Direction;
	public float SpawnRadius;

	public Vector3 Velocity;
	public float VelocityRandomness;

	public Vector4 ColorStart;
	public Vector4 ColorEnd;

	public Vector2 SizeStart;
	public Vector2 SizeEnd;

	public float LifetimeMin;
	public float LifetimeMax;
	public float Gravity;
	public float Drag;

	public uint32 MaxParticles;
	public uint32 AliveCount; // Current alive particles (update shader reads this)
	public float DeltaTime;
	public float TotalTime;
	public uint32 SpawnCount; // Particles to spawn this frame (spawn shader reads this)
	public uint32 _Padding;

	/// Size in bytes.
	public static int SizeInBytes => 144;
}

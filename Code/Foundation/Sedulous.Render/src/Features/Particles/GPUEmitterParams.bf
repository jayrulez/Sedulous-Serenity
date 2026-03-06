namespace Sedulous.Render;

using System;
using Sedulous.Core.Mathematics;

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

	// Emission shape parameters
	public uint32 ShapeType;          // EmissionShapeType as uint (0=Point,1=Sphere,2=Hemisphere,3=Cone,4=Box,5=Circle,6=Edge)
	public float ShapeSizeX;          // Shape size X (radius for spheres, half-extent for box)
	public float ShapeSizeY;          // Shape size Y
	public float ShapeSizeZ;          // Shape size Z

	public float ShapeConeAngle;      // Cone angle in radians
	public float ShapeArc;            // Arc angle (0 = full 2*PI)
	public uint32 ShapeEmitFromSurface; // 1 = surface emission, 0 = volume emission
	public uint32 _ShapePadding;      // Pad to 16-byte alignment

	/// Size in bytes.
	public static int SizeInBytes => 176;
}

namespace Sedulous.RendererNG;

using System;
using Sedulous.Mathematics;

/// Type of force field.
enum ForceFieldType : uint8
{
	/// Directional wind force.
	Wind,
	/// Radial point force (attraction/repulsion).
	Point,
	/// Vortex/rotation force.
	Vortex,
	/// Turbulence/noise force.
	Turbulence,
	/// Drag/resistance force.
	Drag
}

/// Proxy for a particle force field.
/// Affects particles within its influence volume.
struct ForceFieldProxy
{
	/// World position of the force field center.
	public Vector3 Position;

	/// Force direction (for directional forces).
	public Vector3 Direction;

	/// Force strength.
	public float Strength;

	/// Radius of influence.
	public float Radius;

	/// Falloff exponent (1 = linear, 2 = quadratic).
	public float Falloff;

	/// Noise frequency (for turbulence).
	public float NoiseFrequency;

	/// Noise amplitude (for turbulence).
	public float NoiseAmplitude;

	/// Vortex axis (for vortex forces).
	public Vector3 VortexAxis;

	/// Type of force field.
	public ForceFieldType Type;

	/// Force field flags.
	public ForceFieldFlags Flags;

	/// Layer mask for which emitters are affected.
	public uint32 LayerMask;

	/// Returns true if this force field is active.
	public bool IsActive => (Flags & .Active) != 0;

	/// Calculates the falloff multiplier at a given distance.
	public float GetFalloff(float distance)
	{
		if (distance >= Radius)
			return 0;

		let normalized = distance / Radius;
		return Math.Pow(1.0f - normalized, Falloff);
	}

	/// Creates a default wind force field.
	public static Self DefaultWind => .()
	{
		Position = .Zero,
		Direction = .(1, 0, 0),
		Strength = 5.0f,
		Radius = 100.0f,
		Falloff = 1.0f,
		NoiseFrequency = 0,
		NoiseAmplitude = 0,
		VortexAxis = .(0, 1, 0),
		Type = .Wind,
		Flags = .Active,
		LayerMask = 0xFFFFFFFF
	};

	/// Creates a default point force field.
	public static Self DefaultPoint => .()
	{
		Position = .Zero,
		Direction = .Zero,
		Strength = 10.0f,
		Radius = 10.0f,
		Falloff = 2.0f,
		NoiseFrequency = 0,
		NoiseAmplitude = 0,
		VortexAxis = .(0, 1, 0),
		Type = .Point,
		Flags = .Active,
		LayerMask = 0xFFFFFFFF
	};

	/// Creates a default vortex force field.
	public static Self DefaultVortex => .()
	{
		Position = .Zero,
		Direction = .Zero,
		Strength = 5.0f,
		Radius = 10.0f,
		Falloff = 1.0f,
		NoiseFrequency = 0,
		NoiseAmplitude = 0,
		VortexAxis = .(0, 1, 0),
		Type = .Vortex,
		Flags = .Active,
		LayerMask = 0xFFFFFFFF
	};

	/// Creates a default turbulence force field.
	public static Self DefaultTurbulence => .()
	{
		Position = .Zero,
		Direction = .Zero,
		Strength = 2.0f,
		Radius = 20.0f,
		Falloff = 1.0f,
		NoiseFrequency = 1.0f,
		NoiseAmplitude = 1.0f,
		VortexAxis = .(0, 1, 0),
		Type = .Turbulence,
		Flags = .Active,
		LayerMask = 0xFFFFFFFF
	};
}

/// Flags for force field behavior.
[AllowDuplicates]
enum ForceFieldFlags : uint32
{
	None = 0,

	/// Force field is active.
	Active = 1 << 0,

	/// Force is relative to particle velocity (drag-like).
	VelocityRelative = 1 << 1,

	/// Invert force direction (repel instead of attract).
	Invert = 1 << 2,

	/// Default flags.
	Default = Active
}

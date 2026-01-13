namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Type of force field.
enum ForceFieldType
{
	/// Constant directional force (like wind).
	Directional,
	/// Point attraction/repulsion.
	Point,
	/// Rotational force around an axis.
	Vortex,
	/// Noise-based turbulence field.
	Turbulence
}

/// A scene-level force field that affects particles.
struct ForceField
{
	/// Unique identifier.
	public uint32 Id;

	/// Type of force.
	public ForceFieldType Type;

	/// Position in world space (for Point, Vortex, Turbulence).
	public Vector3 Position;

	/// Direction (for Directional, axis for Vortex).
	public Vector3 Direction;

	/// Force strength (can be negative for repulsion).
	public float Strength;

	/// Radius of effect (0 = infinite for Directional).
	public float Radius;

	/// Falloff exponent (0=constant, 1=linear, 2=quadratic).
	public float Falloff;

	/// Whether this force field is active.
	public bool Enabled;

	/// Layer mask for selective particle interaction.
	public uint32 LayerMask;

	// Turbulence-specific settings
	/// Noise frequency for turbulence.
	public float Frequency;
	/// Number of noise octaves.
	public int32 Octaves;

	// Vortex-specific settings
	/// Inward pull strength for vortex.
	public float InwardForce;

	/// Invalid/empty force field.
	public static Self Invalid => .() { Id = uint32.MaxValue, Enabled = false };

	/// Check if this is a valid force field.
	public bool IsValid => Id != uint32.MaxValue;

	/// Creates a directional (wind) force field.
	public static Self Directional(Vector3 direction, float strength)
	{
		return .()
		{
			Id = 0,
			Type = .Directional,
			Position = .Zero,
			Direction = Vector3.Normalize(direction),
			Strength = strength,
			Radius = 0,  // Infinite
			Falloff = 0,
			Enabled = true,
			LayerMask = 0xFFFFFFFF
		};
	}

	/// Creates a point attractor/repulsor force field.
	public static Self Point(Vector3 position, float strength, float radius, float falloff = 2.0f)
	{
		return .()
		{
			Id = 0,
			Type = .Point,
			Position = position,
			Direction = .Zero,
			Strength = strength,
			Radius = radius,
			Falloff = falloff,
			Enabled = true,
			LayerMask = 0xFFFFFFFF
		};
	}

	/// Creates a vortex force field.
	public static Self Vortex(Vector3 position, Vector3 axis, float strength, float radius, float inwardForce = 0)
	{
		return .()
		{
			Id = 0,
			Type = .Vortex,
			Position = position,
			Direction = Vector3.Normalize(axis),
			Strength = strength,
			Radius = radius,
			Falloff = 1.0f,
			Enabled = true,
			LayerMask = 0xFFFFFFFF,
			InwardForce = inwardForce
		};
	}

	/// Creates a turbulence force field.
	public static Self Turbulence(Vector3 position, float strength, float radius, float frequency = 1.0f, int32 octaves = 2)
	{
		return .()
		{
			Id = 0,
			Type = .Turbulence,
			Position = position,
			Direction = .Zero,
			Strength = strength,
			Radius = radius,
			Falloff = 1.0f,
			Enabled = true,
			LayerMask = 0xFFFFFFFF,
			Frequency = frequency,
			Octaves = octaves
		};
	}

	/// Calculates the force at a given position.
	public Vector3 CalculateForce(Vector3 particlePos, float time)
	{
		if (!Enabled)
			return .Zero;

		switch (Type)
		{
		case .Directional:
			return Direction * Strength;

		case .Point:
			Vector3 toCenter = Position - particlePos;
			float distance = toCenter.Length();

			if (distance < 0.001f || (Radius > 0 && distance > Radius))
				return .Zero;

			float falloffMult = CalculateFalloff(distance);
			return (toCenter / distance) * Strength * falloffMult;

		case .Vortex:
			Vector3 toParticle = particlePos - Position;
			Vector3 onAxis = Direction * Vector3.Dot(toParticle, Direction);
			Vector3 radial = toParticle - onAxis;
			float dist = radial.Length();

			if (dist < 0.001f || (Radius > 0 && dist > Radius))
				return .Zero;

			float falloff = CalculateFalloff(dist);
			Vector3 tangent = Vector3.Normalize(Vector3.Cross(Direction, radial));
			Vector3 force = tangent * Strength * falloff;

			// Add inward pull if specified
			if (InwardForce != 0 && dist > 0.01f)
			{
				force += (-radial / dist) * InwardForce * falloff;
			}

			return force;

		case .Turbulence:
			Vector3 toPos = particlePos - Position;
			float distance2 = toPos.Length();

			if (Radius > 0 && distance2 > Radius)
				return .Zero;

			float falloff2 = CalculateFalloff(distance2);

			// Sample noise for each axis
			float px = particlePos.X * Frequency;
			float py = particlePos.Y * Frequency;
			float pz = particlePos.Z * Frequency + time * 0.5f;

			Vector3 noiseForce = .Zero;
			float amplitude = Strength;
			float freq = 1.0f;

			for (int32 i = 0; i < Octaves; i++)
			{
				noiseForce.X += SimplexNoise.Noise3D(px * freq, py * freq, pz * freq) * amplitude;
				noiseForce.Y += SimplexNoise.Noise3D(px * freq + 100, py * freq + 100, pz * freq) * amplitude;
				noiseForce.Z += SimplexNoise.Noise3D(px * freq + 200, py * freq + 200, pz * freq) * amplitude;

				freq *= 2.0f;
				amplitude *= 0.5f;
			}

			return noiseForce * falloff2;
		}
	}

	private float CalculateFalloff(float distance)
	{
		if (Radius <= 0 || Falloff == 0)
			return 1.0f;

		float normalizedDist = distance / Radius;
		return Math.Pow(1.0f - Math.Clamp(normalizedDist, 0, 1), Falloff);
	}
}

/// Handle to a force field in the world.
struct ForceFieldHandle : IEquatable<ForceFieldHandle>, IHashable
{
	public uint32 Index;
	public uint32 Generation;

	public static readonly Self Invalid = .((uint32)-1, 0);

	public this(uint32 index, uint32 generation)
	{
		Index = index;
		Generation = generation;
	}

	public bool IsValid => Index != (uint32)-1;

	public bool Equals(ForceFieldHandle other) => Index == other.Index && Generation == other.Generation;
	public int GetHashCode() => (int)(Index ^ (Generation << 16));
}

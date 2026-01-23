namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;

/// Force modules that can be applied to particles during simulation.
/// All fields default to 0 (inactive). Set non-zero values to enable.
[CRepr]
public struct ParticleForceModules
{
	// --- Turbulence (Perlin noise-based displacement) ---

	/// Turbulence force strength.
	public float TurbulenceStrength;

	/// Turbulence spatial frequency (higher = more detail).
	public float TurbulenceFrequency;

	/// Turbulence scroll speed (how fast the noise field moves).
	public float TurbulenceSpeed;

	// --- Vortex (rotational force around Y-axis) ---

	/// Vortex rotational strength (radians/sec at unit distance).
	public float VortexStrength;

	/// Vortex center offset from emitter.
	public Vector3 VortexCenter;

	/// Vortex axis (default Y-up).
	public Vector3 VortexAxis;

	// --- Attractor (pulls particles toward a point) ---

	/// Attractor force strength (negative = repel).
	public float AttractorStrength;

	/// Attractor position in world space.
	public Vector3 AttractorPosition;

	/// Attractor radius (force falls off outside this).
	public float AttractorRadius;

	// --- Wind (constant directional force) ---

	/// Wind direction and strength (vector magnitude = force).
	public Vector3 WindForce;

	/// Wind turbulence (randomized variation applied each frame).
	public float WindTurbulence;

	// --- Radial force (pushes away from or toward emitter origin) ---

	/// Radial force strength (positive = outward, negative = inward).
	public float RadialForce;

	/// Whether any force module is active.
	public bool HasActiveModules =>
		TurbulenceStrength != 0 ||
		VortexStrength != 0 ||
		AttractorStrength != 0 ||
		WindForce.X != 0 || WindForce.Y != 0 || WindForce.Z != 0 ||
		RadialForce != 0;

	/// Applies all active force modules to a particle.
	public void Apply(ref CPUParticle particle, float deltaTime, float totalTime, Vector3 emitterPos, Random rng)
	{
		// Turbulence (simplified 3D noise approximation)
		if (TurbulenceStrength != 0)
		{
			let scrollOffset = totalTime * TurbulenceSpeed;
			let noiseInput = particle.Position * TurbulenceFrequency + Vector3(scrollOffset, scrollOffset * 0.7f, scrollOffset * 1.3f);

			// Simple pseudo-noise using sin combinations (not true Perlin, but fast)
			let noiseX = Math.Sin(noiseInput.X * 1.27f + noiseInput.Y * 2.43f) *
						 Math.Cos(noiseInput.Z * 0.79f + noiseInput.X * 1.83f);
			let noiseY = Math.Sin(noiseInput.Y * 1.57f + noiseInput.Z * 2.17f) *
						 Math.Cos(noiseInput.X * 0.93f + noiseInput.Y * 1.61f);
			let noiseZ = Math.Sin(noiseInput.Z * 1.37f + noiseInput.X * 2.63f) *
						 Math.Cos(noiseInput.Y * 0.87f + noiseInput.Z * 1.47f);

			particle.Velocity = particle.Velocity + Vector3(noiseX, noiseY, noiseZ) * TurbulenceStrength * deltaTime;
		}

		// Vortex (rotational force)
		if (VortexStrength != 0)
		{
			let axis = (VortexAxis.X == 0 && VortexAxis.Y == 0 && VortexAxis.Z == 0)
				? Vector3(0, 1, 0)
				: Vector3.Normalize(VortexAxis);

			let toParticle = particle.Position - VortexCenter;
			// Project onto plane perpendicular to axis
			let projDist = Vector3.Dot(toParticle, axis);
			let inPlane = toParticle - axis * projDist;
			let dist = inPlane.Length();

			if (dist > 0.001f)
			{
				// Tangential direction (perpendicular to radial in the plane)
				let radial = inPlane / dist;
				let tangent = Vector3.Cross(axis, radial);
				let force = tangent * VortexStrength / Math.Max(dist, 0.1f);
				particle.Velocity = particle.Velocity + force * deltaTime;
			}
		}

		// Attractor
		if (AttractorStrength != 0)
		{
			let toAttractor = AttractorPosition - particle.Position;
			let dist = toAttractor.Length();

			if (dist > 0.001f)
			{
				var strength = AttractorStrength;
				// Fall off outside radius
				if (AttractorRadius > 0 && dist > AttractorRadius)
					strength *= AttractorRadius / dist;

				let dir = toAttractor / dist;
				particle.Velocity = particle.Velocity + dir * strength * deltaTime;
			}
		}

		// Wind
		if (WindForce.X != 0 || WindForce.Y != 0 || WindForce.Z != 0)
		{
			var force = WindForce;
			if (WindTurbulence > 0)
			{
				force = force + Vector3(
					(float)(rng.NextDouble() * 2.0 - 1.0) * WindTurbulence,
					(float)(rng.NextDouble() * 2.0 - 1.0) * WindTurbulence,
					(float)(rng.NextDouble() * 2.0 - 1.0) * WindTurbulence
				);
			}
			particle.Velocity = particle.Velocity + force * deltaTime;
		}

		// Radial force
		if (RadialForce != 0)
		{
			let fromEmitter = particle.Position - emitterPos;
			let dist = fromEmitter.Length();
			if (dist > 0.001f)
			{
				let dir = fromEmitter / dist;
				particle.Velocity = particle.Velocity + dir * RadialForce * deltaTime;
			}
		}
	}
}

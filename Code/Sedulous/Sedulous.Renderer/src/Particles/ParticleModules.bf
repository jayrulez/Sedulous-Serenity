namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Interface for particle behavior modules.
/// Modules are composable behaviors that can be added to a particle system.
interface IParticleModule
{
	/// Called when a particle is spawned.
	void OnParticleSpawn(ref Particle particle, ParticleEmitterConfig config, Random random);

	/// Called each frame to update a particle.
	void OnParticleUpdate(ref Particle particle, float deltaTime, ParticleEmitterConfig config, float time);
}

/// Turbulence module that applies noise-based displacement to particles.
/// Creates organic, swirling motion for smoke, fire, and magical effects.
class TurbulenceModule : IParticleModule
{
	/// Strength of the turbulence force.
	public float Strength = 1.0f;

	/// Frequency of the noise (higher = more detail, smaller swirls).
	public float Frequency = 1.0f;

	/// Speed at which the noise field evolves over time.
	public float ScrollSpeed = 0.5f;

	/// Number of noise octaves (more = more detail, but slower).
	public int32 Octaves = 2;

	/// How noise strength changes per octave.
	public float Persistence = 0.5f;

	/// Per-particle random offset to prevent all particles moving the same.
	public bool UseParticleRandomOffset = true;

	public this(float strength = 1.0f, float frequency = 1.0f)
	{
		Strength = strength;
		Frequency = frequency;
	}

	public void OnParticleSpawn(ref Particle particle, ParticleEmitterConfig config, Random random)
	{
		// Nothing needed on spawn
	}

	public void OnParticleUpdate(ref Particle particle, float deltaTime, ParticleEmitterConfig config, float time)
	{
		// Sample 3D noise at particle position to get force direction
		float scrollTime = time * ScrollSpeed;

		// Use particle's random seed for offset if enabled
		float offsetX = 0, offsetY = 0, offsetZ = 0;
		if (UseParticleRandomOffset)
		{
			// Convert seed to offset
			offsetX = (particle.RandomSeed & 0xFF) / 255.0f * 100.0f;
			offsetY = ((particle.RandomSeed >> 8) & 0xFF) / 255.0f * 100.0f;
			offsetZ = ((particle.RandomSeed >> 16) & 0xFF) / 255.0f * 100.0f;
		}

		float px = (particle.Position.X + offsetX) * Frequency;
		float py = (particle.Position.Y + offsetY) * Frequency;
		float pz = (particle.Position.Z + offsetZ) * Frequency + scrollTime;

		// Sample noise for each force component (offset positions for different values)
		Vector3 force = .Zero;
		float amplitude = Strength;
		float freq = 1.0f;

		for (int32 i = 0; i < Octaves; i++)
		{
			force.X += SimplexNoise.Noise3D(px * freq, py * freq, pz * freq) * amplitude;
			force.Y += SimplexNoise.Noise3D(px * freq + 100, py * freq + 100, pz * freq) * amplitude;
			force.Z += SimplexNoise.Noise3D(px * freq + 200, py * freq + 200, pz * freq) * amplitude;

			freq *= 2.0f;
			amplitude *= Persistence;
		}

		// Apply force to velocity
		particle.Velocity += force * deltaTime;
	}
}

/// Vortex module that creates swirling motion around an axis.
class VortexModule : IParticleModule
{
	/// Axis of the vortex (normalized).
	public Vector3 Axis = .(0, 1, 0);

	/// Center point of the vortex in local space.
	public Vector3 Center = .Zero;

	/// Rotational strength (radians per second at unit distance).
	public float Strength = 2.0f;

	/// How strength falls off with distance (0 = constant, 1 = linear, 2 = quadratic).
	public float Falloff = 1.0f;

	/// Maximum radius of effect.
	public float Radius = 10.0f;

	/// Also pull particles toward the center.
	public float InwardForce = 0.0f;

	public this(float strength = 2.0f, Vector3 axis = default)
	{
		Strength = strength;
		Axis = axis == default ? .(0, 1, 0) : Vector3.Normalize(axis);
	}

	public void OnParticleSpawn(ref Particle particle, ParticleEmitterConfig config, Random random)
	{
	}

	public void OnParticleUpdate(ref Particle particle, float deltaTime, ParticleEmitterConfig config, float time)
	{
		// Vector from center to particle
		Vector3 toParticle = particle.Position - Center;

		// Project onto plane perpendicular to axis
		Vector3 onAxis = Axis * Vector3.Dot(toParticle, Axis);
		Vector3 radial = toParticle - onAxis;
		float distance = radial.Length();

		if (distance < 0.001f || distance > Radius)
			return;

		// Calculate falloff
		float falloffMult = 1.0f;
		if (Falloff > 0)
		{
			float normalizedDist = distance / Radius;
			falloffMult = Math.Pow(1.0f - normalizedDist, Falloff);
		}

		// Tangent direction (perpendicular to both axis and radial)
		Vector3 tangent = Vector3.Normalize(Vector3.Cross(Axis, radial));

		// Apply rotational force
		float rotForce = Strength * falloffMult;
		particle.Velocity += tangent * rotForce * deltaTime;

		// Apply inward force if set
		if (InwardForce != 0 && distance > 0.01f)
		{
			Vector3 inward = -Vector3.Normalize(radial);
			particle.Velocity += inward * InwardForce * falloffMult * deltaTime;
		}
	}
}

/// Attractor module that pulls particles toward a point.
class AttractorModule : IParticleModule
{
	/// Position of the attractor in local space.
	public Vector3 Position = .Zero;

	/// Strength of attraction (negative for repulsion).
	public float Strength = 5.0f;

	/// Radius of effect (0 = infinite).
	public float Radius = 0.0f;

	/// Falloff exponent (1 = linear, 2 = inverse square law).
	public float Falloff = 2.0f;

	/// Kill particles that get too close.
	public float KillRadius = 0.0f;

	public this(Vector3 position, float strength = 5.0f)
	{
		Position = position;
		Strength = strength;
	}

	public void OnParticleSpawn(ref Particle particle, ParticleEmitterConfig config, Random random)
	{
	}

	public void OnParticleUpdate(ref Particle particle, float deltaTime, ParticleEmitterConfig config, float time)
	{
		Vector3 toAttractor = Position - particle.Position;
		float distance = toAttractor.Length();

		if (distance < 0.001f)
			return;

		// Check kill radius
		if (KillRadius > 0 && distance < KillRadius)
		{
			particle.Life = 0;
			return;
		}

		// Check radius of effect
		if (Radius > 0 && distance > Radius)
			return;

		// Calculate force with falloff
		float forceMagnitude = Strength;
		if (Falloff > 0 && distance > 0.1f)
		{
			forceMagnitude /= Math.Pow(distance, Falloff);
		}

		Vector3 direction = toAttractor / distance;
		particle.Velocity += direction * forceMagnitude * deltaTime;
	}
}

/// Wind module that applies a directional force.
class WindModule : IParticleModule
{
	/// Wind direction and strength (magnitude = force).
	public Vector3 Wind = .(1, 0, 0);

	/// Add random variation to wind direction.
	public float Turbulence = 0.0f;

	/// How much particle size affects wind force (larger = more affected).
	public float SizeInfluence = 0.0f;

	public this(Vector3 wind)
	{
		Wind = wind;
	}

	public void OnParticleSpawn(ref Particle particle, ParticleEmitterConfig config, Random random)
	{
	}

	public void OnParticleUpdate(ref Particle particle, float deltaTime, ParticleEmitterConfig config, float time)
	{
		Vector3 windForce = Wind;

		// Add turbulence
		if (Turbulence > 0)
		{
			float tx = SimplexNoise.Noise3D(particle.Position.X * 0.1f, particle.Position.Y * 0.1f, time);
			float ty = SimplexNoise.Noise3D(particle.Position.X * 0.1f + 50, particle.Position.Y * 0.1f, time);
			float tz = SimplexNoise.Noise3D(particle.Position.X * 0.1f + 100, particle.Position.Y * 0.1f, time);
			windForce += Vector3(tx, ty, tz) * Turbulence;
		}

		// Size influence
		float sizeMult = 1.0f;
		if (SizeInfluence > 0)
		{
			float avgSize = (particle.Size.X + particle.Size.Y) * 0.5f;
			sizeMult = 1.0f + avgSize * SizeInfluence;
		}

		particle.Velocity += windForce * sizeMult * deltaTime;
	}
}

/// Simple 3D simplex noise implementation for particle effects.
static class SimplexNoise
{
	// Permutation table
	private static uint8[512] sPerm;
	private static bool sInitialized = false;

	private static void Initialize()
	{
		if (sInitialized) return;

		// Standard permutation table
		uint8[256] p = .(
			151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,
			8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,
			35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,
			134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,
			55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,
			18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,
			250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,
			189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,
			172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,
			228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,
			107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
			138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
		);

		for (int i = 0; i < 256; i++)
		{
			sPerm[i] = p[i];
			sPerm[256 + i] = p[i];
		}

		sInitialized = true;
	}

	// Skewing factors for 3D
	private const float F3 = 1.0f / 3.0f;
	private const float G3 = 1.0f / 6.0f;

	// Gradient vectors for 3D
	private static readonly int32[12][3] sGrad3 = .(
		.(1,1,0), .(-1,1,0), .(1,-1,0), .(-1,-1,0),
		.(1,0,1), .(-1,0,1), .(1,0,-1), .(-1,0,-1),
		.(0,1,1), .(0,-1,1), .(0,1,-1), .(0,-1,-1)
	);

	private static float Dot(int32[3] g, float x, float y, float z)
	{
		return g[0] * x + g[1] * y + g[2] * z;
	}

	/// 3D simplex noise. Returns value in range [-1, 1].
	public static float Noise3D(float x, float y, float z)
	{
		Initialize();

		// Skew input space
		float s = (x + y + z) * F3;
		int32 i = FastFloor(x + s);
		int32 j = FastFloor(y + s);
		int32 k = FastFloor(z + s);

		float t = (i + j + k) * G3;
		float X0 = i - t;
		float Y0 = j - t;
		float Z0 = k - t;
		float x0 = x - X0;
		float y0 = y - Y0;
		float z0 = z - Z0;

		// Determine simplex
		int32 i1, j1, k1, i2, j2, k2;
		if (x0 >= y0)
		{
			if (y0 >= z0) { i1=1; j1=0; k1=0; i2=1; j2=1; k2=0; }
			else if (x0 >= z0) { i1=1; j1=0; k1=0; i2=1; j2=0; k2=1; }
			else { i1=0; j1=0; k1=1; i2=1; j2=0; k2=1; }
		}
		else
		{
			if (y0 < z0) { i1=0; j1=0; k1=1; i2=0; j2=1; k2=1; }
			else if (x0 < z0) { i1=0; j1=1; k1=0; i2=0; j2=1; k2=1; }
			else { i1=0; j1=1; k1=0; i2=1; j2=1; k2=0; }
		}

		float x1 = x0 - i1 + G3;
		float y1 = y0 - j1 + G3;
		float z1 = z0 - k1 + G3;
		float x2 = x0 - i2 + 2.0f * G3;
		float y2 = y0 - j2 + 2.0f * G3;
		float z2 = z0 - k2 + 2.0f * G3;
		float x3 = x0 - 1.0f + 3.0f * G3;
		float y3 = y0 - 1.0f + 3.0f * G3;
		float z3 = z0 - 1.0f + 3.0f * G3;

		int32 ii = i & 255;
		int32 jj = j & 255;
		int32 kk = k & 255;

		// Calculate contributions
		float n0 = 0, n1 = 0, n2 = 0, n3 = 0;

		float t0 = 0.6f - x0*x0 - y0*y0 - z0*z0;
		if (t0 >= 0)
		{
			int32 gi0 = sPerm[ii + sPerm[jj + sPerm[kk]]] % 12;
			t0 *= t0;
			n0 = t0 * t0 * Dot(sGrad3[gi0], x0, y0, z0);
		}

		float t1 = 0.6f - x1*x1 - y1*y1 - z1*z1;
		if (t1 >= 0)
		{
			int32 gi1 = sPerm[ii + i1 + sPerm[jj + j1 + sPerm[kk + k1]]] % 12;
			t1 *= t1;
			n1 = t1 * t1 * Dot(sGrad3[gi1], x1, y1, z1);
		}

		float t2 = 0.6f - x2*x2 - y2*y2 - z2*z2;
		if (t2 >= 0)
		{
			int32 gi2 = sPerm[ii + i2 + sPerm[jj + j2 + sPerm[kk + k2]]] % 12;
			t2 *= t2;
			n2 = t2 * t2 * Dot(sGrad3[gi2], x2, y2, z2);
		}

		float t3 = 0.6f - x3*x3 - y3*y3 - z3*z3;
		if (t3 >= 0)
		{
			int32 gi3 = sPerm[ii + 1 + sPerm[jj + 1 + sPerm[kk + 1]]] % 12;
			t3 *= t3;
			n3 = t3 * t3 * Dot(sGrad3[gi3], x3, y3, z3);
		}

		return 32.0f * (n0 + n1 + n2 + n3);
	}

	private static int32 FastFloor(float x)
	{
		int32 xi = (int32)x;
		return x < xi ? xi - 1 : xi;
	}
}

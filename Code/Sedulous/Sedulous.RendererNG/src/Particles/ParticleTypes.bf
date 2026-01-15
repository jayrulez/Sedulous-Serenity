namespace Sedulous.RendererNG;

using System;
using Sedulous.Mathematics;

/// A range of float values for randomization.
struct RangeFloat
{
	public float Min;
	public float Max;

	public this(float min, float max) { Min = min; Max = max; }
	public this(float value) { Min = value; Max = value; }

	public float Evaluate(Random random)
	{
		if (Min == Max) return Min;
		return Min + (float)random.NextDouble() * (Max - Min);
	}

	public float Lerp(float t) => Min + t * (Max - Min);
	public static Self Constant(float value) => .(value, value);
}

/// A range of Color values for randomization.
struct RangeColor
{
	public Color Min;
	public Color Max;

	public this(Color min, Color max) { Min = min; Max = max; }
	public this(Color value) { Min = value; Max = value; }

	public Color Evaluate(Random random)
	{
		float t = (float)random.NextDouble();
		return Min.Interpolate(Max, t);
	}

	public Color Lerp(float t) => Min.Interpolate(Max, t);
}

// ParticleBlendMode is defined in Proxies/ParticleEmitterProxy.bf

/// Particle render mode.
enum ParticleRenderMode
{
	Billboard,           // Always face camera
	StretchedBillboard,  // Stretch along velocity
	HorizontalBillboard, // Face up (Y-axis)
	VerticalBillboard    // Stay vertical
}

/// Emission shape type.
enum EmissionShapeType
{
	Point,
	Sphere,
	Hemisphere,
	Cone,
	Box,
	Circle
}

/// Emission shape configuration.
struct EmissionShape
{
	public EmissionShapeType Type;
	public Vector3 Size;
	public float ConeAngle;
	public bool EmitFromSurface;
	public bool RandomizeDirection;
	public float Arc;

	public static Self Point => .() { Type = .Point, Size = .Zero, Arc = 360 };

	public static Self Sphere(float radius, bool surface = false) => .()
	{
		Type = .Sphere,
		Size = .(radius, radius, radius),
		EmitFromSurface = surface,
		Arc = 360
	};

	public static Self Cone(float angle, float radius = 0) => .()
	{
		Type = .Cone,
		ConeAngle = angle,
		Size = .(radius, 0, 0),
		Arc = 360
	};

	public static Self Box(Vector3 halfExtents) => .()
	{
		Type = .Box,
		Size = halfExtents,
		Arc = 360
	};
}

/// A single particle in the system.
struct Particle
{
	public Vector3 Position;
	public Vector3 Velocity;
	public Vector2 Size;
	public Color Color;
	public float Rotation;
	public float RotationSpeed;
	public float Life;
	public float MaxLife;

	// Initial values for curve evaluation
	public Vector3 StartVelocity;
	public Vector2 StartSize;
	public Color StartColor;

	// Texture animation
	public uint16 TextureFrame;
	public uint16 TotalFrames;

	// Per-particle random seed
	public uint32 RandomSeed;

	public bool IsAlive => Life > 0;
	public float LifeRatio => MaxLife > 0 ? Life / MaxLife : 0;
	public float NormalizedAge => MaxLife > 0 ? 1.0f - (Life / MaxLife) : 1;
}

/// GPU-uploadable particle vertex data (52 bytes).
[CRepr]
struct ParticleVertex
{
	public Vector3 Position;       // 12 bytes
	public Vector2 Size;           // 8 bytes
	public Color Color;            // 4 bytes
	public float Rotation;         // 4 bytes
	public Vector2 TexCoordOffset; // 8 bytes
	public Vector2 TexCoordScale;  // 8 bytes
	public Vector2 Velocity2D;     // 8 bytes

	public const uint32 Stride = 52;

	public this(Particle p)
	{
		Position = p.Position;
		Size = p.Size;
		Color = p.Color;
		Rotation = p.Rotation;
		TexCoordOffset = .Zero;
		TexCoordScale = .(1, 1);
		Velocity2D = .Zero;
	}

	public this(Vector3 position, Vector2 size, Color color, float rotation,
				Vector2 texOffset, Vector2 texScale, Vector2 velocity)
	{
		Position = position;
		Size = size;
		Color = color;
		Rotation = rotation;
		TexCoordOffset = texOffset;
		TexCoordScale = texScale;
		Velocity2D = velocity;
	}
}

/// Particle uniform data for shaders.
[CRepr]
struct ParticleUniforms
{
	public uint32 RenderMode;       // 0=Billboard, 1=Stretched, etc.
	public float StretchFactor;
	public float MinStretchLength;
	public uint32 UseTexture;

	public uint32 SoftParticlesEnabled;
	public float SoftParticleDistance;
	public float NearPlane;
	public float FarPlane;

	public const uint32 Size = 32;

	public static Self Default => .()
	{
		RenderMode = 0,
		StretchFactor = 1.0f,
		MinStretchLength = 0.1f,
		UseTexture = 0,
		SoftParticlesEnabled = 0,
		SoftParticleDistance = 0.5f,
		NearPlane = 0.1f,
		FarPlane = 1000.0f
	};
}

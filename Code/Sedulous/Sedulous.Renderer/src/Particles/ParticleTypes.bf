namespace Sedulous.Renderer;

using System;
using Sedulous.Mathematics;

/// A range of float values for randomization.
struct RangeFloat
{
	public float Min;
	public float Max;

	public this(float min, float max)
	{
		Min = min;
		Max = max;
	}

	/// Creates a constant range (min == max).
	public this(float value)
	{
		Min = value;
		Max = value;
	}

	/// Evaluates a random value within the range.
	public float Evaluate(Random random)
	{
		if (Min == Max)
			return Min;
		return Min + (float)random.NextDouble() * (Max - Min);
	}

	/// Evaluates a value at the given t (0-1).
	public float Lerp(float t)
	{
		return Min + t * (Max - Min);
	}

	/// Creates a constant range.
	public static Self Constant(float value) => .(value, value);
}

/// A range of Vector2 values for randomization.
struct RangeVector2
{
	public Vector2 Min;
	public Vector2 Max;

	public this(Vector2 min, Vector2 max)
	{
		Min = min;
		Max = max;
	}

	/// Creates a constant range.
	public this(Vector2 value)
	{
		Min = value;
		Max = value;
	}

	/// Evaluates a random value within the range.
	public Vector2 Evaluate(Random random)
	{
		return .(
			Min.X + (float)random.NextDouble() * (Max.X - Min.X),
			Min.Y + (float)random.NextDouble() * (Max.Y - Min.Y)
		);
	}

	/// Evaluates a value at the given t (0-1).
	public Vector2 Lerp(float t)
	{
		return .(
			Min.X + t * (Max.X - Min.X),
			Min.Y + t * (Max.Y - Min.Y)
		);
	}
}

/// A range of Vector3 values for randomization.
struct RangeVector3
{
	public Vector3 Min;
	public Vector3 Max;

	public this(Vector3 min, Vector3 max)
	{
		Min = min;
		Max = max;
	}

	/// Creates a constant range.
	public this(Vector3 value)
	{
		Min = value;
		Max = value;
	}

	/// Evaluates a random value within the range.
	public Vector3 Evaluate(Random random)
	{
		return .(
			Min.X + (float)random.NextDouble() * (Max.X - Min.X),
			Min.Y + (float)random.NextDouble() * (Max.Y - Min.Y),
			Min.Z + (float)random.NextDouble() * (Max.Z - Min.Z)
		);
	}

	/// Evaluates a value at the given t (0-1).
	public Vector3 Lerp(float t)
	{
		return .(
			Min.X + t * (Max.X - Min.X),
			Min.Y + t * (Max.Y - Min.Y),
			Min.Z + t * (Max.Z - Min.Z)
		);
	}
}

/// A range of Color values for randomization.
struct RangeColor
{
	public Color Min;
	public Color Max;

	public this(Color min, Color max)
	{
		Min = min;
		Max = max;
	}

	/// Creates a constant range.
	public this(Color value)
	{
		Min = value;
		Max = value;
	}

	/// Evaluates a random value within the range.
	public Color Evaluate(Random random)
	{
		float t = (float)random.NextDouble();
		return Min.Interpolate(Max, t);
	}

	/// Evaluates a value at the given t (0-1).
	public Color Lerp(float t)
	{
		return Min.Interpolate(Max, t);
	}
}

/// Particle render mode.
enum ParticleRenderMode
{
	/// Always face camera (default billboard).
	Billboard,
	/// Stretch along velocity direction.
	StretchedBillboard,
	/// Face up (Y-axis aligned).
	HorizontalBillboard,
	/// Face camera but stay vertical.
	VerticalBillboard,
	/// Connected ribbon trail.
	Trail,
	/// Render as mesh (future).
	Mesh
}

/// Particle blend mode.
enum ParticleBlendMode
{
	/// Standard alpha blending.
	AlphaBlend,
	/// Additive (for fire, glow).
	Additive,
	/// Multiply (for shadows).
	Multiply,
	/// Pre-multiplied alpha.
	Premultiplied
}

/// Emission shape type.
enum EmissionShapeType
{
	/// Emit from a single point.
	Point,
	/// Emit from a sphere volume or surface.
	Sphere,
	/// Emit from a hemisphere.
	Hemisphere,
	/// Emit from a cone.
	Cone,
	/// Emit from a box volume or surface.
	Box,
	/// Emit from a circle (2D).
	Circle,
	/// Emit from a line edge.
	Edge,
	/// Emit from a mesh surface (future).
	Mesh
}

/// Emission shape configuration.
struct EmissionShape
{
	/// Shape type.
	public EmissionShapeType Type;
	/// Size/extents (meaning depends on shape type).
	public Vector3 Size;
	/// Cone angle in degrees (for cone emission).
	public float ConeAngle;
	/// Emit from surface only (vs volume).
	public bool EmitFromSurface;
	/// Randomize initial direction.
	public bool RandomizeDirection;
	/// Arc for partial shapes (0-360 degrees).
	public float Arc;

	/// Default point emission.
	public static Self Point => .() { Type = .Point, Size = .Zero, Arc = 360 };

	/// Creates a sphere emission shape.
	public static Self Sphere(float radius, bool surface = false) => .()
	{
		Type = .Sphere,
		Size = .(radius, radius, radius),
		EmitFromSurface = surface,
		Arc = 360
	};

	/// Creates a cone emission shape.
	public static Self Cone(float angle, float radius = 0) => .()
	{
		Type = .Cone,
		ConeAngle = angle,
		Size = .(radius, 0, 0),
		Arc = 360
	};

	/// Creates a box emission shape.
	public static Self Box(Vector3 halfExtents, bool surface = false) => .()
	{
		Type = .Box,
		Size = halfExtents,
		EmitFromSurface = surface,
		Arc = 360
	};

	/// Creates a circle emission shape.
	public static Self Circle(float radius) => .()
	{
		Type = .Circle,
		Size = .(radius, 0, radius),
		Arc = 360
	};
}

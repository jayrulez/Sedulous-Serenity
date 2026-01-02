using System;

namespace Sedulous.Mathematics;

/// A two-dimensional vector.
[CRepr]
struct Vector2 : IEquatable<Vector2>, IHashable
{
	/// The X component.
	public float X;

	/// The Y component.
	public float Y;

	/// Creates a vector with both components set to the same value.
	public this(float value)
	{
		X = value;
		Y = value;
	}

	/// Creates a vector with the specified components.
	public this(float x, float y)
	{
		X = x;
		Y = y;
	}

	// ---- Static Properties ----

	/// A vector with all components set to zero.
	public static Vector2 Zero => .(0, 0);

	/// A vector with all components set to one.
	public static Vector2 One => .(1, 1);

	/// The unit X vector (1, 0).
	public static Vector2 UnitX => .(1, 0);

	/// The unit Y vector (0, 1).
	public static Vector2 UnitY => .(0, 1);

	// ---- Properties ----

	/// Gets the length (magnitude) of the vector.
	public float Length => Math.Sqrt(X * X + Y * Y);

	/// Gets the squared length of the vector.
	public float LengthSquared => X * X + Y * Y;

	/// Returns a normalized copy of this vector.
	public Vector2 Normalized
	{
		get
		{
			let len = Length;
			if (len > MathUtil.Epsilon)
				return .(X / len, Y / len);
			return Zero;
		}
	}

	// ---- Operators ----

	public static Vector2 operator +(Vector2 a, Vector2 b) => .(a.X + b.X, a.Y + b.Y);
	public static Vector2 operator -(Vector2 a, Vector2 b) => .(a.X - b.X, a.Y - b.Y);
	public static Vector2 operator *(Vector2 a, Vector2 b) => .(a.X * b.X, a.Y * b.Y);
	public static Vector2 operator /(Vector2 a, Vector2 b) => .(a.X / b.X, a.Y / b.Y);
	public static Vector2 operator *(Vector2 v, float s) => .(v.X * s, v.Y * s);
	public static Vector2 operator *(float s, Vector2 v) => .(v.X * s, v.Y * s);
	public static Vector2 operator /(Vector2 v, float s) => .(v.X / s, v.Y / s);
	public static Vector2 operator -(Vector2 v) => .(-v.X, -v.Y);

	public static bool operator ==(Vector2 a, Vector2 b) => a.X == b.X && a.Y == b.Y;
	public static bool operator !=(Vector2 a, Vector2 b) => !(a == b);

	// ---- Methods ----

	/// Normalizes this vector in place.
	public void Normalize() mut
	{
		let len = Length;
		if (len > MathUtil.Epsilon)
		{
			X /= len;
			Y /= len;
		}
	}

	/// Calculates the dot product of two vectors.
	public static float Dot(Vector2 a, Vector2 b)
	{
		return a.X * b.X + a.Y * b.Y;
	}

	/// Calculates the distance between two vectors.
	public static float Distance(Vector2 a, Vector2 b)
	{
		return (a - b).Length;
	}

	/// Calculates the squared distance between two vectors.
	public static float DistanceSquared(Vector2 a, Vector2 b)
	{
		return (a - b).LengthSquared;
	}

	/// Linearly interpolates between two vectors.
	public static Vector2 Lerp(Vector2 a, Vector2 b, float t)
	{
		return .(
			MathUtil.Lerp(a.X, b.X, t),
			MathUtil.Lerp(a.Y, b.Y, t)
		);
	}

	/// Returns a vector with the minimum components of two vectors.
	public static Vector2 Min(Vector2 a, Vector2 b)
	{
		return .(
			MathUtil.Min(a.X, b.X),
			MathUtil.Min(a.Y, b.Y)
		);
	}

	/// Returns a vector with the maximum components of two vectors.
	public static Vector2 Max(Vector2 a, Vector2 b)
	{
		return .(
			MathUtil.Max(a.X, b.X),
			MathUtil.Max(a.Y, b.Y)
		);
	}

	/// Reflects a vector off a surface with the given normal.
	public static Vector2 Reflect(Vector2 vector, Vector2 normal)
	{
		return vector - 2.0f * Dot(vector, normal) * normal;
	}

	// ---- IEquatable / IHashable ----

	public bool Equals(Vector2 other)
	{
		return this == other;
	}

	public int GetHashCode()
	{
		return (int)(X.GetHashCode() * 397) ^ Y.GetHashCode();
	}

	public override void ToString(String strBuffer)
	{
		strBuffer.AppendF("({}, {})", X, Y);
	}
}

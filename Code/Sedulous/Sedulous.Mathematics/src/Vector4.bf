using System;

namespace Sedulous.Mathematics;

/// A four-dimensional vector.
[CRepr]
struct Vector4 : IEquatable<Vector4>, IHashable
{
	/// The X component.
	public float X;

	/// The Y component.
	public float Y;

	/// The Z component.
	public float Z;

	/// The W component.
	public float W;

	/// Creates a vector with all components set to the same value.
	public this(float value)
	{
		X = value;
		Y = value;
		Z = value;
		W = value;
	}

	/// Creates a vector with the specified components.
	public this(float x, float y, float z, float w)
	{
		X = x;
		Y = y;
		Z = z;
		W = w;
	}

	/// Creates a vector from a Vector2 and Z, W components.
	public this(Vector2 xy, float z, float w)
	{
		X = xy.X;
		Y = xy.Y;
		Z = z;
		W = w;
	}

	/// Creates a vector from a Vector3 and a W component.
	public this(Vector3 xyz, float w)
	{
		X = xyz.X;
		Y = xyz.Y;
		Z = xyz.Z;
		W = w;
	}

	// ---- Static Properties ----

	/// A vector with all components set to zero.
	public static Vector4 Zero => .(0, 0, 0, 0);

	/// A vector with all components set to one.
	public static Vector4 One => .(1, 1, 1, 1);

	/// The unit X vector (1, 0, 0, 0).
	public static Vector4 UnitX => .(1, 0, 0, 0);

	/// The unit Y vector (0, 1, 0, 0).
	public static Vector4 UnitY => .(0, 1, 0, 0);

	/// The unit Z vector (0, 0, 1, 0).
	public static Vector4 UnitZ => .(0, 0, 1, 0);

	/// The unit W vector (0, 0, 0, 1).
	public static Vector4 UnitW => .(0, 0, 0, 1);

	// ---- Properties ----

	/// Gets the length (magnitude) of the vector.
	public float Length => Math.Sqrt(X * X + Y * Y + Z * Z + W * W);

	/// Gets the squared length of the vector.
	public float LengthSquared => X * X + Y * Y + Z * Z + W * W;

	/// Returns a normalized copy of this vector.
	public Vector4 Normalized
	{
		get
		{
			let len = Length;
			if (len > MathUtil.Epsilon)
				return .(X / len, Y / len, Z / len, W / len);
			return Zero;
		}
	}

	/// Gets the XY components as a Vector2.
	public Vector2 XY => .(X, Y);

	/// Gets the XYZ components as a Vector3.
	public Vector3 XYZ => .(X, Y, Z);

	// ---- Operators ----

	public static Vector4 operator +(Vector4 a, Vector4 b) => .(a.X + b.X, a.Y + b.Y, a.Z + b.Z, a.W + b.W);
	public static Vector4 operator -(Vector4 a, Vector4 b) => .(a.X - b.X, a.Y - b.Y, a.Z - b.Z, a.W - b.W);
	public static Vector4 operator *(Vector4 a, Vector4 b) => .(a.X * b.X, a.Y * b.Y, a.Z * b.Z, a.W * b.W);
	public static Vector4 operator /(Vector4 a, Vector4 b) => .(a.X / b.X, a.Y / b.Y, a.Z / b.Z, a.W / b.W);
	public static Vector4 operator *(Vector4 v, float s) => .(v.X * s, v.Y * s, v.Z * s, v.W * s);
	public static Vector4 operator *(float s, Vector4 v) => .(v.X * s, v.Y * s, v.Z * s, v.W * s);
	public static Vector4 operator /(Vector4 v, float s) => .(v.X / s, v.Y / s, v.Z / s, v.W / s);
	public static Vector4 operator -(Vector4 v) => .(-v.X, -v.Y, -v.Z, -v.W);

	public static bool operator ==(Vector4 a, Vector4 b) => a.X == b.X && a.Y == b.Y && a.Z == b.Z && a.W == b.W;
	public static bool operator !=(Vector4 a, Vector4 b) => !(a == b);

	// ---- Methods ----

	/// Normalizes this vector in place.
	public void Normalize() mut
	{
		let len = Length;
		if (len > MathUtil.Epsilon)
		{
			X /= len;
			Y /= len;
			Z /= len;
			W /= len;
		}
	}

	/// Calculates the dot product of two vectors.
	public static float Dot(Vector4 a, Vector4 b)
	{
		return a.X * b.X + a.Y * b.Y + a.Z * b.Z + a.W * b.W;
	}

	/// Calculates the distance between two vectors.
	public static float Distance(Vector4 a, Vector4 b)
	{
		return (a - b).Length;
	}

	/// Calculates the squared distance between two vectors.
	public static float DistanceSquared(Vector4 a, Vector4 b)
	{
		return (a - b).LengthSquared;
	}

	/// Linearly interpolates between two vectors.
	public static Vector4 Lerp(Vector4 a, Vector4 b, float t)
	{
		return .(
			MathUtil.Lerp(a.X, b.X, t),
			MathUtil.Lerp(a.Y, b.Y, t),
			MathUtil.Lerp(a.Z, b.Z, t),
			MathUtil.Lerp(a.W, b.W, t)
		);
	}

	/// Returns a vector with the minimum components of two vectors.
	public static Vector4 Min(Vector4 a, Vector4 b)
	{
		return .(
			MathUtil.Min(a.X, b.X),
			MathUtil.Min(a.Y, b.Y),
			MathUtil.Min(a.Z, b.Z),
			MathUtil.Min(a.W, b.W)
		);
	}

	/// Returns a vector with the maximum components of two vectors.
	public static Vector4 Max(Vector4 a, Vector4 b)
	{
		return .(
			MathUtil.Max(a.X, b.X),
			MathUtil.Max(a.Y, b.Y),
			MathUtil.Max(a.Z, b.Z),
			MathUtil.Max(a.W, b.W)
		);
	}

	// ---- IEquatable / IHashable ----

	public bool Equals(Vector4 other)
	{
		return this == other;
	}

	public int GetHashCode()
	{
		var hash = X.GetHashCode();
		hash = (hash * 397) ^ Y.GetHashCode();
		hash = (hash * 397) ^ Z.GetHashCode();
		hash = (hash * 397) ^ W.GetHashCode();
		return hash;
	}

	public override void ToString(String strBuffer)
	{
		strBuffer.AppendF("({}, {}, {}, {})", X, Y, Z, W);
	}
}

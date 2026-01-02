using System;

namespace Sedulous.Mathematics;

/// A three-dimensional vector.
[CRepr]
struct Vector3 : IEquatable<Vector3>, IHashable
{
	/// The X component.
	public float X;

	/// The Y component.
	public float Y;

	/// The Z component.
	public float Z;

	/// Creates a vector with all components set to the same value.
	public this(float value)
	{
		X = value;
		Y = value;
		Z = value;
	}

	/// Creates a vector with the specified components.
	public this(float x, float y, float z)
	{
		X = x;
		Y = y;
		Z = z;
	}

	/// Creates a vector from a Vector2 and a Z component.
	public this(Vector2 xy, float z)
	{
		X = xy.X;
		Y = xy.Y;
		Z = z;
	}

	// ---- Static Properties ----

	/// A vector with all components set to zero.
	public static Vector3 Zero => .(0, 0, 0);

	/// A vector with all components set to one.
	public static Vector3 One => .(1, 1, 1);

	/// The unit X vector (1, 0, 0).
	public static Vector3 UnitX => .(1, 0, 0);

	/// The unit Y vector (0, 1, 0).
	public static Vector3 UnitY => .(0, 1, 0);

	/// The unit Z vector (0, 0, 1).
	public static Vector3 UnitZ => .(0, 0, 1);

	/// The up vector (0, 1, 0).
	public static Vector3 Up => .(0, 1, 0);

	/// The down vector (0, -1, 0).
	public static Vector3 Down => .(0, -1, 0);

	/// The right vector (1, 0, 0).
	public static Vector3 Right => .(1, 0, 0);

	/// The left vector (-1, 0, 0).
	public static Vector3 Left => .(-1, 0, 0);

	/// The forward vector (0, 0, -1).
	public static Vector3 Forward => .(0, 0, -1);

	/// The back vector (0, 0, 1).
	public static Vector3 Back => .(0, 0, 1);

	// ---- Properties ----

	/// Gets the length (magnitude) of the vector.
	public float Length => Math.Sqrt(X * X + Y * Y + Z * Z);

	/// Gets the squared length of the vector.
	public float LengthSquared => X * X + Y * Y + Z * Z;

	/// Returns a normalized copy of this vector.
	public Vector3 Normalized
	{
		get
		{
			let len = Length;
			if (len > MathUtil.Epsilon)
				return .(X / len, Y / len, Z / len);
			return Zero;
		}
	}

	/// Gets the XY components as a Vector2.
	public Vector2 XY => .(X, Y);

	// ---- Operators ----

	public static Vector3 operator +(Vector3 a, Vector3 b) => .(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
	public static Vector3 operator -(Vector3 a, Vector3 b) => .(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
	public static Vector3 operator *(Vector3 a, Vector3 b) => .(a.X * b.X, a.Y * b.Y, a.Z * b.Z);
	public static Vector3 operator /(Vector3 a, Vector3 b) => .(a.X / b.X, a.Y / b.Y, a.Z / b.Z);
	public static Vector3 operator *(Vector3 v, float s) => .(v.X * s, v.Y * s, v.Z * s);
	public static Vector3 operator *(float s, Vector3 v) => .(v.X * s, v.Y * s, v.Z * s);
	public static Vector3 operator /(Vector3 v, float s) => .(v.X / s, v.Y / s, v.Z / s);
	public static Vector3 operator -(Vector3 v) => .(-v.X, -v.Y, -v.Z);

	public static bool operator ==(Vector3 a, Vector3 b) => a.X == b.X && a.Y == b.Y && a.Z == b.Z;
	public static bool operator !=(Vector3 a, Vector3 b) => !(a == b);

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
		}
	}

	/// Calculates the dot product of two vectors.
	public static float Dot(Vector3 a, Vector3 b)
	{
		return a.X * b.X + a.Y * b.Y + a.Z * b.Z;
	}

	/// Calculates the cross product of two vectors.
	public static Vector3 Cross(Vector3 a, Vector3 b)
	{
		return .(
			a.Y * b.Z - a.Z * b.Y,
			a.Z * b.X - a.X * b.Z,
			a.X * b.Y - a.Y * b.X
		);
	}

	/// Calculates the distance between two vectors.
	public static float Distance(Vector3 a, Vector3 b)
	{
		return (a - b).Length;
	}

	/// Calculates the squared distance between two vectors.
	public static float DistanceSquared(Vector3 a, Vector3 b)
	{
		return (a - b).LengthSquared;
	}

	/// Linearly interpolates between two vectors.
	public static Vector3 Lerp(Vector3 a, Vector3 b, float t)
	{
		return .(
			MathUtil.Lerp(a.X, b.X, t),
			MathUtil.Lerp(a.Y, b.Y, t),
			MathUtil.Lerp(a.Z, b.Z, t)
		);
	}

	/// Returns a vector with the minimum components of two vectors.
	public static Vector3 Min(Vector3 a, Vector3 b)
	{
		return .(
			MathUtil.Min(a.X, b.X),
			MathUtil.Min(a.Y, b.Y),
			MathUtil.Min(a.Z, b.Z)
		);
	}

	/// Returns a vector with the maximum components of two vectors.
	public static Vector3 Max(Vector3 a, Vector3 b)
	{
		return .(
			MathUtil.Max(a.X, b.X),
			MathUtil.Max(a.Y, b.Y),
			MathUtil.Max(a.Z, b.Z)
		);
	}

	/// Reflects a vector off a surface with the given normal.
	public static Vector3 Reflect(Vector3 vector, Vector3 normal)
	{
		return vector - 2.0f * Dot(vector, normal) * normal;
	}

	/// Projects a vector onto another vector.
	public static Vector3 Project(Vector3 vector, Vector3 onto)
	{
		let dot = Dot(onto, onto);
		if (dot < MathUtil.Epsilon)
			return Zero;
		return onto * (Dot(vector, onto) / dot);
	}

	/// Returns a normalized copy of the vector.
	public static Vector3 Normalize(Vector3 v)
	{
		return v.Normalized;
	}

	/// Transforms this vector by a 4x4 matrix (as a position, w=1).
	public Vector3 Transform(Matrix4x4 matrix)
	{
		return .(
			X * matrix.M11 + Y * matrix.M21 + Z * matrix.M31 + matrix.M41,
			X * matrix.M12 + Y * matrix.M22 + Z * matrix.M32 + matrix.M42,
			X * matrix.M13 + Y * matrix.M23 + Z * matrix.M33 + matrix.M43
		);
	}

	/// Transforms a direction by a 4x4 matrix (ignores translation, w=0).
	public Vector3 TransformDirection(Matrix4x4 matrix)
	{
		return .(
			X * matrix.M11 + Y * matrix.M21 + Z * matrix.M31,
			X * matrix.M12 + Y * matrix.M22 + Z * matrix.M32,
			X * matrix.M13 + Y * matrix.M23 + Z * matrix.M33
		);
	}

	// ---- IEquatable / IHashable ----

	public bool Equals(Vector3 other)
	{
		return this == other;
	}

	public int GetHashCode()
	{
		var hash = X.GetHashCode();
		hash = (hash * 397) ^ Y.GetHashCode();
		hash = (hash * 397) ^ Z.GetHashCode();
		return hash;
	}

	public override void ToString(String strBuffer)
	{
		strBuffer.AppendF("({}, {}, {})", X, Y, Z);
	}
}

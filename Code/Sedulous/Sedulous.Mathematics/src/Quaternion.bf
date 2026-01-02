using System;

namespace Sedulous.Mathematics;

/// Represents a rotation as a quaternion (x, y, z, w).
[CRepr]
struct Quaternion : IEquatable<Quaternion>, IHashable
{
	/// The X component.
	public float X;

	/// The Y component.
	public float Y;

	/// The Z component.
	public float Z;

	/// The W component.
	public float W;

	/// Identity quaternion (no rotation).
	public static Quaternion Identity => .(0, 0, 0, 1);

	/// Creates a quaternion with the specified components.
	public this(float x, float y, float z, float w)
	{
		X = x;
		Y = y;
		Z = z;
		W = w;
	}

	/// Creates a quaternion from a vector and scalar.
	public this(Vector3 vector, float scalar)
	{
		X = vector.X;
		Y = vector.Y;
		Z = vector.Z;
		W = scalar;
	}

	// ---- Operators ----

	public static Quaternion operator +(Quaternion a, Quaternion b)
	{
		return .(a.X + b.X, a.Y + b.Y, a.Z + b.Z, a.W + b.W);
	}

	public static Quaternion operator -(Quaternion a, Quaternion b)
	{
		return .(a.X - b.X, a.Y - b.Y, a.Z - b.Z, a.W - b.W);
	}

	public static Quaternion operator *(Quaternion a, Quaternion b)
	{
		var cx = a.Y * b.Z - a.Z * b.Y;
		var cy = a.Z * b.X - a.X * b.Z;
		var cz = a.X * b.Y - a.Y * b.X;
		var dot = a.X * b.X + a.Y * b.Y + a.Z * b.Z;

		return .(
			a.X * b.W + b.X * a.W + cx,
			a.Y * b.W + b.Y * a.W + cy,
			a.Z * b.W + b.Z * a.W + cz,
			a.W * b.W - dot
		);
	}

	public static Quaternion operator *(Quaternion q, float s)
	{
		return .(q.X * s, q.Y * s, q.Z * s, q.W * s);
	}

	public static Quaternion operator *(float s, Quaternion q)
	{
		return .(q.X * s, q.Y * s, q.Z * s, q.W * s);
	}

	public static Quaternion operator -(Quaternion q)
	{
		return .(-q.X, -q.Y, -q.Z, -q.W);
	}

	public static bool operator ==(Quaternion a, Quaternion b)
	{
		return a.X == b.X && a.Y == b.Y && a.Z == b.Z && a.W == b.W;
	}

	public static bool operator !=(Quaternion a, Quaternion b)
	{
		return !(a == b);
	}

	// ---- Static Methods ----

	/// Creates a quaternion from an axis and angle (in radians).
	public static Quaternion CreateFromAxisAngle(Vector3 axis, float angle)
	{
		float halfAngle = angle * 0.5f;
		float sin = Math.Sin(halfAngle);
		float cos = Math.Cos(halfAngle);

		return .(axis.X * sin, axis.Y * sin, axis.Z * sin, cos);
	}

	/// Creates a quaternion from yaw, pitch, and roll (in radians).
	public static Quaternion CreateFromYawPitchRoll(float yaw, float pitch, float roll)
	{
		float halfRoll = roll * 0.5f;
		float sr = Math.Sin(halfRoll);
		float cr = Math.Cos(halfRoll);

		float halfPitch = pitch * 0.5f;
		float sp = Math.Sin(halfPitch);
		float cp = Math.Cos(halfPitch);

		float halfYaw = yaw * 0.5f;
		float sy = Math.Sin(halfYaw);
		float cy = Math.Cos(halfYaw);

		return .(
			cy * sp * cr + sy * cp * sr,
			sy * cp * cr - cy * sp * sr,
			cy * cp * sr - sy * sp * cr,
			cy * cp * cr + sy * sp * sr
		);
	}

	/// Calculates the dot product of two quaternions.
	public static float Dot(Quaternion a, Quaternion b)
	{
		return a.X * b.X + a.Y * b.Y + a.Z * b.Z + a.W * b.W;
	}

	/// Normalizes a quaternion.
	public static Quaternion Normalize(Quaternion q)
	{
		float lengthSquared = q.X * q.X + q.Y * q.Y + q.Z * q.Z + q.W * q.W;
		float invLength = 1.0f / Math.Sqrt(lengthSquared);
		return .(q.X * invLength, q.Y * invLength, q.Z * invLength, q.W * invLength);
	}

	/// Returns the conjugate of a quaternion.
	public static Quaternion Conjugate(Quaternion q)
	{
		return .(-q.X, -q.Y, -q.Z, q.W);
	}

	/// Returns the inverse of a quaternion.
	public static Quaternion Inverse(Quaternion q)
	{
		float lengthSquared = q.X * q.X + q.Y * q.Y + q.Z * q.Z + q.W * q.W;
		float invLengthSquared = 1.0f / lengthSquared;
		return .(-q.X * invLengthSquared, -q.Y * invLengthSquared, -q.Z * invLengthSquared, q.W * invLengthSquared);
	}

	/// Linearly interpolates between two quaternions.
	public static Quaternion Lerp(Quaternion source, Quaternion target, float amount)
	{
		float t = amount;
		float t1 = 1.0f - amount;

		float dot = Dot(source, target);

		Quaternion result;
		if (dot > 0)
		{
			result = .(
				t1 * source.X + t * target.X,
				t1 * source.Y + t * target.Y,
				t1 * source.Z + t * target.Z,
				t1 * source.W + t * target.W
			);
		}
		else
		{
			result = .(
				t1 * source.X - t * target.X,
				t1 * source.Y - t * target.Y,
				t1 * source.Z - t * target.Z,
				t1 * source.W - t * target.W
			);
		}

		return Normalize(result);
	}

	/// Spherically interpolates between two quaternions.
	public static Quaternion Slerp(Quaternion source, Quaternion target, float amount)
	{
		bool flip = false;
		float cosOmega = Dot(source, target);

		if (cosOmega < 0)
		{
			flip = true;
			cosOmega = -cosOmega;
		}

		float s1, s2;

		if (cosOmega > 0.9999f)
		{
			// Very close, use linear interpolation
			s1 = 1.0f - amount;
			s2 = flip ? -amount : amount;
		}
		else
		{
			float omega = Math.Acos(cosOmega);
			float invSinOmega = 1.0f / Math.Sin(omega);

			s1 = Math.Sin((1.0f - amount) * omega) * invSinOmega;
			s2 = flip ? -Math.Sin(amount * omega) * invSinOmega : Math.Sin(amount * omega) * invSinOmega;
		}

		return .(
			s1 * source.X + s2 * target.X,
			s1 * source.Y + s2 * target.Y,
			s1 * source.Z + s2 * target.Z,
			s1 * source.W + s2 * target.W
		);
	}

	// ---- Instance Methods ----

	/// Gets the length of the quaternion.
	public float Length => Math.Sqrt(X * X + Y * Y + Z * Z + W * W);

	/// Gets the squared length of the quaternion.
	public float LengthSquared => X * X + Y * Y + Z * Z + W * W;

	/// Returns a normalized copy of this quaternion.
	public Quaternion Normalized => Normalize(this);

	/// Rotates a vector by this quaternion.
	public Vector3 Rotate(Vector3 v)
	{
		// q * v * q^-1
		let qv = Quaternion(v.X, v.Y, v.Z, 0);
		let qConj = Conjugate(this);
		let result = this * qv * qConj;
		return Vector3(result.X, result.Y, result.Z);
	}

	// ---- IEquatable / IHashable ----

	public bool Equals(Quaternion other)
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

	public override void ToString(String str)
	{
		str.AppendF("({}, {}, {}, {})", X, Y, Z, W);
	}
}
